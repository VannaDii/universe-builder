import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'attribute_draft.dart';
import 'connection.dart';
import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';
import 'record_browser.dart';
import 'evidence_basis_draft.dart';
import 'evidence_basis_fields.dart';
import 'qualifier_draft.dart';
import 'scope_draft.dart';
import 'scope_input_fields.dart';
import 'record_fields.dart';
import 'record_reference_fields.dart';
import 'saved_changes.dart';
import 'value_input_fields.dart';
import 'temporal_validity_draft.dart';
import 'temporal_validity_fields.dart';

class AttributeEditorPage extends StatefulWidget {
  const AttributeEditorPage({
    super.key,
    required this.changes,
    required this.draft,
    required this.index,
  }) : publishedEntity = null,
       openedRevision = null;
  const AttributeEditorPage.create({
    super.key,
    required this.changes,
    required this.draft,
    required this.publishedEntity,
    required this.openedRevision,
  }) : index = null;
  final SavedChanges changes;
  final SavedDraft draft;
  final int? index;
  final RecordVersion? publishedEntity;
  final RevisionId? openedRevision;
  bool get creating => publishedEntity != null;
  @override
  State<AttributeEditorPage> createState() => _AttributeEditorPageState();
}

class _AttributeEditorPageState extends State<AttributeEditorPage> {
  late SavedDraft _draft;
  UnfinishedAttributeForm? _form;
  SavedDraft get _choices => SavedDraft(
    version: BigInt.zero,
    content: DraftContent(
      baseRevision: _form!.baseRevision,
      representedContext: _form!.representedContext,
      operations: [],
      rationale: '',
    ),
  );

  BigInt _generation = BigInt.zero;
  bool _loading = true,
      _saving = false,
      _updating = false,
      _dirty = false,
      _leaving = false,
      _stale = false;
  String? _error, _updated;
  Timer? _autosave;
  SavedDraft? _result;
  late EditorFormScope _scope;
  bool get _added =>
      widget.creating &&
      _form?.creationInput != null &&
      _draft.content.operations.any(
        (op) =>
            op is AssertPropositionOperation &&
            op.clientRef == _form!.creationInput!.operationRef,
      );
  bool get _disabled =>
      _loading || _saving || _updating || _form == null || _added;
  DomainOperation? get _source =>
      widget.creating ? null : _draft.content.operations[widget.index!];
  DomainValue? get _value => _source == null ? null : attributeValue(_source!);
  AttributeEvidence get _evidence => widget.creating
      ? newAttributeEvidence(
          widget.changes.scope.universe,
          _form?.representedContext ?? widget.changes.scope.representedContext!,
        )
      : attributeEvidence(_source!);
  UnfinishedAttributeForm _freshForm() => widget.creating
      ? newAttributeForm(
          draft: _draft,
          entity: widget.publishedEntity!,
          baseRevision: widget.openedRevision,
          representedContext: widget.changes.scope.representedContext,
        )
      : attributeFormFromDraft(_draft, widget.index!);
  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    final scope = widget.changes.scope;
    _scope = EditorFormScope(
      instance: scope.instance,
      profile: scope.profile,
      universe: scope.universe,
      continuity: scope.continuity,
      representedContext: widget.creating
          ? scope.representedContext
          : _draft.content.representedContext,
      attributeClientRef: widget.creating
          ? 'new-attribute:${widget.publishedEntity!.identity.recordId.value}'
          : attributeClientRef(_source!),
    );
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await widget.changes.session.loadAttributeForm(_scope);
      if (!mounted) return;
      final form = saved?.form ?? _freshForm();
      setState(() {
        _form = form;
        _roleGeneration++;
        _generation = saved?.generation ?? BigInt.zero;
        _dirty = false;
        _stale =
            form.draftVersion != _draft.version ||
            form.baseRevision != _draft.content.baseRevision ||
            form.representedContext != _draft.content.representedContext ||
            (widget.creating &&
                (widget.openedRevision != _draft.content.baseRevision ||
                    _scope.representedContext !=
                        _draft.content.representedContext ||
                    form.creationInput?.subject.version !=
                        widget.publishedEntity!.recordVersionId));
      });
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open the saved fields. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change(
    QualifierInput value, {
    AttributeEvidenceInput? evidence,
    AttributeCreationInput? creation,
    List<PropositionRoleInput>? roles,
  }) {
    final old = _form!;
    setState(() {
      _form = UnfinishedAttributeForm(
        baseRevision: old.baseRevision,
        representedContext: old.representedContext,
        clientRef: old.clientRef,
        draftVersion: old.draftVersion,
        value: value,
        evidenceInput: evidence ?? old.evidenceInput,
        creationInput: creation ?? old.creationInput,
        roles: roles ?? old.roles,
      );
      _dirty = true;
      _updated = null;
    });
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 500), _save);
  }

  bool get _relationship =>
      _source != null && isRelationshipAssertion(_source!);
  List<PropositionRoleInput> get _roles =>
      _form!.roles ??
      [
        if (_source
            case AssertPropositionOperation(:final proposition) ||
                RecordRelationOperation(:final proposition))
          for (final r in proposition.roles)
            PropositionRoleInput(
              role: r.role,
              record: r.participant.record.value,
              universe: r.participant.universe?.value ?? '',
            ),
      ];
  Widget _roleFields() => ExpansionTile(
    key: const ValueKey('assertion participants'),
    initiallyExpanded: _relationship,
    title: const Text('Relationship participants'),
    children: [
      const Text(
        'Role order and repeated participants remain explicit. Changing a participant does not transfer ownership or create an event.',
      ),
      for (var i = 0; i < _roles.length; i++)
        Card(
          key: ValueKey((_roleGeneration, i)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  initialValue: _roles[i].role,
                  enabled: !_disabled,
                  decoration: const InputDecoration(labelText: 'Role name'),
                  onChanged: (v) {
                    final rows = [..._roles], r = rows[i];
                    rows[i] = PropositionRoleInput(
                      role: v,
                      record: r.record,
                      universe: r.universe,
                    );
                    _change(_form!.value, roles: rows);
                  },
                ),
                RecordReferenceFields(
                  changes: widget.changes,
                  draft: _choices,
                  record: _roles[i].record,
                  universe: _roles[i].universe,
                  label: 'Participant',
                  disabled: _disabled,
                  onChanged: (record, universe) {
                    final rows = [..._roles], r = rows[i];
                    rows[i] = PropositionRoleInput(
                      role: r.role,
                      record: record,
                      universe: universe,
                    );
                    _change(_form!.value, roles: rows);
                  },
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: _disabled || i == 0
                          ? null
                          : () {
                              final rows = [..._roles], row = rows.removeAt(i);
                              rows.insert(i - 1, row);
                              _roleGeneration++;
                              _change(_form!.value, roles: rows);
                            },
                      child: const Text('Move earlier'),
                    ),
                    TextButton(
                      onPressed: _disabled || i == _roles.length - 1
                          ? null
                          : () {
                              final rows = [..._roles], row = rows.removeAt(i);
                              rows.insert(i + 1, row);
                              _roleGeneration++;
                              _change(_form!.value, roles: rows);
                            },
                      child: const Text('Move later'),
                    ),
                    TextButton(
                      onPressed: _disabled
                          ? null
                          : () {
                              _roleGeneration++;
                              _change(
                                _form!.value,
                                roles: [..._roles]..removeAt(i),
                              );
                            },
                      child: const Text('Remove participant'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      TextButton(
        onPressed: _disabled
            ? null
            : () => _change(
                _form!.value,
                roles: [..._roles, const PropositionRoleInput()],
              ),
        child: const Text('Add participant'),
      ),
    ],
  );
  int _roleGeneration = 0;

  void _editEvidence({
    EvidenceBasisInput? basis,
    AttributeMode? attributeMode,
    ScopeInput? scope,
    Polarity? polarity,
    Precision? precision,
    PersistenceSemantics? persistence,
    String? validityChoice,
    TemporalValidityInput? temporal,
    List<QualifierInput>? alternatives,
  }) {
    final old = _form!.evidenceInput ?? const AttributeEvidenceInput();
    _change(
      _form!.value,
      evidence: AttributeEvidenceInput(
        basis: basis ?? old.basis,
        attributeMode: attributeMode ?? old.attributeMode,
        scope: scope ?? old.scope,
        alternatives: alternatives ?? old.alternatives,
        polarity: polarity ?? old.polarity,
        precision: precision ?? old.precision,
        persistence: persistence ?? old.persistence,
        validity: validityChoice == null
            ? old.validity
            : switch (validityChoice) {
                'unspecified' => const UnspecifiedValidity(),
                'unknown' => const UnknownValidity(),
                'conditional' => const ConditionalValidity(),
                _ => null,
              },
        temporalValidity: validityChoice == null
            ? temporal ?? old.temporalValidity
            : validityChoice == 'temporal'
            ? temporalValidityInput(_evidence.validity)
            : null,
      ),
    );
  }

  List<QualifierInput> get _alternatives =>
      _form!.evidenceInput?.alternatives ??
      [
        for (var i = 0; i < _evidence.alternatives.length; i++)
          qualifierInput(i.toString(), _evidence.alternatives[i]),
      ];
  void _moveAlternative(int index, int destination) {
    final rows = [..._alternatives];
    rows.insert(destination, rows.removeAt(index));
    _editEvidence(alternatives: rows);
  }

  Widget _alternativeFields() {
    final rows = _alternatives;
    final original = qualifierChildren(SequenceValue(_evidence.alternatives));
    return ExpansionTile(
      key: const ValueKey('attribute alternatives'),
      title: const Text('Alternative values'),
      children: [
        const Text(
          'These are authored alternatives, not additional established facts. Precision is selected separately.',
        ),
        if (rows.isEmpty) const Text('No alternatives'),
        for (var i = 0; i < rows.length; i++)
          Column(
            key: ValueKey(('attribute alternative', i)),
            children: [
              ValueInputFields(
                changes: widget.changes,
                draft: _choices,
                input: rows[i],
                original: original[rows[i].originalKey],
                disabled: _disabled,
                label: 'Alternative ${i + 1}',
                onChanged: (value) {
                  final changed = [..._alternatives];
                  changed[i] = value;
                  _editEvidence(alternatives: changed);
                },
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: _disabled || i == 0
                        ? null
                        : () => _moveAlternative(i, i - 1),
                    child: const Text('Move earlier'),
                  ),
                  TextButton(
                    onPressed: _disabled || i == rows.length - 1
                        ? null
                        : () => _moveAlternative(i, i + 1),
                    child: const Text('Move later'),
                  ),
                  TextButton(
                    onPressed: _disabled
                        ? null
                        : () {
                            final changed = [..._alternatives]..removeAt(i);
                            _editEvidence(alternatives: changed);
                          },
                    child: const Text('Remove alternative'),
                  ),
                ],
              ),
            ],
          ),
        TextButton(
          onPressed: _disabled
              ? null
              : () => _editEvidence(
                  alternatives: [..._alternatives, const QualifierInput()],
                ),
          child: const Text('Add alternative'),
        ),
      ],
    );
  }

  Widget _choice<T>(
    String label,
    T value,
    Map<T, String> choices,
    ValueChanged<T> change,
  ) => DropdownButtonFormField<T>(
    key: ValueKey((label, value)),
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final e in choices.entries)
        DropdownMenuItem(value: e.key, child: Text(e.value)),
    ],
    onChanged: _disabled
        ? null
        : (v) {
            if (v != null) change(v);
          },
  );
  Widget _evidenceFields() {
    final input = _form!.evidenceInput;
    final original = _evidence;
    final choice = input?.temporalValidity != null
        ? 'temporal'
        : switch (input?.validity) {
            UnspecifiedValidity() => 'unspecified',
            UnknownValidity() => 'unknown',
            ConditionalValidity() => 'conditional',
            _ => 'retain',
          };
    return ExpansionTile(
      key: const ValueKey('attribute assertion details'),
      title: const Text('Assertion details'),
      children: [
        _choice(
          'Attribute mode',
          input?.attributeMode ?? original.attributeMode,
          const {
            AttributeMode.instance: 'Instance fact',
            AttributeMode.shared: 'Shared attribute',
            AttributeMode.initialValue: 'Initial value',
          },
          (v) => _editEvidence(attributeMode: v),
        ),
        _choice('Polarity', input?.polarity ?? original.polarity, const {
          Polarity.support: 'Supports this fact',
          Polarity.refutation: 'Refutes this fact',
        }, (v) => _editEvidence(polarity: v)),
        _choice('Precision', input?.precision ?? original.precision, const {
          Precision.exact: 'Exact',
          Precision.approximate: 'Approximate',
          Precision.range: 'Range',
          Precision.oneOf: 'One of the authored alternatives',
          Precision.unresolved: 'Unresolved',
        }, (v) => _editEvidence(precision: v)),
        _choice(
          'Persistence',
          input?.persistence ?? original.persistence,
          const {
            PersistenceSemantics.explicitInterval: 'Explicit interval',
            PersistenceSemantics.persistentUntilChanged:
                'Persistent until changed',
            PersistenceSemantics.instantaneousObservation:
                'Instantaneous observation',
            PersistenceSemantics.conditionDependent: 'Condition dependent',
            PersistenceSemantics.unspecified: 'Unspecified',
          },
          (v) => _editEvidence(persistence: v),
        ),
        _choice('Validity', choice, const {
          'retain': 'Keep current validity',
          'unspecified': 'Unspecified',
          'unknown': 'Unknown',
          'conditional': 'Conditional',
          'temporal': 'Temporal validity',
        }, (v) => _editEvidence(validityChoice: v)),
        if (input?.temporalValidity != null)
          TemporalValidityFields(
            changes: widget.changes,
            draft: _choices,
            key: const ValueKey('attribute temporal'),
            input: input!.temporalValidity!,
            originalAmounts: temporalOriginalAmounts(original.validity),
            disabled: _disabled,
            onChanged: (v) => _editEvidence(temporal: v),
          ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_dirty || _saving || _form == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.changes.session.saveAttributeForm(
        _scope,
        _form!,
        _generation,
      );
      if (mounted) {
        setState(() {
          _form = saved.form;
          _generation = saved.generation;
          _dirty = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not save these fields. Another window may have changed them. Your input remains here.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _useCurrent() async {
    _autosave?.cancel();
    try {
      if (widget.creating) {
        final latest = await widget.changes.load();
        if (latest != null) _draft = latest;
        if (_draft.content.baseRevision != widget.openedRevision ||
            _draft.content.representedContext != _scope.representedContext ||
            _draft.content.proposal != null) {
          throw const FormatException(
            'Review Changes and reopen the dossier at its current revision.',
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _form = _freshForm();
        _roleGeneration++;
        _stale = false;
        _dirty = true;
        _updated = null;
      });
      await _save();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not open the current draft. Retry when connected.',
        );
      }
    }
  }

  Future<void> _update() async {
    _autosave?.cancel();
    await _save();
    if (!mounted || _dirty || _form == null || _stale) return;
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      final DraftContent content;
      SavedDraft current = _draft;
      if (widget.creating) {
        current = await widget.changes.load() ?? _draft;
        _draft = current;
        final creation = _form!.creationInput!;
        final context = await openDraftChoiceContext(widget.changes, current);
        if (creation.propertyUniverse != widget.changes.scope.universe.value) {
          throw const FormatException(
            'Choose an existing property in this universe.',
          );
        }
        final property = await readContextRecord(
          session: widget.changes.session,
          universe: LibraryEntry(
            widget.changes.scope.universe,
            widget.changes.universe.value,
          ),
          context: context,
          record: RecordId.parse(creation.propertyRecord),
        );
        final entity = await readContextRecord(
          session: widget.changes.session,
          universe: LibraryEntry(
            widget.changes.scope.universe,
            widget.changes.universe.value,
          ),
          context: context,
          record: creation.subject.record,
        );
        content = appendDraftAttribute(
          draft: current,
          form: _form!,
          entity: entity,
          property: property,
        );
      } else {
        content = replaceDraftAttribute(
          draft: current,
          index: widget.index!,
          form: _form!,
        );
      }
      final saved =
          content.toWire().toText() == current.content.toWire().toText()
          ? current
          : await widget.changes.saveContent(current, content);
      if (!mounted) return;
      setState(() {
        _draft = saved;
        _result = saved;
        _roleGeneration++;
        _form = widget.creating
            ? UnfinishedAttributeForm(
                baseRevision: _form!.baseRevision,
                representedContext: _form!.representedContext,
                clientRef: _form!.clientRef,
                draftVersion: saved.version,
                value: _form!.value,
                evidenceInput: _form!.evidenceInput,
                creationInput: _form!.creationInput,
              )
            : attributeFormFromDraft(saved, widget.index!);
        _dirty = true;
        _stale = false;
        _updated = _relationship
            ? 'Relationship assertion saved in Changes. Return to Changes to review it.'
            : 'Attribute saved in Changes. Return to Changes to review it.';
      });
      await _save();
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          if (widget.creating) {
            _stale =
                _form!.draftVersion != _draft.version ||
                _form!.baseRevision != _draft.content.baseRevision ||
                _form!.representedContext != _draft.content.representedContext;
          }
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm saving the attribute. Your entered fields remain saved. Check Changes before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _leave() async {
    if (_loading || _saving || _updating) return;
    _autosave?.cancel();
    await _save();
    if (!mounted || _dirty || _saving) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(_result);
  }

  @override
  Widget build(BuildContext context) => PopScope<SavedDraft>(
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.creating
              ? 'Add factual attribute'
              : _relationship
              ? 'Edit relationship assertion'
              : 'Edit attribute',
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(switch (_source) {
                  AddNamedAttributeOperation(:final namespace, :final key) =>
                    '$namespace: $key',
                  _ =>
                    _relationship
                        ? 'Relationship assertion'
                        : 'Factual attribute',
                }, style: Theme.of(context).textTheme.titleLarge),
                Text(
                  _relationship
                      ? 'Unfinished edits stay on this device. The relation definition and subject remain intact. Save into Changes for review before publication.'
                      : 'Unfinished edits stay on this device. The property definition remains intact. Assertion details change only when edited. Save into Changes for review before publication.',
                ),
                if (_loading || _saving || _updating)
                  const LinearProgressIndicator(),
                if (_stale) ...[
                  const Text(
                    'Recovered edits belong to an earlier draft. Use current draft fields before saving changes.',
                  ),
                  TextButton(
                    onPressed: _disabled ? null : _useCurrent,
                    child: const Text('Use current draft fields'),
                  ),
                ],
                if (widget.creating && _form?.creationInput != null)
                  DraftRecordChoiceField(
                    changes: widget.changes,
                    draft: _draft,
                    kind: RecordKind.property,
                    label: 'Property',
                    record: _form!.creationInput!.propertyRecord,
                    universe: _form!.creationInput!.propertyUniverse,
                    disabled: _disabled,
                    onChanged: (ref) {
                      final creation = _form!.creationInput!;
                      _change(
                        _form!.value,
                        creation: AttributeCreationInput(
                          subject: creation.subject,
                          operationRef: creation.operationRef,
                          propertyRecord: ref.record.value,
                          propertyUniverse: ref.universe!.value,
                        ),
                      );
                    },
                  ),
                if (_form != null && (widget.creating || _value != null))
                  ValueInputFields(
                    changes: widget.changes,
                    draft: _choices,
                    key: const ValueKey('attribute value'),
                    input: _form!.value,
                    original: _value,
                    disabled: _disabled,
                    label: 'Attribute value',
                    onChanged: _change,
                  ),
                if (_form != null) ...[
                  if (_source is AssertPropositionOperation ||
                      _source is RecordRelationOperation)
                    _roleFields(),
                  _evidenceFields(),
                  ExpansionTile(
                    key: const ValueKey('attribute factual scope'),
                    title: const Text('Factual scope'),
                    children: [
                      ScopeInputFields(
                        changes: widget.changes,
                        draft: _draft,
                        input:
                            _form!.evidenceInput?.scope ??
                            scopeInput(_evidence.scope),
                        disabled: _disabled,
                        onChanged: (v) => _editEvidence(scope: v),
                      ),
                    ],
                  ),
                  _alternativeFields(),
                  ExpansionTile(
                    key: const ValueKey('attribute source basis'),
                    title: const Text('Source basis'),
                    children: [
                      EvidenceBasisFields(
                        changes: widget.changes,
                        draft: _draft,
                        input:
                            _form!.evidenceInput?.basis ??
                            evidenceBasisInput(_evidence.basis),
                        original: _evidence.basis,
                        disabled: _disabled,
                        onChanged: (v) => _editEvidence(basis: v),
                      ),
                    ],
                  ),
                ],
                if (_source != null)
                  ExpansionTile(
                    key: const ValueKey('original attribute'),
                    title: const Text('Original attribute and evidence'),
                    children: [ExactFields(value: _source!.toWire())],
                  ),
                Text(
                  _dirty
                      ? 'Unsaved fields'
                      : _generation == BigInt.zero
                      ? 'No saved fields yet'
                      : 'Saved on this device',
                ),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (_updated != null)
                  Semantics(liveRegion: true, child: Text(_updated!)),
                FilledButton(
                  onPressed: _disabled || _stale ? null : _update,
                  child: Text(
                    widget.creating
                        ? 'Add to Changes'
                        : _relationship
                        ? 'Save relationship changes'
                        : 'Save attribute changes',
                  ),
                ),
                if (_added) ...[
                  const Text(
                    'This fact is in Changes. Review or edit it there before publication.',
                  ),
                  TextButton(
                    onPressed: _loading || _saving || _updating
                        ? null
                        : _useCurrent,
                    child: const Text('Start another attribute'),
                  ),
                ],
                TextButton(
                  onPressed: _disabled || !_dirty ? null : _save,
                  child: const Text('Save unfinished work'),
                ),
                if (_error != null)
                  TextButton(
                    onPressed: _loading || _saving || _updating ? null : _load,
                    child: const Text('Reload saved fields'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
