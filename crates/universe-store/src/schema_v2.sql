-- Noncanonical workflow evidence is durable and append-only in the owned package.
CREATE TABLE workflow_entries (
    key TEXT PRIMARY KEY NOT NULL,
    payload BLOB NOT NULL,
    digest TEXT NOT NULL
) STRICT;
CREATE TRIGGER workflow_entries_no_update BEFORE UPDATE ON workflow_entries
BEGIN SELECT RAISE(ABORT, 'immutable workflow entry'); END;
CREATE TRIGGER workflow_entries_no_delete BEFORE DELETE ON workflow_entries
BEGIN SELECT RAISE(ABORT, 'immutable workflow entry'); END;
