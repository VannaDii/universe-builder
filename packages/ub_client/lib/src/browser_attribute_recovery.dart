import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserAttributeFormRecovery {
  const BrowserAttributeFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserAttributeFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedAttributeForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedAttributeForm> save(
    EditorFormScope scope,
    UnfinishedAttributeForm form,
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
extension type _AttributeRow._(JSObject _) implements JSObject {
  external factory _AttributeRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String draftVersion,
    required JSAny value,
    JSAny? evidence,
    String? validity,
    JSAny? creation,
    JSAny? roles,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get draftVersion;
  external JSAny get value;
  external JSAny? get evidence;
  external String? get validity;
  external JSAny? get creation;
  external JSAny? get roles;
}

/// Named fields retain attribute values, evidence and ordered role input.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserAttributeFormRecoveryStore {
  BrowserAttributeFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['attribute_form'];

  static Future<BrowserAttributeFormRecoveryStore> open({
    String databaseName = 'ub-attribute-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserAttributeFormRecoveryStore>();
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
        result.complete(BrowserAttributeFormRecoveryStore._(db));
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
        scope.attributeClientRef == null ||
        scope.attributeClientRef == '' ||
        scope.worldClientRef != null ||
        scope.worldRecord != null ||
        scope.typeClientRef != null ||
        scope.entityClientRef != null ||
        scope.entityNameRecord != null ||
        scope.entityClassificationRecord != null ||
        scope.entityOperationIndex != null) {
      throw const FormatException('Choose the attribute form context.');
    }
    return [
      scope.instance.value.toJS,
      scope.profile.value.toJS,
      scope.universe.value.toJS,
      scope.continuity.value.toJS,
      scope.representedContext!.value.toJS,
      scope.attributeClientRef!.toJS,
    ];
  }

  SavedAttributeForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _AttributeRow;
    return SavedAttributeForm(
      generation: BigInt.parse(row.generation),
      form: UnfinishedAttributeForm(
        baseRevision: RevisionId.parse(row.baseRevision),
        representedContext: RecordId.parse(row.representedContext),
        clientRef: row.clientRef,
        draftVersion: BigInt.parse(row.draftVersion),
        value: QualifierInput.fromWire(decodeBrowserInput(row.value)),
        evidenceInput: row.evidence == null
            ? null
            : AttributeEvidenceInput.fromWire(
                CanonicalObject([
                  ...(decodeBrowserInput(
                    row.evidence!,
                  ) as CanonicalObject).fields,
                  if (row.validity != null)
                    MapEntry(
                      'validity',
                      CanonicalValue.parseWireJson(row.validity!),
                    ),
                ]),
              ),
        creationInput: row.creation == null
            ? null
            : AttributeCreationInput.fromWire(
                decodeBrowserInput(row.creation!),
              ),
        roles: row.roles == null
            ? null
            : (decodeBrowserInput(row.roles!) as CanonicalArray).items.map(
                PropositionRoleInput.fromWire,
              ),
      ),
    );
  }

  Future<SavedAttributeForm?> load(EditorFormScope scope) {
    final result = Completer<SavedAttributeForm?>();
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

  Future<SavedAttributeForm> save(
    EditorFormScope scope,
    UnfinishedAttributeForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        scope.attributeClientRef != form.clientRef) {
      throw const FormatException('Attribute form context does not match.');
    }
    _binding(scope);
    for (final text in [
      form.clientRef,
      ...form.value.exactTexts,
      if (form.roles != null)
        for (final role in form.roles!) ...role.exactTexts,
      if (form.creationInput != null) ...[
        form.creationInput!.operationRef,
        form.creationInput!.propertyRecord,
        form.creationInput!.propertyUniverse,
      ],
      if (form.evidenceInput != null) ...form.evidenceInput!.exactTexts,
    ]) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedAttributeForm>();
    SavedAttributeForm? saved;
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
          saved = SavedAttributeForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(
            _AttributeRow(
              generation: saved!.generation.toString(),
              baseRevision: form.baseRevision.value,
              representedContext: form.representedContext.value,
              clientRef: form.clientRef,
              draftVersion: form.draftVersion.toString(),
              value: encodeBrowserInput(form.value.toWire())!,
              evidence: form.evidenceInput == null
                  ? null
                  : encodeBrowserInput(
                      CanonicalObject(
                        form.evidenceInput!.toWire().fields.where(
                          (field) => field.key != 'validity',
                        ),
                      ),
                    ),
              validity: form.evidenceInput?.validity?.toWire().toText(),
              creation: form.creationInput == null
                  ? null
                  : encodeBrowserInput(form.creationInput!.toWire()),
              roles: form.roles == null
                  ? null
                  : encodeBrowserInput(
                      CanonicalArray(form.roles!.map((role) => role.toWire())),
                    ),
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
