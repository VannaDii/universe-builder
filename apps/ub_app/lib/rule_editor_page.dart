import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'rule_draft.dart';
import 'saved_changes.dart';
import 'expression_input_fields.dart';
import 'scope_input_fields.dart';
import 'value_shape_fields.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';
import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';
import 'record_browser.dart';
import 'connection.dart';
import 'rule_knowledge_fields.dart';
import 'rule_constraint_fields.dart';

class RuleEditorPage extends StatefulWidget {
  const RuleEditorPage({
    super.key,
    required this.changes,
    required this.revision,
    this.editingDraft,
    this.index,
  });
  final SavedChanges changes;
  final RevisionId revision;
  final SavedDraft? editingDraft;
  final int? index;
  @override
  State<RuleEditorPage> createState() => _RuleEditorPageState();
}

class _RuleEditorPageState extends State<RuleEditorPage> {
  UnfinishedRuleForm? _form;
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
  bool _choosingPredicate = false;
  bool get _disabled =>
      _loading ||
      _adding ||
      _choosingPredicate ||
      _form == null ||
      (widget.index == null && _added != null);
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

  UnfinishedRuleForm _fresh() => widget.index != null
      ? ruleFormFromDraft(_draft!, widget.index!)
      : UnfinishedRuleForm(
          baseRevision: widget.revision,
          representedContext: _scope.representedContext!,
          clientRef: RecordId.generate().value,
          scope: ScopeInput(contextRecord: _scope.representedContext!.value),
        );
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _draft = widget.editingDraft ?? await widget.changes.load();
      final saved = await widget.changes.session.loadRuleForm(_scope);
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
            : _form!.baseRevision != widget.revision;
        _added =
            widget.index == null &&
                (_draft?.content.operations.any(
                      (op) =>
                          op is DefineRuleOperation &&
                          op.clientRef == _form!.clientRef,
                    ) ??
                    false)
            ? 'This definition is in Changes. Review or edit it there.'
            : null;
      });
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open the rule definition form. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change({
    String? namespace,
    String? key,
    List<PropertyLabelInput>? labels,
    String? kind,
    String? commitPolicy,
    bool? executable,
    ExpressionInput? expression,
    List<String>? subjectTypes,
    List<String>? targetPredicates,
    List<String>? capabilities,
    ScopeInput? scope,
    TemporalValidityInput? validity,
    String? rationale,
    RuleKnowledgeInput? knowledge,
    RuleConstraintInput? constraints,
  }) {
    final f = _form!;
    setState(() {
      _form = UnfinishedRuleForm(
        baseRevision: f.baseRevision,
        representedContext: f.representedContext,
        clientRef: f.clientRef,
        namespace: namespace ?? f.namespace,
        key: key ?? f.key,
        labels: labels ?? f.labels,
        kind: kind ?? f.kind,
        commitPolicy: commitPolicy ?? f.commitPolicy,
        executable: executable ?? f.executable,
        expression: expression ?? f.expression,
        subjectTypes: subjectTypes ?? f.subjectTypes,
        targetPredicates: targetPredicates ?? f.targetPredicates,
        capabilities: capabilities ?? f.capabilities,
        scope: scope ?? f.scope,
        validity: validity ?? f.validity,
        original: f.original,
        knowledge: knowledge ?? f.knowledge,
        constraints: constraints ?? f.constraints,
        rationale: rationale ?? f.rationale,
        draftVersion: f.draftVersion,
      );
      _dirty = true;
    });
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    if (!_dirty || _saving || _form == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final savingForm = _form!;
      final saved = await widget.changes.session.saveRuleForm(
        _scope,
        savingForm,
        _generation,
      );
      if (mounted) {
        setState(() {
          _generation = saved.generation;
          _dirty = _form!.toWire().toText() != savingForm.toWire().toText();
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not save these fields. Your input remains here; another window may have changed it.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_dirty && _error == null) {
          _autosave?.cancel();
          _autosave = Timer(const Duration(milliseconds: 500), _save);
        }
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
      final request = ruleDraftRequest(
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
        if (widget.index != null) {
          _form = ruleFormFromDraft(saved, widget.index!);
          _fields++;
          _dirty = true;
        } else {
          _added =
              'Rule definition added to Changes. Review it before publication.';
        }
      });
      await _save();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on InvalidArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.field}: ${e.message}');
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm saving the definition. Check Changes before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _leave() async {
    if (_loading || _saving || _adding || _choosingPredicate) return;
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
      enabled: !_disabled,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      onChanged: change,
    ),
  );
  Future<void> _addTargetPredicate(RecordRef reference) async {
    final clientRef = _form!.clientRef;
    setState(() => _choosingPredicate = true);
    try {
      if (reference.universe != null && reference.universe != _scope.universe) {
        throw const FormatException('Choose a predicate in this universe.');
      }
      final context = await openDraftChoiceContext(widget.changes, _choices);
      final row = await readContextRecord(
        session: widget.changes.session,
        universe: LibraryEntry(_scope.universe, widget.changes.universe.value),
        context: context,
        record: reference.record,
      );
      final predicate = switch (row.payload) {
        PropertyRecord(:final namespace, :final key) ||
        RelationRecord(:final namespace, :final key) => '$namespace:$key',
        _ => throw const FormatException(
          'Choose a property or relation definition.',
        ),
      };
      if (!mounted || _form!.clientRef != clientRef) return;
      _fields++;
      _change(targetPredicates: [..._form!.targetPredicates, predicate]);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not read the selected predicate. Check access and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _choosingPredicate = false);
    }
  }

  Widget _choice(
    String key,
    String label,
    String value,
    Map<String, String> choices,
    ValueChanged<String> change,
  ) => DropdownButtonFormField<String>(
    key: ValueKey((_fields, key)),
    initialValue: value.isEmpty ? null : value,
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
  @override
  Widget build(BuildContext context) => PopScope<SavedDraft>(
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.index == null ? 'Rule definition' : 'Edit rule definition',
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
                const Text(
                  'Declare scoped rules and commit behavior. Declared execution support is checked by the service. These fields stay unfinished on this device until added to Changes.',
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
                  _text(
                    'namespace',
                    'Namespace',
                    f.namespace,
                    (v) => _change(namespace: v),
                  ),
                  _text(
                    'key',
                    'Rule definition key',
                    f.key,
                    (v) => _change(key: v),
                  ),
                  const SizedBox(height: 16),
                  const Text('Display labels'),
                  for (var i = 0; i < f.labels.length; i++)
                    Column(
                      children: [
                        _text(
                          'label-language-$i',
                          'Language key',
                          f.labels[i].language,
                          (v) {
                            final labels = [...f.labels];
                            labels[i] = PropertyLabelInput(
                              language: v,
                              text: labels[i].text,
                            );
                            _change(labels: labels);
                          },
                        ),
                        _text(
                          'label-text-$i',
                          'Display label',
                          f.labels[i].text,
                          (v) {
                            final labels = [...f.labels];
                            labels[i] = PropertyLabelInput(
                              language: labels[i].language,
                              text: v,
                            );
                            _change(labels: labels);
                          },
                        ),
                        TextButton(
                          onPressed: _disabled
                              ? null
                              : () {
                                  _fields++;
                                  _change(labels: [...f.labels]..removeAt(i));
                                },
                          child: const Text('Remove label'),
                        ),
                      ],
                    ),
                  TextButton(
                    onPressed: _disabled
                        ? null
                        : () => _change(
                            labels: [...f.labels, const PropertyLabelInput()],
                          ),
                    child: const Text('Add label'),
                  ),
                  _choice('kind', 'Rule kind', f.kind, {
                    for (final k in RuleKind.values)
                      k.wireName: k.wireName.replaceAll('_', ' '),
                  }, (v) => _change(kind: v)),
                  _choice('policy', 'Commit policy', f.commitPolicy, {
                    for (final p in CommitPolicy.values)
                      p.wireName: p.wireName.replaceAll('_', ' '),
                  }, (v) => _change(commitPolicy: v)),
                  _choice(
                    'executable',
                    'Executable',
                    f.executable?.toString() ?? '',
                    {'true': 'Executable', 'false': 'Descriptive only'},
                    (v) => _change(executable: v == 'true'),
                  ),
                  ScopeInputFields(
                    key: ValueKey((_fields, 'applicability')),
                    input: f.scope,
                    applicabilityOnly: true,
                    changes: widget.changes,
                    draft: _choices,
                    disabled: _disabled,
                    onChanged: (v) => _change(scope: v),
                  ),
                  SubjectTypeFields(
                    key: ValueKey((_fields, 'subject-types')),
                    changes: widget.changes,
                    draft: _choices,
                    values: f.subjectTypes,
                    label: 'Subject type',
                    disabled: _disabled,
                    onChanged: (v) => _change(subjectTypes: v),
                  ),
                  for (final kind in [RecordKind.property, RecordKind.relation])
                    DraftRecordChoiceField(
                      changes: widget.changes,
                      draft: _choices,
                      kind: kind,
                      label: kind == RecordKind.property
                          ? 'Add target property'
                          : 'Add target relation',
                      record: '',
                      universe: '',
                      disabled: _disabled || _choosingPredicate,
                      onChanged: _addTargetPredicate,
                    ),
                  _text(
                    'targets',
                    'Target predicate keys (namespace:key), one per line',
                    f.targetPredicates.join('\n'),
                    (v) => _change(
                      targetPredicates: v.isEmpty ? [] : v.split('\n'),
                    ),
                    maxLines: 3,
                  ),
                  _text(
                    'capabilities',
                    'Declared capabilities, one per line',
                    f.capabilities.join('\n'),
                    (v) =>
                        _change(capabilities: v.isEmpty ? [] : v.split('\n')),
                    maxLines: 3,
                  ),
                  const Text('Expression'),
                  ExpressionInputFields(
                    key: ValueKey((_fields, 'expression')),
                    input: f.expression,
                    changes: widget.changes,
                    draft: _choices,
                    disabled: _disabled,
                    onChanged: (v) => _change(expression: v),
                  ),
                  _choice(
                    'validity-kind',
                    'Rule validity',
                    {
                          'unknown',
                          'unspecified',
                          'condition_dependent',
                        }.contains(f.validity.kind)
                        ? f.validity.kind
                        : 'temporal',
                    {
                      'unspecified': 'Unspecified',
                      'unknown': 'Unknown',
                      'condition_dependent': 'Condition dependent',
                      'temporal': 'Temporal validity',
                    },
                    (v) {
                      _fields++;
                      _change(
                        validity: v == 'temporal'
                            ? const TemporalValidityInput()
                            : TemporalValidityInput(kind: v),
                      );
                    },
                  ),
                  if (!{
                    'unknown',
                    'unspecified',
                    'condition_dependent',
                  }.contains(f.validity.kind))
                    TemporalValidityFields(
                      key: ValueKey((_fields, 'validity')),
                      input: f.validity,
                      originalAmounts: temporalOriginalAmounts(
                        f.original?.validity,
                      ),
                      changes: widget.changes,
                      draft: _choices,
                      disabled: _disabled,
                      onChanged: (v) => _change(validity: v),
                    ),
                  RuleKnowledgeFields(
                    key: ValueKey((_fields, 'knowledge')),
                    input:
                        f.knowledge ??
                        (f.original == null
                            ? const RuleKnowledgeInput()
                            : ruleKnowledgeInput(f.original!)),
                    changes: widget.changes,
                    draft: _choices,
                    disabled: _disabled,
                    onChanged: (v) => _change(knowledge: v),
                  ),
                  RuleConstraintFields(
                    key: ValueKey((_fields, 'constraints')),
                    input:
                        f.constraints ??
                        (f.original == null
                            ? const RuleConstraintInput()
                            : ruleConstraintInput(f.original!)),
                    originalCardinality: f.original?.relationCardinality,
                    changes: widget.changes,
                    draft: _choices,
                    disabled: _disabled,
                    onChanged: (v) => _change(constraints: v),
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
                          : 'Save rule definition changes',
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
                      child: const Text('Start another rule definition'),
                    ),
                  TextButton(
                    onPressed: _loading || _saving || _adding
                        ? null
                        : () async {
                            _autosave?.cancel();
                            await _save();
                            if (!context.mounted || _dirty) return;
                            await Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ChangesPage(changes: widget.changes),
                              ),
                            );
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
