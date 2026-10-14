import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;

import 'connection.dart';
import 'storage_maintenance.dart';
import 'package_import_page.dart';

class StorageMaintenancePage extends StatefulWidget {
  const StorageMaintenancePage({
    super.key,
    required this.session,
    this.universe,
  });
  final AppSession session;
  final LibraryEntry? universe;
  @override
  State<StorageMaintenancePage> createState() => _StorageMaintenancePageState();
}

class _StorageMaintenancePageState extends State<StorageMaintenancePage> {
  final _name = TextEditingController();
  StorageMaintenance? _storage;
  bool _busy = false;
  String? _message, _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } on NameUnavailableError {
      if (mounted) {
        setState(
          () => _error = 'The backup’s identity or name is already reserved in this instance.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'File selection failed.');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Could not confirm the operation. Check the library before retrying. ${error is FormatException ? error.message : ''}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _maintain(bool collect) async {
    final storage = await maintainStorage(
      widget.session,
      widget.universe!,
      collect: collect,
    );
    if (mounted) {
      setState(() {
        _storage = storage;
        _message = collect
            ? 'Storage maintenance completed; ${storage.collectedCaches} snapshot caches collected.'
            : 'Storage check completed.';
      });
    }
  }

  Future<void> _backup() async {
    final path = await widget.session.backupFile!(widget.universe!);
    if (mounted) {
      setState(
        () => _message = path == null
            ? 'Backup file selection cancelled.'
            : 'Backup saved: $path',
      );
    }
  }

  Future<void> _downloadArchive() async {
    await widget.session.downloadArchive!(widget.universe!);
    if (mounted) {
      setState(
        () => _message = 'Archive download started. Check your browser’s downloads for completion.',
      );
    }
  }

  Future<void> _saveArchive() async {
    final path = await widget.session.saveArchiveFile!(widget.universe!);
    if (mounted) {
      setState(() => _message = path == null
          ? 'Archive file selection cancelled.'
          : 'Archive saved: $path');
    }
  }

  Future<void> _restore() async {
    final restored = await widget.session.restoreBackupFile!(_name.text);
    if (mounted) {
      setState(
        () => _message = restored == null
            ? 'Backup selection cancelled.'
            : 'Restored ${restored.name}. Return to the library to open it.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.universe == null
              ? 'Restore a backup'
              : 'Backup and storage · ${widget.universe!.name}',
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (widget.universe != null) ...[
                const Text(
                  'Keep a complete backup of this universe, including retained history and embedded source content.',
                ),
                if (widget.session.downloadArchive == null)
                  FilledButton(
                    onPressed: _busy || widget.session.backupFile == null
                        ? null
                        : () => _run(_backup),
                    child: const Text('Save complete backup file'),
                  ),
                if (widget.session.downloadArchive != null) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(_downloadArchive),
                    icon: const Icon(Icons.download),
                    label: const Text('Download complete archive'),
                  ),
                  const Text(
                    'The archive includes retained history, source content and workflow evidence. Your browser manages the download.',
                  ),
                ],
                if (widget.session.saveArchiveFile != null) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(_saveArchive),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Save complete archive file'),
                  ),
                  const Text(
                    'Transfer this universe to another installation with retained history, source content and workflow evidence.',
                  ),
                ],
                if (widget.session.backupFile == null &&
                    widget.session.downloadArchive == null)
                  const Text(
                    'Native backup file selection is available on macOS, iOS and Android. Other file flows remain in the operator interface.',
                  ),
                const Divider(),
              ],
              if (widget.session.pickArchiveFile != null)
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) =>
                                PackageImportPage(session: widget.session),
                          ),
                        ),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import a package'),
                ),
              if (widget.session.restoreBackupFile != null ||
                  widget.session.pickArchiveFile == null) ...[
                const Text('Restore a backup'),
                const Text(
                  'Restoration registers the backup’s original universe identity. Use it in an instance where that identity is absent.',
                ),
                TextField(
                  controller: _name,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Restored universe name',
                  ),
                ),
                FilledButton(
                  onPressed: _busy || widget.session.restoreBackupFile == null
                      ? null
                      : () => _run(_restore),
                  child: const Text('Choose backup and restore'),
                ),
              ],
              if (widget.universe != null) ...[
                const Divider(),
                const Text('Storage maintenance'),
                const Text(
                  'History, receipts and source assets are retained. Collection removes disposable snapshot caches and compacts storage.',
                ),
                TextButton(
                  onPressed: _busy ? null : () => _run(() => _maintain(false)),
                  child: const Text('Check storage'),
                ),
                if (_storage case final storage?) ...[
                  Text(
                    'Retained record versions: ${storage.versions}\nRevisions: ${storage.revisions}\nPublication receipts: ${storage.receipts}\nWorkflow entries: ${storage.workflows}\nSource assets: ${storage.sources}\nDisposable snapshot caches: ${storage.eligibleCaches}',
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _run(() => _maintain(true)),
                    child: const Text('Collect snapshot caches and compact'),
                  ),
                ],
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Semantics(liveRegion: true, child: Text(_message!)),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
            ],
          ),
        ),
      ),
    ),
  );
}
