@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/package_import_forms.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
PackageImportDraft input({bool empty = false}) {
  final op = OperationId.generate(), name = '\ufeffMemoir\r\n\u0000😀';
  return PackageImportDraft(
    operation: op,
    name: name,
    fileName: '\ufeffArchive\r\n\u0000.sqlite',
    mode: ImportMode.restore,
    phase: PackageImportPhase.admitted,
    review: CanonicalObject([
      MapEntry('preview_id', CanonicalString(op.value)),
      MapEntry('digest', CanonicalString('a' * 64)),
      MapEntry('source_universe', CanonicalString(UniverseId.generate().value)),
      MapEntry('target_universe', CanonicalString(UniverseId.generate().value)),
      MapEntry('name', CanonicalString(name)),
      const MapEntry('complete', CanonicalBool(false)),
      MapEntry('omitted_records', CanonicalNumber(maxU64.toString())),
      MapEntry('record_count', CanonicalNumber('9007199254740993')),
      MapEntry('record_ids', CanonicalString('\ufeffRecords')),
      MapEntry('version_ids', CanonicalString('')),
      MapEntry('references', CanonicalString('\ufeffReferences')),
      const MapEntry('includes_history', CanonicalBool(true)),
      const MapEntry('includes_workflow', CanonicalBool(false)),
      MapEntry('workflow_and_approvals', CanonicalString('\ufeffHistory')),
      const MapEntry('canonical', CanonicalBool(false)),
      MapEntry(
        'conflicts',
        CanonicalArray(
          empty
              ? []
              : [
                  CanonicalString(''),
                  CanonicalString('\ufeffConflict\r\n\u0000😀'),
                  CanonicalString(''),
                ],
        ),
      ),
    ]),
    receipt: CanonicalObject([
      MapEntry('preview_id', CanonicalString(op.value)),
      MapEntry('digest', CanonicalString('a' * 64)),
      MapEntry('universe_id', CanonicalString(UniverseId.generate().value)),
      MapEntry('name', CanonicalString(name)),
      const MapEntry('complete', CanonicalBool(false)),
      MapEntry('omitted_records', CanonicalNumber(maxU64.toString())),
      const MapEntry('imported', CanonicalBool(true)),
    ]),
  );
}

void main() {
  test('fixed import rows retain complete reviews, exact counts and results, then replace them without stale conflicts', () {
    final root = Directory('/tmp').createTempSync('ub-import-typed-'),
        scope = (OperationId.generate(), ProfileId.generate());
    final path = '${root.path}/forms.sqlite', f = input();
    var store = PackageImportFormRecoveryStore.open(path);
    try {
      store.save(scope, f, BigInt.zero);
      store.close();
      store = PackageImportFormRecoveryStore.open(path);
      expect(store.load(scope)!.form.toWire().toText(), f.toWire().toText());
      expect(store.load(scope)!.form.admission().digest, 'a' * 64);
      expect(store.save(scope, f, BigInt.zero).generation, BigInt.one);
      final empty = input(empty: true);
      store.save(scope, empty, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        empty.toWire().toText(),
      );
      final fresh = PackageImportDraft(operation: OperationId.generate());
      store.save(scope, fresh, BigInt.two);
      store.close();
      store = PackageImportFormRecoveryStore.open(path);
      expect(
        store.load(scope)!.form.toWire().toText(),
        fresh.toWire().toText(),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        for (final table in ['review', 'receipt', 'conflict']) {
          expect(
            db
                .select('SELECT count(*) n FROM package_import_$table')
                .single['n'],
            0,
          );
        }
        expect(
          db
              .select('PRAGMA table_info(package_import_form)')
              .map((r) => r['name']),
          isNot(contains('review')),
        );
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
