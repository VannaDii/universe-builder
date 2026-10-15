import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserRuleFormRecovery {
  const BrowserRuleFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserRuleFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedRuleForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedRuleForm> save(
    EditorFormScope scope,
    UnfinishedRuleForm form,
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
extension type _RuleRow._(JSObject _) implements JSObject {
  external factory _RuleRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String namespace,
    required String key,
    required JSAny labels,
    required String kind,
    required String commitPolicy,
    required JSAny factualScope,
    required JSAny subjectTypes,
    required JSAny targetPredicates,
    required JSAny capabilities,
    required JSAny expression,
    bool? executable,
    required JSAny validity,
    JSAny? knowledge,
    JSAny? constraints,
    JSAny? evidence,
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
  external String get namespace;
  external String get key;
  external JSAny get labels;
  external String get kind;
  external String get commitPolicy;
  external JSAny get factualScope;
  external JSAny get subjectTypes;
  external JSAny get targetPredicates;
  external JSAny get capabilities;
  external JSAny get expression;
  external bool? get executable;
  external JSAny get validity;
  external JSAny? get knowledge;
  external JSAny? get constraints;
  external JSAny? get evidence;
  external JSAny? get revisionTarget;
  external String? get expectedRecordVersion;
  external String get rationale;
  external String? get draftVersion;
  external String? get original;
}

/// Named fields retain unfinished rule input and ordered declarations.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserRuleFormRecoveryStore {
  BrowserRuleFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['rule_form'];

  static Future<BrowserRuleFormRecoveryStore> open({
    String databaseName = 'ub-rule-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserRuleFormRecoveryStore>();
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
        result.complete(BrowserRuleFormRecoveryStore._(db));
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
      throw const FormatException('Choose the rule context.');
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

  SavedRuleForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _RuleRow;
    return SavedRuleForm(
      generation: BigInt.parse(row.generation),
      form: UnfinishedRuleForm(
        baseRevision: RevisionId.parse(row.baseRevision),
        representedContext: RecordId.parse(row.representedContext),
        clientRef: row.clientRef,
        namespace: row.namespace,
        key: row.key,
        labels: (decodeBrowserInput(row.labels) as CanonicalArray).items.map(
          PropertyLabelInput.fromWire,
        ),
        kind: row.kind,
        commitPolicy: row.commitPolicy,
        scope: ScopeInput.fromWire(decodeBrowserInput(row.factualScope)),
        subjectTypes: (decodeBrowserInput(row.subjectTypes) as CanonicalArray)
            .items
            .map(wireString),
        targetPredicates: (decodeBrowserInput(
          row.targetPredicates,
        ) as CanonicalArray).items.map(wireString),
        capabilities: (decodeBrowserInput(row.capabilities) as CanonicalArray)
            .items
            .map(wireString),
        expression: ExpressionInput.fromWire(
          decodeBrowserInput(row.expression),
        ),
        executable: row.executable,
        validity: TemporalValidityInput.fromWire(
          decodeBrowserInput(row.validity),
        ),
        evidence: row.evidence == null
            ? null
            : RuleEvidenceInput.fromWire(decodeBrowserInput(row.evidence!)),
        knowledge: row.knowledge == null
            ? null
            : RuleKnowledgeInput.fromWire(decodeBrowserInput(row.knowledge!)),
        constraints: row.constraints == null
            ? null
            : RuleConstraintInput.fromWire(
                decodeBrowserInput(row.constraints!),
              ),
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
            : RuleRecord.fromWire(CanonicalValue.parseWireJson(row.original!)),
        rationale: row.rationale,
        draftVersion: row.draftVersion == null
            ? null
            : BigInt.parse(row.draftVersion!),
      ),
    );
  }

  Future<SavedRuleForm?> load(EditorFormScope scope) {
    final result = Completer<SavedRuleForm?>();
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

  Future<SavedRuleForm> save(
    EditorFormScope scope,
    UnfinishedRuleForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Rule form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedRuleForm>();
    SavedRuleForm? saved;
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
          saved = SavedRuleForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(
            _RuleRow(
              generation: saved!.generation.toString(),
              baseRevision: form.baseRevision.value,
              representedContext: form.representedContext.value,
              clientRef: form.clientRef,
              namespace: form.namespace,
              key: form.key,
              labels: encodeBrowserInput(
                CanonicalArray(form.labels.map((v) => v.toWire())),
              )!,
              kind: form.kind,
              commitPolicy: form.commitPolicy,
              factualScope: encodeBrowserInput(form.scope.toWire())!,
              subjectTypes: encodeBrowserInput(
                CanonicalArray(form.subjectTypes.map(CanonicalString.new)),
              )!,
              targetPredicates: encodeBrowserInput(
                CanonicalArray(form.targetPredicates.map(CanonicalString.new)),
              )!,
              capabilities: encodeBrowserInput(
                CanonicalArray(form.capabilities.map(CanonicalString.new)),
              )!,
              expression: encodeBrowserInput(form.expression.toWire())!,
              executable: form.executable,
              validity: encodeBrowserInput(form.validity.toWire())!,
              evidence: form.evidence == null
                  ? null
                  : encodeBrowserInput(form.evidence!.toWire()),
              knowledge: form.knowledge == null
                  ? null
                  : encodeBrowserInput(form.knowledge!.toWire()),
              constraints: form.constraints == null
                  ? null
                  : encodeBrowserInput(form.constraints!.toWire()),
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
