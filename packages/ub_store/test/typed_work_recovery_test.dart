@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/src/ownership.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: '\ufeffPending work',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
UnfinishedWorkForm input(EditorFormScope s) {
  final ref = RecordRef(record: RecordId.generate(), universe: s.universe),
      edition = RecordId.generate();
  final association = WorldAssociation(
    world: WorldId.generate(),
    role: '\ufeffSetting',
    validity: InstantValidity(
      DurationTime(
        CalendarId.generate(),
        SequenceValue([const TextValue('\ufeffA lifetime')]),
      ),
    ),
    qualifiers: {
      '\ufeffKey': const RationalValue('9007199254740997', '3'),
      'nested': StructuredValue(ValueDefinitionId.generate(), {
        '\ufeffField': const TextValue('\ufeffValue\r\n\u0000😀'),
      }),
    },
  );
  const validity = TemporalValidityInput(
    kind: 'pending',
    calendar: '\ufeffCalendar',
    targetRecord: 'disabled target',
    start: TemporalBoundInput(
      kind: 'unknown',
      value: 'disabled start',
      upper: '\ufeffUpper',
      amount: QualifierInput(kind: 'rational', value: '3', denominator: '0'),
    ),
  );
  const qualifier = QualifierInput(
    kind: 'pending',
    key: '\ufeffKey',
    value: '\ufeffValue',
    unit: 'disabled unit',
    originalKey: '',
    temporal: validity,
    children: [
      QualifierInput(key: 'same'),
      QualifierInput(key: 'same', value: '😀'),
    ],
    lower: QualifierInput(kind: 'integer', value: '9007199254740997'),
  );
  return UnfinishedWorkForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: s.typeClientRef!,
    kind: 'unfinished kind',
    title: '\ufeffChronicle 記憶',
    labels: const [
      PropertyLabelInput(language: '\ufeffen', text: '\ufeffName'),
      PropertyLabelInput(),
      PropertyLabelInput(language: '\ufeffen', text: 'Repeated'),
    ],
    sources: const [
      ExpressionReferenceInput(record: '\ufeffPending', universe: ''),
      ExpressionReferenceInput(),
      ExpressionReferenceInput(record: '\ufeffPending', universe: ''),
    ],
    versions: const ['\ufeffEdition', '', '\ufeffEdition'],
    associations: [
      WorkAssociationInput(
        world: '\ufeffPending world',
        role: '',
        validity: validity,
        qualifiers: const [qualifier, qualifier],
        originalOrdinal: 9223372036854775807,
      ),
      WorkAssociationInput(),
      WorkAssociationInput(
        world: '\ufeffPending world',
        role: 'repeated',
        originalOrdinal: -1,
      ),
    ],
    original: WorkRecord(
      kind: WorkKind.novel,
      title: '\ufeffOriginal',
      labels: {'\ufeffen': '\ufeffName', '': '', 'ja': '記憶😀'},
      sourceRefs: [
        ref,
        ref,
        RecordRef(record: ref.record),
      ],
      versions: [edition, edition],
      worldAssociations: [association, association],
    ),
    associationOriginal: association,
    associationTarget: const ExpressionReferenceInput(
      record: '',
      universe: '\ufeffPending universe',
    ),
    expectedRecordVersion: RecordVersionId.generate(),
    draftVersion: maxU64,
    rationale: '\ufeffReason\r\n\u0000😀',
  );
}

void legacy(String path, List<(EditorFormScope, BigInt, String)> entries) {
  protectedFile(path, create: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE work_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, g, text) in entries) {
      db.execute('INSERT INTO work_form VALUES(?,?,?,?,?,?,?,?)', [
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
  test('typed work recovery retains ordered incomplete links, association qualifiers and original records after restart', () {
    final root = Directory('/tmp').createTempSync('ub-typed-work-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = WorkFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = WorkFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(work_form)').map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db
              .select(
                'SELECT original_ordinal FROM work_association ORDER BY ordinal',
              )
              .map((r) => r['original_ordinal']),
          ['9223372036854775807', null, '-1'],
        );
        expect(
          db
              .select('SELECT count(*) AS n FROM work_association_qualifier')
              .single['n'],
          2,
        );
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('work conversion preserves isolated forms, generations and conflict handling', () {
    final root = Directory('/tmp').createTempSync('ub-work-conversion-'),
        s = scope(),
        second = scope();
    final path = '${root.path}/forms.sqlite',
        form = input(s),
        other = input(second);
    legacy(path, [
      (s, BigInt.from(19), form.toWire().toText()),
      (second, maxU64, other.toWire().toText()),
    ]);
    var store = WorkFormRecoveryStore.open(path);
    final competing = WorkFormRecoveryStore.open(path);
    try {
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = form.copyWith(
        labels: [],
        sources: [],
        versions: [],
        associations: [],
      );
      expect(
        store.save(s, changed, BigInt.from(19)).generation,
        BigInt.from(20),
      );
      expect(
        store.save(s, changed, BigInt.from(19)).generation,
        BigInt.from(20),
      );
      expect(
        () => competing.save(s, form, BigInt.from(19)),
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
      store = WorkFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), changed.toWire().toText());
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        for (final table in [
          'label',
          'source',
          'version',
          'association',
          'association_qualifier',
        ]) {
          expect(
            db.select('SELECT count(*) AS n FROM work_$table WHERE profile=?', [
              s.profile.value,
            ]).single['n'],
            0,
          );
        }
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      competing.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('clearing a work removes superseded nested values and originals and preserves optional absence', () {
    final root = Directory('/tmp').createTempSync('ub-work-clearing-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = WorkFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.save(s, form.copyWith(title: 'replaced'), BigInt.one);
      final empty = UnfinishedWorkForm(
        baseRevision: form.baseRevision,
        representedContext: form.representedContext,
        clientRef: form.clientRef,
      );
      store.save(s, empty, BigInt.two);
      store.close();
      store = WorkFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), empty.toWire().toText());
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        for (final row in db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name!='work_form'",
        )) {
          expect(
            db.select('SELECT count(*) AS n FROM "${row['name']}"').single['n'],
            0,
            reason: row['name'] as String,
          );
        }
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('failed work conversion rolls back all typed rows and retains original forms', () {
    final root = Directory('/tmp').createTempSync('ub-work-rollback-'),
        s = scope(),
        second = scope();
    final path = '${root.path}/forms.sqlite', text = input(s).toWire().toText();
    legacy(path, [(s, BigInt.one, text), (second, BigInt.two, '{unfinished')]);
    try {
      expect(
        () => WorkFormRecoveryStore.open(path),
        throwsA(isA<EditorRecoveryException>()),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 1);
        expect(
          db
              .select('SELECT form_input FROM work_form ORDER BY generation')
              .map((r) => r['form_input']),
          [text, '{unfinished'],
        );
        expect(
          db
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((r) => r['name']),
          ['work_form'],
        );
      } finally {
        db.close();
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
