import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserSecretFormRecovery {
  const BrowserSecretFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserSecretFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedSecretForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedSecretForm> save(
    EditorFormScope scope,
    UnfinishedSecretForm form,
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
extension type _SecretRow._(JSObject _) implements JSObject {
  external factory _SecretRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String concealment,
    required String validityKind,
    required String calendar,
    required String start,
    required String end,
    required String rationale,
    required bool hasConcealment,
    required bool startUnbounded,
    required bool endUnbounded,
    bool? readerDisclosed,
    String? targetRecord,
    String? targetUniverse,
    String? expectedRecordVersion,
    JSAny? originalFields,
    String? draftVersion,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get concealment;
  external String get validityKind;
  external String get calendar;
  external String get start;
  external String get end;
  external String get rationale;
  external bool get hasConcealment;
  external bool get startUnbounded;
  external bool get endUnbounded;
  external bool? get readerDisclosed;
  external String? get targetRecord;
  external String? get targetUniverse;
  external String? get expectedRecordVersion;
  external JSAny? get originalFields;
  external String? get original;
  external String? get draftVersion;
}

@JS()
extension type _ReferenceRow._(JSObject _) implements JSObject {
  external factory _ReferenceRow({
    required int ordinal,
    required String record,
    required String universe,
  });
  external int get ordinal;
  external String get record;
  external String get universe;
}

SavedSecretForm _decodeSecret(
  _SecretRow row,
  Iterable<ExpressionReferenceInput> scopeRefs,
  Iterable<ExpressionReferenceInput> knowerRefs, {
  bool legacy = false,
}) {
  return SavedSecretForm(
    generation: BigInt.parse(row.generation),
    form: UnfinishedSecretForm(
      baseRevision: RevisionId.parse(row.baseRevision),
      representedContext: RecordId.parse(row.representedContext),
      clientRef: row.clientRef,
      scope: scopeRefs,
      fictionalKnowers: knowerRefs,
      readerDisclosed: row.readerDisclosed,
      hasConcealment: row.hasConcealment,
      concealment: row.concealment,
      validityKind: row.validityKind,
      calendar: row.calendar,
      start: row.start,
      end: row.end,
      startUnbounded: row.startUnbounded,
      endUnbounded: row.endUnbounded,
      rationale: row.rationale,
      revisionTarget: row.targetRecord == null
          ? null
          : ExpressionReferenceInput(
              record: row.targetRecord!,
              universe: row.targetUniverse!,
            ),
      expectedRecordVersion: row.expectedRecordVersion == null
          ? null
          : RecordVersionId.parse(row.expectedRecordVersion!),
      original: legacy
          ? (row.original == null
                ? null
                : SecretRecord.fromWire(
                    CanonicalValue.parseWireJson(row.original!),
                  ))
          : row.originalFields == null
          ? null
          : SecretRecord.fromWire(decodeBrowserInput(row.originalFields!)),
      draftVersion: row.draftVersion == null
          ? null
          : BigInt.parse(row.draftVersion!),
    ),
  );
}

_SecretRow _encodeSecret(SavedSecretForm saved) {
  final form = saved.form;
  return _SecretRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    clientRef: form.clientRef,
    concealment: form.concealment,
    validityKind: form.validityKind,
    calendar: form.calendar,
    start: form.start,
    end: form.end,
    rationale: form.rationale,
    hasConcealment: form.hasConcealment,
    startUnbounded: form.startUnbounded,
    endUnbounded: form.endUnbounded,
    readerDisclosed: form.readerDisclosed,
    targetRecord: form.revisionTarget?.record,
    targetUniverse: form.revisionTarget?.universe,
    expectedRecordVersion: form.expectedRecordVersion?.value,
    originalFields: form.original == null
        ? null
        : encodeBrowserInput(form.original!.toWire()),
    draftVersion: form.draftVersion?.toString(),
  );
}

final class BrowserSecretFormRecoveryStore {
  BrowserSecretFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['secret_form', 'secret_scope', 'secret_knowers'];
  static Future<BrowserSecretFormRecoveryStore> open({
    String databaseName = 'ub-secret-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserSecretFormRecoveryStore>();
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
            for (final table in _tables) {
              db.createObjectStore(table);
            }
          } else {
            final scan = tx.objectStore(_tables.first).openCursor();
            scan.onsuccess = ((web.Event _) {
              try {
                if (scan.result == null || scan.result.isUndefined) return;
                final cursor = scan.result as web.IDBCursorWithValue;
                cursor.update(
                  _encodeSecret(
                    _decodeSecret(
                      cursor.value as _SecretRow,
                      [],
                      [],
                      legacy: true,
                    ),
                  ),
                );
                cursor.continue_();
              } catch (_) {
                tx.abort();
              }
            }).toJS;
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
        result.complete(BrowserSecretFormRecoveryStore._(db));
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
      throw const FormatException('Choose the secret definition context.');
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

  SavedSecretForm? _read(
    web.IDBRequest main,
    web.IDBRequest scopes,
    web.IDBRequest knowers,
  ) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _SecretRow;
    List<ExpressionReferenceInput> refs(web.IDBRequest request) {
      final rows = (request.result as JSArray<_ReferenceRow>).toDart
        ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
      return rows
          .map(
            (ref) => ExpressionReferenceInput(
              record: ref.record,
              universe: ref.universe,
            ),
          )
          .toList();
    }

    return _decodeSecret(row, refs(scopes), refs(knowers));
  }

  Future<SavedSecretForm?> load(EditorFormScope scope) {
    final result = Completer<SavedSecretForm?>();
    try {
      final key = _binding(scope), range = _children(_binding(scope));
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readonly',
      );
      final main = tx.objectStore(_tables[0]).get(key.toJS);
      final scopes = tx.objectStore(_tables[1]).getAll(range);
      final knowers = tx.objectStore(_tables[2]).getAll(range);
      tx.oncomplete = ((web.Event _) {
        try {
          result.complete(_read(main, scopes, knowers));
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

  Future<SavedSecretForm> save(
    EditorFormScope scope,
    UnfinishedSecretForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.recoveryKey)) {
      throw const FormatException('Secret form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedSecretForm>();
    SavedSecretForm? saved;
    EditorRecoveryException? failure;
    try {
      final key = _binding(scope), range = _children(_binding(scope));
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readwrite',
        web.IDBTransactionOptions(durability: 'strict'),
      );
      final primary = tx.objectStore(_tables[0]),
          scopeStore = tx.objectStore(_tables[1]),
          knowerStore = tx.objectStore(_tables[2]);
      final main = primary.get(key.toJS),
          scopes = scopeStore.getAll(range),
          knowers = knowerStore.getAll(range);
      // Queue writes synchronously in the final read's success callback, while
      // the transaction is active; awaiting a later task could auto-commit it.
      knowers.onsuccess = ((web.Event _) {
        try {
          final current = _read(main, scopes, knowers),
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
          saved = SavedSecretForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeSecret(saved!), key.toJS);
          scopeStore.delete(range);
          knowerStore.delete(range);
          for (final (store, refs) in [
            (scopeStore, form.scope),
            (knowerStore, form.fictionalKnowers),
          ]) {
            for (var i = 0; i < refs.length; i++) {
              store.put(
                _ReferenceRow(
                  ordinal: i,
                  record: refs[i].record,
                  universe: refs[i].universe,
                ),
                [...key, i.toJS].toJS,
              );
            }
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
