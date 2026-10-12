import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/definition_registry.dart';

import 'operation_compilation_test.dart' as f;
import 'effective_objects_test.dart' as o;

DefinitionRegistry registry(List<RecordVersion> rows) {
  final r = DefinitionRegistry();
  for (final row in rows) {
    r.add(row);
  }
  return r;
}

void validate(List<RecordVersion> rows) => registry(rows).validate();
Matcher error(String code) => throwsA(
  isA<DefinitionAdmissionError>().having((e) => e.code, 'code', code),
);
UnitId unitId(int n) => UnitId.parse('unit_${f.suffix(n)}');
ValueDefinitionId valueId(int n) =>
    ValueDefinitionId.parse('vdef_${f.suffix(n)}');
UnitRecord unit(
  int n, {
  String dimension = 'length',
  DomainValue? scale,
  UnitId? base,
}) => UnitRecord(
  namespace: 'test',
  key: 'unit$n',
  dimension: dimension,
  symbol: 'u',
  labels: {},
  scaleToBase: scale,
  base: base,
  validity: const UnspecifiedValidity(),
);
ValueDefinitionRecord valueDef(
  int n,
  List<ValueShape> shapes, {
  bool duplicate = false,
}) => ValueDefinitionRecord(
  namespace: 'test',
  key: 'value$n',
  labels: {},
  fields: [
    for (var i = 0; i < shapes.length; i++)
      ValueDefinitionField(
        name: duplicate ? 'x' : 'f$i',
        shape: shapes[i],
        required: true,
        allowsUnknown: false,
      ),
  ],
);
DomainPackRecord pack(
  String key, {
  String version = '1',
  Map<String, String> dependencies = const {},
  List<String> capabilities = const [],
}) => DomainPackRecord(
  key: key,
  version: version,
  dependencies: dependencies,
  capabilities: capabilities,
  records: [],
);

void main() {
  test('relation roles must be nonempty unique and reference declared participant types', () {
    RelationRecord relation(List<RoleDefinition> roles) =>
        RelationRecord(namespace: '', key: '', labels: {}, roles: roles);
    expect(
      () => validate([f.row(1, relation([]))]),
      error('INVALID_DEFINITION'),
    );
    final role = RoleDefinition(
      name: 'actor',
      ordered: false,
      participantTypes: [f.id(2)],
      multiplicity: Multiplicity.single,
    );
    expect(
      () => validate([
        f.row(1, relation([role, role])),
        f.row(2, f.type(2)),
      ]),
      error('INVALID_DEFINITION'),
    );
    expect(
      () => validate([
        f.row(1, relation([role])),
      ]),
      error('MISSING_REFERENCE'),
    );
    // The owning validator does not require property-style namespace bounds
    // for relations; retain that behavior rather than adding admission policy.
    validate([
      f.row(1, relation([role])),
      f.row(2, f.type(2)),
    ]);
  });
  test('pack dependency depth is bounded without moving exact versions', () {
    List<RecordVersion> chain(int length) => [
      for (var n = 1; n <= length; n++)
        f.row(
          n,
          pack('p$n', dependencies: n == length ? {} : {'p${n + 1}': '1'}),
        ),
    ];
    validate(chain(32));
    expect(() => validate(chain(33)), error('INVALID_DEFINITION'));
  });
  test('registry ignores instances after verifying digests and replaces active definitions', () {
    final r = registry(o.fixture());
    expect(r.universe, f.u);
    expect(r.get(f.id(4), RecordKind.entity), isNull);
    r.add(
      f.row(
        5,
        f.patch(o.get(o.fixture(), 5).payload, {
          'key': CanonicalString('replacement'),
        }),
      ),
    );
    expect(
      (r.get(f.id(5), RecordKind.property) as PropertyRecord).key,
      'replacement',
    );
    r.validate();
    final instance = f.row(80, f.entity());
    expect(
      () => r.add(
        RecordVersion(
          recordVersionId: instance.recordVersionId,
          identity: instance.identity,
          payload: instance.payload,
          payloadDigest: 'bad',
        ),
      ),
      error('DIGEST_MISMATCH'),
    );
    final empty = registry([instance]);
    expect(empty.universe, isNull);
  });
  test(
    'definition namespaces are isolated and duplicate family names rejected',
    () {
      final rows = [f.row(1, f.type(1)), f.row(2, f.type(2, key: 'type1'))];
      expect(() => registry(rows), error('DUPLICATE_DEFINITION'));
      final foreign = RecordVersion.build(
        recordVersionId: f.ver(3),
        identity: RecordIdentity(
          universeId: UniverseId.parse('unv_${f.suffix(2)}'),
          recordId: f.id(3),
          recordKind: RecordKind.entityType,
        ),
        payload: f.type(3),
      );
      expect(
        () => registry([rows.first, foreign]),
        error('CROSS_UNIVERSE_REFERENCE'),
      );
      validate([f.row(1, f.type(1)), f.row(2, unit(2))]);
    },
  );
  test(
    'type parent consistency dangling parents and cycles are admission errors',
    () {
      expect(
        () => validate([f.row(1, f.type(1, parent: 2))]),
        error('MISSING_REFERENCE'),
      );
      expect(
        () => validate([
          f.row(1, f.type(1, parent: 2, resolution: ParentResolution.root)),
          f.row(2, f.type(2)),
        ]),
        error('INVALID_DEFINITION'),
      );
      expect(
        () => validate([
          f.row(1, f.type(1, parent: 2)),
          f.row(2, f.type(2, parent: 1)),
        ]),
        error('INHERITANCE_CYCLE'),
      );
      validate([f.row(1, f.type(1, resolution: ParentResolution.ambiguous))]);
    },
  );
  test('property subject types inverse names exact units and dimensions must resolve', () {
    final rows = o.fixture();
    o.edit(rows, 5, {'value': QuantityShape(unitId(80)).toWire()});
    expect(() => validate(rows), error('MISSING_REFERENCE'));
    rows.add(f.row(80, unit(80)));
    validate(rows);
    o.edit(rows, 5, {'unitDimension': CanonicalString('mass')});
    expect(() => validate(rows), error('INVALID_DEFINITION'));
    o.edit(rows, 5, {
      'unitDimension': const CanonicalNull(),
      'inverse': CanonicalString('missing'),
    });
    expect(() => validate(rows), error('MISSING_REFERENCE'));
    o.edit(rows, 5, {'inverse': CanonicalString('grows')});
    validate(rows);
  });
  test('quantity units and value definition references inside sequences remain governed by owning checks', () {
    final rows = o.fixture();
    o.edit(rows, 5, {'value': StructuredShape(valueId(80)).toWire()});
    expect(() => validate(rows), error('MISSING_REFERENCE'));
    rows.add(f.row(80, valueDef(80, [])));
    validate(rows);
    o.edit(rows, 5, {
      'value': SequenceShape(StructuredShape(valueId(81))).toWire(),
    });
    // Registry mirrors the owning schema check: nested sequence conformance
    // belongs to the separate value admission path.
    validate(rows);
  });
  test('units require positive exact scale and a compatible distinct base', () {
    for (final value in [
      IntegerValue('0'),
      DecimalValue('-0.5'),
      RationalValue('1', '-2'),
      const BooleanValue(true),
    ]) {
      expect(
        () => validate([f.row(1, unit(1, scale: value))]),
        error('INVALID_DEFINITION'),
      );
    }
    validate([
      f.row(1, unit(1, scale: RationalValue('1', '2'))),
      f.row(2, unit(2, scale: DecimalValue('+00.5'), base: unitId(1))),
    ]);
    expect(
      () => validate([f.row(1, unit(1, base: unitId(1)))]),
      error('INVALID_DEFINITION'),
    );
    expect(
      () => validate([f.row(1, unit(1, base: unitId(2)))]),
      error('MISSING_REFERENCE'),
    );
    expect(
      () => validate([
        f.row(1, unit(1, base: unitId(2))),
        f.row(2, unit(2, dimension: 'mass')),
      ]),
      error('INVALID_DEFINITION'),
    );
  });
  test('calendars may be label only but conversion targets must exist', () {
    CalendarRecord calendar(List<CalendarConversion> conversions) =>
        CalendarRecord(
          namespace: 'test',
          key: 'days',
          labels: {},
          unitStructure: {},
          conversions: conversions,
        );
    validate([f.row(1, calendar([]))]);
    expect(
      () => validate([
        f.row(
          1,
          calendar([
            CalendarConversion(
              target: CalendarId.parse('cal_${f.suffix(2)}'),
              valid: false,
            ),
          ]),
        ),
      ]),
      error('MISSING_REFERENCE'),
    );
  });
  test('value fields reject duplicates direct recursion and excessive structured depth', () {
    expect(
      () => validate([
        f.row(
          1,
          valueDef(1, [
            const SimpleValueShape(SimpleShapeKind.text),
            const SimpleValueShape(SimpleShapeKind.text),
          ], duplicate: true),
        ),
      ]),
      error('INVALID_DEFINITION'),
    );
    expect(
      () => validate([
        f.row(1, valueDef(1, [StructuredShape(valueId(1))])),
      ]),
      error('SCHEMA_RECURSION'),
    );
    expect(
      () => validate([
        f.row(1, valueDef(1, [StructuredShape(valueId(2))])),
        f.row(2, valueDef(2, [StructuredShape(valueId(1))])),
      ]),
      error('SCHEMA_RECURSION'),
    );
    List<RecordVersion> chain(int length) => [
      for (var n = 1; n <= length; n++)
        f.row(
          n,
          valueDef(n, n == length ? [] : [StructuredShape(valueId(n + 1))]),
        ),
    ];
    validate(chain(33));
    expect(() => validate(chain(34)), error('SCHEMA_RECURSION'));
    validate([
      f.row(1, valueDef(1, [StructuredShape(valueId(2))])),
    ]);
  });
  test('packs pin dependencies reject cycles and cannot enable unknown capabilities', () {
    validate([
      f.row(
        1,
        pack(
          'a',
          dependencies: {'b': '1'},
          capabilities: knownDefinitionCapabilities,
        ),
      ),
      f.row(2, pack('b')),
    ]);
    expect(
      () => validate([
        f.row(1, pack('a', dependencies: {'b': '2'})),
        f.row(2, pack('b')),
      ]),
      error('INVALID_DEFINITION'),
    );
    expect(
      () => validate([
        f.row(1, pack('a', dependencies: {'b': '1'})),
        f.row(2, pack('b', dependencies: {'a': '1'})),
      ]),
      error('INVALID_DEFINITION'),
    );
    expect(
      () => validate([
        f.row(1, pack('a', capabilities: ['new.code.v1'])),
      ]),
      error('UNKNOWN_CAPABILITY'),
    );
    expect(
      () => validate([f.row(1, pack('a', version: '\u3000'))]),
      error('INVALID_DEFINITION'),
    );
  });
}
