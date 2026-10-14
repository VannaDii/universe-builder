import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';

final class BrowserWorldFormRecovery {
  const BrowserWorldFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserWorldFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedWorldForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedWorldForm> save(
    EditorFormScope scope,
    UnfinishedWorldForm form,
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
extension type _WorldRow._(JSObject _) implements JSObject {
  external factory _WorldRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String record,
    required String selector,
    required String settingType,
    required String rationale,
    String? draftVersion,
    String? expectedRecordVersion,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get record;
  external String get selector;
  external String get settingType;
  external String get rationale;
  external String? get draftVersion;
  external String? get expectedRecordVersion;
}

@JS()
extension type _AliasRow._(JSObject _) implements JSObject {
  external factory _AliasRow({required int ordinal, required String value});
  external int get ordinal;
  external String get value;
}

@JS()
extension type _LabelRow._(JSObject _) implements JSObject {
  external factory _LabelRow({required String language, required String value});
  external String get language;
  external String get value;
}

/// Named fields and ordered child rows, never a serialized UI-state blob.
/// IndexedDB transactions compare generations and commit all children together.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserWorldFormRecoveryStore {
  BrowserWorldFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['world_form', 'world_form_alias', 'world_form_label'];

  static Future<BrowserWorldFormRecoveryStore> open({
    String databaseName = 'ub-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserWorldFormRecoveryStore>();
      final request = web.window.indexedDB.open(databaseName, 1);
      void fail() {
        if (!result.isCompleted) {
          result.completeError(
            const EditorRecoveryException(EditorRecoveryFailure.unavailable),
          );
        }
      }

      request.onupgradeneeded = ((web.Event _) {
        final db = request.result as web.IDBDatabase;
        for (final name in _tables) {
          db.createObjectStore(name);
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
        result.complete(BrowserWorldFormRecoveryStore._(db));
      }).toJS;
      return await result.future;
    } on EditorRecoveryException {
      rethrow;
    } on Object {
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  List<JSAny> _binding(EditorFormScope scope) => [
    scope.instance.value.toJS,
    scope.profile.value.toJS,
    scope.universe.value.toJS,
    scope.continuity.value.toJS,
    [
      if (scope.representedContext != null)
        'context:${scope.representedContext!.value}',
      if (scope.worldClientRef != null) 'edit:${scope.worldClientRef}',
      if (scope.worldRecord != null) 'record:${scope.worldRecord!.value}',
    ].join(':').toJS,
  ];
  web.IDBKeyRange _children(List<JSAny> key) => web.IDBKeyRange.bound(
    key.toJS,
    [...key, <JSAny>[].toJS].toJS,
    false,
    true,
  );

  SavedWorldForm? _read(
    web.IDBRequest main,
    web.IDBRequest aliases,
    web.IDBRequest labels,
  ) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _WorldRow;
    final aliasRows = (aliases.result as JSArray<_AliasRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return SavedWorldForm(
      generation: BigInt.parse(row.generation),
      form: UnfinishedWorldForm(
        baseRevision: RevisionId.parse(row.baseRevision),
        representedContext: RecordId.parse(row.representedContext),
        record: RecordId.parse(row.record),
        selector: row.selector,
        settingType: row.settingType,
        rationale: row.rationale,
        draftVersion: row.draftVersion == null
            ? null
            : BigInt.parse(row.draftVersion!),
        expectedRecordVersion: row.expectedRecordVersion == null
            ? null
            : RecordVersionId.parse(row.expectedRecordVersion!),
        aliases: aliasRows.map((row) => row.value),
        labels: {
          for (final label in (labels.result as JSArray<_LabelRow>).toDart)
            label.language: label.value,
        },
      ),
    );
  }

  Future<SavedWorldForm?> load(EditorFormScope scope) {
    final result = Completer<SavedWorldForm?>();
    try {
      final key = _binding(scope), range = _children(_binding(scope));
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readonly',
      );
      final main = tx.objectStore(_tables[0]).get(key.toJS);
      final aliases = tx.objectStore(_tables[1]).getAll(range);
      final labels = tx.objectStore(_tables[2]).getAll(range);
      tx.oncomplete = ((web.Event _) {
        try {
          result.complete(_read(main, aliases, labels));
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

  Future<SavedWorldForm> save(
    EditorFormScope scope,
    UnfinishedWorldForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    for (final text in [
      if (scope.worldClientRef != null) scope.worldClientRef!,
      form.selector,
      form.settingType,
      form.rationale,
      ...form.aliases,
      ...form.labels.keys,
      ...form.labels.values,
    ]) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedWorldForm>();
    SavedWorldForm? saved;
    EditorRecoveryException? failure;
    try {
      final key = _binding(scope), range = _children(_binding(scope));
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readwrite',
        web.IDBTransactionOptions(durability: 'strict'),
      );
      final primary = tx.objectStore(_tables[0]),
          aliasStore = tx.objectStore(_tables[1]),
          labelStore = tx.objectStore(_tables[2]);
      final main = primary.get(key.toJS),
          aliases = aliasStore.getAll(range),
          labels = labelStore.getAll(range);
      // Queue writes synchronously in the final read's success callback, while
      // the transaction is active; awaiting a later task could auto-commit it.
      labels.onsuccess = ((web.Event _) {
        try {
          final current = _read(main, aliases, labels),
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
          saved = SavedWorldForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(
            _WorldRow(
              generation: saved!.generation.toString(),
              baseRevision: form.baseRevision.value,
              representedContext: form.representedContext.value,
              record: form.record.value,
              selector: form.selector,
              settingType: form.settingType,
              rationale: form.rationale,
              draftVersion: form.draftVersion?.toString(),
              expectedRecordVersion: form.expectedRecordVersion?.value,
            ),
            key.toJS,
          );
          aliasStore.delete(range);
          labelStore.delete(range);
          for (var i = 0; i < form.aliases.length; i++) {
            aliasStore.put(
              _AliasRow(ordinal: i, value: form.aliases[i]),
              [...key, i.toJS].toJS,
            );
          }
          for (final entry in form.labels.entries) {
            labelStore.put(
              _LabelRow(language: entry.key, value: entry.value),
              [...key, entry.key.toJS].toJS,
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
