import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'proposal_assessment.dart';
import 'record_fields.dart';

class AssessmentDeclarationView extends StatefulWidget {
  const AssessmentDeclarationView({
    super.key,
    required this.state,
    this.envelope,
    this.load,
  });
  final AssessmentState state;
  final AssessmentEnvelope? envelope;
  final Future<AssessmentEnvelope?> Function(AssessmentRef)? load;
  @override
  State<AssessmentDeclarationView> createState() =>
      _AssessmentDeclarationViewState();
}

class _AssessmentDeclarationViewState extends State<AssessmentDeclarationView> {
  AssessmentEnvelope? _envelope;
  bool _busy = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _envelope = widget.envelope;
  }

  @override
  void didUpdateWidget(AssessmentDeclarationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.envelope != widget.envelope) {
      _generation++;
      _envelope = widget.envelope;
      _busy = false;
      _error = null;
    }
  }

  Future<void> _read(AssessmentRef reference) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final envelope = await widget.load!(reference);
      if (mounted && generation == _generation) {
        setState(() {
          _envelope = envelope;
          if (envelope == null) {
            _error = 'The assessment declaration was not returned.';
          }
        });
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Could not read this exact assessment in full. Retry with your current connection and access.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final envelope = _envelope;
    final reference = assessmentReference(widget.state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Source assessment',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'This is the assessor’s attributed declaration about the submitted material. Source bytes and engine checks are separate.',
        ),
        Text(switch (widget.state) {
          BoundAssessment() => 'At this check, the assessment is bound to the proposal and its source bytes are verified.',
          StaleAssessment() => 'At this check, the assessment is stale. Its retained declaration can still be read.',
          AbsentAssessment() => 'No source assessment was selected for this proposal. Existing evidence policies still apply.',
          UnavailableAssessment() =>
            'The source assessment is unavailable for this check.',
        }),
        if (envelope == null && reference != null && widget.load != null)
          TextButton(
            onPressed: _busy ? null : () => _read(reference),
            child: Text(
              _error == null
                  ? 'Read assessor declaration'
                  : 'Retry assessor declaration',
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (envelope != null) ...[
          for (final section in <(String, CanonicalValue)>[
            ('Assessor', envelope.body.assessor.toWire()),
            (
              'Submitted sources and exact ranges',
              CanonicalArray(envelope.body.sources.map((s) => s.toWire())),
            ),
            (
              'Exact dependencies',
              CanonicalArray(envelope.body.dependencies.map((d) => d.toWire())),
            ),
            (
              'Declared inventory',
              CanonicalArray(
                envelope.body.declaredInventory.map((i) => i.toWire()),
              ),
            ),
            (
              'Inventory declaration and exclusions',
              envelope.body.inventoryDeclaration.toWire(),
            ),
            (
              'Claim mappings and unchanged evidence',
              CanonicalArray(
                envelope.body.claimMappings.map((m) => m.toWire()),
              ),
            ),
            (
              'Unresolved material',
              CanonicalArray(envelope.body.unresolved.map((u) => u.toWire())),
            ),
          ])
            ExpansionTile(
              title: Text(section.$1),
              initiallyExpanded: true,
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [ExactFields(value: section.$2)],
            ),
          Text(
            'Assessor concludes: ${envelope.body.conclusion.wireName.replaceAll('_', ' ')}',
          ),
          ExpansionTile(
            title: const Text('Exact assessment attachment'),
            children: [
              SelectableText('Attachment: ${envelope.assessmentId.value}'),
              SelectableText('Digest: ${envelope.digest.value}'),
            ],
          ),
        ],
        ExpansionTile(
          title: const Text('Assessment binding details'),
          children: [ExactFields(value: widget.state.toWire())],
        ),
      ],
    );
  }
}
