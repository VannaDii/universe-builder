-- Separate profiles/{profile}.sqlite, private 0600 file in a 0700 directory.
-- Never part of the package, logical archive or installation export.
CREATE TABLE credential (
 format_version INTEGER NOT NULL,
 profile_id TEXT PRIMARY KEY,
 credential TEXT NOT NULL
) STRICT;
