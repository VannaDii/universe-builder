import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserObservationFormRecovery {
  const BrowserObservationFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserObservationFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedObservationForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedObservationForm> save(
    EditorFormScope scope,
    UnfinishedObservationForm form,
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
extension type _ObservationRow._(JSObject _) implements JSObject {
  external factory _ObservationRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required JSAny observer,
    required JSAny observed,
    bool? sensoryAccess,
    required JSAny time,
    required bool interpretationEnabled,
    required JSAny interpretation,
    required JSAny basis,
    required String rationale,
    String? draftVersion,
    JSAny? originalFields,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external JSAny get observer;
  external JSAny get observed;
  external bool? get sensoryAccess;
  external JSAny get time;
  external bool get interpretationEnabled;
  external JSAny get interpretation;
  external JSAny get basis;
  external String get rationale;
  external String? get draftVersion;
  external JSAny? get originalFields;
  external String? get original;
}

SavedObservationForm _decodeObservation(
  _ObservationRow row, {
  bool legacy = false,
}) {
  return SavedObservationForm(
    generation: BigInt.parse(row.generation),
    form: UnfinishedObservationForm(
      baseRevision: RevisionId.parse(row.baseRevision),
      representedContext: RecordId.parse(row.representedContext),
      clientRef: row.clientRef,
      observer: ExpressionReferenceInput.fromWire(
        decodeBrowserInput(row.observer),
      ),
      observed: ExpressionReferenceInput.fromWire(
        decodeBrowserInput(row.observed),
      ),
      sensoryAccess: row.sensoryAccess,
      time: TemporalValidityInput.fromWire(decodeBrowserInput(row.time)),
      interpretationEnabled: row.interpretationEnabled,
      interpretation: ExpressionReferenceInput.fromWire(
        decodeBrowserInput(row.interpretation),
      ),
      basis: EvidenceBasisInput.fromWire(decodeBrowserInput(row.basis)),
      original: legacy
          ? (row.original == null
                ? null
                : ObservationRecord.fromWire(
                    CanonicalValue.parseWireJson(row.original!),
                  ))
          : row.originalFields == null
          ? null
          : ObservationRecord.fromWire(decodeBrowserInput(row.originalFields!)),
      rationale: row.rationale,
      draftVersion: row.draftVersion == null
          ? null
          : BigInt.parse(row.draftVersion!),
    ),
  );
}

_ObservationRow _encodeObservation(SavedObservationForm saved) {
  final form = saved.form;
  return _ObservationRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    clientRef: form.clientRef,
    observer: encodeBrowserInput(form.observer.toWire())!,
    observed: encodeBrowserInput(form.observed.toWire())!,
    sensoryAccess: form.sensoryAccess,
    time: encodeBrowserInput(form.time.toWire())!,
    interpretationEnabled: form.interpretationEnabled,
    interpretation: encodeBrowserInput(form.interpretation.toWire())!,
    basis: encodeBrowserInput(form.basis.toWire())!,
    originalFields: form.original == null
        ? null
        : encodeBrowserInput(form.original!.toWire()),
    rationale: form.rationale,
    draftVersion: form.draftVersion?.toString(),
  );
}

/// Named fields retain observation references, sensory-access choices and temporal input.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserObservationFormRecoveryStore {
  BrowserObservationFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['observation_form'];

  static Future<BrowserObservationFormRecoveryStore> open({
    String databaseName = 'ub-observation-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserObservationFormRecoveryStore>();
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
            db.createObjectStore(_tables.single);
          } else {
            final scan = tx.objectStore(_tables.single).openCursor();
            scan.onsuccess = ((web.Event _) {
              try {
                if (scan.result == null || scan.result.isUndefined) return;
                final cursor = scan.result as web.IDBCursorWithValue;
                cursor.update(
                  _encodeObservation(
                    _decodeObservation(
                      cursor.value as _ObservationRow,
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
        result.complete(BrowserObservationFormRecoveryStore._(db));
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
      throw const FormatException('Choose the observation context.');
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

  SavedObservationForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _ObservationRow;
    return _decodeObservation(row);
  }

  Future<SavedObservationForm?> load(EditorFormScope scope) {
    final result = Completer<SavedObservationForm?>();
    try {
      final key = _binding(scope);
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readonly',
      );
      final main = tx.objectStore(_tables[0]).get(key.toJS);
      tx.oncomplete = ((web.Event _) {
        try {
          result.complete(_read(main));
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

  Future<SavedObservationForm> save(
    EditorFormScope scope,
    UnfinishedObservationForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Observation form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedObservationForm>();
    SavedObservationForm? saved;
    EditorRecoveryException? failure;
    try {
      final key = _binding(scope);
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readwrite',
        web.IDBTransactionOptions(durability: 'strict'),
      );
      final primary = tx.objectStore(_tables[0]);
      final main = primary.get(key.toJS);
      // Queue writes synchronously in the final read's success callback, while
      // the transaction is active; awaiting a later task could auto-commit it.
      main.onsuccess = ((web.Event _) {
        try {
          final current = _read(main),
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
          saved = SavedObservationForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeObservation(saved!), key.toJS);
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
