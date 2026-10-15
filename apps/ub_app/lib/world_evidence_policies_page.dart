import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'evidence_policy_view.dart';
import 'evidence_review_summary.dart';
import 'record_browser.dart';
import 'record_browser_page.dart';
import 'world_browser.dart';
import 'world_evidence_policies.dart';

class WorldEvidencePoliciesPage extends StatefulWidget {
  const WorldEvidencePoliciesPage({
    super.key,
    required this.session,
    required this.universe,
    required this.scope,
    required this.continuity,
    required this.representedContext,
    required this.world,
  });
  final AppSession session;
  final LibraryEntry universe;
  final EditorFormScope scope;
  final ContinuitySummary continuity;
  final RepresentedContextSummary representedContext;
  final WorldSummary world;
  @override
  State<WorldEvidencePoliciesPage> createState() =>
      _WorldEvidencePoliciesPageState();
}

class _WorldEvidencePoliciesPageState extends State<WorldEvidencePoliciesPage> {
  WorldEvidencePolicies? _policies;
  OpenedContext? _context;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _policies = null;
      _context = null;
    });
    try {
      final context = await openAuthorReadContext(
        widget.session,
        widget.universe,
        widget.continuity,
        widget.representedContext,
      );
      final policies = await readWorldEvidencePolicies(
        session: widget.session,
        universe: widget.universe,
        context: context,
        world: widget.world.id,
      );
      if (mounted) {
        setState(() {
          _context = context;
          _policies = policies;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not read the policies. Check your connection and access, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(WorldEvidencePolicy policy) => dossierReferenceLabel(
    Records(records: [policy.record]),
    widget.universe.id,
    RecordRef(record: policy.record.identity.recordId),
    unavailableLabel: policy.rule.key.isEmpty
        ? 'Unnamed evidence policy'
        : policy.rule.key,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Evidence policies')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          widget.world.name.value,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('Context: ${representedContextName(widget.representedContext)}'),
        const Text(
          'Policies visible to this profile at the revision opened from this world. Return and refresh the world to read later changes.',
        ),
        const Text(
          'All applicable evidence policies still apply to objective claims. Beliefs and attributed accounts retain their own meaning. Subject, predicate and time conditions determine the requirements for an individual claim; review its findings in Changes.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (_policies case final policies?) ...[
          if (!policies.complete)
            const Text(
              'This view is incomplete. Missing policy or category details may affect the requirements; retry before relying on the list.',
            ),
          if (policies.policies.isEmpty)
            const Text(
              'No required-evidence policy is visible for this world at this revision.',
            ),
          for (final policy in policies.policies)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label(policy),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(policy.originLabel),
                    EvidencePolicyView(
                      summary: EvidencePolicySummary(
                        policy.rule,
                        policies.categories,
                      ),
                    ),
                    TextButton(
                      onPressed: _busy || _context == null
                          ? null
                          : () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => RecordDetailPage(
                                  session: widget.session,
                                  universe: widget.universe,
                                  context: _context!,
                                  record: policy.record.identity.recordId,
                                  kind: RecordKind.rule,
                                  label: _label(policy),
                                  scope: widget.scope,
                                  continuity: widget.continuity,
                                  representedContext: widget.representedContext,
                                ),
                              ),
                            ),
                      child: const Text('Open policy'),
                    ),
                  ],
                ),
              ),
            ),
        ],
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('Retry policy read'),
        ),
      ],
    ),
  );
}
