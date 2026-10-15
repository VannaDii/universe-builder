import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'editor_scope.dart';
import 'browser_input_fields.dart';

final class BrowserCalendarFormRecovery {
  const BrowserCalendarFormRecovery({
    required this.store,
    required this.principal,
    required this.call,
  });
  final BrowserCalendarFormRecoveryStore store;
  final ProfileId principal;
  final Future<CanonicalValue> Function(EngineRequest) call;
  Future<SavedCalendarForm?> load(EditorFormScope scope) async {
    await checkEditorRecoveryScope(
      principal: principal,
      call: call,
      scope: scope,
    );
    return store.load(scope);
  }

  Future<SavedCalendarForm> save(
    EditorFormScope scope,
    UnfinishedCalendarForm form,
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
extension type _CalendarRow._(JSObject _) implements JSObject {
  external factory _CalendarRow({
    required String generation,
    required String baseRevision,
    required String representedContext,
    required String clientRef,
    required String namespace,
    required String key,
    required bool hasEpoch,
    required String epoch,
    required String rationale,
    String? draftVersion,
    JSAny? revisionTarget,
    String? expectedRecordVersion,
    JSAny? originalFields,
  });
  external String get generation;
  external String get baseRevision;
  external String get representedContext;
  external String get clientRef;
  external String get namespace;
  external String get key;
  external bool get hasEpoch;
  external String get epoch;
  external String get rationale;
  external String? get draftVersion;
  external JSAny? get revisionTarget;
  external String? get expectedRecordVersion;
  external JSAny? get originalFields;
  external String? get original;
}

@JS()
extension type _UnitRow._(JSObject _) implements JSObject {
  external factory _UnitRow({
    required int ordinal,
    required String name,
    required String structure,
  });
  external int get ordinal;
  external String get name;
  external String get structure;
}

@JS()
extension type _ConversionRow._(JSObject _) implements JSObject {
  external factory _ConversionRow({
    required int ordinal,
    required String target,
    required bool hasExpression,
    required String expression,
    required bool valid,
  });
  external int get ordinal;
  external String get target;
  external bool get hasExpression;
  external String get expression;
  external bool get valid;
}

@JS()
extension type _LabelRow._(JSObject _) implements JSObject {
  external factory _LabelRow({
    required int ordinal,
    required String language,
    required String text,
  });
  external int get ordinal;
  external String get language;
  external String get text;
}

SavedCalendarForm _decodeCalendar(
  _CalendarRow row,
  Iterable<_UnitRow> unitRows,
  Iterable<_LabelRow> labelRows,
  Iterable<_ConversionRow> conversionRows, {
  bool legacy = false,
}) {
  return SavedCalendarForm(
    generation: BigInt.parse(row.generation),
    form: UnfinishedCalendarForm(
      baseRevision: RevisionId.parse(row.baseRevision),
      representedContext: RecordId.parse(row.representedContext),
      clientRef: row.clientRef,
      namespace: row.namespace,
      key: row.key,
      hasEpoch: row.hasEpoch,
      epoch: row.epoch,
      rationale: row.rationale,
      draftVersion: row.draftVersion == null
          ? null
          : BigInt.parse(row.draftVersion!),
      revisionTarget: row.revisionTarget == null
          ? null
          : ExpressionReferenceInput.fromWire(
              decodeBrowserInput(row.revisionTarget!),
            ),
      expectedRecordVersion: row.expectedRecordVersion == null
          ? null
          : RecordVersionId.parse(row.expectedRecordVersion!),
      original: legacy
          ? (row.original == null
                ? null
                : CalendarRecord.fromWire(
                    CanonicalValue.parseWireJson(row.original!),
                  ))
          : row.originalFields == null
          ? null
          : CalendarRecord.fromWire(decodeBrowserInput(row.originalFields!)),
      units: unitRows.map(
        (unit) => CalendarUnitInput(name: unit.name, structure: unit.structure),
      ),
      conversions: conversionRows.map(
        (conversion) => CalendarConversionInput(
          target: conversion.target,
          hasExpression: conversion.hasExpression,
          expression: conversion.expression,
          valid: conversion.valid,
        ),
      ),
      labels: labelRows.map(
        (label) =>
            PropertyLabelInput(language: label.language, text: label.text),
      ),
    ),
  );
}

_CalendarRow _encodeCalendar(SavedCalendarForm saved) {
  final form = saved.form;
  return _CalendarRow(
    generation: saved.generation.toString(),
    baseRevision: form.baseRevision.value,
    representedContext: form.representedContext.value,
    clientRef: form.clientRef,
    namespace: form.namespace,
    key: form.key,
    hasEpoch: form.hasEpoch,
    epoch: form.epoch,
    rationale: form.rationale,
    draftVersion: form.draftVersion?.toString(),
    revisionTarget: form.revisionTarget == null
        ? null
        : encodeBrowserInput(form.revisionTarget!.toWire()),
    expectedRecordVersion: form.expectedRecordVersion?.value,
    originalFields: form.original == null
        ? null
        : encodeBrowserInput(form.original!.toWire()),
  );
}

/// Named fields and ordered child rows, never a serialized UI-state blob.
/// IndexedDB transactions compare generations and commit all children together.
/// Browser storage is origin-private and may be cleared by the user/browser;
/// this store contains only unfinished input, never canon or service credentials.
final class BrowserCalendarFormRecoveryStore {
  BrowserCalendarFormRecoveryStore._(this._db);
  final web.IDBDatabase _db;
  static const _tables = [
    'calendar_form',
    'calendar_unit',
    'calendar_label',
    'calendar_conversion',
  ];

  static Future<BrowserCalendarFormRecoveryStore> open({
    String databaseName = 'ub-calendar-editor-recovery',
  }) async {
    try {
      final result = Completer<BrowserCalendarFormRecoveryStore>();
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
                  _encodeCalendar(
                    _decodeCalendar(
                      cursor.value as _CalendarRow,
                      [],
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
        result.complete(BrowserCalendarFormRecoveryStore._(db));
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
      throw const FormatException('Choose the calendar definition context.');
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

  SavedCalendarForm? _read(
    web.IDBRequest main,
    web.IDBRequest aliases,
    web.IDBRequest labels,
    web.IDBRequest conversions,
  ) {
    if (main.result == null || main.result.isUndefined) return null;
    final row = main.result as _CalendarRow;
    final unitRows = (aliases.result as JSArray<_UnitRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    final labelRows = (labels.result as JSArray<_LabelRow>).toDart
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    final conversionRows =
        (conversions.result as JSArray<_ConversionRow>).toDart
          ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return _decodeCalendar(row, unitRows, labelRows, conversionRows);
  }

  Future<SavedCalendarForm?> load(EditorFormScope scope) {
    final result = Completer<SavedCalendarForm?>();
    try {
      final key = _binding(scope), range = _children(_binding(scope));
      final tx = _db.transaction(
        _tables.map((name) => name.toJS).toList().toJS,
        'readonly',
      );
      final main = tx.objectStore(_tables[0]).get(key.toJS);
      final aliases = tx.objectStore(_tables[1]).getAll(range);
      final conversions = tx.objectStore(_tables[3]).getAll(range);
      final labels = tx.objectStore(_tables[2]).getAll(range);
      tx.oncomplete = ((web.Event _) {
        try {
          result.complete(_read(main, aliases, labels, conversions));
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

  Future<SavedCalendarForm> save(
    EditorFormScope scope,
    UnfinishedCalendarForm form,
    BigInt expectedGeneration,
  ) async {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Calendar form context does not match.');
    }
    _binding(scope);
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    final result = Completer<SavedCalendarForm>();
    SavedCalendarForm? saved;
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
          labelStore = tx.objectStore(_tables[2]),
          conversionStore = tx.objectStore(_tables[3]);
      final main = primary.get(key.toJS),
          aliases = aliasStore.getAll(range),
          conversions = conversionStore.getAll(range),
          labels = labelStore.getAll(range);
      // Queue writes synchronously in the final read's success callback, while
      // the transaction is active; awaiting a later task could auto-commit it.
      labels.onsuccess = ((web.Event _) {
        try {
          final current = _read(main, aliases, labels, conversions),
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
          saved = SavedCalendarForm(
            generation: generation + BigInt.one,
            form: form,
          );
          primary.put(_encodeCalendar(saved!), key.toJS);
          aliasStore.delete(range);
          labelStore.delete(range);
          conversionStore.delete(range);
          for (var i = 0; i < form.units.length; i++) {
            final unit = form.units[i];
            aliasStore.put(
              _UnitRow(ordinal: i, name: unit.name, structure: unit.structure),
              [...key, i.toJS].toJS,
            );
          }
          for (var i = 0; i < form.conversions.length; i++) {
            final conversion = form.conversions[i];
            conversionStore.put(
              _ConversionRow(
                ordinal: i,
                target: conversion.target,
                hasExpression: conversion.hasExpression,
                expression: conversion.expression,
                valid: conversion.valid,
              ),
              [...key, i.toJS].toJS,
            );
          }
          for (var i = 0; i < form.labels.length; i++) {
            final label = form.labels[i];
            labelStore.put(
              _LabelRow(ordinal: i, language: label.language, text: label.text),
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
