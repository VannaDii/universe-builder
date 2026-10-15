import 'app_theme.dart';
import 'fixture_page.dart';
import 'fixture_connection_stub.dart'
    if (dart.library.io) 'fixture_connection_native.dart';
import 'event_editor_page.dart';
import 'source_editor_page.dart';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart'
    show ContinuityId, RecordId, RecordRef;

import 'connection.dart';
import 'create_universe_page.dart';
import 'world_editor_page.dart';
import 'world_browser.dart';
import 'world_detail_page.dart';
import 'record_browser_page.dart';
import 'record_browser.dart';
import 'record_editor_page.dart';
import 'draft_operation_editor.dart';
import 'draft_navigation.dart';
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
import 'secret_editor_page.dart';
import 'appearance_editor_page.dart';
import 'story_time_editor_page.dart';
import 'memory_editor_page.dart';
import 'work_editor_page.dart';
import 'saga_editor_page.dart';
import 'scene_editor_page.dart';
import 'passage_editor_page.dart';
import 'work_version_editor_page.dart';
import 'boundary_editor_page.dart';
import 'exception_editor_page.dart';
import 'issue_decision_editor_page.dart';
import 'initialization_editor_page.dart';
import 'represented_context_editor_page.dart';
import 'item_power_editor_page.dart';
import 'plan_editor_page.dart';
import 'commitment_editor_page.dart';
import 'communication_editor_page.dart';
import 'continuity_page.dart';
import 'universe_access_page.dart';
import 'backup_file_dialogs.dart';
import 'device_storage.dart';
import 'hosted_connection_page.dart';
import 'storage_maintenance_page.dart';
import 'package_import_page.dart';
import 'navigation_location.dart';
import 'library_router.dart';
import 'calendar_editor_page.dart';
import 'pack_editor_page.dart';
import 'entity_editor_page.dart';
import 'changes_page.dart';
import 'writing_review.dart';
import 'writing_review_page.dart';
import 'saved_changes.dart';
import 'universe_name_page.dart';
import 'postgres_settings.dart';
import 'sqlite_settings.dart';
import 'connection_stub.dart'
    if (dart.library.io) 'connection_native.dart'
    if (dart.library.js_interop) 'connection_browser.dart';

Future<void> _openAuthorWorkspace() async {
  var arguments = const <String>[];
  try {
    final root = await mobileInstallationRoot();
    if (root != null) arguments = ['--installation', root];
  } on Object {
    // Other desktop runners resolve their ordinary connection themselves.
  }
  main(arguments);
}

void main(List<String> arguments) {
  if (arguments.contains('--fixture')) {
    final device = FixtureDevice(arguments);
    runApp(
      FixtureApp(connect: device.start, openPersistent: _openAuthorWorkspace),
    );
    return;
  }
  runApp(
    UniverseBuilderApp(
      device: DeviceConnection(
        arguments,
        saveBackupFile: saveBackupFile,
        openBackupFile: openBackupFile,
        pickImagePath: pickImagePath,
        pickSourcePath: pickSourcePath,
        pickSharedSourcePath: mobileSharedSources.pendingPath,
        releasePickedPath: releasePickedFile,
        installationRoot: mobileInstallationRoot,
      ),
    ),
  );
}

class UniverseBuilderApp extends StatefulWidget {
  const UniverseBuilderApp({super.key, required this.device});
  final DeviceConnection device;
  @override
  State<UniverseBuilderApp> createState() => _UniverseBuilderAppState();
}

class _UniverseBuilderAppState extends State<UniverseBuilderApp> {
  late final LibraryRouter _router = LibraryRouter(
    home: (_) => _home(),
    navigate: _navigateLibrary,
  );
  LibraryLocation? _resumeLocation;
  final _browserToken = TextEditingController();
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
  void initState() {
    super.initState();
    mobileSharedSources.addListener(_sharedSourceChanged);
    mobileSharedSources.start();
  }

  void _sharedSourceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    mobileSharedSources.removeListener(_sharedSourceChanged);
    mobileSharedSources.stop();
    _session?.close();
    _router.dispose();
    _browserToken.dispose();
    super.dispose();
  }

  Future<LibraryLocation> _navigateLibrary(LibraryLocation location) async {
    if (!mounted) return const LibraryLocation();
    if (location.universe != null) {
      if (_library == null) {
        _resumeLocation = location;
        setState(() => _page = 0);
        return location;
      }
      final entries = _library!.universes.where(
        (entry) => entry.id == location.universe,
      );
      if (entries.isEmpty) {
        setState(() {
          _selected = null;
          _description = null;
          _page = 0;
          _error = 'This universe is unavailable with your current access.';
        });
        return const LibraryLocation();
      }
      setState(() => _page = 0);
      await _open(entries.single, announce: false);
      if (location.editor != null ||
          location.record != null ||
          location.operationIndex != null) {
        if ((location.operationIndex != null ||
                location.recordAction != null ||
                (location.record == null && location.editor != 'records')) &&
            !_session!.author) {
          return LibraryLocation(universe: location.universe);
        }
        final matches = _description?.result.continuities.where(
          (c) => c.id == location.continuity,
        );
        if (matches == null ||
            matches.length != 1 ||
            selectedRepresentedContext(matches.single, location.context)?.id !=
                location.context) {
          setState(
            () => _error = 'This continuity or context is unavailable with your current access.',
          );
          return LibraryLocation(universe: location.universe);
        }
        final continuity = matches.single;
        _contexts[continuity.id] = location.context!;
        _worlds[continuity.id] = await readContextWorlds(
          session: _session!,
          universe: _selected!,
          continuity: continuity,
          representedContext: selectedRepresentedContext(
            continuity,
            location.context,
          )!,
        );
        Widget page;
        if (location.operationIndex != null) {
          try {
            final changes = SavedChanges(
              session: _session!,
              universe: Selector(_selected!.name),
              scope: EditorFormScope(
                instance: _library!.instance,
                profile: _session!.principal,
                universe: _selected!.id,
                continuity: continuity.id,
                representedContext: location.context,
              ),
            );
            final draft = draftForLocation(await changes.load(), location);
            page = await draftOperationEditor(
              changes,
              draft,
              location.operationIndex!,
            );
          } on FormatException catch (error) {
            setState(() => _error = error.message);
            return LibraryLocation(universe: location.universe);
          } on Object {
            setState(
              () => _error = 'This draft operation is unavailable. Open Changes to choose a current operation.',
            );
            return LibraryLocation(universe: location.universe);
          }
        } else if (location.record != null) {
          final represented = selectedRepresentedContext(
            continuity,
            location.context,
          )!;
          try {
            final opened = await openAuthorReadContext(
              _session!,
              _selected!,
              continuity,
              represented,
              revision: location.revision,
            );
            final material = await readContextRecordMaterial(
              session: _session!,
              universe: _selected!,
              context: opened,
              record: location.record!,
              group: FieldGroup.payload,
            );
            if (!material.delivery.complete ||
                material.result.records.length != 1 ||
                material.result.records.single.identity.recordId !=
                    location.record) {
              throw const FormatException('Record unavailable');
            }
            final record = material.result.records.single;
            final scope = EditorFormScope(
              instance: _library!.instance,
              profile: _session!.principal,
              universe: _selected!.id,
              continuity: continuity.id,
              representedContext: represented.id,
            );
            if (location.recordAction != null) {
              page = await recordEditorPage(
                session: _session!,
                universe: _selected!,
                continuity: continuity,
                representedContext: represented,
                opened: opened,
                scope: scope,
                record: record,
                action: location.recordAction!,
              );
            } else {
              page = RecordDetailPage(
                session: _session!,
                universe: _selected!,
                context: opened,
                record: location.record!,
                kind: record.identity.recordKind,
                label: dossierReferenceLabel(
                  material.result,
                  _selected!.id,
                  RecordRef(record: location.record!),
                ),
                scope: scope,
                continuity: continuity,
                representedContext: represented,
              );
            }
          } on Object {
            setState(
              () => _error = 'This record or revision is unavailable with your current access.',
            );
            return LibraryLocation(universe: location.universe);
          }
        } else {
          page = _linkedEditor(location, continuity);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _session != null &&
              _selected?.id == location.universe) {
            _router.navigatorKey.currentState!.push<void>(
              MaterialPageRoute(
                settings: RouteSettings(name: location.uri.toString()),
                builder: (_) => page,
              ),
            );
          }
        });
      }
      return location;
    }
    setState(() {
      _page = location.section.index;
      if (_page == 0) {
        _selected = null;
        _description = null;
        _worlds = {};
        _contexts = {};
      }
    });
    return location;
  }

  Widget _linkedEditor(
    LibraryLocation location,
    ContinuitySummary continuity,
  ) => switch (location.editor) {
    'records' => RecordBrowserPage(
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
    'entity' => EntityEditorPage(
      session: _session!,
      universe: _selected!,
      continuity: continuity,
      representedContext: selectedRepresentedContext(
        continuity,
        _contexts[continuity.id],
      )!,
      scope: EditorFormScope(
        instance: _library!.instance,
        profile: _session!.principal,
        universe: _selected!.id,
        continuity: continuity.id,
        representedContext: _contexts[continuity.id],
      ),
    ),
    'type' => TypeEditorPage(
      session: _session!,
      universe: _selected!,
      continuity: continuity,
      representedContext: selectedRepresentedContext(
        continuity,
        _contexts[continuity.id],
      )!,
      scope: EditorFormScope(
        instance: _library!.instance,
        profile: _session!.principal,
        universe: _selected!.id,
        continuity: continuity.id,
        representedContext: _contexts[continuity.id],
      ),
    ),
    'property' => PropertyEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'unit' => UnitEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'value-definition' => ValueDefinitionEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'relation' => RelationEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'action' => ActionEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'rule' => RuleEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'communication' => CommunicationEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'commitment' => CommitmentEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'plan' => PlanEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'item-power' => ItemPowerEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'represented-context' => RepresentedContextEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'initialization' => InitializationEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'issue-decision' => IssueDecisionEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'exception' => ExceptionEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'boundary' => BoundaryEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'work' => WorkEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'work-version' => WorkVersionEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'saga' => SagaEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'scene' => SceneEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'passage' => PassageEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'memory' => MemoryEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'observation' => ObservationEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'secret' => SecretEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'appearance' => AppearanceEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'story-time' => StoryTimeEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'attitude' => AttitudeEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'proposition' => PropositionEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'completeness' => CompletenessEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'source' => SourceEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'event' => EventEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'calendar' => CalendarEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'pack' => PackEditorPage(
      revision: continuity.revisionId,
      changes: SavedChanges(
        session: _session!,
        universe: Selector(_selected!.name),
        scope: EditorFormScope(
          instance: _library!.instance,
          profile: _session!.principal,
          universe: _selected!.id,
          continuity: continuity.id,
          representedContext: _contexts[continuity.id],
        ),
      ),
    ),
    'world' => WorldEditorPage(
      session: _session!,
      continuity: continuity,
      representedContext: selectedRepresentedContext(
        continuity,
        _contexts[continuity.id],
      ),
      universe: Selector(_selected!.name),
      scope: EditorFormScope(
        instance: _library!.instance,
        profile: _session!.principal,
        universe: _selected!.id,
        continuity: continuity.id,
        representedContext: _contexts[continuity.id],
      ),
    ),
    'writing' => WritingReviewPage(
      workflow: WritingWorkflow(
        SavedChanges(
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
    'changes' => ChangesPage(
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
    _ => throw const FormatException('Unsupported editor link'),
  };

  void _selectSection(int index) {
    setState(() => _page = index);
    if (widget.device.supportsBrowser) {
      _router.setLocation(
        index == 0 && _selected != null
            ? LibraryLocation(universe: _selected!.id)
            : LibraryLocation(section: LibrarySection.values[index]),
      );
    }
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
      if (widget.device.supportsBrowser &&
          _browserToken.text.trim().isNotEmpty) {
        widget.device.browserEnrollmentToken = _browserToken.text.trim();
        _browserToken.clear();
      }
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
      if (widget.device.supportsBrowser) {
        final target = _resumeLocation ?? _router.currentConfiguration;
        _resumeLocation = null;
        _router.setLocation(await _navigateLibrary(target));
      }
    } on Object {
      await session?.close();
      if (mounted) {
        setState(() {
          _error = widget.device.supportsBrowser
              ? 'Could not connect. Check that the instance is running. Use a fresh connection code if your session has expired.'
              : widget.device.isHosted
              ? 'Could not connect. Check the service address and profile access, then try again.'
              : 'Could not connect. Check that your local instance is available, then try again.';
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

  Future<void> _logoutBrowser() async {
    final session = _session;
    if (session?.logout == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session!.logout!();
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'The instance could not confirm sign-out. This tab is disconnected.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _session = null;
          _library = null;
          _selected = null;
          _description = null;
          _worlds = {};
          _contexts = {};
          _page = 0;
          _busy = false;
        });
      }
    }
  }

  Future<void> _openHosted(BuildContext context) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => HostedConnectionPage(connect: (choice) async {
        widget.device.hosted = choice;
        await _connect();
        if (_session == null) throw StateError('Service connection unavailable');
      }),
    ));
    if (_session == null) widget.device.hosted = null;
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

  Future<void> _renameUniverse(BuildContext context) async {
    final session = _session!;
    final renamed = await Navigator.of(context).push<LibraryEntry>(
      MaterialPageRoute(
        builder: (_) => UniverseNamePage(
          session: session,
          universe: _selected!,
        ),
      ),
    );
    if (!mounted || renamed == null || _session != session) return;
    setState(() {
      _busy = true;
      _error = null;
      _selected = renamed;
    });
    try {
      final library = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
      );
      if (!mounted || _session != session) return;
      setState(() => _library = library);
      await _open(renamed);
    } on Object {
      if (mounted) setState(() => _error = 'The rename was saved. Refresh the connection to reload this universe.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(LibraryEntry entry, {bool announce = true}) async {
    if (announce && widget.device.supportsBrowser) {
      _router.setLocation(LibraryLocation(universe: entry.id));
    }
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
        builder: (_) => CreateUniversePage(session: session),
      ),
    );
    if (!mounted || result == null) return;
    if (result.refresh) {
      await _connect();
      if (_session != null && _library != null) {
        try {
          final saved = await _session!.loadUniverseCreationForm!();
          if (saved?.form.creationPending == true) {
            await _session!.saveUniverseCreationForm!(
              saved!.form.withPending(false), saved.generation,
            );
          }
        } on Object {
          if (mounted) {
            setState(() => _error =
                'The library is open, but the interrupted creation fields could not be updated. Check the library again before another creation.');
          }
        }
      }
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

  @override
  Widget build(BuildContext context) => widget.device.supportsBrowser
      ? MaterialApp.router(
          title: 'Universe Builder',
          debugShowCheckedModeBanner: false,
          theme: universeBuilderTheme(Brightness.light),
          darkTheme: universeBuilderTheme(Brightness.dark),
          themeMode: _theme,
          routerDelegate: _router,
          routeInformationParser: const LibraryRouteParser(),
        )
      : MaterialApp(
          title: 'Universe Builder',
          debugShowCheckedModeBanner: false,
          theme: universeBuilderTheme(Brightness.light),
          darkTheme: universeBuilderTheme(Brightness.dark),
          themeMode: _theme,
          home: _home(),
        );

  Widget _home() => Builder(
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
              if (_session?.logout != null)
                IconButton(
                  onPressed: _busy ? null : _logoutBrowser,
                  icon: const Icon(Icons.logout),
                  tooltip: 'Sign out',
                ),
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
                  onDestinationSelected: _selectSection,
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
                    if (mobileSharedSources.error != null || mobileSharedSources.pending)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(children: [
                          Text(mobileSharedSources.error ??
                              'A shared text file is waiting. Open a universe, then choose Import source and Use shared text file.'),
                          if (mobileSharedSources.error != null)
                            TextButton(onPressed: mobileSharedSources.dismissError,
                                child: const Text('Dismiss message')),
                        ]),
                      ),
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
                  onDestinationSelected: _selectSection,
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
                onPressed: _busy || !widget.device.available ? null : () {
                  widget.device.hosted = null;
                  _connect();
                },
                icon: const Icon(Icons.computer_outlined),
                label: const Text('Use this device'),
              ),
            if (widget.device.supportsHosted)
              Builder(builder: (context) => TextButton.icon(
                onPressed: _busy ? null : () => _openHosted(context),
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Connect to a service'),
              )),
            if (widget.device.supportsBrowser) ...[
              const Text(
                'Connect to the instance serving this page. Paste a connection code from that instance, or resume this tab’s session.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _browserToken,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Connection code',
                  helperText:
                      'A code can be used once and expires after one minute.',
                ),
                onSubmitted: (_) {
                  if (!_busy) _connect();
                },
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: const Icon(Icons.link),
                label: const Text('Connect or resume'),
              ),
            ],
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
        '${widget.device.supportsBrowser || widget.device.isHosted ? 'Connected instance' : 'This device'} · ${_session!.author ? 'Approval owner' : 'Contributor'}',
      ),
      if (widget.device.supportsHosted && widget.device.hosted != null)
        SelectableText(widget.device.hosted!.endpoint.origin),
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
        if (_session!.pickArchiveFile != null)
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => Navigator.of(context)
                      .push<void>(
                        MaterialPageRoute(
                          builder: (_) => PackageImportPage(session: _session!),
                        ),
                      )
                      .then((_) {
                        if (mounted) _connect();
                      }),
            icon: const Icon(Icons.upload_file),
            label: const Text('Import a package'),
          ),
        if (_session!.restoreBackupFile != null || _session!.pickArchiveFile == null)
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
            if (widget.device.supportsBrowser) {
              _router.setLocation(const LibraryLocation());
            }
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
      if (_session!.author)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : () => _renameUniverse(context),
            child: const Text('Rename universe'),
          ),
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
                              settings: widget.device.supportsBrowser
                                  ? RouteSettings(
                                      name: LibraryLocation(
                                        universe: _selected!.id,
                                        continuity: continuity.id,
                                        context: _contexts[continuity.id],
                                        editor: 'records',
                                      ).uri.toString(),
                                    )
                                  : null,
                              builder: (_) => _linkedEditor(
                                LibraryLocation(
                                  universe: _selected!.id,
                                  continuity: continuity.id,
                                  context: _contexts[continuity.id],
                                  editor: 'records',
                                ),
                                continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'entity',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'entity',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'type',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'type',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'property',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'property',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'unit',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'unit',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'value-definition',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'value-definition',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'relation',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'relation',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'action',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'action',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'rule',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'rule',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'communication',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'communication',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'commitment',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'commitment',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'plan',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'plan',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'item-power',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'item-power',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'represented-context',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'represented-context',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'initialization',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'initialization',
                                          ),
                                          continuity,
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Initialize an instance'),
                        ),
                      if (_session!.author &&
                          _contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'issue-decision',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'issue-decision',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'exception',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'exception',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'boundary',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'boundary',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'work',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'work',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'work-version',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'work-version',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'saga',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'saga',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'scene',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'scene',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'passage',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'passage',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'memory',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'memory',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'observation',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'observation',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'secret',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'secret',
                                          ),
                                          continuity,
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Story secret'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'appearance',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'appearance',
                                          ),
                                          continuity,
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Appearance'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'story-time',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'story-time',
                                          ),
                                          continuity,
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Story time'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'attitude',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'attitude',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'proposition',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'proposition',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'completeness',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'completeness',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'source',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'source',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'event',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'event',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'calendar',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'calendar',
                                          ),
                                          continuity,
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
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'pack',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'pack',
                                          ),
                                          continuity,
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted && _selected != null) {
                                        _open(_selected!);
                                      }
                                    }),
                          child: const Text('Domain pack'),
                        ),
                      if (_contexts.containsKey(continuity.id))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        settings: widget.device.supportsBrowser
                                            ? RouteSettings(
                                                name: LibraryLocation(
                                                  universe: _selected!.id,
                                                  continuity: continuity.id,
                                                  context:
                                                      _contexts[continuity.id],
                                                  editor: 'world',
                                                ).uri.toString(),
                                              )
                                            : null,
                                        builder: (_) => _linkedEditor(
                                          LibraryLocation(
                                            universe: _selected!.id,
                                            continuity: continuity.id,
                                            context: _contexts[continuity.id],
                                            editor: 'world',
                                          ),
                                          continuity,
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
                                      settings: widget.device.supportsBrowser
                                          ? RouteSettings(
                                              name: LibraryLocation(
                                                universe: _selected!.id,
                                                continuity: continuity.id,
                                                context:
                                                    _contexts[continuity.id],
                                                editor: 'writing',
                                              ).uri.toString(),
                                            )
                                          : null,
                                      builder: (_) => _linkedEditor(
                                        LibraryLocation(
                                          universe: _selected!.id,
                                          continuity: continuity.id,
                                          context: _contexts[continuity.id],
                                          editor: 'writing',
                                        ),
                                        continuity,
                                      ),
                                    ),
                                  )
                                  .then((_) {
                                    if (mounted && _selected != null) {
                                      _open(_selected!);
                                    }
                                  }),
                        child: const Text('Writing proposals'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context)
                                  .push<void>(
                                    MaterialPageRoute(
                                      settings: widget.device.supportsBrowser
                                          ? RouteSettings(
                                              name: LibraryLocation(
                                                universe: _selected!.id,
                                                continuity: continuity.id,
                                                context:
                                                    _contexts[continuity.id],
                                                editor: 'changes',
                                              ).uri.toString(),
                                            )
                                          : null,
                                      builder: (_) => _linkedEditor(
                                        LibraryLocation(
                                          universe: _selected!.id,
                                          continuity: continuity.id,
                                          context: _contexts[continuity.id],
                                          editor: 'changes',
                                        ),
                                        continuity,
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
      Text(
        _session == null
            ? 'Not connected'
            : widget.device.supportsBrowser
            ? 'Connected instance'
            : 'This device',
      ),
      if (_library case final library?) ...[
        const SizedBox(height: 12),
        Text(switch (library.backend) {
          ConnectedBackend.sqlite => 'Database: SQLite',
          ConnectedBackend.postgres => 'Database: PostgreSQL',
        }),
        const SizedBox(height: 8),
        SelectableText('Instance: ${library.instance.value}'),
      ],
      if (widget.device.supportsLocalSettings && widget.device.available) ...[
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
      SizedBox(height: 16),
      Text(
        'In an editor, Command+S on Apple platforms or Ctrl+S elsewhere saves unfinished work. In Changes, it saves your rationale. Review, approval and publication remain separate actions.',
      ),
    ],
  );
}
