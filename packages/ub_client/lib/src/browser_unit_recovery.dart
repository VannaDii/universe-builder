import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserUnitFormRecovery {
  const BrowserUnitFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserUnitFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedUnitForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedUnitForm> save(
    EditorFormScope scope,
    UnfinishedUnitForm form,
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
extension type _UnitRow._(JSObject _) implements JSObject {
  external factory _UnitRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String namespace,
    required String key,
    required String dimension,
    required String symbol,
    required bool hasBase,
    required String base,
    required bool hasScale,
    required JSAny scale,
    required String validityChoice,
    JSAny? temporal,
    required String rationale,
    String? draftVersion,
    JSAny? revisionTarget,
    String? expectedRecordVersion,
    JSAny? originalFields,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get namespace;
  external String get key;
  external String get dimension;
  external String get symbol;
  external bool get hasBase;
  external String get base;
  external bool get hasScale;
  external JSAny get scale;
  external String get validityChoice;
  external JSAny? get temporal;
  external String get rationale;
  external String? get draftVersion;
  external JSAny? get revisionTarget;
  external String? get expectedRecordVersion;
  external JSAny? get originalFields;
}

@JS()
extension type _LabelRow._(JSObject _) implements JSObject {
  external factory _LabelRow({
    required int ordinal,
    required String language,
    required String text,
  });
  external int get ordinal;
  external String get language;
  external String get text;
}

SavedUnitForm _decodeUnit(_UnitRow row, Iterable<_LabelRow> labelRows) {
  return SavedUnitForm(
    generation: BigInt.parse(row.generation),
    form: UnfinishedUnitForm(
      baseRevision: RevisionId.parse(row.baseRevision),
      representedContext: RecordId.parse(row.representedContext),
      clientRef: row.clientRef,
      namespace: row.namespace,
      key: row.key,
      dimension: row.dimension,
      symbol: row.symbol,
      hasBase: row.hasBase,
      base: row.base,
      hasScale: row.hasScale,
      scale: QualifierInput.fromWire(decodeBrowserInput(row.scale)),
      validityChoice: row.validityChoice,
      temporalValidity: row.temporal == null
          ? null
          : TemporalValidityInput.fromWire(decodeBrowserInput(row.temporal!)),
      rationale: row.rationale,
      draftVersion: row.draftVersion == null
          ? null
          : BigInt.parse(row.draftVersion!),
      revisionTarget: row.revisionTarget == null
          ? null
          : ExpressionReferenceInput.fromWire(
              decodeBrowserInput(row.revisionTarget!),
            ),
      expectedRecordVersion: row.expectedRecordVersion == null
          ? null
          : RecordVersionId.parse(row.expectedRecordVersion!),
      original: row.originalFields == null
          ? null
          : UnitRecord.fromWire(decodeBrowserInput(row.originalFields!)),
      labels: labelRows.map(
        (label) =>
            PropertyLabelInput(language: label.language, text: label.text),
      ),
    ),
  );
}

_UnitRow _encodeUnit(SavedUnitForm saved) {
  final form = saved.form;
  return _UnitRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    clientRef: form.clientRef,
    namespace: form.namespace,
    key: form.key,
    dimension: form.dimension,
    symbol: form.symbol,
    hasBase: form.hasBase,
    base: form.base,
    hasScale: form.hasScale,
    scale: encodeBrowserInput(form.scale.toWire())!,
    validityChoice: form.validityChoice,
    temporal: form.temporalValidity == null
        ? null
        : encodeBrowserInput(form.temporalValidity!.toWire()),
    rationale: form.rationale,
    draftVersion: form.draftVersion?.toString(),
    revisionTarget: form.revisionTarget == null
        ? null
        : encodeBrowserInput(form.revisionTarget!.toWire()),
    expectedRecordVersion: form.expectedRecordVersion?.value,
    originalFields: form.original == null
        ? null
        : encodeBrowserInput(form.original!.toWire()),
  );
}

/// Named fields and ordered child rows, never a serialized UI-state blob.
/// IndexedDB transactions compare generations and commit all children together.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserUnitFormRecoveryStore {
  BrowserUnitFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['unit_form', 'unit_form_label'];

  static Future<BrowserUnitFormRecoveryStore> open({
    String databaseName = 'ub-unit-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserUnitFormRecoveryStore>();
      final request = web.window.indexedDB.open(databaseName, 2);
      void fail() {
        if (!result.isCompleted) {
          result.completeError(
            const EditorRecoveryException(EditorRecoveryFailure.unavailable),
          );
        }
      }

      request.onupgradeneeded = ((web.Event event) {
        final db = request.result as web.IDBDatabase;
        if ((event as web.IDBVersionChangeEvent).oldVersion != 0) {
          request.transaction!.abort();
          return;
        }
        for (final table in _tables) {
          db.createObjectStore(table);
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
        result.complete(BrowserUnitFormRecoveryStore._(db));
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
      throw const FormatException('Choose the unit definition context.');
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

  SavedUnitForm? _read(web.IDBRequest main, web.IDBRequest labels) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _UnitRow;
    final labelRows = (labels.result as JSArray<_LabelRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return _decodeUnit(row, labelRows);
  }

  Future<SavedUnitForm?> load(EditorFormScope scope) {
    final result = Completer<SavedUnitForm?>();
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

  Future<SavedUnitForm> save(
    EditorFormScope scope,
    UnfinishedUnitForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Unit form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedUnitForm>();
    SavedUnitForm? saved;
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
          saved = SavedUnitForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeUnit(saved!), key.toJS);
          labelStore.delete(range);
          for (var i = 0; i < form.labels.length; i++) {
            final label = form.labels[i];
            labelStore.put(
              _LabelRow(ordinal: i, language: label.language, text: label.text),
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
