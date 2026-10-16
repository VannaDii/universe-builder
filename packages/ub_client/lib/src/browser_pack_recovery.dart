import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserPackFormRecovery {
  const BrowserPackFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserPackFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedPackForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedPackForm> save(
    EditorFormScope scope,
    UnfinishedPackForm form,
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
extension type _PackRow._(JSObject _) implements JSObject {
  external factory _PackRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String key,
    required String version,
    required String rationale,
    String? draftVersion,
    JSAny? revisionTarget,
    String? expectedRecordVersion,
    JSAny? originalFields,
    bool? realWorldPolicy,
    required bool activatePolicy,
    String? expectedRootVersion,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get key;
  external String get version;
  external String get rationale;
  external String? get draftVersion;
  external JSAny? get revisionTarget;
  external String? get expectedRecordVersion;
  external JSAny? get originalFields;
  external bool? get realWorldPolicy;
  external bool get activatePolicy;
  external String? get expectedRootVersion;
}

@JS()
extension type _DependencyRow._(JSObject _) implements JSObject {
  external factory _DependencyRow({
    required int ordinal,
    required String key,
    required String version,
  });
  external int get ordinal;
  external String get key;
  external String get version;
}

@JS()
extension type _MemberRow._(JSObject _) implements JSObject {
  external factory _MemberRow({required int ordinal, required String value});
  external int get ordinal;
  external String get value;
}

@JS()
extension type _CapabilityRow._(JSObject _) implements JSObject {
  external factory _CapabilityRow({
    required int ordinal,
    required String value,
  });
  external int get ordinal;
  external String get value;
}

SavedPackForm _decodePack(
  _PackRow row,
  Iterable<_DependencyRow> dependencyRows,
  Iterable<_CapabilityRow> capabilityRows,
  Iterable<_MemberRow> memberRows,
) {
  return SavedPackForm(
    generation: BigInt.parse(row.generation),
    form: UnfinishedPackForm(
      baseRevision: RevisionId.parse(row.baseRevision),
      representedContext: RecordId.parse(row.representedContext),
      clientRef: row.clientRef,
      key: row.key,
      version: row.version,
      rationale: row.rationale,
      realWorldPolicy: row.realWorldPolicy,
      activatePolicy: row.activatePolicy,
      expectedRootVersion: row.expectedRootVersion == null
          ? null
          : RecordVersionId.parse(row.expectedRootVersion!),
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
          : DomainPackRecord.fromWire(decodeBrowserInput(row.originalFields!)),
      dependencies: dependencyRows.map(
        (dependency) => PackDependencyInput(
          key: dependency.key,
          version: dependency.version,
        ),
      ),
      capabilities: capabilityRows.map((capability) => capability.value),
      records: memberRows.map((member) => member.value),
    ),
  );
}

_PackRow _encodePack(SavedPackForm saved) {
  final form = saved.form;
  return _PackRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    clientRef: form.clientRef,
    key: form.key,
    version: form.version,
    rationale: form.rationale,
    realWorldPolicy: form.realWorldPolicy,
    activatePolicy: form.activatePolicy,
    expectedRootVersion: form.expectedRootVersion?.value,
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
final class BrowserPackFormRecoveryStore {
  BrowserPackFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = [
    'pack_form',
    'pack_dependency',
    'pack_capability',
    'pack_member',
  ];

  static Future<BrowserPackFormRecoveryStore> open({
    String databaseName = 'ub-pack-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserPackFormRecoveryStore>();
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
        result.complete(BrowserPackFormRecoveryStore._(db));
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
      throw const FormatException('Choose the pack definition context.');
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

  SavedPackForm? _read(
    web.IDBRequest main,
    web.IDBRequest aliases,
    web.IDBRequest labels,
    web.IDBRequest conversions,
  ) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _PackRow;
    final dependencyRows = (aliases.result as JSArray<_DependencyRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    final capabilityRows = (labels.result as JSArray<_CapabilityRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    final memberRows = (conversions.result as JSArray<_MemberRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return _decodePack(row, dependencyRows, capabilityRows, memberRows);
  }

  Future<SavedPackForm?> load(EditorFormScope scope) {
    final result = Completer<SavedPackForm?>();
    try {
      final key = _binding(scope), range = _children(_binding(scope));
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readonly',
      );
      final main = tx.objectStore(_tables[0]).get(key.toJS);
      final aliases = tx.objectStore(_tables[1]).getAll(range);
      final conversions = tx.objectStore(_tables[3]).getAll(range);
      final labels = tx.objectStore(_tables[2]).getAll(range);
      tx.oncomplete = ((web.Event _) {
        try {
          result.complete(_read(main, aliases, labels, conversions));
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

  Future<SavedPackForm> save(
    EditorFormScope scope,
    UnfinishedPackForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef &&
            !(scope.typeClientRef == universePolicyEditorKey &&
                form.realWorldPolicy != null))) {
      throw const FormatException('Pack form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedPackForm>();
    SavedPackForm? saved;
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
          labelStore = tx.objectStore(_tables[2]),
          conversionStore = tx.objectStore(_tables[3]);
      final main = primary.get(key.toJS),
          aliases = aliasStore.getAll(range),
          conversions = conversionStore.getAll(range),
          labels = labelStore.getAll(range);
      // Queue writes synchronously in the final read's success callback, while
      // the transaction is active; awaiting a later task could auto-commit it.
      labels.onsuccess = ((web.Event _) {
        try {
          final current = _read(main, aliases, labels, conversions),
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
          saved = SavedPackForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodePack(saved!), key.toJS);
          aliasStore.delete(range);
          labelStore.delete(range);
          conversionStore.delete(range);
          for (var i = 0; i < form.dependencies.length; i++) {
            final dependency = form.dependencies[i];
            aliasStore.put(
              _DependencyRow(
                ordinal: i,
                key: dependency.key,
                version: dependency.version,
              ),
              [...key, i.toJS].toJS,
            );
          }
          for (var i = 0; i < form.capabilities.length; i++) {
            labelStore.put(
              _CapabilityRow(ordinal: i, value: form.capabilities[i]),
              [...key, i.toJS].toJS,
            );
          }
          for (var i = 0; i < form.records.length; i++) {
            conversionStore.put(
              _MemberRow(ordinal: i, value: form.records[i]),
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
