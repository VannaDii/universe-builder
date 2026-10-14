import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserWorkVersionFormRecovery {
  const BrowserWorkVersionFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserWorkVersionFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedWorkVersionForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedWorkVersionForm> save(
    EditorFormScope scope,
    UnfinishedWorkVersionForm form,
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
extension type _EditionRow._(JSObject _) implements JSObject {
  external factory _EditionRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String workRecord,
    required String workUniverse,
    required String versionLabel,
    required String bindingKind,
    required String continuity,
    required String revision,
    required JSAny segments,
    required String rationale,
    String? draftVersion,
    JSAny? bindingTarget,
    String? expectedRecordVersion,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get workRecord;
  external String get workUniverse;
  external String get versionLabel;
  external String get bindingKind;
  external String get continuity;
  external String get revision;
  external JSAny get segments;
  external String get rationale;
  external String? get draftVersion;
  external JSAny? get bindingTarget;
  external String? get expectedRecordVersion;
}

/// Named fields retain edition bindings and ordered segment input.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserWorkVersionFormRecoveryStore {
  BrowserWorkVersionFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['work_version_form'];

  static Future<BrowserWorkVersionFormRecoveryStore> open({
    String databaseName = 'ub-work-version-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserWorkVersionFormRecoveryStore>();
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
        result.complete(BrowserWorkVersionFormRecoveryStore._(db));
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
      throw const FormatException('Choose the work_version context.');
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

  SavedWorkVersionForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _EditionRow;
    return SavedWorkVersionForm(
      generation: BigInt.parse(row.generation),
      form: UnfinishedWorkVersionForm(
        baseRevision: RevisionId.parse(row.baseRevision),
        representedContext: RecordId.parse(row.representedContext),
        clientRef: row.clientRef,
        work: ExpressionReferenceInput(
          record: row.workRecord,
          universe: row.workUniverse,
        ),
        versionLabel: row.versionLabel,
        bindingKind: row.bindingKind,
        continuity: row.continuity,
        revision: row.revision,
        segments: (decodeBrowserInput(row.segments) as CanonicalArray).items
            .map(WorkSegmentInput.fromWire),
        bindingTarget: row.bindingTarget == null
            ? null
            : ExpressionReferenceInput.fromWire(
                decodeBrowserInput(row.bindingTarget!),
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

  Future<SavedWorkVersionForm?> load(EditorFormScope scope) {
    final result = Completer<SavedWorkVersionForm?>();
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

  Future<SavedWorkVersionForm> save(
    EditorFormScope scope,
    UnfinishedWorkVersionForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Edition form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedWorkVersionForm>();
    SavedWorkVersionForm? saved;
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
          saved = SavedWorkVersionForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(
            _EditionRow(
              generation: saved!.generation.toString(),
              baseRevision: form.baseRevision.value,
              representedContext: form.representedContext.value,
              clientRef: form.clientRef,
              workRecord: form.work.record,
              workUniverse: form.work.universe,
              versionLabel: form.versionLabel,
              bindingKind: form.bindingKind,
              continuity: form.continuity,
              revision: form.revision,
              segments: encodeBrowserInput(
                CanonicalArray(
                  form.segments.map((segment) => segment.toWire()),
                ),
              )!,
              bindingTarget: form.bindingTarget == null
                  ? null
                  : encodeBrowserInput(form.bindingTarget!.toWire()),
              expectedRecordVersion: form.expectedRecordVersion?.value,
              rationale: form.rationale,
              draftVersion: form.draftVersion?.toString(),
            ),
            key.toJS,
          );
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
