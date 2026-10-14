import 'package:ub_domain/ub_domain.dart';

enum LibrarySection { library, settings, help }

/// Links carry identifiers and page choices, never profile or database secrets.
final class LibraryLocation {
  const LibraryLocation({
    this.section = LibrarySection.library,
    this.universe,
    this.continuity,
    this.context,
    this.editor,
    this.record,
    this.revision,
  });
  final LibrarySection section;
  final UniverseId? universe;
  final ContinuityId? continuity;
  final RecordId? context;
  final String? editor;
  final RecordId? record;
  final RevisionId? revision;
  static const editors = {
    'records',
    'entity',
    'type',
    'property',
    'unit',
    'value-definition',
    'relation',
    'action',
    'rule',
    'communication',
    'commitment',
    'plan',
    'item-power',
    'represented-context',
    'issue-decision',
    'exception',
    'boundary',
    'work',
    'work-version',
    'saga',
    'scene',
    'passage',
    'memory',
    'observation',
    'attitude',
    'proposition',
    'completeness',
    'source',
    'event',
    'calendar',
    'pack',
    'world',
    'changes',
  };
  Uri get uri => universe == null
      ? Uri(path: '/${section.name}')
      : Uri(
          path: record != null
              ? '/universe/${universe!.value}/continuity/${continuity!.value}/context/${context!.value}/revision/${revision!.value}/record/${record!.value}'
              : editor == null
              ? '/universe/${universe!.value}'
              : '/universe/${universe!.value}/continuity/${continuity!.value}/context/${context!.value}/editor/$editor',
        );
  static LibraryLocation parse(Uri uri) {
    if (uri.hasScheme || uri.hasAuthority || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('Unsupported application link');
    }
    final parts = uri.pathSegments;
    if (parts.isEmpty) return const LibraryLocation();
    if (parts.length == 1 && parts.single.isEmpty) {
      return const LibraryLocation();
    }
    if (parts.length == 1) {
      return LibraryLocation(
        section: LibrarySection.values.byName(parts.single),
      );
    }
    if (parts.length == 2 && parts.first == 'universe') {
      return LibraryLocation(universe: UniverseId.parse(parts.last));
    }
    if (parts.length == 8 &&
        parts[0] == 'universe' &&
        parts[2] == 'continuity' &&
        parts[4] == 'context' &&
        parts[6] == 'editor' &&
        editors.contains(parts[7])) {
      return LibraryLocation(
        universe: UniverseId.parse(parts[1]),
        continuity: ContinuityId.parse(parts[3]),
        context: RecordId.parse(parts[5]),
        editor: parts[7],
      );
    }
    if (parts.length == 10 &&
        parts[0] == 'universe' &&
        parts[2] == 'continuity' &&
        parts[4] == 'context' &&
        parts[6] == 'revision' &&
        parts[8] == 'record') {
      return LibraryLocation(
        universe: UniverseId.parse(parts[1]),
        continuity: ContinuityId.parse(parts[3]),
        context: RecordId.parse(parts[5]),
        revision: RevisionId.parse(parts[7]),
        record: RecordId.parse(parts[9]),
      );
    }
    throw const FormatException('Unsupported application link');
  }
}
