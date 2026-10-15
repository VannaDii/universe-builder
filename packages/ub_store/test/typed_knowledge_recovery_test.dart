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
  typeClientRef: '\ufeffPending knowledge input',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
const pendingTime = TemporalValidityInput(
  kind: 'pending',
  calendar: '\ufeffCalendar',
  relation: 'before?',
  targetRecord: 'disabled target',
  start: TemporalBoundInput(
    kind: 'unknown',
    value: 'disabled start',
    upper: '\ufeffUpper',
    amount: QualifierInput(kind: 'rational', value: '3', denominator: '0'),
  ),
);
const reason = '\ufeffReason\r\n\u0000記憶😀';
dynamic open(String kind, String path) => switch (kind) {
  'communication' => CommunicationFormRecoveryStore.open(path),
  'observation' => ObservationFormRecoveryStore.open(path),
  'memory' => MemoryFormRecoveryStore.open(path),
  _ => throw StateError('Unknown form'),
};
dynamic input(
  String kind,
  EditorFormScope s, {
  bool empty = false,
  bool? flag = false,
}) {
  final base = RevisionId.generate(),
      ref = RecordRef(record: RecordId.generate(), universe: s.universe),
      calendar = CalendarId.generate();
  final time = ApproximateTime(
    calendar,
    '\ufeffCoordinate',
    SequenceValue([
      const RationalValue('9007199254740997', '3'),
      const TextValue('\ufeffUncertainty'),
    ]),
  );
  switch (kind) {
    case 'communication':
      return empty
          ? UnfinishedCommunicationForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              distorted: flag,
            )
          : UnfinishedCommunicationForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              sender: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffSender universe',
              ),
              intendedRecipients: const [
                ExpressionReferenceInput(record: '\ufeffRecipient'),
                ExpressionReferenceInput(),
                ExpressionReferenceInput(record: '\ufeffRecipient'),
              ],
              actualRecipients: const [
                ExpressionReferenceInput(record: '\ufeffActual'),
                ExpressionReferenceInput(record: '\ufeffActual'),
              ],
              content: const [
                ExpressionReferenceInput(),
                ExpressionReferenceInput(record: '\ufeffContent'),
              ],
              channelEnabled: false,
              channel: '\ufeffDisabled channel',
              distorted: flag,
              sentAt: pendingTime,
              receivedEnabled: false,
              receivedAt: pendingTime,
              rationale: reason,
              draftVersion: maxU64,
              correctionTarget: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffPending target universe',
              ),
              expectedRecordVersion: RecordVersionId.generate(),
              original: CommunicationRecord(
                sender: ref,
                intendedRecipients: [
                  ref,
                  ref,
                  RecordRef(record: ref.record),
                ],
                actualRecipients: [ref, ref],
                content: [ref, ref],
                channel: flag == true ? '' : null,
                sentAt: time,
                receivedAt: flag == true
                    ? ExactTime(calendar, '\ufeffReceived')
                    : null,
                distorted: flag ?? false,
              ),
            );
    case 'observation':
      return empty
          ? UnfinishedObservationForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              sensoryAccess: flag,
            )
          : UnfinishedObservationForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              observer: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffObserver universe',
              ),
              observed: const ExpressionReferenceInput(
                record: '\ufeffObserved',
                universe: '',
              ),
              sensoryAccess: flag,
              time: pendingTime,
              interpretationEnabled: false,
              interpretation: const ExpressionReferenceInput(
                record: 'disabled interpretation',
                universe: 'disabled universe',
              ),
              basis: const EvidenceBasisInput(
                kind: 'pending',
                note: '\ufeffNote\r\n\u0000😀',
                anchorRecord: '',
                anchorUniverse: 'disabled',
                verified: true,
              ),
              rationale: reason,
              draftVersion: maxU64,
              original: ObservationRecord(
                observer: ref,
                observed: RecordRef(record: ref.record),
                sensoryAccess: flag ?? false,
                time: time,
                interpretation: flag == true ? ref : null,
                basis: DerivationBasis([
                  VersionRef(
                    record: ref.record,
                    version: RecordVersionId.generate(),
                    universe: s.universe,
                  ),
                ], '\ufeffEvaluator'),
              ),
            );
    case 'memory':
      return empty
          ? UnfinishedMemoryForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              altered: flag,
            )
          : UnfinishedMemoryForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              holder: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffHolder universe',
              ),
              content: const ExpressionReferenceInput(
                record: '\ufeffRemembered',
                universe: '',
              ),
              altered: flag,
              validity: pendingTime,
              allegedEnabled: false,
              alleged: const ExpressionReferenceInput(
                record: 'disabled alleged',
                universe: 'disabled universe',
              ),
              accessibility: '\ufeffAccessibility',
              rationale: reason,
              draftVersion: maxU64,
              original: MemoryRecord(
                holder: ref,
                content: RecordRef(record: ref.record),
                alleged: flag == true ? ref : null,
                accessibility: '\ufeffOriginal accessibility\r\n\u0000😀',
                altered: flag ?? false,
                validity: InstantValidity(time),
              ),
            );
    default:
      throw StateError('Unknown form');
  }
}

void legacy(
  String kind,
  String path,
  List<(EditorFormScope, BigInt, String)> entries,
) {
  protectedFile(path, create: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE ${kind}_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, g, text) in entries) {
      db.execute('INSERT INTO ${kind}_form VALUES(?,?,?,?,?,?,?,?)', [
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
  for (final kind in ['communication', 'observation', 'memory']) {
    test(
      '$kind typed recovery retains disabled inputs and original records while preserving unset versus explicit boolean choices',
      () {
        final root = Directory('/tmp').createTempSync('ub-typed-$kind-'),
            s = scope();
        final path = '${root.path}/forms.sqlite';
        dynamic store = open(kind, path);
        var generation = BigInt.zero;
        try {
          for (final flag in <bool?>[null, false, true]) {
            final dynamic form = input(kind, s, flag: flag);
            generation = store.save(s, form, generation).generation as BigInt;
            store.close();
            store = open(kind, path);
            expect(
              store.load(s).form.toWire().toText(),
              form.toWire().toText(),
            );
            expect(
              store.save(s, form, generation - BigInt.one).generation,
              generation,
            );
          }
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(
              db
                  .select('PRAGMA table_info(${kind}_form)')
                  .map((r) => r['name']),
              isNot(contains('form_input')),
            );
            expect(db.select('PRAGMA foreign_key_check'), isEmpty);
          } finally {
            db.close();
          }
        } finally {
          store.close();
          root.deleteSync(recursive: true);
        }
      },
    );
    test(
      '$kind replacement removes superseded original records and nested inputs',
      () {
        final root = Directory('/tmp').createTempSync('ub-$kind-clear-'),
            s = scope();
        final path = '${root.path}/forms.sqlite';
        final dynamic form = input(kind, s),
            empty = input(kind, s, empty: true);
        dynamic store = open(kind, path);
        try {
          store.save(s, form, BigInt.zero);
          store.save(s, form, BigInt.one);
          store.save(s, empty, BigInt.two);
          store.close();
          store = open(kind, path);
          expect(store.load(s).form.toWire().toText(), empty.toWire().toText());
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            final n = kind == 'communication' ? 2 : 1;
            for (final row in db.select(
              "SELECT name FROM sqlite_master WHERE type='table' AND name!='${kind}_form'",
            )) {
              expect(
                db
                    .select('SELECT count(*) AS n FROM "${row['name']}"')
                    .single['n'],
                row['name'] == '${kind}_temporal'
                    ? n
                    : row['name'] == '${kind}_bound'
                    ? 2 * n
                    : 0,
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
      },
    );
    test(
      '$kind conversion preserves isolated recovery slots, generations, retries and save conflicts',
      () {
        final root = Directory('/tmp').createTempSync('ub-$kind-conversion-'),
            s = scope(),
            second = scope();
        final path = '${root.path}/forms.sqlite';
        final dynamic form = input(kind, s),
            other = input(kind, second, flag: true);
        legacy(kind, path, [
          (s, BigInt.from(19), form.toWire().toText() as String),
          (second, maxU64, other.toWire().toText() as String),
        ]);
        final dynamic store = open(kind, path), competing = open(kind, path);
        try {
          expect(store.load(s).form.toWire().toText(), form.toWire().toText());
          expect(
            store.load(second).form.toWire().toText(),
            other.toWire().toText(),
          );
          final dynamic changed = input(kind, s, empty: true);
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
          expect(
            store.load(second).form.toWire().toText(),
            other.toWire().toText(),
          );
        } finally {
          competing.close();
          store.close();
          root.deleteSync(recursive: true);
        }
      },
    );
    test(
      '$kind failed conversion rolls back typed rows and retains every legacy unfinished form',
      () {
        final root = Directory('/tmp').createTempSync('ub-$kind-rollback-'),
            s = scope(),
            second = scope();
        final path = '${root.path}/forms.sqlite',
            text = input(kind, s).toWire().toText() as String;
        legacy(kind, path, [
          (s, BigInt.one, text),
          (second, BigInt.two, '{unfinished'),
        ]);
        try {
          expect(
            () => open(kind, path),
            throwsA(isA<EditorRecoveryException>()),
          );
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(db.select('PRAGMA user_version').single.values.single, 1);
            expect(
              db
                  .select(
                    'SELECT form_input FROM ${kind}_form ORDER BY generation',
                  )
                  .map((r) => r['form_input']),
              [text, '{unfinished'],
            );
            expect(
              db
                  .select("SELECT name FROM sqlite_master WHERE type='table'")
                  .map((r) => r['name']),
              ['${kind}_form'],
            );
          } finally {
            db.close();
          }
        } finally {
          root.deleteSync(recursive: true);
        }
      },
    );
  }
}
