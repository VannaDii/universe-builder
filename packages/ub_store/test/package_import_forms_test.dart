import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/package_import_forms.dart';

void main() {
  test('import choices recover by instance and profile, reject conflicts, retain exact admission', () {
    final root = Directory.systemTemp.createTempSync('ub-import-recovery-');
    final path = '${root.path}/forms.sqlite';
    var store = PackageImportFormRecoveryStore.open(path);
    final scope = (OperationId.generate(), ProfileId.generate());
    final initial = PackageImportDraft(
      operation: OperationId.generate(),
      name: '\uFEFFMemoir café 😀\r\n',
    );
    try {
      expect(store.load(scope), isNull);
      final saved = store.save(scope, initial, BigInt.zero);
      expect(store.load(scope)!.form.toWire().toText(), initial.toWire().toText());
      expect(
        store.save(scope, initial, BigInt.zero).generation,
        saved.generation,
      );
      store.close();
      store = PackageImportFormRecoveryStore.open(path);
      expect(store.load(scope)!.form.toWire().toText(), initial.toWire().toText());
      expect(store.load((scope.$1, ProfileId.generate())), isNull);
      expect(store.load((OperationId.generate(), scope.$2)), isNull);
      expect(
        () =>
            store.save(scope, initial.copyWith(name: 'different'), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
      final reviewed = initial.copyWith(
        phase: PackageImportPhase.admitting,
        review: CanonicalObject([
          MapEntry('preview_id', CanonicalString(initial.operation.value)),
          MapEntry('name', CanonicalString(initial.name)),
          MapEntry('digest', CanonicalString('exact-reviewed-digest')),
        ]),
      );
      store.save(scope, reviewed, saved.generation);
      store.close();
      store = PackageImportFormRecoveryStore.open(path);
      final recovered = store.load(scope)!;
      expect(recovered.form.phase, PackageImportPhase.admitting);
      expect(recovered.form.admission().digest, 'exact-reviewed-digest');
      expect(recovered.form.admission().previewId, initial.operation);
      expect(
        () => store.save(
          scope,
          initial.copyWith(name: '\uD800'),
          recovered.generation,
        ),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
