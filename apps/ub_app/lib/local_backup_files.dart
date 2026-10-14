import 'dart:io';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';

import 'connection.dart';

/// File dialogs and copying run in the app; the local service sees only private staging paths.
final class LocalBackupFiles {
  LocalBackupFiles({
    required this.root,
    required this.call,
    required this.saveFile,
    required this.openFile,
  });
  final String root;
  final Future<CanonicalValue> Function(EngineRequest) call;
  final Future<String?> Function(String source) saveFile;
  final Future<bool> Function(String destination) openFile;
  Directory _directory() {
    final parent = privateDirectory('$root/client-files');
    final directory = Directory(parent).createTempSync('backup-');
    privateDirectory(directory.path);
    return directory;
  }

  Future<String?> backup(LibraryEntry universe) async {
    final directory = _directory();
    final path = '${directory.path}/package.sqlite';
    final f = WireFields(
      await call(
        BackupEngineRequest(
          universe: Selector(universe.name),
          destination: path,
        ),
      ),
      {'backup', 'universe_id', 'verified'},
    );
    if (f.string('backup') != path ||
        f.string('universe_id') != universe.id.value ||
        !f.boolean('verified')) {
      throw const FormatException('Backup was not confirmed.');
    }
    // The service has completed its snapshot before the dialog opens.
    try {
      return await saveFile(path);
    } finally {
      directory.deleteSync(recursive: true);
    }
  }

  Future<LibraryEntry?> restore(String name) async {
    if (name.trim().isEmpty) {
      throw const FormatException('Enter the restored universe name.');
    }
    final directory = _directory();
    final source = '${directory.path}/package.sqlite';
    if (!await openFile(source)) {
      directory.deleteSync(recursive: true);
      return null;
    }
    final CanonicalValue response;
    try {
      response = await call(RestoreEngineRequest(source: source, name: name));
    } on ProtocolError catch (error) {
      if (error is NameUnavailableError || error is InvalidArgumentError) {
        File(source).parent.deleteSync(recursive: true);
      }
      rethrow;
    }
    final f = WireFields(response, {'universe_id', 'name', 'restored'});
    if (!f.boolean('restored') || f.string('name') != name) {
      throw const FormatException('Restore was not confirmed.');
    }
    final result = LibraryEntry(
      UniverseId.parse(f.string('universe_id')),
      f.string('name'),
    );
    File(source).parent.deleteSync(recursive: true);
    return result;
  }
}
