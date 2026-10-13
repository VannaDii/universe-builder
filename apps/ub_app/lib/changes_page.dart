import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';

class ChangesPage extends StatefulWidget {
  const ChangesPage({super.key, required this.changes});
  final SavedChanges changes;
  @override
  State<ChangesPage> createState() => _ChangesPageState();
}

class _ChangesPageState extends State<ChangesPage> {
  SavedDraft? _draft;
  Proposal? _proposal;
  Map<RecordId, RecordVersion> _before = {};
  bool _busy = true;
  String? _error;
  final _rationale = TextEditingController();
  bool _rationaleDirty = false;
  @override
  void dispose() {
    _rationale.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _draft = null;
      _proposal = null;
      _before = {};
    });
    try {
      final draft = await widget.changes.load();
      final proposal = draft == null
          ? null
          : await widget.changes.recover(draft);
      final before = proposal == null
          ? <RecordId, RecordVersion>{}
          : await widget.changes.before(proposal);
      if (mounted) {
        setState(() {
          _draft = draft;
          _proposal = proposal;
          _before = before;
          _rationale.text = draft?.content.rationale ?? '';
          _rationaleDirty = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not open saved changes. Check your connection and access, then try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_rationaleDirty) await _saveRationale();
    if (!mounted || _rationaleDirty) return;
    final draft = _draft;
    if (draft == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final proposal = await widget.changes.submit(draft);
      final before = await widget.changes.before(proposal);
      final saved = await widget.changes.load();
      if (saved?.content.proposal !=
          ProposalRef(
            proposalId: proposal.proposalId,
            version: proposal.version,
            digest: proposal.digest,
          )) {
        throw const FormatException(
          'Saved changes have changed. Reload before continuing.',
        );
      }
      if (mounted) {
        setState(() {
          _proposal = proposal;
          _before = before;
          _draft = saved;
        });
      }
    } on InvalidArgumentError catch (error) {
      if (mounted) {
        setState(() {
          _error = error.field.contains('rationale')
              ? 'Add a rationale explaining these changes, save it, then submit the proposal.'
              : 'The proposal contains an invalid value. Your saved changes remain; review the entered fields.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not confirm submission. Your saved changes remain. Check saved changes before trying again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _saveRationale() async {
    final draft = _draft;
    if (draft == null || _busy || !_rationaleDirty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.changes.saveRationale(draft, _rationale.text);
      if (mounted) {
        setState(() {
          _draft = saved;
          _rationaleDirty = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not save the rationale. Your text is still here. Another window may have saved newer changes; check before replacing work.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_rationaleDirty) await _saveRationale();
    if (!mounted || _busy || _rationaleDirty) return;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && !_busy && !_rationaleDirty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final operations =
        _proposal?.operations ?? _draft?.content.operations ?? [];
    return PopScope(
      canPop: !_busy && !_rationaleDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Changes')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_busy) const LinearProgressIndicator(),
                Text(
                  _proposal == null ? 'Saved changes' : 'Submitted proposal',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Canon stays unchanged until you review, approve and publish separately.',
                ),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (_draft == null && !_busy && _error == null)
                  const Text('No saved changes in this continuity.'),
                if (_draft != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Rationale',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_proposal == null) ...[
                    TextField(
                      controller: _rationale,
                      enabled: !_busy,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Rationale'),
                      onChanged: (_) => setState(() {
                        _rationaleDirty = true;
                      }),
                    ),
                    TextButton(
                      onPressed: _busy || !_rationaleDirty
                          ? null
                          : _saveRationale,
                      child: const Text('Save rationale'),
                    ),
                  ] else
                    SelectableText(
                      _proposal?.rationale ?? _draft!.content.rationale,
                    ),
                  const SizedBox(height: 20),
                  for (var index = 0; index < operations.length; index++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Change ${index + 1}: ${operations[index].kind.wireName.replaceAll('_', ' ')}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (operations[index] case CreateWorldOperation(
                              :final record,
                            )) ...[
                              const Text('Before: no world'),
                              const Text('After'),
                              _ExactFields(value: record.toWire()),
                            ] else
                              _ExactFields(value: operations[index].toWire()),
                          ],
                        ),
                      ),
                    ),
                  if (_proposal != null) ...[
                    const SizedBox(height: 16),
                    const Text('Compiled record changes'),
                    for (final change in _proposal!.compiledChanges)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                'Record: ${change.recordId.value}',
                              ),
                              const Text('Before'),
                              if (change.expected == null)
                                const Text('No record')
                              else
                                _ExactFields(
                                  value: _before[change.recordId]!.payload
                                      .toWire(),
                                ),
                              const Text('After'),
                              if (change.next == null)
                                const Text('After: removed')
                              else
                                _ExactFields(
                                  value: change.next!.payload.toWire(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ExpansionTile(
                      title: const Text('Revision and proposal details'),
                      children: [
                        SelectableText(
                          'Base revision: ${_proposal!.baseFrame.revision.value}',
                        ),
                        SelectableText(
                          'Represented context: ${_proposal!.baseFrame.context.record.value}',
                        ),
                        SelectableText(
                          'Proposal: ${_proposal!.proposalId.value} · version ${_proposal!.version}',
                        ),
                        SelectableText('Digest: ${_proposal!.digest}'),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: _busy || _rationaleDirty ? null : _load,
                      child: const Text('Check saved changes'),
                    ),
                    if (_draft != null &&
                        _proposal == null &&
                        operations.isNotEmpty)
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: const Text('Submit proposal'),
                      ),
                    if (_draft != null &&
                        _proposal != null &&
                        _draft!.content.proposal == null)
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: const Text('Save proposal with changes'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only field layout retains all nested values without a raw JSON editor.
class _ExactFields extends StatelessWidget {
  const _ExactFields({required this.value});
  final CanonicalValue value;
  @override
  Widget build(BuildContext context) => switch (value) {
    CanonicalObject(:final fields) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fields.isEmpty) const Text('None'),
        for (final field in fields)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(switch (field.key) {
                  'selector' => 'World name',
                  'settingType' => 'Setting type',
                  'labels' => 'Display labels',
                  'aliases' => 'Other names',
                  'metadata' => 'Additional details',
                  'kind' || 'record_kind' => 'Record type',
                  _ => field.key.replaceAll('_', ' '),
                }, style: Theme.of(context).textTheme.labelLarge),
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _ExactFields(value: field.value),
                ),
              ],
            ),
          ),
      ],
    ),
    CanonicalArray(:final items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty) const Text('None'),
        for (var index = 0; index < items.length; index++)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${index + 1}. '),
                Expanded(child: _ExactFields(value: items[index])),
              ],
            ),
          ),
      ],
    ),
    CanonicalString(:final value) => SelectableText(
      value.isEmpty ? '(empty)' : value,
    ),
    CanonicalNumber(:final digits) => SelectableText(digits),
    CanonicalBool(:final value) => Text(value ? 'Yes' : 'No'),
    CanonicalNull() => const Text('Not set'),
  };
}
