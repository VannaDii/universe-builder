import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _ImportRow._(JSObject _) implements JSObject {
  external factory _ImportRow({
    required String generation,
    required String operation,
    required String name,
    required String mode,
    required String phase,
    required String fileName,
    _ReviewFields? reviewFields,
    _ReceiptFields? receiptFields,
  });
  external String get generation;
  external String get operation;
  external String get name;
  external String get mode;
  external String get phase;
  external String get fileName;
  external _ReviewFields? get reviewFields;
  external _ReceiptFields? get receiptFields;
  // Version-one values are read only within the upgrade transaction.
  external String? get review;
  external String? get receipt;
}

@JS()
extension type _ReviewFields._(JSObject _) implements JSObject {
  external factory _ReviewFields({
    String? previewId,
    String? digest,
    String? sourceUniverse,
    String? targetUniverse,
    String? name,
    String? recordIds,
    String? versionIds,
    String? references,
    String? workflowAndApprovals,
    String? omittedRecords,
    String? recordCount,
    bool? complete,
    bool? includesHistory,
    bool? includesWorkflow,
    bool? canonical,
    JSArray<JSString>? conflicts,
  });
  external String? get previewId;
  external String? get digest;
  external String? get sourceUniverse;
  external String? get targetUniverse;
  external String? get name;
  external String? get recordIds;
  external String? get versionIds;
  external String? get references;
  external String? get workflowAndApprovals;
  external String? get omittedRecords;
  external String? get recordCount;
  external bool? get complete;
  external bool? get includesHistory;
  external bool? get includesWorkflow;
  external bool? get canonical;
  external JSArray<JSString>? get conflicts;
}

@JS()
extension type _ReceiptFields._(JSObject _) implements JSObject {
  external factory _ReceiptFields({
    String? previewId,
    String? digest,
    String? universeId,
    String? name,
    String? omittedRecords,
    bool? complete,
    bool? imported,
  });
  external String? get previewId;
  external String? get digest;
  external String? get universeId;
  external String? get name;
  external String? get omittedRecords;
  external bool? get complete;
  external bool? get imported;
}

_ReviewFields? _encodeReview(CanonicalObject? value) {
  if (value == null) return null;
  final fields = Map.fromEntries(value.fields);
  if (fields.keys.any(
    (k) => !{
      'preview_id',
      'digest',
      'source_universe',
      'target_universe',
      'name',
      'record_ids',
      'version_ids',
      'references',
      'workflow_and_approvals',
      'omitted_records',
      'record_count',
      'complete',
      'includes_history',
      'includes_workflow',
      'canonical',
      'conflicts',
    }.contains(k),
  )) {
    throw const FormatException('Unsupported import report field');
  }
  return _ReviewFields(
    previewId: fields.containsKey('preview_id')
        ? (fields['preview_id'] as CanonicalString).value
        : null,
    digest: fields.containsKey('digest')
        ? (fields['digest'] as CanonicalString).value
        : null,
    sourceUniverse: fields.containsKey('source_universe')
        ? (fields['source_universe'] as CanonicalString).value
        : null,
    targetUniverse: fields.containsKey('target_universe')
        ? (fields['target_universe'] as CanonicalString).value
        : null,
    name: fields.containsKey('name')
        ? (fields['name'] as CanonicalString).value
        : null,
    recordIds: fields.containsKey('record_ids')
        ? (fields['record_ids'] as CanonicalString).value
        : null,
    versionIds: fields.containsKey('version_ids')
        ? (fields['version_ids'] as CanonicalString).value
        : null,
    references: fields.containsKey('references')
        ? (fields['references'] as CanonicalString).value
        : null,
    workflowAndApprovals: fields.containsKey('workflow_and_approvals')
        ? (fields['workflow_and_approvals'] as CanonicalString).value
        : null,
    omittedRecords: fields.containsKey('omitted_records')
        ? (fields['omitted_records'] as CanonicalNumber).digits
        : null,
    recordCount: fields.containsKey('record_count')
        ? (fields['record_count'] as CanonicalNumber).digits
        : null,
    complete: fields.containsKey('complete')
        ? (fields['complete'] as CanonicalBool).value
        : null,
    includesHistory: fields.containsKey('includes_history')
        ? (fields['includes_history'] as CanonicalBool).value
        : null,
    includesWorkflow: fields.containsKey('includes_workflow')
        ? (fields['includes_workflow'] as CanonicalBool).value
        : null,
    canonical: fields.containsKey('canonical')
        ? (fields['canonical'] as CanonicalBool).value
        : null,
    conflicts: fields.containsKey('conflicts')
        ? (fields['conflicts'] as CanonicalArray).items
              .map((v) => (v as CanonicalString).value.toJS)
              .toList()
              .toJS
        : null,
  );
}

_ReceiptFields? _encodeReceipt(CanonicalObject? value) {
  if (value == null) return null;
  final fields = Map.fromEntries(value.fields);
  if (fields.keys.any(
    (k) => !{
      'preview_id',
      'digest',
      'universe_id',
      'name',
      'omitted_records',
      'complete',
      'imported',
    }.contains(k),
  )) {
    throw const FormatException('Unsupported import report field');
  }
  return _ReceiptFields(
    previewId: fields.containsKey('preview_id')
        ? (fields['preview_id'] as CanonicalString).value
        : null,
    digest: fields.containsKey('digest')
        ? (fields['digest'] as CanonicalString).value
        : null,
    universeId: fields.containsKey('universe_id')
        ? (fields['universe_id'] as CanonicalString).value
        : null,
    name: fields.containsKey('name')
        ? (fields['name'] as CanonicalString).value
        : null,
    omittedRecords: fields.containsKey('omitted_records')
        ? (fields['omitted_records'] as CanonicalNumber).digits
        : null,
    complete: fields.containsKey('complete')
        ? (fields['complete'] as CanonicalBool).value
        : null,
    imported: fields.containsKey('imported')
        ? (fields['imported'] as CanonicalBool).value
        : null,
  );
}

CanonicalObject? _decodeReview(_ReviewFields? row) => row == null
    ? null
    : CanonicalObject([
        if (row.previewId != null)
          MapEntry('preview_id', CanonicalString(row.previewId!)),
        if (row.digest != null)
          MapEntry('digest', CanonicalString(row.digest!)),
        if (row.sourceUniverse != null)
          MapEntry('source_universe', CanonicalString(row.sourceUniverse!)),
        if (row.targetUniverse != null)
          MapEntry('target_universe', CanonicalString(row.targetUniverse!)),
        if (row.name != null) MapEntry('name', CanonicalString(row.name!)),
        if (row.recordIds != null)
          MapEntry('record_ids', CanonicalString(row.recordIds!)),
        if (row.versionIds != null)
          MapEntry('version_ids', CanonicalString(row.versionIds!)),
        if (row.references != null)
          MapEntry('references', CanonicalString(row.references!)),
        if (row.workflowAndApprovals != null)
          MapEntry(
            'workflow_and_approvals',
            CanonicalString(row.workflowAndApprovals!),
          ),
        if (row.omittedRecords != null)
          MapEntry('omitted_records', CanonicalNumber(row.omittedRecords!)),
        if (row.recordCount != null)
          MapEntry('record_count', CanonicalNumber(row.recordCount!)),
        if (row.complete != null)
          MapEntry('complete', CanonicalBool(row.complete!)),
        if (row.includesHistory != null)
          MapEntry('includes_history', CanonicalBool(row.includesHistory!)),
        if (row.includesWorkflow != null)
          MapEntry('includes_workflow', CanonicalBool(row.includesWorkflow!)),
        if (row.canonical != null)
          MapEntry('canonical', CanonicalBool(row.canonical!)),
        if (row.conflicts != null)
          MapEntry(
            'conflicts',
            CanonicalArray(
              row.conflicts!.toDart.map((v) => CanonicalString(v.toDart)),
            ),
          ),
      ]);
CanonicalObject? _decodeReceipt(_ReceiptFields? row) => row == null
    ? null
    : CanonicalObject([
        if (row.previewId != null)
          MapEntry('preview_id', CanonicalString(row.previewId!)),
        if (row.digest != null)
          MapEntry('digest', CanonicalString(row.digest!)),
        if (row.universeId != null)
          MapEntry('universe_id', CanonicalString(row.universeId!)),
        if (row.name != null) MapEntry('name', CanonicalString(row.name!)),
        if (row.omittedRecords != null)
          MapEntry('omitted_records', CanonicalNumber(row.omittedRecords!)),
        if (row.complete != null)
          MapEntry('complete', CanonicalBool(row.complete!)),
        if (row.imported != null)
          MapEntry('imported', CanonicalBool(row.imported!)),
      ]);
_ImportRow _encodeRow(SavedPackageImport saved) => _ImportRow(
  generation: saved.generation.toString(),
  operation: saved.form.operation.value,
  name: saved.form.name,
  mode: saved.form.mode.name,
  phase: saved.form.phase.name,
  fileName: saved.form.fileName,
  reviewFields: _encodeReview(saved.form.review),
  receiptFields: _encodeReceipt(saved.form.receipt),
);
SavedPackageImport _decodeRow(
  _ImportRow row, {
  bool legacy = false,
}) => SavedPackageImport(
  generation: BigInt.parse(row.generation),
  form: PackageImportDraft(
    operation: OperationId.parse(row.operation),
    name: row.name,
    mode: ImportMode.fromName(row.mode),
    phase: PackageImportPhase.values.byName(row.phase),
    fileName: row.fileName,
    review: legacy
        ? (row.review == null
              ? null
              : CanonicalValue.parseWireJson(row.review!) as CanonicalObject)
        : _decodeReview(row.reviewFields),
    receipt: legacy
        ? (row.receipt == null
              ? null
              : CanonicalValue.parseWireJson(row.receipt!) as CanonicalObject)
        : _decodeReceipt(row.receiptFields),
  ),
);

/// Named fields retain import choices and domain review/receipt records.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains private import recovery metadata, never service credentials.
final class BrowserPackageImportFormRecoveryStore {
  BrowserPackageImportFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['package_import_form'];

  static Future<BrowserPackageImportFormRecoveryStore> open({
    String databaseName = 'ub-package-import-recovery',
  }) async {
    try {
      final result = Completer<BrowserPackageImportFormRecoveryStore>();
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
        final transaction = request.transaction!;
        try {
          if ((event as web.IDBVersionChangeEvent).oldVersion == 0) {
            db.createObjectStore(_tables.single);
          } else {
            final scan = transaction.objectStore(_tables.single).openCursor();
            scan.onsuccess = ((web.Event _) {
              try {
                if (scan.result == null || scan.result.isUndefined) return;
                final cursor = scan.result as web.IDBCursorWithValue;
                cursor.update(
                  _encodeRow(
                    _decodeRow(cursor.value as _ImportRow, legacy: true),
                  ),
                );
                cursor.continue_();
              } catch (_) {
                transaction.abort();
              }
            }).toJS;
          }
        } catch (_) {
          transaction.abort();
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
        result.complete(BrowserPackageImportFormRecoveryStore._(db));
      }).toJS;
      return await result.future;
    } on EditorRecoveryException {
      rethrow;
    } on Object {
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  List<JSAny> _binding((OperationId, ProfileId) scope) => [
    scope.$1.value.toJS,
    scope.$2.value.toJS,
  ];

  SavedPackageImport? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    return _decodeRow(main.result as _ImportRow);
  }

  Future<SavedPackageImport?> load((OperationId, ProfileId) scope) {
    final result = Completer<SavedPackageImport?>();
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

  Future<SavedPackageImport> save(
    (OperationId, ProfileId) scope,
    PackageImportDraft form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    for (final text in [form.name, form.fileName, form.toWire().toText()]) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedPackageImport>();
    SavedPackageImport? saved;
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
          saved = SavedPackageImport(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeRow(saved!), key.toJS);
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
