import 'package:ub_domain/ub_domain.dart';

import 'postgres_values.dart';

/// Rebuildable projections, provisioned after the canonical body/history tables.
/// Authored text and scalar/path tokens remain exact bytes. Only the disposable
/// search document uses PostgreSQL's text parser.
Iterable<String> postgresProjectionSchema(UniverseId universe) sync* {
  final s = postgresUniverseSchema(universe);
  const text = 'TEXT COLLATE "C"';
  yield 'CREATE TABLE $s.projection_state(singleton SMALLINT PRIMARY KEY CHECK(singleton=1), generation BIGINT NOT NULL)';
  yield 'INSERT INTO $s.projection_state VALUES(1,0)';
  yield 'CREATE TABLE $s.reference_index(generation BIGINT NOT NULL, version_id $text NOT NULL, target_record $text NOT NULL, target_version $text, path BYTEA NOT NULL)';
  yield 'CREATE TABLE $s.typed_projection(generation BIGINT NOT NULL, version_id $text NOT NULL, path BYTEA NOT NULL, value BYTEA NOT NULL)';
  yield 'CREATE TABLE $s.world_projection(generation BIGINT NOT NULL, version_id $text NOT NULL, world_id $text NOT NULL)';
  yield 'CREATE TABLE $s.narrative_projection(generation BIGINT NOT NULL, version_id $text NOT NULL, target_record $text NOT NULL, path BYTEA NOT NULL)';
  yield 'CREATE TABLE $s.search_index(generation BIGINT NOT NULL, version_id $text NOT NULL, text BYTEA NOT NULL, document TSVECTOR NOT NULL)';
  yield 'CREATE INDEX reference_target ON $s.reference_index(generation,target_record)';
  yield 'CREATE INDEX typed_lookup ON $s.typed_projection(generation,path,value)';
  yield 'CREATE INDEX world_lookup ON $s.world_projection(generation,world_id)';
  yield 'CREATE INDEX search_document ON $s.search_index USING GIN(document)';
}
