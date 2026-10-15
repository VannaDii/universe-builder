import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserAppearanceFormRecovery {
  const BrowserAppearanceFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserAppearanceFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedAppearanceForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedAppearanceForm> save(
    EditorFormScope scope,
    UnfinishedAppearanceForm form,
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
extension type _AppearanceRow._(JSObject _) implements JSObject {
  external factory _AppearanceRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String targetKind,
    required String targetEntry,
    required String targetOwner,
    required String label,
    required String physicalDescription,
    required String atmosphere,
    required String validityKind,
    required String calendar,
    required String start,
    required String end,
    required String rationale,
    required bool startUnbounded,
    required bool endUnbounded,
    String? targetRecord,
    String? targetUniverse,
    String? expectedRecordVersion,
    JSAny? originalFields,
    String? draftVersion,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get targetKind;
  external String get targetEntry;
  external String get targetOwner;
  external String get label;
  external String get physicalDescription;
  external String get atmosphere;
  external String get validityKind;
  external String get calendar;
  external String get start;
  external String get end;
  external String get rationale;
  external bool get startUnbounded;
  external bool get endUnbounded;
  external String? get targetRecord;
  external String? get targetUniverse;
  external String? get expectedRecordVersion;
  external JSAny? get originalFields;
  external String? get original;
  external String? get draftVersion;
}

@JS()
extension type _ImageRow._(JSObject _) implements JSObject {
  external factory _ImageRow({
    required int ordinal,
    required String record,
    required String universe,
    required String caption,
    required String purpose,
    required String preview,
    String? stagedRef,
    String? digest,
    String? mediaType,
    String? byteSize,
    int? width,
    int? height,
    String? originalName,
  });
  external int get ordinal;
  external String get record;
  external String get universe;
  external String get caption;
  external String get purpose;
  external String get preview;
  external String? get stagedRef;
  external String? get digest;
  external String? get mediaType;
  external String? get byteSize;
  external int? get width;
  external int? get height;
  external String? get originalName;
}

@JS()
extension type _LinkRow._(JSObject _) implements JSObject {
  external factory _LinkRow({
    required int ordinal,
    required String record,
    required String universe,
    required String relationship,
    required String note,
  });
  external int get ordinal;
  external String get record;
  external String get universe;
  external String get relationship;
  external String get note;
}

SavedAppearanceForm _decodeAppearance(
  _AppearanceRow row,
  Iterable<_ImageRow> imageRows,
  Iterable<_LinkRow> linkRows, {
  bool legacy = false,
}) {
  return SavedAppearanceForm(
    generation: BigInt.parse(row.generation),
    form: UnfinishedAppearanceForm(
      baseRevision: RevisionId.parse(row.baseRevision),
      representedContext: RecordId.parse(row.representedContext),
      clientRef: row.clientRef,
      targetKind: row.targetKind,
      target: ExpressionReferenceInput(
        record: row.targetEntry,
        universe: row.targetOwner,
      ),
      label: row.label,
      physicalDescription: row.physicalDescription,
      atmosphere: row.atmosphere,
      images: imageRows.map(
        (image) => AppearanceImageInput(
          asset: ExpressionReferenceInput(
            record: image.record,
            universe: image.universe,
          ),
          caption: image.caption,
          purpose: image.purpose,
          preview: image.preview,
          stagedOperation: image.stagedRef == null
              ? null
              : AddImageAssetOperation(
                  clientRef: image.stagedRef!,
                  record: ImageAssetRecord(
                    contentDigest: image.digest!,
                    mediaType: image.mediaType!,
                    byteSize: BigInt.parse(image.byteSize!),
                    width: image.width!,
                    height: image.height!,
                    originalName: image.originalName!,
                  ),
                ),
        ),
      ),
      links: linkRows.map(
        (link) => AppearanceLinkInput(
          entry: ExpressionReferenceInput(
            record: link.record,
            universe: link.universe,
          ),
          relationship: link.relationship,
          note: link.note,
        ),
      ),
      validityKind: row.validityKind,
      calendar: row.calendar,
      start: row.start,
      end: row.end,
      startUnbounded: row.startUnbounded,
      endUnbounded: row.endUnbounded,
      rationale: row.rationale,
      revisionTarget: row.targetRecord == null
          ? null
          : ExpressionReferenceInput(
              record: row.targetRecord!,
              universe: row.targetUniverse!,
            ),
      expectedRecordVersion: row.expectedRecordVersion == null
          ? null
          : RecordVersionId.parse(row.expectedRecordVersion!),
      original: legacy
          ? (row.original == null
                ? null
                : AppearanceRecord.fromWire(
                    CanonicalValue.parseWireJson(row.original!),
                  ))
          : row.originalFields == null
          ? null
          : AppearanceRecord.fromWire(decodeBrowserInput(row.originalFields!)),
      draftVersion: row.draftVersion == null
          ? null
          : BigInt.parse(row.draftVersion!),
    ),
  );
}

_AppearanceRow _encodeAppearance(SavedAppearanceForm saved) {
  final form = saved.form;
  return _AppearanceRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    clientRef: form.clientRef,
    targetKind: form.targetKind,
    targetEntry: form.target.record,
    targetOwner: form.target.universe,
    label: form.label,
    physicalDescription: form.physicalDescription,
    atmosphere: form.atmosphere,
    validityKind: form.validityKind,
    calendar: form.calendar,
    start: form.start,
    end: form.end,
    rationale: form.rationale,
    startUnbounded: form.startUnbounded,
    endUnbounded: form.endUnbounded,
    targetRecord: form.revisionTarget?.record,
    targetUniverse: form.revisionTarget?.universe,
    expectedRecordVersion: form.expectedRecordVersion?.value,
    originalFields: form.original == null
        ? null
        : encodeBrowserInput(form.original!.toWire()),
    draftVersion: form.draftVersion?.toString(),
  );
}

final class BrowserAppearanceFormRecoveryStore {
  BrowserAppearanceFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = [
    'appearance_form',
    'appearance_image',
    'appearance_link',
  ];
  static Future<BrowserAppearanceFormRecoveryStore> open({
    String databaseName = 'ub-appearance-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserAppearanceFormRecoveryStore>();
      final request = web.window.indexedDB.open(databaseName, 2);
      void fail() {
        if (!result.isCompleted) {
          result.completeError(
            const EditorRecoveryException(EditorRecoveryFailure.unavailable),
          );
        }
      }

      request.onupgradeneeded = ((web.Event event) {
        final db = request.result as web.IDBDatabase, tx = request.transaction!;
        try {
          if ((event as web.IDBVersionChangeEvent).oldVersion == 0) {
            for (final table in _tables) {
              db.createObjectStore(table);
            }
          } else {
            final scan = tx.objectStore(_tables.first).openCursor();
            scan.onsuccess = ((web.Event _) {
              try {
                if (scan.result == null || scan.result.isUndefined) return;
                final cursor = scan.result as web.IDBCursorWithValue;
                cursor.update(
                  _encodeAppearance(
                    _decodeAppearance(
                      cursor.value as _AppearanceRow,
                      [],
                      [],
                      legacy: true,
                    ),
                  ),
                );
                cursor.continue_();
              } catch (_) {
                tx.abort();
              }
            }).toJS;
          }
        } catch (_) {
          tx.abort();
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
        result.complete(BrowserAppearanceFormRecoveryStore._(db));
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
      throw const FormatException('Choose the appearance context.');
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

  web.IDBKeyRange _children(List<JSAny> key) => web.IDBKeyRange.bound(
    key.toJS,
    [...key, <JSAny>[].toJS].toJS,
    false,
    true,
  );

  SavedAppearanceForm? _read(
    web.IDBRequest main,
    web.IDBRequest scopes,
    web.IDBRequest knowers,
  ) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _AppearanceRow;
    final imageRows = (scopes.result as JSArray<_ImageRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    final linkRows = (knowers.result as JSArray<_LinkRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return _decodeAppearance(row, imageRows, linkRows);
  }

  Future<SavedAppearanceForm?> load(EditorFormScope scope) {
    final result = Completer<SavedAppearanceForm?>();
    try {
      final key = _binding(scope), range = _children(_binding(scope));
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readonly',
      );
      final main = tx.objectStore(_tables[0]).get(key.toJS);
      final scopes = tx.objectStore(_tables[1]).getAll(range);
      final knowers = tx.objectStore(_tables[2]).getAll(range);
      tx.oncomplete = ((web.Event _) {
        try {
          result.complete(_read(main, scopes, knowers));
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

  Future<SavedAppearanceForm> save(
    EditorFormScope scope,
    UnfinishedAppearanceForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.recoveryKey)) {
      throw const FormatException('Appearance form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedAppearanceForm>();
    SavedAppearanceForm? saved;
    EditorRecoveryException? failure;
    try {
      final key = _binding(scope), range = _children(_binding(scope));
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readwrite',
        web.IDBTransactionOptions(durability: 'strict'),
      );
      final primary = tx.objectStore(_tables[0]),
          scopeStore = tx.objectStore(_tables[1]),
          knowerStore = tx.objectStore(_tables[2]);
      final main = primary.get(key.toJS),
          scopes = scopeStore.getAll(range),
          knowers = knowerStore.getAll(range);
      // Queue writes synchronously in the final read's success callback, while
      // the transaction is active; awaiting a later task could auto-commit it.
      knowers.onsuccess = ((web.Event _) {
        try {
          final current = _read(main, scopes, knowers),
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
          saved = SavedAppearanceForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeAppearance(saved!), key.toJS);
          scopeStore.delete(range);
          knowerStore.delete(range);
          for (var i = 0; i < form.images.length; i++) {
            final image = form.images[i],
                op = image.stagedOperation,
                asset = op?.record;
            scopeStore.put(
              _ImageRow(
                ordinal: i,
                record: image.asset.record,
                universe: image.asset.universe,
                caption: image.caption,
                purpose: image.purpose,
                preview: image.preview,
                stagedRef: op?.clientRef,
                digest: asset?.contentDigest,
                mediaType: asset?.mediaType,
                byteSize: asset?.byteSize.toString(),
                width: asset?.width,
                height: asset?.height,
                originalName: asset?.originalName,
              ),
              [...key, i.toJS].toJS,
            );
          }
          for (var i = 0; i < form.links.length; i++) {
            final link = form.links[i];
            knowerStore.put(
              _LinkRow(
                ordinal: i,
                record: link.entry.record,
                universe: link.entry.universe,
                relationship: link.relationship,
                note: link.note,
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
