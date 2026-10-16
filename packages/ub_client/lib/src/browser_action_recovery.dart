import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';
import 'browser_consequence_fields.dart';

final class BrowserActionFormRecovery {
  const BrowserActionFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserActionFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedActionForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedActionForm> save(
    EditorFormScope scope,
    UnfinishedActionForm form,
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
extension type _ActionRow._(JSObject _) implements JSObject {
  external factory _ActionRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String namespace,
    required String key,
    required JSAny labels,
    required JSAny requirements,
    JSArray<_SlotRow>? slots,
    required JSAny factualScope,
    required JSAny validity,
    JSAny? revisionTarget,
    String? expectedRecordVersion,
    required String rationale,
    String? draftVersion,
    JSAny? originalFields,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get namespace;
  external String get key;
  external JSAny get labels;
  external JSAny get requirements;
  external JSArray<_SlotRow>? get slots;
  external JSAny get factualScope;
  external JSAny get validity;
  external JSAny? get revisionTarget;
  external String? get expectedRecordVersion;
  external String get rationale;
  external String? get draftVersion;
  external JSAny? get originalFields;
}

SavedActionForm _decodeAction(_ActionRow row) {
  return SavedActionForm(
    generation: BigInt.parse(row.generation),
    form: UnfinishedActionForm(
      baseRevision: RevisionId.parse(row.baseRevision),
      representedContext: RecordId.parse(row.representedContext),
      clientRef: row.clientRef,
      namespace: row.namespace,
      key: row.key,
      labels: (decodeBrowserInput(row.labels) as CanonicalArray).items.map(
        PropertyLabelInput.fromWire,
      ),
      requirements: (decodeBrowserInput(row.requirements) as CanonicalArray)
          .items
          .map(ActionRequirementInput.fromWire),
      slots: row.slots?.toDart.map((r) => _readSlot(r)),
      scope: ScopeInput.fromWire(decodeBrowserInput(row.factualScope)),
      validity: TemporalValidityInput.fromWire(
        decodeBrowserInput(row.validity),
      ),
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
          : decodeBrowserAction(row.originalFields!),
      rationale: row.rationale,
      draftVersion: row.draftVersion == null
          ? null
          : BigInt.parse(row.draftVersion!),
    ),
  );
}

_ActionRow _encodeAction(SavedActionForm saved) {
  final form = saved.form;
  return _ActionRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    clientRef: form.clientRef,
    namespace: form.namespace,
    key: form.key,
    labels: encodeBrowserInput(
      CanonicalArray(form.labels.map((v) => v.toWire())),
    )!,
    requirements: encodeBrowserInput(
      CanonicalArray(form.requirements.map((v) => v.toWire())),
    )!,
    slots: form.slots?.map(_writeSlot).toList().toJS,
    factualScope: encodeBrowserInput(form.scope.toWire())!,
    validity: encodeBrowserInput(form.validity.toWire())!,
    revisionTarget: form.revisionTarget == null
        ? null
        : encodeBrowserInput(form.revisionTarget!.toWire()),
    expectedRecordVersion: form.expectedRecordVersion?.value,
    originalFields: form.original == null
        ? null
        : encodeBrowserAction(form.original!),
    rationale: form.rationale,
    draftVersion: form.draftVersion?.toString(),
  );
}

/// Named fields retain unfinished action input and ordered declarations.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserActionFormRecoveryStore {
  BrowserActionFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['action_form'];

  static Future<BrowserActionFormRecoveryStore> open({
    String databaseName = 'ub-action-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserActionFormRecoveryStore>();
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
        result.complete(BrowserActionFormRecoveryStore._(db));
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
      throw const FormatException('Choose the action context.');
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

  SavedActionForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _ActionRow;
    return _decodeAction(row);
  }

  Future<SavedActionForm?> load(EditorFormScope scope) {
    final result = Completer<SavedActionForm?>();
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

  Future<SavedActionForm> save(
    EditorFormScope scope,
    UnfinishedActionForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Action form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedActionForm>();
    SavedActionForm? saved;
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
          saved = SavedActionForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeAction(saved!), key.toJS);
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

// Retained slots keep their exact numeric order as named decimal text.
@JS()
extension type _SlotRow._(JSObject _) implements JSObject {
  external factory _SlotRow({
    required JSAny fields,
    required JSAny target,
    required JSAny condition,
    required JSAny value,
    JSAny? originalFields,
  });
  external JSAny get fields;
  external JSAny get target;
  external JSAny get condition;
  external JSAny get value;
  external JSAny? get originalFields;
}

_SlotRow _writeSlot(ActionSlotInput input) => _SlotRow(
  fields: encodeBrowserInput(
    CanonicalObject(
      input.fields.entries.map(
        (e) => MapEntry(e.key, CanonicalString(e.value)),
      ),
    ),
  )!,
  target: encodeBrowserInput(input.target.toWire())!,
  condition: encodeBrowserInput(input.condition.toWire())!,
  value: encodeBrowserInput(input.value.toWire())!,
  originalFields: input.original == null
      ? null
      : encodeBrowserEffectSlot(input.original!),
);
ActionSlotInput _readSlot(_SlotRow row) => ActionSlotInput(
  fields: {
    for (final e in (decodeBrowserInput(row.fields) as CanonicalObject).fields)
      e.key: wireString(e.value),
  },
  target: ExpressionReferenceInput.fromWire(decodeBrowserInput(row.target)),
  condition: ActionRequirementInput.fromWire(decodeBrowserInput(row.condition)),
  value: QualifierInput.fromWire(decodeBrowserInput(row.value)),
  original: row.originalFields == null
      ? null
      : decodeBrowserEffectSlot(row.originalFields!),
);
