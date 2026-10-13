import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'entity_draft.dart';
import 'qualifier_draft.dart';
import 'value_input_fields.dart';
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
    this.publishedEntity,
    this.refineClassification = false,
  });
  final RecordVersion? publishedEntity;
  final bool refineClassification;
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
      _rationale = TextEditingController(),
      _language = TextEditingController(),
      _community = TextEditingController(),
      _nameRole = TextEditingController();
  String? _languageValue, _communityValue, _nameRoleValue;
  Validity? _nameValidity;
  TemporalValidityInput? _nameTemporal;
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
  SavedChanges get _calendarChanges => SavedChanges(
    session: widget.session,
    universe: Selector(widget.universe.name),
    scope: widget.scope,
  );
  SavedDraft get _calendarChoices => SavedDraft(
    version: BigInt.zero,
    content: DraftContent(
      baseRevision: _base!.baseRevision,
      representedContext: _base!.representedContext,
      operations: [],
      rationale: '',
    ),
  );
  bool get _disabled => _loading || _saving || _adding || _base == null;
  bool get _classificationOnly =>
      widget.refineClassification ||
      (_editingDraft != null &&
          _editingDraft!.content.operations[widget.operationIndex!]
              is RefineClassificationOperation);
  bool get _recordOnly => _nameOnly || _classificationOnly;
  bool get _nameOnly =>
      (widget.publishedEntity != null && !widget.refineClassification) ||
      (_editingDraft != null &&
          _editingDraft!.content.operations[widget.operationIndex!]
              is AddNameOperation);
  ContextualName? get _originalName {
    if (_editingDraft == null) return null;
    return switch (_editingDraft!.content.operations[widget.operationIndex!]) {
      IntroduceInstanceOperation(:final name) => name,
      AddNameOperation(:final name) => name,
      _ => null,
    };
  }

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
    _language.dispose();
    _community.dispose();
    _nameRole.dispose();
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
          clientRef:
              widget.publishedEntity?.identity.recordId.value ??
              RecordId.generate().value,
          expectedRecordVersion: widget.publishedEntity?.recordVersionId,
          name: '',
          classification: '',
          worldRole: '',
          rationale: '',
        );
  void _enter(UnfinishedEntityForm form) {
    _base = form;
    _name.text = form.name;
    final details =
        form.nameDetails ??
        (_editingDraft == null
            ? null
            : entityFormFromDraft(
                _editingDraft!,
                widget.operationIndex!,
              ).nameDetails);
    _languageValue = details?.language;
    _communityValue = details?.community;
    _nameRoleValue = details?.role;
    _language.text = _languageValue ?? '';
    _community.text = _communityValue ?? '';
    _nameRole.text = _nameRoleValue ?? '';
    _nameValidity = details?.validity;
    _nameTemporal = details?.temporalValidity;
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
        (_editingDraft == null || _recordOnly
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
    expectedRecordVersion: _base!.expectedRecordVersion,
    name: _name.text,
    nameDetails: EntityNameForm(
      language: _languageValue,
      community: _communityValue,
      role: _nameRoleValue,
      validity: _nameValidity,
      temporalValidity: _nameTemporal,
    ),
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
              qualifiers: a.qualifiers.toList(),
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
      if (!_nameOnly) await _choices();
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
    if (!_classificationOnly) {
      final worlds = await readContextWorlds(
        session: widget.session,
        universe: widget.universe,
        continuity: pinned,
        representedContext: widget.representedContext,
      );
      _worlds = worlds.result.worlds;
      _worldsComplete = worlds.delivery.complete;
    }
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
      if (!_nameOnly) await _choices();
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
          _added = _classificationOnly
              ? 'Classification updated in saved changes. Return to Changes to review it.'
              : _nameOnly
              ? 'Name updated in saved changes. Return to Changes to review it.'
              : 'Entity updated in saved changes. Return to Changes to review it.';
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
      final request = widget.publishedEntity == null
          ? entityDraftRequest(
              universe: Selector(widget.universe.name),
              continuity: widget.scope.continuity,
              form: _form,
              previous: old,
            )
          : _classificationOnly
          ? entityClassificationDraftRequest(
              universe: Selector(widget.universe.name),
              universeId: widget.universe.id,
              continuity: widget.scope.continuity,
              record: widget.publishedEntity!.identity.recordId,
              form: _form,
              previous: old,
            )
          : entityNameDraftRequest(
              universe: Selector(widget.universe.name),
              universeId: widget.universe.id,
              continuity: widget.scope.continuity,
              record: widget.publishedEntity!.identity.recordId,
              form: _form,
              previous: old,
            );
      if (old?.content.toWire().toText() != request.content.toWire().toText()) {
        await widget.session.call(request);
      }
      if (mounted) {
        setState(
          () => _added = _classificationOnly
              ? 'Classification added to saved changes. Review, approve and publish it in Changes.'
              : widget.publishedEntity == null
              ? 'Entity added to saved changes. Review, approve and publish it in Changes.'
              : 'Name added to saved changes. Review, approve and publish it in Changes.',
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
  Widget _nameMetadata(
    TextEditingController controller,
    String label,
    String? value,
    ValueChanged<String?> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: controller,
        enabled: !_disabled,
        decoration: InputDecoration(
          labelText: label,
          helperText: value == null ? 'Not set' : null,
        ),
        onChanged: (value) {
          change(value);
          _changed();
        },
      ),
      TextButton(
        onPressed: _disabled || value == null
            ? null
            : () {
                controller.clear();
                setState(() => change(null));
                _changed();
              },
        child: Text('Clear $label'),
      ),
    ],
  );
  Widget _nameDetailsFields() {
    final original = _originalName?.validity;
    final choice = _nameTemporal != null
        ? 'temporal'
        : switch (_nameValidity) {
            UnspecifiedValidity() => 'unspecified',
            UnknownValidity() => 'unknown',
            ConditionalValidity() => 'conditional',
            _ => 'retain',
          };
    return ExpansionTile(
      title: const Text('Name details (optional)'),
      children: [
        _nameMetadata(
          _language,
          'Language',
          _languageValue,
          (v) => _languageValue = v,
        ),
        _nameMetadata(
          _community,
          'Community',
          _communityValue,
          (v) => _communityValue = v,
        ),
        _nameMetadata(
          _nameRole,
          'Naming role',
          _nameRoleValue,
          (v) => _nameRoleValue = v,
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('name validity', choice)),
          initialValue: choice,
          decoration: const InputDecoration(labelText: 'Name validity'),
          items: [
            for (final entry in {
              'retain': original == null
                  ? 'Unspecified by default'
                  : 'Keep current validity',
              'unspecified': 'Unspecified',
              'unknown': 'Unknown',
              'conditional': 'Conditional',
              'temporal': 'Temporal validity',
            }.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _disabled
              ? null
              : (v) {
                  setState(() {
                    _nameTemporal = v == 'temporal'
                        ? temporalValidityInput(original)
                        : null;
                    _nameValidity = switch (v) {
                      'unspecified' => const UnspecifiedValidity(),
                      'unknown' => const UnknownValidity(),
                      'conditional' => const ConditionalValidity(),
                      _ => null,
                    };
                  });
                  _changed();
                },
        ),
        if (_nameTemporal != null)
          TemporalValidityFields(
            changes: _calendarChanges,
            draft: _calendarChoices,
            key: const ValueKey('name temporal'),
            input: _nameTemporal!,
            originalAmounts: temporalOriginalAmounts(original),
            disabled: _disabled,
            onChanged: (v) {
              setState(() => _nameTemporal = v);
              _changed();
            },
          ),
      ],
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
                changes: _calendarChanges,
                draft: _calendarChoices,
                key: ValueKey(('temporal', fields)),
                input: fields.temporalValidity!,
                originalAmounts: temporalOriginalAmounts(original?.validity),
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
              Column(
                key: ValueKey((fields, q)),
                children: [
                  ValueInputFields(
                    changes: _calendarChanges,
                    draft: _calendarChoices,
                    input: fields.qualifiers[q],
                    original:
                        original?.qualifiers[fields.qualifiers[q].originalKey],
                    disabled: _disabled,
                    named: true,
                    onChanged: (input) {
                      fields.qualifiers[q] = input;
                      _changed();
                    },
                  ),
                  TextButton(
                    onPressed: _disabled
                        ? null
                        : () {
                            setState(() => fields.qualifiers.removeAt(q));
                            _changed();
                          },
                    child: const Text('Remove qualifier'),
                  ),
                ],
              ),
            if (fields.qualifiers.isEmpty) const Text('No qualifiers'),
            TextButton(
              onPressed: _disabled
                  ? null
                  : () {
                      setState(
                        () => fields.qualifiers.add(const QualifierInput()),
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
          _classificationOnly
              ? widget.editingDraft == null
                    ? 'Refine classification'
                    : 'Edit classification in changes'
              : widget.publishedEntity != null
              ? 'Add contextual name'
              : widget.editingDraft == null
              ? 'Person, place or other entity'
              : _nameOnly
              ? 'Edit name in changes'
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
              Text(
                _classificationOnly
                    ? 'Choose a type for an unclassified entity, or a descendant of its current type. Changes preserve its identity and existing facts.'
                    : 'A name is enough to start. Unfinished work stays on this device; adding to Changes does not change canon.',
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
              if (!_classificationOnly) ...[
                _field(_name, 'Name'),
                _nameDetailsFields(),
              ],
              const SizedBox(height: 12),
              if (!_nameOnly)
                DropdownButtonFormField<String>(
                  key: ValueKey(_classification),
                  initialValue: _classification,
                  decoration: InputDecoration(
                    labelText: _classificationOnly
                        ? 'Classification'
                        : 'Classification (optional)',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(
                        _classificationOnly
                            ? 'Choose a classification'
                            : 'Leave unclassified',
                      ),
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
              if (_editingDraft != null && !_classificationOnly) ...[
                const Text('Original name details'),
                Text(
                  _nameOnly
                      ? 'The target identity and expected version are retained. Validity stays unchanged unless you edit it.'
                      : 'Name identity is retained. World and role edits retain validity and qualifiers unless those fields are explicitly changed.',
                ),
                ExactFields(value: _originalName!.toWire()),
              ],
              if (_editingDraft != null && !_recordOnly) ...[
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
              ] else if (!_recordOnly) ...[
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
              if (widget.publishedEntity != null) ...[
                Text(
                  _classificationOnly
                      ? 'Names, world associations and other entity facts are retained.'
                      : 'Existing names remain attached to the same identity.',
                ),
                if (_base?.expectedRecordVersion !=
                    widget.publishedEntity!.recordVersionId)
                  const Text(
                    'Recovered input retains an earlier entity version. Review or rebase it in Changes before publication.',
                  ),
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
                if (widget.editingDraft == null &&
                    widget.publishedEntity == null)
                  TextButton(
                    onPressed: _disabled ? null : _startAnother,
                    child: const Text('Start another entity'),
                  ),
              ],
              FilledButton(
                onPressed: _disabled || _stale ? null : _add,
                child: Text(
                  widget.publishedEntity != null
                      ? _classificationOnly
                            ? 'Add classification to changes'
                            : 'Add name to changes'
                      : widget.editingDraft == null
                      ? 'Add entity to changes'
                      : _classificationOnly
                      ? 'Save classification changes'
                      : _nameOnly
                      ? 'Save name changes'
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
       qualifiers = (form.qualifiers ?? fallback ?? []).toList();
  String world;
  Validity? validity;
  TemporalValidityInput? temporalValidity;
  final int? originalOrdinal;
  final TextEditingController role;
  final List<QualifierInput> qualifiers;
  void dispose() {
    role.dispose();
  }
}
