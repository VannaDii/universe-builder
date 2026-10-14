import 'dart:async';

import 'guarded_pop_scope.dart';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'story_time_draft.dart';
import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';
import 'record_browser.dart';
import 'connection.dart';

class StoryTimeEditorPage extends StatefulWidget {
  const StoryTimeEditorPage({
    super.key,
    required this.changes,
    required this.revision,
    this.editingDraft,
    this.index,
    this.sourceRecord,
  });
  final SavedChanges changes;
  final RevisionId revision;
  final SavedDraft? editingDraft;
  final int? index;
  final RecordVersion? sourceRecord;
  @override
  State<StoryTimeEditorPage> createState() => _StoryTimeEditorPageState();
}

class _StoryTimeEditorPageState extends State<StoryTimeEditorPage> {
  UnfinishedStoryTimeForm? _form;
  RecordVersion? _source;
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
      _loading ||
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

  UnfinishedStoryTimeForm _fresh() => widget.index != null
      ? storyTimeFormFromDraft(_draft!, widget.index!, _source!)
      : storyTimeFormFromRecord(
          record: _source!,
          baseRevision: widget.revision,
          representedContext: _scope.representedContext!,
        );
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _draft = widget.editingDraft ?? await widget.changes.load();
      final pinned = SavedDraft(
        version: BigInt.zero,
        content: DraftContent(
          baseRevision: widget.index == null
              ? widget.revision
              : _draft!.content.baseRevision,
          representedContext: _scope.representedContext!,
          operations: [],
          rationale: '',
        ),
      );
      final target = widget.index == null
          ? _scope.representedContext!
          : (_draft!.content.operations[widget.index!] as SetStoryTimeOperation)
                .record
                .record;
      _source =
          widget.sourceRecord ??
          await readContextRecord(
            session: widget.changes.session,
            universe: LibraryEntry(
              _scope.universe,
              widget.changes.universe.value,
            ),
            context: await openDraftChoiceContext(widget.changes, pinned),
            record: target,
          );
      final saved = await widget.changes.session.loadStoryTimeForm(_scope);
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
                  (_form!.expectedRecordVersion != _source!.recordVersionId);
        _added =
            widget.index == null &&
                (_draft?.content.operations.any(
                      (op) =>
                          op is SetStoryTimeOperation &&
                          op.record.record.value == _form!.target.record &&
                          (op.record.universe?.value ?? '') ==
                              _form!.target.universe,
                    ) ??
                    false)
            ? 'This time transition is in Changes. Review or edit it there.'
            : null;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open the time transition form. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change(UnfinishedStoryTimeForm form) {
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
      final saved = await widget.changes.session.saveStoryTimeForm(
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
      final request = storyTimeDraftRequest(
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
        final index =
            widget.index ??
            saved.content.operations.indexWhere(
              (op) =>
                  op is SetStoryTimeOperation &&
                  op.record == storyTimeOperation(_form!).record,
            );
        _form = storyTimeFormFromDraft(saved, index, _source!);
        _fields++;
        _dirty = true;
      });
      await _save();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm saving the time transition. Check Changes before retrying.',
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
          widget.index == null ? 'Change story time' : 'Edit time transition',
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
                  'Time moves only through a reviewed change. Choose elapsed story time or explicit time travel and explain the transition. Other world clocks are not synchronized implicitly.',
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
                  Text(
                    'Current authored time: ${f.original.display(f.original.current)}',
                  ),
                  Text(
                    'First interaction: ${f.original.display(f.original.firstInteraction)}',
                  ),
                  DraftRecordChoiceField(
                    changes: widget.changes,
                    draft: _choices,
                    kind: RecordKind.representedContext,
                    label: 'Story clock context',
                    record: f.target.record,
                    universe: f.target.universe,
                    disabled: true,
                    onChanged: (_) {},
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey((_fields, 'mode')),
                    initialValue: f.mode,
                    decoration: const InputDecoration(labelText: 'Transition'),
                    items: const [
                      DropdownMenuItem(
                        value: '',
                        child: Text('Choose explicitly'),
                      ),
                      DropdownMenuItem(
                        value: 'elapsed',
                        child: Text('Elapsed story time'),
                      ),
                      DropdownMenuItem(
                        value: 'time_travel',
                        child: Text('Time travel'),
                      ),
                    ],
                    onChanged: _disabled
                        ? null
                        : (v) => _change(f.copyWith(mode: v)),
                  ),
                  _text(
                    'value',
                    f.original.system is GregorianClock
                        ? 'New timestamp with explicit offset'
                        : 'New whole-tick coordinate',
                    f.value,
                    (v) => _change(f.copyWith(value: v)),
                  ),
                  _text(
                    'reason',
                    'What accounts for this transition?',
                    f.reason,
                    (v) => _change(f.copyWith(reason: v)),
                    maxLines: 3,
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
                          : 'Save time transition',
                    ),
                  ),
                  TextButton(
                    onPressed: _loading || _saving || _adding || !_dirty
                        ? null
                        : _save,
                    child: const Text('Save unfinished work'),
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
                            if (mounted) await _load();
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
