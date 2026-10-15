import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

final class UniversePurgePreview {
  UniversePurgePreview(CanonicalValue value) {
    final f = WireFields(value, {'digest', 'impact'});
    digest = f.string('digest');
    final impact = WireFields(f.require('impact'), {
      'universe_id',
      'heads',
      'revisions',
      'record_versions',
      'workflow_entries',
      'commit_receipts',
      'scope',
      'retained',
      'erasure',
    });
    universe = UniverseId.parse(impact.string('universe_id'));
    continuities = impact.array('heads').length;
    revisions = impact.u64('revisions');
    versions = impact.u64('record_versions');
    workflows = impact.u64('workflow_entries');
    receipts = impact.u64('commit_receipts');
    scope = impact.string('scope');
    retained = impact.string('retained');
    erasure = impact.string('erasure');
  }
  late final UniverseId universe;
  late final String digest, scope, retained, erasure;
  late final int continuities;
  late final BigInt revisions, versions, workflows, receipts;
}

Future<UniversePurgePreview> previewUniversePurge(
  AppSession session,
  LibraryEntry universe,
) async {
  final preview = UniversePurgePreview(
    await session.call(
      PreviewPurgeEngineRequest(universe: Selector(universe.name)),
    ),
  );
  if (preview.universe != universe.id) {
    throw const FormatException(
      'The selected universe changed. Return to Library and reopen it.',
    );
  }
  return preview;
}

Future<void> purgeUniverse(
  AppSession session,
  LibraryEntry universe,
  UniversePurgePreview preview,
  String confirmation,
) async {
  if (preview.universe != universe.id) {
    throw const FormatException('Preview this universe before purging it.');
  }
  await session.call(
    PurgeEngineRequest(
      universe: Selector(universe.name),
      digest: preview.digest,
      confirmation: confirmation,
    ),
  );
}
