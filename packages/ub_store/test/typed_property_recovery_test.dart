@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: '\ufeffPending property',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
UnfinishedPropertyForm input(
  EditorFormScope s, {
  ValueShape? originalShape,
  bool editing = true,
  int variant = 0,
}) {
  final type = RecordId.generate();
  return UnfinishedPropertyForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: s.typeClientRef!,
    namespace: '\ufeffAuthored 記憶',
    key: '\ufeffPending key',
    rationale: '\ufeffReason 😀\r\n\u0000',
    draftVersion: editing ? maxU64 : null,
    labels: const [
      PropertyLabelInput(language: '\ufeffen', text: '\ufeffName'),
      PropertyLabelInput(),
      PropertyLabelInput(
        language: '\ufeffen',
        text: 'Repeated unfinished language',
      ),
    ],
    subjectTypes: const ['\ufeffPending type', '', 'Repeated', 'Repeated'],
    shape: ValueShapeInput(
      kind: 'still choosing',
      unit: '\ufeffUnused unit',
      definition: '\ufeffUnused definition',
      subjectTypes: ['\ufeffPending shape subject', '', 'Repeated', 'Repeated'],
      item: ValueShapeInput(
        kind: 'sequence',
        item: ValueShapeInput(
          kind: '',
          unit: '',
          definition: '\ufeffStill typing',
        ),
      ),
    ),
    multiplicity: 'still choosing',
    persistence: 'pending policy',
    hasUnitDimension: false,
    unitDimension: '\ufeffDisabled dimension',
    hasInverse: false,
    inverse: '\ufeffDisabled inverse',
    exclusive: true,
    symmetric: false,
    transitive: true,
    revisionTarget: editing
        ? const ExpressionReferenceInput(
            record: '',
            universe: '\ufeffUnfinished universe',
          )
        : null,
    expectedRecordVersion: editing ? RecordVersionId.generate() : null,
    original: editing
        ? PropertyRecord(
            namespace: '\ufeffOriginal namespace',
            key: '\ufeffOriginal key',
            labels: {'\ufeffen': '\ufeffOriginal name', '': '', 'ja': '記憶 😀'},
            subjectTypes: [type, type],
            value: originalShape ?? const RangeShape(null),
            multiplicity:
                Multiplicity.values[variant % Multiplicity.values.length],
            persistence: PersistenceSemantics
                .values[variant % PersistenceSemantics.values.length],
            unitDimension: switch (variant % 3) {
              0 => null,
              1 => '',
              _ => '\ufeffOriginal dimension',
            },
            inverse: switch (variant % 3) {
              0 => '',
              1 => null,
              _ => '\ufeffOriginal inverse',
            },
            exclusive: variant.isEven,
            symmetric: variant.isOdd,
            transitive: variant % 3 == 0,
          )
        : null,
  );
}

UnfinishedPropertyForm cleared(UnfinishedPropertyForm form) =>
    UnfinishedPropertyForm.fromWire(
      CanonicalObject([
        for (final e in form.toWire().fields)
          MapEntry(e.key, switch (e.key) {
            'labels' || 'subject_types' => CanonicalArray([]),
            'shape' => ValueShapeInput().toWire(),
            _ => e.value,
          }),
      ]),
    );

void main() {
  test('typed property recovery preserves every original shape, flag and nullable field alongside incomplete input', () {
    final root = Directory('/tmp').createTempSync('ub-typed-property-');
    final path = '${root.path}/forms.sqlite',
        s = scope(),
        unit = UnitId.generate(),
        definition = ValueDefinitionId.generate(),
        entity = RecordId.generate();
    final shapes = <ValueShape>[
      for (final kind in SimpleShapeKind.values) SimpleValueShape(kind),
      QuantityShape(unit),
      const RangeShape(null),
      RangeShape(unit),
      EntityRefShape([entity, entity]),
      EnumShape(definition),
      StructuredShape(definition),
      SequenceShape(SequenceShape(QuantityShape(unit))),
    ];
    var store = PropertyFormRecoveryStore.open(path);
    try {
      for (var i = 0; i < shapes.length; i++) {
        final form = input(s, originalShape: shapes[i], variant: i);
        final generation = BigInt.from(i);
        store.save(s, form, generation);
        store.close();
        store = PropertyFormRecoveryStore.open(path);
        expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
        expect(
          store.save(s, form, generation).generation,
          generation + BigInt.one,
        );
      }
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(property_form)').map((r) => r['name']),
          isNot(contains('form_input')),
        );
        final row = db
            .select(
              'SELECT has_unit_dimension,CAST(unit_dimension AS BLOB) AS dimension,has_inverse,CAST(inverse_input AS BLOB) AS inverse_value FROM property_form',
            )
            .single;
        expect(row['has_unit_dimension'], 0);
        expect(row['dimension'], utf8.encode('\ufeffDisabled dimension'));
        expect(row['has_inverse'], 0);
        expect(row['inverse_value'], utf8.encode('\ufeffDisabled inverse'));
        expect(
          db
              .select(
                "SELECT shape_kind FROM property_shape WHERE list_kind='input' ORDER BY depth",
              )
              .map((r) => r['shape_kind']),
          ['still choosing', 'sequence', ''],
        );
        expect(
          db
              .select(
                "SELECT count(*) AS n FROM property_subject_type WHERE list_kind='input'",
              )
              .single['n'],
          4,
        );
        expect(
          db
              .select(
                "SELECT count(*) AS n FROM property_subject WHERE list_kind='input' AND depth=0",
              )
              .single['n'],
          4,
        );
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
