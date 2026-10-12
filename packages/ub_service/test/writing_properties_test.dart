import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'writing_units_test.dart' as units;

WritingProperty declaration(
  String name, {
  bool introduce = true,
  PlainPropertyType type = PlainPropertyType.boolean,
  String? unit,
  bool single = true,
  PlainPersistence persistence = PlainPersistence.unspecified,
}) => WritingProperty(
  name: name,
  introduce: introduce,
  valueType: type,
  unit: unit,
  singleValue: single,
  persistence: persistence,
);

void main() {
  test('candidate stages bind earlier explicit units and property revisions without changing the base', () {
    final base = [f.row(30, f.entity()), f.row(1, f.entity())];
    final before = base.map((row) => row.toWire().toText()).toList();
    final unitStage = compileWritingUnits([
      units.declaration(name: 'metre', introduce: true),
    ], base);
    final withUnits = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: unitStage.operations,
    );
    final propertyStage = compileWritingProperties(
      universe: f.u,
      rows: withUnits,
      declarations: [
        declaration('distance', type: PlainPropertyType.quantity, unit: 'm'),
      ],
      corrections: [],
    );
    expect(propertyStage.clarifications, isEmpty);
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: [...unitStage.operations, ...propertyStage.operations],
    );
    expect(candidate, hasLength(4));
    final ids = candidate.map((row) => row.identity.recordId.value).toList();
    expect(ids, [...ids]..sort());
    final unit = candidate.singleWhere((row) => row.payload is UnitRecord);
    final property = candidate.singleWhere(
      (row) => row.payload is PropertyRecord,
    );
    expect(
      (property.payload as PropertyRecord).value,
      QuantityShape(UnitId.fromRecordId(unit.identity.recordId)),
    );
    final corrected = compileWritingProperties(
      universe: f.u,
      rows: candidate,
      declarations: [],
      corrections: [
        WritingPropertyCorrection(
          name: 'distance',
          singleValue: false,
          reason: 'Keep several measurements',
        ),
      ],
    );
    final revised = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: candidate,
      operations: corrected.operations,
    );
    final changed = revised.singleWhere(
      (row) => row.identity.recordId == property.identity.recordId,
    );
    expect(
      (changed.payload as PropertyRecord).multiplicity,
      Multiplicity.multiple,
    );
    expect(changed.recordVersionId, isNot(property.recordVersionId));
    expect(
      (property.payload as PropertyRecord).multiplicity,
      Multiplicity.single,
    );
    expect(base.map((row) => row.toWire().toText()), before);
    final stale = compileWritingProperties(
      universe: f.u,
      rows: candidate,
      declarations: [],
      corrections: [
        WritingPropertyCorrection(
          name: 'distance',
          persistence: PlainPersistence.untilChanged,
          reason: 'Stale preview',
        ),
      ],
    );
    expect(
      () => compileWritingCandidate(
        universe: f.u,
        revision: f.revision,
        base: revised,
        operations: stale.operations,
      ),
      throwsA(
        isA<InvalidArgumentError>().having(
          (e) => e.message,
          'message',
          contains('expected record version differs'),
        ),
      ),
    );
  });
  test('all declared value types compile to canonical definitions with explicit units', () {
    final unitRows = [f.row(1, units.unit())];
    final result = compileWritingProperties(
      universe: f.u,
      rows: unitRows,
      declarations: [
        for (final type in PlainPropertyType.values)
          declaration(
            type.name,
            type: type,
            unit: type == PlainPropertyType.quantity ? 'm' : null,
            single: type != PlainPropertyType.object,
            persistence: type == PlainPropertyType.integer
                ? PlainPersistence.untilChanged
                : type == PlainPropertyType.decimal
                ? PlainPersistence.explicitInterval
                : PlainPersistence.unspecified,
          ),
      ],
      corrections: [],
    );
    expect(result.clarifications, isEmpty);
    expect(result.additions, hasLength(6));
    final records = f
        .compile(unitRows, result.operations)
        .map(f.decode)
        .toList();
    expect(records, hasLength(6));
    final shapes = [
      const SimpleValueShape(SimpleShapeKind.text),
      const SimpleValueShape(SimpleShapeKind.boolean),
      const SimpleValueShape(SimpleShapeKind.integer),
      const SimpleValueShape(SimpleShapeKind.decimal),
      EntityRefShape([]),
      QuantityShape(UnitId.fromRecordId(f.id(1))),
    ];
    for (var i = 0; i < records.length; i++) {
      final property = records[i].payload as PropertyRecord;
      expect(property.value, shapes[i]);
      expect(property.namespace, 'authoring');
      expect(property.subjectTypes, isEmpty);
      expect(property.labels, isEmpty);
      expect(
        property.exclusive || property.symmetric || property.transitive,
        isFalse,
      );
      expect(result.properties[property.key]!.$1, records[i].identity.recordId);
    }
    expect(
      (records[2].payload as PropertyRecord).persistence,
      PersistenceSemantics.persistentUntilChanged,
    );
    expect(
      (records[3].payload as PropertyRecord).persistence,
      PersistenceSemantics.explicitInterval,
    );
    expect(
      (records[4].payload as PropertyRecord).multiplicity,
      Multiplicity.multiple,
    );
    // A declaration in a later segment reuses the actual candidate definition.
    final unchanged = compileWritingProperties(
      universe: f.u,
      rows: [...unitRows, ...records],
      declarations: [
        declaration(
          'quantity',
          introduce: false,
          type: PlainPropertyType.quantity,
          unit: 'metre',
        ),
      ],
      corrections: [],
    );
    expect(unchanged.operations, isEmpty);
    expect(unchanged.unchanged, ['Property definition: quantity']);
  });

  test('missing ambiguous or inappropriate units clarify without inferred conversion', () {
    final rows = [
      f.row(1, units.unit()),
      f.row(2, units.unit(key: 'other', symbol: 'm')),
    ];
    final result = compileWritingProperties(
      universe: f.u,
      rows: rows,
      declarations: [
        declaration('textUnit', type: PlainPropertyType.text, unit: 'm'),
        declaration('missingUnit', type: PlainPropertyType.quantity),
        declaration(
          'unknownUnit',
          type: PlainPropertyType.quantity,
          unit: 'feet',
        ),
        declaration(
          'ambiguousUnit',
          type: PlainPropertyType.quantity,
          unit: 'm',
        ),
      ],
      corrections: [],
    );
    expect(result.operations, isEmpty);
    expect(result.properties, isEmpty);
    expect(result.clarifications, hasLength(4));
    expect(
      result.clarifications.first,
      contains('without explicitly declaring quantity'),
    );
    expect(result.clarifications[1], contains('What authored unit'));
    expect(
      result.clarifications.skip(2),
      everyElement(contains('cannot imply conversion')),
    );
  });

  test('declarations cannot replace existing settings or duplicate introduced identities', () {
    final newDefinition = compileWritingProperties(
      universe: f.u,
      rows: [],
      declarations: [declaration('open'), declaration('open')],
      corrections: [],
    );
    expect(newDefinition.operations, hasLength(1));
    expect(newDefinition.clarifications, hasLength(1));
    final rows = f.compile([], newDefinition.operations).map(f.decode).toList();
    final results = compileWritingProperties(
      universe: f.u,
      rows: rows,
      declarations: [
        declaration('open'),
        declaration('missing', introduce: false),
        declaration('open', introduce: false, type: PlainPropertyType.text),
        declaration('open', introduce: false, single: false),
        declaration(
          'open',
          introduce: false,
          persistence: PlainPersistence.untilChanged,
        ),
        declaration('open', introduce: false),
      ],
      corrections: [],
    );
    expect(results.operations, isEmpty);
    expect(results.clarifications, hasLength(5));
    expect(results.unchanged, ['Property definition: open']);
    expect(
      () => compileWritingProperties(
        universe: f.u,
        rows: [],
        declarations: [declaration('\u2003')],
        corrections: [],
      ),
      throwsA(
        isA<InvalidArgumentError>().having(
          (e) => e.field,
          'field',
          'properties.name',
        ),
      ),
    );
  });

  test('corrections preserve omitted settings and pin original versions', () {
    final original = f.row(
      3,
      PropertyRecord(
        namespace: 'test',
        key: 'linked',
        labels: {'en': 'linked to', 'alias': 'link'},
        subjectTypes: [f.id(50)],
        value: EntityRefShape([f.id(50)]),
        multiplicity: Multiplicity.single,
        unitDimension: 'retained',
        persistence: PersistenceSemantics.explicitInterval,
        exclusive: true,
        inverse: 'backlink',
        symmetric: true,
        transitive: true,
      ),
    );
    final result = compileWritingProperties(
      universe: f.u,
      rows: [original],
      declarations: [],
      corrections: [
        WritingPropertyCorrection(
          name: 'linked to',
          singleValue: false,
          reason: 'Allow several links',
        ),
      ],
    );
    expect(result.clarifications, isEmpty);
    final operation = result.operations.single as ReviseDefinitionOperation;
    expect(operation.record, f.ref(3));
    expect(operation.expectedVersion, original.recordVersionId);
    final replacement = operation.replacement as PropertyRecord;
    expect(
      replacement,
      f.patch<PropertyRecord>(original.payload as PropertyRecord, {
        'multiplicity': CanonicalString('multiple'),
      }),
    );
    for (final name in ['linked', 'linked to', 'link']) {
      expect(result.properties[name], (f.id(3), replacement));
    }
    expect(result.additions, [
      'Property rule correction: linked to — Allow several links',
    ]);
    final compiled = f
        .compile([original], result.operations)
        .map(f.decode)
        .single;
    expect(compiled.identity.recordId, original.identity.recordId);
    expect(compiled.payload, replacement);
    expect(compiled.recordVersionId, isNot(original.recordVersionId));
    final second = compileWritingProperties(
      universe: f.u,
      rows: [compiled],
      declarations: [],
      corrections: [
        WritingPropertyCorrection(
          name: 'link',
          persistence: PlainPersistence.untilChanged,
          reason: 'Retain links',
        ),
      ],
    );
    final changed = second.operations.single as ReviseDefinitionOperation;
    expect(changed.expectedVersion, compiled.recordVersionId);
    expect(
      (changed.replacement as PropertyRecord).multiplicity,
      Multiplicity.multiple,
    );
    expect(
      (changed.replacement as PropertyRecord).persistence,
      PersistenceSemantics.persistentUntilChanged,
    );
  });

  test('unsupported missing and ambiguous corrections cannot manufacture or overwrite properties', () {
    final initial = compileWritingProperties(
      universe: f.u,
      rows: [],
      declarations: [declaration('open')],
      corrections: [],
    );
    final original = f.compile([], initial.operations).map(f.decode).single;
    final duplicate = f.row(10, original.payload);
    final results = compileWritingProperties(
      universe: f.u,
      rows: [original, duplicate],
      declarations: [],
      corrections: [
        WritingPropertyCorrection(
          name: 'open',
          singleValue: false,
          reason: '\u0085',
        ),
        WritingPropertyCorrection(name: 'open', reason: 'No setting provided'),
        WritingPropertyCorrection(
          name: 'missing',
          singleValue: false,
          reason: 'Missing',
        ),
        WritingPropertyCorrection(
          name: 'open',
          singleValue: false,
          reason: 'Ambiguous',
        ),
      ],
    );
    expect(results.operations, isEmpty);
    expect(results.properties, isEmpty);
    expect(results.clarifications, hasLength(4));
    expect(
      results.clarifications.take(2),
      everyElement(contains('omitted settings stay unchanged')),
    );
    expect(
      results.clarifications.skip(2),
      everyElement(contains('Which exact authored property')),
    );
    final ownDelta = compileWritingProperties(
      universe: f.u,
      rows: [],
      declarations: [declaration('new')],
      corrections: [
        WritingPropertyCorrection(
          name: 'new',
          singleValue: false,
          reason: 'Cannot edit an unpinned introduction',
        ),
      ],
    );
    expect(ownDelta.operations, hasLength(1));
    expect(
      ownDelta.clarifications.single,
      contains('Which exact authored property'),
    );
  });
}
