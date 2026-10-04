-- Fresh trusted-schema archive only. Import never executes input SQL.
CREATE TABLE archive_integrity (
 singleton INTEGER PRIMARY KEY CHECK(singleton=1),
 manifest_row INTEGER NOT NULL REFERENCES r_archive_manifest(__row_id),
 checksum_recipe TEXT NOT NULL CHECK(checksum_recipe='typed-row-stream'),
 sha256 TEXT NOT NULL,
 row_count INTEGER NOT NULL CHECK(row_count>=0),
 authority_state TEXT NOT NULL CHECK(authority_state='historical_evidence_only')
) STRICT;
-- Stream includes named tables/columns/typed cells in PK order, excluding archive_integrity
-- and r_archive_manifest. Any content byte cell is hex-encoded transiently for hashing.
-- This checksum does not claim byte equality with a legacy JSONL checksum.
