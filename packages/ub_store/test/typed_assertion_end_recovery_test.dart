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
  typeClientRef: '\ufeffPending end',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
UnfinishedAssertionEndForm input(EditorFormScope s, EvidenceBasis original) =>
    UnfinishedAssertionEndForm(
      baseRevision: RevisionId.generate(),
      representedContext: s.representedContext!,
      clientRef: s.typeClientRef!,
      target: const ExpressionReferenceInput(
        record: '',
        universe: '\ufeffUnfinished universe',
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      calendar: CalendarId.generate(),
      originalBasis: original,
      coordinate: '\ufeffPending coordinate',
      basis: const EvidenceBasisInput(
        kind: 'still choosing',
        note: '\ufeffNote\r\n\u0000😀',
        anchorRecord: 'disabled anchor',
        anchorUniverse: '',
        verified: true,
      ),
      rationale: '\ufeffReason\r\n記憶',
      draftVersion: maxU64,
    );
VersionRef version({UniverseId? universe}) => VersionRef(
  record: RecordId.generate(),
  version: RecordVersionId.generate(),
  universe: universe,
);
List<EvidenceBasis> bases() {
  final ref = RecordRef(
        record: RecordId.generate(),
        universe: UniverseId.generate(),
      ),
      v = version();
  return [
    const AuthorDecisionBasis('\ufeffAuthor note\r\n\u0000'),
    SourceAnchorBasis(ref, true),
    SourceAnchorBasis(RecordRef(record: ref.record), false),
    EventEffectBasis(ref, '\ufeffEffect slot'),
    InstanceInitializationBasis(
      v,
      version(universe: ref.universe),
      RevisionId.generate(),
    ),
    const ImportedClaimBasis(),
    DerivationBasis([v, version(universe: ref.universe), v], '\ufeffEvaluator'),
    DerivationBasis([], null),
    DerivationBasis([], ''),
  ];
}

void legacy(String path, List<(EditorFormScope, BigInt, String)> entries) {
  protectedFile(path, create: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE assertion_end_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, g, text) in entries) {
      db.execute('INSERT INTO assertion_end_form VALUES(?,?,?,?,?,?,?,?)', [
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
  test('assertion ending retains exact input and every evidence basis across typed recovery and replacement', () {
    final root = Directory('/tmp').createTempSync('ub-typed-assertion-end-'),
        s = scope();
    final path = '${root.path}/forms.sqlite';
    var store = AssertionEndFormRecoveryStore.open(path),
        generation = BigInt.zero;
    try {
      for (final basis in bases()) {
        final form = input(s, basis);
        generation = store.save(s, form, generation).generation;
        store.close();
        store = AssertionEndFormRecoveryStore.open(path);
        expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
        expect(
          store.save(s, form, generation - BigInt.one).generation,
          generation,
        );
        final db = sqlite3.open(path, mode: OpenMode.readOnly);
        try {
          expect(
            db
                .select('PRAGMA table_info(assertion_end_form)')
                .map((r) => r['name']),
            isNot(contains('form_input')),
          );
          expect(db.select('PRAGMA foreign_key_check'), isEmpty);
          expect(
            db
                .select('SELECT count(*) AS n FROM assertion_end_basis_version')
                .single['n'],
            basis is DerivationBasis
                ? basis.chain.length
                : basis is InstanceInitializationBasis
                ? 2
                : 0,
          );
        } finally {
          db.close();
        }
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('assertion ending conversion preserves generations, isolated forms and ordered original version references', () {
    final root = Directory('/tmp').createTempSync('ub-end-conversion-'),
        s = scope(),
        second = scope();
    final path = '${root.path}/forms.sqlite',
        form = input(s, bases()[6]),
        other = input(second, bases()[4]);
    legacy(path, [
      (s, BigInt.from(19), form.toWire().toText()),
      (second, maxU64, other.toWire().toText()),
    ]);
    var store = AssertionEndFormRecoveryStore.open(path);
    final competing = AssertionEndFormRecoveryStore.open(path);
    try {
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = form.copyWith(
        coordinate: '',
        basis: const EvidenceBasisInput(),
        rationale: 'changed',
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
      store = AssertionEndFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), changed.toWire().toText());
    } finally {
      competing.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('failed assertion ending conversion restores all original unfinished forms', () {
    final root = Directory('/tmp').createTempSync('ub-end-rollback-'),
        s = scope(),
        second = scope();
    final path = '${root.path}/forms.sqlite',
        text = input(s, bases()[4]).toWire().toText();
    legacy(path, [(s, BigInt.one, text), (second, BigInt.two, '{unfinished')]);
    try {
      expect(
        () => AssertionEndFormRecoveryStore.open(path),
        throwsA(isA<EditorRecoveryException>()),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 1);
        expect(
          db
              .select(
                'SELECT form_input FROM assertion_end_form ORDER BY generation',
              )
              .map((r) => r['form_input']),
          [text, '{unfinished'],
        );
        expect(
          db
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((r) => r['name']),
          ['assertion_end_form'],
        );
      } finally {
        db.close();
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
