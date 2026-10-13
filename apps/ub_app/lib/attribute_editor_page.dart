import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'attribute_draft.dart';
import 'record_fields.dart';
import 'saved_changes.dart';
import 'value_input_fields.dart';

class AttributeEditorPage extends StatefulWidget {
  const AttributeEditorPage({
    super.key,
    required this.changes,
    required this.draft,
    required this.index,
  });
  final SavedChanges changes;
  final SavedDraft draft;
  final int index;
  @override
  State<AttributeEditorPage> createState() => _AttributeEditorPageState();
}

class _AttributeEditorPageState extends State<AttributeEditorPage> {
  late SavedDraft _draft;
  UnfinishedAttributeForm? _form;
  BigInt _generation = BigInt.zero;
  bool _loading = true,
      _saving = false,
      _updating = false,
      _dirty = false,
      _leaving = false,
      _stale = false;
  String? _error, _updated;
  Timer? _autosave;
  SavedDraft? _result;
  late EditorFormScope _scope;
  bool get _disabled => _loading || _saving || _updating || _form == null;
  AddNamedAttributeOperation get _source =>
      _draft.content.operations[widget.index] as AddNamedAttributeOperation;
  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    final scope = widget.changes.scope;
    _scope = EditorFormScope(
      instance: scope.instance,
      profile: scope.profile,
      universe: scope.universe,
      continuity: scope.continuity,
      representedContext: _draft.content.representedContext,
      attributeClientRef: _source.clientRef,
    );
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await widget.changes.session.loadAttributeForm(_scope);
      if (!mounted) return;
      final form = saved?.form ?? attributeFormFromDraft(_draft, widget.index);
      setState(() {
        _form = form;
        _generation = saved?.generation ?? BigInt.zero;
        _dirty = false;
        _stale =
            form.draftVersion != _draft.version ||
            form.baseRevision != _draft.content.baseRevision ||
            form.representedContext != _draft.content.representedContext;
      });
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open the saved fields. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change(QualifierInput value) {
    final old = _form!;
    setState(() {
      _form = UnfinishedAttributeForm(
        baseRevision: old.baseRevision,
        representedContext: old.representedContext,
        clientRef: old.clientRef,
        draftVersion: old.draftVersion,
        value: value,
      );
      _dirty = true;
      _updated = null;
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
      final saved = await widget.changes.session.saveAttributeForm(
        _scope,
        _form!,
        _generation,
      );
      if (mounted) {
        setState(() {
          _form = saved.form;
          _generation = saved.generation;
          _dirty = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not save these fields. Another window may have changed them. Your input remains here.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _useCurrent() async {
    _autosave?.cancel();
    setState(() {
      _form = attributeFormFromDraft(_draft, widget.index);
      _stale = false;
      _dirty = true;
      _updated = null;
    });
    await _save();
  }

  Future<void> _update() async {
    _autosave?.cancel();
    await _save();
    if (!mounted || _dirty || _form == null || _stale) return;
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      final content = replaceDraftAttribute(
        draft: _draft,
        index: widget.index,
        form: _form!,
      );
      final saved = await widget.changes.saveContent(_draft, content);
      if (!mounted) return;
      setState(() {
        _draft = saved;
        _result = saved;
        _form = attributeFormFromDraft(saved, widget.index);
        _dirty = true;
        _updated = 'Attribute value updated in saved changes. Return to Changes to review it.';
      });
      await _save();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm saving the attribute. Your entered fields remain saved. Check Changes before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _leave() async {
    if (_loading || _saving || _updating) return;
    _autosave?.cancel();
    await _save();
    if (!mounted || _dirty || _saving) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(_result);
  }

  @override
  Widget build(BuildContext context) => PopScope<SavedDraft>(
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Edit attribute value')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '${_source.namespace}: ${_source.key}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Unfinished value edits stay on this device. The property definition and authored evidence remain intact. Save into Changes for review before publication.',
              ),
              if (_loading || _saving || _updating)
                const LinearProgressIndicator(),
              if (_stale) ...[
                const Text(
                  'Recovered edits belong to an earlier draft. Use current draft fields before saving changes.',
                ),
                TextButton(
                  onPressed: _disabled ? null : _useCurrent,
                  child: const Text('Use current draft fields'),
                ),
              ],
              if (_form != null)
                ValueInputFields(
                  input: _form!.value,
                  original: _source.value,
                  disabled: _disabled,
                  label: 'Attribute value',
                  onChanged: _change,
                ),
              ExpansionTile(
                title: const Text('Original attribute and evidence'),
                children: [ExactFields(value: _source.toWire())],
              ),
              Text(
                _dirty
                    ? 'Unsaved fields'
                    : _generation == BigInt.zero
                    ? 'No saved fields yet'
                    : 'Saved on this device',
              ),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
              if (_updated != null)
                Semantics(liveRegion: true, child: Text(_updated!)),
              FilledButton(
                onPressed: _disabled || _stale ? null : _update,
                child: const Text('Save attribute changes'),
              ),
              TextButton(
                onPressed: _disabled || !_dirty ? null : _save,
                child: const Text('Save unfinished work'),
              ),
              if (_error != null)
                TextButton(
                  onPressed: _loading || _saving || _updating ? null : _load,
                  child: const Text('Reload saved fields'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
