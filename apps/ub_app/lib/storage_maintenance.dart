import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

final class StorageMaintenance {
  const StorageMaintenance(
    this.versions,
    this.revisions,
    this.receipts,
    this.workflows,
    this.sources,
    this.eligibleCaches,
    this.collectedCaches,
  );
  final BigInt versions,
      revisions,
      receipts,
      workflows,
      sources,
      eligibleCaches,
      collectedCaches;
  factory StorageMaintenance.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'retention_policy',
      'retained_record_versions',
      'retained_revisions',
      'retained_commit_receipts',
      'retained_workflow_entries',
      'retained_source_assets',
      'eligible_snapshot_caches',
      'collected_snapshot_caches',
      'source_assets_collected',
      'backup_pins',
      'canonical',
    });
    return StorageMaintenance(
      f.u64('retained_record_versions'),
      f.u64('retained_revisions'),
      f.u64('retained_commit_receipts'),
      f.u64('retained_workflow_entries'),
      f.u64('retained_source_assets'),
      f.u64('eligible_snapshot_caches'),
      f.u64('collected_snapshot_caches'),
    );
  }
}

Future<StorageMaintenance> maintainStorage(
  AppSession session,
  LibraryEntry universe, {
  bool collect = false,
}) async => StorageMaintenance.fromWire(
  await session.call(
    MaintainEngineRequest(universe: Selector(universe.name), collect: collect),
  ),
);
