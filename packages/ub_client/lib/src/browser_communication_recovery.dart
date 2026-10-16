import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserCommunicationFormRecovery {
  const BrowserCommunicationFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserCommunicationFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedCommunicationForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedCommunicationForm> save(
    EditorFormScope scope,
    UnfinishedCommunicationForm form,
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
extension type _CommunicationRow._(JSObject _) implements JSObject {
  external factory _CommunicationRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required JSAny sender,
    required JSAny intendedRecipients,
    required JSAny actualRecipients,
    required JSAny content,
    required bool channelEnabled,
    required String channel,
    bool? distorted,
    required JSAny sentAt,
    required bool receivedEnabled,
    required JSAny receivedAt,
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
  external JSAny get sender;
  external JSAny get intendedRecipients;
  external JSAny get actualRecipients;
  external JSAny get content;
  external bool get channelEnabled;
  external String get channel;
  external bool? get distorted;
  external JSAny get sentAt;
  external bool get receivedEnabled;
  external JSAny get receivedAt;
  external String get rationale;
  external String? get draftVersion;
  external JSAny? get originalFields;
  external JSAny? get correctionTarget;
  external String? get expectedRecordVersion;
}

SavedCommunicationForm _decodeCommunication(_CommunicationRow row) {
  return SavedCommunicationForm(
    generation: BigInt.parse(row.generation),
    form: UnfinishedCommunicationForm(
      baseRevision: RevisionId.parse(row.baseRevision),
      representedContext: RecordId.parse(row.representedContext),
      clientRef: row.clientRef,
      sender: ExpressionReferenceInput.fromWire(decodeBrowserInput(row.sender)),
      intendedRecipients: (decodeBrowserInput(
        row.intendedRecipients,
      ) as CanonicalArray).items.map(ExpressionReferenceInput.fromWire),
      actualRecipients: (decodeBrowserInput(
        row.actualRecipients,
      ) as CanonicalArray).items.map(ExpressionReferenceInput.fromWire),
      content: (decodeBrowserInput(row.content) as CanonicalArray).items.map(
        ExpressionReferenceInput.fromWire,
      ),
      channelEnabled: row.channelEnabled,
      channel: row.channel,
      distorted: row.distorted,
      sentAt: TemporalValidityInput.fromWire(decodeBrowserInput(row.sentAt)),
      receivedEnabled: row.receivedEnabled,
      receivedAt: TemporalValidityInput.fromWire(
        decodeBrowserInput(row.receivedAt),
      ),
      original: row.originalFields == null
          ? null
          : CommunicationRecord.fromWire(
              decodeBrowserInput(row.originalFields!),
            ),
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

_CommunicationRow _encodeCommunication(SavedCommunicationForm saved) {
  final form = saved.form;
  return _CommunicationRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    clientRef: form.clientRef,
    sender: encodeBrowserInput(form.sender.toWire())!,
    intendedRecipients: encodeBrowserInput(
      CanonicalArray(form.intendedRecipients.map((ref) => ref.toWire())),
    )!,
    actualRecipients: encodeBrowserInput(
      CanonicalArray(form.actualRecipients.map((ref) => ref.toWire())),
    )!,
    content: encodeBrowserInput(
      CanonicalArray(form.content.map((ref) => ref.toWire())),
    )!,
    channelEnabled: form.channelEnabled,
    channel: form.channel,
    distorted: form.distorted,
    sentAt: encodeBrowserInput(form.sentAt.toWire())!,
    receivedEnabled: form.receivedEnabled,
    receivedAt: encodeBrowserInput(form.receivedAt.toWire())!,
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

/// Named fields retain communication recipients, content and temporal input.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserCommunicationFormRecoveryStore {
  BrowserCommunicationFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['communication_form'];

  static Future<BrowserCommunicationFormRecoveryStore> open({
    String databaseName = 'ub-communication-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserCommunicationFormRecoveryStore>();
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
        result.complete(BrowserCommunicationFormRecoveryStore._(db));
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
      throw const FormatException('Choose the communication context.');
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

  SavedCommunicationForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _CommunicationRow;
    return _decodeCommunication(row);
  }

  Future<SavedCommunicationForm?> load(EditorFormScope scope) {
    final result = Completer<SavedCommunicationForm?>();
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

  Future<SavedCommunicationForm> save(
    EditorFormScope scope,
    UnfinishedCommunicationForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Communication form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedCommunicationForm>();
    SavedCommunicationForm? saved;
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
          saved = SavedCommunicationForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeCommunication(saved!), key.toJS);
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
