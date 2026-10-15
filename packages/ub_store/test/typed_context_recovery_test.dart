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
  typeClientRef: '\ufeffPending',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
UnfinishedRepresentedContextForm form(
  EditorFormScope s, {
  RepresentedContextRecord? original,
}) => UnfinishedRepresentedContextForm(
  baseRevision: RevisionId.generate(),
  representedContext: s.representedContext!,
  universe: s.universe,
  clientRef: s.typeClientRef!,
  kind: 'still choosing',
  authoredLabel: '\ufeffLabel\r\n\u0000😀',
  reference: const ExpressionReferenceInput(
    record: '',
    universe: '\ufeffPending universe',
  ),
  parentEnabled: false,
  parent: const ExpressionReferenceInput(
    record: 'disabled parent',
    universe: '',
  ),
  chronology: const ChronologyInput(
    enabled: false,
    calendar: 'pending',
    system: 'undecided',
    offsetSeconds: '-',
    tickLabel: '\ufeffTick',
    ticksPerMonthEnabled: false,
    ticksPerMonth: '9007199254740997',
    firstInteraction: '\ufeffStart',
    current: '\ufeffCurrent',
  ),
  labels: const [
    PropertyLabelInput(language: '\ufeffen', text: '\ufeffName'),
    PropertyLabelInput(),
    PropertyLabelInput(language: '\ufeffen', text: 'Repeated'),
  ],
  rationale: '\ufeffReason\r\n\u0000記憶',
  draftVersion: maxU64,
  original: original,
);
void legacy(String path, List<(EditorFormScope, BigInt, String)> entries) {
  protectedFile(path, create: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE represented_context_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, g, text) in entries) {
      db.execute(
        'INSERT INTO represented_context_form VALUES(?,?,?,?,?,?,?,?)',
        [...binding(s), g.toString(), text],
      );
    }
  } finally {
    db.close();
  }
}

void main() {
  test('context recovery retains disabled chronology input and all original context and clock variants through replacement and restart', () {
    final root = Directory('/tmp').createTempSync('ub-typed-context-'),
        s = scope();
    final path = '${root.path}/forms.sqlite',
        ref = RecordRef(
          record: RecordId.generate(),
          universe: UniverseId.generate(),
        );
    var store = RepresentedContextFormRecoveryStore.open(path),
        generation = BigInt.zero;
    try {
      for (final kind in <RepresentedContextKind>[
        const ObjectiveContext(),
        const AuthoredContext('\ufeffAuthored'),
        CharacterContext(ref),
        SourceContext(RecordRef(record: ref.record)),
        NarratorContext(ref),
      ]) {
        for (final clock in <ClockSystem?>[
          null,
          GregorianClock(-2147483648),
          GregorianClock(2147483647),
          FictionalClock('\ufeffTick', null),
          FictionalClock('', 0),
          FictionalClock('Tick', 4294967295),
        ]) {
          final input = form(
            s,
            original: RepresentedContextRecord(
              universe: UniverseId.generate(),
              kind: kind,
              parent: clock == null ? null : ref,
              chronology: clock == null
                  ? null
                  : Chronology(
                      calendar: CalendarId.generate(),
                      system: clock,
                      firstInteraction: '\ufeffStart',
                      current: '\ufeffCurrent',
                    ),
              labels: {'\ufeffen': '\ufeffOriginal', '': '', 'ja': '記憶😀'},
            ),
          );
          generation = store.save(s, input, generation).generation;
          store.close();
          store = RepresentedContextFormRecoveryStore.open(path);
          expect(
            store.load(s)!.form.toWire().toText(),
            input.toWire().toText(),
          );
          expect(
            store.save(s, input, generation - BigInt.one).generation,
            generation,
          );
        }
      }
      final changed = form(s);
      generation = store.save(s, changed, generation).generation;
      store.close();
      store = RepresentedContextFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), changed.toWire().toText());
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db
              .select('PRAGMA table_info(represented_context_form)')
              .map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db
              .select('SELECT count(*) AS n FROM represented_context_original')
              .single['n'],
          0,
        );
        expect(
          db
              .select(
                "SELECT count(*) AS n FROM represented_context_label WHERE list_kind='original'",
              )
              .single['n'],
          0,
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
  test('context conversion preserves scope and generation and retains conflict and exhaustion behavior', () {
    final root = Directory('/tmp').createTempSync('ub-context-conversion-'),
        s = scope(),
        second = scope();
    final path = '${root.path}/forms.sqlite',
        input = form(s),
        other = form(second);
    legacy(path, [
      (s, BigInt.from(19), input.toWire().toText()),
      (second, maxU64, other.toWire().toText()),
    ]);
    final store = RepresentedContextFormRecoveryStore.open(path),
        competing = RepresentedContextFormRecoveryStore.open(path);
    try {
      expect(store.load(s)!.form.toWire().toText(), input.toWire().toText());
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = input.copyWith(labels: [], rationale: 'changed');
      expect(
        store.save(s, changed, BigInt.from(19)).generation,
        BigInt.from(20),
      );
      expect(
        () => competing.save(s, input, BigInt.from(19)),
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
      final wrong = EditorFormScope(
        instance: s.instance,
        profile: s.profile,
        universe: UniverseId.generate(),
        continuity: s.continuity,
        representedContext: s.representedContext,
        typeClientRef: s.typeClientRef,
      );
      expect(store.load(wrong), isNull);
      expect(
        () => store.save(wrong, input, BigInt.zero),
        throwsFormatException,
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 2);
        expect(
          db.select(
            'SELECT count(*) AS n FROM represented_context_label WHERE profile=?',
            [s.profile.value],
          ).single['n'],
          0,
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
  test('failed context conversion rolls back the entire conversion and retains original unfinished forms', () {
    final root = Directory('/tmp').createTempSync('ub-context-rollback-'),
        s = scope(),
        second = scope();
    final path = '${root.path}/forms.sqlite', text = form(s).toWire().toText();
    legacy(path, [(s, BigInt.one, text), (second, BigInt.two, '{unfinished')]);
    try {
      expect(
        () => RepresentedContextFormRecoveryStore.open(path),
        throwsA(isA<EditorRecoveryException>()),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 1);
        expect(
          db
              .select(
                'SELECT form_input FROM represented_context_form ORDER BY generation',
              )
              .map((r) => r['form_input']),
          [text, '{unfinished'],
        );
        expect(
          db
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((r) => r['name']),
          ['represented_context_form'],
        );
      } finally {
        db.close();
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
