import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';

final class BrowserSourceFormRecovery {
  const BrowserSourceFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserSourceFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedSourceForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedSourceForm> save(
    EditorFormScope scope,
    UnfinishedSourceForm form,
    BigInt expectedGeneration,
  ) {
    // A disconnected writer can retain input without acquiring service authority.
    if (scope.profile != principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    return store.save(scope, form, expectedGeneration);
  }
}

@JS()
extension type _SourceRow._(JSObject _) implements JSObject {
  external factory _SourceRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String label,
    required String text,
    required String rationale,
    String? draftVersion,
    String? anchorRecord,
    String? anchorVersion,
    String? anchorUniverse,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get label;
  external String get text;
  external String get rationale;
  external String? get draftVersion;
  external String? get anchorRecord;
  external String? get anchorVersion;
  external String? get anchorUniverse;
  external String? get anchorSource;
}

@JS()
extension type _OperationRow._(JSObject _) implements JSObject {
  external factory _OperationRow({
    required int ordinal,
    required String kind,
    required String clientRef,
    String? label,
    String? externalId,
    String? originAuthor,
    String? originNote,
    String? sourceRecord,
    String? sourceUniverse,
    String? contentDigest,
    String? mediaType,
    String? byteSize,
    String? importActor,
    String? importTime,
    String? encoding,
    String? representation,
    String? decodingLength,
    String? pinRecord,
    String? pinVersion,
    String? pinUniverse,
    String? locatorKind,
    String? rangeStart,
    String? rangeEnd,
    String? excerptDigest,
    String? excerpt,
    String? contextRecord,
    String? contextUniverse,
    JSArray<JSString>? versions,
    JSArray<JSString>? path,
  });
  external int get ordinal;
  external String get kind;
  external String get clientRef;
  external String? get label;
  external String? get externalId;
  external String? get originAuthor;
  external String? get originNote;
  external String? get sourceRecord;
  external String? get sourceUniverse;
  external String? get contentDigest;
  external String? get mediaType;
  external String? get byteSize;
  external String? get importActor;
  external String? get importTime;
  external String? get encoding;
  external String? get representation;
  external String? get decodingLength;
  external String? get pinRecord;
  external String? get pinVersion;
  external String? get pinUniverse;
  external String? get locatorKind;
  external String? get rangeStart;
  external String? get rangeEnd;
  external String? get excerptDigest;
  external String? get excerpt;
  external String? get contextRecord;
  external String? get contextUniverse;
  external JSArray<JSString>? get versions;
  external JSArray<JSString>? get path;
  external String get operation;
}

_OperationRow _encodeOperation(int ordinal, DomainOperation operation) {
  final RecordPayload payload;
  final String clientRef;
  switch (operation) {
    case AddSourceAnchorOperation(:final record, clientRef: final ref):
      payload = record;
      clientRef = ref;
    case RecordNarrativeReferenceOperation(
          :final record,
          payload: final body,
          clientRef: final ref,
        )
        when (body is SourceRecord || body is SourceVersionRecord) &&
            record == body.recordKind:
      payload = body;
      clientRef = ref;
    default:
      throw const FormatException(
        'Expected a staged source, source version or anchor.',
      );
  }
  switch (payload) {
    case SourceRecord():
      return _OperationRow(
        ordinal: ordinal,
        kind: 'source',
        clientRef: clientRef,
        label: payload.label,
        externalId: payload.externalId,
        originAuthor: payload.origin.externallyAssertedAuthor,
        originNote: payload.origin.originNote,
        versions: payload.versions.map((id) => id.value.toJS).toList().toJS,
      );
    case SourceVersionRecord():
      return _OperationRow(
        ordinal: ordinal,
        kind: RecordKind.sourceVersion.wireName,
        clientRef: clientRef,
        sourceRecord: payload.source.record.value,
        sourceUniverse: payload.source.universe?.value,
        contentDigest: payload.contentDigest,
        mediaType: payload.mediaType,
        byteSize: payload.byteSize.toString(),
        importActor: payload.importActor.value,
        importTime: payload.importTime,
        encoding: payload.decoding.encoding,
        representation: payload.decoding.representation,
        decodingLength: payload.decoding.byteLength.toString(),
        originAuthor: payload.origin.externallyAssertedAuthor,
        originNote: payload.origin.originNote,
      );
    case AnchorRecord():
      final locator = payload.locator;
      return _OperationRow(
        ordinal: ordinal,
        kind: 'anchor',
        clientRef: clientRef,
        pinRecord: payload.sourceVersion.record.value,
        pinVersion: payload.sourceVersion.version.value,
        pinUniverse: payload.sourceVersion.universe?.value,
        excerptDigest: payload.excerptDigest,
        excerpt: payload.excerpt,
        contextRecord: payload.context?.record.value,
        contextUniverse: payload.context?.universe?.value,
        locatorKind: locator is ByteRangeLocator
            ? 'byte_range'
            : 'structural_path',
        rangeStart: locator is ByteRangeLocator
            ? locator.start.toString()
            : null,
        rangeEnd: locator is ByteRangeLocator ? locator.end.toString() : null,
        path: locator is StructuralPathLocator
            ? locator.path.map((p) => p.toJS).toList().toJS
            : null,
      );
    default:
      throw const FormatException('Expected a source or anchor payload.');
  }
}

DomainOperation _decodeOperation(_OperationRow row) {
  final kind = RecordKind.parse(row.kind);
  OriginMetadata origin() => OriginMetadata(
    externallyAssertedAuthor: row.originAuthor,
    originNote: row.originNote,
  );
  final RecordPayload payload;
  switch (kind) {
    case RecordKind.source:
      payload = SourceRecord(
        label: row.label!,
        externalId: row.externalId,
        origin: origin(),
        versions: row.versions!.toDart.map((v) => RecordId.parse(v.toDart)),
      );
    case RecordKind.sourceVersion:
      payload = SourceVersionRecord(
        source: RecordRef(
          record: RecordId.parse(row.sourceRecord!),
          universe: row.sourceUniverse == null
              ? null
              : UniverseId.parse(row.sourceUniverse!),
        ),
        contentDigest: row.contentDigest!,
        mediaType: row.mediaType!,
        byteSize: BigInt.parse(row.byteSize!),
        importActor: PrincipalId.parse(row.importActor!),
        importTime: row.importTime!,
        decoding: DecodingDescriptor(
          encoding: row.encoding!,
          representation: row.representation!,
          byteLength: BigInt.parse(row.decodingLength!),
        ),
        origin: origin(),
      );
    case RecordKind.anchor:
      final locator = switch (row.locatorKind) {
        'byte_range' => ByteRangeLocator(
          BigInt.parse(row.rangeStart!),
          BigInt.parse(row.rangeEnd!),
        ),
        'structural_path' => StructuralPathLocator(
          row.path!.toDart.map((v) => v.toDart),
        ),
        _ => throw const FormatException('Unknown source anchor locator.'),
      };
      return AddSourceAnchorOperation(
        clientRef: row.clientRef,
        record: AnchorRecord(
          sourceVersion: VersionRef(
            record: RecordId.parse(row.pinRecord!),
            version: RecordVersionId.parse(row.pinVersion!),
            universe: row.pinUniverse == null
                ? null
                : UniverseId.parse(row.pinUniverse!),
          ),
          locator: locator,
          excerptDigest: row.excerptDigest!,
          excerpt: row.excerpt!,
          context: row.contextRecord == null
              ? null
              : RecordRef(
                  record: RecordId.parse(row.contextRecord!),
                  universe: row.contextUniverse == null
                      ? null
                      : UniverseId.parse(row.contextUniverse!),
                ),
        ),
      );
    default:
      throw const FormatException('Unknown staged source record.');
  }
  return RecordNarrativeReferenceOperation(
    clientRef: row.clientRef,
    record: kind,
    payload: payload,
  );
}

_SourceRow _encodeSource(SavedSourceForm saved) {
  final form = saved.form;
  return _SourceRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    clientRef: form.clientRef,
    label: form.label,
    text: form.text,
    rationale: form.rationale,
    draftVersion: form.draftVersion?.toString(),
    anchorRecord: form.anchorSource?.record.value,
    anchorVersion: form.anchorSource?.version.value,
    anchorUniverse: form.anchorSource?.universe?.value,
  );
}

SavedSourceForm _decodeSource(
  _SourceRow row,
  Iterable<DomainOperation> operations, {
  bool legacy = false,
}) => SavedSourceForm(
  generation: BigInt.parse(row.generation),
  form: UnfinishedSourceForm(
    baseRevision: RevisionId.parse(row.baseRevision),
    representedContext: RecordId.parse(row.representedContext),
    clientRef: row.clientRef,
    label: row.label,
    text: row.text,
    rationale: row.rationale,
    draftVersion: row.draftVersion == null
        ? null
        : BigInt.parse(row.draftVersion!),
    staged: operations,
    anchorSource: legacy
        ? (row.anchorSource == null
              ? null
              : VersionRef.fromCanonical(
                  CanonicalValue.parseWireJson(row.anchorSource!),
                ))
        : row.anchorRecord == null
        ? null
        : VersionRef(
            record: RecordId.parse(row.anchorRecord!),
            version: RecordVersionId.parse(row.anchorVersion!),
            universe: row.anchorUniverse == null
                ? null
                : UniverseId.parse(row.anchorUniverse!),
          ),
  ),
);

/// Named fields and ordered child rows, never a serialized UI-state blob.
/// IndexedDB transactions compare generations and commit all children together.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserSourceFormRecoveryStore {
  BrowserSourceFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['source_form', 'source_operation'];

  static Future<BrowserSourceFormRecoveryStore> open({
    String databaseName = 'ub-source-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserSourceFormRecoveryStore>();
      final request = web.window.indexedDB.open(databaseName, 2);
      void fail() {
        if (!result.isCompleted) {
          result.completeError(
            const EditorRecoveryException(EditorRecoveryFailure.unavailable),
          );
        }
      }

      request.onupgradeneeded = ((web.Event event) {
        final db = request.result as web.IDBDatabase, tx = request.transaction!;
        try {
          if ((event as web.IDBVersionChangeEvent).oldVersion == 0) {
            for (final name in _tables) {
              db.createObjectStore(name);
            }
          } else {
            void migrate(String table, JSAny Function(JSAny) convert) {
              final scan = tx.objectStore(table).openCursor();
              scan.onsuccess = ((web.Event _) {
                try {
                  if (scan.result == null || scan.result.isUndefined) return;
                  final cursor = scan.result as web.IDBCursorWithValue;
                  cursor.update(convert(cursor.value!));
                  cursor.continue_();
                } catch (_) {
                  tx.abort();
                }
              }).toJS;
            }

            migrate(
              _tables[0],
              (value) => _encodeSource(
                _decodeSource(value as _SourceRow, [], legacy: true),
              ),
            );
            migrate(_tables[1], (value) {
              final row = value as _OperationRow;
              return _encodeOperation(
                row.ordinal,
                DomainOperation.fromWire(
                  CanonicalValue.parseWireJson(row.operation),
                ),
              );
            });
          }
        } catch (_) {
          tx.abort();
        }
      }).toJS;
      request.onerror = ((web.Event _) => fail()).toJS;
      request.onblocked = ((web.Event _) => fail()).toJS;
      request.onsuccess = ((web.Event _) {
        final db = request.result as web.IDBDatabase;
        if (result.isCompleted) {
          db.close();
          return;
        }
        if (_tables.any((name) => !db.objectStoreNames.contains(name))) {
          db.close();
          result.completeError(
            const EditorRecoveryException(
              EditorRecoveryFailure.incompatibleSchema,
            ),
          );
          return;
        }
        db.onversionchange = ((web.Event _) => db.close()).toJS;
        result.complete(BrowserSourceFormRecoveryStore._(db));
      }).toJS;
      return await result.future;
    } on EditorRecoveryException {
      rethrow;
    } on Object {
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  List<JSAny> _binding(EditorFormScope scope) {
    if (scope.representedContext == null ||
        scope.worldClientRef != null ||
        scope.worldRecord != null ||
        scope.entityClientRef != null ||
        scope.entityNameRecord != null ||
        scope.entityClassificationRecord != null ||
        scope.entityOperationIndex != null ||
        scope.attributeClientRef != null) {
      throw const FormatException('Choose the source import context.');
    }
    return [
      scope.instance.value.toJS,
      scope.profile.value.toJS,
      scope.universe.value.toJS,
      scope.continuity.value.toJS,
      scope.representedContext!.value.toJS,
      (scope.typeClientRef ?? '').toJS,
    ];
  }

  web.IDBKeyRange _children(List<JSAny> key) => web.IDBKeyRange.bound(
    key.toJS,
    [...key, <JSAny>[].toJS].toJS,
    false,
    true,
  );

  SavedSourceForm? _read(web.IDBRequest main, web.IDBRequest labels) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _SourceRow;
    final operationRows = (labels.result as JSArray<_OperationRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    for (var i = 0; i < operationRows.length; i++) {
      if (operationRows[i].ordinal != i) {
        throw const FormatException('Incomplete source operation order');
      }
    }
    return _decodeSource(row, operationRows.map(_decodeOperation));
  }

  Future<SavedSourceForm?> load(EditorFormScope scope) {
    final result = Completer<SavedSourceForm?>();
    try {
      final key = _binding(scope), range = _children(_binding(scope));
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readonly',
      );
      final main = tx.objectStore(_tables[0]).get(key.toJS);
      final labels = tx.objectStore(_tables[1]).getAll(range);
      tx.oncomplete = ((web.Event _) {
        try {
          result.complete(_read(main, labels));
        } on Object {
          result.completeError(
            const EditorRecoveryException(EditorRecoveryFailure.unavailable),
          );
        }
      }).toJS;
      tx.onabort = ((web.Event _) {
        result.completeError(
          const EditorRecoveryException(EditorRecoveryFailure.unavailable),
        );
      }).toJS;
    } on Object {
      result.completeError(
        const EditorRecoveryException(EditorRecoveryFailure.unavailable),
      );
    }
    return result.future;
  }

  Future<SavedSourceForm> save(
    EditorFormScope scope,
    UnfinishedSourceForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef !=
                (form.draftVersion == null
                    ? (form.anchorSource?.version.value ?? form.clientRef)
                    : form.clientRef))) {
      throw const FormatException('Source import form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedSourceForm>();
    SavedSourceForm? saved;
    EditorRecoveryException? failure;
    try {
      final key = _binding(scope), range = _children(_binding(scope));
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readwrite',
        web.IDBTransactionOptions(durability: 'strict'),
      );
      final primary = tx.objectStore(_tables[0]),
          labelStore = tx.objectStore(_tables[1]);
      final main = primary.get(key.toJS), labels = labelStore.getAll(range);
      // Queue writes synchronously in the final read's success callback, while
      // the transaction is active; awaiting a later task could auto-commit it.
      labels.onsuccess = ((web.Event _) {
        try {
          final current = _read(main, labels),
              generation = current?.generation ?? BigInt.zero;
          if (generation != expectedGeneration) {
            if (generation == expectedGeneration + BigInt.one &&
                current!.form.toWire().toText() == form.toWire().toText()) {
              saved = current;
              return;
            }
            throw const EditorRecoveryException(EditorRecoveryFailure.conflict);
          }
          if (generation == (BigInt.one << 64) - BigInt.one) {
            throw const EditorRecoveryException(
              EditorRecoveryFailure.generationExhausted,
            );
          }
          saved = SavedSourceForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeSource(saved!), key.toJS);
          labelStore.delete(range);
          for (var i = 0; i < form.staged.length; i++) {
            labelStore.put(
              _encodeOperation(i, form.staged[i]),
              [...key, i.toJS].toJS,
            );
          }
        } on Object catch (error) {
          failure = error is EditorRecoveryException
              ? error
              : const EditorRecoveryException(
                  EditorRecoveryFailure.unavailable,
                );
          tx.abort();
        }
      }).toJS;
      tx.oncomplete = ((web.Event _) => result.complete(saved!)).toJS;
      tx.onabort = ((web.Event _) => result.completeError(
        failure ??
            const EditorRecoveryException(EditorRecoveryFailure.unavailable),
      )).toJS;
    } on Object {
      result.completeError(
        const EditorRecoveryException(EditorRecoveryFailure.unavailable),
      );
    }
    return result.future;
  }

  void close() => _db.close();
}
