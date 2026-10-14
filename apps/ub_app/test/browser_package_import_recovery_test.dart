@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_app/browser_package_import_recovery.dart';
import 'package:ub_app/package_import.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
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
