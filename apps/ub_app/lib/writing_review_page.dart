import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'evidence_review_summary.dart';
import 'evidence_policy_view.dart';
import 'guarded_pop_scope.dart';
import 'record_fields.dart';
import 'source_text_editing.dart';
import 'writing_review.dart';
import 'assessment_declaration_view.dart';
import 'proposal_assessment.dart';

class WritingReviewPage extends StatefulWidget {
  const WritingReviewPage({super.key, required this.workflow});
  final WritingWorkflow workflow;
  @override
  State<WritingReviewPage> createState() => _WritingReviewPageState();
}

class _WritingReviewPageState extends State<WritingReviewPage> {
  List<WritingChoice> _choices = [];
  List<WritingApproval> _approvals = [];
  WritingChoice? _selected;
  Proposal? _proposal;
  WritingReview? _review;
  WritingApproval? _approved, _recovery;
  Map<RecordId, RecordVersion> _records = {};
  final _label = TextEditingController(),
      _text = TextEditingController(),
      _reason = TextEditingController();
  String _exactText = '';
  int? _acceptance;
  bool _busy = true, _dirty = false, _leaving = false;
  BigInt _generation = BigInt.zero;
  Timer? _autosave;
  String? _error, _status;
  WritingWorkflow get _flow => widget.workflow;

  @override
  void initState() {
    super.initState();
    _run(_refresh);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _label.dispose();
    _text.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final rows = await _flow.choices();
    if (!mounted) return;
    _choices = rows.proposals;
    _approvals = rows.approved;
    final candidate = _selected?.candidate;
    _selected = _choices.where((row) => row.candidate == candidate).firstOrNull;
    _recovery = null;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) _error = e is FormatException ? e.message.toString() : 'Could not complete this action. Check your connection and try again. For publication, recover the original approval.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    _autosave?.cancel();
    if (!_dirty || _proposal == null) return;
    final form = _flow.passage(
      _proposal!,
      label: _label.text,
      text: _exactText,
    );
    final saved = await _flow.changes.session.saveSourceForm(
      _flow.passageScope(_proposal!),
      form,
      _generation,
    );
    _generation = saved.generation;
    _dirty = false;
  }

  void _edit() {
    _exactText = kIsWeb
        ? retainBrowserSourceText(_exactText, _text.text)
        : _text.text;
    setState(() {
      _dirty = true;
      _review = null;
      _approved = null;
      _records = {};
      _acceptance = null;
      _status = null;
    });
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 500), () {
      if (!_busy && mounted) _run(_save);
    });
  }

  Future<void> _select(WritingChoice row) async {
    await _save();
    final proposal = await _flow.exact(row.candidate);
    final saved = await _flow.changes.session.loadSourceForm(
      _flow.passageScope(proposal),
    );
    if (!mounted) return;
    _selected = row;
    _proposal = proposal;
    _review = null;
    _approved = null;
    _records = {};
    _acceptance = null;
    _label.text = saved?.form.label ?? '';
    _exactText = saved?.form.text ?? '';
    _text.text = kIsWeb ? browserSourceInputText(_exactText) : _exactText;
    _generation = saved?.generation ?? BigInt.zero;
    _dirty = false;
    _status = null;
  }

  Future<void> _show(WritingReview review) async {
    if (!mounted) return;
    _review = review;
    _approved = null;
    _acceptance = null;
    _proposal = review.proposal;
    _records = review.validation is EvaluatedValidation
        ? await _flow.changes.findingRecords(
            review.proposal,
            review.validation as EvaluatedValidation,
          )
        : {};
    await _refresh();
    if (!mounted) return;
    _selected = _choices
        .where((row) => row.candidate == review.candidate)
        .firstOrNull;
    _status =
        'Read the exact passage, changes and findings. Approval is separate.';
  }

  Future<void> _prepare(bool contracts) async {
    await _save();
    _review = null;
    _approved = null;
    await _show(
      await _flow.review(
        contracts
            ? PrepareContractsWritingAction(
                candidate: _selected!.candidate.proposalId,
                label: _label.text,
                text: _exactText,
              )
            : PrepareWritingAction(
                candidate: _selected!.candidate.proposalId,
                label: _label.text,
                text: _exactText,
              ),
      ),
    );
  }

  Future<void> _publish(WritingApproval approval) async {
    final receipt = await _flow.publish(approval);
    if (!mounted) return;
    _review = null;
    _approved = null;
    _selected = null;
    _status =
        'Published revision ${receipt.revision.value}. Open the current revision to continue.';
    await _refresh();
  }

  Future<void> _leave() async {
    if (_busy) return;
    await _run(() async {
      await _save();
      if (!mounted) return;
      setState(() => _leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final author = _flow.changes.session.author;
    final review = _review;
    final selected = _selected;
    return GuardedPopScope<void>(
      canPop: _leaving,
      onLeave: _leave,
      onBackground: () async {
        if (!_busy) await _run(_save);
      },
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Writing proposals')),
        body: !author
            ? const Center(
                child: Text('Only the author can review writing proposals.'),
              )
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    'Attach your exact passage, review the findings, then approve and publish separately. Canon changes when publication succeeds.',
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (_status != null) SelectableText(_status!),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await _save();
                              await _refresh();
                            }),
                      child: const Text('Refresh proposals and approvals'),
                    ),
                  ),
                  if (_choices.isEmpty)
                    const Text(
                      'No pending writing proposals in this continuity. Use your connected writer to propose changes first.',
                    ),
                  DropdownButtonFormField<WritingChoice>(
                    key: ValueKey(selected),
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Pending proposal',
                    ),
                    items: _choices
                        .map(
                          (row) => DropdownMenuItem(
                            value: row,
                            child: Text(
                              '${row.label} · ${row.submission.wireName} · version ${row.candidate.version}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (row) {
                            if (row != null) _run(() => _select(row));
                          },
                  ),
                  TextField(
                    controller: _label,
                    enabled: !_busy && selected?.submission == Submission.draft,
                    onChanged: (_) => _edit(),
                    decoration: const InputDecoration(
                      labelText: 'Passage title',
                    ),
                  ),
                  TextField(
                    controller: _text,
                    enabled: !_busy && selected?.submission == Submission.draft,
                    onChanged: (_) => _edit(),
                    minLines: 6,
                    maxLines: 18,
                    decoration: const InputDecoration(
                      labelText: 'Exact passage',
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final contracts in [false, true])
                        OutlinedButton(
                          onPressed:
                              _busy ||
                                  selected?.submission != Submission.draft ||
                                  _exactText.trim().isEmpty
                              ? null
                              : () => _run(() => _prepare(contracts)),
                          child: Text(
                            contracts
                                ? 'Declare contracts and review passage'
                                : 'Attach passage and review facts',
                          ),
                        ),
                      OutlinedButton(
                        onPressed:
                            _busy ||
                                selected?.submission != Submission.submitted
                            ? null
                            : () => _run(() async {
                                _review = null;
                                _approved = null;
                                await _show(
                                  await _flow.review(
                                    InspectWritingAction(
                                      candidate: selected!.candidate,
                                    ),
                                  ),
                                );
                              }),
                        child: const Text('Reopen prepared review'),
                      ),
                      TextButton(
                        onPressed: _busy || selected == null
                            ? null
                            : () => _run(() async {
                                await _save();
                                await _flow.reject(
                                  selected.candidate.proposalId,
                                );
                                _selected = null;
                                _review = null;
                                _approved = null;
                                _status =
                                    'Proposal rejected. Canon is unchanged.';
                                await _refresh();
                              }),
                        child: const Text('Reject proposal'),
                      ),
                    ],
                  ),
                  if (review != null) ...[
                    Text(
                      'Exact review',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final operation in review.proposal.operations)
                      if (operation is AddSourceAnchorOperation)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(operation.record.excerpt),
                          ),
                        ),
                    for (final line in review.summary) SelectableText(line),
                    AssessmentDeclarationView(
                      state: review.assessment.state,
                      envelope: review.assessment.envelope,
                      load: (reference) => readProposalAssessment(
                        _flow.changes, review.proposal, reference,
                      ),
                    ),
                    Text(
                      'Impact: ${review.impact.coverage.wireName} · ${review.impact.records.length} related records',
                    ),
                    if (review.validation.execution case final execution?) ...[
                      Text('Check coverage: ${execution.coverage.wireName}'),
                      for (final finding in execution.findings)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  FindingReviewSummary(
                                    finding: finding,
                                    universe: _flow.changes.scope.universe,
                                    records: _records,
                                  ).title,
                                ),
                                for (final claim in FindingReviewSummary(
                                  finding: finding,
                                  universe: _flow.changes.scope.universe,
                                  records: _records,
                                ).claims)
                                  Text(claim),
                                Text(
                                  '${finding.outcome.wireName.replaceAll('_', ' ')} · ${finding.coverage.wireName}',
                                ),
                                if (finding.message != null)
                                  SelectableText(finding.message!),
                                if (_records[finding.ruleId]?.payload
                                    case RuleRecord(:final requiredEvidence)
                                    when requiredEvidence != null)
                                  EvidencePolicyView(
                                    summary: EvidencePolicySummary(
                                      _records[finding.ruleId]!.payload
                                          as RuleRecord,
                                      _records,
                                    ),
                                  ),
                                ExactFields(value: finding.toWire()),
                              ],
                            ),
                          ),
                        ),
                    ],
                    ExpansionTile(
                      title: const Text('Exact changes and affected records'),
                      children: [
                        ExactFields(value: review.diff),
                        ExactFields(value: review.footprint),
                        for (final operation in review.proposal.operations)
                          ExactFields(value: operation.toWire()),
                      ],
                    ),
                    if (review.acceptance.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        key: ValueKey(review),
                        initialValue: _acceptance,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Unexplained resource finding',
                        ),
                        items: [
                          for (var i = 0; i < review.acceptance.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                'Finding ${i + 1} · ${review.acceptance[i].scope}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _acceptance = value),
                      ),
                      TextField(
                        controller: _reason,
                        enabled: !_busy,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Reason for scoped creative acceptance',
                        ),
                      ),
                      OutlinedButton(
                        onPressed:
                            _busy ||
                                _acceptance == null ||
                                _reason.text.trim().isEmpty
                            ? null
                            : () => _run(() async {
                                final option = review.acceptance[_acceptance!];
                                _approved = null;
                                await _show(
                                  await _flow.review(
                                    AcceptWritingAction(
                                      candidate: review.candidate,
                                      fingerprint: option.fingerprint,
                                      scope: option.scope,
                                      rationale: _reason.text,
                                    ),
                                  ),
                                );
                              }),
                        child: const Text(
                          'Accept this exact unexplained count',
                        ),
                      ),
                    ],
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed:
                              _busy || !review.publishable || _approved != null
                              ? null
                              : () => _run(() async {
                                  _approved = await _flow.approve(review);
                                  _status = 'Exact changes approved. Publish separately.';
                                  await _refresh();
                                }),
                          child: const Text('Approve exact reviewed changes'),
                        ),
                        FilledButton(
                          onPressed: _busy || _approved == null
                              ? null
                              : () => _run(() => _publish(_approved!)),
                          child: const Text('Publish approved writing'),
                        ),
                      ],
                    ),
                  ],
                  ExpansionTile(
                    title: const Text('Recover an approved publication'),
                    children: [
                      const Text(
                        'Recovery uses the original approval and publication key. It does not grant a new approval.',
                      ),
                      DropdownButtonFormField<WritingApproval>(
                        key: ValueKey(_approvals),
                        initialValue: _recovery,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Existing approval',
                        ),
                        items: _approvals
                            .map(
                              (row) => DropdownMenuItem(
                                value: row,
                                child: Text(
                                  '${row.label} · version ${row.candidate.version}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (row) => setState(() => _recovery = row),
                      ),
                      OutlinedButton(
                        onPressed: _busy || _recovery == null
                            ? null
                            : () => _run(() => _publish(_recovery!)),
                        child: const Text('Recover original publication'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
