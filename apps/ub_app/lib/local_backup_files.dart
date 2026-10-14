import 'dart:io';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';

import 'connection.dart';
import 'package_import.dart';

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
    final path = '${directory.path}/Universe Builder backup.sqlite';
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

  Future<String?> archive(LibraryEntry universe) async {
    final directory = _directory();
    final path = '${directory.path}/Universe Builder archive.sqlite';
    try {
      final manifest = WireFields(
        await call(
          ExportLogicalEngineRequest(
            universe: Selector(universe.name),
            destination: path,
            recordIds: const [],
            completeHistory: true,
          ),
        ),
        {
          'format',
          'universe',
          'name',
          'complete',
          'omitted_records',
          'includes_history',
          'includes_workflow',
        },
      );
      if (manifest.string('format') != 'universe-relational' ||
          manifest.string('universe') != universe.id.value ||
          !manifest.boolean('complete') ||
          manifest.u64('omitted_records') != BigInt.zero ||
          !manifest.boolean('includes_history') ||
          !manifest.boolean('includes_workflow')) {
        throw const FormatException('Complete archive was not confirmed.');
      }
      return await saveFile(path);
    } finally {
      directory.deleteSync(recursive: true);
    }
  }

  Future<SelectedArchiveFile?> pickArchive() async {
    final directory = _directory();
    final source = '${directory.path}/package.sqlite';
    try {
      if (!await openFile(source)) {
        directory.deleteSync(recursive: true);
        return null;
      }
      return SelectedArchiveFile(
        source: source,
        name: 'Selected archive.sqlite',
        release: () async {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        },
      );
    } on Object {
      directory.deleteSync(recursive: true);
      rethrow;
    }
  }

  Future<CanonicalValue> reviewArchive(
    SelectedArchiveFile file,
    PackageImportDraft form,
  ) => call(
    PreviewImportEngineRequest(
      source: file.source as String,
      name: form.name,
      mode: form.mode,
      previewId: form.operation,
    ),
  );

  Future<LibraryEntry?> restore(String name) async {
    if (name.trim().isEmpty) {
      throw const FormatException('Enter the restored universe name.');
    }
    final directory = _directory();
    final source = '${directory.path}/package.sqlite';
    final bool picked;
    try {
      picked = await openFile(source);
    } on Object {
      directory.deleteSync(recursive: true);
      rethrow;
    }
    if (!picked) {
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
