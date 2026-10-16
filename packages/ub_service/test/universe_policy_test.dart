import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' as protocol;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/src/universe_evidence_policy.dart';
import 'package:ub_service/definition_registry.dart';

import 'candidate_validation_test.dart' as candidate;

RecordVersion replace(RecordVersion original, RecordPayload payload) =>
    RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: original.identity,
      payload: payload,
    );

void main() {
  final universe = candidate.fixture().first.identity.universeId;
  for (final realWorld in [false, true]) {
    test(
      'creation defines and selects ${realWorld ? 'Real World' : 'scratch'} root',
      () {
        final rows = initialUniversePolicyRecords(universe, realWorld);
        final selected = UniversePolicySelection.fromRecords(universe, rows);
        expect(selected.rules, hasLength(realWorld ? 1 : 0));
        final policy = selected.definition.payload as DomainPackRecord;
        final binding = selected.selection.payload as DomainPackRecord;
        expect(binding.records, [selected.definition.identity.recordId]);
        expect(binding.dependencies, {policy.key: policy.version});
        expect(rows.every((r) => r.verifiesDigest), isTrue);
        // Re-decoding canonical records preserves the exact selection and members.
        final restored = UniversePolicySelection.fromRecords(
          universe,
          rows.map((r) => RecordVersion.fromWire(r.toWire())),
        );
        expect(
          restored.selection.payloadDigest,
          selected.selection.payloadDigest,
        );
        expect(
          restored.definition.payloadDigest,
          selected.definition.payloadDigest,
        );
      },
    );
  }

  test('a declared root cannot be removed together with all definitions', () {
    final root = initialUniversePolicyRecords(universe, false);
    final base = [...candidate.fixture(), ...root];
    expect(candidate.check(base).admissible, isTrue);
    expect(
      () => candidate.check(candidate.fixture(), base: base),
      throwsA(isA<protocol.InvalidArgumentError>()),
    );
  });

  test('another defined root can be selected without deleting the former definition', () {
    final initial = initialUniversePolicyRecords(universe, false);
    final old = UniversePolicySelection.fromRecords(universe, initial);
    final alternative = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.domainPack,
      ),
      payload: DomainPackRecord(
        key: '${universePolicyDefinitionPrefix}alternative',
        version: '1',
        dependencies: {},
        capabilities: [],
        records: [],
      ),
    );
    final definition = alternative.payload as DomainPackRecord;
    final selected = replace(
      old.selection,
      DomainPackRecord(
        key: universePolicySelectionKey,
        version: '2',
        dependencies: {definition.key: definition.version},
        capabilities: [],
        records: [alternative.identity.recordId],
      ),
    );
    final rows = [
      ...candidate.fixture(),
      old.definition,
      alternative,
      selected,
    ];
    expect(
      candidate
          .check(rows, base: [...candidate.fixture(), ...initial])
          .admissible,
      isTrue,
    );
    expect(
      UniversePolicySelection.fromRecords(universe, rows).definition,
      alternative,
    );
    expect(rows, contains(old.definition));
    expect(
      () => candidate.check(
        rows.where((r) => r != alternative).toList(),
        base: rows,
      ),
      throwsA(isA<DefinitionAdmissionError>()),
    );
  });

  test(
    'changing a nonempty root requires an explicit rule-scope transition',
    () {
      final initial = initialUniversePolicyRecords(universe, true);
      final active = UniversePolicySelection.fromRecords(universe, initial);
      final empty = initialUniversePolicyRecords(universe, false);
      final scratch = UniversePolicySelection.fromRecords(universe, empty);
      final rows = [
        ...candidate.fixture(),
        ...initial.where((r) => r != active.selection),
        ...empty,
      ];
      expect(
        () => candidate.check(rows, base: [...candidate.fixture(), ...initial]),
        throwsA(isA<protocol.InvalidArgumentError>()),
      );
      expect(scratch.rules, isEmpty);
    },
  );

  test(
    'selection refuses missing, duplicate, foreign and mismatched definitions',
    () {
      final initial = initialUniversePolicyRecords(universe, false);
      final selected = UniversePolicySelection.fromRecords(universe, initial);
      final definition = selected.definition.payload as DomainPackRecord;
      expect(
        () => UniversePolicySelection.fromRecords(universe, []),
        throwsFormatException,
      );
      expect(
        () =>
            UniversePolicySelection.fromRecords(universe, [selected.selection]),
        throwsFormatException,
      );
      expect(
        () => UniversePolicySelection.fromRecords(universe, [
          ...initial,
          selected.selection,
        ]),
        throwsFormatException,
      );
      expect(
        () =>
            UniversePolicySelection.fromRecords(UniverseId.generate(), initial),
        throwsFormatException,
      );
      final wrongVersion = replace(
        selected.selection,
        DomainPackRecord(
          key: universePolicySelectionKey,
          version: '2',
          dependencies: {definition.key: 'not-the-defined-version'},
          capabilities: [],
          records: [selected.definition.identity.recordId],
        ),
      );
      expect(
        () => UniversePolicySelection.fromRecords(universe, [
          selected.definition,
          wrongVersion,
        ]),
        throwsFormatException,
      );
    },
  );
}
