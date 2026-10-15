@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_source_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _LegacyForm._(JSObject _) implements JSObject {
  external factory _LegacyForm({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String label,
    required String text,
    required String rationale,
    String? draftVersion,
    String? anchorSource,
  });
  external String? get anchorSource;
  external String? get anchorRecord;
}

@JS()
extension type _LegacyOperation._(JSObject _) implements JSObject {
  external factory _LegacyOperation({
    required int ordinal,
    required String operation,
  });
  external String? get operation;
  external String? get byteSize;
  external String? get decodingLength;
}

Future<web.IDBDatabase> openDatabase(String name, [int? version]) async {
  final done = Completer<web.IDBDatabase>();
  final request = version == null
      ? web.window.indexedDB.open(name)
      : web.window.indexedDB.open(name, version);
  request.onupgradeneeded = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    db.createObjectStore('source_form');
    db.createObjectStore('source_operation');
  }).toJS;
  request.onsuccess = ((web.Event _) => done.complete(
    request.result as web.IDBDatabase,
  )).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('Fixture open failed'),
  )).toJS;
  return done.future;
}

List<JSAny> key(EditorFormScope s) => [
  s.instance.value.toJS,
  s.profile.value.toJS,
  s.universe.value.toJS,
  s.continuity.value.toJS,
  s.representedContext!.value.toJS,
  (s.typeClientRef ?? '').toJS,
];
Future<void> seed(
  String name,
  EditorFormScope s,
  UnfinishedSourceForm f, {
  bool malformed = false,
}) async {
  final db = await openDatabase(name, 1);
  try {
    final done = Completer<void>(),
        tx = db.transaction(
          ['source_form'.toJS, 'source_operation'.toJS].toJS,
          'readwrite',
        );
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onabort = ((web.Event _) => done.completeError(
      StateError('Fixture save failed'),
    )).toJS;
    tx
        .objectStore('source_form')
        .put(
          _LegacyForm(
            generation: '9007199254740993',
            baseRevision: f.baseRevision.value,
            representedContext: f.representedContext.value,
            clientRef: f.clientRef,
            label: f.label,
            text: f.text,
            rationale: f.rationale,
            draftVersion: f.draftVersion?.toString(),
            anchorSource: f.anchorSource?.toCanonical().toText(),
          ),
          key(s).toJS,
        );
    for (var i = 0; i < f.staged.length; i++) {
      tx
          .objectStore('source_operation')
          .put(
            _LegacyOperation(
              ordinal: i,
              operation: malformed && i == f.staged.length - 1
                  ? '{unfinished'
                  : f.staged[i].toWire().toText(),
            ),
            [...key(s), i.toJS].toJS,
          );
    }
    await done.future;
  } finally {
    db.close();
  }
}

Future<JSAny?> read(web.IDBDatabase db, String table, JSAny rowKey) async {
  final done = Completer<JSAny?>(), tx = db.transaction(table.toJS, 'readonly');
  final request = tx.objectStore(table).get(rowKey);
  tx.oncomplete = ((web.Event _) => done.complete(request.result)).toJS;
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
      'source upgrade ${malformed ? 'rolls back source and all child operations' : 'retains exact source versions, origins and both locator forms'}',
      () async {
        final name = 'ub-source-typed-${OperationId.generate().value}',
            universe = UniverseId.generate(),
            context = RecordId.generate(),
            max = (BigInt.one << 64) - BigInt.one;
        final s = EditorFormScope(
          instance: OperationId.generate(),
          profile: ProfileId.generate(),
          universe: universe,
          continuity: ContinuityId.generate(),
          representedContext: context,
          typeClientRef: '\ufeffDraft',
        );
        final ref = RecordId.generate(), version = RecordVersionId.generate();
        final pin = VersionRef(record: ref, version: version);
        final f = UnfinishedSourceForm(
          baseRevision: RevisionId.generate(),
          representedContext: context,
          clientRef: s.typeClientRef!,
          label: '\ufeffMemoir\r\n\u0000😀',
          text: '\ufeffExact\r\n\u0000😀',
          rationale: '\ufeffReason',
          draftVersion: max,
          anchorSource: pin,
          staged: [
            RecordNarrativeReferenceOperation(
              clientRef: '\ufeffSource',
              record: RecordKind.source,
              payload: SourceRecord(
                label: '\ufeffSource\r\n\u0000',
                externalId: '',
                origin: const OriginMetadata(
                  externallyAssertedAuthor: '\ufeffAuthor',
                  originNote: '',
                ),
                versions: [ref, ref],
              ),
            ),
            RecordNarrativeReferenceOperation(
              clientRef: '\ufeffVersion',
              record: RecordKind.sourceVersion,
              payload: SourceVersionRecord(
                source: RecordRef(record: ref, universe: universe),
                contentDigest: 'a' * 64,
                mediaType: 'text/plain',
                byteSize: max,
                importActor: PrincipalId.generate(),
                importTime: '\ufeffTime',
                decoding: DecodingDescriptor(
                  encoding: 'UTF-8',
                  representation: '\ufeffRepresentation',
                  byteLength: max,
                ),
                origin: const OriginMetadata(),
              ),
            ),
            AddSourceAnchorOperation(
              clientRef: '\ufeffAnchor',
              record: AnchorRecord(
                sourceVersion: pin,
                locator: StructuralPathLocator([
                  '',
                  '\ufeffPath\r\n\u0000😀',
                  '',
                ]),
                excerptDigest: 'b' * 64,
                excerpt: '\ufeffExcerpt',
                context: RecordRef(record: context),
              ),
            ),
            AddSourceAnchorOperation(
              clientRef: '\ufeffAnchor',
              record: AnchorRecord(
                sourceVersion: VersionRef(
                  record: ref,
                  version: version,
                  universe: universe,
                ),
                locator: ByteRangeLocator(
                  BigInt.parse('9007199254740993'),
                  max,
                ),
                excerptDigest: 'c' * 64,
                excerpt: '',
                context: null,
              ),
            ),
          ],
        );
        await seed(name, s, f, malformed: malformed);
        try {
          if (malformed) {
            await expectLater(
              BrowserSourceFormRecoveryStore.open(databaseName: name),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(name);
            try {
              expect(db.version, 1);
              final main =
                  await read(db, 'source_form', key(s).toJS) as _LegacyForm;
              expect(main.anchorSource, f.anchorSource!.toCanonical().toText());
              expect(main.anchorRecord, isNull);
              final first = await read(
                db,
                'source_operation',
                [...key(s), 0.toJS].toJS,
              ) as _LegacyOperation;
              expect(first.operation, f.staged.first.toWire().toText());
              final last = await read(
                db,
                'source_operation',
                [...key(s), 3.toJS].toJS,
              ) as _LegacyOperation;
              expect(last.operation, '{unfinished');
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserSourceFormRecoveryStore.open(
              databaseName: name,
            );
            try {
              final saved = (await store.load(s))!;
              expect(saved.generation, BigInt.parse('9007199254740993'));
              expect(saved.form.toWire().toText(), f.toWire().toText());
              final db = await openDatabase(name);
              try {
                expect(db.version, 2);
                final main =
                    await read(db, 'source_form', key(s).toJS) as _LegacyForm;
                expect(main.anchorSource, isNull);
                expect(main.anchorRecord, ref.value);
                final row = await read(
                  db,
                  'source_operation',
                  [...key(s), 1.toJS].toJS,
                ) as _LegacyOperation;
                expect(row.operation, isNull);
                expect(row.byteSize, max.toString());
                expect(row.decodingLength, max.toString());
              } finally {
                db.close();
              }
              await store.save(s, f, saved.generation);
              store.close();
              store = await BrowserSourceFormRecoveryStore.open(
                databaseName: name,
              );
              expect(
                (await store.load(s))!.form.toWire().toText(),
                f.toWire().toText(),
              );
              final empty = UnfinishedSourceForm(
                baseRevision: f.baseRevision,
                representedContext: context,
                clientRef: f.clientRef,
                draftVersion: max,
              );
              await store.save(s, empty, saved.generation + BigInt.one);
              expect(
                (await store.load(s))!.form.toWire().toText(),
                empty.toWire().toText(),
              );
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
