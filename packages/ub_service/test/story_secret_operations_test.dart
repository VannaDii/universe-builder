import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/src/proposal_authorization.dart';

import 'operation_compilation_test.dart' as f;

void main() {
  test(
    'story secrets round trip, create and revise with exact expected versions',
    () {
      final first = SecretRecord(
        scope: [f.ref(2)],
        fictionalKnowers: [f.ref(3)],
        readerDisclosed: false,
        concealment: 'The reader learns later 記憶\r\n',
        validity: const UnspecifiedValidity(),
      );
      final create = CreateSecretOperation(
        clientRef: 'heir-secret',
        record: first,
      );
      expect(
        DomainOperation.fromWire(create.toWire()).toWire().toText(),
        create.toWire().toText(),
      );
      final base = [f.row(2, f.entity()), f.row(3, f.entity())];
      final changes = f.compile(base, [create]);
      final published = f.decode(changes.single);
      expect(published.identity.recordKind, RecordKind.secret);
      expect(published.payload.toWire().toText(), first.toWire().toText());
      final next = SecretRecord(
        scope: first.scope,
        fictionalKnowers: [f.ref(3), f.ref(2)],
        readerDisclosed: true,
        concealment: null,
        validity: first.validity,
      );
      final revise = ReviseSecretOperation(
        record: RecordRef(universe: f.u, record: published.identity.recordId),
        expectedVersion: published.recordVersionId,
        replacement: next,
      );
      expect(
        DomainOperation.fromWire(revise.toWire()).toWire().toText(),
        revise.toWire().toText(),
      );
      final revised = f.compile([...base, published], [revise]);
      expect(revised.single.recordId, published.identity.recordId);
      expect(revised.single.expected, published.recordVersionId);
      expect(
        f.decode(revised.single).payload.toWire().toText(),
        next.toWire().toText(),
      );
      expect(published.payload.toWire().toText(), first.toWire().toText());
      expect(
        () => f.compile(
          [...base, published],
          [
            ReviseSecretOperation(
              record: revise.record,
              expectedVersion: f.ver(999),
              replacement: next,
            ),
          ],
        ),
        throwsA(isA<InvalidArgumentError>()),
      );
      expect(
        () => f.compile(base, [
          ReviseSecretOperation(
            record: f.ref(2),
            expectedVersion: f.ver(2),
            replacement: next,
          ),
        ]),
        throwsA(isA<InvalidArgumentError>()),
      );
    },
  );
  test('reader disclosure does not relax application permissions', () {
    for (final disclosed in [false, true]) {
      final record = SecretRecord(
        scope: [f.ref(2)],
        fictionalKnowers: [],
        readerDisclosed: disclosed,
        validity: const UnspecifiedValidity(),
      );
      final base = [f.row(2, f.entity())];
      final changes = f.compile(base, [
        CreateSecretOperation(clientRef: 'secret', record: record),
      ]);
      final footprint = writeFootprint(base: base, changes: changes);
      expect(footprint.protected, isTrue);
      expect(footprint.shared, isTrue);
    }
  });
}
