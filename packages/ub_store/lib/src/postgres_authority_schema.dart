import 'package:ub_domain/ub_domain.dart';

/// One control namespace in the configured installation database. Its name is
/// derived only from the stable internal installation identity.
String postgresAuthorityNamespace(OperationId instance) =>
    '"ub_install_${instance.value}"';

/// Current installation authority, isolated from universe packages and exports.
/// Catalog locations are backend namespaces, never fabricated file identities.
/// Reviewed import archives belong to installation authority, never universe exports.
Iterable<String> postgresAuthoritySchema(OperationId instance) sync* {
  final s = postgresAuthorityNamespace(instance);
  const text = 'TEXT COLLATE "C"';
  yield 'CREATE SCHEMA $s';
  yield 'CREATE TABLE $s.authority(singleton SMALLINT PRIMARY KEY CHECK(singleton=1), instance_id $text NOT NULL UNIQUE, normalization $text NOT NULL, schema_version SMALLINT NOT NULL CHECK(schema_version=6))';
  yield "INSERT INTO $s.authority VALUES(1,'${instance.value}','$selectorNormalizationVersion',6)";
  yield 'CREATE TABLE $s.profiles(id $text PRIMARY KEY, hash $text NOT NULL, author BOOLEAN NOT NULL, revoked BOOLEAN NOT NULL)';
  yield 'CREATE TABLE $s.catalog(id $text PRIMARY KEY, name BYTEA NOT NULL, schema_name $text NOT NULL UNIQUE)';
  yield 'CREATE TABLE $s.move_quiescence(universe $text PRIMARY KEY REFERENCES $s.catalog(id) ON DELETE CASCADE, operation $text NOT NULL UNIQUE, target_instance $text NOT NULL)';
  yield 'CREATE TABLE $s.move_stage(operation $text PRIMARY KEY REFERENCES $s.move_quiescence(operation) ON DELETE CASCADE, digest $text NOT NULL, records BIGINT NOT NULL CHECK(records>=0))';
  yield "CREATE TABLE $s.move_review(operation $text PRIMARY KEY REFERENCES $s.move_stage(operation) ON DELETE CASCADE, preview_id $text NOT NULL, owner $text NOT NULL, name BYTEA NOT NULL, source_digest $text NOT NULL, records BIGINT NOT NULL CHECK(records>=0), preview_digest $text NOT NULL, state $text NOT NULL CHECK(state IN ('reviewed','admitting','admitted')))";
  yield 'CREATE TABLE $s.move_archive(operation $text NOT NULL REFERENCES $s.move_stage(operation) ON DELETE CASCADE, ordinal BIGINT NOT NULL CHECK(ordinal>=0), content BYTEA NOT NULL CHECK(octet_length(content)>0 AND octet_length(content)<=262144), PRIMARY KEY(operation,ordinal))';
  yield 'CREATE TABLE $s.aliases(key $text PRIMARY KEY, universe $text NOT NULL REFERENCES $s.catalog(id))';
  yield "CREATE TABLE $s.grants(profile $text NOT NULL REFERENCES $s.profiles(id), universe $text NOT NULL REFERENCES $s.catalog(id), worlds_state $text NOT NULL CHECK(worlds_state IN ('all','listed')), propose BOOLEAN NOT NULL, edit BOOLEAN NOT NULL, protected BOOLEAN NOT NULL, entities_state $text NOT NULL CHECK(entities_state IN ('all','listed')), predicates_state $text NOT NULL CHECK(predicates_state IN ('all','listed')), continuities_state $text NOT NULL CHECK(continuities_state IN ('all','listed')), expires_at $text, delegated_commit BOOLEAN NOT NULL, allow_shared BOOLEAN NOT NULL, PRIMARY KEY(profile,universe))";
  for (final entry in {
    'worlds': 'world',
    'entities': 'entity',
    'predicates': 'predicate',
    'continuities': 'continuity',
  }.entries) {
    yield 'CREATE TABLE $s.grant_${entry.key}(profile $text NOT NULL, universe $text NOT NULL, ordinal BIGINT NOT NULL CHECK(ordinal>=0), ${entry.value} $text NOT NULL, PRIMARY KEY(profile,universe,ordinal), FOREIGN KEY(profile,universe) REFERENCES $s.grants(profile,universe))';
  }
  // Allocation under the authority lock matches SQLite's max+1 audit ordering
  // without sequence consumption from aborted transactions.
  yield 'CREATE TABLE $s.audit(sequence BIGINT PRIMARY KEY, actor $text NOT NULL, action $text NOT NULL, target $text NOT NULL)';
  yield 'CREATE TABLE $s.import_preview(id $text PRIMARY KEY, owner $text NOT NULL REFERENCES $s.profiles(id), source_digest $text NOT NULL, target $text NOT NULL, source $text NOT NULL, name BYTEA NOT NULL, complete BOOLEAN NOT NULL, omitted_records BIGINT NOT NULL CHECK(omitted_records>=0), records BIGINT NOT NULL CHECK(records>=0), includes_workflow BOOLEAN NOT NULL, preview_digest $text NOT NULL)';
  yield 'CREATE TABLE $s.archive_upload(id $text PRIMARY KEY, owner $text NOT NULL REFERENCES $s.profiles(id), source_digest $text NOT NULL, bytes BIGINT NOT NULL CHECK(bytes>0 AND bytes<=8589934592))';
  yield 'CREATE TABLE $s.archive_upload_chunk(upload $text NOT NULL REFERENCES $s.archive_upload(id) ON DELETE CASCADE, ordinal BIGINT NOT NULL CHECK(ordinal>=0 AND ordinal<32768), content BYTEA NOT NULL CHECK(octet_length(content)>0 AND octet_length(content)<=262144), PRIMARY KEY(upload,ordinal))';
  yield 'CREATE TABLE $s.import_archive(preview_id $text NOT NULL REFERENCES $s.import_preview(id), ordinal BIGINT NOT NULL CHECK(ordinal>=0), content BYTEA NOT NULL CHECK(octet_length(content)>0 AND octet_length(content)<=262144), PRIMARY KEY(preview_id,ordinal))';
}
