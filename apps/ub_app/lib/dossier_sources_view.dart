import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'dossier_sources.dart';
import 'record_browser.dart';
import 'record_fields.dart';
import 'connection.dart';
import 'source_text_view.dart';

class DossierSources extends StatelessWidget {
  const DossierSources({
    super.key,
    required this.material,
    required this.universe,
    required this.session,
    required this.selector,
    required this.openedContext,
  });
  final Records material;
  final UniverseId universe;
  final AppSession session;
  final Selector selector;
  final ContextId openedContext;

  @override
  Widget build(BuildContext context) {
    final rows = dossierSourceRecords(material, universe);
    String label(RecordRef ref) =>
        dossierReferenceLabel(material, universe, ref);
    Widget origin(OriginMetadata origin) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (origin.externallyAssertedAuthor case final String author)
          SelectableText('Attributed author: $author'),
        if (origin.originNote case final String note) SelectableText(note),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Source material accessible at this opened revision. Excerpts preserve the submitted text; source attribution does not establish a claim’s truth.',
        ),
        if (rows.isEmpty)
          const Text('No source or anchor records were returned in this view.'),
        for (final row in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...switch (row.payload) {
                    SourceRecord source => <Widget>[
                      Text(
                        source.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      origin(source.origin),
                      if (source.externalId case final String external)
                        SelectableText('External identifier: $external'),
                      Text(
                        '${source.versions.length} declared source versions',
                      ),
                    ],
                    SourceVersionRecord version => <Widget>[
                      Text(
                        'Source version · ${label(version.source)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      origin(version.origin),
                      SelectableText(
                        '${version.mediaType} · ${version.byteSize} bytes · ${version.decoding.encoding}',
                      ),
                      SelectableText('Imported: ${version.importTime}'),
                      SelectableText(
                        'Import actor: ${version.importActor.value}',
                      ),
                      SourceTextView(
                        key: ValueKey(row.recordVersionId),
                        session: session,
                        universe: selector,
                        context: openedContext,
                        version: VersionRef(
                          universe: universe,
                          record: row.identity.recordId,
                          version: row.recordVersionId,
                        ),
                      ),
                    ],
                    AnchorRecord anchor => <Widget>[
                      Builder(
                        builder: (context) {
                          final exact = dossierAnchorSource(
                            rows,
                            universe,
                            anchor,
                          );
                          final source = exact?.payload as SourceVersionRecord?;
                          return Text(
                            source == null
                                ? 'Anchored excerpt · exact source version unavailable in this view'
                                : 'Anchored excerpt · ${label(source.source)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          );
                        },
                      ),
                      SelectableText(sourceLocatorText(anchor.locator)),
                      const SizedBox(height: 8),
                      SelectableText(anchor.excerpt),
                      if (anchor.context case final RecordRef represented)
                        Text('Represented context: ${label(represented)}'),
                    ],
                    _ => <Widget>[],
                  },
                  ExpansionTile(
                    title: const Text('Exact source details'),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText('Record: ${row.identity.recordId.value}'),
                      SelectableText('Version: ${row.recordVersionId.value}'),
                      ExactFields(value: row.payload.toWire()),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
