import 'dart:async';

import 'guarded_pop_scope.dart';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'value_definition_draft.dart';
import 'saved_changes.dart';
import 'value_shape_fields.dart';

class ValueDefinitionEditorPage extends StatefulWidget {
  const ValueDefinitionEditorPage({
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
  State<ValueDefinitionEditorPage> createState() =>
      _ValueDefinitionEditorPageState();
}

class _ValueDefinitionEditorPageState extends State<ValueDefinitionEditorPage> {
  UnfinishedValueDefinitionForm? _form;
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

  UnfinishedValueDefinitionForm _fresh() => widget.index != null
      ? valueDefinitionFormFromDraft(_draft!, widget.index!)
      : widget.revisionRecord != null
      ? valueDefinitionRevisionFormFromRecord(
          record: widget.revisionRecord!,
          baseRevision: widget.revision,
          representedContext: _scope.representedContext!,
        )
      : UnfinishedValueDefinitionForm(
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
      final saved = await widget.changes.session.loadValueDefinitionForm(
        _scope,
      );
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
                          (op is DefineValueOperation &&
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
          () => _error = 'Could not open the value definition form. Check the connection and retry.',
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
    List<ValueDefinitionFieldInput>? fields,
    String? rationale,
  }) {
    final f = _form!;
    setState(() {
      _form = UnfinishedValueDefinitionForm(
        baseRevision: f.baseRevision,
        representedContext: f.representedContext,
        clientRef: f.clientRef,
        namespace: namespace ?? f.namespace,
        key: key ?? f.key,
        labels: labels ?? f.labels,
        fields: fields ?? f.fields,
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

  void _fieldChanged(
    int index, {
    String? name,
    ValueShapeInput? shape,
    bool? required,
    bool? allowsUnknown,
  }) {
    final fields = [..._form!.fields], f = _form!.fields[index];
    fields[index] = ValueDefinitionFieldInput(
      name: name ?? f.name,
      shape: shape ?? f.shape,
      required: required ?? f.required,
      allowsUnknown: allowsUnknown ?? f.allowsUnknown,
    );
    _change(fields: fields);
  }

  void _moveField(int index, int destination) {
    final fields = [..._form!.fields], field = _form!.fields[index];
    fields.removeAt(index);
    fields.insert(destination, field);
    _fields++;
    _change(fields: fields);
  }

  Future<void> _save() async {
    if (!_dirty || _saving || _form == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.changes.session.saveValueDefinitionForm(
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
      final request = valueDefinitionDraftRequest(
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
                    op.record ==
                        valueDefinitionRevisionOperation(_form!).record,
              );
          _form = valueDefinitionFormFromDraft(saved, index);
          _fields++;
          _dirty = true;
        } else {
          _added = 'Value definition added to Changes. Review it before publication.';
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
  Widget build(BuildContext context) => GuardedPopScope<SavedDraft>(
    onLeave: _leave,
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.index == null ? 'Value definition' : 'Edit value definition',
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
                  'Declare named fields, their shapes and required/unknown flags. These fields stay unfinished on this device until added to Changes.',
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
                      'Revisions retain the namespace and key. Edit field shapes, order and required/unknown flags explicitly; publication preserves history.',
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
                    'Value definition key',
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
                  const Text('Declared fields'),
                  for (var i = 0; i < f.fields.length; i++)
                    Card(
                      key: ValueKey((_fields, 'field', i)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _text(
                              'field-name-$i',
                              'Field name',
                              f.fields[i].name,
                              (v) => _fieldChanged(i, name: v),
                            ),
                            ValueShapeFields(
                              key: ValueKey((_fields, 'shape', i)),
                              input: f.fields[i].shape,
                              changes: widget.changes,
                              draft: _choices,
                              disabled: _disabled,
                              onChanged: (v) => _fieldChanged(i, shape: v),
                            ),
                            _toggle(
                              'Required',
                              f.fields[i].required,
                              (v) => _fieldChanged(i, required: v),
                            ),
                            _toggle(
                              'Allows unknown',
                              f.fields[i].allowsUnknown,
                              (v) => _fieldChanged(i, allowsUnknown: v),
                            ),
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: _disabled || i == 0
                                      ? null
                                      : () => _moveField(i, i - 1),
                                  child: const Text('Move earlier'),
                                ),
                                TextButton(
                                  onPressed:
                                      _disabled || i == f.fields.length - 1
                                      ? null
                                      : () => _moveField(i, i + 1),
                                  child: const Text('Move later'),
                                ),
                                TextButton(
                                  onPressed: _disabled
                                      ? null
                                      : () {
                                          _fields++;
                                          _change(
                                            fields: [...f.fields]..removeAt(i),
                                          );
                                        },
                                  child: const Text('Remove field'),
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
                            fields: [
                              ...f.fields,
                              ValueDefinitionFieldInput(
                                shape: ValueShapeInput(),
                              ),
                            ],
                          ),
                    child: const Text('Add field'),
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
                          : 'Save value definition changes',
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
                      child: const Text('Start another value definition'),
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
