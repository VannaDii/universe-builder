import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserPropositionFormRecovery {
  const BrowserPropositionFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserPropositionFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedPropositionForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedPropositionForm> save(
    EditorFormScope scope,
    UnfinishedPropositionForm form,
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
extension type _PropositionRow._(JSObject _) implements JSObject {
  external factory _PropositionRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required JSAny subject,
    required JSAny predicate,
    required JSAny context,
    required JSAny roles,
    required String quantification,
    required bool hasValue,
    required JSAny value,
    required String rationale,
    String? draftVersion,
    JSAny? originalFields,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external JSAny get subject;
  external JSAny get predicate;
  external JSAny get context;
  external JSAny get roles;
  external String get quantification;
  external bool get hasValue;
  external JSAny get value;
  external String get rationale;
  external String? get draftVersion;
  external JSAny? get originalFields;
}

SavedPropositionForm _decodeProposition(_PropositionRow row) {
  return SavedPropositionForm(
    generation: BigInt.parse(row.generation),
    form: UnfinishedPropositionForm(
      baseRevision: RevisionId.parse(row.baseRevision),
      representedContext: RecordId.parse(row.representedContext),
      clientRef: row.clientRef,
      subject: ExpressionReferenceInput.fromWire(
        decodeBrowserInput(row.subject),
      ),
      predicate: ExpressionReferenceInput.fromWire(
        decodeBrowserInput(row.predicate),
      ),
      context: ExpressionReferenceInput.fromWire(
        decodeBrowserInput(row.context),
      ),
      roles: (decodeBrowserInput(row.roles) as CanonicalArray).items.map(
        PropositionRoleInput.fromWire,
      ),
      quantification: row.quantification,
      hasValue: row.hasValue,
      value: QualifierInput.fromWire(decodeBrowserInput(row.value)),
      original: row.originalFields == null
          ? null
          : PropositionRecord.fromWire(decodeBrowserInput(row.originalFields!)),
      rationale: row.rationale,
      draftVersion: row.draftVersion == null
          ? null
          : BigInt.parse(row.draftVersion!),
    ),
  );
}

_PropositionRow _encodeProposition(SavedPropositionForm saved) {
  final form = saved.form;
  return _PropositionRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    clientRef: form.clientRef,
    subject: encodeBrowserInput(form.subject.toWire())!,
    predicate: encodeBrowserInput(form.predicate.toWire())!,
    context: encodeBrowserInput(form.context.toWire())!,
    roles: encodeBrowserInput(
      CanonicalArray(form.roles.map((role) => role.toWire())),
    )!,
    quantification: form.quantification,
    hasValue: form.hasValue,
    value: encodeBrowserInput(form.value.toWire())!,
    originalFields: form.original == null
        ? null
        : encodeBrowserInput(form.original!.toWire()),
    rationale: form.rationale,
    draftVersion: form.draftVersion?.toString(),
  );
}

/// Named fields retain proposition references, ordered roles and nested value input.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserPropositionFormRecoveryStore {
  BrowserPropositionFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['proposition_form'];

  static Future<BrowserPropositionFormRecoveryStore> open({
    String databaseName = 'ub-proposition-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserPropositionFormRecoveryStore>();
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
        result.complete(BrowserPropositionFormRecoveryStore._(db));
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
      throw const FormatException('Choose the proposition context.');
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

  SavedPropositionForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _PropositionRow;
    return _decodeProposition(row);
  }

  Future<SavedPropositionForm?> load(EditorFormScope scope) {
    final result = Completer<SavedPropositionForm?>();
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

  Future<SavedPropositionForm> save(
    EditorFormScope scope,
    UnfinishedPropositionForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Proposition form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedPropositionForm>();
    SavedPropositionForm? saved;
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
          saved = SavedPropositionForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeProposition(saved!), key.toJS);
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
