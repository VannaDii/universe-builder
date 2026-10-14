import 'dart:async';

import 'guarded_pop_scope.dart';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'event_draft.dart';
import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';
import 'record_fields.dart';
import 'draft_record_choices.dart';
import 'scope_input_fields.dart';
import 'expression_input_fields.dart';
import 'expression_draft.dart';

class EventEditorPage extends StatefulWidget {
  const EventEditorPage({
    super.key,
    required this.changes,
    required this.revision,
    this.editingDraft,
    this.index,
    this.revisionRecord,
  });
  final SavedChanges changes;
  final RevisionId revision;
  final SavedDraft? editingDraft;
  final int? index;
  final RecordVersion? revisionRecord;
  @override
  State<EventEditorPage> createState() => _EventEditorPageState();
}

class _EventEditorPageState extends State<EventEditorPage> {
  UnfinishedEventForm? _form;
  SavedDraft? _draft, _result;
  BigInt _generation = BigInt.zero;
  bool _loading = true,
      _saving = false,
      _adding = false,
      _dirty = false,
      _stale = false,
      _leaving = false;
  String? _error, _added;
  Timer? _autosave;
  int _fields = 0;
  List<WorldSummary> _worlds = [];
  bool _worldsComplete = false;
  bool get _disabled =>
      _loading || _saving || _adding || _form == null || _added != null;
  EditorFormScope get _scope => widget.changes.scope;
  SavedDraft get _choices => SavedDraft(
    version: BigInt.zero,
    content: DraftContent(
      baseRevision: _form!.baseRevision,
      representedContext: _form!.representedContext,
      operations: [],
      rationale: '',
    ),
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    super.dispose();
  }

  UnfinishedEventForm _fresh() => widget.index != null
      ? eventFormFromDraft(_draft!, widget.index!)
      : widget.revisionRecord != null
      ? eventRevisionFormFromRecord(
          record: widget.revisionRecord!,
          baseRevision: widget.revision,
          representedContext: _scope.representedContext!,
        )
      : UnfinishedEventForm(
          baseRevision: widget.revision,
          representedContext: _scope.representedContext!,
          clientRef: RecordId.generate().value,
        );
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _draft = widget.editingDraft ?? await widget.changes.load();
      final saved = await widget.changes.session.loadEventForm(_scope);
      if (!mounted) return;
      setState(() {
        _form = saved?.form ?? _fresh();
        _generation = saved?.generation ?? BigInt.zero;
        _fields++;
        _dirty = false;
        _stale = widget.index != null
            ? _form!.draftVersion != _draft!.version ||
                  _form!.baseRevision != _draft!.content.baseRevision ||
                  _form!.representedContext !=
                      _draft!.content.representedContext
            : _form!.baseRevision != widget.revision ||
                  (widget.revisionRecord != null &&
                      _form!.expectedRecordVersion !=
                          widget.revisionRecord!.recordVersionId);
        _added =
            widget.index == null &&
                (_draft?.content.operations.any(
                      (op) =>
                          (op is RecordEventOperation &&
                              _form!.revisionTarget == null &&
                              op.clientRef == _form!.clientRef) ||
                          (op is ReviseEventOperation &&
                              _form!.revisionTarget?.record ==
                                  op.record.record.value &&
                              _form!.revisionTarget?.universe ==
                                  (op.record.universe?.value ?? '')),
                    ) ??
                    false)
            ? 'This definition is in Changes. Review or edit it there.'
            : null;
      });
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not open the event form. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadWorlds() async {
    final opened = await openDraftChoiceContext(widget.changes, _choices);
    final worlds = Envelope<Description>.fromWire(
      await widget.changes.session.call(
        ToolEngineRequest(
          request: DescribeWorldsRequest(
            universe: widget.changes.universe,
            universeId: _scope.universe,
            contextId: opened.contextId,
          ),
        ),
      ),
      Description.fromWire,
    );
    if (mounted) {
      setState(() {
        _worlds = worlds.result.worlds;
        _worldsComplete = worlds.delivery.complete;
      });
    }
  }

  List<EventEffectInput> get _effects =>
      _form?.effects ??
      _form?.original?.effects.map(eventEffectInput).toList() ??
      const [];
  List<ExpressionInput> get _conditions =>
      _form?.preconditions ??
      _form?.original?.preconditions.map(expressionInput).toList() ??
      const [];
  bool get _inputDisabled =>
      _loading || _adding || _form == null || _added != null;
  void _change({
    String? label,
    String? occurrence,
    String? description,
    String? actionRecord,
    String? actionUniverse,
    TemporalValidityInput? time,
    List<EventParticipantInput>? participants,
    List<EventEffectInput>? effects,
    List<ExpressionInput>? preconditions,
    String? rationale,
    List<String>? worlds,
    String? regionRecord,
    String? regionUniverse,
    String? sequence,
    String? occurrenceId,
  }) {
    final f = _form!;
    setState(() {
      _form = UnfinishedEventForm(
        baseRevision: f.baseRevision,
        representedContext: f.representedContext,
        clientRef: f.clientRef,
        label: label ?? f.label,
        occurrence: occurrence ?? f.occurrence,
        description: description ?? f.description,
        actionRecord: actionRecord ?? f.actionRecord,
        actionUniverse: actionUniverse ?? f.actionUniverse,
        time: time ?? f.time,
        participants: participants ?? f.participants,
        effects: effects ?? f.effects,
        preconditions: preconditions ?? f.preconditions,
        rationale: rationale ?? f.rationale,
        original: f.original,
        worlds: worlds ?? f.worlds,
        regionRecord: regionRecord ?? f.regionRecord,
        regionUniverse: regionUniverse ?? f.regionUniverse,
        sequence: sequence ?? f.sequence,
        occurrenceId: occurrenceId ?? f.occurrenceId,
        draftVersion: f.draftVersion,
        revisionTarget: f.revisionTarget,
        expectedRecordVersion: f.expectedRecordVersion,
      );
      _dirty = true;
    });
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 500), _save);
  }

  void _participant(int index, {RecordRef? reference, String? role}) {
    final rows = [..._form!.participants], old = rows[index];
    rows[index] = EventParticipantInput(
      record: reference?.record.value ?? old.record,
      universe: reference == null
          ? old.universe
          : reference.universe?.value ?? '',
      role: role ?? old.role,
    );
    _change(participants: rows);
  }

  void _moveParticipant(int index, int destination) {
    final rows = [..._form!.participants], row = rows.removeAt(index);
    rows.insert(destination, row);
    _fields++;
    _change(participants: rows);
  }

  void _effect(
    int index, {
    String? slot,
    RecordRef? proposition,
    String? polarity,
    String? order,
    ScopeInput? scope,
    TemporalValidityInput? validity,
  }) {
    final rows = [..._effects], old = rows[index];
    rows[index] = EventEffectInput(
      slot: slot ?? old.slot,
      propositionRecord: proposition?.record.value ?? old.propositionRecord,
      propositionUniverse: proposition == null
          ? old.propositionUniverse
          : proposition.universe?.value ?? '',
      polarity: polarity ?? old.polarity,
      order: order ?? old.order,
      scope: scope ?? old.scope,
      validity: validity ?? old.validity,
      original: old.original,
    );
    _change(effects: rows);
  }

  void _moveEffect(int index, int destination) {
    final rows = [..._effects], row = rows.removeAt(index);
    rows.insert(destination, row);
    _fields++;
    _change(effects: rows);
  }

  Future<void> _save() async {
    if (!_dirty || _saving || _form == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final input = _form!;
      final saved = await widget.changes.session.saveEventForm(
        _scope,
        input,
        _generation,
      );
      if (mounted) {
        setState(() {
          _generation = saved.generation;
          _dirty = _form != input;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not save these fields. Your input remains here; another window may have changed it.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
      if (mounted && _dirty && _error == null) {
        _autosave?.cancel();
        _autosave = Timer(const Duration(milliseconds: 500), _save);
      }
    }
  }

  Future<void> _reset() async {
    _autosave?.cancel();
    setState(() {
      _form = _fresh();
      _fields++;
      _dirty = true;
      _stale = false;
      _added = null;
    });
    await _save();
    await _loadWorlds();
  }

  Future<void> _add() async {
    _autosave?.cancel();
    await _save();
    if (!mounted || _dirty || _stale) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      final draft = widget.index == null ? await widget.changes.load() : _draft;
      final base = draft ?? _choices;
      final request = eventDraftRequest(
        draft: base,
        form: _form!,
        universe: widget.changes.universe,
        continuity: _scope.continuity,
        index: widget.index,
      );
      final saved =
          request.content.toWire().toText() == base.content.toWire().toText()
          ? base
          : SavedDraft.fromWire(await widget.changes.session.call(request));
      if (!mounted) return;
      setState(() {
        _draft = saved;
        _result = saved;
        if (widget.index != null || _form!.revisionTarget != null) {
          final index =
              widget.index ??
              saved.content.operations.indexWhere(
                (op) =>
                    op is ReviseEventOperation &&
                    op.record == eventRevisionOperation(_form!).record,
              );
          _form = eventFormFromDraft(saved, index);
          _fields++;
          _dirty = true;
        } else {
          _added = 'Event added to Changes. Review it before publication.';
        }
      });
      await _save();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm saving the event. Check Changes before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _leave() async {
    if (_loading || _saving || _adding) return;
    _autosave?.cancel();
    await _save();
    if (!mounted || _dirty) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(_result);
  }

  Widget _text(
    String key,
    String label,
    String value,
    ValueChanged<String> change, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      key: ValueKey((_fields, key)),
      initialValue: value,
      enabled: !_inputDisabled,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      onChanged: change,
    ),
  );
  @override
  Widget build(BuildContext context) => GuardedPopScope<SavedDraft>(
    onLeave: _leave,
    onBackground: _save,
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.index == null ? 'Event' : 'Edit event'),
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
                const Text(
                  'Declare what occurred, was planned or was reported, when, and who participated. Publication uses Changes; storing a plan or report does not make it an occurrence.',
                ),
                if (_loading || _saving || _adding)
                  const LinearProgressIndicator(),
                if (_stale) ...[
                  const Text(
                    'Recovered fields belong to an earlier draft or revision.',
                  ),
                  TextButton(
                    onPressed: _disabled ? null : _reset,
                    child: const Text('Use current draft fields'),
                  ),
                ],
                if (_form case final f?) ...[
                  if (f.revisionTarget != null)
                    const Text(
                      'Revising this event retains its record and version reference. Review occurrence, time, participants and declared effects explicitly. Publication preserves history; the service checks the action contract and regenerates effects.',
                    ),
                  _text(
                    'label',
                    'Event label',
                    f.label,
                    (v) => _change(label: v),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey((_fields, 'occurrence')),
                    initialValue: f.occurrence.isEmpty ? null : f.occurrence,
                    decoration: const InputDecoration(
                      labelText: 'Occurrence status',
                    ),
                    items: [
                      for (final kind in OccurrenceKind.values)
                        DropdownMenuItem(
                          value: kind.name,
                          child: Text(kind.name),
                        ),
                      const DropdownMenuItem(
                        value: 'descriptive',
                        child: Text('Descriptive'),
                      ),
                    ],
                    onChanged: _inputDisabled
                        ? null
                        : (v) {
                            if (v != null) _change(occurrence: v);
                          },
                  ),
                  if (f.occurrence == 'descriptive')
                    _text(
                      'description',
                      'Descriptive status',
                      f.description,
                      (v) => _change(description: v),
                    ),
                  DraftRecordChoiceField(
                    changes: widget.changes,
                    draft: _choices,
                    kind: RecordKind.actionDefinition,
                    label: 'Declared action',
                    record: f.actionRecord,
                    universe: f.actionUniverse,
                    disabled: _inputDisabled,
                    onChanged: (ref) => _change(
                      actionRecord: ref.record.value,
                      actionUniverse: ref.universe?.value ?? '',
                    ),
                  ),
                  TemporalValidityFields(
                    key: ValueKey((_fields, 'time')),
                    input: f.time,
                    changes: widget.changes,
                    draft: _choices,
                    disabled: _inputDisabled,
                    expressionOnly: true,
                    originalAmounts: temporalOriginalAmounts(
                      f.original == null
                          ? null
                          : InstantValidity(f.original!.time),
                    ),
                    onChanged: (time) => _change(time: time),
                  ),
                  const Text('Declared worlds'),
                  if (!_worldsComplete)
                    const Text('Only part of the world list was returned.'),
                  for (final world in _worlds)
                    CheckboxListTile(
                      title: Text(world.name.value),
                      value: f.worlds.contains(world.id.value),
                      onChanged: _inputDisabled
                          ? null
                          : (selected) {
                              final worlds = [...f.worlds];
                              if (selected == true) {
                                worlds.add(world.id.value);
                              } else {
                                worlds.remove(world.id.value);
                              }
                              _change(worlds: worlds);
                            },
                    ),
                  for (final id in f.worlds.where(
                    (id) => !_worlds.any((w) => w.id.value == id),
                  ))
                    ListTile(
                      title: Text('Unavailable world name ($id)'),
                      trailing: TextButton(
                        onPressed: _inputDisabled
                            ? null
                            : () => _change(worlds: [...f.worlds]..remove(id)),
                        child: const Text('Remove'),
                      ),
                    ),
                  DraftRecordChoiceField(
                    changes: widget.changes,
                    draft: _choices,
                    kind: null,
                    label: 'Declared region',
                    record: f.regionRecord,
                    universe: f.regionUniverse,
                    disabled: _inputDisabled,
                    onChanged: (ref) => _change(
                      regionRecord: ref.record.value,
                      regionUniverse: ref.universe?.value ?? '',
                    ),
                  ),
                  if (f.regionRecord.isNotEmpty)
                    TextButton(
                      onPressed: _inputDisabled
                          ? null
                          : () => _change(regionRecord: '', regionUniverse: ''),
                      child: const Text('Clear region'),
                    ),
                  _text(
                    'sequence',
                    'Authored sequence',
                    f.sequence,
                    (v) => _change(sequence: v),
                  ),
                  _text(
                    'occurrence-id',
                    'Authored occurrence identity',
                    f.occurrenceId,
                    (v) => _change(occurrenceId: v),
                  ),
                  const Text('Participants in authored order'),
                  for (var i = 0; i < f.participants.length; i++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            _text(
                              'role-$i',
                              'Role',
                              f.participants[i].role,
                              (v) => _participant(i, role: v),
                            ),
                            DraftRecordChoiceField(
                              key: ValueKey((_fields, i)),
                              changes: widget.changes,
                              draft: _choices,
                              kind: null,
                              label: 'Participant ${i + 1}',
                              record: f.participants[i].record,
                              universe: f.participants[i].universe,
                              disabled: _inputDisabled,
                              onChanged: (ref) =>
                                  _participant(i, reference: ref),
                            ),
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: _inputDisabled || i == 0
                                      ? null
                                      : () => _moveParticipant(i, i - 1),
                                  child: const Text('Move earlier'),
                                ),
                                TextButton(
                                  onPressed:
                                      _inputDisabled ||
                                          i == f.participants.length - 1
                                      ? null
                                      : () => _moveParticipant(i, i + 1),
                                  child: const Text('Move later'),
                                ),
                                TextButton(
                                  onPressed: _inputDisabled
                                      ? null
                                      : () {
                                          _fields++;
                                          _change(
                                            participants: [...f.participants]
                                              ..removeAt(i),
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
                    onPressed: _inputDisabled
                        ? null
                        : () => _change(
                            participants: [
                              ...f.participants,
                              const EventParticipantInput(),
                            ],
                          ),
                    child: const Text('Add participant'),
                  ),
                  const Text('Declared preconditions'),
                  const Text(
                    'The service evaluates these conditions in the reviewed context. Unresolved or unsupported results remain explicit.',
                  ),
                  for (var i = 0; i < _conditions.length; i++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            ExpressionInputFields(
                              key: ValueKey((_fields, 'condition', i)),
                              input: _conditions[i],
                              changes: widget.changes,
                              draft: _choices,
                              disabled: _inputDisabled,
                              onChanged: (condition) {
                                final rows = [..._conditions];
                                rows[i] = condition;
                                _change(preconditions: rows);
                              },
                            ),
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: _inputDisabled || i == 0
                                      ? null
                                      : () {
                                          final rows = [..._conditions],
                                              item = rows.removeAt(i);
                                          rows.insert(i - 1, item);
                                          _fields++;
                                          _change(preconditions: rows);
                                        },
                                  child: const Text('Move earlier'),
                                ),
                                TextButton(
                                  onPressed:
                                      _inputDisabled ||
                                          i == _conditions.length - 1
                                      ? null
                                      : () {
                                          final rows = [..._conditions],
                                              item = rows.removeAt(i);
                                          rows.insert(i + 1, item);
                                          _fields++;
                                          _change(preconditions: rows);
                                        },
                                  child: const Text('Move later'),
                                ),
                                TextButton(
                                  onPressed: _inputDisabled
                                      ? null
                                      : () {
                                          _fields++;
                                          _change(
                                            preconditions: [..._conditions]
                                              ..removeAt(i),
                                          );
                                        },
                                  child: const Text('Remove precondition'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: _inputDisabled
                        ? null
                        : () => _change(
                            preconditions: [..._conditions, ExpressionInput()],
                          ),
                    child: const Text('Add precondition'),
                  ),
                  const Text('Declared effects'),
                  const Text(
                    'Effect slots and execution order must match the declared action contract. List position does not replace execution order.',
                  ),
                  for (var i = 0; i < _effects.length; i++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            _text(
                              'effect-slot-$i',
                              'Contract slot',
                              _effects[i].slot,
                              (v) => _effect(i, slot: v),
                            ),
                            DraftRecordChoiceField(
                              key: ValueKey((_fields, 'effect', i)),
                              changes: widget.changes,
                              draft: _choices,
                              kind: RecordKind.proposition,
                              label: 'Effect proposition',
                              record: _effects[i].propositionRecord,
                              universe: _effects[i].propositionUniverse,
                              disabled: _inputDisabled,
                              onChanged: (ref) => _effect(i, proposition: ref),
                            ),
                            DropdownButtonFormField<String>(
                              key: ValueKey((_fields, 'effect-polarity', i)),
                              initialValue: _effects[i].polarity.isEmpty
                                  ? null
                                  : _effects[i].polarity,
                              decoration: const InputDecoration(
                                labelText: 'Effect polarity',
                              ),
                              items: [
                                for (final polarity in Polarity.values)
                                  DropdownMenuItem(
                                    value: polarity.wireName,
                                    child: Text(polarity.wireName),
                                  ),
                              ],
                              onChanged: _inputDisabled
                                  ? null
                                  : (v) {
                                      if (v != null) _effect(i, polarity: v);
                                    },
                            ),
                            _text(
                              'effect-order-$i',
                              'Execution order',
                              _effects[i].order,
                              (v) => _effect(i, order: v),
                            ),
                            ExpansionTile(
                              title: const Text('Effect scope'),
                              children: [
                                ScopeInputFields(
                                  key: ValueKey((_fields, 'effect-scope', i)),
                                  input: _effects[i].scope,
                                  changes: widget.changes,
                                  draft: _choices,
                                  disabled: _inputDisabled,
                                  onChanged: (scope) =>
                                      _effect(i, scope: scope),
                                ),
                              ],
                            ),
                            DropdownButtonFormField<String>(
                              key: ValueKey((
                                _fields,
                                'effect-validity-kind',
                                i,
                              )),
                              initialValue:
                                  {
                                    'unknown',
                                    'unspecified',
                                    'retain',
                                    'condition_dependent',
                                  }.contains(_effects[i].validity.kind)
                                  ? _effects[i].validity.kind
                                  : 'temporal',
                              decoration: const InputDecoration(
                                labelText: 'Validity',
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: 'unspecified',
                                  child: Text('Unspecified'),
                                ),
                                const DropdownMenuItem(
                                  value: 'unknown',
                                  child: Text('Unknown'),
                                ),
                                const DropdownMenuItem(
                                  value: 'condition_dependent',
                                  child: Text('Condition dependent'),
                                ),
                                const DropdownMenuItem(
                                  value: 'temporal',
                                  child: Text('Temporal validity'),
                                ),
                                if (_effects[i].original != null)
                                  const DropdownMenuItem(
                                    value: 'retain',
                                    child: Text('Keep current validity'),
                                  ),
                              ],
                              onChanged: _inputDisabled
                                  ? null
                                  : (v) {
                                      if (v != null) {
                                        _fields++;
                                        _effect(
                                          i,
                                          validity: v == 'temporal'
                                              ? const TemporalValidityInput()
                                              : TemporalValidityInput(kind: v),
                                        );
                                      }
                                    },
                            ),
                            if (!{
                              'unknown',
                              'unspecified',
                              'retain',
                              'condition_dependent',
                            }.contains(_effects[i].validity.kind))
                              ExpansionTile(
                                title: const Text('Effect validity'),
                                children: [
                                  TemporalValidityFields(
                                    key: ValueKey((
                                      _fields,
                                      'effect-validity',
                                      i,
                                    )),
                                    input: _effects[i].validity,
                                    originalAmounts: temporalOriginalAmounts(
                                      _effects[i].original?.validity,
                                    ),
                                    changes: widget.changes,
                                    draft: _choices,
                                    disabled: _inputDisabled,
                                    onChanged: (validity) =>
                                        _effect(i, validity: validity),
                                  ),
                                ],
                              ),
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: _inputDisabled || i == 0
                                      ? null
                                      : () => _moveEffect(i, i - 1),
                                  child: const Text('Move earlier'),
                                ),
                                TextButton(
                                  onPressed:
                                      _inputDisabled || i == _effects.length - 1
                                      ? null
                                      : () => _moveEffect(i, i + 1),
                                  child: const Text('Move later'),
                                ),
                                TextButton(
                                  onPressed: _inputDisabled
                                      ? null
                                      : () {
                                          _fields++;
                                          _change(
                                            effects: [..._effects]..removeAt(i),
                                          );
                                        },
                                  child: const Text('Remove effect'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: _inputDisabled
                        ? null
                        : () => _change(
                            effects: [
                              ..._effects,
                              EventEffectInput(
                                scope: ScopeInput(
                                  contextRecord: f.representedContext.value,
                                  contextUniverse: _scope.universe.value,
                                ),
                              ),
                            ],
                          ),
                    child: const Text('Add declared effect'),
                  ),
                  if (f.original != null)
                    ExpansionTile(
                      title: const Text('Retained event declarations'),
                      children: [ExactFields(value: f.original!.toWire())],
                    ),
                  if (widget.index == null)
                    _text(
                      'rationale',
                      'Rationale',
                      f.rationale,
                      (v) => _change(rationale: v),
                      maxLines: 3,
                    ),
                  Text(
                    _dirty
                        ? 'Unsaved fields'
                        : _generation == BigInt.zero
                        ? 'No saved fields yet'
                        : 'Saved on this device',
                  ),
                  FilledButton(
                    onPressed: _disabled || _stale ? null : _add,
                    child: Text(
                      widget.index == null
                          ? 'Add to Changes'
                          : 'Save event changes',
                    ),
                  ),
                  TextButton(
                    onPressed: _loading || _saving || _adding || !_dirty
                        ? null
                        : _save,
                    child: const Text('Save unfinished work'),
                  ),
                  if (_added != null)
                    TextButton(
                      onPressed: _loading || _saving || _adding ? null : _reset,
                      child: const Text('Start another event'),
                    ),
                  TextButton(
                    onPressed: _loading || _saving || _adding
                        ? null
                        : () async {
                            _autosave?.cancel();
                            await _save();
                            if (!context.mounted || _dirty) return;
                            await Navigator.of(context)
                                .push<void>(changesRoute(widget.changes));
                          },
                    child: const Text('Review Changes'),
                  ),
                ],
                if (_added != null)
                  Semantics(liveRegion: true, child: Text(_added!)),
                if (_error != null) ...[
                  Semantics(liveRegion: true, child: Text(_error!)),
                  TextButton(
                    onPressed: _loading || _saving || _adding ? null : _load,
                    child: const Text('Reload saved fields'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
