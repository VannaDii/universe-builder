import 'package:ub_contracts/ub_contracts.dart' show SearchHit;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'backup_file_dialogs.dart';
import 'fixture_workspace.dart';

class FixtureApp extends StatefulWidget {
  const FixtureApp({
    super.key,
    required this.connect,
    required this.openPersistent,
  });
  final Future<FixtureTransport> Function() connect;
  final VoidCallback openPersistent;
  @override
  State<FixtureApp> createState() => _FixtureAppState();
}

class _FixtureAppState extends State<FixtureApp> {
  FixtureWorkspace? _workspace;
  final _label = TextEditingController(), _filter = TextEditingController();
  final _reviewFocus = FocusNode();
  var _valueState = 'unspecified';
  var _status = 'Connecting to the bundled disposable engine…';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final transport = await widget.connect();
      if (!mounted) {
        await transport.close();
        return;
      }
      setState(() {
        _workspace = FixtureWorkspace(transport);
        _busy = false;
        _status = 'Open a universe to load its fixture records.';
      });
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'The disposable engine is unavailable. Open fixture mode from a complete desktop bundle.';
        });
      }
    }
  }

  @override
  void dispose() {
    _workspace?.transport.close().ignore();
    _label.dispose();
    _filter.dispose();
    _reviewFocus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _status = 'Loading the selected universe…';
    });
    try {
      await _workspace!.open();
      if (mounted) {
        setState(
          () => _status = 'Connected · main continuity · revision 1 · timeless author frame',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _status =
              'Could not load this fixture universe. Try Open universe again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scope(String universe, String? world) => setState(() {
    _workspace!.selectScope(universe, world);
    _status = 'Scope changed. Open universe to load its records.';
  });
  Future<void> _review(BuildContext context) async {
    final draft = _workspace!.review(_label.text, _valueState);
    var saving = false;
    String? failure;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (!saving) Navigator.pop(dialog);
            },
          },
          child: PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: const Text('Review noncanonical proposal'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Universe: ${draft.universe.value}'),
                    const SizedBox(height: 12),
                    SelectableText('Create entity: ${draft.label}'),
                    const SizedBox(height: 12),
                    Text('Value state: ${_stateLabel(draft.valueState)}'),
                    const SizedBox(height: 12),
                    const Text(
                      'World applicability remains unspecified. World focus is a reading filter; it does not establish location or truth.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This saves a disposable proposal. It does not approve or publish canon.',
                    ),
                    if (failure != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(failure!),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  autofocus: true,
                  onPressed: saving ? null : () => Navigator.pop(dialog),
                  child: const Text('Back to draft'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          update(() {
                            saving = true;
                            failure = null;
                          });
                          try {
                            final saved = await _workspace!.save(draft);
                            if (mounted) {
                              setState(
                                () => _status =
                                    'Draft saved · ${saved.proposalId.value} · noncanonical · no approval or commit',
                              );
                            }
                            if (dialog.mounted) Navigator.pop(dialog);
                          } on Object {
                            if (dialog.mounted) {
                              update(() {
                                saving = false;
                                failure = 'The save could not be confirmed. Retry this exact proposal with the same key, or return to the draft.';
                              });
                            }
                          }
                        },
                  child: Text(
                    saving
                        ? 'Saving…'
                        : failure == null
                        ? 'Save noncanonical proposal'
                        : 'Retry exact proposal',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) _reviewFocus.requestFocus();
  }

  String _stateLabel(String value) => switch (value) {
    'known' => 'Known text',
    'explicit_absence' => 'Explicit absence',
    _ => 'Unspecified',
  };
  Future<void> _pickSource() async {
    try {
      final path = await pickSourcePath();
      if (mounted) {
        setState(
          () => _status = path == null
              ? 'No source selected. No import performed.'
              : 'Source selected locally. No import or canon change performed.',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () =>
              _status = 'Source selection is unavailable. No import performed.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Universe Builder — Fixture',
    debugShowCheckedModeBanner: false,
    theme: universeBuilderTheme(Brightness.light),
    darkTheme: universeBuilderTheme(Brightness.dark),
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('Universe Builder · Fixture'),
          actions: [
            TextButton(
              onPressed: _busy ? null : widget.openPersistent,
              child: const Text('Open author workspace'),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/universe-builder.png',
                          width: 64,
                          height: 64,
                          semanticLabel: 'Universe Builder',
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Text(
                            'Keep worlds distinct. Keep canon deliberate.',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Disposable fixture · Read and propose · Canon publication unavailable',
                    ),
                    const SizedBox(height: 24),
                    if (_workspace != null)
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 280,
                            child: DropdownButtonFormField<String>(
                              initialValue: _workspace!.universe,
                              decoration: const InputDecoration(
                                labelText: 'Universe',
                              ),
                              items: [
                                for (final name in FixtureWorkspace.universes)
                                  DropdownMenuItem(
                                    value: name,
                                    child: Text(name),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (name) {
                                      if (name != null) _scope(name, null);
                                    },
                            ),
                          ),
                          SizedBox(
                            width: 260,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(_workspace!.universe),
                              initialValue: _workspace!.world ?? '',
                              decoration: const InputDecoration(
                                labelText: 'World focus',
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text('All universe content'),
                                ),
                                const DropdownMenuItem(
                                  value: 'Aster',
                                  child: Text('Aster'),
                                ),
                                if (_workspace!.universe ==
                                    FixtureWorkspace.universes.first)
                                  const DropdownMenuItem(
                                    value: 'Nacre',
                                    child: Text('Nacre'),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (world) => _scope(
                                      _workspace!.universe,
                                      world == '' ? null : world,
                                    ),
                            ),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : _open,
                            child: Text(_busy ? 'Loading…' : 'Open universe'),
                          ),
                        ],
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Semantics(liveRegion: true, child: Text(_status)),
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, size) => size.maxWidth >= 860
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _records()),
                                const SizedBox(width: 24),
                                Expanded(child: _draft(context)),
                              ],
                            )
                          : Column(
                              children: [
                                _records(),
                                const SizedBox(height: 24),
                                _draft(context),
                              ],
                            ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Closing this fixture ends its engine and discards its proposals. Persistent storage, approvals and continuity validation are available in the author workspace.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _records() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Explore fixture records', style: TextStyle(fontSize: 22)),
          const SizedBox(height: 16),
          Semantics(
            label: 'Filter by name',
            child: TextField(
              controller: _filter,
              decoration: const InputDecoration(
                labelText: 'Filter by name',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          if (_workspace?.hits.isEmpty ?? true)
            const Text('No fixture records loaded.'),
          for (final hit in _workspace?.hits ?? const <SearchHit>[])
            if (hit.label.toLowerCase().contains(_filter.text.toLowerCase()))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(hit.label),
                subtitle: Text(
                  hit.worldIds.isEmpty
                      ? 'Unassigned'
                      : hit.worldIds
                            .map(FixtureWorkspace.worldLabel)
                            .join(', '),
                ),
              ),
        ],
      ),
    ),
  );
  Widget _draft(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Draft a qualified value', style: TextStyle(fontSize: 22)),
          const SizedBox(height: 12),
          const Text(
            'This preserves an explicit value state in a proposal for review. It does not establish a fact.',
          ),
          const SizedBox(height: 16),
          Semantics(
            label: 'Entity label',
            child: TextField(
              controller: _label,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Entity label',
                hintText: 'The Lantern House',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _valueState,
            decoration: const InputDecoration(labelText: 'Value state'),
            items: [
              for (final state in ['unspecified', 'explicit_absence', 'known'])
                DropdownMenuItem(value: state, child: Text(_stateLabel(state))),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _valueState = value!),
          ),
          const SizedBox(height: 12),
          const Text(
            'Blank input stays blank. Missing information never becomes false or zero.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            focusNode: _reviewFocus,
            onPressed:
                _busy ||
                    _workspace?.context == null ||
                    _label.text.trim().isEmpty
                ? null
                : () => _review(context),
            child: const Text('Review proposal'),
          ),
          const Divider(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _pickSource,
                child: const Text('Choose source file (selection only)'),
              ),
              OutlinedButton(
                onPressed: () async {
                  try {
                    await Clipboard.setData(
                      const ClipboardData(
                        text: 'Universe Builder feasibility fixture — no canon commits',
                      ),
                    );
                    if (mounted) {
                      setState(() => _status = 'Fixture label copied.');
                    }
                  } on Object {
                    if (mounted) {
                      setState(() => _status = 'Clipboard unavailable.');
                    }
                  }
                },
                child: const Text('Copy fixture label'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
