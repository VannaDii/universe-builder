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
    Future<AppSession> instance(String name) async {
      final root = '${temporary.path}/$name';
      final catalog = SqliteInstallationStore.create(root);
      final profile = InstallationAuthority(catalog).initializeAuthor();
      catalog.close();
      servers.add(
        await LocalSqliteEngineServer.start(root, compatibilitySocket: false),
      );
      final session = await DeviceConnection([
        '--installation',
        root,
        '--profile',
        profile.value,
        '--engine=/nonexistent',
      ]).connect();
      sessions.add(session);
      return session;
    }

    try {
      final source = await instance('source'),
          target = await instance('target');
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
      final maintenance = await maintainStorage(
        source,
        universe,
        collect: true,
      );
      expect(maintenance.revisions, greaterThan(BigInt.zero));
      expect(maintenance.sources, BigInt.zero);
      final targetFiles = LocalBackupFiles(
        root: '${temporary.path}/target',
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
        root: '${temporary.path}/target',
        call: target.call,
        saveFile: (_) async => null,
        openFile: (_) async => false,
      );
      expect(await cancelled.restore('Cancelled'), isNull);
      expect(await cancelled.backup(restored), isNull);
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
