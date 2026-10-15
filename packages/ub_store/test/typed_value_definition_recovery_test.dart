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

void legacy(String path, List<(EditorFormScope, BigInt, String)> entries) {
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE value_definition_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, generation, text) in entries) {
      db.execute('INSERT INTO value_definition_form VALUES(?,?,?,?,?,?,?,?)', [
        ...binding(s),
        generation.toString(),
        text,
      ]);
    }
  } finally {
    db.close();
  }
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
  test('value-definition conversion retains profiles and generations and atomically replaces shape subtrees', () {
    final root = Directory('/tmp').createTempSync('ub-value-conversion-');
    final path = '${root.path}/forms.sqlite', s = scope(), second = scope();
    final form = input(s), other = input(second, editing: false);
    legacy(path, [
      (s, BigInt.from(7), form.toWire().toText()),
      (second, maxU64, other.toWire().toText()),
    ]);
    var store = ValueDefinitionFormRecoveryStore.open(path);
    final competing = ValueDefinitionFormRecoveryStore.open(path);
    try {
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = cleared(form);
      expect(store.save(s, changed, BigInt.from(7)).generation, BigInt.from(8));
      expect(store.save(s, changed, BigInt.from(7)).generation, BigInt.from(8));
      expect(
        () => competing.save(s, form, BigInt.from(7)),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        () => store.save(second, other, maxU64),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.generationExhausted,
          ),
        ),
      );
      store.close();
      store = ValueDefinitionFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), changed.toWire().toText());
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 2);
        for (final table in ['label', 'field', 'shape', 'subject']) {
          expect(
            db.select(
              "SELECT count(*) AS n FROM value_definition_$table WHERE profile=? AND list_kind='input'",
              [s.profile.value],
            ).single['n'],
            0,
          );
        }
        expect(
          db.select(
            "SELECT count(*) AS n FROM value_definition_field WHERE profile=? AND list_kind='original'",
            [s.profile.value],
          ).single['n'],
          form.original!.fields.length,
        );
      } finally {
        db.close();
      }
    } finally {
      competing.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('failed value-definition conversion rolls back complete shape trees and retains original rows', () {
    final root = Directory('/tmp').createTempSync('ub-value-rollback-');
    final path = '${root.path}/forms.sqlite',
        s = scope(),
        second = scope(),
        text = input(s).toWire().toText();
    legacy(path, [(s, BigInt.one, text), (second, BigInt.two, '{unfinished')]);
    try {
      expect(
        () => ValueDefinitionFormRecoveryStore.open(path),
        throwsA(isA<EditorRecoveryException>()),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 1);
        expect(
          db
              .select(
                'SELECT form_input FROM value_definition_form ORDER BY generation',
              )
              .map((r) => r['form_input']),
          [text, '{unfinished'],
        );
        expect(
          db
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((r) => r['name']),
          ['value_definition_form'],
        );
      } finally {
        db.close();
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
