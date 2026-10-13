import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'entity_draft.dart';
import 'qualifier_draft.dart';
import 'temporal_validity_draft.dart';
import 'temporal_validity_fields.dart';
import 'record_browser.dart';
import 'record_fields.dart';
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
    this.editingDraft,
    this.operationIndex,
  });
  final SavedDraft? editingDraft;
  final int? operationIndex;
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
  final List<_AssociationFields> _associations = [];
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
  SavedDraft? _editingDraft, _savedDraft;
  bool _stale = false;
  late RevisionId _revision;
  bool get _disabled => _loading || _saving || _adding || _base == null;
  @override
  void initState() {
    super.initState();
    _revision = widget.continuity.revisionId;
    _editingDraft = widget.editingDraft;
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _name.dispose();
    _role.dispose();
    _rationale.dispose();
    for (final a in _associations) {
      a.dispose();
    }
    super.dispose();
  }

  UnfinishedEntityForm _fresh() => _editingDraft != null
      ? entityFormFromDraft(_editingDraft!, widget.operationIndex!)
      : UnfinishedEntityForm(
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
    for (final a in _associations) {
      a.dispose();
    }
    _associations.clear();
    final rows =
        form.associations ??
        (_editingDraft == null
            ? <EntityAssociationForm>[]
            : entityFormFromDraft(
                _editingDraft!,
                widget.operationIndex!,
              ).associations!);
    _associations.addAll(
      rows.map((row) {
        final ordinal = row.originalOrdinal;
        final source = _editingDraft == null || ordinal == null
            ? null
            : (_editingDraft!.content.operations[widget.operationIndex!]
                      as IntroduceInstanceOperation)
                  .worldAssociations
                  .elementAtOrNull(ordinal);
        return _AssociationFields(
          row,
          fallback: source == null
              ? null
              : [
                  for (final q in source.qualifiers.entries)
                    qualifierInput(q.key, q.value),
                ],
        );
      }),
    );
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
    draftVersion: _base!.draftVersion,
    associations: _editingDraft == null
        ? null
        : _associations.map(
            (a) => EntityAssociationForm(
              world: a.world,
              role: a.role.text,
              originalOrdinal: a.originalOrdinal,
              validity: a.validity,
              temporalValidity: a.temporalValidity,
              qualifiers: a.qualifiers.map((q) => q.form).toList(),
            ),
          ),
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
      _stale =
          _editingDraft != null &&
          (_base!.draftVersion != _editingDraft!.version ||
              _base!.baseRevision != _editingDraft!.content.baseRevision ||
              _base!.representedContext !=
                  _editingDraft!.content.representedContext);
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
    if (mounted && !_dirty && !_saving && !_adding) {
      Navigator.of(context).pop(_savedDraft);
    }
  }

  Future<void> _useCurrentFields() async {
    setState(() {
      _enter(_fresh());
      _stale = false;
      _dirty = true;
      _added = null;
      _loading = true;
    });
    try {
      await _save();
      await _choices();
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not reload the current choices. Retry opening this form.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
      if (_editingDraft != null) {
        if (_stale) {
          throw const FormatException(
            'These unfinished edits use an earlier draft. Use current draft fields before saving.',
          );
        }
        final content = replaceDraftEntity(
          draft: _editingDraft!,
          index: widget.operationIndex!,
          form: _form,
        );
        final saved = await SavedChanges(
          session: widget.session,
          universe: Selector(widget.universe.name),
          scope: widget.scope,
        ).saveContent(_editingDraft!, content);
        if (!mounted) return;
        setState(() {
          _editingDraft = saved;
          _savedDraft = saved;
          _enter(entityFormFromDraft(saved, widget.operationIndex!));
          _dirty = true;
          _added = 'Entity updated in saved changes. Return to Changes to review it.';
        });
        await _save();
        return;
      }
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

  Widget _field(
    TextEditingController controller,
    String label, {
    int? maxLines,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      enabled: !_disabled,
      decoration: InputDecoration(labelText: label),
      maxLines: maxLines ?? (controller == _rationale ? 4 : 1),
      onChanged: (_) => _changed(),
    ),
  );
  Widget _qualifierRow(
    _AssociationFields association,
    int index,
    Map<String, DomainValue> original,
  ) {
    final fields = association.qualifiers[index];
    final retained = original[fields.originalKey];
    return Card(
      key: ValueKey(fields),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(fields.name, 'Qualifier name'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey((fields, fields.kind)),
              initialValue: fields.kind,
              decoration: const InputDecoration(
                labelText: 'Qualifier value type',
              ),
              items: [
                if (retained != null || fields.kind == 'retain')
                  const DropdownMenuItem(
                    value: 'retain',
                    child: Text('Keep original exact value'),
                  ),
                for (final choice in {
                  'text': 'Text',
                  'boolean': 'Boolean',
                  'integer': 'Integer',
                  'decimal': 'Decimal',
                  'rational': 'Rational',
                }.entries)
                  DropdownMenuItem(
                    value: choice.key,
                    child: Text(choice.value),
                  ),
              ],
              onChanged: _disabled
                  ? null
                  : (value) {
                      setState(() => fields.kind = value!);
                      _changed();
                    },
            ),
            if (fields.kind == 'retain')
              retained == null
                  ? const Text(
                      'Original value unavailable. Reopen the current draft fields before saving.',
                    )
                  : ExactFields(value: retained.toWire())
            else ...[
              if (fields.kind == 'boolean')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey((fields, fields.value.text)),
                    initialValue: fields.value.text,
                    decoration: const InputDecoration(
                      labelText: 'Boolean value',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Choose true or false'),
                      ),
                      const DropdownMenuItem(
                        value: 'true',
                        child: Text('True'),
                      ),
                      const DropdownMenuItem(
                        value: 'false',
                        child: Text('False'),
                      ),
                      if (!['', 'true', 'false'].contains(fields.value.text))
                        DropdownMenuItem(
                          value: fields.value.text,
                          child: Text('Pending input: ${fields.value.text}'),
                        ),
                    ],
                    onChanged: _disabled
                        ? null
                        : (value) {
                            setState(() => fields.value.text = value!);
                            _changed();
                          },
                  ),
                )
              else
                _field(
                  fields.value,
                  fields.kind == 'rational' ? 'Numerator' : 'Qualifier value',
                  maxLines: fields.kind == 'text' ? 4 : 1,
                ),
              if (fields.kind == 'rational')
                _field(fields.denominator, 'Denominator'),
              _field(fields.unit, 'Unit ID (numeric values only, optional)'),
            ],
            TextButton(
              onPressed: _disabled
                  ? null
                  : () {
                      setState(() => association.qualifiers.removeAt(index));
                      fields.dispose();
                      _changed();
                    },
              child: const Text('Remove qualifier'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _associationRow(int index) {
    final fields = _associations[index];
    final originalOrdinal = fields.originalOrdinal;
    final original = originalOrdinal == null
        ? null
        : (_editingDraft!.content.operations[widget.operationIndex!]
                  as IntroduceInstanceOperation)
              .worldAssociations
              .elementAtOrNull(originalOrdinal);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Association ${index + 1}'),
            DropdownButtonFormField<String>(
              key: ValueKey(fields),
              initialValue: fields.world,
              decoration: const InputDecoration(labelText: 'Associated world'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Choose a world'),
                ),
                for (final world in _worlds)
                  DropdownMenuItem(
                    value: world.id.value,
                    child: Text(world.name.value),
                  ),
                if (fields.world.isNotEmpty &&
                    !_worlds.any((w) => w.id.value == fields.world))
                  DropdownMenuItem(
                    value: fields.world,
                    child: const Text('Saved world (not in loaded list)'),
                  ),
              ],
              onChanged: _disabled
                  ? null
                  : (value) {
                      setState(() => fields.world = value!);
                      _changed();
                    },
            ),
            _field(fields.role, 'Association role'),
            DropdownButtonFormField<String>(
              key: ValueKey((
                fields,
                fields.validity,
                fields.temporalValidity != null,
              )),
              initialValue: fields.temporalValidity != null
                  ? 'temporal'
                  : fields.validity == null
                  ? 'retain'
                  : switch (fields.validity!) {
                      UnspecifiedValidity() => 'unspecified',
                      UnknownValidity() => 'unknown',
                      ConditionalValidity() => 'conditional',
                      _ => 'retain',
                    },
              decoration: const InputDecoration(
                labelText: 'Association validity',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'retain',
                  child: Text('Keep current validity'),
                ),
                DropdownMenuItem(
                  value: 'unspecified',
                  child: Text('Unspecified'),
                ),
                DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
                DropdownMenuItem(
                  value: 'temporal',
                  child: Text('Temporal validity'),
                ),
                DropdownMenuItem(
                  value: 'conditional',
                  child: Text('Condition dependent'),
                ),
              ],
              onChanged: _disabled
                  ? null
                  : (value) {
                      setState(() {
                        fields.temporalValidity = value == 'temporal'
                            ? temporalValidityInput(
                                fields.validity ?? original?.validity,
                              )
                            : null;
                        fields.validity = switch (value) {
                          'unspecified' => const UnspecifiedValidity(),
                          'unknown' => const UnknownValidity(),
                          'conditional' => const ConditionalValidity(),
                          _ => null,
                        };
                      });
                      _changed();
                    },
            ),
            if (fields.temporalValidity != null)
              TemporalValidityFields(
                key: ValueKey(('temporal', fields)),
                input: fields.temporalValidity!,
                disabled: _disabled,
                onChanged: (input) {
                  setState(() => fields.temporalValidity = input);
                  _changed();
                },
              ),
            if (original != null) ...[
              const Text('Original validity and qualifiers'),
              ExactFields(
                value: CanonicalObject([
                  MapEntry('validity', original.validity.toWire()),
                  MapEntry(
                    'qualifiers',
                    CanonicalObject(
                      original.qualifiers.entries.map(
                        (e) => MapEntry(e.key, e.value.toWire()),
                      ),
                    ),
                  ),
                ]),
              ),
            ] else
              const Text(
                'New associations default to unspecified validity and no qualifiers.',
              ),
            const Text('Association qualifiers'),
            for (var q = 0; q < fields.qualifiers.length; q++)
              _qualifierRow(fields, q, original?.qualifiers ?? {}),
            if (fields.qualifiers.isEmpty) const Text('No qualifiers'),
            TextButton(
              onPressed: _disabled
                  ? null
                  : () {
                      setState(
                        () => fields.qualifiers.add(
                          _QualifierFields(const QualifierInput()),
                        ),
                      );
                      _changed();
                    },
              child: const Text('Add qualifier'),
            ),
            TextButton(
              onPressed: _disabled
                  ? null
                  : () {
                      setState(() => _associations.removeAt(index));
                      fields.dispose();
                      _changed();
                    },
              child: const Text('Remove association'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<SavedDraft>(
    canPop:
        _leaving ||
        (widget.editingDraft == null && !_dirty && !_saving && !_adding),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.editingDraft == null
              ? 'Person, place or other entity'
              : 'Edit entity in changes',
        ),
      ),
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
              if (_stale) ...[
                const Text(
                  'Recovered edits belong to an earlier draft. Your fields remain visible; use current draft fields before saving changes.',
                ),
                TextButton(
                  onPressed: _disabled ? null : _useCurrentFields,
                  child: const Text('Use current draft fields'),
                ),
              ],
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
              if (_editingDraft != null) ...[
                const Text('Retained name details'),
                const Text(
                  'Name metadata is retained. World and role edits retain validity and qualifiers unless those fields are explicitly changed.',
                ),
                ExactFields(
                  value:
                      (_editingDraft!.content.operations[widget.operationIndex!]
                              as IntroduceInstanceOperation)
                          .name
                          .toWire(),
                ),
                const Text('World associations (not location)'),
                for (var i = 0; i < _associations.length; i++)
                  _associationRow(i),
                if (_associations.isEmpty) const Text('No world associations'),
                if (!_worldsComplete)
                  const Text('Only part of the world list was returned.'),
                TextButton(
                  onPressed: _disabled
                      ? null
                      : () {
                          setState(
                            () => _associations.add(
                              _AssociationFields(
                                const EntityAssociationForm(
                                  world: '',
                                  role: '',
                                ),
                              ),
                            ),
                          );
                          _changed();
                        },
                  child: const Text('Add world association'),
                ),
              ] else ...[
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
                if (_selected.isNotEmpty)
                  _field(_role, 'World association role'),
                _field(_rationale, 'Notes and rationale'),
              ],
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
                if (widget.editingDraft == null)
                  TextButton(
                    onPressed: _disabled ? null : _startAnother,
                    child: const Text('Start another entity'),
                  ),
              ],
              FilledButton(
                onPressed: _disabled || _stale ? null : _add,
                child: Text(
                  widget.editingDraft == null
                      ? 'Add entity to changes'
                      : 'Save entity changes',
                ),
              ),
              TextButton(
                onPressed: _disabled || !_dirty ? null : _save,
                child: const Text('Save unfinished work'),
              ),
              if (widget.editingDraft == null)
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

final class _AssociationFields {
  _AssociationFields(
    EntityAssociationForm form, {
    List<QualifierInput>? fallback,
  }) : world = form.world,
       originalOrdinal = form.originalOrdinal,
       role = TextEditingController(text: form.role),
       validity = form.validity,
       temporalValidity = form.temporalValidity,
       qualifiers = (form.qualifiers ?? fallback ?? [])
           .map(_QualifierFields.new)
           .toList();
  String world;
  Validity? validity;
  TemporalValidityInput? temporalValidity;
  final int? originalOrdinal;
  final TextEditingController role;
  final List<_QualifierFields> qualifiers;
  void dispose() {
    role.dispose();
    for (final q in qualifiers) {
      q.dispose();
    }
  }
}

final class _QualifierFields {
  _QualifierFields(QualifierInput form)
    : name = TextEditingController(text: form.key),
      value = TextEditingController(text: form.value),
      denominator = TextEditingController(text: form.denominator),
      unit = TextEditingController(text: form.unit),
      kind = form.kind,
      originalKey = form.originalKey;
  final TextEditingController name, value, denominator, unit;
  String kind;
  final String? originalKey;
  QualifierInput get form => QualifierInput(
    key: name.text,
    kind: kind,
    value: value.text,
    denominator: denominator.text,
    unit: unit.text,
    originalKey: originalKey,
  );
  void dispose() {
    name.dispose();
    value.dispose();
    denominator.dispose();
    unit.dispose();
  }
}
