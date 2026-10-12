import 'package:ub_domain/ub_domain.dart';

import 'postgres_values.dart';

/// Normative semantic projections and initialization receipts. Provision after
/// body/history tables in the caller-owned transaction.
Iterable<String> postgresSemanticSchema(UniverseId universe) sync* {
  final s = postgresUniverseSchema(universe);
  yield '''CREATE TABLE $s.type_definition (
 universe_id TEXT COLLATE "C" NOT NULL, version_id TEXT COLLATE "C" NOT NULL, record_id TEXT COLLATE "C" NOT NULL,
 name BYTEA NOT NULL, parent_id TEXT COLLATE "C", parent_resolution TEXT COLLATE "C" NOT NULL CHECK(parent_resolution IN ('root','resolved','ambiguous')), applicability TEXT COLLATE "C" NOT NULL CHECK(applicability IN ('universe','worlds','unspecified','conditional')),
 PRIMARY KEY(universe_id,version_id), UNIQUE(universe_id,version_id,record_id),
 FOREIGN KEY(universe_id,version_id,record_id) REFERENCES $s.record_versions(universe_id,id,record_id),
 FOREIGN KEY(universe_id,parent_id) REFERENCES $s.record_identities(universe_id,id),
 CHECK((parent_resolution='resolved' AND parent_id IS NOT NULL) OR (parent_resolution!='resolved' AND parent_id IS NULL))
)''';
  yield '''CREATE TABLE $s.type_world (
 universe_id TEXT COLLATE "C" NOT NULL, version_id TEXT COLLATE "C" NOT NULL, ordinal BIGINT NOT NULL CHECK(ordinal>=0), world_id TEXT COLLATE "C" NOT NULL,
 PRIMARY KEY(universe_id,version_id,ordinal), UNIQUE(universe_id,version_id,world_id),
 FOREIGN KEY(universe_id,version_id) REFERENCES $s.type_definition(universe_id,version_id),
 FOREIGN KEY(universe_id,world_id) REFERENCES $s.record_identities(universe_id,id)
)''';
  yield '''CREATE TABLE $s.instance_classification (
 universe_id TEXT COLLATE "C" NOT NULL, version_id TEXT COLLATE "C" NOT NULL, record_id TEXT COLLATE "C" NOT NULL, type_id TEXT COLLATE "C",
 resolution TEXT COLLATE "C" NOT NULL CHECK(resolution IN ('resolved','unclassified','ambiguous')),
 PRIMARY KEY(universe_id,version_id),
 FOREIGN KEY(universe_id,version_id,record_id) REFERENCES $s.record_versions(universe_id,id,record_id),
 FOREIGN KEY(universe_id,type_id) REFERENCES $s.record_identities(universe_id,id),
 CHECK((resolution='resolved' AND type_id IS NOT NULL) OR (resolution!='resolved' AND type_id IS NULL))
)''';
  yield '''CREATE TABLE $s.classification_evidence (
 universe_id TEXT COLLATE "C" NOT NULL, version_id TEXT COLLATE "C" NOT NULL, relationship TEXT COLLATE "C" NOT NULL CHECK(relationship IN ('parent','membership')),
 ordinal BIGINT NOT NULL CHECK(ordinal>=0), type_id TEXT COLLATE "C" NOT NULL,
 PRIMARY KEY(universe_id,version_id,relationship,ordinal),
 FOREIGN KEY(universe_id,version_id) REFERENCES $s.record_versions(universe_id,id),
 FOREIGN KEY(universe_id,type_id) REFERENCES $s.record_identities(universe_id,id)
)''';
  yield '''CREATE TABLE $s.definition_attribute (
 universe_id TEXT COLLATE "C" NOT NULL, assertion_version TEXT COLLATE "C" NOT NULL, subject_id TEXT COLLATE "C" NOT NULL, predicate_id TEXT COLLATE "C" NOT NULL,
 mode TEXT COLLATE "C" NOT NULL CHECK(mode IN ('shared','initial_value')),
 PRIMARY KEY(universe_id,assertion_version),
 FOREIGN KEY(universe_id,assertion_version) REFERENCES $s.record_versions(universe_id,id),
 FOREIGN KEY(universe_id,subject_id) REFERENCES $s.record_identities(universe_id,id),
 FOREIGN KEY(universe_id,predicate_id) REFERENCES $s.record_identities(universe_id,id)
)''';
  yield '''CREATE TABLE $s.initialization_receipt (
 universe_id TEXT COLLATE "C" NOT NULL, instance_id TEXT COLLATE "C" NOT NULL, start_event_id TEXT COLLATE "C" NOT NULL, predicate_id TEXT COLLATE "C" NOT NULL,
 initial_definition_version TEXT COLLATE "C" NOT NULL, assertion_version TEXT COLLATE "C" NOT NULL, revision_id TEXT COLLATE "C" NOT NULL, source_revision TEXT COLLATE "C" NOT NULL,
 PRIMARY KEY(universe_id,instance_id,start_event_id,predicate_id),
 FOREIGN KEY(universe_id,instance_id) REFERENCES $s.record_identities(universe_id,id),
 FOREIGN KEY(universe_id,start_event_id) REFERENCES $s.record_identities(universe_id,id),
 FOREIGN KEY(universe_id,predicate_id) REFERENCES $s.record_identities(universe_id,id),
 FOREIGN KEY(universe_id,initial_definition_version) REFERENCES $s.record_versions(universe_id,id),
 FOREIGN KEY(universe_id,assertion_version) REFERENCES $s.record_versions(universe_id,id),
 FOREIGN KEY(universe_id,revision_id) REFERENCES $s.commits(universe_id,id),
 FOREIGN KEY(universe_id,source_revision) REFERENCES $s.commits(universe_id,id)
)''';
}
