import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_chronology_fields.dart';

final class BrowserStoryTimeFormRecovery {
  const BrowserStoryTimeFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserStoryTimeFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedStoryTimeForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedStoryTimeForm> save(
    EditorFormScope scope,
    UnfinishedStoryTimeForm form,
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
extension type _StoryTimeRow._(JSObject _) implements JSObject {
  external factory _StoryTimeRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String targetRecord,
    required String targetUniverse,
    required String expectedRecordVersion,
    required BrowserChronologyFields originalFields,
    required String value,
    required String mode,
    required String reason,
    required String rationale,
    String? draftVersion,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get targetRecord;
  external String get targetUniverse;
  external String get expectedRecordVersion;
  external BrowserChronologyFields get originalFields;
  external String get original;
  external String get value;
  external String get mode;
  external String get reason;
  external String get rationale;
  external String? get draftVersion;
}

_StoryTimeRow _encodeStoryTime(SavedStoryTimeForm saved) {
  final form = saved.form;
  return _StoryTimeRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    targetRecord: form.target.record,
    targetUniverse: form.target.universe,
    expectedRecordVersion: form.expectedRecordVersion.value,
    originalFields: encodeBrowserChronology(form.original),
    value: form.value,
    mode: form.mode,
    reason: form.reason,
    rationale: form.rationale,
    draftVersion: form.draftVersion?.toString(),
  );
}

SavedStoryTimeForm _decodeStoryTime(_StoryTimeRow row) => SavedStoryTimeForm(
  generation: BigInt.parse(row.generation),
  form: UnfinishedStoryTimeForm(
    baseRevision: RevisionId.parse(row.baseRevision),
    representedContext: RecordId.parse(row.representedContext),
    target: ExpressionReferenceInput(
      record: row.targetRecord,
      universe: row.targetUniverse,
    ),
    expectedRecordVersion: RecordVersionId.parse(row.expectedRecordVersion),
    original: decodeBrowserChronology(row.originalFields),
    value: row.value,
    mode: row.mode,
    reason: row.reason,
    rationale: row.rationale,
    draftVersion: row.draftVersion == null
        ? null
        : BigInt.parse(row.draftVersion!),
  ),
);

final class BrowserStoryTimeFormRecoveryStore {
  BrowserStoryTimeFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['story_time_form'];
  static Future<BrowserStoryTimeFormRecoveryStore> open({
    String databaseName = 'ub-story-time-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserStoryTimeFormRecoveryStore>();
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
        result.complete(BrowserStoryTimeFormRecoveryStore._(db));
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
      throw const FormatException('Choose the story-time context.');
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

  SavedStoryTimeForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    return _decodeStoryTime(main.result as _StoryTimeRow);
  }

  Future<SavedStoryTimeForm?> load(EditorFormScope scope) {
    final result = Completer<SavedStoryTimeForm?>();
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

  Future<SavedStoryTimeForm> save(
    EditorFormScope scope,
    UnfinishedStoryTimeForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.recoveryKey)) {
      throw const FormatException('StoryTime form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedStoryTimeForm>();
    SavedStoryTimeForm? saved;
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
      // Queue writes while the read transaction remains active.
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
          saved = SavedStoryTimeForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeStoryTime(saved!), key.toJS);
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
