import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/local_backup_files.dart';
import 'package:ub_app/storage_maintenance.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('app copies a complete backup and restores original identity and context into another instance', () async {
    final temporary = Directory('/tmp').createTempSync('ub-app-backup-');
    final sessions = <AppSession>[], servers = <LocalSqliteEngineServer>[];
    var targetRoot = '${temporary.path}/target';
    Future<AppSession> instance(String name) async {
      final root = '${temporary.path}/$name';
      final catalog = File('$root/installation.sqlite').existsSync()
          ? SqliteInstallationStore.openExisting(root)
          : SqliteInstallationStore.create(root);
      final profile = catalog.hasProfiles
          ? catalog.currentAuthor()
          : InstallationAuthority(catalog).initializeAuthor();
      catalog.close();
      servers.add(
        await LocalSqliteEngineServer.start(root, compatibilitySocket: false),
      );
      final session = await DeviceConnection(
        [
          '--installation',
          root,
          '--profile',
          profile.value,
          '--engine=/nonexistent',
        ],
        saveBackupFile: (_) async => null,
        openBackupFile: (_) async => false,
      ).connect();
      sessions.add(session);
      return session;
    }

    try {
      final source = await instance('source');
      var target = await instance('target');
      final created = WireFields(
        await source.call(
          const CreateUniverseEngineRequest(
            name: 'Campaign',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final universe = LibraryEntry(
        UniverseId.parse(created.string('universe_id')),
        'Campaign',
      );
      final destination = '${temporary.path}/retained.sqlite';
      final sourceFiles = LocalBackupFiles(
        root: '${temporary.path}/source',
        call: source.call,
        saveFile: (file) async {
          await File(file).copy(destination);
          return destination;
        },
        openFile: (_) async => false,
      );
      expect(await sourceFiles.backup(universe), destination);
      expect(File(destination).lengthSync(), greaterThan(0));
      final archivePath = '${temporary.path}/archive.sqlite';
      final archiveFiles = LocalBackupFiles(
        root: '${temporary.path}/source',
        call: source.call,
        saveFile: (file) async {
          expect(File(file).uri.pathSegments.last, 'Universe Builder archive.sqlite');
          await File(file).copy(archivePath);
          return archivePath;
        },
        openFile: (_) async => false,
      );
      expect(await archiveFiles.archive(universe), archivePath);
      expect(Directory('${temporary.path}/source/client-files').listSync(), isEmpty);
      final nativeImport = LocalBackupFiles(
        root: targetRoot,
        call: target.call,
        saveFile: (_) async => null,
        openFile: (path) async {
          await File(archivePath).copy(path);
          return true;
        },
      );
      final selected = (await nativeImport.pickArchive())!;
      final choices = PackageImportDraft(
        operation: OperationId.generate(), name: 'Transferred campaign',
      );
      final preview = Map.fromEntries((await nativeImport.reviewArchive(
        selected, choices,
      ) as CanonicalObject).fields);
      expect(wireString(preview['preview_id']!), choices.operation.value);
      final reviewed = choices.copyWith(
        phase: PackageImportPhase.review,
        review: CanonicalObject(preview.entries),
      );
      await target.savePackageImport!(reviewed, BigInt.zero);
      await selected.release!();
      expect(File(selected.source as String).existsSync(), isFalse);
      // Mobile app updates can move the entire private installation container.
      await target.close();
      await servers[1].close();
      Directory(targetRoot).renameSync('${temporary.path}/moved-target');
      targetRoot = '${temporary.path}/moved-target';
      target = await instance('moved-target');
      expect(
        (await target.loadPackageImport!())!.form.toWire().toText(),
        reviewed.toWire().toText(),
      );
      expect((preview['includes_workflow'] as CanonicalBool).value, isTrue);
      final admitted = Map.fromEntries((await target.call(
        AcceptImportEngineRequest(
          previewId: OperationId.parse(wireString(preview['preview_id']!)),
          digest: wireString(preview['digest']!),
        ),
      ) as CanonicalObject).fields);
      expect((admitted['imported'] as CanonicalBool).value, isTrue);
      final completed = reviewed.copyWith(
        phase: PackageImportPhase.admitted,
        receipt: CanonicalObject(admitted.entries),
      );
      await target.savePackageImport!(completed, BigInt.one);
      expect(
        (await target.loadPackageImport!())!.form.toWire().toText(),
        completed.toWire().toText(),
      );
      expect(wireString(admitted['universe_id']!), isNot(universe.id.value));
      final maintenance = await maintainStorage(
        source,
        universe,
        collect: true,
      );
      expect(maintenance.revisions, greaterThan(BigInt.zero));
      expect(maintenance.sources, BigInt.zero);
      final targetFiles = LocalBackupFiles(
        root: targetRoot,
        call: target.call,
        saveFile: (_) async => null,
        openFile: (file) async {
          await File(destination).copy(file);
          return true;
        },
      );
      final restored = (await targetFiles.restore('Recovered campaign'))!;
      expect(restored.id, universe.id);
      final description = Envelope<Description>.fromWire(
        await target.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(universe: Selector(restored.name)),
          ),
        ),
        Description.fromWire,
      ).result;
      expect(
        description.continuities.single.revisionId.value,
        created.string('revision'),
      );
      expect(
        description.continuities.single.representedContexts.single.id.value,
        created.string('context_id'),
      );
      await expectLater(
        targetFiles.restore('Conflicting identity'),
        throwsA(isA<NameUnavailableError>()),
      );
      await expectLater(
        targetFiles.restore('Another restore choice'),
        throwsA(isA<NameUnavailableError>()),
      );
      expect(File(destination).lengthSync(), greaterThan(0));
      final cancelled = LocalBackupFiles(
        root: targetRoot,
        call: target.call,
        saveFile: (_) async => null,
        openFile: (_) async => false,
      );
      expect(await cancelled.restore('Cancelled'), isNull);
      expect(await cancelled.pickArchive(), isNull);
      expect(await cancelled.backup(restored), isNull);
      expect(await cancelled.archive(restored), isNull);
      final failedExport = LocalBackupFiles(
        root: '${temporary.path}/source',
        call: (_) async => throw const FormatException('Export unavailable'),
        saveFile: (_) async => fail('Do not open a picker for a failed export'),
        openFile: (_) async => false,
      );
      await expectLater(failedExport.archive(universe), throwsFormatException);
      expect(Directory('${temporary.path}/source/client-files').listSync(), isEmpty);
      final failedPicker = LocalBackupFiles(
        root: targetRoot,
        call: target.call,
        saveFile: (_) async => null,
        openFile: (destination) async {
          File(destination).writeAsStringSync('partial provider copy');
          throw const FileSystemException('Provider read failed');
        },
      );
      await expectLater(
        failedPicker.restore('Unreadable'),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(failedPicker.pickArchive(), throwsA(isA<FileSystemException>()));
      expect(
        Directory('$targetRoot/client-files').listSync(),
        isEmpty,
      );
    } finally {
      for (final session in sessions) {
        await session.close();
      }
      for (final server in servers) {
        await server.close();
      }
      temporary.deleteSync(recursive: true);
    }
  });
}
