-- PROPOSED: existing kernel identities and constraints retained, payload/cache authority replaced.
-- Durable kernel. Each database contains exactly one universe.
CREATE TABLE schema_meta(key TEXT PRIMARY KEY,value INTEGER NOT NULL) STRICT;
INSERT INTO schema_meta VALUES ('schema_version',3);
CREATE TABLE universes(id TEXT PRIMARY KEY, singleton INTEGER NOT NULL DEFAULT 1 UNIQUE CHECK(singleton=1), name TEXT NOT NULL);
CREATE TABLE record_identities(universe_id TEXT NOT NULL REFERENCES universes(id), id TEXT NOT NULL, kind TEXT NOT NULL, PRIMARY KEY(universe_id,id), UNIQUE(universe_id,id,kind));
CREATE TABLE record_versions(universe_id TEXT NOT NULL, id TEXT NOT NULL, record_id TEXT NOT NULL, kind TEXT NOT NULL, schema_version TEXT NOT NULL, storage_layout TEXT NOT NULL CHECK(storage_layout IN ('legacy','type_v3','instance_v3','attribute_v3')),
 payload_row INTEGER REFERENCES r_payload(__row_id),
 type_row INTEGER REFERENCES r_type_definition_v3(__row_id), instance_row INTEGER REFERENCES r_instance_v3(__row_id), attribute_row INTEGER REFERENCES r_attribute_assertion_v3(__row_id), digest TEXT NOT NULL, CHECK((storage_layout='legacy' AND payload_row IS NOT NULL AND type_row IS NULL AND instance_row IS NULL AND attribute_row IS NULL)
 OR (storage_layout='type_v3' AND payload_row IS NULL AND type_row IS NOT NULL AND instance_row IS NULL AND attribute_row IS NULL AND kind='entity_type' AND schema_version='v3')
 OR (storage_layout='instance_v3' AND payload_row IS NULL AND type_row IS NULL AND instance_row IS NOT NULL AND attribute_row IS NULL AND kind='entity' AND schema_version='v3')
 OR (storage_layout='attribute_v3' AND payload_row IS NULL AND type_row IS NULL AND instance_row IS NULL AND attribute_row IS NOT NULL AND kind='assertion' AND schema_version='v3')),
 PRIMARY KEY(universe_id,id), UNIQUE(universe_id,id,record_id), FOREIGN KEY(universe_id,record_id,kind) REFERENCES record_identities(universe_id,id,kind));
CREATE TABLE continuities(universe_id TEXT NOT NULL REFERENCES universes(id), id TEXT NOT NULL, head_commit TEXT NOT NULL, baseline_commit TEXT, PRIMARY KEY(universe_id,id), FOREIGN KEY(universe_id,head_commit,id) REFERENCES commits(universe_id,id,continuity_id) DEFERRABLE INITIALLY DEFERRED, FOREIGN KEY(universe_id,baseline_commit) REFERENCES commits(universe_id,id));
CREATE TABLE commits(universe_id TEXT NOT NULL, id TEXT NOT NULL, continuity_id TEXT NOT NULL, parent_id TEXT, sequence INTEGER NOT NULL CHECK(sequence>=0), principal TEXT NOT NULL, decision TEXT NOT NULL, reason TEXT NOT NULL, digest TEXT NOT NULL, PRIMARY KEY(universe_id,id), UNIQUE(universe_id,continuity_id,sequence), UNIQUE(universe_id,id,continuity_id), FOREIGN KEY(universe_id,continuity_id) REFERENCES continuities(universe_id,id) DEFERRABLE INITIALLY DEFERRED, FOREIGN KEY(universe_id,parent_id,continuity_id) REFERENCES commits(universe_id,id,continuity_id));
CREATE TABLE commit_changes(universe_id TEXT NOT NULL, revision_id TEXT NOT NULL, record_id TEXT NOT NULL, prior_version TEXT, version_id TEXT, PRIMARY KEY(universe_id,revision_id,record_id), FOREIGN KEY(universe_id,revision_id) REFERENCES commits(universe_id,id), FOREIGN KEY(universe_id,record_id) REFERENCES record_identities(universe_id,id), FOREIGN KEY(universe_id,prior_version,record_id) REFERENCES record_versions(universe_id,id,record_id), FOREIGN KEY(universe_id,version_id,record_id) REFERENCES record_versions(universe_id,id,record_id));
CREATE TABLE world_name_reservations(universe_id TEXT NOT NULL, name TEXT NOT NULL, record_id TEXT NOT NULL, first_revision TEXT NOT NULL, PRIMARY KEY(universe_id,name), FOREIGN KEY(universe_id,record_id) REFERENCES record_identities(universe_id,id), FOREIGN KEY(universe_id,first_revision) REFERENCES commits(universe_id,id));
CREATE TABLE head_membership(universe_id TEXT NOT NULL, continuity_id TEXT NOT NULL, record_id TEXT NOT NULL, version_id TEXT NOT NULL, PRIMARY KEY(universe_id,continuity_id,record_id), FOREIGN KEY(universe_id,continuity_id) REFERENCES continuities(universe_id,id), FOREIGN KEY(universe_id,version_id,record_id) REFERENCES record_versions(universe_id,id,record_id));
CREATE TABLE projection_heads(universe_id TEXT NOT NULL, continuity_id TEXT NOT NULL, revision_id TEXT NOT NULL, checksum TEXT NOT NULL, PRIMARY KEY(universe_id,continuity_id));
CREATE TABLE snapshot_membership(universe_id TEXT NOT NULL, revision_id TEXT NOT NULL,  checksum TEXT NOT NULL, PRIMARY KEY(universe_id,revision_id), FOREIGN KEY(universe_id,revision_id) REFERENCES commits(universe_id,id));
CREATE TABLE projection_state(singleton INTEGER PRIMARY KEY CHECK(singleton=1), generation INTEGER NOT NULL);
INSERT INTO projection_state VALUES(1,0);
CREATE TABLE reference_index(generation INTEGER NOT NULL, version_id TEXT NOT NULL, target_record TEXT NOT NULL, target_version TEXT, path TEXT NOT NULL);
CREATE TABLE typed_projection(generation INTEGER NOT NULL, version_id TEXT NOT NULL, path TEXT NOT NULL, value TEXT NOT NULL);
CREATE TABLE world_projection(generation INTEGER NOT NULL, version_id TEXT NOT NULL, world_id TEXT NOT NULL);
CREATE TABLE narrative_projection(generation INTEGER NOT NULL, version_id TEXT NOT NULL, target_record TEXT NOT NULL, path TEXT NOT NULL);
CREATE VIRTUAL TABLE search_index USING fts5(generation UNINDEXED, version_id UNINDEXED, text);
CREATE INDEX reference_target ON reference_index(generation,target_record);
CREATE INDEX typed_lookup ON typed_projection(generation,path,value);
CREATE INDEX world_lookup ON world_projection(generation,world_id);
CREATE TABLE operation_receipts(universe_id TEXT NOT NULL REFERENCES universes(id), principal TEXT NOT NULL, operation_kind TEXT NOT NULL, idempotency_key TEXT NOT NULL, payload_digest TEXT NOT NULL, revision_id TEXT NOT NULL, PRIMARY KEY(universe_id,principal,operation_kind,idempotency_key), FOREIGN KEY(universe_id,revision_id) REFERENCES commits(universe_id,id));
CREATE TRIGGER immutable_record_identities_update BEFORE UPDATE ON record_identities BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_record_identities_delete BEFORE DELETE ON record_identities BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_record_versions_update BEFORE UPDATE ON record_versions BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_record_versions_delete BEFORE DELETE ON record_versions BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_commits_update BEFORE UPDATE ON commits BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_commits_delete BEFORE DELETE ON commits BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_commit_changes_update BEFORE UPDATE ON commit_changes BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_commit_changes_delete BEFORE DELETE ON commit_changes BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_world_name_reservations_update BEFORE UPDATE ON world_name_reservations BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_world_name_reservations_delete BEFORE DELETE ON world_name_reservations BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_operation_receipts_update BEFORE UPDATE ON operation_receipts BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_operation_receipts_delete BEFORE DELETE ON operation_receipts BEGIN SELECT RAISE(ABORT,'immutable canon history'); END;
CREATE TRIGGER immutable_branch BEFORE UPDATE OF universe_id,id,baseline_commit ON continuities BEGIN SELECT RAISE(ABORT,'immutable branch descriptor'); END;

CREATE TRIGGER immutable_universe_id BEFORE UPDATE OF id ON universes BEGIN SELECT RAISE(ABORT,'immutable universe identity'); END;
CREATE TRIGGER immutable_universe_delete BEFORE DELETE ON universes BEGIN SELECT RAISE(ABORT,'immutable universe identity'); END;

CREATE TABLE snapshot_member (universe_id TEXT NOT NULL, revision_id TEXT NOT NULL, record_id TEXT NOT NULL, version_id TEXT NOT NULL,
 PRIMARY KEY(universe_id,revision_id,record_id), FOREIGN KEY(universe_id,revision_id) REFERENCES snapshot_membership(universe_id,revision_id),
 FOREIGN KEY(universe_id,version_id,record_id) REFERENCES record_versions(universe_id,id,record_id)) STRICT;
