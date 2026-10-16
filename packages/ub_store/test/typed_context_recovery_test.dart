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
}
