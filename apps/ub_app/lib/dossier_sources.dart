import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

/// Only records admitted by the existing pinned, permission-filtered read.
List<RecordVersion> dossierSourceRecords(
  Records material,
  UniverseId universe,
) {
  final seen = <RecordVersionId>{};
  return [
    for (final row in [...material.records, ...material.evidence])
      if (row.identity.universeId == universe &&
          (row.payload is SourceRecord ||
              row.payload is SourceVersionRecord ||
              row.payload is AnchorRecord) &&
          seen.add(row.recordVersionId))
        row,
  ];
}

/// A newer version with the same record ID cannot name an older anchor's text.
RecordVersion? dossierAnchorSource(
  List<RecordVersion> records,
  UniverseId universe,
  AnchorRecord anchor,
) {
  final reference = anchor.sourceVersion;
  if (reference.universe != null && reference.universe != universe) return null;
  for (final row in records) {
    if (row.identity.universeId == universe &&
        row.identity.recordId == reference.record &&
        row.recordVersionId == reference.version &&
        row.payload is SourceVersionRecord) {
      return row;
    }
  }
  return null;
}

String sourceLocatorText(AnchorLocator locator) => switch (locator) {
  ByteRangeLocator(:final start, :final end) =>
    'UTF-8 bytes $start–$end (end excluded)',
  StructuralPathLocator(:final path) => 'Structural path: ${path.join(' / ')}',
};
