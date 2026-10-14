import 'dart:async';

import 'guarded_pop_scope.dart';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'appearance_draft.dart';
import 'saved_changes.dart';
import 'appearance_input_fields.dart';

class AppearanceEditorPage extends StatefulWidget {
  const AppearanceEditorPage({
    super.key,
    required this.changes,
    required this.revision,
    this.editingDraft,
    this.index,
    this.correctionRecord,
  });
  final SavedChanges changes;
  final RevisionId revision;
  final SavedDraft? editingDraft;
  final int? index;
  final RecordVersion? correctionRecord;
  @override
  State<AppearanceEditorPage> createState() => _AppearanceEditorPageState();
}

class _AppearanceEditorPageState extends State<AppearanceEditorPage> {
  UnfinishedAppearanceForm? _form;
  SavedDraft? _draft, _result;
  BigInt _generation = BigInt.zero;
  bool _loading = true,
      _saving = false,
      _adding = false,
      _dirty = false,
      _stale = false,
      _leaving = false,
      _picking = false;
  String? _error, _added;
  Timer? _autosave;
  int _fields = 0;
  bool get _disabled =>
      _loading ||
      _adding ||
      _picking ||
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

  UnfinishedAppearanceForm _fresh() => widget.index != null
      ? appearanceFormFromDraft(_draft!, widget.index!)
      : widget.correctionRecord != null
      ? appearanceFormFromRecord(
          record: widget.correctionRecord!,
          baseRevision: widget.revision,
          representedContext: _scope.representedContext!,
        )
      : UnfinishedAppearanceForm(
          baseRevision: widget.revision,
          representedContext: _scope.representedContext!,
          clientRef: RecordId.generate().value,
        );
  UnfinishedAppearanceForm _cachedPreviews(
    UnfinishedAppearanceForm form,
    UnfinishedAppearanceForm cached,
  ) => form.copyWith(
    images: form.images.map((image) {
      final match = cached.images
          .where(
            (old) =>
                old.preview.isNotEmpty &&
                old.asset.toWire().toText() == image.asset.toWire().toText() &&
                old.stagedOperation?.toWire().toText() ==
                    image.stagedOperation?.toWire().toText(),
          )
          .firstOrNull;
      return AppearanceImageInput(
        asset: image.asset,
        caption: image.caption,
        purpose: image.purpose,
        stagedOperation: image.stagedOperation,
        preview: match?.preview ?? image.preview,
      );
    }),
  );
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _draft = widget.editingDraft ?? await widget.changes.load();
      final saved = await widget.changes.session.loadAppearanceForm(_scope);
      var opened = saved?.form ?? _fresh();
      var retainCache = false;
      if (saved == null &&
          widget.index != null &&
          opened.revisionTarget == null) {
        final source = await widget.changes.session.loadAppearanceForm(
          EditorFormScope(
            instance: _scope.instance,
            profile: _scope.profile,
            universe: _scope.universe,
            continuity: _scope.continuity,
            representedContext: _scope.representedContext,
          ),
        );
        if (source != null &&
            source.form.clientRef == opened.clientRef &&
            source.form.baseRevision == opened.baseRevision) {
          final withCache = _cachedPreviews(opened, source.form);
          retainCache = withCache.toWire().toText() != opened.toWire().toText();
          opened = withCache;
        }
      }
      if (!mounted) return;
      setState(() {
        _form = opened;
        _generation = saved?.generation ?? BigInt.zero;
        _fields++;
        _dirty = retainCache;
        _stale = widget.index != null
            ? _form!.draftVersion != _draft!.version ||
                  _form!.baseRevision != _draft!.content.baseRevision ||
                  _form!.representedContext !=
                      _draft!.content.representedContext
            : _form!.baseRevision != widget.revision ||
                  (widget.correctionRecord != null &&
                      _form!.expectedRecordVersion !=
                          widget.correctionRecord!.recordVersionId);
        _added =
            widget.index == null &&
                (_draft?.content.operations.any(
                      (op) =>
                          (op is CreateAppearanceOperation &&
                              _form!.revisionTarget == null &&
                              op.clientRef == _form!.clientRef) ||
                          (op is ReviseAppearanceOperation &&
                              _form!.revisionTarget?.record ==
                                  op.record.record.value &&
                              _form!.revisionTarget?.universe ==
                                  (op.record.universe?.value ?? '')),
                    ) ??
                    false)
            ? 'This appearance is in Changes. Review or edit it there.'
            : null;
      });
      if (retainCache) await _save();
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open the appearance form. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change(UnfinishedAppearanceForm form) {
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
      final saved = await widget.changes.session.saveAppearanceForm(
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
      final request = appearanceDraftRequest(
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
                    op is ReviseAppearanceOperation &&
                    op.record ==
                        (appearanceOperation(
                          _form!,
                        ) as ReviseAppearanceOperation).record,
              );
          final prior = _form!;
          final updated = appearanceFormFromDraft(saved, index);
          _form = _cachedPreviews(updated, prior);
          _fields++;
          _dirty = true;
        } else {
          _added = 'Appearance added to Changes. Review it before publication.';
        }
      });
      await _save();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm saving the appearance. Check Changes before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _pickImage() async {
    if (_disabled || _picking) return;
    _autosave?.cancel();
    await _save();
    if (!mounted || _dirty) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final image = await widget.changes.session.pickImage!(
        widget.changes.universe,
      );
      if (!mounted || image == null) return;
      _change(
        _form!.copyWith(
          images: [
            ..._form!.images,
            AppearanceImageInput.staged(image, _scope.universe),
          ],
        ),
      );
      await _save();
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm retaining the image. Reconnect before retrying; your existing fields remain.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _leave() async {
    if (_loading || _saving || _adding || _picking) return;
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
    onBackground: _save,
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.index == null ? 'Appearance' : 'Edit appearance'),
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
                  'Describe a universe or a named entry at an authored phase. Images and depiction links remain descriptive; they do not assert facts or advance time. These fields remain unfinished until added to Changes.',
                ),
                if (_loading || _saving || _adding || _picking)
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
                  AppearanceInputFields(
                    key: ValueKey((_fields, 'appearance')),
                    form: f,
                    changes: widget.changes,
                    draft: _choices,
                    disabled: _disabled,
                    onChanged: _change,
                    onPickImage: widget.changes.session.pickImage == null
                        ? null
                        : _pickImage,
                  ),
                  if (widget.index == null || f.revisionTarget != null)
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
                          : 'Save appearance changes',
                    ),
                  ),
                  TextButton(
                    onPressed:
                        _loading || _saving || _adding || _picking || !_dirty
                        ? null
                        : _save,
                    child: const Text('Save unfinished work'),
                  ),
                  if (_added != null)
                    TextButton(
                      onPressed: _loading || _saving || _adding || _picking
                          ? null
                          : _reset,
                      child: const Text('Start another appearance'),
                    ),
                  TextButton(
                    onPressed: _loading || _saving || _adding || _picking
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
                    onPressed: _loading || _saving || _adding || _picking
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
