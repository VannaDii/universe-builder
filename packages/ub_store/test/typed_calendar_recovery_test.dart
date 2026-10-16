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
  typeClientRef: '\ufeffPending calendar',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
UnfinishedCalendarForm input(EditorFormScope s, {bool editing = true}) {
  final target = CalendarId.generate();
  return UnfinishedCalendarForm(
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
    hasEpoch: false,
    epoch: '\ufeffDisabled epoch',
    units: const [
      CalendarUnitInput(
        name: '\ufeffDay',
        structure: 'pending structure\r\n\u0000',
      ),
      CalendarUnitInput(),
      CalendarUnitInput(name: '\ufeffDay', structure: 'repeated name'),
    ],
    conversions: const [
      CalendarConversionInput(
        target: '\ufeffPending calendar',
        hasExpression: false,
        expression: 'disabled expression 😀',
        valid: true,
      ),
      CalendarConversionInput(),
      CalendarConversionInput(
        target: '\ufeffPending calendar',
        hasExpression: true,
        expression: '',
        valid: false,
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
        ? CalendarRecord(
            namespace: '\ufeffOriginal namespace',
            key: '\ufeffOriginal key',
            labels: {'\ufeffen': '\ufeffOriginal name', '': '', 'ja': '記憶 😀'},
            epoch: '\ufeffOriginal epoch',
            unitStructure: {
              '\ufeffDay': '\ufeff24 hours',
              '': '',
              'ja': '記憶 😀',
            },
            conversions: [
              CalendarConversion(
                target: target,
                expression: null,
                valid: false,
              ),
              CalendarConversion(target: target, expression: '', valid: true),
              CalendarConversion(
                target: CalendarId.generate(),
                expression: '\ufeffAuthored formula\r\n\u0000',
                valid: false,
              ),
            ],
          )
        : null,
  );
}

UnfinishedCalendarForm cleared(UnfinishedCalendarForm form) =>
    UnfinishedCalendarForm.fromWire(
      CanonicalObject([
        for (final e in form.toWire().fields)
          MapEntry(
            e.key,
            {'units', 'conversions', 'labels'}.contains(e.key)
                ? CanonicalArray([])
                : e.value,
          ),
      ]),
    );

void main() {
  test('typed calendar recovery retains incomplete structures, disabled conversion expressions and original definitions after restart', () {
    final root = Directory('/tmp').createTempSync('ub-typed-calendar-');
    final path = '${root.path}/forms.sqlite', s = scope(), form = input(s);
    var store = CalendarFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = CalendarFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(calendar_form)').map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db
              .select(
                "SELECT has_expression,is_valid,CAST(expression_input AS BLOB) AS expression FROM calendar_conversion WHERE list_kind='input' ORDER BY ordinal",
              )
              .map(
                (r) => [r['has_expression'], r['is_valid'], r['expression']],
              ),
          [
            [0, 1, utf8.encode(form.conversions[0].expression)],
            [0, 0, utf8.encode('')],
            [1, 0, utf8.encode('')],
          ],
        );
        expect(
          db
              .select(
                "SELECT CAST(unit_name AS BLOB) AS name FROM calendar_unit WHERE list_kind='input' ORDER BY ordinal",
              )
              .map((r) => r['name']),
          form.units.map((u) => utf8.encode(u.name)),
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
  test('calendar optional epoch and original states remain distinct through replacement and restart', () {
    final root = Directory('/tmp').createTempSync('ub-calendar-optionals-');
    final path = '${root.path}/forms.sqlite', s = scope();
    var store = CalendarFormRecoveryStore.open(path), generation = BigInt.zero;
    try {
      for (final epoch in <String?>[null, '', '\ufeffEpoch']) {
        for (final hasEpoch in [true, false]) {
          final form = UnfinishedCalendarForm(
            baseRevision: RevisionId.generate(),
            representedContext: s.representedContext!,
            clientRef: s.typeClientRef!,
            hasEpoch: hasEpoch,
            epoch: '\ufeffInput',
            original: CalendarRecord(
              namespace: '',
              key: '',
              labels: {},
              epoch: epoch,
              unitStructure: {},
            ),
          );
          generation = store.save(s, form, generation).generation;
          store.close();
          store = CalendarFormRecoveryStore.open(path);
          expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
        }
      }
      final form = UnfinishedCalendarForm(
        baseRevision: RevisionId.generate(),
        representedContext: s.representedContext!,
        clientRef: s.typeClientRef!,
      );
      generation = store.save(s, form, generation).generation;
      store.close();
      store = CalendarFormRecoveryStore.open(path);
      expect(store.load(s)!.form.original, isNull);
      expect(store.load(s)!.generation, generation);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
