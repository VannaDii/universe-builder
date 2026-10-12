import 'dart:io';

import 'package:ub_domain/ub_domain.dart';

import 'database.dart';
import 'operator_source.dart';
import 'owned_database.dart';
import 'ownership.dart';
import 'serialized_package.dart';

/// Offline owning-installation conversion, distinct from logical import.
/// Retains active workflow authority exactly and never registers the target.
CanonicalObject convertPackage(String source, String destination) =>
    convertPackageWithHook(source, destination, (_) {});

enum PackageConversionPoint { constructed, verified, beforePublish }

/// Internal interruption seam for the maintained conversion regression cases.
CanonicalObject convertPackageWithHook(
  String source,
  String destination,
  void Function(PackageConversionPoint) hook,
) {
  if (FileSystemEntity.typeSync(destination, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw const FormatException(
      'Conversion destination exists; choose a fresh path',
    );
  }
  final parent = privateDirectory(File(destination).absolute.parent.path);
  final original = openOriginalDatabase(source);
  Directory? temporary;
  OwnedSqliteDatabase? target;
  try {
    temporary = Directory(parent).createTempSync('.operator-conversion-');
    privateDirectory(temporary.path);
    final path = '${temporary.path}/package.sqlite';
    target = OwnedSqliteDatabase.create(path);
    final relational = original.database
        .select('PRAGMA table_info(record_versions)')
        .any((row) => row['name'] == 'payload_row');
    final report = relational
        ? constructRelationalPackage(original.database, target.database)
        : constructSerializedPackage(original.database, target.database);
    hook(PackageConversionPoint.constructed);
    if (target.database.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw const FormatException('Converted foreign key check failed');
    }
    hook(PackageConversionPoint.verified);
    target.database.execute(
      'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE',
    );
    target.close();
    target = null;
    if (File(path).lengthSync() > maxPackageBytes) {
      throw const FormatException('Converted package exceeds 8 GiB');
    }
    if (originalFileHash(source) != original.hash) {
      throw const FormatException('Source changed during conversion');
    }
    hook(PackageConversionPoint.beforePublish);
    verifyOriginalDatabase(source, original.hash);
    publishConversionFile(path, destination);
    return CanonicalObject([
      MapEntry('source_sha256', CanonicalString(original.hash)),
      MapEntry('records', CanonicalNumber(report.records.toString())),
      MapEntry('workflows', CanonicalNumber(report.workflows.toString())),
      MapEntry(
        'compared_tables',
        CanonicalNumber(report.comparedTables.toString()),
      ),
      const MapEntry('original_preserved', CanonicalBool(true)),
    ]);
  } finally {
    try {
      target?.close();
    } finally {
      original.database.close();
      temporary?.deleteSync(recursive: true);
    }
  }
}
