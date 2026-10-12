import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'postgres_schema.dart';
import 'postgres_values.dart';
import 'workflow_keys.dart';

/// Closed evidence and actual source/media content. Install after typed bodies
/// and the kernel schema in the caller-owned provisioning transaction.
Iterable<String> postgresWorkflowSchema(UniverseId universe) sync* {
  final s = postgresUniverseSchema(universe);
  final families = workflowFamiliesByPrefix.values.toSet().toList();
  const text = 'TEXT COLLATE "C"';
  final columns = [
    'key BYTEA PRIMARY KEY',
    'family $text NOT NULL CHECK(family IN (${families.map((f) => "'$f'").join(',')}))',
    'digest $text NOT NULL',
    "digest_recipe $text NOT NULL CHECK(digest_recipe='workflow-canonical')",
    for (final family in families)
      '${postgresIdentifier(family)} BIGINT REFERENCES $s.${postgresIdentifier(BodyCatalog.instance.model(family).table)}(__row_id)',
    for (final family in families)
      "CHECK(family!='$family' OR (${families.map((f) => '${postgresIdentifier(f)} IS ${f == family ? 'NOT ' : ''}NULL').join(' AND ')}))",
  ];
  yield 'CREATE TABLE $s.workflow_entries(${columns.join(',')})';
  yield 'CREATE TABLE $s.source_content(digest $text PRIMARY KEY, byte_size BIGINT NOT NULL CHECK(byte_size>=0), utf8_content BYTEA NOT NULL, workflow_digest $text NOT NULL)';
  yield 'CREATE TABLE $s.source_staging(key BYTEA PRIMARY KEY, workflow_digest $text NOT NULL, source_version_row BIGINT NOT NULL REFERENCES $s.r_payload(__row_id))';
  yield 'CREATE TABLE $s.media_chunk(digest BYTEA NOT NULL, ordinal BIGINT NOT NULL CHECK(ordinal>=0), byte_size BIGINT NOT NULL, content BYTEA NOT NULL, historical_workflow_digest $text NOT NULL, PRIMARY KEY(digest,ordinal))';
  yield 'CREATE TABLE $s.image_staging(key BYTEA PRIMARY KEY, workflow_digest $text NOT NULL, image_asset_row BIGINT NOT NULL REFERENCES $s.r_payload(__row_id))';
  yield 'CREATE TABLE $s.continuity_name(continuity_id BYTEA PRIMARY KEY, key BYTEA NOT NULL UNIQUE, name BYTEA NOT NULL, workflow_digest $text NOT NULL)';
  yield 'CREATE VIEW $s.workflow_index AS SELECT key,digest FROM $s.workflow_entries '
      "UNION ALL SELECT convert_to('source:'||digest,'UTF8'),workflow_digest FROM $s.source_content "
      'UNION ALL SELECT key,workflow_digest FROM $s.source_staging '
      "UNION ALL SELECT convert_to('image-bytes:','UTF8')||digest||convert_to(':'||ordinal::text,'UTF8'),historical_workflow_digest FROM $s.media_chunk "
      'UNION ALL SELECT key,workflow_digest FROM $s.image_staging '
      'UNION ALL SELECT key,workflow_digest FROM $s.continuity_name';
  yield 'CREATE TABLE $s.historical_workflow(key BYTEA PRIMARY KEY REFERENCES $s.workflow_entries(key))';
  yield 'CREATE VIEW $s.active_workflow_index AS SELECT key,digest FROM $s.workflow_index WHERE key NOT IN '
      '(SELECT h.key FROM $s.historical_workflow h JOIN $s.workflow_entries e ON e.key=h.key '
      "WHERE e.family IN ('ApprovalEvidence','StoredOperation','StoredContext','Cursor'))";
  yield 'CREATE TABLE $s.import_workflow_digest(key BYTEA PRIMARY KEY, source_digest $text NOT NULL, normalized_digest $text NOT NULL)';
  for (final table in [
    'workflow_entries',
    'source_content',
    'source_staging',
    'media_chunk',
    'image_staging',
    'continuity_name',
    'historical_workflow',
    'import_workflow_digest',
  ]) {
    yield 'CREATE TRIGGER immutable_workflow BEFORE UPDATE OR DELETE ON $s.$table FOR EACH ROW EXECUTE FUNCTION $s.immutable_body()';
  }
}
