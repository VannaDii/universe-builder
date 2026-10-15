import 'package:flutter/material.dart';

import 'evidence_review_summary.dart';

class EvidencePolicyView extends StatelessWidget {
  const EvidencePolicyView({super.key, required this.summary});
  final EvidencePolicySummary summary;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Required evidence',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(summary.scope),
        Text(summary.review),
        const Text('Qualifying source categories:'),
        for (final category in summary.categories) Text(category),
        const Text(
          'Source selection records authored eligibility; it does not independently establish truth.',
        ),
      ],
    ),
  );
}
