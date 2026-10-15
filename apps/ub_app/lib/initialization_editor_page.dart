import 'dart:async';

import 'guarded_pop_scope.dart';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'initialization_draft.dart';
import 'saved_changes.dart';
import 'initialization_input_fields.dart';
import 'draft_record_choices.dart';
import 'record_browser.dart';
import 'connection.dart';
import 'record_fields.dart';

class InitializationEditorPage extends StatefulWidget {
  const InitializationEditorPage({
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
  State<InitializationEditorPage> createState() =>
      _InitializationEditorPageState();
}

class _InitializationEditorPageState extends State<InitializationEditorPage> {
  UnfinishedInitializationForm? _form;
  SavedDraft? _draft, _result;
  BigInt _generation = BigInt.zero;
  bool _loading = true,
      _saving = false,
      _adding = false,
      _dirty = false,
      _stale = false,
      _leaving = false,
      _reading = false;
  CanonicalValue? _preview;
  String? _error, _added;
  Timer? _autosave;
  int _fields = 0;
  bool get _disabled =>
      !widget.changes.session.author ||
      _loading ||
      _adding ||
      _reading ||
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

  UnfinishedInitializationForm _fresh() => widget.index != null
      ? initializationFormFromDraft(_draft!, widget.index!)
      : UnfinishedInitializationForm(
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
      final saved = await widget.changes.session.loadInitializationForm(_scope);
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
                          op is InitializeInstanceOperation &&
                          op.clientRef == _form!.clientRef,
                    ) ??
                    false)
            ? 'This initialization is in Changes. Review or edit it there.'
            : null;
      });
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open the initialization form. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change(UnfinishedInitializationForm form) {
    setState(() {
      _form = form;
      _preview = null;
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
      final saved = await widget.changes.session.saveInitializationForm(
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
      _preview = null;
      _fields++;
      _dirty = true;
      _stale = false;
      _added = null;
    });
    await _save();
  }

  Future<
    ({
      RecordVersion start,
      RecordVersion definition,
      Chronology? clock,
      PropositionRecord proposition,
    })
  >
  _material() async {
    final f = _form!;
    if (f.instance.record.isEmpty ||
        f.start.record.isEmpty ||
        f.definition == null) {
      throw const FormatException(
        'Choose an instance, an occurred start and an initial-value assertion.',
      );
    }
    final context = await openDraftChoiceContext(widget.changes, _choices);
    Future<RecordVersion> read(RecordId record) => readContextRecord(
      session: widget.changes.session,
      universe: LibraryEntry(_scope.universe, widget.changes.universe.value),
      context: context,
      record: record,
    );
    final start = await read(RecordId.parse(f.start.record));
    if (f.definition == null) {
      throw const FormatException('Choose an initial-value assertion.');
    }
    final definition = await read(f.definition!.record);
    final assertion = definition.payload;
    if (assertion is! AssertionRecord ||
        assertion.attributeMode != AttributeMode.initialValue) {
      throw const FormatException('Choose an initial-value assertion.');
    }
    if (assertion.proposition.universe != null &&
        assertion.proposition.universe != _scope.universe) {
      throw const FormatException(
        'Choose an initial-value proposition in this universe.',
      );
    }
    final proposition = (await read(assertion.proposition.record)).payload;
    if (proposition is! PropositionRecord) {
      throw const FormatException('The source proposition is unavailable.');
    }
    final represented = (await read(f.representedContext)).payload;
    final clock = represented is RepresentedContextRecord
        ? represented.chronology
        : null;
    return (
      start: start,
      definition: definition,
      clock: clock,
      proposition: proposition,
    );
  }

  Future<void> _inspect() async {
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final material = await _material();
      final op = initializationOperation(
        _form!,
        universe: _scope.universe,
        start: material.start,
        definition: material.definition,
        clock: material.clock,
      );
      if (mounted) {
        setState(
          () => _preview = CanonicalObject([
            MapEntry('subject', op.instance.toCanonical()),
            MapEntry('predicate', material.proposition.predicate.toCanonical()),
            MapEntry(
              'value',
              material.proposition.value?.toWire() ?? const CanonicalNull(),
            ),
            MapEntry('scope', op.scope.toWire()),
            MapEntry('validity', op.validity.toWire()),
            MapEntry('source_assertion_version', op.definition.toCanonical()),
          ]),
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not read the starting fact. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
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
      final material = await _material();
      final request = initializationDraftRequest(
        draft: base,
        form: _form!,
        universe: widget.changes.universe,
        continuity: _scope.continuity,
        universeId: _scope.universe,
        start: material.start,
        definition: material.definition,
        clock: material.clock,
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
          _form = initializationFormFromDraft(saved, widget.index!);
          _fields++;
          _dirty = true;
        } else {
          _added = 'Instance initialization added to Changes. Review it before publication.';
        }
      });
      await _save();
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm saving the initialization. Check Changes before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _leave() async {
    if (_loading || _saving || _adding || _reading) return;
    _autosave?.cancel();
    await _save();
    if (!mounted || _dirty) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(_result);
  }

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
        title: Text(
          widget.index == null
              ? 'Instance initialization'
              : 'Edit initialization',
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
                  'Apply an initial value to an instance at its exact occurred start. Review the starting fact before publication. Unfinished fields stay on this device until added to Changes.',
                ),
                if (_loading || _saving || _adding || _reading)
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
                  InitializationInputFields(
                    key: ValueKey((_fields, 'initialization')),
                    form: f,
                    changes: widget.changes,
                    draft: _choices,
                    disabled: _disabled,
                    onChanged: _change,
                    onBusy: (value) => setState(() => _reading = value),
                  ),
                  Text(
                    _dirty
                        ? 'Unsaved fields'
                        : _generation == BigInt.zero
                        ? 'No saved fields yet'
                        : 'Saved on this device',
                  ),
                  TextButton(
                    onPressed: _disabled || _stale ? null : _inspect,
                    child: const Text('Preview starting fact'),
                  ),
                  if (_preview != null) ...[
                    const Text('Proposed starting instance fact'),
                    ExactFields(value: _preview!),
                  ],
                  FilledButton(
                    onPressed: _disabled || _stale ? null : _add,
                    child: Text(
                      widget.index == null
                          ? 'Add to Changes'
                          : 'Save initialization changes',
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
                      onPressed: _loading || _saving || _adding || _reading
                          ? null
                          : _reset,
                      child: const Text('Start another initialization'),
                    ),
                  TextButton(
                    onPressed: _loading || _saving || _adding || _reading
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
                    onPressed: _loading || _saving || _adding || _reading
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
