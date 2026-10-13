import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'attribute_draft.dart';
import 'evidence_basis_draft.dart';
import 'evidence_basis_fields.dart';
import 'qualifier_draft.dart';
import 'scope_draft.dart';
import 'scope_input_fields.dart';
import 'record_fields.dart';
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
  });
  final SavedChanges changes;
  final SavedDraft draft;
  final int index;
  @override
  State<AttributeEditorPage> createState() => _AttributeEditorPageState();
}

class _AttributeEditorPageState extends State<AttributeEditorPage> {
  late SavedDraft _draft;
  UnfinishedAttributeForm? _form;
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
  bool get _disabled => _loading || _saving || _updating || _form == null;
  AddNamedAttributeOperation get _source =>
      _draft.content.operations[widget.index] as AddNamedAttributeOperation;
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
      representedContext: _draft.content.representedContext,
      attributeClientRef: _source.clientRef,
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
      final form = saved?.form ?? attributeFormFromDraft(_draft, widget.index);
      setState(() {
        _form = form;
        _generation = saved?.generation ?? BigInt.zero;
        _dirty = false;
        _stale =
            form.draftVersion != _draft.version ||
            form.baseRevision != _draft.content.baseRevision ||
            form.representedContext != _draft.content.representedContext;
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

  void _change(QualifierInput value, {AttributeEvidenceInput? evidence}) {
    final old = _form!;
    setState(() {
      _form = UnfinishedAttributeForm(
        baseRevision: old.baseRevision,
        representedContext: old.representedContext,
        clientRef: old.clientRef,
        draftVersion: old.draftVersion,
        value: value,
        evidenceInput: evidence ?? old.evidenceInput,
      );
      _dirty = true;
      _updated = null;
    });
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 500), _save);
  }

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
            ? temporalValidityInput(_source.evidence.validity)
            : null,
      ),
    );
  }

  List<QualifierInput> get _alternatives =>
      _form!.evidenceInput?.alternatives ??
      [
        for (var i = 0; i < _source.evidence.alternatives.length; i++)
          qualifierInput(i.toString(), _source.evidence.alternatives[i]),
      ];
  void _moveAlternative(int index, int destination) {
    final rows = [..._alternatives];
    rows.insert(destination, rows.removeAt(index));
    _editEvidence(alternatives: rows);
  }

  Widget _alternativeFields() {
    final rows = _alternatives;
    final original = qualifierChildren(
      SequenceValue(_source.evidence.alternatives),
    );
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
    final original = _source.evidence;
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
    setState(() {
      _form = attributeFormFromDraft(_draft, widget.index);
      _stale = false;
      _dirty = true;
      _updated = null;
    });
    await _save();
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
      final content = replaceDraftAttribute(
        draft: _draft,
        index: widget.index,
        form: _form!,
      );
      final saved = await widget.changes.saveContent(_draft, content);
      if (!mounted) return;
      setState(() {
        _draft = saved;
        _result = saved;
        _form = attributeFormFromDraft(saved, widget.index);
        _dirty = true;
        _updated = 'Attribute updated in saved changes. Return to Changes to review it.';
      });
      await _save();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
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
      appBar: AppBar(title: const Text('Edit attribute')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_source.namespace}: ${_source.key}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Unfinished edits stay on this device. The property definition remains intact. Assertion details change only when edited. Save into Changes for review before publication.',
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
                if (_form != null)
                  ValueInputFields(
                    key: const ValueKey('attribute value'),
                    input: _form!.value,
                    original: _source.value,
                    disabled: _disabled,
                    label: 'Attribute value',
                    onChanged: _change,
                  ),
                if (_form != null) ...[
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
                            scopeInput(_source.evidence.scope),
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
                            evidenceBasisInput(_source.evidence.basis),
                        original: _source.evidence.basis,
                        disabled: _disabled,
                        onChanged: (v) => _editEvidence(basis: v),
                      ),
                    ],
                  ),
                ],
                ExpansionTile(
                  key: const ValueKey('original attribute'),
                  title: const Text('Original attribute and evidence'),
                  children: [ExactFields(value: _source.toWire())],
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
                  child: const Text('Save attribute changes'),
                ),
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
