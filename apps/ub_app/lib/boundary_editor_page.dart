import 'dart:async';

import 'guarded_pop_scope.dart';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'boundary_draft.dart';
import 'saved_changes.dart';
import 'boundary_input_fields.dart';

class BoundaryEditorPage extends StatefulWidget {
  const BoundaryEditorPage({
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
  State<BoundaryEditorPage> createState() => _BoundaryEditorPageState();
}

class _BoundaryEditorPageState extends State<BoundaryEditorPage> {
  UnfinishedBoundaryForm? _form;
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
  bool _pickingPredicate = false;
  bool get _disabled =>
      _loading ||
      _pickingPredicate ||
      _adding ||
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

  UnfinishedBoundaryForm _fresh() => widget.index != null
      ? boundaryFormFromDraft(_draft!, widget.index!)
      : UnfinishedBoundaryForm(
          baseRevision: widget.revision,
          representedContext: _scope.representedContext!,
          clientRef: RecordId.generate().value,
          scope: ScopeInput(
            contextRecord: _scope.representedContext!.value,
            contextUniverse: _scope.universe.value,
          ),
        );
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _draft = widget.editingDraft ?? await widget.changes.load();
      final saved = await widget.changes.session.loadBoundaryForm(_scope);
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
                          op is SetCreativeBoundaryOperation &&
                          op.clientRef == _form!.clientRef,
                    ) ??
                    false)
            ? 'This definition is in Changes. Review or edit it there.'
            : null;
      });
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open the boundary form. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change(UnfinishedBoundaryForm form) {
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
      final savingForm = _form!;
      final saved = await widget.changes.session.saveBoundaryForm(
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
      final request = boundaryDraftRequest(
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
          _form = boundaryFormFromDraft(saved, widget.index!);
          _fields++;
          _dirty = true;
        } else {
          _added = 'Boundary added to Changes. Review it before publication.';
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
    if (_loading || _saving || _adding || _pickingPredicate) return;
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
          widget.index == null ? 'Creative boundary' : 'Edit creative boundary',
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
                  'Declare a creative boundary over a record, predicate or category. Its mode, constraints, scope and validity remain explicit; the existing evaluator determines how it applies. These fields stay unfinished on this device until added to Changes.',
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
                  BoundaryInputFields(
                    key: ValueKey((_fields, 'boundary')),
                    form: f,
                    changes: widget.changes,
                    draft: _choices,
                    disabled: _disabled,
                    onChanged: _change,
                    onBusy: (v) => setState(() => _pickingPredicate = v),
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
                          : 'Save boundary changes',
                    ),
                  ),
                  TextButton(
                    onPressed:
                        _loading ||
                            _saving ||
                            _adding ||
                            _pickingPredicate ||
                            !_dirty
                        ? null
                        : _save,
                    child: const Text('Save unfinished work'),
                  ),
                  if (_added != null)
                    TextButton(
                      onPressed:
                          _loading || _saving || _adding || _pickingPredicate
                          ? null
                          : _reset,
                      child: const Text('Start another boundary'),
                    ),
                  TextButton(
                    onPressed:
                        _loading || _saving || _adding || _pickingPredicate
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
                    onPressed:
                        _loading || _saving || _adding || _pickingPredicate
                        ? null
                        : _load,
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
