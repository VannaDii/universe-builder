import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_contracts/ub_contracts.dart' as data show State;
import 'package:ub_domain/ub_domain.dart';

import 'record_browser.dart';
import 'record_fields.dart';

class DossierFacts extends StatelessWidget {
  const DossierFacts({super.key, required this.state, required this.universe});
  final data.State state;
  final UniverseId universe;

  @override
  Widget build(BuildContext context) {
    final material = Records(
      records: [
        ...state.propositions,
        ...state.assertions,
        ...state.epistemic,
        for (final object in state.objects) ...[
          object.identity,
          ...object.ancestry,
          ...object.dependencies,
          for (final row in [
            ...object.instanceFacts,
            ...object.sharedAttributes,
            ...object.initialValueCandidates,
            ...object.behavioralRequirements,
            ...object.rules,
          ])
            row.record,
        ],
      ],
    );
    String name(RecordRef ref) =>
        dossierReferenceLabel(material, universe, ref);
    String applicability(bool? value) => switch (value) {
      true => 'Applies in this read context',
      false => 'Does not apply in this read context',
      null => 'Applicability unresolved',
    };
    Widget value(DomainValue v) => switch (v) {
      TextValue(:final text) => SelectableText(text),
      BooleanValue(:final value) => Text(value ? 'Yes' : 'No'),
      IntegerValue(:final digits) ||
      DecimalValue(:final digits) => SelectableText(digits),
      RationalValue(:final numerator, :final denominator) => SelectableText(
        '$numerator / $denominator',
      ),
      ReferenceValue(:final record) => SelectableText(name(record)),
      _ => ExactFields(value: v.toWire()),
    };
    Widget evidence(ObjectEvidence row) {
      final payload = row.record.payload;
      PropositionRecord? proposition;
      if (payload is AssertionRecord) {
        for (final record in material.records) {
          if (record.payload case final PropositionRecord p
              when record.identity.recordId == payload.proposition.record &&
                  record.identity.universeId ==
                      (payload.proposition.universe ?? universe)) {
            proposition = p;
            break;
          }
        }
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                proposition == null
                    ? payload.recordKind.wireName.replaceAll('_', ' ')
                    : name(proposition.predicate),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(applicability(row.applicability)),
              if (payload is AssertionRecord)
                Text(
                  payload.polarity == Polarity.support
                      ? 'Supporting assertion'
                      : 'Refuting assertion',
                ),
              if (proposition != null) ...[
                SelectableText('Subject: ${name(proposition.subject)}'),
                if (proposition.value != null) value(proposition.value!),
                for (var i = 0; i < proposition.roles.length; i++)
                  SelectableText(
                    '${i + 1}. ${proposition.roles[i].role}: ${name(proposition.roles[i].participant)}',
                  ),
              ],
              for (final unknown in row.unknowns)
                Text('Unresolved: ${unknown.replaceAll('_', ' ')}'),
              ExpansionTile(
                title: const Text('Scope, validity and evidence'),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [ExactFields(value: payload.toWire())],
              ),
              if (proposition != null)
                ExpansionTile(
                  title: const Text('Exact declaration'),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [ExactFields(value: proposition.toWire())],
                ),
            ],
          ),
        ),
      );
    }

    List<Widget> section(String title, List<ObjectEvidence> rows) => [
      const SizedBox(height: 16),
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      if (rows.isEmpty) const Text('No evidence returned in this view.'),
      for (final row in rows) evidence(row),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Facts at the opened revision and represented context. This dossier reads all authored times; applicability here does not establish what holds at a chosen date.',
        ),
        Text('State coverage: ${state.coverage.wireName}'),
        for (final limitation in state.unsupportedCapabilities)
          Text(limitation),
        for (final object in state.objects) ...[
          Text('Object coverage: ${object.coverage.wireName}'),
          for (final unknown in object.unknowns)
            Text('Unresolved: ${unknown.replaceAll('_', ' ')}'),
          for (final conflict in object.conflicts)
            Card(
              child: ListTile(
                title: Text(
                  'Conflicting candidates: ${name(RecordRef(universe: universe, record: conflict.predicate))}',
                ),
                subtitle: Text(
                  '${applicability(conflict.applicability)} · ${conflict.assertions.length} assertions${conflict.initialValues ? ' · initial values' : ''}',
                ),
              ),
            ),
          ...section('Instance facts', object.instanceFacts),
          ...section(
            'Shared and inherited attributes',
            object.sharedAttributes,
          ),
          ...section('Initial-value candidates', object.initialValueCandidates),
          ...section('Behavioral requirements', object.behavioralRequirements),
          ...section('Rules', object.rules),
          ExpansionTile(
            title: const Text(
              'Classification, names and initialization history',
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                object.ancestryComplete
                    ? 'Ancestry complete in this view'
                    : 'Ancestry unresolved',
              ),
              for (final ancestor in object.ancestry)
                SelectableText(
                  name(
                    RecordRef(
                      universe: ancestor.identity.universeId,
                      record: ancestor.identity.recordId,
                    ),
                  ),
                ),
              for (final contextualName in object.contextualNames) ...[
                Text(applicability(contextualName.applicability)),
                ExactFields(value: contextualName.name.toWire()),
              ],
              Text(
                'Initialization history: ${object.initializationHistoryCoverage.wireName}',
              ),
              for (final receipt in object.initializationReceipts)
                ExactFields(value: receipt.toWire()),
            ],
          ),
        ],
        if (state.derived.isNotEmpty) ...[
          const Text('Derived results'),
          for (final fact in state.derived)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name(fact.predicate)),
                    value(fact.value),
                    ExpansionTile(
                      title: const Text('Derivation and evidence'),
                      children: [ExactFields(value: fact.toWire())],
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (state.epistemic.isNotEmpty)
          ExpansionTile(
            title: const Text('Knowledge and memory'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in state.epistemic)
                ExactFields(value: row.payload.toWire()),
            ],
          ),
        if (state.completeness.isNotEmpty)
          ExpansionTile(
            title: const Text('Authored completeness declarations'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in state.completeness)
                ExactFields(value: row.payload.toWire()),
            ],
          ),
      ],
    );
  }
}
