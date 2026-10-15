@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_represented_context_recovery.dart';
import 'package:ub_client/src/browser_input_fields.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _LegacyRow._(JSObject _) implements JSObject {
  external factory _LegacyRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String universe,
    required String clientRef,
    required String kind,
    required String authoredLabel,
    required JSAny reference,
    required bool parentEnabled,
    required JSAny parent,
    required JSAny chronology,
    required JSAny labels,
    required String rationale,
    String? draftVersion,
    String? original,
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
  final done = Completer<web.IDBDatabase>(),
      request = version == null
          ? web.window.indexedDB.open(name)
          : web.window.indexedDB.open(name, version);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore(
      'represented_context_form',
    );
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
  List<(EditorFormScope, UnfinishedRepresentedContextForm)> forms, {
  bool malformed = false,
}) async {
  final db = await openDatabase(name, 1);
  try {
    final tx = db.transaction('represented_context_form'.toJS, 'readwrite'),
        done = Completer<void>();
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onabort = ((web.Event _) => done.completeError(
      StateError('Fixture save failed'),
    )).toJS;
    for (final (s, f) in forms) {
      tx
          .objectStore('represented_context_form')
          .put(
            _LegacyRow(
              generation: '9007199254740993',
              baseRevision: f.baseRevision.value,
              representedContext: f.representedContext.value,
              universe: f.universe.value,
              clientRef: f.clientRef,
              kind: f.kind,
              authoredLabel: f.authoredLabel,
              reference: encodeBrowserInput(f.reference.toWire())!,
              parentEnabled: f.parentEnabled,
              parent: encodeBrowserInput(f.parent.toWire())!,
              chronology: encodeBrowserInput(f.chronology.toWire())!,
              labels: encodeBrowserInput(
                CanonicalArray(f.labels.map((l) => l.toWire())),
              )!,
              rationale: f.rationale,
              draftVersion: f.draftVersion?.toString(),
              original: malformed && f == forms.last.$2
                  ? '{unfinished'
                  : f.original?.toWire().toText(),
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
      tx = db.transaction('represented_context_form'.toJS, 'readonly'),
      request = tx.objectStore('represented_context_form').get(key(s).toJS);
  tx.oncomplete = ((web.Event _) => done.complete(
    request.result as _LegacyRow,
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
      'browser context conversion ${malformed ? 'rolls back all old originals' : 'preserves nullable originals and exact retained context records'}',
      () async {
        final name = 'ub-typed-context-${OperationId.generate().value}';
        final kinds = <RepresentedContextKind?>[
          null,
          const ObjectiveContext(),
          CharacterContext(RecordRef(record: RecordId.generate())),
          SourceContext(
            RecordRef(
              record: RecordId.generate(),
              universe: UniverseId.generate(),
            ),
          ),
          NarratorContext(RecordRef(record: RecordId.generate())),
          const AuthoredContext('\ufeffAccount\r\n\u0000😀'),
        ];
        final forms = [
          for (final kind in kinds)
            (() {
              final s = EditorFormScope(
                instance: OperationId.generate(),
                profile: ProfileId.generate(),
                universe: UniverseId.generate(),
                continuity: ContinuityId.generate(),
                representedContext: RecordId.generate(),
              );
              final f = UnfinishedRepresentedContextForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                universe: s.universe,
                clientRef: '\ufeffContext',
                authoredLabel: '\ufeffInput\r\n\u0000😀',
                reference: const ExpressionReferenceInput(
                  record: '\ufeffUnfinished',
                ),
                chronology: const ChronologyInput(
                  current: 'unfinished',
                  tickLabel: '\ufeffInput',
                ),
                labels: const [
                  PropertyLabelInput(language: '', text: '\ufeffLabel'),
                  PropertyLabelInput(),
                ],
                rationale: '\ufeffReason',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                original: kind == null
                    ? null
                    : RepresentedContextRecord(
                        universe: s.universe,
                        kind: kind,
                        parent: kind is ObjectiveContext
                            ? null
                            : RecordRef(
                                record: RecordId.generate(),
                                universe: s.universe,
                              ),
                        labels: {'': '', '\ufeffen': '\ufeffName\r\n\u0000😀'},
                        chronology: kind is ObjectiveContext
                            ? null
                            : Chronology(
                                calendar: CalendarId.generate(),
                                system: GregorianClock(-3600),
                                firstInteraction: '\ufeffAuthored',
                                current: '9007199254740993123456789',
                              ),
                      ),
              );
              return (s, f);
            })(),
        ];
        await seed(name, forms, malformed: malformed);
        try {
          if (malformed) {
            await expectLater(
              BrowserRepresentedContextFormRecoveryStore.open(
                databaseName: name,
              ),
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
                      : f.original?.toWire().toText(),
                );
                expect(row.originalFields, isNull);
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserRepresentedContextFormRecoveryStore.open(
              databaseName: name,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(
                  s,
                  f.copyWith(authoredLabel: '\ufeffReplaced'),
                  saved.generation,
                );
              }
              store.close();
              store = await BrowserRepresentedContextFormRecoveryStore.open(
                databaseName: name,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.copyWith(authoredLabel: '\ufeffReplaced').toWire().toText(),
                );
              }
              final db = await openDatabase(name);
              try {
                expect(db.version, 2);
                for (final (s, f) in forms) {
                  final row = await _read(db, s);
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
          await cleanup(name);
        }
      },
    );
  }
}
