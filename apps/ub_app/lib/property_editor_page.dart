import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'property_draft.dart';
import 'saved_changes.dart';
import 'value_shape_fields.dart';

class PropertyEditorPage extends StatefulWidget {
  const PropertyEditorPage({
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
  State<PropertyEditorPage> createState() => _PropertyEditorPageState();
}

class _PropertyEditorPageState extends State<PropertyEditorPage> {
  UnfinishedPropertyForm? _form;
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

  UnfinishedPropertyForm _fresh() => widget.index != null
      ? propertyFormFromDraft(_draft!, widget.index!)
      : widget.revisionRecord != null
      ? propertyRevisionFormFromRecord(
          record: widget.revisionRecord!,
          baseRevision: widget.revision,
          representedContext: _scope.representedContext!,
        )
      : UnfinishedPropertyForm(
          baseRevision: widget.revision,
          representedContext: _scope.representedContext!,
          clientRef: RecordId.generate().value,
          shape: ValueShapeInput(),
        );
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _draft = widget.editingDraft ?? await widget.changes.load();
      final saved = await widget.changes.session.loadPropertyForm(_scope);
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
                          (op is DefinePropertyOperation &&
                              _form!.revisionTarget == null &&
                              op.clientRef == _form!.clientRef) ||
                          (op is ReviseDefinitionOperation &&
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
          () => _error = 'Could not open the property form. Check the connection and retry.',
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
    List<String>? types,
    ValueShapeInput? shape,
    String? multiplicity,
    String? persistence,
    bool? hasDimension,
    String? dimension,
    bool? hasInverse,
    String? inverse,
    bool? exclusive,
    bool? symmetric,
    bool? transitive,
    String? rationale,
  }) {
    final f = _form!;
    setState(() {
      _form = UnfinishedPropertyForm(
        baseRevision: f.baseRevision,
        representedContext: f.representedContext,
        clientRef: f.clientRef,
        namespace: namespace ?? f.namespace,
        key: key ?? f.key,
        labels: labels ?? f.labels,
        subjectTypes: types ?? f.subjectTypes,
        shape: shape ?? f.shape,
        multiplicity: multiplicity ?? f.multiplicity,
        persistence: persistence ?? f.persistence,
        hasUnitDimension: hasDimension ?? f.hasUnitDimension,
        unitDimension: dimension ?? f.unitDimension,
        hasInverse: hasInverse ?? f.hasInverse,
        inverse: inverse ?? f.inverse,
        exclusive: exclusive ?? f.exclusive,
        symmetric: symmetric ?? f.symmetric,
        transitive: transitive ?? f.transitive,
        rationale: rationale ?? f.rationale,
        draftVersion: f.draftVersion,
        revisionTarget: f.revisionTarget,
        expectedRecordVersion: f.expectedRecordVersion,
        original: f.original,
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
      final saved = await widget.changes.session.savePropertyForm(
        _scope,
        _form!,
        _generation,
      );
      if (mounted) {
        setState(() {
          _generation = saved.generation;
          _dirty = false;
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
      final request = propertyDraftRequest(
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
                    op is ReviseDefinitionOperation &&
                    op.record == propertyRevisionOperation(_form!).record,
              );
          _form = propertyFormFromDraft(saved, index);
          _fields++;
          _dirty = true;
        } else {
          _added = 'Property definition added to Changes. Review it before publication.';
        }
      });
      await _save();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
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
    bool readOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      key: ValueKey((_fields, key)),
      initialValue: value,
      enabled: !_disabled && !readOnly,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      onChanged: change,
    ),
  );
  Widget _toggle(String label, bool value, ValueChanged<bool> change) =>
      SwitchListTile(
        title: Text(label),
        value: value,
        onChanged: _disabled ? null : change,
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
          widget.index == null
              ? 'Property definition'
              : 'Edit property definition',
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
                  'Define what a factual attribute can hold. These fields stay unfinished on this device until added to Changes.',
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
                      'Revisions retain this property’s namespace and key. Existing checks assess changes against its current users and rules; publication preserves history.',
                    ),
                  _text(
                    'namespace',
                    'Namespace',
                    f.namespace,
                    (v) => _change(namespace: v),
                    readOnly: f.revisionTarget != null,
                  ),
                  _text(
                    'key',
                    'Property key',
                    f.key,
                    (v) => _change(key: v),
                    readOnly: f.revisionTarget != null,
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
                  SubjectTypeFields(
                    changes: widget.changes,
                    draft: _choices,
                    values: f.subjectTypes,
                    disabled: _disabled,
                    onChanged: (v) => _change(types: v),
                  ),
                  ValueShapeFields(
                    input: f.shape,
                    changes: widget.changes,
                    draft: _choices,
                    disabled: _disabled,
                    onChanged: (v) => _change(shape: v),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(('multiplicity', f.multiplicity)),
                    initialValue: f.multiplicity,
                    decoration: const InputDecoration(
                      labelText: 'Multiplicity',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Choose multiplicity'),
                      ),
                      for (final value in Multiplicity.values)
                        DropdownMenuItem(
                          value: value.name,
                          child: Text(value.name),
                        ),
                    ],
                    onChanged: _disabled
                        ? null
                        : (v) => _change(multiplicity: v),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(('persistence', f.persistence)),
                    initialValue: f.persistence,
                    decoration: const InputDecoration(labelText: 'Persistence'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Choose persistence'),
                      ),
                      for (final value in PersistenceSemantics.values)
                        DropdownMenuItem(
                          value: value.wireName,
                          child: Text(value.wireName.replaceAll('_', ' ')),
                        ),
                    ],
                    onChanged: _disabled
                        ? null
                        : (v) => _change(persistence: v),
                  ),
                  _toggle(
                    'Declare a unit dimension',
                    f.hasUnitDimension,
                    (v) => _change(hasDimension: v),
                  ),
                  if (f.hasUnitDimension)
                    _text(
                      'dimension',
                      'Unit dimension',
                      f.unitDimension,
                      (v) => _change(dimension: v),
                    ),
                  _toggle(
                    'Declare inverse metadata',
                    f.hasInverse,
                    (v) => _change(hasInverse: v),
                  ),
                  if (f.hasInverse)
                    _text(
                      'inverse',
                      'Inverse',
                      f.inverse,
                      (v) => _change(inverse: v),
                    ),
                  _toggle(
                    'Exclusive',
                    f.exclusive,
                    (v) => _change(exclusive: v),
                  ),
                  _toggle(
                    'Symmetric',
                    f.symmetric,
                    (v) => _change(symmetric: v),
                  ),
                  _toggle(
                    'Transitive',
                    f.transitive,
                    (v) => _change(transitive: v),
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
                          : 'Save property changes',
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
                      child: const Text('Start another property'),
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
