import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;

import 'connection.dart';
import 'create_universe_page.dart';
import 'universe_creation.dart';
import 'world_editor_page.dart';
import 'connection_stub.dart' if (dart.library.io) 'connection_native.dart';

void main(List<String> arguments) =>
    runApp(UniverseBuilderApp(device: DeviceConnection(arguments)));

class UniverseBuilderApp extends StatefulWidget {
  const UniverseBuilderApp({super.key, required this.device});
  final DeviceConnection device;
  @override
  State<UniverseBuilderApp> createState() => _UniverseBuilderAppState();
}

class _UniverseBuilderAppState extends State<UniverseBuilderApp> {
  ThemeMode _theme = ThemeMode.system;
  AppSession? _session;
  InstanceLibrary? _library;
  LibraryEntry? _selected;
  Envelope<Description>? _description;
  String? _error;
  bool _busy = false;
  var _page = 0;

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final previous = _session;
    _session = null;
    setState(() {
      _library = null;
      _selected = null;
      _description = null;
    });
    AppSession? session;
    try {
      await previous?.close();
      session = await widget.device.connect();
      final library = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
      );
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() {
        _session = session;
        _library = library;
        _selected = null;
        _description = null;
        _page = 0;
      });
    } on Object {
      await session?.close();
      if (mounted) {
        setState(() {
          _error = 'Could not connect. Check that your local instance is available, then try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _open(LibraryEntry entry) async {
    setState(() {
      _busy = true;
      _error = null;
      _description = null;
      _selected = entry;
    });
    try {
      final value = await _session!.call(
        ToolEngineRequest(
          request: DescribeSummaryRequest(universe: Selector(entry.name)),
        ),
      );
      final description = Envelope<Description>.fromWire(
        value,
        Description.fromWire,
      );
      if (mounted) {
        setState(() {
          _description = description;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'This universe is unavailable with your current access. Refresh your connection to continue.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _newUniverse(BuildContext context) async {
    final session = _session!;
    final result = await Navigator.of(context).push<CreationResult>(
      MaterialPageRoute(
        builder: (_) => CreateUniversePage(
          create: (request) async =>
              createdUniverse(await session.call(request)),
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result.refresh) {
      await _connect();
      return;
    }
    final created = result.created!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final library = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
      );
      if (!mounted) return;
      setState(() {
        _library = library;
      });
      final entry = library.universes.singleWhere(
        (entry) => entry.id == created.id,
      );
      await _open(entry);
    } on Object {
      if (mounted) {
        setState(() {
          _error =
              'The universe was created. Refresh your connection to open it.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  ThemeData _colors(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff516b80),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Universe Builder',
    debugShowCheckedModeBanner: false,
    theme: _colors(Brightness.light),
    darkTheme: _colors(Brightness.dark),
    themeMode: _theme,
    home: Builder(
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 800;
          final content = _page == 1
              ? _settings()
              : _page == 2
              ? _help()
              : _library == null
              ? _entry()
              : _selected == null
              ? _universes(context)
              : _overview(context);
          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Image.asset(
                    'assets/universe-builder.png',
                    width: 36,
                    height: 36,
                    semanticLabel: 'Universe Builder',
                  ),
                  const SizedBox(width: 12),
                  const Text('Universe Builder'),
                ],
              ),
              actions: [
                if (_session != null)
                  IconButton(
                    onPressed: _busy ? null : _connect,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh connection',
                  ),
              ],
            ),
            body: Row(
              children: [
                if (wide)
                  NavigationRail(
                    selectedIndex: _page,
                    extended: constraints.maxWidth >= 1100,
                    onDestinationSelected: (index) => setState(() {
                      _page = index;
                    }),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.auto_stories_outlined),
                        selectedIcon: Icon(Icons.auto_stories),
                        label: Text('Library'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        label: Text('Settings'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.help_outline),
                        label: Text('Help'),
                      ),
                    ],
                  ),
                if (wide) const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      if (_busy) const LinearProgressIndicator(),
                      if (_error != null)
                        MaterialBanner(
                          content: Text(_error!),
                          actions: [
                            TextButton(
                              onPressed: _busy ? null : _connect,
                              child: const Text('Reconnect'),
                            ),
                          ],
                        ),
                      Expanded(child: FocusTraversalGroup(child: content)),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: _page,
                    onDestinationSelected: (index) => setState(() {
                      _page = index;
                    }),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.auto_stories_outlined),
                        label: 'Library',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        label: 'Settings',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.help_outline),
                        label: 'Help',
                      ),
                    ],
                  ),
          );
        },
      ),
    ),
  );

  Widget _entry() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your universes',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            const Text('Open the people, places and history in your library.'),
            const SizedBox(height: 28),
            if (widget.device.supportsLocal)
              FilledButton.icon(
                onPressed: _busy || !widget.device.available ? null : _connect,
                icon: const Icon(Icons.computer_outlined),
                label: const Text('Use this computer'),
              ),
            if (!widget.device.available)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(widget.device.unavailableMessage),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _universes(BuildContext context) => ListView(
    padding: const EdgeInsets.all(32),
    children: [
      const Text(
        'Library',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(
        'This computer · ${_session!.author ? 'Approval owner' : 'Contributor'}',
      ),
      const SizedBox(height: 24),
      if (_session!.author) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _newUniverse(context),
            icon: const Icon(Icons.add),
            label: const Text('Create universe'),
          ),
        ),
        const SizedBox(height: 24),
      ],
      if (_library!.universes.isEmpty)
        const Text('No universes are available to this profile.'),
      for (final universe in _library!.universes)
        ListTile(
          title: Text(universe.name),
          leading: const Icon(Icons.public_outlined),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : () => _open(universe),
        ),
    ],
  );

  Widget _overview(BuildContext context) => ListView(
    padding: const EdgeInsets.all(32),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            _selected = null;
            _description = null;
          }),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Library'),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        _selected!.name,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 24),
      if (_description != null) ...[
        const Text(
          'Continuities',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        for (final continuity in _description!.result.continuities)
          ListTile(
            title: Text(continuity.name),
            subtitle: Text(
              '${continuity.representedContexts.length} represented contexts',
            ),
            trailing:
                _session!.author && continuity.representedContexts.length == 1
                ? TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => WorldEditorPage(
                                session: _session!,
                                continuity: continuity,
                                scope: EditorFormScope(
                                  instance: _library!.instance,
                                  profile: _session!.principal,
                                  universe: _selected!.id,
                                  continuity: continuity.id,
                                ),
                              ),
                            ),
                          ),
                    child: const Text('World draft'),
                  )
                : null,
          ),
        const SizedBox(height: 24),
        const Text(
          'Worlds',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        if (_description!.result.worlds.isEmpty)
          const Text('No worlds are visible in this scope.'),
        for (final world in _description!.result.worlds)
          ListTile(
            title: Text(world.name.value),
            leading: const Icon(Icons.public_outlined),
          ),
        if (!_description!.delivery.complete)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Some results are not included in this view.'),
          ),
      ],
    ],
  );

  Widget _settings() => ListView(
    padding: const EdgeInsets.all(32),
    children: [
      const Text(
        'Settings',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 28),
      const Text('Appearance', style: TextStyle(fontSize: 20)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        children: [
          for (final mode in ThemeMode.values)
            ChoiceChip(
              label: Text(switch (mode) {
                ThemeMode.system => 'System',
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
              }),
              selected: _theme == mode,
              onSelected: (_) => setState(() {
                _theme = mode;
              }),
            ),
        ],
      ),
      const SizedBox(height: 12),
      const Text('System follows this device’s appearance.'),
      const SizedBox(height: 32),
      const Text('Connection', style: TextStyle(fontSize: 20)),
      const SizedBox(height: 12),
      Text(_session == null ? 'Not connected' : 'This computer'),
    ],
  );
  Widget _help() => ListView(
    padding: const EdgeInsets.all(32),
    children: const [
      Text('Help', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
      SizedBox(height: 24),
      Text(
        'Universe Builder keeps attributed facts and continuity. Changes to canon require an exact review, approval and separate publication.',
      ),
    ],
  );
}
