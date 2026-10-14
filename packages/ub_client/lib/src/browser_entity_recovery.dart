import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserEntityFormRecovery {
  const BrowserEntityFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserEntityFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedEntityForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedEntityForm> save(
    EditorFormScope scope,
    UnfinishedEntityForm form,
    BigInt expectedGeneration,
  ) {
    // A disconnected writer can retain input without acquiring service authority.
    if (scope.profile != principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    return store.save(scope, form, expectedGeneration);
  }
}

Iterable<String> _temporalTexts(TemporalValidityInput input) sync* {
  yield* [
    input.kind,
    input.calendar,
    input.relation,
    input.targetUniverse,
    input.targetRecord,
  ];
  for (final bound in [input.start, input.end]) {
    yield* [
      bound.kind,
      bound.value,
      bound.upper,
      bound.uncertaintyKind,
      bound.uncertainty,
      bound.denominator,
      bound.unit,
    ];
    if (bound.amount != null) yield* bound.amount!.exactTexts;
  }
}

@JS()
extension type _EntityRow._(JSObject _) implements JSObject {
  external factory _EntityRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String name,
    required String classification,
    required String worldRole,
    required String rationale,
    required bool associationsPresent,
    String? draftVersion,
    String? expectedRecordVersion,
    bool? namePresent,
    String? language,
    String? community,
    String? role,
    String? validity,
    JSAny? temporal,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get name;
  external String get classification;
  external String get worldRole;
  external String get rationale;
  external bool get associationsPresent;
  external String? get draftVersion;
  external String? get expectedRecordVersion;
  external bool? get namePresent;
  external String? get language;
  external String? get community;
  external String? get role;
  external String? get validity;
  external JSAny? get temporal;
}

@JS()
extension type _WorldRow._(JSObject _) implements JSObject {
  external factory _WorldRow({required int ordinal, required String value});
  external int get ordinal;
  external String get value;
}

@JS()
extension type _AssociationRow._(JSObject _) implements JSObject {
  external factory _AssociationRow({
    required int ordinal,
    required String world,
    required String role,
    int? originalOrdinal,
    String? validity,
    JSAny? temporal,
    JSAny? qualifiers,
  });
  external int get ordinal;
  external String get world;
  external String get role;
  external int? get originalOrdinal;
  external String? get validity;
  external JSAny? get temporal;
  external JSAny? get qualifiers;
}

/// Named fields and ordered child rows, never a serialized UI-state blob.
/// IndexedDB transactions compare generations and commit all children together.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserEntityFormRecoveryStore {
  BrowserEntityFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = [
    'entity_form',
    'entity_form_world',
    'entity_form_association',
  ];

  static Future<BrowserEntityFormRecoveryStore> open({
    String databaseName = 'ub-entity-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserEntityFormRecoveryStore>();
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
        result.complete(BrowserEntityFormRecoveryStore._(db));
      }).toJS;
      return await result.future;
    } on EditorRecoveryException {
      rethrow;
    } on Object {
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  List<JSAny> _binding(EditorFormScope scope) {
    final target = scope.entityNameRecord ?? scope.entityClassificationRecord;
    if (scope.representedContext == null ||
        scope.worldClientRef != null ||
        scope.worldRecord != null ||
        scope.typeClientRef != null ||
        scope.entityClientRef == '' ||
        (scope.entityClientRef != null && target != null) ||
        (scope.entityNameRecord != null &&
            scope.entityClassificationRecord != null) ||
        (scope.entityOperationIndex != null &&
            (target == null || scope.entityOperationIndex! < 0))) {
      throw const FormatException('Choose the entity form context.');
    }
    final editor = target == null
        ? scope.entityClientRef ?? ''
        : '${scope.entityNameRecord == null ? 'classification' : 'name'}:${target.value}${scope.entityOperationIndex == null ? '' : ':edit:${scope.entityOperationIndex}'}';
    return [
      scope.instance.value.toJS,
      scope.profile.value.toJS,
      scope.universe.value.toJS,
      scope.continuity.value.toJS,
      scope.representedContext!.value.toJS,
      editor.toJS,
    ];
  }

  web.IDBKeyRange _children(List<JSAny> key) => web.IDBKeyRange.bound(
    key.toJS,
    [...key, <JSAny>[].toJS].toJS,
    false,
    true,
  );

  SavedEntityForm? _read(
    web.IDBRequest main,
    web.IDBRequest aliases,
    web.IDBRequest labels,
  ) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _EntityRow;
    final worlds = (aliases.result as JSArray<_WorldRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    final associationRows = (labels.result as JSArray<_AssociationRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return SavedEntityForm(
      generation: BigInt.parse(row.generation),
      form: UnfinishedEntityForm(
        baseRevision: RevisionId.parse(row.baseRevision),
        representedContext: RecordId.parse(row.representedContext),
        clientRef: row.clientRef,
        name: row.name,
        classification: row.classification,
        worldRole: row.worldRole,
        rationale: row.rationale,
        draftVersion: row.draftVersion == null
            ? null
            : BigInt.parse(row.draftVersion!),
        expectedRecordVersion: row.expectedRecordVersion == null
            ? null
            : RecordVersionId.parse(row.expectedRecordVersion!),
        nameDetails: row.namePresent != true
            ? null
            : EntityNameForm(
                language: row.language,
                community: row.community,
                role: row.role,
                validity: row.validity == null
                    ? null
                    : Validity.fromWire(
                        CanonicalValue.parseWireJson(row.validity!),
                      ),
                temporalValidity: row.temporal == null
                    ? null
                    : TemporalValidityInput.fromWire(
                        decodeBrowserInput(row.temporal!),
                      ),
              ),
        worlds: worlds.map((world) => WorldId.parse(world.value)),
        associations: !row.associationsPresent
            ? null
            : associationRows.map(
                (a) => EntityAssociationForm(
                  world: a.world,
                  role: a.role,
                  originalOrdinal: a.originalOrdinal,
                  validity: a.validity == null
                      ? null
                      : Validity.fromWire(
                          CanonicalValue.parseWireJson(a.validity!),
                        ),
                  temporalValidity: a.temporal == null
                      ? null
                      : TemporalValidityInput.fromWire(
                          decodeBrowserInput(a.temporal!),
                        ),
                  qualifiers: a.qualifiers == null
                      ? null
                      : (decodeBrowserInput(a.qualifiers!) as CanonicalArray)
                            .items
                            .map(QualifierInput.fromWire)
                            .toList(),
                ),
              ),
      ),
    );
  }

  Future<SavedEntityForm?> load(EditorFormScope scope) {
    final result = Completer<SavedEntityForm?>();
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

  Future<SavedEntityForm> save(
    EditorFormScope scope,
    UnfinishedEntityForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.entityClientRef != null &&
            scope.entityClientRef != form.clientRef) ||
        ((scope.entityNameRecord ?? scope.entityClassificationRecord) != null &&
            (scope.entityNameRecord ?? scope.entityClassificationRecord)!
                    .value !=
                form.clientRef)) {
      throw const FormatException('Entity form context does not match.');
    }
    _binding(scope);
    for (final text in [
      form.clientRef,
      form.name,
      form.classification,
      form.worldRole,
      form.rationale,
      if (form.nameDetails != null) ...form.nameDetails!.exactTexts,
      for (final association
          in form.associations ?? <EntityAssociationForm>[]) ...[
        association.world,
        association.role,
        if (association.temporalValidity != null)
          ..._temporalTexts(association.temporalValidity!),
        for (final qualifier in association.qualifiers ?? <QualifierInput>[])
          ...qualifier.exactTexts,
      ],
    ]) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedEntityForm>();
    SavedEntityForm? saved;
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
          saved = SavedEntityForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(
            _EntityRow(
              generation: saved!.generation.toString(),
              baseRevision: form.baseRevision.value,
              representedContext: form.representedContext.value,
              clientRef: form.clientRef,
              name: form.name,
              classification: form.classification,
              worldRole: form.worldRole,
              rationale: form.rationale,
              draftVersion: form.draftVersion?.toString(),
              expectedRecordVersion: form.expectedRecordVersion?.value,
              associationsPresent: form.associations != null,
              namePresent: form.nameDetails != null,
              language: form.nameDetails?.language,
              community: form.nameDetails?.community,
              role: form.nameDetails?.role,
              validity: form.nameDetails?.validity?.toWire().toText(),
              temporal: form.nameDetails?.temporalValidity == null
                  ? null
                  : encodeBrowserInput(
                      form.nameDetails!.temporalValidity!.toWire(),
                    ),
            ),
            key.toJS,
          );
          aliasStore.delete(range);
          labelStore.delete(range);
          for (var i = 0; i < form.worlds.length; i++) {
            aliasStore.put(
              _WorldRow(ordinal: i, value: form.worlds[i].value),
              [...key, i.toJS].toJS,
            );
          }
          final associations = form.associations ?? <EntityAssociationForm>[];
          for (var i = 0; i < associations.length; i++) {
            final a = associations[i];
            labelStore.put(
              _AssociationRow(
                ordinal: i,
                world: a.world,
                role: a.role,
                originalOrdinal: a.originalOrdinal,
                validity: a.validity?.toWire().toText(),
                temporal: a.temporalValidity == null
                    ? null
                    : encodeBrowserInput(a.temporalValidity!.toWire()),
                qualifiers: a.qualifiers == null
                    ? null
                    : encodeBrowserInput(
                        CanonicalArray(a.qualifiers!.map((q) => q.toWire())),
                      ),
              ),
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
