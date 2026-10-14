import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserBoundaryFormRecovery {
  const BrowserBoundaryFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserBoundaryFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedBoundaryForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedBoundaryForm> save(
    EditorFormScope scope,
    UnfinishedBoundaryForm form,
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
extension type _BoundaryRow._(JSObject _) implements JSObject {
  external factory _BoundaryRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String key,
    required String areaKind,
    required JSAny record,
    required String predicate,
    required bool subjectEnabled,
    required JSAny subject,
    required String category,
    required String mode,
    required JSAny constraints,
    required JSAny factualScope,
    required JSAny validity,
    required String rationale,
    String? draftVersion,
    String? original,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get key;
  external String get areaKind;
  external JSAny get record;
  external String get predicate;
  external bool get subjectEnabled;
  external JSAny get subject;
  external String get category;
  external String get mode;
  external JSAny get constraints;
  external JSAny get factualScope;
  external JSAny get validity;
  external String get rationale;
  external String? get draftVersion;
  external String? get original;
}

/// Named fields retain boundary areas, modes, ordered constraints and scoped validity input.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserBoundaryFormRecoveryStore {
  BrowserBoundaryFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['boundary_form'];

  static Future<BrowserBoundaryFormRecoveryStore> open({
    String databaseName = 'ub-boundary-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserBoundaryFormRecoveryStore>();
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
        result.complete(BrowserBoundaryFormRecoveryStore._(db));
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
      throw const FormatException('Choose the boundary context.');
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

  SavedBoundaryForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _BoundaryRow;
    return SavedBoundaryForm(
      generation: BigInt.parse(row.generation),
      form: UnfinishedBoundaryForm(
        baseRevision: RevisionId.parse(row.baseRevision),
        representedContext: RecordId.parse(row.representedContext),
        clientRef: row.clientRef,
        key: row.key,
        areaKind: row.areaKind,
        record: ExpressionReferenceInput.fromWire(
          decodeBrowserInput(row.record),
        ),
        predicate: row.predicate,
        subjectEnabled: row.subjectEnabled,
        subject: ExpressionReferenceInput.fromWire(
          decodeBrowserInput(row.subject),
        ),
        category: row.category,
        mode: row.mode,
        constraints: (decodeBrowserInput(row.constraints) as CanonicalArray)
            .items
            .map(ExpressionInput.fromWire),
        scope: ScopeInput.fromWire(decodeBrowserInput(row.factualScope)),
        validity: TemporalValidityInput.fromWire(
          decodeBrowserInput(row.validity),
        ),
        original: row.original == null
            ? null
            : BoundaryRecord.fromWire(
                CanonicalValue.parseWireJson(row.original!),
              ),
        rationale: row.rationale,
        draftVersion: row.draftVersion == null
            ? null
            : BigInt.parse(row.draftVersion!),
      ),
    );
  }

  Future<SavedBoundaryForm?> load(EditorFormScope scope) {
    final result = Completer<SavedBoundaryForm?>();
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

  Future<SavedBoundaryForm> save(
    EditorFormScope scope,
    UnfinishedBoundaryForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Boundary form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedBoundaryForm>();
    SavedBoundaryForm? saved;
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
          saved = SavedBoundaryForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(
            _BoundaryRow(
              generation: saved!.generation.toString(),
              baseRevision: form.baseRevision.value,
              representedContext: form.representedContext.value,
              clientRef: form.clientRef,
              key: form.key,
              areaKind: form.areaKind,
              record: encodeBrowserInput(form.record.toWire())!,
              predicate: form.predicate,
              subjectEnabled: form.subjectEnabled,
              subject: encodeBrowserInput(form.subject.toWire())!,
              category: form.category,
              mode: form.mode,
              constraints: encodeBrowserInput(
                CanonicalArray(form.constraints.map((expr) => expr.toWire())),
              )!,
              factualScope: encodeBrowserInput(form.scope.toWire())!,
              validity: encodeBrowserInput(form.validity.toWire())!,
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
