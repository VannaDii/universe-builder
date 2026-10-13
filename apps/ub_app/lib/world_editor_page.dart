import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart'
    show
        RecordId,
        RecordVersion,
        WorldRecord,
        CanonicalNull,
        CreateWorldOperation;

import 'connection.dart';
import 'world_draft.dart';
import 'changes_page.dart';
import 'saved_changes.dart';
import 'world_browser.dart';

class WorldEditorPage extends StatefulWidget {
  const WorldEditorPage({
    super.key,
    required this.session,
    required this.scope,
    required this.continuity,
    required this.universe,
    this.representedContext,
  }) : addAlias = false,
       publishedWorld = null,
       editingDraft = null,
       operationIndex = null;
  WorldEditorPage.edit({
    super.key,
    required SavedChanges changes,
    required SavedDraft draft,
    required int index,
  }) : addAlias = false,
       session = changes.session,
       universe = changes.universe,
       continuity = null,
       representedContext = null,
       publishedWorld = null,
       editingDraft = draft,
       operationIndex = index,
       scope = EditorFormScope(
         instance: changes.scope.instance,
         profile: changes.scope.profile,
         universe: changes.scope.universe,
         continuity: changes.scope.continuity,
         worldClientRef:
             (draft.content.operations[index] as CreateWorldOperation)
                 .clientRef,
       );
  const WorldEditorPage.rename({
    super.key,
    required this.session,
    required this.scope,
    required this.continuity,
    required this.universe,
    required this.representedContext,
    required RecordVersion world,
    this.addAlias = false,
  }) : publishedWorld = world,
       editingDraft = null,
       operationIndex = null;
  final bool addAlias;
  final RecordVersion? publishedWorld;
  final SavedDraft? editingDraft;
  final int? operationIndex;
  final AppSession session;
  final EditorFormScope scope;
  final ContinuitySummary? continuity;
  final RepresentedContextSummary? representedContext;
  final Selector universe;
  @override
  State<WorldEditorPage> createState() => _WorldEditorPageState();
}

class _WorldEditorPageState extends State<WorldEditorPage> {
  final _name = TextEditingController(),
      _label = TextEditingController(),
      _setting = TextEditingController(),
      _rationale = TextEditingController();
  UnfinishedWorldForm? _base;
  BigInt _generation = BigInt.zero;
  bool _loading = true, _saving = false, _dirty = false, _adding = false;
  bool _stale = false;
  SavedDraft? _editingDraft, _savedDraft;
  String? _error;
  String? _added;
  Timer? _autosave;

  @override
  void initState() {
    super.initState();
    _editingDraft = widget.editingDraft;
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    for (final controller in [_name, _label, _setting, _rationale]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await widget.session.loadWorldForm(widget.scope);
      if (!mounted) return;
      final form = saved?.form ?? _initialForm();
      setState(() {
        _base = form;
        _stale =
            _editingDraft != null &&
            (form.draftVersion != _editingDraft!.version ||
                form.baseRevision != _editingDraft!.content.baseRevision ||
                form.representedContext !=
                    _editingDraft!.content.representedContext);
        if (widget.publishedWorld != null) {
          _stale =
              form.expectedRecordVersion !=
                  widget.publishedWorld!.recordVersionId ||
              form.baseRevision != widget.continuity!.revisionId ||
              form.representedContext != widget.representedContext!.id;
        }
        _generation = saved?.generation ?? BigInt.zero;
        _name.text = form.selector;
        _label.text = form.labels['en'] ?? '';
        _setting.text = form.settingType;
        _rationale.text = form.rationale;
        _loading = false;
        _dirty = false;
        _error = null;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not open saved work. Check your connection and access, then try again.';
        });
      }
    }
  }

  UnfinishedWorldForm _initialForm() {
    final draft = _editingDraft;
    if (draft != null) {
      final operation =
          draft.content.operations[widget.operationIndex!]
              as CreateWorldOperation;
      return UnfinishedWorldForm(
        baseRevision: draft.content.baseRevision,
        representedContext: draft.content.representedContext,
        record: RecordId.generate(),
        selector: operation.record.selector,
        settingType: operation.record.settingType ?? '',
        rationale: '',
        aliases: operation.record.aliases,
        labels: operation.record.labels,
        draftVersion: draft.version,
      );
    }
    if (widget.publishedWorld case final world?) {
      final record = world.payload as WorldRecord;
      return UnfinishedWorldForm(
        baseRevision: widget.continuity!.revisionId,
        representedContext: widget.representedContext!.id,
        record: world.identity.recordId,
        expectedRecordVersion: world.recordVersionId,
        selector: widget.addAlias ? '' : record.selector,
        settingType: record.settingType ?? '',
        rationale: '',
        aliases: record.aliases,
        labels: record.labels,
      );
    }
    return UnfinishedWorldForm(
      baseRevision: widget.continuity!.revisionId,
      representedContext:
          widget.representedContext?.id ??
          widget.continuity!.representedContexts.single.id,
      record: RecordId.generate(),
      selector: '',
      settingType: '',
      rationale: '',
    );
  }

  Future<void> _replacePendingFields() async {
    if (_saving || _adding) return;
    await _replaceFields(_initialForm());
  }

  Future<void> _startAnotherWorld() async {
    if (_saving ||
        _adding ||
        _dirty ||
        _added == null ||
        _editingDraft != null ||
        widget.publishedWorld != null) {
      return;
    }
    final previous = _base!;
    await _replaceFields(
      UnfinishedWorldForm(
        baseRevision: previous.baseRevision,
        representedContext: previous.representedContext,
        record: RecordId.generate(),
        selector: '',
        settingType: '',
        rationale: '',
      ),
    );
  }

  Future<void> _replaceFields(UnfinishedWorldForm form) async {
    _autosave?.cancel();
    setState(() {
      _base = form;
      _name.text = form.selector;
      _label.text = form.labels['en'] ?? '';
      _setting.text = form.settingType;
      _rationale.text = form.rationale;
      _dirty = true;
      _stale = false;
      _added = null;
    });
    await _save();
  }

  UnfinishedWorldForm get _form => UnfinishedWorldForm(
    baseRevision: _base!.baseRevision,
    representedContext: _base!.representedContext,
    record: _base!.record,
    draftVersion: _base!.draftVersion,
    expectedRecordVersion: _base!.expectedRecordVersion,
    selector: _name.text,
    settingType: _setting.text,
    rationale: _rationale.text,
    aliases: _base!.aliases,
    labels: {..._base!.labels, 'en': _label.text},
  );

  void _changed(String _) {
    setState(() {
      _dirty = true;
      _added = null;
    });
    _autosave?.cancel();
    if (_error == null) {
      _autosave = Timer(const Duration(milliseconds: 600), _save);
    }
  }

  Future<void> _save() async {
    if (_saving || !_dirty || _base == null) return;
    _autosave?.cancel();
    final entered = _form;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.session.saveWorldForm(
        widget.scope,
        entered,
        _generation,
      );
      if (!mounted) return;
      setState(() {
        _generation = saved.generation;
        _dirty = _form.toWire().toText() != entered.toWire().toText();
        _base = saved.form;
      });
    } on EditorRecoveryException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.failure == EditorRecoveryFailure.conflict
              ? 'Another window saved newer fields. Your text is still here. Open the saved version separately before replacing your work.'
              : 'Could not save unfinished work. Your text is still here; try saving again.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not save unfinished work. Your text is still here. Check your connection and access.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
      if (mounted && _dirty && _error == null) {
        _autosave = Timer(const Duration(milliseconds: 600), _save);
      }
    }
  }

  Future<void> _leave() async {
    if (_saving || _adding) return;
    if (_dirty) await _save();
    if (!mounted || _dirty || _saving) return;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && !_dirty && !_saving && !_adding) {
      Navigator.of(context).pop(_savedDraft);
    }
  }

  Future<void> _add() async {
    if (_base == null || _saving || _adding) return;
    if (_dirty) await _save();
    if (!mounted || _dirty || _saving) return;
    final entered = _form;
    setState(() {
      _adding = true;
      _error = null;
      _added = null;
    });
    try {
      if (_editingDraft != null) {
        if (_stale || entered.draftVersion != _editingDraft!.version) {
          throw const FormatException(
            'These unfinished edits use an earlier draft. Review your text and the current world before replacing the pending fields.',
          );
        }
        final changes = SavedChanges(
          session: widget.session,
          universe: widget.universe,
          scope: widget.scope,
        );
        final saved = await changes.editWorldFields(
          _editingDraft!,
          widget.operationIndex!,
          selector: entered.selector,
          settingType: entered.settingType,
          englishLabel: entered.labels['en'] ?? '',
        );
        if (!mounted) return;
        setState(() {
          _editingDraft = saved;
          _savedDraft = saved;
          _base = UnfinishedWorldForm(
            baseRevision: entered.baseRevision,
            representedContext: entered.representedContext,
            record: entered.record,
            selector: entered.selector,
            settingType: entered.settingType,
            rationale: entered.rationale,
            aliases: entered.aliases,
            labels: entered.labels,
            draftVersion: saved.version,
          );
          _dirty = true;
          _added =
              'World updated in saved changes. Return to Changes to review it.';
        });
        await _save();
        return;
      }
      final loaded = await widget.session.call(
        LoadDraftEngineRequest(
          universe: widget.universe,
          continuityId: widget.scope.continuity,
        ),
      );
      final previous = loaded is CanonicalNull
          ? null
          : SavedDraft.fromWire(loaded);
      if (_stale) {
        throw const FormatException(
          'Review the current published world before replacing your recovered fields.',
        );
      }
      final request = widget.publishedWorld == null
          ? worldDraftRequest(
              universe: widget.universe,
              continuity: widget.scope.continuity,
              form: entered,
              previous: previous,
            )
          : (widget.addAlias
                ? worldAliasDraftRequest
                : renameWorldDraftRequest)(
              universe: widget.universe,
              universeId: widget.scope.universe,
              continuity: widget.scope.continuity,
              form: entered,
              previous: previous,
            );
      if (previous?.content.toWire().toText() !=
          request.content.toWire().toText()) {
        SavedDraft.fromWire(await widget.session.call(request));
      }
      if (mounted) {
        setState(() {
          _added = widget.publishedWorld == null
              ? 'World added to saved changes. Open Changes to review its current proposal and publication status.'
              : widget.addAlias
              ? 'World alias added to saved changes. Open Changes to review and publish it.'
              : 'World rename added to saved changes. Open Changes to review and publish it.';
        });
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = _editingDraft == null
              ? 'Could not confirm adding this world. Your fields remain saved. Try again to check the saved changes before adding.'
              : 'Could not confirm saving this edit. Your fields remain saved. Another window may have changed the draft; return to Changes to check it.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _adding = false;
        });
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Semantics(
      label: label,
      child: TextField(
        controller: controller,
        enabled: _base != null && !_loading && !_adding,
        maxLines: lines,
        decoration: InputDecoration(labelText: label),
        onChanged: _changed,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: widget.editingDraft == null && !_dirty && !_saving && !_adding,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.publishedWorld != null
              ? (widget.addAlias ? 'Add world alias' : 'Rename world')
              : widget.editingDraft == null
              ? 'World draft'
              : 'Edit world in changes',
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.continuity?.name ?? 'Saved changes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (widget.representedContext != null)
                Text(
                  'Context: ${representedContextName(widget.representedContext!)}',
                ),
              const SizedBox(height: 12),
              const Text(
                'Unfinished work stays on this device. Saving here does not change canon.',
              ),
              const SizedBox(height: 24),
              if (_loading || _saving || _adding)
                const LinearProgressIndicator(),
              _field(_name, widget.addAlias ? 'Alias' : 'World name'),
              if (widget.publishedWorld == null) ...[
                _field(_label, 'Display label (English, optional)'),
                _field(_setting, 'Setting type (optional)'),
              ],
              if (widget.editingDraft == null)
                _field(_rationale, 'Notes and rationale', lines: 4),
              if (_base != null &&
                  widget.continuity != null &&
                  _base!.baseRevision != widget.continuity!.revisionId)
                const Text(
                  'Saved work uses an earlier revision. Review it before adding it to a proposal.',
                ),
              if (_stale) ...[
                Text(
                  widget.publishedWorld == null
                      ? 'Your recovered fields belong to an earlier draft. They have not replaced the current saved world.'
                      : 'Your recovered fields use an earlier record or revision. The published world has not changed.',
                ),
                TextButton(
                  onPressed: _saving || _adding ? null : _replacePendingFields,
                  child: Text(
                    widget.publishedWorld == null
                        ? 'Replace unfinished fields with current saved world'
                        : 'Replace unfinished fields with current published world',
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              Text(
                _saving
                    ? 'Saving…'
                    : _dirty
                    ? 'Unsaved fields'
                    : _generation > BigInt.zero
                    ? 'Saved on this device'
                    : 'No saved fields yet',
              ),
              const SizedBox(height: 20),
              if (_added != null)
                Semantics(liveRegion: true, child: Text(_added!)),
              if (_added != null &&
                  widget.editingDraft == null &&
                  widget.publishedWorld == null)
                TextButton(
                  onPressed: _saving || _adding || _dirty
                      ? null
                      : _startAnotherWorld,
                  child: const Text('Start another world'),
                ),
              if (_added != null && widget.editingDraft == null)
                TextButton(
                  onPressed: _saving || _adding
                      ? null
                      : () async {
                          if (_dirty) await _save();
                          if (!mounted || _dirty || _saving) return;
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => ChangesPage(
                                changes: SavedChanges(
                                  session: widget.session,
                                  universe: widget.universe,
                                  scope: widget.scope,
                                ),
                              ),
                            ),
                          );
                        },
                  child: const Text('Review saved changes'),
                ),
              if (_base != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _saving || _adding || _stale ? null : _add,
                      child: Text(
                        widget.publishedWorld != null
                            ? (widget.addAlias
                                  ? 'Add alias to changes'
                                  : 'Add rename to changes')
                            : widget.editingDraft == null
                            ? 'Add to changes'
                            : 'Save world changes',
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: _base == null
                    ? FilledButton(
                        onPressed: _loading ? null : _load,
                        child: const Text('Retry'),
                      )
                    : FilledButton(
                        onPressed: _saving || _adding || !_dirty ? null : _save,
                        child: const Text('Save unfinished work'),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
