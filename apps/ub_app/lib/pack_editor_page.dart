import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'pack_draft.dart';
import 'draft_record_choice_field.dart';
import 'saved_changes.dart';

class PackEditorPage extends StatefulWidget {
  const PackEditorPage({
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
  State<PackEditorPage> createState() => _PackEditorPageState();
}

class _PackEditorPageState extends State<PackEditorPage> {
  UnfinishedPackForm? _form;
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

  UnfinishedPackForm _fresh() => widget.index != null
      ? packFormFromDraft(_draft!, widget.index!)
      : widget.revisionRecord != null
      ? packRevisionFormFromRecord(
          record: widget.revisionRecord!,
          baseRevision: widget.revision,
          representedContext: _scope.representedContext!,
        )
      : UnfinishedPackForm(
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
      final saved = await widget.changes.session.loadPackForm(_scope);
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
                          (op is InstallPackOperation &&
                              _form!.revisionTarget == null &&
                              op.clientRef == _form!.clientRef) ||
                          (op is UpgradePackOperation &&
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
          () => _error = 'Could not open the pack declaration form. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change(UnfinishedPackForm form) {
    setState(() {
      _form = form;
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
      final saved = await widget.changes.session.savePackForm(
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
      final request = packDraftRequest(
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
                    op is UpgradePackOperation &&
                    op.record == packRevisionOperation(_form!).record,
              );
          _form = packFormFromDraft(saved, index);
          _fields++;
          _dirty = true;
        } else {
          _added =
              'Domain pack added to Changes. Review it before publication.';
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
  @override
  Widget build(BuildContext context) => PopScope<SavedDraft>(
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.index == null ? 'Domain pack' : 'Edit pack declaration',
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
                  'Declare a data pack of existing records with an exact version, dependency versions and capabilities. The service checks dependencies and supported capabilities during review. This declaration does not download content or alter member records.',
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
                      'Upgrades retain the pack key and require a different exact version. Dependency versions and member records remain explicit; publication preserves history.',
                    ),
                  _text(
                    'key',
                    'Pack key',
                    f.key,
                    (v) => _change(f.copyWith(key: v)),
                    readOnly: f.revisionTarget != null,
                  ),
                  _text(
                    'version',
                    'Exact version',
                    f.version,
                    (v) => _change(f.copyWith(version: v)),
                  ),
                  const Text('Exact dependency versions'),
                  for (var i = 0; i < f.dependencies.length; i++)
                    Column(
                      children: [
                        _text(
                          'dependency-key-$i',
                          'Dependency pack key',
                          f.dependencies[i].key,
                          (v) {
                            final rows = [...f.dependencies];
                            rows[i] = PackDependencyInput(
                              key: v,
                              version: rows[i].version,
                            );
                            _change(f.copyWith(dependencies: rows));
                          },
                        ),
                        _text(
                          'dependency-version-$i',
                          'Dependency exact version',
                          f.dependencies[i].version,
                          (v) {
                            final rows = [...f.dependencies];
                            rows[i] = PackDependencyInput(
                              key: rows[i].key,
                              version: v,
                            );
                            _change(f.copyWith(dependencies: rows));
                          },
                        ),
                        TextButton(
                          onPressed: _disabled
                              ? null
                              : () {
                                  _fields++;
                                  _change(
                                    f.copyWith(
                                      dependencies: [...f.dependencies]
                                        ..removeAt(i),
                                    ),
                                  );
                                },
                          child: const Text('Remove dependency'),
                        ),
                      ],
                    ),
                  TextButton(
                    onPressed: _disabled
                        ? null
                        : () => _change(
                            f.copyWith(
                              dependencies: [
                                ...f.dependencies,
                                const PackDependencyInput(),
                              ],
                            ),
                          ),
                    child: const Text('Add dependency'),
                  ),
                  const Text('Declared capabilities'),
                  for (var i = 0; i < f.capabilities.length; i++)
                    Row(
                      children: [
                        Expanded(
                          child: _text(
                            'capability-$i',
                            'Capability',
                            f.capabilities[i],
                            (v) {
                              final rows = [...f.capabilities];
                              rows[i] = v;
                              _change(f.copyWith(capabilities: rows));
                            },
                          ),
                        ),
                        TextButton(
                          onPressed: _disabled
                              ? null
                              : () {
                                  _fields++;
                                  _change(
                                    f.copyWith(
                                      capabilities: [...f.capabilities]
                                        ..removeAt(i),
                                    ),
                                  );
                                },
                          child: const Text('Remove capability'),
                        ),
                      ],
                    ),
                  TextButton(
                    onPressed: _disabled
                        ? null
                        : () => _change(
                            f.copyWith(capabilities: [...f.capabilities, '']),
                          ),
                    child: const Text('Add capability'),
                  ),
                  const Text('Member records in declared order'),
                  for (var i = 0; i < f.records.length; i++)
                    Column(
                      children: [
                        DraftRecordChoiceField(
                          key: ValueKey((_fields, 'record', i)),
                          changes: widget.changes,
                          draft: _choices,
                          kind: null,
                          label: 'Member record',
                          record: f.records[i],
                          universe: _scope.universe.value,
                          disabled: _disabled,
                          onChanged: (ref) {
                            final rows = [...f.records];
                            rows[i] = ref.record.value;
                            _change(f.copyWith(records: rows));
                          },
                        ),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: _disabled || i == 0
                                  ? null
                                  : () {
                                      final rows = [...f.records];
                                      rows.insert(i - 1, rows.removeAt(i));
                                      _fields++;
                                      _change(f.copyWith(records: rows));
                                    },
                              child: const Text('Move earlier'),
                            ),
                            TextButton(
                              onPressed: _disabled || i == f.records.length - 1
                                  ? null
                                  : () {
                                      final rows = [...f.records];
                                      rows.insert(i + 1, rows.removeAt(i));
                                      _fields++;
                                      _change(f.copyWith(records: rows));
                                    },
                              child: const Text('Move later'),
                            ),
                            TextButton(
                              onPressed: _disabled
                                  ? null
                                  : () {
                                      _fields++;
                                      _change(
                                        f.copyWith(
                                          records: [...f.records]..removeAt(i),
                                        ),
                                      );
                                    },
                              child: const Text('Remove member'),
                            ),
                          ],
                        ),
                        _text(
                          'record-$i',
                          'Advanced member record reference',
                          f.records[i],
                          (v) {
                            final rows = [...f.records];
                            rows[i] = v;
                            _change(f.copyWith(records: rows));
                          },
                        ),
                      ],
                    ),
                  TextButton(
                    onPressed: _disabled
                        ? null
                        : () =>
                              _change(f.copyWith(records: [...f.records, ''])),
                    child: const Text('Add member record'),
                  ),
                  if (widget.index == null)
                    _text(
                      'rationale',
                      'Rationale',
                      f.rationale,
                      (v) => _change(f.copyWith(rationale: v)),
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
                          : 'Save pack declaration changes',
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
                      child: const Text('Start another pack declaration'),
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
