import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart' show RecordId, CanonicalNull;

import 'connection.dart';
import 'world_draft.dart';
import 'changes_page.dart';
import 'saved_changes.dart';

class WorldEditorPage extends StatefulWidget {
  const WorldEditorPage({
    super.key,
    required this.session,
    required this.scope,
    required this.continuity,
    required this.universe,
  });
  final AppSession session;
  final EditorFormScope scope;
  final ContinuitySummary continuity;
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
  String? _error;
  String? _added;
  Timer? _autosave;

  @override
  void initState() {
    super.initState();
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
      final form =
          saved?.form ??
          UnfinishedWorldForm(
            baseRevision: widget.continuity.revisionId,
            representedContext: widget.continuity.representedContexts.single.id,
            record: RecordId.generate(),
            selector: '',
            settingType: '',
            rationale: '',
          );
      setState(() {
        _base = form;
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

  UnfinishedWorldForm get _form => UnfinishedWorldForm(
    baseRevision: _base!.baseRevision,
    representedContext: _base!.representedContext,
    record: _base!.record,
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
    if (mounted && !_dirty && !_saving && !_adding) Navigator.of(context).pop();
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
      final loaded = await widget.session.call(
        LoadDraftEngineRequest(
          universe: widget.universe,
          continuityId: widget.scope.continuity,
        ),
      );
      final previous = loaded is CanonicalNull
          ? null
          : SavedDraft.fromWire(loaded);
      final request = worldDraftRequest(
        universe: widget.universe,
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
          _added = 'Added to saved changes. Canon is unchanged. Proposal review is still required.';
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
          _error = 'Could not confirm adding this world. Your fields remain saved. Try again to check the saved changes before adding.';
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
    canPop: !_dirty && !_saving && !_adding,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('World draft')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.continuity.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Unfinished work stays on this device. Saving here does not change canon.',
              ),
              const SizedBox(height: 24),
              if (_loading || _saving || _adding)
                const LinearProgressIndicator(),
              _field(_name, 'World name'),
              _field(_label, 'Display label (English, optional)'),
              _field(_setting, 'Setting type (optional)'),
              _field(_rationale, 'Notes and rationale', lines: 4),
              if (_base != null &&
                  _base!.baseRevision != widget.continuity.revisionId)
                const Text(
                  'Saved work uses an earlier revision. Review it before adding it to a proposal.',
                ),
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
              if (_added != null)
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
                      onPressed: _saving || _adding ? null : _add,
                      child: const Text('Add to changes'),
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
