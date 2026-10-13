import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'entity_draft.dart';
import 'record_browser.dart';
import 'world_browser.dart';
import 'changes_page.dart';
import 'saved_changes.dart';

class EntityEditorPage extends StatefulWidget {
  const EntityEditorPage({
    super.key,
    required this.session,
    required this.universe,
    required this.scope,
    required this.continuity,
    required this.representedContext,
  });
  final AppSession session;
  final LibraryEntry universe;
  final EditorFormScope scope;
  final ContinuitySummary continuity;
  final RepresentedContextSummary representedContext;
  @override
  State<EntityEditorPage> createState() => _EntityEditorPageState();
}

class _EntityEditorPageState extends State<EntityEditorPage> {
  final _name = TextEditingController(),
      _role = TextEditingController(),
      _rationale = TextEditingController();
  UnfinishedEntityForm? _base;
  BigInt _generation = BigInt.zero;
  String _classification = '';
  List<WorldId> _selected = [];
  List<WorldSummary> _worlds = [];
  final List<SearchHit> _types = [];
  OpenedContext? _context;
  Delivery? _delivery;
  bool _worldsComplete = true;
  bool _loading = true,
      _saving = false,
      _adding = false,
      _dirty = false,
      _leaving = false;
  String? _error, _added;
  Timer? _autosave;
  late RevisionId _revision;
  bool get _disabled => _loading || _saving || _adding || _base == null;
  @override
  void initState() {
    super.initState();
    _revision = widget.continuity.revisionId;
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _name.dispose();
    _role.dispose();
    _rationale.dispose();
    super.dispose();
  }

  UnfinishedEntityForm _fresh() => UnfinishedEntityForm(
    baseRevision: _revision,
    representedContext: widget.representedContext.id,
    clientRef: RecordId.generate().value,
    name: '',
    classification: '',
    worldRole: '',
    rationale: '',
  );
  void _enter(UnfinishedEntityForm form) {
    _base = form;
    _name.text = form.name;
    _role.text = form.worldRole;
    _rationale.text = form.rationale;
    _classification = form.classification;
    _selected = [...form.worlds];
  }

  UnfinishedEntityForm get _form => UnfinishedEntityForm(
    baseRevision: _base!.baseRevision,
    representedContext: _base!.representedContext,
    clientRef: _base!.clientRef,
    name: _name.text,
    classification: _classification,
    worldRole: _role.text,
    rationale: _rationale.text,
    worlds: _selected,
  );
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await widget.session.loadEntityForm(widget.scope);
      if (!mounted) return;
      _enter(saved?.form ?? _fresh());
      _generation = saved?.generation ?? BigInt.zero;
      _dirty = false;
      await _choices();
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open this form or its choices. Check your connection and access, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choices() async {
    final pinned = ContinuitySummary(
      id: widget.continuity.id,
      revisionId: _base!.baseRevision,
      name: widget.continuity.name,
      representedContexts: widget.continuity.representedContexts,
    );
    _context = await openAuthorReadContext(
      widget.session,
      widget.universe,
      pinned,
      widget.representedContext,
    );
    final worlds = await readContextWorlds(
      session: widget.session,
      universe: widget.universe,
      continuity: pinned,
      representedContext: widget.representedContext,
    );
    _worlds = worlds.result.worlds;
    _worldsComplete = worlds.delivery.complete;
    _types.clear();
    await _readTypes();
  }

  Future<void> _readTypes({bool more = false}) async {
    final page = await searchContextRecords(
      session: widget.session,
      universe: widget.universe,
      context: _context!,
      query: '',
      kind: RecordKind.entityType,
      cursor: more ? _delivery?.cursor : null,
      limit: 100,
    );
    if (!mounted) return;
    _types.addAll(page.result.hits);
    _delivery = page.delivery;
  }

  Future<void> _moreTypes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _readTypes(more: true);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not load more classifications. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changed() {
    setState(() {
      _dirty = true;
      _added = null;
    });
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    if (_base == null || _saving || !_dirty) return;
    final form = _form;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.session.saveEntityForm(
        widget.scope,
        form,
        _generation,
      );
      if (mounted) {
        setState(() {
          _base = saved.form;
          _generation = saved.generation;
          _dirty = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not save these fields. Another window may have changed the form. Your entered fields remain here.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    if (_loading || _saving || _adding) return;
    _autosave?.cancel();
    if (_dirty) await _save();
    if (!mounted || _dirty || _saving) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && !_dirty && !_saving && !_adding) Navigator.of(context).pop();
  }

  Future<void> _add() async {
    _autosave?.cancel();
    await _save();
    if (!mounted || _dirty || _base == null) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      final loaded = await widget.session.call(
        LoadDraftEngineRequest(
          universe: Selector(widget.universe.name),
          continuityId: widget.scope.continuity,
        ),
      );
      final old = loaded is CanonicalNull ? null : SavedDraft.fromWire(loaded);
      final request = entityDraftRequest(
        universe: Selector(widget.universe.name),
        continuity: widget.scope.continuity,
        form: _form,
        previous: old,
      );
      if (old?.content.toWire().toText() != request.content.toWire().toText()) {
        await widget.session.call(request);
      }
      if (mounted) {
        setState(
          () => _added = 'Entity added to saved changes. Review, approve and publish it in Changes.',
        );
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm adding this entity. Your fields remain saved. Retry to check the saved draft before adding.',
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _startAnother() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = Envelope<Description>.fromWire(
        await widget.session.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: Selector(widget.universe.name),
              universeId: widget.universe.id,
            ),
          ),
        ),
        Description.fromWire,
      ).result;
      final continuity = summary.continuities.singleWhere(
        (c) => c.id == widget.scope.continuity,
      );
      if (!continuity.representedContexts.any(
        (c) => c.id == widget.representedContext.id,
      )) {
        throw const FormatException(
          'Choose an accessible context from the overview.',
        );
      }
      if (!mounted) return;
      setState(() {
        _revision = continuity.revisionId;
        _enter(_fresh());
        _dirty = true;
        _added = null;
      });
      await _save();
      await _choices();
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not start another entity. Check the saved form and connection before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      enabled: !_disabled,
      decoration: InputDecoration(labelText: label),
      maxLines: controller == _rationale ? 4 : 1,
      onChanged: (_) => _changed(),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _leaving || (!_dirty && !_saving && !_adding),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Person, place or other entity')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.continuity.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Context: ${representedContextName(widget.representedContext)}',
              ),
              const Text(
                'A name is enough to start. Unfinished work stays on this device; adding to Changes does not change canon.',
              ),
              if (_loading || _saving || _adding)
                const LinearProgressIndicator(),
              if (_base != null && _base!.baseRevision != _revision)
                const Text(
                  'Recovered fields use an earlier revision. Changes retain it until you explicitly rebase the draft.',
                ),
              _field(_name, 'Name'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_classification),
                initialValue: _classification,
                decoration: const InputDecoration(
                  labelText: 'Classification (optional)',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Leave unclassified'),
                  ),
                  for (final type in _types)
                    DropdownMenuItem(
                      value: type.recordId.value,
                      child: Text(type.label),
                    ),
                  if (_classification.isNotEmpty &&
                      !_types.any((t) => t.recordId.value == _classification))
                    DropdownMenuItem(
                      value: _classification,
                      child: const Text(
                        'Saved classification (not in loaded list)',
                      ),
                    ),
                ],
                onChanged: _disabled
                    ? null
                    : (value) {
                        setState(() => _classification = value!);
                        _changed();
                      },
              ),
              if (_delivery?.complete == false)
                TextButton(
                  onPressed: _disabled || _delivery?.cursor == null
                      ? null
                      : _moreTypes,
                  child: const Text('Load more classifications'),
                ),
              const SizedBox(height: 12),
              const Text('World associations'),
              const Text(
                'Selecting several worlds preserves one shared identity. No selection declares no association. Associations do not establish location.',
              ),
              for (final world in _worlds)
                CheckboxListTile(
                  title: Text(world.name.value),
                  value: _selected.contains(world.id),
                  onChanged: _disabled
                      ? null
                      : (selected) {
                          setState(() {
                            if (selected!) {
                              _selected.add(world.id);
                            } else {
                              _selected.remove(world.id);
                            }
                          });
                          _changed();
                        },
                ),
              if (!_worldsComplete)
                const Text('Only part of the world list was returned.'),
              if (_selected.any(
                (id) => !_worlds.any((world) => world.id == id),
              ))
                const Text(
                  'Saved world selections outside this list are retained.',
                ),
              if (_selected.isNotEmpty) _field(_role, 'World association role'),
              _field(_rationale, 'Notes and rationale'),
              const SizedBox(height: 16),
              Text(
                _dirty
                    ? 'Unsaved fields'
                    : _generation == BigInt.zero
                    ? 'No saved fields yet'
                    : 'Saved on this device',
              ),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
              if (_added != null) ...[
                Semantics(liveRegion: true, child: Text(_added!)),
                TextButton(
                  onPressed: _disabled ? null : _startAnother,
                  child: const Text('Start another entity'),
                ),
              ],
              FilledButton(
                onPressed: _disabled ? null : _add,
                child: const Text('Add entity to changes'),
              ),
              TextButton(
                onPressed: _disabled || !_dirty ? null : _save,
                child: const Text('Save unfinished work'),
              ),
              TextButton(
                onPressed: _disabled
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => ChangesPage(
                            changes: SavedChanges(
                              session: widget.session,
                              universe: Selector(widget.universe.name),
                              scope: widget.scope,
                            ),
                          ),
                        ),
                      ),
                child: const Text('Review saved changes'),
              ),
              if (_error != null && !_disabled)
                TextButton(
                  onPressed: _load,
                  child: const Text('Reload saved form and choices'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
