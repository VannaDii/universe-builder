import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/proposal_state.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as p;

CanonicalValue reservation(ProposalId id) =>
    CanonicalObject([MapEntry('proposal_id', CanonicalString(id.value))]);

StoredProposal adopt(RecordVersion source, {bool update = false}) => p.prepare(
  request: p.create(
    operations: [
      AdoptRecordVersionOperation(
        source: source,
        expectedVersion: update ? source.recordVersionId : null,
      ),
    ],
  ),
  base: update ? [source] : [],
);

Future<void> check(
  StoredProposal stored, {
  CanonicalValue? reserved,
  bool existing = false,
  RecordVersion? historical,
}) => checkProposalReservations(
  stored: stored,
  readWorkflow: (_) => reserved,
  identityExists: (_) => existing,
  readVersion: (_) =>
      historical ?? (throw StateError('Unexpected version read')),
);

void main() {
  test('fresh creation and same-proposal reservations pass, other owners and canon reject', () async {
    final stored = p.prepare(), other = p.prepare();
    await check(stored);
    await check(stored, reserved: reservation(stored.proposal.proposalId));
    for (final reserved in [
      reservation(other.proposal.proposalId),
      const CanonicalNull(),
      CanonicalObject([]),
      CanonicalString('invalid owner'),
    ]) {
      await expectLater(
        check(stored, reserved: reserved),
        f.fails('already reserved', field: 'client_ref'),
      );
    }
    await expectLater(
      check(stored, existing: true),
      f.fails('already reserved', field: 'client_ref'),
    );
  });

  test(
    'exact historical adoption bypasses both canon and a competing reservation',
    () async {
      final source = f.row(10, f.entity()),
          stored = adopt(f.row(10, f.entity()));
      await checkProposalReservations(
        stored: stored,
        readWorkflow: (_) => reservation(p.prepare().proposal.proposalId),
        identityExists: (_) =>
            throw StateError('Historical adoption must short circuit'),
        readVersion: (id) {
          expect(id, source.recordVersionId);
          return source;
        },
      );
      await verifyImmutableAdoptions(
        stored: stored,
        readVersion: (_) => source,
      );
    },
  );

  test('immutable adoption compares the whole version and propagates missing history', () async {
    final source = f.row(10, f.entity()), stored = adopt(f.row(10, f.entity()));
    final altered = RecordVersion.build(
      recordVersionId: source.recordVersionId,
      identity: source.identity,
      payload: f.entity(classification: f.id(20)),
    );
    await expectLater(
      check(stored, existing: true, historical: altered),
      f.fails('already reserved', field: 'client_ref'),
    );
    // Reservation admission alone is insufficient when neither identity nor
    // reservation exists. Validation independently rejects the altered source.
    await check(stored, historical: altered);
    await expectLater(
      verifyImmutableAdoptions(stored: stored, readVersion: (_) => altered),
      f.fails('existing immutable version', field: 'adoption'),
    );
    const missing = NotFoundOrNotAccessibleError(message: 'resource');
    await expectLater(
      verifyImmutableAdoptions(
        stored: stored,
        readVersion: (_) => throw missing,
      ),
      throwsA(same(missing)),
    );
    await expectLater(
      checkProposalReservations(
        stored: stored,
        readWorkflow: (_) => null,
        identityExists: (_) => true,
        readVersion: (_) => throw missing,
      ),
      throwsA(same(missing)),
    );
  });

  test(
    'expected-version updates never acquire or check a reservation',
    () async {
      final stored = adopt(f.row(10, f.entity()), update: true);
      await checkProposalReservations(
        stored: stored,
        readWorkflow: (_) => throw StateError('Unexpected reservation read'),
        identityExists: (_) => throw StateError('Unexpected identity read'),
        readVersion: (_) => throw StateError('Unexpected history read'),
      );
      expect(
        await proposalReservationEntries(
          stored: stored,
          readWorkflow: (_) => throw StateError('Unexpected reservation read'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'adoption equality includes version ID, identity and declared digest',
    () async {
      final source = f.row(10, f.entity()),
          stored = adopt(f.row(10, f.entity()));
      for (final historical in [
        RecordVersion(
          recordVersionId: f.ver(11),
          identity: source.identity,
          payload: source.payload,
          payloadDigest: source.payloadDigest,
        ),
        RecordVersion(
          recordVersionId: source.recordVersionId,
          identity: f.row(11, f.entity()).identity,
          payload: source.payload,
          payloadDigest: source.payloadDigest,
        ),
        RecordVersion(
          recordVersionId: source.recordVersionId,
          identity: source.identity,
          payload: source.payload,
          payloadDigest: '0' * 64,
        ),
      ]) {
        await expectLater(
          verifyImmutableAdoptions(
            stored: stored,
            readVersion: (_) => historical,
          ),
          f.fails('existing immutable version', field: 'adoption'),
        );
        await expectLater(
          check(stored, existing: true, historical: historical),
          f.fails('already reserved', field: 'client_ref'),
        );
      }
    },
  );

  test('all adopted versions are checked, while reservation exemption uses first matching adoption', () async {
    final source = f.row(10, f.entity());
    final altered = RecordVersion.build(
      recordVersionId: source.recordVersionId,
      identity: source.identity,
      payload: f.entity(classification: f.id(20)),
    );
    final initial = adopt(source);
    StoredProposal withOperations(List<DomainOperation> operations) =>
        StoredProposal(
          proposal: Proposal.fromWire(
            CanonicalObject([
              for (final field in initial.proposal.toWire().fields)
                field.key == 'operations'
                    ? MapEntry(
                        'operations',
                        CanonicalArray(operations.map((o) => o.toWire())),
                      )
                    : field,
            ]),
          ),
          owner: initial.owner,
          authorOrigin: initial.authorOrigin,
          changes: initial.changes,
          footprint: initial.footprint,
        );
    final exactFirst = withOperations([
      AdoptRecordVersionOperation(source: source),
      AdoptRecordVersionOperation(source: altered),
    ]);
    await check(exactFirst, existing: true, historical: source);
    await expectLater(
      verifyImmutableAdoptions(stored: exactFirst, readVersion: (_) => source),
      f.fails('existing immutable version', field: 'adoption'),
    );
    final alteredFirst = withOperations([
      AdoptRecordVersionOperation(source: altered),
      AdoptRecordVersionOperation(source: source),
    ]);
    await expectLater(
      check(alteredFirst, existing: true, historical: source),
      f.fails('already reserved', field: 'client_ref'),
    );
  });

  test(
    'new reservation entries retain existing ownership even on withdrawal',
    () async {
      final stored = p.prepare();
      final key = proposalReservationKey(stored.changes.single.recordId);
      final entries = await proposalReservationEntries(
        stored: stored,
        readWorkflow: (_) => null,
      );
      expect(entries.single.key, key);
      expect(
        entries.single.value.toText(),
        reservation(stored.proposal.proposalId).toText(),
      );
      expect(() => entries.clear(), throwsUnsupportedError);
      final withdrawn = p.prepare(
        request: p.transition(stored, withdraw: true),
        previous: stored,
      );
      expect(
        await proposalReservationEntries(
          stored: withdrawn,
          readWorkflow: (_) => entries.single.value,
        ),
        isEmpty,
      );
      expect(
        await proposalReservationEntries(
          stored: adopt(f.row(10, f.entity())),
          readWorkflow: (_) => reservation(stored.proposal.proposalId),
        ),
        isEmpty,
      );
    },
  );
}
