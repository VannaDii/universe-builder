import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserItemPowerFormRecovery {
  const BrowserItemPowerFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserItemPowerFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedItemPowerForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedItemPowerForm> save(
    EditorFormScope scope,
    UnfinishedItemPowerForm form,
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
extension type _PowerRow._(JSObject _) implements JSObject {
  external factory _PowerRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required JSAny item,
    required JSAny holderPredicate,
    required JSAny powerPredicate,
    required JSAny value,
    required JSAny factualScope,
    required JSAny validity,
    required String rationale,
    String? draftVersion,
    JSAny? originalFields,
    JSAny? correctionTarget,
    String? expectedRecordVersion,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external JSAny get item;
  external JSAny get holderPredicate;
  external JSAny get powerPredicate;
  external JSAny get value;
  external JSAny get factualScope;
  external JSAny get validity;
  external String get rationale;
  external String? get draftVersion;
  external JSAny? get originalFields;
  external String? get original;
  external JSAny? get correctionTarget;
  external String? get expectedRecordVersion;
}

SavedItemPowerForm _decodeItemPower(_PowerRow row, {bool legacy = false}) {
  return SavedItemPowerForm(
    generation: BigInt.parse(row.generation),
    form: UnfinishedItemPowerForm(
      baseRevision: RevisionId.parse(row.baseRevision),
      representedContext: RecordId.parse(row.representedContext),
      clientRef: row.clientRef,
      item: ExpressionReferenceInput.fromWire(decodeBrowserInput(row.item)),
      holderPredicate: ExpressionReferenceInput.fromWire(
        decodeBrowserInput(row.holderPredicate),
      ),
      powerPredicate: ExpressionReferenceInput.fromWire(
        decodeBrowserInput(row.powerPredicate),
      ),
      value: QualifierInput.fromWire(decodeBrowserInput(row.value)),
      scope: ScopeInput.fromWire(decodeBrowserInput(row.factualScope)),
      validity: TemporalValidityInput.fromWire(
        decodeBrowserInput(row.validity),
      ),
      original: legacy
          ? (row.original == null
                ? null
                : ItemPowerRecord.fromWire(
                    CanonicalValue.parseWireJson(row.original!),
                  ))
          : row.originalFields == null
          ? null
          : ItemPowerRecord.fromWire(decodeBrowserInput(row.originalFields!)),
      correctionTarget: row.correctionTarget == null
          ? null
          : ExpressionReferenceInput.fromWire(
              decodeBrowserInput(row.correctionTarget!),
            ),
      expectedRecordVersion: row.expectedRecordVersion == null
          ? null
          : RecordVersionId.parse(row.expectedRecordVersion!),
      rationale: row.rationale,
      draftVersion: row.draftVersion == null
          ? null
          : BigInt.parse(row.draftVersion!),
    ),
  );
}

_PowerRow _encodeItemPower(SavedItemPowerForm saved) {
  final form = saved.form;
  return _PowerRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    clientRef: form.clientRef,
    item: encodeBrowserInput(form.item.toWire())!,
    holderPredicate: encodeBrowserInput(form.holderPredicate.toWire())!,
    powerPredicate: encodeBrowserInput(form.powerPredicate.toWire())!,
    value: encodeBrowserInput(form.value.toWire())!,
    factualScope: encodeBrowserInput(form.scope.toWire())!,
    validity: encodeBrowserInput(form.validity.toWire())!,
    originalFields: form.original == null
        ? null
        : encodeBrowserInput(form.original!.toWire()),
    correctionTarget: form.correctionTarget == null
        ? null
        : encodeBrowserInput(form.correctionTarget!.toWire()),
    expectedRecordVersion: form.expectedRecordVersion?.value,
    rationale: form.rationale,
    draftVersion: form.draftVersion?.toString(),
  );
}

/// Named fields retain item-power references, nested values, factual scope and validity input.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserItemPowerFormRecoveryStore {
  BrowserItemPowerFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['item_power_form'];

  static Future<BrowserItemPowerFormRecoveryStore> open({
    String databaseName = 'ub-item-power-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserItemPowerFormRecoveryStore>();
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
                  _encodeItemPower(
                    _decodeItemPower(cursor.value as _PowerRow, legacy: true),
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
        result.complete(BrowserItemPowerFormRecoveryStore._(db));
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
      throw const FormatException('Choose the item_power context.');
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

  SavedItemPowerForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _PowerRow;
    return _decodeItemPower(row);
  }

  Future<SavedItemPowerForm?> load(EditorFormScope scope) {
    final result = Completer<SavedItemPowerForm?>();
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

  Future<SavedItemPowerForm> save(
    EditorFormScope scope,
    UnfinishedItemPowerForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Item power form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedItemPowerForm>();
    SavedItemPowerForm? saved;
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
          saved = SavedItemPowerForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeItemPower(saved!), key.toJS);
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
