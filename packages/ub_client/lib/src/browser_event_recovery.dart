import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserEventFormRecovery {
  const BrowserEventFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserEventFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedEventForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedEventForm> save(
    EditorFormScope scope,
    UnfinishedEventForm form,
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
extension type _EventRow._(JSObject _) implements JSObject {
  external factory _EventRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String label,
    required String occurrence,
    required String description,
    required String actionRecord,
    required String actionUniverse,
    required JSAny time,
    required JSAny participants,
    JSArray<_EffectRow>? effects,
    JSAny? preconditions,
    required JSAny worlds,
    required String regionRecord,
    required String regionUniverse,
    required String sequence,
    required String occurrenceId,
    JSAny? revisionTarget,
    String? expectedRecordVersion,
    required String rationale,
    String? draftVersion,
    String? original,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get label;
  external String get occurrence;
  external String get description;
  external String get actionRecord;
  external String get actionUniverse;
  external JSAny get time;
  external JSAny get participants;
  external JSArray<_EffectRow>? get effects;
  external JSAny? get preconditions;
  external JSAny get worlds;
  external String get regionRecord;
  external String get regionUniverse;
  external String get sequence;
  external String get occurrenceId;
  external JSAny? get revisionTarget;
  external String? get expectedRecordVersion;
  external String get rationale;
  external String? get draftVersion;
  external String? get original;
}

/// Named fields retain unfinished event input and ordered declarations.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserEventFormRecoveryStore {
  BrowserEventFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['event_form'];

  static Future<BrowserEventFormRecoveryStore> open({
    String databaseName = 'ub-event-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserEventFormRecoveryStore>();
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
        result.complete(BrowserEventFormRecoveryStore._(db));
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
      throw const FormatException('Choose the event context.');
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

  SavedEventForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _EventRow;
    return SavedEventForm(
      generation: BigInt.parse(row.generation),
      form: UnfinishedEventForm(
        baseRevision: RevisionId.parse(row.baseRevision),
        representedContext: RecordId.parse(row.representedContext),
        clientRef: row.clientRef,
        label: row.label,
        occurrence: row.occurrence,
        description: row.description,
        actionRecord: row.actionRecord,
        actionUniverse: row.actionUniverse,
        time: TemporalValidityInput.fromWire(decodeBrowserInput(row.time)),
        participants: (decodeBrowserInput(row.participants) as CanonicalArray)
            .items
            .map(EventParticipantInput.fromWire),
        effects: row.effects?.toDart.map(_readEffect),
        preconditions: row.preconditions == null
            ? null
            : (decodeBrowserInput(row.preconditions!) as CanonicalArray).items
                  .map(ExpressionInput.fromWire),
        worlds: (decodeBrowserInput(row.worlds) as CanonicalArray).items.map(
          wireString,
        ),
        regionRecord: row.regionRecord,
        regionUniverse: row.regionUniverse,
        sequence: row.sequence,
        occurrenceId: row.occurrenceId,
        revisionTarget: row.revisionTarget == null
            ? null
            : ExpressionReferenceInput.fromWire(
                decodeBrowserInput(row.revisionTarget!),
              ),
        expectedRecordVersion: row.expectedRecordVersion == null
            ? null
            : RecordVersionId.parse(row.expectedRecordVersion!),
        original: row.original == null
            ? null
            : RecordPayload.fromWire(
                CanonicalValue.parseWireJson(row.original!),
              ) as EventRecord,
        rationale: row.rationale,
        draftVersion: row.draftVersion == null
            ? null
            : BigInt.parse(row.draftVersion!),
      ),
    );
  }

  Future<SavedEventForm?> load(EditorFormScope scope) {
    final result = Completer<SavedEventForm?>();
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

  Future<SavedEventForm> save(
    EditorFormScope scope,
    UnfinishedEventForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Event form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedEventForm>();
    SavedEventForm? saved;
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
          saved = SavedEventForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(
            _EventRow(
              generation: saved!.generation.toString(),
              baseRevision: form.baseRevision.value,
              representedContext: form.representedContext.value,
              clientRef: form.clientRef,
              label: form.label,
              occurrence: form.occurrence,
              description: form.description,
              actionRecord: form.actionRecord,
              actionUniverse: form.actionUniverse,
              time: encodeBrowserInput(form.time.toWire())!,
              participants: encodeBrowserInput(
                CanonicalArray(form.participants.map((v) => v.toWire())),
              )!,
              effects: form.effects?.map(_writeEffect).toList().toJS,
              preconditions: form.preconditions == null
                  ? null
                  : encodeBrowserInput(
                      CanonicalArray(
                        form.preconditions!.map((v) => v.toWire()),
                      ),
                    ),
              worlds: encodeBrowserInput(
                CanonicalArray(form.worlds.map(CanonicalString.new)),
              )!,
              regionRecord: form.regionRecord,
              regionUniverse: form.regionUniverse,
              sequence: form.sequence,
              occurrenceId: form.occurrenceId,
              revisionTarget: form.revisionTarget == null
                  ? null
                  : encodeBrowserInput(form.revisionTarget!.toWire()),
              expectedRecordVersion: form.expectedRecordVersion?.value,
              original: form.original?.toWire().toText(),
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

// Retain the domain effect's exact order/validity separately from entered fields.
@JS()
extension type _EffectRow._(JSObject _) implements JSObject {
  external factory _EffectRow({
    required String slot,
    required String propositionRecord,
    required String propositionUniverse,
    required String polarity,
    required String order,
    required JSAny factualScope,
    required JSAny validity,
    String? original,
  });
  external String get slot;
  external String get propositionRecord;
  external String get propositionUniverse;
  external String get polarity;
  external String get order;
  external JSAny get factualScope;
  external JSAny get validity;
  external String? get original;
}

_EffectRow _writeEffect(EventEffectInput input) => _EffectRow(
  slot: input.slot,
  propositionRecord: input.propositionRecord,
  propositionUniverse: input.propositionUniverse,
  polarity: input.polarity,
  order: input.order,
  factualScope: encodeBrowserInput(input.scope.toWire())!,
  validity: encodeBrowserInput(input.validity.toWire())!,
  original: input.original?.toWire().toText(),
);
EventEffectInput _readEffect(_EffectRow row) => EventEffectInput(
  slot: row.slot,
  propositionRecord: row.propositionRecord,
  propositionUniverse: row.propositionUniverse,
  polarity: row.polarity,
  order: row.order,
  scope: ScopeInput.fromWire(decodeBrowserInput(row.factualScope)),
  validity: TemporalValidityInput.fromWire(decodeBrowserInput(row.validity)),
  original: row.original == null
      ? null
      : EntityEffect.fromWire(CanonicalValue.parseWireJson(row.original!)),
);
