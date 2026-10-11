import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

Map<String, CanonicalValue> fields(CanonicalObject value) => {
  for (final e in value.fields) e.key: e.value,
};
CanonicalObject replace(
  CanonicalObject value,
  Map<String, CanonicalValue> changes,
) => CanonicalObject({...fields(value), ...changes}.entries);

void main() {
  final typeId = RecordId.parse('rec_000000000000000000000001');
  final worldId = WorldId.parse('wld_000000000000000000000001');
  final unitId = UnitId.parse('unit_000000000000000000000001');
  final valueId = ValueDefinitionId.parse('vdef_000000000000000000000001');
  final calendarId = CalendarId.parse('cal_000000000000000000000001');
  test(
    'every declared shape preserves authored wire and comparison meanings',
    () {
      final shapes = <ValueShape>[
        for (final kind in SimpleShapeKind.values) SimpleValueShape(kind),
        QuantityShape(unitId),
        const RangeShape(null),
        RangeShape(unitId),
        EntityRefShape([typeId, typeId]),
        EnumShape(valueId),
        StructuredShape(valueId),
        const SequenceShape(
          SequenceShape(SimpleValueShape(SimpleShapeKind.text)),
        ),
      ];
      for (final shape in shapes) {
        expect(ValueShape.fromWire(shape.toWire()), shape);
      }
      expect(
        const SimpleValueShape(SimpleShapeKind.text).toWire().toText(),
        '{"kind":"text"}',
      );
      expect(
        const SimpleValueShape(SimpleShapeKind.text).toCanonical().toText(),
        '"text"',
      );
      expect(
        const RangeShape(null).toWire().toText(),
        '{"kind":"range","unit":null}',
      );
      expect(const RangeShape(null).toCanonical().toText(), '{"kind":"range"}');
      final refs = EntityRefShape([typeId, typeId]);
      expect(refs.toWire().toText(), contains('"subject_types"'));
      expect(refs.toCanonical().toText(), contains('"subjectTypes"'));
      expect(refs.subjectTypes, [typeId, typeId]);
      expect(() => refs.subjectTypes.clear(), throwsUnsupportedError);
      expect(
        const SequenceShape(SimpleValueShape(SimpleShapeKind.text))
            .toCanonical()
            .toText(),
        '{"item":"text","kind":"sequence"}',
      );
    },
  );
  test(
    'shapes reject unknown fields and wrongly typed definition identities',
    () {
      for (final text in [
        '{"kind":"text","unit":"${unitId.value}"}',
        '{"kind":"enum","definition":"${typeId.value}"}',
        '{"kind":"entity_ref","subject_types":null}',
        '{"kind":"sequence","item":"text"}',
        '{"kind":"invented"}',
      ]) {
        expect(
          () => ValueShape.fromWire(CanonicalValue.parseJson(text)),
          throwsFormatException,
        );
      }
    },
  );
  final type = EntityTypeRecord(
    namespace: 'author',
    key: 'person',
    labels: {'en': 'Person'},
    name: 'Person',
    parentResolution: ParentResolution.ambiguous,
    applicability: WorldsApplicability([]),
    classificationExecutable: false,
  );
  final property = PropertyRecord(
    namespace: 'author',
    key: 'balance',
    labels: {},
    value: const SimpleValueShape(SimpleShapeKind.decimal),
    multiplicity: Multiplicity.single,
    persistence: PersistenceSemantics.persistentUntilChanged,
    exclusive: false,
    symmetric: false,
    transitive: false,
  );
  test('definitions retain explicit ambiguity and opt-in behavior without inference', () {
    expect(EntityTypeRecord.fromWire(type.toWire()), type);
    expect(type.parent, isNull);
    expect(type.parentResolution, ParentResolution.ambiguous);
    expect(type.classificationExecutable, isFalse);
    expect((type.applicability as WorldsApplicability).worldIds, isEmpty);
    expect(PropertyRecord.fromWire(property.toWire()), property);
    expect(property.exclusive, isFalse);
    expect(property.symmetric, isFalse);
    expect(property.transitive, isFalse);
    expect(property.inverse, isNull);
    expect(property.toWire().toText(), contains('"subjectTypes":[]'));
    expect(property.toWire().toText(), contains('"unitDimension":null'));
    expect(property.toWire().toText(), contains('"inverse":null'));
  });
  test('source defaults expand only where declared and do not accept null collections', () {
    final world = WorldRecord.fromWire(
      CanonicalValue.parseJson(
        '{"record_kind":"world","selector":"Original 🌲"}',
      ),
    );
    expect(world.labels, isEmpty);
    expect(world.metadata, isEmpty);
    expect(
      world.toWire().toText(),
      '{"labels":{},"metadata":{},"record_kind":"world","selector":"Original 🌲"}',
    );
    expect(
      () => WorldRecord.fromWire(
        replace(world.toWire(), {'aliases': const CanonicalNull()}),
      ),
      throwsFormatException,
    );
    expect(
      () => WorldRecord.fromWire(
        replace(world.toWire(), {'labels': const CanonicalNull()}),
      ),
      throwsFormatException,
    );
    expect(
      () => EntityTypeRecord.fromWire(
        replace(type.toWire(), {
          'parentResolution': CanonicalString('unclassified'),
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => PropertyRecord.fromWire(
        replace(property.toWire(), {'subjectTypes': const CanonicalNull()}),
      ),
      throwsFormatException,
    );
    expect(
      () => RelationRecord.fromWire(
        CanonicalValue.parseJson(
          '{"record_kind":"relation","namespace":"author","key":"owns","labels":{}}',
        ),
      ),
      throwsFormatException,
    );
  });
  test('identity names and world association retain uncertainty without inferring location', () {
    final labels = {'en': 'Memoir subject'};
    final qualifiers = {'account': const TextValue('firsthand')};
    final names = [
      const ContextualName(
        text: 'Author’s name',
        language: 'en',
        role: 'pseudonym',
        validity: UnknownValidity(),
      ),
    ];
    final association = WorldAssociation(
      world: worldId,
      role: 'origin',
      validity: const UnknownValidity(),
      qualifiers: qualifiers,
    );
    final entity = EntityRecord(
      names: names,
      classificationResolution: ClassificationResolution.unclassified,
      worldAssociations: [association],
      labels: labels,
      metadata: {'recollection': const TextValue('approximate')},
    );
    labels.clear();
    qualifiers.clear();
    names.clear();
    expect(EntityRecord.fromWire(entity.toWire()), entity);
    expect(entity.names.single.text, 'Author’s name');
    expect(entity.names.single.validity, const UnknownValidity());
    expect(entity.names.single.community, isNull);
    expect(entity.labels['en'], 'Memoir subject');
    expect(association.qualifiers['account'], const TextValue('firsthand'));
    expect(entity.classification, isNull);
    expect(entity.worldAssociations.single.role, 'origin');
    expect(() => entity.names.clear(), throwsUnsupportedError);
    expect(() => entity.metadata.clear(), throwsUnsupportedError);
    expect(() => association.qualifiers.clear(), throwsUnsupportedError);
  });
  test(
    'unit and calendar preserve authored conversion limits and exact values',
    () {
      final unit = UnitRecord(
        namespace: 'author',
        key: 'money',
        dimension: 'currency',
        symbol: 'M',
        labels: {},
        scaleToBase: const DecimalValue('0001.00'),
        validity: const UnknownValidity(),
      );
      expect(UnitRecord.fromWire(unit.toWire()), unit);
      expect(unit.base, isNull);
      expect(unit.scaleToBase, const DecimalValue('0001.00'));
      final calendar = CalendarRecord(
        namespace: 'author',
        key: 'memoir',
        labels: {},
        unitStructure: {'month': 'authored'},
        conversions: [CalendarConversion(target: calendarId, valid: false)],
      );
      expect(CalendarRecord.fromWire(calendar.toWire()), calendar);
      expect(calendar.epoch, isNull);
      expect(calendar.conversions.single.expression, isNull);
      expect(calendar.conversions.single.valid, isFalse);
      expect(calendar.toWire().toText(), contains('"expression":null'));
      expect(() => calendar.conversions.clear(), throwsUnsupportedError);
    },
  );
  test('structured definitions and packs remain typed data with ordered dependencies', () {
    final definition = ValueDefinitionRecord(
      namespace: 'author',
      key: 'inventory',
      labels: {},
      fields: [
        const ValueDefinitionField(
          name: 'contents',
          shape: SequenceShape(SimpleValueShape(SimpleShapeKind.text)),
          required: true,
          allowsUnknown: true,
        ),
      ],
    );
    final pack = DomainPackRecord(
      key: 'campaign',
      version: '1',
      dependencies: {'rules': 'pinned'},
      capabilities: ['authored', 'authored'],
      records: [typeId, typeId],
    );
    expect(ValueDefinitionRecord.fromWire(definition.toWire()), definition);
    expect(DomainPackRecord.fromWire(pack.toWire()), pack);
    expect(pack.capabilities, ['authored', 'authored']);
    expect(pack.records, [typeId, typeId]);
    expect(() => definition.fields.clear(), throwsUnsupportedError);
    expect(() => pack.dependencies.clear(), throwsUnsupportedError);
    expect(() => pack.records.clear(), throwsUnsupportedError);
  });
}
