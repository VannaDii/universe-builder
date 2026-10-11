import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

final frame = Frame(
  universe: UniverseId.parse('unv_000000000000000000000001'),
  continuity: ContinuityId.parse('cont_000000000000000000000001'),
  revision: RevisionId.parse('rev_000000000000000000000001'),
  context: RecordRef(record: RecordId.parse('rec_000000000000000000000001')),
  time: const TimelessFrameTime(),
  perspective: const AuthorPerspective(),
);
final proposalId = ProposalId.parse('prp_000000000000000000000001');
final operationId = OperationId.parse('op_000000000000000000000001');
final max = BigInt.parse('18446744073709551615');
Proposal sample({
  Iterable<DomainOperation> operations = const [],
  Iterable<CompiledChange> changes = const [],
}) => Proposal(
  baseFrame: frame,
  proposalId: proposalId,
  version: max,
  digest: 'supplied digest',
  submission: Submission.submitted,
  operations: operations,
  compiledChanges: changes,
  rationale: 'authored proposal',
  canonical: false,
  operationId: operationId,
  withdrawn: false,
);

void main() {
  test(
    'proposal keeps pinned frame and exact u64 version through VM and web',
    () {
      final p = Proposal.fromWire(sample().toWire());
      expect(p.version, max);
      expect(p.baseFrame, frame);
      expect(p.digest, 'supplied digest');
      expect(p.canonical, isFalse);
      expect(p.submission, Submission.submitted);
      expect(p.toWire().toText(), contains('"world_scope":null'));
      expect(p.toWire().toText(), isNot(contains('compiled_changes')));
      expect(p.toWire().toText(), isNot(contains('approval')));
    },
  );
  test(
    'proposal versions reject rounded, negative and overflowing numbers',
    () {
      final p = ProposalRef(
        proposalId: proposalId,
        version: max,
        digest: 'exact',
      );
      for (final digits in ['18446744073709551616', '-1', '1.0', '1e2']) {
        expect(
          () => ProposalRef.fromWire(
            CanonicalObject([
              ...p.toWire().fields.where((e) => e.key != 'version'),
              MapEntry('version', CanonicalNumber(digits)),
            ]),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => ProposalRef(
          proposalId: proposalId,
          version: -BigInt.one,
          digest: 'exact',
        ),
        throwsFormatException,
      );
      expect(ProposalRef.fromWire(p.toWire()).version, max);
    },
  );
  test('authored operations and compiled tombstones remain separate immutable lists', () {
    final authored = <DomainOperation>[
      CreateWorldOperation(
        clientRef: 'new',
        record: WorldRecord(selector: 'World'),
      ),
    ];
    final changes = [
      CompiledChange(
        recordId: frame.context.record,
        expected: RecordVersionId.parse('ver_000000000000000000000001'),
      ),
    ];
    final p = sample(operations: authored, changes: changes);
    authored.clear();
    changes.clear();
    final back = Proposal.fromWire(p.toWire());
    expect(back.operations.single, isA<CreateWorldOperation>());
    expect(back.compiledChanges.single.next, isNull);
    expect(back.compiledChanges.single.expected, isNotNull);
    expect(() => back.operations.clear(), throwsUnsupportedError);
    expect(() => back.compiledChanges.clear(), throwsUnsupportedError);
  });
  test(
    'compiled change preserves supplied version digest without certifying it',
    () {
      final record = RecordVersion(
        recordVersionId: RecordVersionId.parse('ver_000000000000000000000001'),
        identity: RecordIdentity(
          universeId: frame.universe,
          recordId: frame.context.record,
          recordKind: RecordKind.world,
        ),
        payload: WorldRecord(selector: 'World'),
        payloadDigest: 'uncertified',
      );
      final c = CompiledChange.fromWire(
        CompiledChange(
          recordId: record.identity.recordId,
          next: record,
        ).toWire(),
      );
      expect(c.next!.payloadDigest, 'uncertified');
      expect(c.next!.verifiesDigest, isFalse);
      expect(c.expected, isNull);
    },
  );
  test('empty default expansion differs from an invalid null expansion', () {
    final p = sample();
    expect(Proposal.fromWire(p.toWire()).compiledChanges, isEmpty);
    expect(
      () => Proposal.fromWire(
        CanonicalObject([
          ...p.toWire().fields,
          const MapEntry('compiled_changes', CanonicalNull()),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => Proposal.fromWire(
        CanonicalObject(p.toWire().fields.where((e) => e.key != 'operations')),
      ),
      throwsFormatException,
    );
  });
  test('impact coverage retains restrictions and does not select a world', () {
    for (final c in Coverage.values) {
      final result = Impact.fromWire(
        Impact(
          records: [frame.context.record, frame.context.record],
          coverage: c,
          worldIds: [],
        ).toWire(),
      );
      expect(result.coverage, c);
      expect(result.records, hasLength(2));
      expect(result.worldIds, isEmpty);
      expect(() => result.records.clear(), throwsUnsupportedError);
    }
  });
  test('receipt binds operation proposal and immutable revision with closed fields', () {
    final receipt = CommitReceipt(
      operationId: operationId,
      proposalId: proposalId,
      revision: frame.revision,
    );
    final back = CommitReceipt.fromWire(receipt.toWire());
    expect(back.operationId, operationId);
    expect(back.proposalId, proposalId);
    expect(back.revision, frame.revision);
    expect(
      () => CommitReceipt.fromWire(
        CanonicalObject([
          ...receipt.toWire().fields,
          const MapEntry('approved', CanonicalBool(true)),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => Proposal.fromWire(
        CanonicalObject([
          ...sample().toWire().fields,
          const MapEntry('authority', CanonicalBool(true)),
        ]),
      ),
      throwsFormatException,
    );
  });
  test(
    'queued interrupted and awaiting-authority states never alias success',
    () {
      for (final s in OperationState.values) {
        expect(OperationState.fromName(s.wireName), s);
      }
      expect(OperationState.awaitingAuthority, isNot(OperationState.succeeded));
      expect(OperationState.interrupted, isNot(OperationState.succeeded));
      expect(() => OperationState.fromName('complete'), throwsFormatException);
      expect(() => Submission.fromName('approved'), throwsFormatException);
    },
  );
}
