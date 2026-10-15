@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_app/browser_package_import_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  migrationTests();
  test('package recovery pins target instance, profile, choices and exact review through admission phases', () async {
    final name = 'ub-import-test-${OperationId.generate().value}';
    var store = await BrowserPackageImportFormRecoveryStore.open(
      databaseName: name,
    );
    final scope = (OperationId.generate(), ProfileId.generate());
    final operation = OperationId.generate();
    final report = CanonicalObject([
      MapEntry('preview_id', CanonicalString(operation.value)),
      MapEntry('digest', CanonicalString('a' * 64)),
      MapEntry('name', CanonicalString('Novel 記憶 😀')),
      MapEntry('record_count', CanonicalNumber('18446744073709551615')),
    ]);
    final form = PackageImportDraft(
      operation: operation,
      name: 'Novel 記憶 😀',
      fileName: 'source.sqlite',
      phase: PackageImportPhase.review,
      review: report,
    );
    try {
      await store.save(scope, form, BigInt.zero);
      store.close();
      store = await BrowserPackageImportFormRecoveryStore.open(
        databaseName: name,
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        form.toWire().toText(),
      );
      expect(
        (await store.save(scope, form, BigInt.zero)).generation,
        BigInt.one,
      );
      expect(form.admission().previewId, operation);
      expect(form.admission().digest, 'a' * 64);
      final admitting = form.copyWith(phase: PackageImportPhase.admitting);
      await expectLater(
        store.save(scope, admitting, BigInt.zero),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      await store.save(scope, admitting, BigInt.one);
      expect(
        (await store.load(scope))!.form.phase,
        PackageImportPhase.admitting,
      );
      expect(await store.load((OperationId.generate(), scope.$2)), isNull);
      expect(await store.load((scope.$1, ProfileId.generate())), isNull);
      final admitted = admitting.copyWith(
        phase: PackageImportPhase.admitted,
        receipt: CanonicalObject([MapEntry('imported', CanonicalBool(true))]),
      );
      await store.save(scope, admitted, BigInt.two);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        admitted.toWire().toText(),
      );
      final fresh = PackageImportDraft(operation: OperationId.generate());
      await store.save(scope, fresh, BigInt.from(3));
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        fresh.toWire().toText(),
      );
    } finally {
      store.close();
      final done = Completer<void>();
      final request = web.window.indexedDB.deleteDatabase(name);
      request.onsuccess = ((web.Event _) => done.complete()).toJS;
      request.onerror = ((web.Event _) => done.completeError(
        StateError('Cleanup failed'),
      )).toJS;
      await done.future;
    }
  });
}

@JS()
extension type _LegacyRow._(JSObject _) implements JSObject {
  external factory _LegacyRow({
    required String generation,
    required String operation,
    required String name,
    required String mode,
    required String phase,
    required String fileName,
    String? review,
    String? receipt,
  });
}

@JS()
extension type _StoredRow._(JSObject _) implements JSObject {
  external String? get review;
  external String? get receipt;
  external _StoredReview? get reviewFields;
  external JSObject? get receiptFields;
}

@JS()
extension type _StoredReview._(JSObject _) implements JSObject {
  external String? get recordCount;
  external String? get omittedRecords;
  external JSArray<JSString>? get conflicts;
}

Future<web.IDBDatabase> _openDatabase(String name, [int? version]) async {
  final result = Completer<web.IDBDatabase>();
  final request = version == null
      ? web.window.indexedDB.open(name)
      : web.window.indexedDB.open(name, version);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore(
      'package_import_form',
    );
  }).toJS;
  request.onsuccess = ((web.Event _) => result.complete(
    request.result as web.IDBDatabase,
  )).toJS;
  request.onerror = ((web.Event _) => result.completeError(
    StateError('Cannot open test database'),
  )).toJS;
  return result.future;
}

Future<void> _seedLegacy(
  String name,
  (OperationId, ProfileId) scope,
  PackageImportDraft form, {
  bool malformed = false,
}) async {
  final db = await _openDatabase(name, 1);
  try {
    final tx = db.transaction('package_import_form'.toJS, 'readwrite');
    final done = Completer<void>();
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onabort = ((web.Event _) => done.completeError(
      StateError('Fixture failed'),
    )).toJS;
    tx
        .objectStore('package_import_form')
        .put(
          _LegacyRow(
            generation: '9007199254740993',
            operation: form.operation.value,
            name: form.name,
            mode: form.mode.name,
            phase: form.phase.name,
            fileName: form.fileName,
            review: form.review?.toText(),
            receipt: malformed ? '{unfinished' : form.receipt?.toText(),
          ),
          [scope.$1.value.toJS, scope.$2.value.toJS].toJS,
        );
    await done.future;
  } finally {
    db.close();
  }
}

Future<void> _delete(String name) async {
  final done = Completer<void>();
  final request = web.window.indexedDB.deleteDatabase(name);
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('Cleanup failed'),
  )).toJS;
  await done.future;
}

Future<_StoredRow> _stored(
  web.IDBDatabase db,
  (OperationId, ProfileId) scope,
) async {
  final done = Completer<_StoredRow>();
  final tx = db.transaction('package_import_form'.toJS, 'readonly');
  final request = tx
      .objectStore('package_import_form')
      .get([scope.$1.value.toJS, scope.$2.value.toJS].toJS);
  tx.oncomplete = ((web.Event _) => done.complete(
    request.result as _StoredRow,
  )).toJS;
  tx.onabort = ((web.Event _) => done.completeError(
    StateError('Read failed'),
  )).toJS;
  return done.future;
}

void migrationTests() {
  for (final malformed in [false, true]) {
    test(
      'browser import upgrade ${malformed ? 'rolls back malformed results' : 'preserves exact review and result fields'}',
      () async {
        final name = 'ub-import-upgrade-${OperationId.generate().value}',
            scope = (OperationId.generate(), ProfileId.generate());
        final operation = OperationId.generate();
        final form = PackageImportDraft(
          operation: operation,
          name: '\ufeffMemoir\r\n\u0000😀',
          fileName: '\ufeffarchive.sqlite',
          phase: PackageImportPhase.admitting,
          review: CanonicalObject([
            MapEntry('preview_id', CanonicalString(operation.value)),
            MapEntry('name', CanonicalString('\ufeffMemoir\r\n\u0000😀')),
            MapEntry('digest', CanonicalString('a' * 64)),
            MapEntry(
              'source_universe',
              CanonicalString(UniverseId.generate().value),
            ),
            MapEntry(
              'target_universe',
              CanonicalString(UniverseId.generate().value),
            ),
            const MapEntry('complete', CanonicalBool(false)),
            const MapEntry(
              'omitted_records',
              CanonicalNumber('18446744073709551615'),
            ),
            const MapEntry('record_count', CanonicalNumber('9007199254740993')),
            MapEntry('record_ids', CanonicalString('\ufeffIDs')),
            MapEntry('version_ids', CanonicalString('')),
            MapEntry('references', CanonicalString('\ufeffReferences')),
            const MapEntry('includes_history', CanonicalBool(true)),
            const MapEntry('includes_workflow', CanonicalBool(false)),
            const MapEntry('canonical', CanonicalBool(false)),
            MapEntry(
              'workflow_and_approvals',
              CanonicalString('\ufeffHistory'),
            ),
            MapEntry(
              'conflicts',
              CanonicalArray([
                CanonicalString(''),
                CanonicalString('\ufeffConflict\r\n\u0000😀'),
                CanonicalString(''),
              ]),
            ),
          ]),
          receipt: CanonicalObject([
            MapEntry('preview_id', CanonicalString(operation.value)),
            MapEntry('digest', CanonicalString('a' * 64)),
            MapEntry(
              'universe_id',
              CanonicalString(UniverseId.generate().value),
            ),
            MapEntry('name', CanonicalString('\ufeffMemoir\r\n\u0000😀')),
            const MapEntry('complete', CanonicalBool(false)),
            const MapEntry(
              'omitted_records',
              CanonicalNumber('18446744073709551615'),
            ),
            const MapEntry('imported', CanonicalBool(true)),
          ]),
        );
        await _seedLegacy(name, scope, form, malformed: malformed);
        try {
          if (malformed) {
            await expectLater(
              BrowserPackageImportFormRecoveryStore.open(databaseName: name),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await _openDatabase(name);
            try {
              expect(db.version, 1);
              final row = await _stored(db, scope);
              expect(row.review, form.review!.toText());
              expect(row.receipt, '{unfinished');
              expect(row.reviewFields, isNull);
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserPackageImportFormRecoveryStore.open(
              databaseName: name,
            );
            try {
              final saved = (await store.load(scope))!;
              expect(saved.generation, BigInt.parse('9007199254740993'));
              expect(saved.form.toWire().toText(), form.toWire().toText());
              final raw = await _openDatabase(name);
              try {
                expect(raw.version, 2);
                final row = await _stored(raw, scope);
                expect(row.review, isNull);
                expect(row.receipt, isNull);
                expect(row.reviewFields!.recordCount, '9007199254740993');
                expect(
                  row.reviewFields!.omittedRecords,
                  '18446744073709551615',
                );
                expect(
                  row.reviewFields!.conflicts!.toDart.map((v) => v.toDart),
                  ['', '\ufeffConflict\r\n\u0000😀', ''],
                );
                expect(row.receiptFields, isNotNull);
              } finally {
                raw.close();
              }
              final empty = PackageImportDraft(
                operation: OperationId.generate(),
                review: CanonicalObject([]),
                receipt: CanonicalObject([]),
              );
              await store.save(scope, empty, saved.generation);
              store.close();
              store = await BrowserPackageImportFormRecoveryStore.open(
                databaseName: name,
              );
              expect(
                (await store.load(scope))!.form.toWire().toText(),
                empty.toWire().toText(),
              );
            } finally {
              store.close();
            }
          }
        } finally {
          await _delete(name);
        }
      },
    );
  }
}
