import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' show InvalidArgumentError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/candidate_checks.dart';

import 'operation_compilation_test.dart' as f;
import 'effective_objects_test.dart' as o;

void edit(
  List<RecordVersion> rows,
  int n,
  Map<String, CanonicalValue> changes,
) => o.edit(rows, n, changes);
CanonicalValue applies(List<int> worlds) =>
    WorldsApplicability(worlds.map(o.world).toList()).toWire();
void scoped(List<RecordVersion> rows, int n, {List<int>? worlds, int? realm}) =>
    edit(rows, n, {
      'scope': o
          .scope(
            applies: worlds == null
                ? null
                : WorldsApplicability(worlds.map(o.world).toList()),
            realm: realm,
          )
          .toWire(),
    });

void main() {
  List<RecordVersion> collection({
    String? predicate,
    List<RecordRef> members = const [],
    CompletenessKind completeness = const ObjectiveCompleteness(),
    Validity? validity,
    Scope? scope,
  }) {
    final rows = o.withInstance();
    edit(rows, 8, {
      'value': ReferenceValue(ValueReferenceKind.entity, f.ref(25)).toWire(),
    });
    rows.add(
      f.row(
        80,
        CompletenessRecord(
          subject: f.ref(4),
          predicate: predicate ?? f.id(5).value,
          members: members,
          completeness: completeness,
          validity: validity ?? o.interval(10, 20),
          scope: scope ?? o.scope(),
        ),
      ),
    );
    return rows;
  }

  test('objective collection closes only its declared members and binds original versions', () {
    for (final predicate in [f.id(5).value, 'test:grows']) {
      final (findings, gaps) = completenessConflicts(
        collection(predicate: predicate),
      );
      expect(findings, hasLength(1));
      expect(findings.single.$1, f.id(80));
      expect(findings.single.$2, [f.ver(80), f.ver(9)]);
      expect(gaps, isEmpty);
    }
    expect(completenessConflicts(collection(members: [f.ref(25)])).$1, isEmpty);
  });
  test('observer knowledge context realm and namespace omission do not close another scope', () {
    for (final rows in [
      collection(completeness: ObserverCompleteness(f.id(4))),
      collection(scope: o.scope(context: 98)),
      collection(scope: o.scope(realm: 30)),
    ]) {
      expect(completenessConflicts(rows).$1, isEmpty);
    }
    // A namespace-omitted member is distinct from the explicit member.
    expect(
      completenessConflicts(collection(members: [RecordRef(record: f.id(25))]))
          .$1,
      hasLength(1),
    );
  });
  test('collection temporal uncertainty remains a gap while disjoint time is harmless', () {
    final (findings, gaps) = completenessConflicts(
      collection(validity: const UnknownValidity()),
    );
    expect(findings, isEmpty);
    expect(gaps, [
      'completeness:${f.id(80).value}: unresolved temporal overlap',
    ]);
    expect(
      completenessConflicts(collection(validity: o.interval(20, 30))).$1,
      isEmpty,
    );
    final rows = collection();
    edit(rows, 9, {'precision': CanonicalString('approximate')});
    expect(completenessConflicts(rows).$1, isEmpty);
    edit(rows, 9, {
      'precision': CanonicalString('exact'),
      'polarity': CanonicalString('refutation'),
    });
    expect(completenessConflicts(rows).$1, isEmpty);
  });
  test(
    'inherited shared witnesses conflict with instance facts in source order',
    () {
      final (conflicts, gaps) = scalarConflicts(o.withInstance());
      expect(conflicts, hasLength(1));
      expect(conflicts.single.$1, f.id(5));
      expect(conflicts.single.$2, [f.ver(9), f.ver(7)]);
      expect(gaps, isEmpty);
      expect(scalarConflicts(o.fixture()).$1, isEmpty);
    },
  );
  test('initial values are separate and multiple nonexclusive properties allow differences', () {
    final rows = o.withInstance();
    edit(rows, 9, {'attributeMode': CanonicalString('initial_value')});
    expect(scalarConflicts(rows).$1, isEmpty);
    final multiple = o.withInstance();
    edit(multiple, 5, {'multiplicity': CanonicalString('multiple')});
    expect(scalarConflicts(multiple).$1, isEmpty);
    edit(multiple, 5, {'exclusive': CanonicalBool(true)});
    expect(scalarConflicts(multiple).$1, hasLength(1));
  });
  test(
    'equivalent integer and decimal values do not create scalar conflicts',
    () {
      final rows = o.withInstance();
      edit(rows, 6, {'value': IntegerValue('1').toWire()});
      edit(rows, 8, {'value': DecimalValue('1.00').toWire()});
      expect(scalarConflicts(rows).$1, isEmpty);
      expect(scalarConflicts(rows).$2, isEmpty);
    },
  );
  test(
    'refutation is excluded and unresolved ancestry does not inherit witnesses',
    () {
      final rows = o.withInstance();
      edit(rows, 9, {'polarity': CanonicalString('refutation')});
      expect(scalarConflicts(rows).$1, isEmpty);
      final unknown = o.withInstance();
      edit(unknown, 2, {'parentResolution': CanonicalString('ambiguous')});
      expect(scalarConflicts(unknown).$1, isEmpty);
    },
  );
  test('disjoint worlds and realms cannot conflict; shared jurisdiction is intersected', () {
    final rows = o.withInstance();
    scoped(rows, 7, worlds: [20]);
    scoped(rows, 9, worlds: [21]);
    expect(scalarConflicts(rows).$1, isEmpty);
    expect(scalarConflicts(rows).$2, isEmpty);
    scoped(rows, 9, worlds: [20], realm: 25);
    expect(scalarConflicts(rows).$1, isEmpty);
    expect(scalarConflicts(rows).$2, isEmpty);
    scoped(rows, 9, worlds: [20]);
    expect(scalarConflicts(rows).$1, hasLength(1));
    edit(rows, 1, {
      'applicability': applies([21]),
    });
    expect(scalarConflicts(rows).$1, isEmpty);
    expect(scalarConflicts(rows).$2, isEmpty);
  });
  test('unknown time precision and conditional scope remain gaps; disjoint time does not', () {
    for (final change in <Map<String, CanonicalValue>>[
      {'validity': const UnknownValidity().toWire()},
      {'precision': CanonicalString('approximate')},
      {'scope': o.scope(applies: const ConditionalApplicability()).toWire()},
    ]) {
      final rows = o.withInstance();
      edit(rows, 9, change);
      final (conflicts, gaps) = scalarConflicts(rows);
      expect(conflicts, isEmpty);
      expect(gaps, ['scalar-scope-or-time:${f.id(5).value}']);
    }
    final rows = o.withInstance();
    edit(rows, 9, {'validity': o.interval(20, 30).toWire()});
    expect(scalarConflicts(rows).$1, isEmpty);
    expect(scalarConflicts(rows).$2, isEmpty);
  });
  test('scalar work cap keeps findings and declares incomplete comparison', () {
    final rows = o.withInstance();
    // Many distinct source assertions borrowing the same proposition are not
    // different facts; their pair comparisons still consume the source budget.
    rows.removeWhere((r) => r.identity.recordId == f.id(7));
    for (var n = 100; n < 1516; n++) {
      rows.add(f.row(n, o.assertion(8)));
    }
    final (conflicts, gaps) = scalarConflicts(rows);
    expect(conflicts, isEmpty);
    expect(gaps, ['scalar-work-budget-exhausted']);
  });
  test(
    'unchanged assertions must remain within candidate definition jurisdiction',
    () {
      final rows = o.withInstance();
      expect(validateDefinitionApplicability(rows), isEmpty);
      edit(rows, 1, {
        'applicability': applies([20]),
      });
      expect(
        () => validateDefinitionApplicability(rows),
        throwsA(
          isA<InvalidArgumentError>().having(
            (e) => e.field,
            'field',
            'candidate',
          ),
        ),
      );
      scoped(rows, 7, worlds: [20]);
      scoped(rows, 9, worlds: [20]);
      expect(validateDefinitionApplicability(rows), isEmpty);
    },
  );
  test(
    'unresolved applicability returns sorted attributed gaps without guessing',
    () {
      final rows = o.withInstance();
      edit(rows, 1, {
        'applicability': const ConditionalApplicability().toWire(),
      });
      expect(validateDefinitionApplicability(rows), [
        'definition-applicability:${f.id(7).value}:${f.id(1).value}',
        'definition-applicability:${f.id(9).value}:${f.id(4).value}',
      ]);
    },
  );
}
