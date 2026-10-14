import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'continuity_draft.dart';
import 'changes_page.dart';

class ContinuityPage extends StatefulWidget {
  const ContinuityPage({
    super.key,
    required this.changes,
    required this.target,
    required this.continuities,
  });
  final SavedChanges changes;
  final ContinuitySummary target;
  final List<ContinuitySummary> continuities;
  @override
  State<ContinuityPage> createState() => _ContinuityPageState();
}

class _ContinuityPageState extends State<ContinuityPage> {
  final _name = TextEditingController(), _rationale = TextEditingController();
  late ContinuitySummary _target;
  late List<ContinuitySummary> _continuities;
  ContinuitySummary? _source;
  ForkContinuityEngineRequest? _forkRequest;
  List<ContinuityDifference>? _differences;
  final _selected = <RecordId>{};
  bool _busy = false;
  String? _error, _message;
  @override
  void initState() {
    super.initState();
    _target = widget.target;
    _continuities = widget.continuities;
  }

  @override
  void dispose() {
    _name.dispose();
    _rationale.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final description = Envelope<Description>.fromWire(
      await widget.changes.session.call(
        ToolEngineRequest(
          request: DescribeSummaryRequest(universe: widget.changes.universe),
        ),
      ),
      Description.fromWire,
    ).result;
    final target = description.continuities
        .where((c) => c.id == _target.id)
        .firstOrNull;
    if (target == null) {
      throw const FormatException('The target continuity is unavailable.');
    }
    if (!mounted) return;
    setState(() {
      _continuities = description.continuities;
      _target = target;
      _source = _continuities.where((c) => c.id == _source?.id).firstOrNull;
      _differences = null;
      _selected.clear();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm this action. Retry with the same selection or refresh the library.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fork() async {
    if (_forkRequest == null) {
      if (_name.text.trim().isEmpty) {
        throw const FormatException('Enter a continuity name.');
      }
      _forkRequest = ForkContinuityEngineRequest(
        universe: widget.changes.universe,
        name: _name.text,
        continuityId: ContinuityId.generate(),
        source: _target.id,
        revision: _target.revisionId,
      );
    }
    final request = _forkRequest!;
    final result = WireFields(await widget.changes.session.call(request), {
      'continuity_id',
      'revision',
    });
    if (result.string('continuity_id') != request.continuityId.value) {
      throw const FormatException(
        'Unexpected continuity response. Refresh the library.',
      );
    }
    await _refresh();
    if (!mounted) return;
    setState(() {
      _message =
          'Created ${request.name} from the selected edition of ${_target.name}.';
      _forkRequest = null;
      _name.clear();
    });
  }

  Future<void> _compare() async {
    final source = _source;
    if (source == null) {
      throw const FormatException('Choose a source continuity.');
    }
    final differences = await compareContinuities(
      widget.changes,
      _target,
      source,
    );
    if (mounted) {
      setState(() {
        _differences = differences;
        _selected.clear();
      });
    }
  }

  Future<void> _stage() async {
    final source = _source;
    if (source == null) {
      throw const FormatException('Choose a source continuity.');
    }
    await stageContinuityAdoption(
      changes: widget.changes,
      target: _target,
      source: source,
      selected: _selected,
      rationale: _rationale.text,
    );
    if (mounted) {
      setState(
        () => _message = 'Selected changes are in target Changes. Review, approve and publish separately.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Continuities'),
      leading: BackButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
      ),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Target: ${_target.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Branch an alternate continuity or bring selected changes into this one. Comparing and preparing changes do not publish canon.',
              ),
              ExpansionTile(
                title: const Text('Selected editions'),
                children: [
                  SelectableText(
                    'Target edition: ${_target.revisionId.value}\n${_source == null ? 'No source selected' : 'Source edition: ${_source!.revisionId.value}'}',
                  ),
                ],
              ),
              TextButton(
                onPressed: _busy ? null : () => _run(_refresh),
                child: const Text('Refresh editions'),
              ),
              const Divider(),
              const Text('Create an alternate continuity'),
              TextField(
                controller: _name,
                enabled: !_busy && _forkRequest == null,
                decoration: const InputDecoration(
                  labelText: 'New continuity name',
                ),
              ),
              FilledButton(
                onPressed: _busy ? null : () => _run(_fork),
                child: Text(
                  _forkRequest == null
                      ? 'Create from this edition'
                      : 'Retry the same creation',
                ),
              ),
              if (_forkRequest != null)
                const Text(
                  'The creation identity and source edition are retained for retry.',
                ),
              const Divider(),
              const Text('Compare and select changes'),
              DropdownButtonFormField<ContinuityId>(
                key: ValueKey((_target.revisionId, _source?.id)),
                initialValue: _source?.id,
                decoration: const InputDecoration(
                  labelText: 'Source continuity',
                ),
                items: [
                  for (final c in _continuities)
                    if (c.id != _target.id)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: _busy
                    ? null
                    : (id) {
                        setState(() {
                          _source = _continuities
                              .where((c) => c.id == id)
                              .firstOrNull;
                          _differences = null;
                          _selected.clear();
                        });
                      },
              ),
              FilledButton(
                onPressed: _busy || _source == null
                    ? null
                    : () => _run(_compare),
                child: const Text('Compare these editions'),
              ),
              if (_differences case final differences?) ...[
                Text(
                  '${differences.length} differences · ${_selected.length} selected',
                ),
                if (differences.isEmpty)
                  const Text('No record differences in these editions.'),
                for (final difference in differences)
                  Card(
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: _selected.contains(difference.record),
                          title: Text(difference.label),
                          subtitle: Text(
                            '${difference.kind.wireName.replaceAll('_', ' ')} · ${difference.change}',
                          ),
                          onChanged: _busy
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      if (_selected.length >= 100) {
                                        _error = 'Select at most 100 changes at a time.';
                                        return;
                                      }
                                      _selected.add(difference.record);
                                    } else {
                                      _selected.remove(difference.record);
                                    }
                                  });
                                },
                        ),
                        ExpansionTile(
                          title: const Text('Version details'),
                          children: [
                            SelectableText(
                              'Record: ${difference.record.value}\nTarget: ${difference.targetVersion?.value ?? 'absent'}\nSource: ${difference.sourceVersion?.value ?? 'absent'}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const Text(
                  'A source absence proposes a removal from the target. Selection order is preserved. Review dependencies and any conflicts in Changes.',
                ),
                TextField(
                  controller: _rationale,
                  enabled: !_busy,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Rationale for selected changes',
                  ),
                ),
                FilledButton(
                  onPressed: _busy || _selected.isEmpty
                      ? null
                      : () => _run(_stage),
                  child: const Text('Add selected changes to target Changes'),
                ),
              ],
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await Navigator.of(context)
                            .push<void>(changesRoute(widget.changes));
                        if (mounted) await _run(_refresh);
                      },
                child: const Text('Review target Changes'),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Semantics(liveRegion: true, child: Text(_message!)),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
            ],
          ),
        ),
      ),
    ),
  );
}
