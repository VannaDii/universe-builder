import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _CreationRow._(JSObject _) implements JSObject {
  external factory _CreationRow({
    required String generation,
    required String name,
    required String calendar,
    required String date,
    required String time,
    required String offset,
    required String calendarName,
    required String initialTick,
    required String tickLabel,
    required String ticksPerMonth,
    required bool creationPending,
  });
  external String get generation;
  external String get name;
  external String get calendar;
  external String get date;
  external String get time;
  external String get offset;
  external String get calendarName;
  external String get initialTick;
  external String get tickLabel;
  external String get ticksPerMonth;
  external bool get creationPending;
}

/// Named fields retain unfinished universe creation, including an unknown attempt.
/// IndexedDB transactions compare generations and commit each form atomically.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains private creation input, never service credentials.
final class BrowserUniverseCreationFormRecoveryStore {
  BrowserUniverseCreationFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = ['universe_creation_form'];

  static Future<BrowserUniverseCreationFormRecoveryStore> open({
    String databaseName = 'ub-universe-creation-recovery',
  }) async {
    try {
      final result = Completer<BrowserUniverseCreationFormRecoveryStore>();
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
        result.complete(BrowserUniverseCreationFormRecoveryStore._(db));
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

  SavedUniverseCreationForm? _read(web.IDBRequest main) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _CreationRow;
    return SavedUniverseCreationForm(
      generation: BigInt.parse(row.generation),
      form: UniverseCreationForm(
        name: row.name,
        calendar: CreationCalendar.values.byName(row.calendar),
        date: row.date,
        time: row.time,
        offset: row.offset,
        calendarName: row.calendarName,
        initialTick: row.initialTick,
        tickLabel: row.tickLabel,
        ticksPerMonth: row.ticksPerMonth,
        creationPending: row.creationPending,
      ),
    );
  }

  Future<SavedUniverseCreationForm?> load((OperationId, ProfileId) scope) {
    final result = Completer<SavedUniverseCreationForm?>();
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

  Future<SavedUniverseCreationForm> save(
    (OperationId, ProfileId) scope,
    UniverseCreationForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    for (final text in [
      form.name,
      form.date,
      form.time,
      form.offset,
      form.calendarName,
      form.initialTick,
      form.tickLabel,
      form.ticksPerMonth,
    ]) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedUniverseCreationForm>();
    SavedUniverseCreationForm? saved;
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
          saved = SavedUniverseCreationForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(
            _CreationRow(
              generation: saved!.generation.toString(),
              name: form.name,
              calendar: form.calendar.name,
              date: form.date,
              time: form.time,
              offset: form.offset,
              calendarName: form.calendarName,
              initialTick: form.initialTick,
              tickLabel: form.tickLabel,
              ticksPerMonth: form.ticksPerMonth,
              creationPending: form.creationPending,
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
