@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_communication_recovery.dart';
import 'package:ub_client/browser_observation_recovery.dart';
import 'package:ub_client/browser_memory_recovery.dart';
import 'package:ub_client/src/browser_input_fields.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _StoredRow._(JSObject _) implements JSObject {
  external String? get original;
  external JSObject? get originalFields;
}

List<JSAny> key(EditorFormScope s) => [
  s.instance.value.toJS,
  s.profile.value.toJS,
  s.universe.value.toJS,
  s.continuity.value.toJS,
  s.representedContext!.value.toJS,
  (s.typeClientRef ?? '').toJS,
];
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
);
RecordRef ref() =>
    RecordRef(record: RecordId.generate(), universe: UniverseId.generate());
TemporalExpression time() => ApproximateTime(
  CalendarId.generate(),
  '\ufeffCoordinate',
  SequenceValue([
    const RationalValue('900719925474099312345', '007'),
    TextValue('\ufeffAmount\r\n\u0000😀'),
  ]),
);
Future<web.IDBDatabase> openDatabase(
  String name,
  String table, [
  int? version,
]) async {
  final done = Completer<web.IDBDatabase>(),
      request = version == null
          ? web.window.indexedDB.open(name)
          : web.window.indexedDB.open(name, version);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore(table);
  }).toJS;
  request.onsuccess = ((web.Event _) => done.complete(
    request.result as web.IDBDatabase,
  )).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('Fixture failed'),
  )).toJS;
  return done.future;
}

Future<void> seed(
  String name,
  String table,
  List<(EditorFormScope, Map<String, Object?>)> rows,
) async {
  final db = await openDatabase(name, table, 1);
  try {
    final done = Completer<void>(),
        tx = db.transaction(table.toJS, 'readwrite');
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onabort = ((web.Event _) => done.completeError(
      StateError('Seed failed'),
    )).toJS;
    for (final (s, row) in rows) {
      tx.objectStore(table).put(row.jsify()!, key(s).toJS);
    }
    await done.future;
  } finally {
    db.close();
  }
}

Future<_StoredRow> _read(
  web.IDBDatabase db,
  String table,
  EditorFormScope s,
) async {
  final done = Completer<_StoredRow>(),
      tx = db.transaction(table.toJS, 'readonly'),
      request = tx.objectStore(table).get(key(s).toJS);
  tx.oncomplete = ((web.Event _) => done.complete(
    request.result as _StoredRow,
  )).toJS;
  tx.onabort = ((web.Event _) => done.completeError(
    StateError('Read failed'),
  )).toJS;
  return done.future;
}

Future<void> cleanup(String name) async {
  final done = Completer<void>(),
      request = web.window.indexedDB.deleteDatabase(name);
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('Cleanup failed'),
  )).toJS;
  await done.future;
}

void main() {
  for (final malformed in [false, true]) {
    test(
      'browser communication originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database =
                'ub-communication-typed-${OperationId.generate().value}',
            table = 'communication_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedCommunicationForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                sender: const ExpressionReferenceInput(record: '\ufeffSender'),
                intendedRecipients: const [
                  ExpressionReferenceInput(record: '\ufeffRecipient'),
                  ExpressionReferenceInput(),
                  ExpressionReferenceInput(record: '\ufeffRecipient'),
                ],
                actualRecipients: const [],
                content: const [ExpressionReferenceInput()],
                channelEnabled: true,
                channel: '\ufeffMail\r\n\u0000😀',
                distorted: i == 0
                    ? null
                    : i == 1
                    ? false
                    : true,
                sentAt: const TemporalValidityInput(kind: 'unfinished'),
                receivedEnabled: true,
                receivedAt: const TemporalValidityInput(
                  kind: 'instant_duration',
                  start: TemporalBoundInput(value: '\ufeffPending'),
                ),
                correctionTarget: const ExpressionReferenceInput(
                  record: '\ufeffCorrection',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                original: i == 0
                    ? null
                    : CommunicationRecord(
                        sender: ref(),
                        intendedRecipients: [repeated, repeated],
                        actualRecipients: [],
                        content: [ref(), ref()],
                        channel: i == 1 ? null : '',
                        sentAt: time(),
                        receivedAt: i == 1
                            ? null
                            : RelativeTime(
                                CalendarId.generate(),
                                TemporalRelation.after,
                                ref(),
                              ),
                        distorted: i == 2,
                      ),
              );
              return (s, f);
            })(),
        ];
        final rows = [
          for (final (s, f) in forms)
            (
              s,
              <String, Object?>{
                'generation': '9007199254740993',
                'baseRevision': f.baseRevision.value,
                'representedContext': f.representedContext.value,
                'clientRef': f.clientRef,
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'original': malformed && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
                'sender': encodeBrowserInput(f.sender.toWire()),
                'intendedRecipients': encodeBrowserInput(
                  CanonicalArray(f.intendedRecipients.map((r) => r.toWire())),
                ),
                'actualRecipients': encodeBrowserInput(
                  CanonicalArray(f.actualRecipients.map((r) => r.toWire())),
                ),
                'content': encodeBrowserInput(
                  CanonicalArray(f.content.map((r) => r.toWire())),
                ),
                'channelEnabled': f.channelEnabled,
                'channel': f.channel,
                'distorted': f.distorted,
                'sentAt': encodeBrowserInput(f.sentAt.toWire()),
                'receivedEnabled': f.receivedEnabled,
                'receivedAt': encodeBrowserInput(f.receivedAt.toWire()),
                'correctionTarget': encodeBrowserInput(
                  f.correctionTarget!.toWire(),
                ),
                'expectedRecordVersion': f.expectedRecordVersion!.value,
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserCommunicationFormRecoveryStore.open(
                databaseName: database,
              ),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(database, table);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, table, s);
                expect(
                  row.original,
                  f == forms.last.$2
                      ? '{unfinished'
                      : f.original?.toWire().toText(),
                );
                expect(row.originalFields, isNull);
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserCommunicationFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(
                  s,
                  f.copyWith(rationale: '\ufeffReplacement'),
                  saved.generation,
                );
              }
              store.close();
              store = await BrowserCommunicationFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.copyWith(rationale: '\ufeffReplacement').toWire().toText(),
                );
              }
              final db = await openDatabase(database, table);
              try {
                expect(db.version, 2);
                for (final (s, f) in forms) {
                  final row = await _read(db, table, s);
                  expect(row.original, isNull);
                  expect(
                    row.originalFields,
                    f.original == null ? isNull : isNotNull,
                  );
                }
              } finally {
                db.close();
              }
            } finally {
              store.close();
            }
          }
        } finally {
          await cleanup(database);
        }
      },
    );
    test(
      'browser observation originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-observation-typed-${OperationId.generate().value}',
            table = 'observation_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedObservationForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                observer: const ExpressionReferenceInput(
                  record: '\ufeffObserver',
                ),
                observed: const ExpressionReferenceInput(),
                sensoryAccess: i == 0
                    ? null
                    : i == 1
                    ? false
                    : true,
                time: const TemporalValidityInput(kind: 'unfinished'),
                interpretationEnabled: false,
                interpretation: const ExpressionReferenceInput(
                  record: '\ufeffDisabled',
                ),
                basis: const EvidenceBasisInput(
                  kind: 'source',
                  verified: false,
                  note: '\ufeffBasis',
                ),
                original: i == 0
                    ? null
                    : ObservationRecord(
                        observer: repeated,
                        observed: ref(),
                        sensoryAccess: i == 2,
                        time: time(),
                        interpretation: i == 1 ? null : ref(),
                        basis: i == 1
                            ? SourceAnchorBasis(ref(), false)
                            : DerivationBasis([
                                VersionRef(
                                  record: repeated.record,
                                  version: RecordVersionId.generate(),
                                ),
                                VersionRef(
                                  record: repeated.record,
                                  version: RecordVersionId.generate(),
                                ),
                              ], '\ufeffEvaluator\r\n\u0000😀'),
                      ),
              );
              return (s, f);
            })(),
        ];
        final rows = [
          for (final (s, f) in forms)
            (
              s,
              <String, Object?>{
                'generation': '9007199254740993',
                'baseRevision': f.baseRevision.value,
                'representedContext': f.representedContext.value,
                'clientRef': f.clientRef,
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'original': malformed && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
                'observer': encodeBrowserInput(f.observer.toWire()),
                'observed': encodeBrowserInput(f.observed.toWire()),
                'sensoryAccess': f.sensoryAccess,
                'time': encodeBrowserInput(f.time.toWire()),
                'interpretationEnabled': f.interpretationEnabled,
                'interpretation': encodeBrowserInput(f.interpretation.toWire()),
                'basis': encodeBrowserInput(f.basis.toWire()),
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserObservationFormRecoveryStore.open(databaseName: database),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(database, table);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, table, s);
                expect(
                  row.original,
                  f == forms.last.$2
                      ? '{unfinished'
                      : f.original?.toWire().toText(),
                );
                expect(row.originalFields, isNull);
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserObservationFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(
                  s,
                  f.copyWith(rationale: '\ufeffReplacement'),
                  saved.generation,
                );
              }
              store.close();
              store = await BrowserObservationFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.copyWith(rationale: '\ufeffReplacement').toWire().toText(),
                );
              }
              final db = await openDatabase(database, table);
              try {
                expect(db.version, 2);
                for (final (s, f) in forms) {
                  final row = await _read(db, table, s);
                  expect(row.original, isNull);
                  expect(
                    row.originalFields,
                    f.original == null ? isNull : isNotNull,
                  );
                }
              } finally {
                db.close();
              }
            } finally {
              store.close();
            }
          }
        } finally {
          await cleanup(database);
        }
      },
    );
    test(
      'browser memory originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-memory-typed-${OperationId.generate().value}',
            table = 'memory_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedMemoryForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                holder: const ExpressionReferenceInput(record: '\ufeffHolder'),
                content: const ExpressionReferenceInput(),
                altered: i == 0
                    ? null
                    : i == 1
                    ? false
                    : true,
                allegedEnabled: false,
                alleged: const ExpressionReferenceInput(
                  record: '\ufeffDisabled',
                ),
                accessibility: '\ufeffFragmented\r\n\u0000😀',
                validity: const TemporalValidityInput(kind: 'unfinished'),
                original: i == 0
                    ? null
                    : MemoryRecord(
                        holder: repeated,
                        content: ref(),
                        alleged: i == 1 ? null : ref(),
                        accessibility: '\ufeffOriginal\r\n\u0000😀',
                        altered: i == 2,
                        validity: InstantValidity(time()),
                      ),
              );
              return (s, f);
            })(),
        ];
        final rows = [
          for (final (s, f) in forms)
            (
              s,
              <String, Object?>{
                'generation': '9007199254740993',
                'baseRevision': f.baseRevision.value,
                'representedContext': f.representedContext.value,
                'clientRef': f.clientRef,
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'original': malformed && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
                'holder': encodeBrowserInput(f.holder.toWire()),
                'content': encodeBrowserInput(f.content.toWire()),
                'altered': f.altered,
                'allegedEnabled': f.allegedEnabled,
                'alleged': encodeBrowserInput(f.alleged.toWire()),
                'accessibility': f.accessibility,
                'validity': encodeBrowserInput(f.validity.toWire()),
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserMemoryFormRecoveryStore.open(databaseName: database),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(database, table);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, table, s);
                expect(
                  row.original,
                  f == forms.last.$2
                      ? '{unfinished'
                      : f.original?.toWire().toText(),
                );
                expect(row.originalFields, isNull);
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserMemoryFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(
                  s,
                  f.copyWith(rationale: '\ufeffReplacement'),
                  saved.generation,
                );
              }
              store.close();
              store = await BrowserMemoryFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.copyWith(rationale: '\ufeffReplacement').toWire().toText(),
                );
              }
              final db = await openDatabase(database, table);
              try {
                expect(db.version, 2);
                for (final (s, f) in forms) {
                  final row = await _read(db, table, s);
                  expect(row.original, isNull);
                  expect(
                    row.originalFields,
                    f.original == null ? isNull : isNotNull,
                  );
                }
              } finally {
                db.close();
              }
            } finally {
              store.close();
            }
          }
        } finally {
          await cleanup(database);
        }
      },
    );
  }
}
