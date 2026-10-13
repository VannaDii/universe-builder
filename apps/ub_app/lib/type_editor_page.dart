import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'connection.dart';
import 'record_browser.dart';
import 'saved_changes.dart';
import 'type_draft.dart';
import 'world_browser.dart';

class TypeEditorPage extends StatefulWidget {
  const TypeEditorPage({
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
  State<TypeEditorPage> createState() => _TypeEditorPageState();
}

class _TypeEditorPageState extends State<TypeEditorPage> {
  final _namespace = TextEditingController(),
      _key = TextEditingController(),
      _name = TextEditingController(),
      _rationale = TextEditingController();
  UnfinishedTypeForm? _base;
  late RevisionId _revision;
  String _parent = '', _applicability = '';
  bool? _executable;
  List<WorldId> _selectedWorlds = [];
  List<WorldSummary> _worlds = [];
  final List<SearchHit> _parents = [];
  OpenedContext? _context;
  Delivery? _parentDelivery;
  bool _worldsComplete = true;
  BigInt _generation = BigInt.zero;
  bool _loading = true, _saving = false, _adding = false, _dirty = false;
  String? _error, _added;
  Timer? _autosave;

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
    for (final controller in [_namespace, _key, _name, _rationale]) {
      controller.dispose();
    }
    super.dispose();
  }

  UnfinishedTypeForm _fresh() => UnfinishedTypeForm(
    baseRevision: _revision,
    representedContext: widget.representedContext.id,
    clientRef: RecordId.generate().value,
    namespace: '',
    key: '',
    name: '',
    parentChoice: '',
    applicabilityChoice: '',
    rationale: '',
  );

  void _enter(UnfinishedTypeForm form) {
    _base = form;
    _namespace.text = form.namespace;
    _key.text = form.key;
    _name.text = form.name;
    _rationale.text = form.rationale;
    _parent = form.parentChoice;
    _applicability = form.applicabilityChoice;
    _executable = form.classificationExecutable;
    _selectedWorlds = [...form.worlds];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await widget.session.loadTypeForm(widget.scope);
      if (!mounted) return;
      _enter(saved?.form ?? _fresh());
      _generation = saved?.generation ?? BigInt.zero;
      _dirty = false;
      await _loadChoices();
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

  Future<void> _loadChoices() async {
    final continuity = ContinuitySummary(
      id: widget.continuity.id,
      revisionId: _base!.baseRevision,
      name: widget.continuity.name,
      representedContexts: widget.continuity.representedContexts,
    );
    _context = await openAuthorReadContext(
      widget.session,
      widget.universe,
      continuity,
      widget.representedContext,
    );
    final worlds = await readContextWorlds(
      session: widget.session,
      universe: widget.universe,
      continuity: continuity,
      representedContext: widget.representedContext,
    );
    _worlds = worlds.result.worlds;
    _worldsComplete = worlds.delivery.complete;
    _parents.clear();
    await _readParents();
  }

  Future<void> _readParents({bool more = false}) async {
    final context = _context;
    if (context == null) return;
    final page = await searchContextRecords(
      session: widget.session,
      universe: widget.universe,
      context: context,
      query: '',
      kind: RecordKind.entityType,
      cursor: more ? _parentDelivery?.cursor : null,
      limit: 100,
    );
    if (!mounted) return;
    _parents.addAll(page.result.hits);
    _parentDelivery = page.delivery;
  }

  Future<void> _moreParents() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _readParents(more: true);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not load more parent definitions. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  UnfinishedTypeForm _entered() => UnfinishedTypeForm(
    baseRevision: _base!.baseRevision,
    representedContext: _base!.representedContext,
    clientRef: _base!.clientRef,
    namespace: _namespace.text,
    key: _key.text,
    name: _name.text,
    parentChoice: _parent,
    applicabilityChoice: _applicability,
    rationale: _rationale.text,
    classificationExecutable: _executable,
    worlds: _selectedWorlds,
  );

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
    final entered = _entered();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.session.saveTypeForm(
        widget.scope,
        entered,
        _generation,
      );
      if (mounted) {
        setState(() {
          _generation = saved.generation;
          _base = saved.form;
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
      final previous = loaded is CanonicalNull
          ? null
          : SavedDraft.fromWire(loaded);
      final request = typeDraftRequest(
        universe: Selector(widget.universe.name),
        continuity: widget.scope.continuity,
        form: _entered(),
        previous: previous,
      );
      if (previous?.content.toWire().toText() !=
          request.content.toWire().toText()) {
        await widget.session.call(request);
      }
      if (mounted) {
        setState(
          () => _added = 'Type definition added to saved changes. Review, approve and publish it in Changes.',
        );
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm adding this definition. Your fields remain saved. Retry to check the saved draft before adding.',
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
        (item) => item.id == widget.scope.continuity,
      );
      if (!continuity.representedContexts.any(
        (item) => item.id == widget.representedContext.id,
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
      await _loadChoices();
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not start another type. Check the saved form and your connection before retrying.',
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Type definition')),
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
              'Unfinished work stays on this device. Definitions go into Changes for review; saving this form does not change canon.',
            ),
            if (_loading || _saving || _adding) const LinearProgressIndicator(),
            if (_base != null && _base!.baseRevision != _revision)
              const Text(
                'Recovered fields use an earlier revision. Changes will retain that revision until you explicitly rebase the draft.',
              ),
            _field(_namespace, 'Namespace'),
            _field(_key, 'Definition key'),
            _field(_name, 'Display name (optional)'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('parent:$_parent'),
              initialValue: _parent,
              decoration: const InputDecoration(labelText: 'Parent definition'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Choose a parent or no parent'),
                ),
                const DropdownMenuItem(
                  value: 'none',
                  child: Text('No parent (root definition)'),
                ),
                for (final parent in _parents)
                  DropdownMenuItem(
                    value: parent.recordId.value,
                    child: Text(parent.label),
                  ),
                if (_parent != '' &&
                    _parent != 'none' &&
                    !_parents.any((parent) => parent.recordId.value == _parent))
                  DropdownMenuItem(
                    value: _parent,
                    child: const Text('Saved parent (not in loaded list)'),
                  ),
              ],
              onChanged: _disabled
                  ? null
                  : (value) {
                      setState(() => _parent = value!);
                      _changed();
                    },
            ),
            if (_parentDelivery?.complete == false)
              TextButton(
                onPressed: _disabled || _parentDelivery?.cursor == null
                    ? null
                    : _moreParents,
                child: const Text('Load more parent definitions'),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('scope:$_applicability'),
              initialValue: _applicability,
              decoration: const InputDecoration(
                labelText: 'Where this definition applies',
              ),
              items: const [
                DropdownMenuItem(
                  value: '',
                  child: Text('Choose applicability'),
                ),
                DropdownMenuItem(
                  value: 'unspecified',
                  child: Text('Unspecified (remains unresolved)'),
                ),
                DropdownMenuItem(
                  value: 'universe_wide',
                  child: Text('Universe wide'),
                ),
                DropdownMenuItem(
                  value: 'worlds',
                  child: Text('Selected worlds'),
                ),
              ],
              onChanged: _disabled
                  ? null
                  : (value) {
                      setState(() => _applicability = value!);
                      _changed();
                    },
            ),
            if (_applicability == 'worlds') ...[
              const Text(
                'No selected worlds means this definition applies nowhere.',
              ),
              for (final world in _worlds)
                CheckboxListTile(
                  title: Text(world.name.value),
                  value: _selectedWorlds.contains(world.id),
                  onChanged: _disabled
                      ? null
                      : (selected) {
                          setState(() {
                            if (selected!) {
                              _selectedWorlds.add(world.id);
                            } else {
                              _selectedWorlds.remove(world.id);
                            }
                          });
                          _changed();
                        },
                ),
              if (!_worldsComplete)
                const Text('Only part of the world list was returned.'),
              if (_selectedWorlds.any(
                (id) => !_worlds.any((world) => world.id == id),
              ))
                const Text(
                  'Saved world selections outside this list are retained.',
                ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
              key: ValueKey('executable:$_executable'),
              initialValue: _executable,
              decoration: const InputDecoration(
                labelText: 'Use for executable classification',
              ),
              hint: const Text('Choose explicitly'),
              items: const [
                DropdownMenuItem(value: true, child: Text('Yes')),
                DropdownMenuItem(
                  value: false,
                  child: Text('No — retain as non-executable'),
                ),
              ],
              onChanged: _disabled
                  ? null
                  : (value) {
                      setState(() => _executable = value);
                      _changed();
                    },
            ),
            const Text(
              'Ancestor applicability is checked separately. A child does not widen its parent’s scope.',
            ),
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
                child: const Text('Start another type'),
              ),
            ],
            FilledButton(
              onPressed: _disabled ? null : _add,
              child: const Text('Add type to changes'),
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
            if (_error != null && !_loading && !_saving && !_adding)
              TextButton(
                onPressed: _load,
                child: const Text('Reload saved form and choices'),
              ),
          ],
        ),
      ),
    ),
  );
}
