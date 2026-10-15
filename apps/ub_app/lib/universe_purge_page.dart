import 'package:flutter/material.dart';

import 'connection.dart';
import 'universe_purge.dart';

/// Installation-author maintenance, separate from ordinary authoring and edits.
class UniversePurgePage extends StatefulWidget {
  const UniversePurgePage({
    super.key,
    required this.session,
    required this.universe,
  });
  final AppSession session;
  final LibraryEntry universe;
  @override
  State<UniversePurgePage> createState() => _UniversePurgePageState();
}

class _UniversePurgePageState extends State<UniversePurgePage> {
  final _confirmation = TextEditingController();
  UniversePurgePreview? _preview;
  bool _busy = false;
  String? _error;
  String get _phrase => 'PURGE ${widget.universe.name}';

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _preview = null;
      _error = null;
      _confirmation.clear();
    });
    try {
      final preview = await previewUniversePurge(
        widget.session,
        widget.universe,
      );
      if (mounted) setState(() => _preview = preview);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not preview this universe. Return to Library to refresh its name and access, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _purge() async {
    if (_busy || _preview == null || _confirmation.text != _phrase) return;
    final preview = _preview!;
    final confirmation = _confirmation.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await purgeUniverse(
        widget.session,
        widget.universe,
        preview,
        confirmation,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() {
          _preview = null;
          _confirmation.clear();
          _error = 'Purge was not confirmed. Return to Library to check the outcome. If the universe is still present, review a fresh preview before retrying.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Purge universe')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.universe.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Permanently remove this entire universe from this instance, including every continuity, history, source, image, draft and approval. This cannot be undone here. Save a complete backup first if you need to retain it.',
              ),
              if (!widget.session.author)
                const Text('Only the installation author can purge a universe.')
              else ...[
                OutlinedButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Preview purge impact'),
                ),
                if (_preview case final preview?) ...[
                  Text(
                    'Continuities: ${preview.continuities}\nRevisions: ${preview.revisions}\nRecord versions: ${preview.versions}\nWorkflow entries: ${preview.workflows}\nPublication receipts: ${preview.receipts}',
                  ),
                  const SizedBox(height: 16),
                  const Text('What is removed'),
                  Text(preview.scope),
                  const SizedBox(height: 16),
                  const Text('What remains'),
                  Text(preview.retained),
                  const Text(
                    'Private unfinished input stored on client devices and external copies may remain.',
                  ),
                  const SizedBox(height: 16),
                  const Text('Erasure limits'),
                  Text(preview.erasure),
                  const SizedBox(height: 16),
                  Text('Type $_phrase to confirm this preview.'),
                  TextField(
                    controller: _confirmation,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Exact purge confirmation',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    onPressed: _busy || _confirmation.text != _phrase
                        ? null
                        : _purge,
                    child: const Text('Permanently purge this universe'),
                  ),
                ],
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
            ],
          ),
        ),
      ),
    ),
  );
}
