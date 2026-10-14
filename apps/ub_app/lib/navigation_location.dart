import 'package:ub_domain/ub_domain.dart';

import 'record_edit_action.dart';

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
    this.recordAction,
    this.draftVersion,
    this.operationIndex,
  });
  final LibrarySection section;
  final UniverseId? universe;
  final ContinuityId? continuity;
  final RecordId? context;
  final String? editor;
  final RecordId? record;
  final RevisionId? revision;
  final RecordEditAction? recordAction;
  final BigInt? draftVersion;
  final int? operationIndex;
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
    'secret',
    'appearance',
    'story-time',
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
          path: operationIndex != null
              ? '/universe/${universe!.value}/continuity/${continuity!.value}/context/${context!.value}/draft/$draftVersion/operation/$operationIndex'
              : record != null
              ? '/universe/${universe!.value}/continuity/${continuity!.value}/context/${context!.value}/revision/${revision!.value}/record/${record!.value}${recordAction == null ? '' : '/edit/${recordAction!.name}'}'
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
    if ((parts.length == 10 ||
            (parts.length == 12 &&
                parts[10] == 'edit' &&
                RecordEditAction.values.any(
                  (action) => action.name == parts[11],
                ))) &&
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
        recordAction: parts.length == 12
            ? RecordEditAction.values.byName(parts[11])
            : null,
      );
    }
    if (parts.length == 10 &&
        parts[0] == 'universe' &&
        parts[2] == 'continuity' &&
        parts[4] == 'context' &&
        parts[6] == 'draft' &&
        parts[8] == 'operation') {
      final version = BigInt.tryParse(parts[7]);
      final index = BigInt.tryParse(parts[9]);
      if (version == null ||
          index == null ||
          version < BigInt.zero ||
          version >= (BigInt.one << 64) ||
          index < BigInt.zero ||
          index > BigInt.from(0xffffffff) ||
          version.toString() != parts[7] ||
          index.toString() != parts[9]) {
        throw const FormatException('Invalid draft operation link');
      }
      return LibraryLocation(
        universe: UniverseId.parse(parts[1]),
        continuity: ContinuityId.parse(parts[3]),
        context: RecordId.parse(parts[5]),
        draftVersion: version,
        operationIndex: index.toInt(),
      );
    }
    throw const FormatException('Unsupported application link');
  }
}
