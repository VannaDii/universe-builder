import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserSagaFormRecovery {
  const BrowserSagaFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserSagaFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedSagaForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedSagaForm> save(
    EditorFormScope scope,
    UnfinishedSagaForm form,
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
extension type _SagaRow._(JSObject _) implements JSObject {
  external factory _SagaRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String title,
    required String rationale,
    String? draftVersion,
    JSAny? membershipTarget,
    String? expectedRecordVersion,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get title;
  external String get rationale;
  external String? get draftVersion;
  external JSAny? get membershipTarget;
  external String? get expectedRecordVersion;
}

@JS()
extension type _MembershipRow._(JSObject _) implements JSObject {
  external factory _MembershipRow({
    required int ordinal,
    required String workRecord,
    required String workUniverse,
    required String role,
    required bool orderEnabled,
    required String order,
  });
  external int get ordinal;
  external String get workRecord;
  external String get workUniverse;
  external String get role;
  external bool get orderEnabled;
  external String get order;
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

/// Named fields and ordered child rows, never a serialized UI-state blob.
/// IndexedDB transactions compare generations and commit all children together.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserSagaFormRecoveryStore {
  BrowserSagaFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['saga_form', 'saga_membership', 'saga_label'];

  static Future<BrowserSagaFormRecoveryStore> open({
    String databaseName = 'ub-saga-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserSagaFormRecoveryStore>();
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
        result.complete(BrowserSagaFormRecoveryStore._(db));
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
      throw const FormatException('Choose the saga context.');
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

  SavedSagaForm? _read(
    web.IDBRequest main,
    web.IDBRequest aliases,
    web.IDBRequest labels,
  ) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _SagaRow;
    final membershipRows = (aliases.result as JSArray<_MembershipRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    final labelRows = (labels.result as JSArray<_LabelRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return SavedSagaForm(
      generation: BigInt.parse(row.generation),
      form: UnfinishedSagaForm(
        baseRevision: RevisionId.parse(row.baseRevision),
        representedContext: RecordId.parse(row.representedContext),
        clientRef: row.clientRef,
        title: row.title,
        rationale: row.rationale,
        draftVersion: row.draftVersion == null
            ? null
            : BigInt.parse(row.draftVersion!),
        membershipTarget: row.membershipTarget == null
            ? null
            : ExpressionReferenceInput.fromWire(
                decodeBrowserInput(row.membershipTarget!),
              ),
        expectedRecordVersion: row.expectedRecordVersion == null
            ? null
            : RecordVersionId.parse(row.expectedRecordVersion!),
        memberships: membershipRows.map(
          (member) => SagaMembershipInput(
            work: ExpressionReferenceInput(
              record: member.workRecord,
              universe: member.workUniverse,
            ),
            role: member.role,
            orderEnabled: member.orderEnabled,
            order: member.order,
          ),
        ),
        labels: labelRows.map(
          (label) =>
              PropertyLabelInput(language: label.language, text: label.text),
        ),
      ),
    );
  }

  Future<SavedSagaForm?> load(EditorFormScope scope) {
    final result = Completer<SavedSagaForm?>();
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

  Future<SavedSagaForm> save(
    EditorFormScope scope,
    UnfinishedSagaForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Saga form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedSagaForm>();
    SavedSagaForm? saved;
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
          saved = SavedSagaForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(
            _SagaRow(
              generation: saved!.generation.toString(),
              baseRevision: form.baseRevision.value,
              representedContext: form.representedContext.value,
              clientRef: form.clientRef,
              title: form.title,
              rationale: form.rationale,
              draftVersion: form.draftVersion?.toString(),
              membershipTarget: form.membershipTarget == null
                  ? null
                  : encodeBrowserInput(form.membershipTarget!.toWire()),
              expectedRecordVersion: form.expectedRecordVersion?.value,
            ),
            key.toJS,
          );
          aliasStore.delete(range);
          labelStore.delete(range);
          for (var i = 0; i < form.memberships.length; i++) {
            final member = form.memberships[i];
            aliasStore.put(
              _MembershipRow(
                ordinal: i,
                workRecord: member.work.record,
                workUniverse: member.work.universe,
                role: member.role,
                orderEnabled: member.orderEnabled,
                order: member.order,
              ),
              [...key, i.toJS].toJS,
            );
          }
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
