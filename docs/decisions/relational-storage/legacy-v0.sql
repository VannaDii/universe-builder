-- PROPOSED typed retention of legacy scalar headers. Unsupported bodies block conversion.
-- Universe Builder schema v0 (spec §28).
-- All legacy_worlds, shared canon, works, and editorial history in one database.

-- Schema metadata (internal).
CREATE TABLE IF NOT EXISTS legacy_schema_meta (
    key   TEXT PRIMARY KEY,
    value INTEGER NOT NULL DEFAULT 0
);

-- Universes: stable identity and metadata.
CREATE TABLE IF NOT EXISTS legacy_universes (
    id            TEXT PRIMARY KEY,  -- unv_<24 hex chars>
    name          TEXT NOT NULL,      -- author-facing name (unique)
    description   TEXT DEFAULT '',
    created_at    TEXT NOT NULL,      -- ISO 8601 timestamp
    format_version INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT uq_universe_name UNIQUE (name)
);

-- Record identities: stable IDs within a universe, with kind.
CREATE TABLE IF NOT EXISTS legacy_record_identities (
    id            TEXT PRIMARY KEY,  -- rec_<24 hex chars>
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    kind          TEXT NOT NULL,     -- entity_type, property, rule, ...
    created_at    TEXT NOT NULL,
    CONSTRAINT fk_ri_universe FOREIGN KEY (universe_id) REFERENCES legacy_universes(id)
);

-- Worlds: named world records within a universe.
CREATE TABLE IF NOT EXISTS legacy_worlds (
    id            TEXT PRIMARY KEY,  -- wld_<24 hex chars>
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    name          TEXT NOT NULL,     -- unique within universe
    description   TEXT DEFAULT '',
    created_at    TEXT NOT NULL,
    CONSTRAINT fk_world_universe FOREIGN KEY (universe_id) REFERENCES legacy_universes(id),
    CONSTRAINT uq_world_name UNIQUE (universe_id, name)
);

-- World name reservations: non-rebinding selector reservations.
CREATE TABLE IF NOT EXISTS legacy_world_name_reservations (
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    name          TEXT NOT NULL,
    world_id      TEXT NOT NULL REFERENCES legacy_worlds(id),
    reserved_at   TEXT NOT NULL,
    PRIMARY KEY (universe_id, name)
);

-- Record versions: immutable typed payloads with schema version and digest.
CREATE TABLE IF NOT EXISTS legacy_record_versions (
    id            TEXT PRIMARY KEY,  -- ver_<24 hex chars>
    record_id     TEXT NOT NULL REFERENCES legacy_record_identities(id),
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    kind          TEXT NOT NULL,     -- matches record_identity.kind
    schema_version INTEGER NOT NULL DEFAULT 0,
    payload_row INTEGER NOT NULL REFERENCES r_payload(__row_id), -- recognized typed legacy canon only
    digest        TEXT NOT NULL,     -- SHA-256 of payload
    created_at    TEXT NOT NULL,
    CONSTRAINT fk_rv_record FOREIGN KEY (record_id) REFERENCES legacy_record_identities(id),
    CONSTRAINT fk_rv_universe FOREIGN KEY (universe_id) REFERENCES legacy_universes(id)
);

-- Commits: editorial parent chain with author and reason.
CREATE TABLE IF NOT EXISTS legacy_commits (
    id            TEXT PRIMARY KEY,  -- commit_<24 hex chars>
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    continuity_id TEXT NOT NULL DEFAULT 'main',
    parent_id     TEXT REFERENCES legacy_commits(id),  -- linear editorial chain
    author        TEXT NOT NULL,      -- principal ID or name
    reason        TEXT DEFAULT '',
    canon_revision INTEGER NOT NULL DEFAULT 0,
    created_at    TEXT NOT NULL,
    CONSTRAINT fk_commit_universe FOREIGN KEY (universe_id) REFERENCES legacy_universes(id)
);

-- Commit changes: record-version additions/replacements/tombstones.
CREATE TABLE IF NOT EXISTS legacy_commit_changes (
    id            TEXT PRIMARY KEY,  -- cc_<24 hex chars>
    commit_id     TEXT NOT NULL REFERENCES legacy_commits(id),
    record_id     TEXT NOT NULL,
    action        TEXT NOT NULL,     -- create, replace, tombstone
    version_id    TEXT REFERENCES legacy_record_versions(id),
    CONSTRAINT fk_cc_commit FOREIGN KEY (commit_id) REFERENCES legacy_commits(id)
);

-- Continuities: current head and pinned inheritance baseline.
CREATE TABLE IF NOT EXISTS legacy_continuities (
    id            TEXT PRIMARY KEY,  -- cont_<name>
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    head_commit   TEXT NOT NULL,     -- latest commit id
    baseline_commit TEXT,           -- pinned inheritance baseline (nullable)
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL,
    CONSTRAINT fk_cont_universe FOREIGN KEY (universe_id) REFERENCES legacy_universes(id)
);

-- Head membership: effective record-version map for each continuity head.
CREATE TABLE IF NOT EXISTS legacy_head_membership (
    id            TEXT PRIMARY KEY,  -- hm_<24 hex chars>
    continuity_id TEXT NOT NULL REFERENCES legacy_continuities(id),
    record_id     TEXT NOT NULL,
    version_id    TEXT NOT NULL REFERENCES legacy_record_versions(id),
    CONSTRAINT fk_hm_cont FOREIGN KEY (continuity_id) REFERENCES legacy_continuities(id),
    CONSTRAINT fk_hm_ver FOREIGN KEY (version_id) REFERENCES legacy_record_versions(id)
);

-- Assertion index: indexed query access by predicate, entity, scope.
CREATE TABLE IF NOT EXISTS legacy_assertion_index (
    id            TEXT PRIMARY KEY,  -- ai_<24 hex chars>
    proposition_id TEXT NOT NULL,
    assertion_type TEXT NOT NULL,    -- support, refutation
    entity_id     TEXT REFERENCES legacy_record_identities(id),
    predicate     TEXT NOT NULL,
    scope         TEXT DEFAULT 'universe',  -- universe, world, conditional
    validity_from TEXT,             -- half-open interval start
    validity_to   TEXT,             -- half-open interval end (NULL = unbounded)
    world_id      TEXT REFERENCES legacy_worlds(id),
    CONSTRAINT fk_ai_prop FOREIGN KEY (proposition_id) REFERENCES legacy_record_identities(id)
);

-- Participant index: indexed by entity for relationship queries.
CREATE TABLE IF NOT EXISTS legacy_participant_index (
    id            TEXT PRIMARY KEY,  -- pi_<24 hex chars>
    record_id     TEXT NOT NULL,
    participant_id TEXT NOT NULL REFERENCES legacy_record_identities(id),
    role          TEXT DEFAULT '',
    CONSTRAINT fk_pi_rec FOREIGN KEY (record_id) REFERENCES legacy_record_identities(id),
    CONSTRAINT fk_pi_part FOREIGN KEY (participant_id) REFERENCES legacy_record_identities(id)
);

-- Time index: indexed by temporal frame for time-range queries.
CREATE TABLE IF NOT EXISTS legacy_time_index (
    id            TEXT PRIMARY KEY,  -- ti_<24 hex chars>
    record_id     TEXT NOT NULL,
    temporal_from TEXT,             -- half-open interval start
    temporal_to   TEXT,             -- half-open interval end (NULL = unbounded)
    CONSTRAINT fk_ti_rec FOREIGN KEY (record_id) REFERENCES legacy_record_identities(id)
);

-- Source versions: version-specific provenance.
CREATE TABLE IF NOT EXISTS legacy_source_versions (
    id            TEXT PRIMARY KEY,  -- sv_<24 hex chars>
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    source_identity TEXT NOT NULL,   -- external source ID
    content_digest  TEXT NOT NULL,   -- SHA-256 of source content
    media_type    TEXT DEFAULT 'text/plain',
    imported_at   TEXT NOT NULL,
    CONSTRAINT fk_sv_universe FOREIGN KEY (universe_id) REFERENCES legacy_universes(id)
);

-- Anchors: immutable source version + structural path.
CREATE TABLE IF NOT EXISTS legacy_anchors (
    id            TEXT PRIMARY KEY,  -- anch_<24 hex chars>
    source_version_id TEXT NOT NULL REFERENCES legacy_source_versions(id),
    record_ref    TEXT NOT NULL,     -- record reference this anchor points to
    path          TEXT DEFAULT '',   -- structural path within source
    excerpt       TEXT DEFAULT '',   -- exact excerpt text
    CONSTRAINT fk_anch_sv FOREIGN KEY (source_version_id) REFERENCES legacy_source_versions(id)
);

-- Blob references: database-side reference to content-addressed blobs.
CREATE TABLE IF NOT EXISTS legacy_blob_refs (
    id            TEXT PRIMARY KEY,  -- br_<24 hex chars>
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    digest        TEXT NOT NULL,     -- SHA-256 digest (matches blob store)
    mime_type     TEXT DEFAULT '',
    size_bytes    INTEGER NOT NULL DEFAULT 0,
    referenced_at TEXT NOT NULL,
    CONSTRAINT fk_br_universe FOREIGN KEY (universe_id) REFERENCES legacy_universes(id)
);

-- Changesets: proposal lifecycle.
CREATE TABLE IF NOT EXISTS legacy_changesets (
    id            TEXT PRIMARY KEY,  -- cs_<24 hex chars>
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    continuity_id TEXT DEFAULT 'main',
    base_revision  INTEGER NOT NULL DEFAULT 0,
    author        TEXT NOT NULL,
    rationale     TEXT DEFAULT '',
    status        TEXT NOT NULL DEFAULT 'draft',  -- draft, submitted, committed, rejected, withdrawn
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL,
    CONSTRAINT fk_cs_universe FOREIGN KEY (universe_id) REFERENCES legacy_universes(id)
);

-- Changeset versions: immutable proposal snapshots.
CREATE TABLE IF NOT EXISTS legacy_changeset_versions (
    id            TEXT PRIMARY KEY,  -- csv_<24 hex chars>
    changeset_id  TEXT NOT NULL REFERENCES legacy_changesets(id),
    operations_row INTEGER NOT NULL REFERENCES r_proposal_operations(__row_id), -- recognized ordered DomainOperation array only
    digest        TEXT NOT NULL,     -- SHA-256 of payload
    version       INTEGER NOT NULL DEFAULT 0,
    created_at    TEXT NOT NULL,
    CONSTRAINT csv_cs FOREIGN KEY (changeset_id) REFERENCES legacy_changesets(id)
);

-- Approvals: exact approved payload binding.
CREATE TABLE IF NOT EXISTS legacy_approvals (
    id            TEXT PRIMARY KEY,  -- ap_<24 hex chars>
    changeset_id  TEXT NOT NULL REFERENCES legacy_changesets(id),
    version       INTEGER NOT NULL,
    payload_digest  TEXT NOT NULL,   -- SHA-256 of approved payload
    author        TEXT NOT NULL,
    scope         TEXT DEFAULT 'universe',  -- universe, world, predicate-scoped
    granted_at    TEXT NOT NULL,
    expires_at    TEXT,             -- nullable expiry (NULL = no expiry)
    revoked       INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT fk_ap_cs FOREIGN KEY (changeset_id) REFERENCES legacy_changesets(id)
);

-- Validation runs: bounded results with evidence and coverage.
CREATE TABLE IF NOT EXISTS legacy_validation_runs (
    id            TEXT PRIMARY KEY,  -- vr_<24 hex chars>
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    continuity_id TEXT DEFAULT 'main',
    base_revision  INTEGER NOT NULL DEFAULT 0,
    evaluator_version TEXT DEFAULT 'v1',
    status        TEXT NOT NULL DEFAULT 'pending',  -- pending, complete, partial, failed
    created_at    TEXT NOT NULL,
    CONSTRAINT fk_vr_universe FOREIGN KEY (universe_id) REFERENCES legacy_universes(id)
);

-- Findings: per-rule results with evidence and coverage.
CREATE TABLE IF NOT EXISTS legacy_findings (
    id            TEXT PRIMARY KEY,  -- fn_<24 hex chars>
    validation_run_id TEXT NOT NULL REFERENCES legacy_validation_runs(id),
    rule_id       TEXT NOT NULL,
    affected_record_id TEXT,        -- nullable: may affect multiple records
    outcome       TEXT NOT NULL,     -- conflict, no_conflict, indeterminate
    evidence_row INTEGER REFERENCES r_finding(__row_id), -- recognized evidence contract only; otherwise block
    coverage      TEXT NOT NULL,     -- complete, partial, failed, unsupported
    CONSTRAINT fk_fn_vr FOREIGN KEY (validation_run_id) REFERENCES legacy_validation_runs(id)
);

-- Dependencies: cross-rule dependency tracking for invalidation.
CREATE TABLE IF NOT EXISTS legacy_dependencies (
    id            TEXT PRIMARY KEY,  -- dep_<24 hex chars>
    finding_id    TEXT NOT NULL REFERENCES legacy_findings(id),
    depends_on_record_id TEXT,       -- record this finding depends on
    CONSTRAINT fk_dep_fn FOREIGN KEY (finding_id) REFERENCES legacy_findings(id)
);

-- Operation receipts: durable retry and recovery (spec §10.5).
CREATE TABLE IF NOT EXISTS legacy_operation_receipts (
    id            TEXT PRIMARY KEY,  -- op_<24 hex chars>
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    principal     TEXT NOT NULL,
    operation_kind TEXT NOT NULL,    -- propose, commit, validate, ...
    idempotency_key TEXT NOT NULL,   -- unique per principal+kind
    payload_digest  TEXT NOT NULL,   -- SHA-256 of original payload
    result_row INTEGER REFERENCES r_stored_operation(__row_id), -- recognized receipt result contract only; otherwise block
    status        TEXT NOT NULL DEFAULT 'pending',  -- pending, completed, cancelled
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL,
    CONSTRAINT fk_op_universe FOREIGN KEY (universe_id) REFERENCES legacy_universes(id),
    CONSTRAINT uq_op_key UNIQUE (universe_id, principal, operation_kind, idempotency_key)
);

-- Idempotency keys tombstone: non-reusable key marker.
CREATE TABLE IF NOT EXISTS legacy_idempotency_keys (
    universe_id   TEXT NOT NULL REFERENCES legacy_universes(id),
    principal     TEXT NOT NULL,
    operation_kind TEXT NOT NULL,
    key           TEXT NOT NULL,
    tombstoned_at TEXT NOT NULL,
    PRIMARY KEY (universe_id, principal, operation_kind, key)
);

-- FTS5 full-text indexes for names, descriptions, and approved searchable text.
CREATE VIRTUAL TABLE IF NOT EXISTS legacy_fts_universes USING fts5(
    name, description, content='legacy_universes', content_rowid='rowid'
);

CREATE VIRTUAL TABLE IF NOT EXISTS legacy_fts_entities USING fts5(
    name, description, content='legacy_record_identities', content_rowid='rowid'
);

CREATE VIRTUAL TABLE IF NOT EXISTS legacy_fts_worlds USING fts5(
    name, description, content='legacy_worlds', content_rowid='rowid'
);

CREATE VIRTUAL TABLE IF NOT EXISTS legacy_fts_sources USING fts5(
    source_identity, excerpt, content='legacy_anchors', content_rowid='rowid'
);
