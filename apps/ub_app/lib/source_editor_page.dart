import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'source_draft.dart';
import 'saved_changes.dart';

class SourceEditorPage extends StatefulWidget {
  const SourceEditorPage({
    super.key,
    required this.changes,
    required this.revision,
  });
  final SavedChanges changes;
  final RevisionId revision;
  @override
  State<SourceEditorPage> createState() => _SourceEditorPageState();
}

class _SourceEditorPageState extends State<SourceEditorPage> {
  UnfinishedSourceForm? _form;
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

  UnfinishedSourceForm _fresh() => UnfinishedSourceForm(
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
      _draft = await widget.changes.load();
      final saved = await widget.changes.session.loadSourceForm(_scope);
      if (!mounted) return;
      setState(() {
        _form = saved?.form ?? _fresh();
        _generation = saved?.generation ?? BigInt.zero;
        _fields++;
        _dirty = false;
        _stale = _form!.baseRevision != widget.revision;
        _added =
            _form!.staged.isNotEmpty &&
                (_draft?.content.operations.isNotEmpty ?? false) &&
                _form!.staged.every(
                  (op) => _draft!.content.operations.any(
                    (existing) =>
                        existing.toWire().toText() == op.toWire().toText(),
                  ),
                )
            ? 'This source is in Changes. Review it there.'
            : null;
      });
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open the source import form. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change({String? label, String? text, String? rationale}) {
    final f = _form!;
    setState(() {
      _form = UnfinishedSourceForm(
        baseRevision: f.baseRevision,
        representedContext: f.representedContext,
        clientRef: f.clientRef,
        label: label ?? f.label,
        text: text ?? f.text,
        rationale: rationale ?? f.rationale,
        staged: label == null && text == null ? f.staged : const [],
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
      final input = _form!;
      final saved = await widget.changes.session.saveSourceForm(
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
      if (_form!.label.trim().isEmpty || _form!.text.isEmpty) {
        throw const FormatException('Enter a source label and its exact text.');
      }
      if (_form!.staged.isEmpty) {
        final f = _form!;
        final staged = WireFields(
          await widget.changes.session.call(
            StageSourceEngineRequest(
              universe: widget.changes.universe,
              label: f.label,
              text: f.text,
            ),
          ),
          {'canonical', 'operations'},
        );
        if (staged.boolean('canonical')) {
          throw const FormatException('Expected an unpublished source.');
        }
        _form = UnfinishedSourceForm(
          baseRevision: f.baseRevision,
          representedContext: f.representedContext,
          clientRef: f.clientRef,
          label: f.label,
          text: f.text,
          rationale: f.rationale,
          staged: staged.array('operations').map(DomainOperation.fromWire),
        );
        _dirty = true;
        await _save();
        if (_dirty) return;
      }
      final draft = await widget.changes.load();
      final base = draft ?? _choices;
      final request = sourceDraftRequest(
        draft: base,
        form: _form!,
        universe: widget.changes.universe,
        continuity: _scope.continuity,
      );
      final saved =
          request.content.toWire().toText() == base.content.toWire().toText()
          ? base
          : SavedDraft.fromWire(await widget.changes.session.call(request));
      if (!mounted) return;
      setState(() {
        _draft = saved;
        _result = saved;
        _added = 'Source added to Changes. Review it before publication.';
      });
      await _save();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm saving the source. Check Changes before retrying.',
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
  Widget build(BuildContext context) => PopScope<SavedDraft>(
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Import source')),
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
                  'Retain submitted source text without fetching external URLs. Importing creates proposed source records; publication still requires review in Changes.',
                ),
                if (_loading || _saving || _adding)
                  const LinearProgressIndicator(),
                if (_stale) ...[
                  const Text(
                    'Recovered fields belong to an earlier draft or revision.',
                  ),
                  TextButton(
                    onPressed: _disabled ? null : _reset,
                    child: const Text('Start at current revision'),
                  ),
                ],
                if (_form case final f?) ...[
                  _text(
                    'label',
                    'Source label',
                    f.label,
                    (v) => _change(label: v),
                  ),
                  _text(
                    'text',
                    'Exact source text',
                    f.text,
                    (v) => _change(text: v),
                    maxLines: 12,
                  ),
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
                    child: const Text('Add to Changes'),
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
                      child: const Text('Import another source'),
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
