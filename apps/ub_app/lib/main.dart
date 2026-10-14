import 'event_editor_page.dart';
import 'source_editor_page.dart';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart' show ContinuityId, RecordId;

import 'connection.dart';
import 'create_universe_page.dart';
import 'universe_creation.dart';
import 'world_editor_page.dart';
import 'world_browser.dart';
import 'world_detail_page.dart';
import 'record_browser_page.dart';
import 'type_editor_page.dart';
import 'property_editor_page.dart';
import 'unit_editor_page.dart';
import 'value_definition_editor_page.dart';
import 'relation_editor_page.dart';
import 'action_editor_page.dart';
import 'rule_editor_page.dart';
import 'completeness_editor_page.dart';
import 'proposition_editor_page.dart';
import 'attitude_editor_page.dart';
import 'observation_editor_page.dart';
import 'memory_editor_page.dart';
import 'work_editor_page.dart';
import 'saga_editor_page.dart';
import 'scene_editor_page.dart';
import 'passage_editor_page.dart';
import 'work_version_editor_page.dart';
import 'boundary_editor_page.dart';
import 'exception_editor_page.dart';
import 'issue_decision_editor_page.dart';
import 'represented_context_editor_page.dart';
import 'item_power_editor_page.dart';
import 'plan_editor_page.dart';
import 'commitment_editor_page.dart';
import 'communication_editor_page.dart';
import 'continuity_page.dart';
import 'universe_access_page.dart';
import 'backup_file_dialogs.dart';
import 'storage_maintenance_page.dart';
import 'calendar_editor_page.dart';
import 'entity_editor_page.dart';
import 'changes_page.dart';
import 'saved_changes.dart';
import 'postgres_settings.dart';
import 'sqlite_settings.dart';
import 'connection_stub.dart' if (dart.library.io) 'connection_native.dart';

void main(List<String> arguments) => runApp(
  UniverseBuilderApp(
    device: DeviceConnection(
      arguments,
      saveBackupFile: saveBackupFile,
      openBackupFile: openBackupFile,
    ),
  ),
);

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
  Map<ContinuityId, Envelope<Description>> _worlds = {};
  Map<ContinuityId, RecordId> _contexts = {};
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
      _worlds = {};
      _contexts = {};
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

  Future<void> _applyPostgres(TestedPostgresConnection target) async {
    final current = _session;
    if (current != null && !current.author) {
      throw StateError('Author access required');
    }
    final checked = await widget.device.testPostgres(target.endpoint);
    if (checked.instance != target.instance ||
        checked.profile != target.profile) {
      throw StateError('Selected installation changed');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _stopLocalEngine();
      await widget.device.savePostgres(target);
      await _connect();
      if (_library?.instance != target.instance ||
          _library?.backend != ConnectedBackend.postgres) {
        if (mounted) {
          setState(() {
            _page = 1;
            _error = 'Saved PostgreSQL settings, but could not connect to the selected instance. Check service environment overrides and reconnect.';
          });
        }
        throw StateError('Selected connection unavailable');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _stopLocalEngine() async {
    final current = _session;
    if (current != null) {
      if (!current.author) throw StateError('Author access required');
      await current.call(const ShutdownEngineRequest());
      await current.close();
    }
    if (mounted) {
      setState(() {
        _session = null;
        _library = null;
        _selected = null;
        _description = null;
        _worlds = {};
        _contexts = {};
      });
    }
  }

  Future<TestedSqliteConnection> _testSqlite() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _stopLocalEngine();
      return await widget.device.testSqlite();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _applySqlite(TestedSqliteConnection target) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _stopLocalEngine();
      await widget.device.saveSqlite(target);
      await _connect();
      if (_library?.instance != target.instance ||
          _library?.backend != ConnectedBackend.sqlite) {
        if (mounted) {
          setState(() {
            _page = 1;
            _error = 'Saved SQLite settings, but could not connect to the selected local instance. Check service environment overrides and reconnect.';
          });
        }
        throw StateError('Selected connection unavailable');
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
    final previousContexts = _selected?.id == entry.id
        ? _contexts
        : <ContinuityId, RecordId>{};
    final session = _session!;
    setState(() {
      _busy = true;
      _error = null;
      _description = null;
      _selected = entry;
      _worlds = {};
    });
    try {
      final value = await session.call(
        ToolEngineRequest(
          request: DescribeSummaryRequest(universe: Selector(entry.name)),
        ),
      );
      final description = Envelope<Description>.fromWire(
        value,
        Description.fromWire,
      );
      final worlds = <ContinuityId, Envelope<Description>>{};
      final contexts = <ContinuityId, RecordId>{};
      for (final continuity in description.result.continuities) {
        final chosen = selectedRepresentedContext(
          continuity,
          previousContexts[continuity.id],
        );
        if (chosen == null) continue;
        contexts[continuity.id] = chosen.id;
        worlds[continuity.id] = await readContextWorlds(
          session: session,
          universe: entry,
          continuity: continuity,
          representedContext: chosen,
        );
      }
      if (mounted && _selected?.id == entry.id && _session == session) {
        setState(() {
          _contexts = contexts;
          _description = description;
          _worlds = worlds;
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

  Future<void> _chooseContext(ContinuitySummary continuity, RecordId id) async {
    final entry = _selected!, session = _session!;
    final chosen = selectedRepresentedContext(continuity, id);
    if (chosen == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _contexts[continuity.id] = chosen.id;
      _worlds.remove(continuity.id);
    });
    try {
      final worlds = await readContextWorlds(
        session: session,
        universe: entry,
        continuity: continuity,
        representedContext: chosen,
      );
      if (mounted && _selected?.id == entry.id && _session == session) {
        setState(() {
          _worlds[continuity.id] = worlds;
        });
      }
    } on Object {
      if (mounted && _selected?.id == entry.id && _session == session) {
        setState(() {
          _error = 'Could not read worlds in this context. Check your access and choose the context again.';
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
        TextButton.icon(
          onPressed: _busy || _session!.restoreBackupFile == null
              ? null
              : () => Navigator.of(context)
                    .push<void>(
                      MaterialPageRoute(
                        builder: (_) =>
                            StorageMaintenancePage(session: _session!),
                      ),
                    )
                    .then((_) {
                      if (mounted) _connect();
                    }),
          icon: const Icon(Icons.restore),
          label: const Text('Restore a backup'),
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
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${continuity.representedContexts.length} represented contexts',
                ),
                if (continuity.representedContexts.isNotEmpty)
                  DropdownButtonFormField<RecordId>(
                    key: ValueKey(
                      '${continuity.id.value}:${_contexts[continuity.id]?.value}',
                    ),
                    initialValue: _contexts[continuity.id],
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Represented context',
                    ),
                    hint: const Text('Choose a context'),
                    items: [
                      for (final represented in continuity.representedContexts)
                        DropdownMenuItem(
                          value: represented.id,
                          child: Text(representedContextName(represented)),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (id) {
                            if (id != null) _chooseContext(continuity, id);
                          },
                  ),
                if (_contexts.containsKey(continuity.id))
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => RecordBrowserPage(
                                session: _session!,
                                universe: _selected!,
                                scope: EditorFormScope(
                                  instance: _library!.instance,
                                  profile: _session!.principal,
                                  universe: _selected!.id,
                                  continuity: continuity.id,
                                ),
                                continuity: continuity,
                                representedContext: selectedRepresentedContext(
                                  continuity,
                                  _contexts[continuity.id],
                                )!,
                              ),
                            ),
                          ),
                    child: const Text('Records'),
                  ),
                if (_session!.author)
                  Wrap(
                    children: [
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => EntityEditorPage(
                                          session: _session!,
                                          universe: _selected!,
                                          continuity: continuity,
                                          representedContext:
                                              selectedRepresentedContext(
                                                continuity,
                                                _contexts[continuity.id],
                                              )!,
                                          scope: EditorFormScope(
                                            instance: _library!.instance,
                                            profile: _session!.principal,
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            representedContext:
                                                _contexts[continuity.id],
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Person, place or entity'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => TypeEditorPage(
                                          session: _session!,
                                          universe: _selected!,
                                          continuity: continuity,
                                          representedContext:
                                              selectedRepresentedContext(
                                                continuity,
                                                _contexts[continuity.id],
                                              )!,
                                          scope: EditorFormScope(
                                            instance: _library!.instance,
                                            profile: _session!.principal,
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            representedContext:
                                                _contexts[continuity.id],
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Type definition'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => PropertyEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Property definition'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => UnitEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Unit definition'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ValueDefinitionEditorPage(
                                              revision: continuity.revisionId,
                                              changes: SavedChanges(
                                                session: _session!,
                                                universe: Selector(
                                                  _selected!.name,
                                                ),
                                                scope: EditorFormScope(
                                                  instance: _library!.instance,
                                                  profile: _session!.principal,
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  representedContext:
                                                      _contexts[continuity.id],
                                                ),
                                              ),
                                            ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Value definition'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => RelationEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Relation definition'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => ActionEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Action definition'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => RuleEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Rule definition'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => CommunicationEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Communication'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => CommitmentEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Commitment'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => PlanEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Plan'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => ItemPowerEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Item power'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            RepresentedContextEditorPage(
                                              revision: continuity.revisionId,
                                              changes: SavedChanges(
                                                session: _session!,
                                                universe: Selector(
                                                  _selected!.name,
                                                ),
                                                scope: EditorFormScope(
                                                  instance: _library!.instance,
                                                  profile: _session!.principal,
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  representedContext:
                                                      _contexts[continuity.id],
                                                ),
                                              ),
                                            ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Context definition'),
                        ),
                      if (_session!.author &&
                          _contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => IssueDecisionEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Issue decision'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => ExceptionEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Exception'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => BoundaryEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Creative boundary'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => WorkEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Work'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => WorkVersionEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Work edition'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => SagaEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Saga'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => SceneEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Scene reference'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => PassageEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Passage reference'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => MemoryEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Memory'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => ObservationEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Observation'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => AttitudeEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Belief or knowledge'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => PropositionEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Proposition'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => CompletenessEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Complete collection'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => ContinuityPage(
                                          target: continuity,
                                          continuities:
                                              _description!.result.continuities,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Continuities'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => UniverseAccessPage(
                                          revision: continuity.revisionId,
                                          worlds:
                                              _worlds[continuity.id]
                                                  ?.result
                                                  .worlds ??
                                              [],
                                          continuities:
                                              _description!.result.continuities,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Universe access'),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context)
                                  .push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => StorageMaintenancePage(
                                        session: _session!,
                                        universe: _selected!,
                                      ),
                                    ),
                                  )
                                  .then((_) {
                                    if (mounted) _connect();
                                  }),
                        child: const Text('Backup and storage'),
                      ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => SourceEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Import source'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => EventEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Event'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => CalendarEditorPage(
                                          revision: continuity.revisionId,
                                          changes: SavedChanges(
                                            session: _session!,
                                            universe: Selector(_selected!.name),
                                            scope: EditorFormScope(
                                              instance: _library!.instance,
                                              profile: _session!.principal,
                                              universe: _selected!.id,
                                              continuity: continuity.id,
                                              representedContext:
                                                  _contexts[continuity.id],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Calendar definition'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => WorldEditorPage(
                                          session: _session!,
                                          continuity: continuity,
                                          representedContext:
                                              selectedRepresentedContext(
                                                continuity,
                                                _contexts[continuity.id],
                                              ),
                                          universe: Selector(_selected!.name),
                                          scope: EditorFormScope(
                                            instance: _library!.instance,
                                            profile: _session!.principal,
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            representedContext:
                                                _contexts[continuity.id],
                                          ),
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('World draft'),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context)
                                  .push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => ChangesPage(
                                        changes: SavedChanges(
                                          session: _session!,
                                          universe: Selector(_selected!.name),
                                          scope: EditorFormScope(
                                            instance: _library!.instance,
                                            profile: _session!.principal,
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .then((_) {
                                    if (mounted && _selected != null) {
                                      _open(_selected!);
                                    }
                                  }),
                        child: const Text('Changes'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        const Text(
          'Worlds',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        for (final continuity in _description!.result.continuities) ...[
          Text(continuity.name, style: Theme.of(context).textTheme.titleMedium),
          if (_contexts.containsKey(continuity.id))
            Text(
              'Context: ${representedContextName(selectedRepresentedContext(continuity, _contexts[continuity.id])!)}',
            ),
          if (!_worlds.containsKey(continuity.id))
            const Text('Choose a represented context to read its worlds.'),
          if (_worlds[continuity.id]?.result.worlds.isEmpty ?? false)
            const Text('No worlds are visible in this context.'),
          for (final world
              in _worlds[continuity.id]?.result.worlds ?? <WorldSummary>[])
            ListTile(
              title: Text(world.name.value),
              leading: const Icon(Icons.public_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy
                  ? null
                  : () => Navigator.of(context)
                        .push<void>(
                          MaterialPageRoute(
                            builder: (_) => WorldDetailPage(
                              session: _session!,
                              universe: _selected!,
                              continuity: continuity,
                              representedContext: selectedRepresentedContext(
                                continuity,
                                _contexts[continuity.id],
                              )!,
                              world: world,
                              scope: EditorFormScope(
                                instance: _library!.instance,
                                profile: _session!.principal,
                                universe: _selected!.id,
                                continuity: continuity.id,
                              ),
                            ),
                          ),
                        )
                        .then((_) {
                          if (mounted && _selected != null) _open(_selected!);
                        }),
            ),
          if (_worlds[continuity.id]?.delivery.complete == false)
            const Text('Only part of this world list was delivered.'),
        ],
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
      if (_library case final library?) ...[
        const SizedBox(height: 12),
        Text(switch (library.backend) {
          ConnectedBackend.sqlite => 'Database: SQLite',
          ConnectedBackend.postgres => 'Database: PostgreSQL',
        }),
        const SizedBox(height: 8),
        SelectableText('Instance: ${library.instance.value}'),
      ],
      if (widget.device.supportsLocal && widget.device.available) ...[
        const SizedBox(height: 32),
        PostgresSettings(
          key: const ValueKey('postgres-settings'),
          enabled: !_busy && (_session == null || _session!.author),
          test: widget.device.testPostgres,
          apply: _applyPostgres,
        ),
        const SizedBox(height: 32),
        SqliteSettings(
          key: const ValueKey('sqlite-settings'),
          enabled: !_busy && (_session == null || _session!.author),
          connected: _session != null,
          test: _testSqlite,
          apply: _applySqlite,
        ),
      ],
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
