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
void legacy(String path, List<(EditorFormScope, BigInt, String)> entries) {
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE property_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, g, text) in entries) {
      db.execute('INSERT INTO property_form VALUES(?,?,?,?,?,?,?,?)', [
        ...binding(s),
        g.toString(),
        text,
      ]);
    }
  } finally {
    db.close();
  }
}

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
  test('property conversion preserves scopes, generations and original definitions while atomically replacing unfinished trees', () {
    final root = Directory('/tmp').createTempSync('ub-property-conversion-');
    final path = '${root.path}/forms.sqlite', s = scope(), otherScope = scope();
    final form = input(s), other = input(otherScope, editing: false);
    legacy(path, [
      (s, BigInt.from(7), form.toWire().toText()),
      (otherScope, maxU64, other.toWire().toText()),
    ]);
    var store = PropertyFormRecoveryStore.open(path);
    final competing = PropertyFormRecoveryStore.open(path);
    try {
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(
        store.load(otherScope)!.form.toWire().toText(),
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
        () => store.save(otherScope, other, maxU64),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.generationExhausted,
          ),
        ),
      );
      store.close();
      store = PropertyFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), changed.toWire().toText());
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 2);
        for (final table in ['label', 'subject_type', 'subject']) {
          expect(
            db.select(
              "SELECT count(*) AS n FROM property_$table WHERE profile=? AND list_kind='input'",
              [s.profile.value],
            ).single['n'],
            0,
          );
        }
        expect(
          db.select(
            "SELECT count(*) AS n FROM property_shape WHERE profile=? AND list_kind='input'",
            [s.profile.value],
          ).single['n'],
          1,
        );
        expect(
          db.select(
            "SELECT count(*) AS n FROM property_subject_type WHERE profile=? AND list_kind='original'",
            [s.profile.value],
          ).single['n'],
          form.original!.subjectTypes.length,
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
  test('failed property conversion retains every original row without partial typed state', () {
    final root = Directory('/tmp').createTempSync('ub-property-rollback-');
    final path = '${root.path}/forms.sqlite',
        s = scope(),
        second = scope(),
        text = input(s).toWire().toText();
    legacy(path, [(s, BigInt.one, text), (second, BigInt.two, '{unfinished')]);
    try {
      expect(
        () => PropertyFormRecoveryStore.open(path),
        throwsA(isA<EditorRecoveryException>()),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 1);
        expect(
          db
              .select(
                'SELECT form_input FROM property_form ORDER BY generation',
              )
              .map((r) => r['form_input']),
          [text, '{unfinished'],
        );
        expect(
          db
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((r) => r['name']),
          ['property_form'],
        );
      } finally {
        db.close();
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
