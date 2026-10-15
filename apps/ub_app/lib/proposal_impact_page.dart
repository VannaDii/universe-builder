import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;

import 'proposal_impact.dart';
import 'record_fields.dart';
import 'saved_changes.dart';

class ProposalImpactPage extends StatefulWidget {
  const ProposalImpactPage({
    super.key,
    required this.changes,
    required this.proposal,
  });
  final SavedChanges changes;
  final Proposal proposal;
  @override
  State<ProposalImpactPage> createState() => _ProposalImpactPageState();
}

class _ProposalImpactPageState extends State<ProposalImpactPage> {
  ProposalImpactSnapshot? _snapshot;
  List<ProposalImpactRecord> _records = [];
  int _offset = 0;
  bool _busy = true;
  String? _error;
  static const _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _records = [];
      _snapshot = null;
    });
    try {
      final snapshot = await readProposalImpact(
        widget.changes,
        widget.proposal,
      );
      final offset = _offset < snapshot.impact.records.length ? _offset : 0;
      final records = await snapshot.page(widget.changes, offset: offset);
      if (mounted) {
        setState(() {
          _offset = offset;
          _snapshot = snapshot;
          _records = records;
        });
      }
    } on EvaluationLimitReachedError {
      if (mounted) {
        setState(
          () => _error = 'The service could not return the complete impact within its response limit. No complete impact result is available.',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not read this proposal’s impact. Check the connection and current access; reconnect before retrying an interrupted request.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _page(int offset) async {
    if (_busy) return;
    setState(() {
      _offset = offset;
      _busy = true;
      _error = null;
      _records = [];
    });
    try {
      final records = await _snapshot!.page(widget.changes, offset: offset);
      if (mounted) setState(() => _records = records);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not read this page at the proposal’s revision. Retry after checking the connection and access.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Proposal impact')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'The service uses a conservative review scope that includes every accessible record at this proposal’s revision. Changes can affect conclusions based on missing facts and counts, so the scope can be broader than the actual changes.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Proposed changes are marked below. Other entries are included for review. Checking impact leaves validation, approval and publication to their separate actions in Changes.',
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_snapshot case final snapshot?) ...[
              const SizedBox(height: 16),
              Text('Coverage: ${snapshot.impact.coverage.wireName}'),
              if (snapshot.impact.coverage != Coverage.complete)
                const Text(
                  'This result has limited coverage for full-universe review. Inaccessible records and names remain undisclosed.',
                ),
              Text(
                '${snapshot.impact.records.length} records included in the review scope',
              ),
              Text(
                '${snapshot.impact.worldIds.length} accessible worlds represented',
              ),
              if (snapshot.impact.records.isEmpty)
                const Text('No records were returned for this impact result.'),
              if (_records.isNotEmpty)
                Text('Showing ${_offset + 1}–${_offset + _records.length}'),
              if (snapshot.impact.records.length > _pageSize)
                _pagination(snapshot),
              for (final row in _records)
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            row.change != null
                                ? row.change!.next == null
                                      ? 'Proposed removal'
                                      : 'Proposed change'
                                : 'Included for review · ${row.summary?.kind.wireName.replaceAll('_', ' ') ?? 'record'}',
                          ),
                          if (row.change?.next case final record?)
                            ExpansionTile(
                              title: const Text('Proposed record fields'),
                              children: [
                                ExactFields(value: record.payload.toWire()),
                              ],
                            ),
                          ExpansionTile(
                            title: const Text('Record reference'),
                            children: [SelectableText(row.id.value)],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (snapshot.impact.records.length > _pageSize)
                _pagination(snapshot),
            ],
            if (_error != null)
              TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Retry impact'),
              ),
            ExpansionTile(
              title: const Text('Proposal and revision'),
              children: [
                SelectableText(
                  'Proposal: ${widget.proposal.proposalId.value} · version ${widget.proposal.version}',
                ),
                SelectableText(
                  'Base revision: ${widget.proposal.baseFrame.revision.value}',
                ),
                SelectableText('Digest: ${widget.proposal.digest}'),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _pagination(ProposalImpactSnapshot snapshot) => Wrap(
    spacing: 8,
    children: [
      TextButton(
        onPressed: _busy || _offset == 0
            ? null
            : () => _page(_offset - _pageSize),
        child: const Text('Previous records'),
      ),
      TextButton(
        onPressed:
            _busy || _offset + _pageSize >= snapshot.impact.records.length
            ? null
            : () => _page(_offset + _pageSize),
        child: const Text('Next records'),
      ),
    ],
  );
}
