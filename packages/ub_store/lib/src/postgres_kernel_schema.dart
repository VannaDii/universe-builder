import 'package:ub_domain/ub_domain.dart';

import 'postgres_values.dart';

/// Canonical history and its rebuildable membership caches. Install after the
/// normative body tables within the caller's provisioning transaction.
/// Semantic/search projections and workflow entries are provisioned separately.
Iterable<String> postgresKernelSchema(UniverseId universe) sync* {
  final s = postgresUniverseSchema(universe);
  const text = 'TEXT COLLATE "C"';
  yield 'CREATE TABLE $s.universes(id $text PRIMARY KEY, singleton SMALLINT NOT NULL DEFAULT 1 UNIQUE CHECK(singleton=1), name BYTEA NOT NULL)';
  yield 'CREATE TABLE $s.record_identities(universe_id $text NOT NULL REFERENCES $s.universes(id), id $text NOT NULL, kind $text NOT NULL, PRIMARY KEY(universe_id,id), UNIQUE(universe_id,id,kind))';
  yield 'CREATE TABLE $s.record_versions(universe_id $text NOT NULL, id $text NOT NULL, record_id $text NOT NULL, kind $text NOT NULL, payload_row BIGINT NOT NULL REFERENCES $s.r_payload(__row_id), digest $text NOT NULL, PRIMARY KEY(universe_id,id), UNIQUE(universe_id,id,record_id), FOREIGN KEY(universe_id,record_id,kind) REFERENCES $s.record_identities(universe_id,id,kind))';
  yield 'CREATE TABLE $s.import_record_digest(universe_id $text NOT NULL, version_id $text NOT NULL, source_digest $text NOT NULL, normalized_digest $text NOT NULL, PRIMARY KEY(universe_id,version_id), FOREIGN KEY(universe_id,version_id) REFERENCES $s.record_versions(universe_id,id))';
  yield 'CREATE TABLE $s.continuities(universe_id $text NOT NULL REFERENCES $s.universes(id), id $text NOT NULL, head_commit $text NOT NULL, baseline_commit $text, PRIMARY KEY(universe_id,id))';
  yield 'CREATE TABLE $s.commits(universe_id $text NOT NULL, id $text NOT NULL, continuity_id $text NOT NULL, parent_id $text, sequence BIGINT NOT NULL CHECK(sequence>=0), principal $text NOT NULL, decision BYTEA NOT NULL, reason BYTEA NOT NULL, digest $text NOT NULL, PRIMARY KEY(universe_id,id), UNIQUE(universe_id,continuity_id,sequence), UNIQUE(universe_id,id,continuity_id), FOREIGN KEY(universe_id,continuity_id) REFERENCES $s.continuities(universe_id,id) DEFERRABLE INITIALLY DEFERRED, FOREIGN KEY(universe_id,parent_id,continuity_id) REFERENCES $s.commits(universe_id,id,continuity_id))';
  yield 'ALTER TABLE $s.continuities ADD FOREIGN KEY(universe_id,head_commit,id) REFERENCES $s.commits(universe_id,id,continuity_id) DEFERRABLE INITIALLY DEFERRED';
  yield 'ALTER TABLE $s.continuities ADD FOREIGN KEY(universe_id,baseline_commit) REFERENCES $s.commits(universe_id,id)';
  yield 'CREATE TABLE $s.commit_changes(universe_id $text NOT NULL, revision_id $text NOT NULL, record_id $text NOT NULL, prior_version $text, version_id $text, PRIMARY KEY(universe_id,revision_id,record_id), FOREIGN KEY(universe_id,revision_id) REFERENCES $s.commits(universe_id,id), FOREIGN KEY(universe_id,record_id) REFERENCES $s.record_identities(universe_id,id), FOREIGN KEY(universe_id,prior_version,record_id) REFERENCES $s.record_versions(universe_id,id,record_id), FOREIGN KEY(universe_id,version_id,record_id) REFERENCES $s.record_versions(universe_id,id,record_id))';
  yield 'CREATE TABLE $s.world_name_reservations(universe_id $text NOT NULL, name $text NOT NULL, record_id $text NOT NULL, first_revision $text NOT NULL, PRIMARY KEY(universe_id,name), FOREIGN KEY(universe_id,record_id) REFERENCES $s.record_identities(universe_id,id), FOREIGN KEY(universe_id,first_revision) REFERENCES $s.commits(universe_id,id))';
  yield 'CREATE TABLE $s.head_membership(universe_id $text NOT NULL, continuity_id $text NOT NULL, record_id $text NOT NULL, version_id $text NOT NULL, PRIMARY KEY(universe_id,continuity_id,record_id), FOREIGN KEY(universe_id,continuity_id) REFERENCES $s.continuities(universe_id,id), FOREIGN KEY(universe_id,version_id,record_id) REFERENCES $s.record_versions(universe_id,id,record_id))';
  yield 'CREATE TABLE $s.projection_heads(universe_id $text NOT NULL, continuity_id $text NOT NULL, revision_id $text NOT NULL, checksum $text NOT NULL, PRIMARY KEY(universe_id,continuity_id))';
  yield 'CREATE TABLE $s.snapshot_membership(universe_id $text NOT NULL, revision_id $text NOT NULL, checksum $text NOT NULL, PRIMARY KEY(universe_id,revision_id), FOREIGN KEY(universe_id,revision_id) REFERENCES $s.commits(universe_id,id))';
  yield 'CREATE TABLE $s.snapshot_member(universe_id $text NOT NULL, revision_id $text NOT NULL, record_id $text NOT NULL, version_id $text NOT NULL, PRIMARY KEY(universe_id,revision_id,record_id), FOREIGN KEY(universe_id,revision_id) REFERENCES $s.snapshot_membership(universe_id,revision_id), FOREIGN KEY(universe_id,version_id,record_id) REFERENCES $s.record_versions(universe_id,id,record_id))';
  yield 'CREATE TABLE $s.operation_receipts(universe_id $text NOT NULL REFERENCES $s.universes(id), principal $text NOT NULL, operation_kind $text NOT NULL, idempotency_key BYTEA NOT NULL, payload_digest $text NOT NULL, revision_id $text NOT NULL, PRIMARY KEY(universe_id,principal,operation_kind,idempotency_key), FOREIGN KEY(universe_id,revision_id) REFERENCES $s.commits(universe_id,id))';
  yield 'CREATE TABLE $s.historical_receipt(universe_id $text NOT NULL, principal $text NOT NULL, operation_kind $text NOT NULL, idempotency_key BYTEA NOT NULL, PRIMARY KEY(universe_id,principal,operation_kind,idempotency_key), FOREIGN KEY(universe_id,principal,operation_kind,idempotency_key) REFERENCES $s.operation_receipts(universe_id,principal,operation_kind,idempotency_key))';
  for (final table in [
    'record_identities',
    'record_versions',
    'commits',
    'commit_changes',
    'world_name_reservations',
    'operation_receipts',
    'import_record_digest',
    'historical_receipt',
  ]) {
    yield 'CREATE TRIGGER immutable_history BEFORE UPDATE OR DELETE ON $s.$table FOR EACH ROW EXECUTE FUNCTION $s.immutable_body()';
  }
  yield 'CREATE TRIGGER immutable_branch BEFORE UPDATE OF universe_id,id,baseline_commit ON $s.continuities FOR EACH ROW EXECUTE FUNCTION $s.immutable_body()';
  yield 'CREATE TRIGGER immutable_universe_id BEFORE UPDATE OF id ON $s.universes FOR EACH ROW EXECUTE FUNCTION $s.immutable_body()';
  yield 'CREATE TRIGGER immutable_universe_delete BEFORE DELETE ON $s.universes FOR EACH ROW EXECUTE FUNCTION $s.immutable_body()';
}
