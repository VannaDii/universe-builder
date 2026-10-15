@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_story_time_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _LegacyRow._(JSObject _) implements JSObject {
  external factory _LegacyRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String targetRecord,
    required String targetUniverse,
    required String expectedRecordVersion,
    required String original,
    required String value,
    required String mode,
    required String reason,
    required String rationale,
    String? draftVersion,
  });
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
Future<web.IDBDatabase> openDatabase(String name, [int? version]) async {
  final result = Completer<web.IDBDatabase>(),
      request = version == null
          ? web.window.indexedDB.open(name)
          : web.window.indexedDB.open(name, version);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore('story_time_form');
  }).toJS;
  request.onsuccess = ((web.Event _) => result.complete(
    request.result as web.IDBDatabase,
  )).toJS;
  request.onerror = ((web.Event _) => result.completeError(
    StateError('Fixture failed'),
  )).toJS;
  return result.future;
}

Future<void> seed(
  String name,
  List<(EditorFormScope, UnfinishedStoryTimeForm)> forms, {
  bool malformed = false,
}) async {
  final db = await openDatabase(name, 1);
  try {
    final tx = db.transaction('story_time_form'.toJS, 'readwrite'),
        done = Completer<void>();
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onabort = ((web.Event _) => done.completeError(
      StateError('Fixture failed'),
    )).toJS;
    for (final (s, f) in forms) {
      tx
          .objectStore('story_time_form')
          .put(
            _LegacyRow(
              generation: '9007199254740993',
              baseRevision: f.baseRevision.value,
              representedContext: f.representedContext.value,
              targetRecord: f.target.record,
              targetUniverse: f.target.universe,
              expectedRecordVersion: f.expectedRecordVersion.value,
              original: malformed && f == forms.last.$2
                  ? '{unfinished'
                  : f.original.toWire().toText(),
              value: f.value,
              mode: f.mode,
              reason: f.reason,
              rationale: f.rationale,
              draftVersion: f.draftVersion?.toString(),
            ),
            key(s).toJS,
          );
    }
    await done.future;
  } finally {
    db.close();
  }
}

Future<_LegacyRow> _read(web.IDBDatabase db, EditorFormScope s) async {
  final done = Completer<_LegacyRow>(),
      tx = db.transaction('story_time_form'.toJS, 'readonly'),
      request = tx.objectStore('story_time_form').get(key(s).toJS);
  tx.oncomplete = ((web.Event _) => done.complete(
    request.result as _LegacyRow,
  )).toJS;
  tx.onabort = ((web.Event _) => done.completeError(
    StateError('Fixture read failed'),
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
      'retained browser chronology ${malformed ? 'rolls back every legacy row on malformed input' : 'preserves clock variants and exact authored coordinates'}',
      () async {
        final name = 'ub-typed-clock-${OperationId.generate().value}';
        final systems = <ClockSystem>[
          GregorianClock(-2147483648),
          GregorianClock(2147483647),
          FictionalClock('\ufeffTicks\r\n\u0000😀', null),
          FictionalClock('', 0),
          FictionalClock('\ufeffTicks', 4294967295),
        ];
        final forms = [
          for (final clock in systems)
            (() {
              final s = EditorFormScope(
                instance: OperationId.generate(),
                profile: ProfileId.generate(),
                universe: UniverseId.generate(),
                continuity: ContinuityId.generate(),
                representedContext: RecordId.generate(),
              );
              final f = UnfinishedStoryTimeForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                target: ExpressionReferenceInput(
                  record: '\ufeffUnfinished',
                  universe: '',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                original: Chronology(
                  calendar: CalendarId.generate(),
                  system: clock,
                  firstInteraction: '\ufeffFirst\r\n\u0000😀',
                  current: '170141183460469231731687303715884105727',
                ),
                value: '\ufeffPending\r\n\u0000😀',
                mode: '',
                reason: '\ufeffReason',
                rationale: '',
                draftVersion: (BigInt.one << 64) - BigInt.one,
              );
              return (s, f);
            })(),
        ];
        await seed(name, forms, malformed: malformed);
        try {
          if (malformed) {
            await expectLater(
              BrowserStoryTimeFormRecoveryStore.open(databaseName: name),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(name);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, s);
                expect(
                  row.original,
                  f == forms.last.$2
                      ? '{unfinished'
                      : f.original.toWire().toText(),
                );
                expect(row.originalFields, isNull);
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserStoryTimeFormRecoveryStore.open(
              databaseName: name,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(
                  s,
                  f.copyWith(value: '\ufeffChanged\r\n\u0000'),
                  saved.generation,
                );
              }
              store.close();
              store = await BrowserStoryTimeFormRecoveryStore.open(
                databaseName: name,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f
                      .copyWith(value: '\ufeffChanged\r\n\u0000')
                      .toWire()
                      .toText(),
                );
              }
              final db = await openDatabase(name);
              try {
                expect(db.version, 2);
                for (final (s, _) in forms) {
                  final row = await _read(db, s);
                  expect(row.original, isNull);
                  expect(row.originalFields, isNotNull);
                }
              } finally {
                db.close();
              }
            } finally {
              store.close();
            }
          }
        } finally {
          await cleanup(name);
        }
      },
    );
  }
}
