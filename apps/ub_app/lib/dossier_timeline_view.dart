import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'dossier_timeline.dart';
import 'record_browser.dart';
import 'record_fields.dart';

class DossierTimeline extends StatelessWidget {
  const DossierTimeline({
    super.key,
    required this.material,
    required this.universe,
    required this.entity,
    required this.name,
    required this.representedContext,
  });
  final Records material;
  final UniverseId universe;
  final RecordId entity, representedContext;
  final String name;

  String label(RecordRef ref) =>
      ref.record == entity && (ref.universe == null || ref.universe == universe)
      ? name
      : dossierReferenceLabel(material, universe, ref);

  @override
  Widget build(BuildContext context) {
    Chronology? chronology;
    for (final row in [...material.records, ...material.evidence]) {
      if (row.payload case RepresentedContextRecord(chronology: final clock)
          when row.identity.recordId == representedContext &&
              row.identity.universeId == universe) {
        chronology = clock;
      }
    }
    final order = dossierEventOrder(dossierEvents(material, universe, entity));
    Widget eventCard(RecordVersion row) {
      final event = row.payload as EventRecord;
      final occurrence = switch (event.occurrence) {
        SimpleOccurrence(:final kind) => kind.name,
        DescriptiveOccurrence(:final label) => label,
      };
      final calendar = eventCalendar(event.time);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label(
                  RecordRef(universe: universe, record: row.identity.recordId),
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('Occurrence: $occurrence'),
              SelectableText(
                eventTimeText(event.time, label, chronology: chronology),
              ),
              if (calendar != null)
                Text(
                  'Calendar: ${label(RecordRef(universe: universe, record: calendar.toRecordId()))}',
                ),
              if (event.sequence != null)
                SelectableText('Authored sequence: ${event.sequence}'),
              for (final participant in event.participants)
                SelectableText(
                  '${participant.role}: ${label(participant.record)}',
                ),
              ExpansionTile(
                title: const Text('Exact time and uncertainty'),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExactFields(value: event.time.encode(canonical: false)),
                ],
              ),
              ExpansionTile(
                title: const Text('Event details and effects'),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [ExactFields(value: event.toWire())],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Events with explicit participation at this opened revision. Exact numeric points are ordered within each calendar; calendars remain separate. Equal coordinates do not establish a sequence. Event participation does not establish a lifespan.',
        ),
        if (order.points.isEmpty && order.other.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No participating events were returned in this view. This does not establish that none exist.',
            ),
          ),
        for (final group in order.points.entries) ...[
          const SizedBox(height: 16),
          Text(
            'Exact points · ${label(RecordRef(universe: universe, record: group.key.toRecordId()))}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final row in group.value) eventCard(row),
        ],
        if (order.other.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Intervals, relative, uncertain and unplaced events',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Text(
            'These retain their authored times without being forced into a point order.',
          ),
          for (final row in order.other) eventCard(row),
        ],
      ],
    );
  }
}
