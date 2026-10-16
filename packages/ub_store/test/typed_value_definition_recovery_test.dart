@TestOn('vm')
library;

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
  typeClientRef: '\ufeffPending definition',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
UnfinishedValueDefinitionForm input(EditorFormScope s, {bool editing = true}) {
  final unit = UnitId.generate(),
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
  return UnfinishedValueDefinitionForm(
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
    fields: [
      ValueDefinitionFieldInput(
        name: '\ufeffFirst field',
        required: true,
        allowsUnknown: false,
        shape: ValueShapeInput(
          kind: 'still choosing',
          unit: '\ufeffUnused unit',
          definition: '\ufeffUnused definition',
          subjectTypes: ['\ufeffPending subject', '', 'Repeated', 'Repeated'],
          item: ValueShapeInput(
            kind: 'sequence',
            item: ValueShapeInput(
              kind: '',
              unit: '',
              definition: '\ufeffStill typing',
            ),
          ),
        ),
      ),
      ValueDefinitionFieldInput(
        name: '',
        required: false,
        allowsUnknown: true,
        shape: ValueShapeInput(),
      ),
    ],
    revisionTarget: editing
        ? const ExpressionReferenceInput(
            record: '',
            universe: '\ufeffUnfinished universe',
          )
        : null,
    expectedRecordVersion: editing ? RecordVersionId.generate() : null,
    original: editing
        ? ValueDefinitionRecord(
            namespace: '\ufeffOriginal namespace',
            key: '\ufeffOriginal key',
            labels: {'\ufeffen': '\ufeffOriginal name', '': '', 'ja': '記憶 😀'},
            fields: [
              for (var i = 0; i < shapes.length; i++)
                ValueDefinitionField(
                  name: '\ufeffOriginal field $i',
                  shape: shapes[i],
                  required: i.isEven,
                  allowsUnknown: i.isOdd,
                ),
            ],
          )
        : null,
  );
}

UnfinishedValueDefinitionForm cleared(UnfinishedValueDefinitionForm form) =>
    UnfinishedValueDefinitionForm.fromWire(
      CanonicalObject([
        for (final e in form.toWire().fields)
          MapEntry(
            e.key,
            {'fields', 'labels'}.contains(e.key) ? CanonicalArray([]) : e.value,
          ),
      ]),
    );
void main() {
  test('typed value-definition recovery retains incomplete nested input and every original shape across restart', () {
    final root = Directory('/tmp').createTempSync('ub-typed-value-');
    final path = '${root.path}/forms.sqlite', s = scope(), form = input(s);
    var store = ValueDefinitionFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = ValueDefinitionFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db
              .select('PRAGMA table_info(value_definition_form)')
              .map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db
              .select(
                "SELECT shape_kind FROM value_definition_shape WHERE list_kind='input' AND field_ordinal=0 ORDER BY depth",
              )
              .map((r) => r['shape_kind']),
          ['still choosing', 'sequence', ''],
        );
        expect(
          db
              .select(
                "SELECT is_required,allows_unknown FROM value_definition_field WHERE list_kind='input' ORDER BY ordinal",
              )
              .map((r) => [r['is_required'], r['allows_unknown']]),
          [
            [1, 0],
            [0, 1],
          ],
        );
        expect(
          db
              .select(
                "SELECT count(*) AS n FROM value_definition_subject WHERE list_kind='input' AND field_ordinal=0 AND depth=0",
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
