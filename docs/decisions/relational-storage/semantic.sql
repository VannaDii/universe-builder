-- Normative semantic projections over the single canonical model.
-- IDs below point to preserved universe/record identities, never labels.
CREATE TABLE type_definition (
 universe_id TEXT NOT NULL, version_id TEXT NOT NULL, record_id TEXT NOT NULL,
 name TEXT NOT NULL, parent_id TEXT, parent_resolution TEXT NOT NULL CHECK(parent_resolution IN ('root','resolved','ambiguous')), applicability TEXT NOT NULL CHECK(applicability IN ('universe','worlds','unspecified','conditional')),
 PRIMARY KEY(universe_id,version_id), UNIQUE(universe_id,version_id,record_id),
 FOREIGN KEY(universe_id,version_id,record_id) REFERENCES record_versions(universe_id,id,record_id),
 FOREIGN KEY(universe_id,parent_id) REFERENCES record_identities(universe_id,id),
 CHECK((parent_resolution='resolved' AND parent_id IS NOT NULL) OR (parent_resolution!='resolved' AND parent_id IS NULL))
) STRICT;
CREATE TABLE type_world (
 universe_id TEXT NOT NULL, version_id TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), world_id TEXT NOT NULL,
 PRIMARY KEY(universe_id,version_id,ordinal), UNIQUE(universe_id,version_id,world_id),
 FOREIGN KEY(universe_id,version_id) REFERENCES type_definition(universe_id,version_id),
 FOREIGN KEY(universe_id,world_id) REFERENCES record_identities(universe_id,id)
) STRICT;
CREATE TABLE instance_classification (
 universe_id TEXT NOT NULL, version_id TEXT NOT NULL, record_id TEXT NOT NULL, type_id TEXT,
 resolution TEXT NOT NULL CHECK(resolution IN ('resolved','unclassified','ambiguous')),
 PRIMARY KEY(universe_id,version_id),
 FOREIGN KEY(universe_id,version_id,record_id) REFERENCES record_versions(universe_id,id,record_id),
 FOREIGN KEY(universe_id,type_id) REFERENCES record_identities(universe_id,id),
 CHECK((resolution='resolved' AND type_id IS NOT NULL) OR (resolution!='resolved' AND type_id IS NULL))
) STRICT;
CREATE TABLE classification_evidence (
 universe_id TEXT NOT NULL, version_id TEXT NOT NULL, relationship TEXT NOT NULL CHECK(relationship IN ('parent','membership')),
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), type_id TEXT NOT NULL,
 PRIMARY KEY(universe_id,version_id,relationship,ordinal),
 FOREIGN KEY(universe_id,version_id) REFERENCES record_versions(universe_id,id),
 FOREIGN KEY(universe_id,type_id) REFERENCES record_identities(universe_id,id)
) STRICT;
CREATE TABLE definition_attribute (
 universe_id TEXT NOT NULL, assertion_version TEXT NOT NULL, subject_id TEXT NOT NULL, predicate_id TEXT NOT NULL,
 mode TEXT NOT NULL CHECK(mode IN ('shared','initial_value')),
 PRIMARY KEY(universe_id,assertion_version),
 FOREIGN KEY(universe_id,assertion_version) REFERENCES record_versions(universe_id,id),
 FOREIGN KEY(universe_id,subject_id) REFERENCES record_identities(universe_id,id),
 FOREIGN KEY(universe_id,predicate_id) REFERENCES record_identities(universe_id,id)
) STRICT;
-- Values, scope, time, context, basis and polarity live in the typed assertion/proposition rows.
-- Separate initialization evidence prevents start/refinement/rename from becoming a refill.
CREATE TABLE initialization_receipt (
 universe_id TEXT NOT NULL, instance_id TEXT NOT NULL, start_event_id TEXT NOT NULL, predicate_id TEXT NOT NULL,
 initial_definition_version TEXT NOT NULL, assertion_version TEXT NOT NULL, revision_id TEXT NOT NULL, source_revision TEXT NOT NULL,
 PRIMARY KEY(universe_id,instance_id,start_event_id,predicate_id),
 FOREIGN KEY(universe_id,instance_id) REFERENCES record_identities(universe_id,id),
 FOREIGN KEY(universe_id,start_event_id) REFERENCES record_identities(universe_id,id),
 FOREIGN KEY(universe_id,predicate_id) REFERENCES record_identities(universe_id,id),
 FOREIGN KEY(universe_id,initial_definition_version) REFERENCES record_versions(universe_id,id),
 FOREIGN KEY(universe_id,assertion_version) REFERENCES record_versions(universe_id,id),
 FOREIGN KEY(universe_id,revision_id) REFERENCES commits(universe_id,id),
 FOREIGN KEY(universe_id,source_revision) REFERENCES commits(universe_id,id)
) STRICT;
