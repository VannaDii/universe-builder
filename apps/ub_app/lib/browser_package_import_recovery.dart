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
    String? review,
    String? receipt,
  });
  external String get generation;
  external String get operation;
  external String get name;
  external String get mode;
  external String get phase;
  external String get fileName;
  external String? get review;
  external String? get receipt;
}

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
    final row = main.result as _ImportRow;
    return SavedPackageImport(
      generation: BigInt.parse(row.generation),
      form: PackageImportDraft(
        operation: OperationId.parse(row.operation),
        name: row.name,
        mode: ImportMode.values.byName(row.mode),
        phase: PackageImportPhase.values.byName(row.phase),
        fileName: row.fileName,
        review: row.review == null
            ? null
            : CanonicalValue.parseWireJson(row.review!) as CanonicalObject,
        receipt: row.receipt == null
            ? null
            : CanonicalValue.parseWireJson(row.receipt!) as CanonicalObject,
      ),
    );
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
          primary.put(
            _ImportRow(
              generation: saved!.generation.toString(),
              operation: form.operation.value,
              name: form.name,
              mode: form.mode.name,
              phase: form.phase.name,
              fileName: form.fileName,
              review: form.review?.toText(),
              receipt: form.receipt?.toText(),
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
