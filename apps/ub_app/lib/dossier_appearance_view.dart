import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'dossier_appearance.dart';
import 'image_preview_view.dart';
import 'record_browser.dart';
import 'record_fields.dart';

class DossierAppearance extends StatelessWidget {
  const DossierAppearance({
    super.key,
    required this.session,
    required this.universe,
    required this.context,
    required this.entry,
    required this.material,
  });
  final AppSession session;
  final LibraryEntry universe;
  final OpenedContext context;
  final RecordId entry;
  final Records material;
  @override
  Widget build(BuildContext context) {
    final appearances = dossierAppearances(material, universe.id, entry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Authored appearance at this opened revision. Descriptions and image purposes retain their declared validity.',
        ),
        if (appearances.isEmpty)
          const Text('No appearance records were returned in this view.'),
        for (final row in appearances)
          Builder(
            builder: (context) {
              final appearance = row.payload as AppearanceRecord;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        appearance.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text('Physical description'),
                      SelectableText(appearance.physicalDescription),
                      const Text('Atmosphere'),
                      SelectableText(appearance.atmosphere),
                      ExpansionTile(
                        title: const Text('Declared validity'),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExactFields(value: appearance.validity.toWire()),
                        ],
                      ),
                      for (
                        var index = 0;
                        index < appearance.images.length;
                        index++
                      ) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Image ${index + 1} · ${appearance.images[index].purpose.name}',
                        ),
                        ImagePreviewView(
                          key: ValueKey(
                            '${row.identity.recordId.value}:$index',
                          ),
                          session: session,
                          universe: universe,
                          context: this.context,
                          reference: appearance.images[index].asset,
                          caption: appearance.images[index].caption,
                        ),
                      ],
                      for (final link in appearance.links) ...[
                        const SizedBox(height: 12),
                        Text(
                          '${link.relationship.wireName.replaceAll('_', ' ')}: ${dossierReferenceLabel(material, universe.id, link.entry)}',
                        ),
                        SelectableText(link.note),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
