-- Closed workflow families: typed pointers preserve exact historical key and digest.
CREATE TABLE workflow_entries (
 key TEXT PRIMARY KEY,
 family TEXT NOT NULL CHECK(family IN ('StoredContext','StoredProposal','Checked','StoredOperation','ApprovalEvidence','AssessmentEnvelope','AssessmentSelection','AssessmentReceipt','Cursor','Cancellation','ReservedRecord','SavedDraft','ImportOrigin','ImportAdmission')),
 digest TEXT NOT NULL,
 digest_recipe TEXT NOT NULL CHECK(digest_recipe IN ('workflow-canonical')),
 "StoredContext" INTEGER REFERENCES "r_stored_context"(__row_id),
 "StoredProposal" INTEGER REFERENCES "r_stored_proposal"(__row_id),
 "Checked" INTEGER REFERENCES "r_checked"(__row_id),
 "StoredOperation" INTEGER REFERENCES "r_stored_operation"(__row_id),
 "ApprovalEvidence" INTEGER REFERENCES "r_approval_evidence"(__row_id),
 "AssessmentEnvelope" INTEGER REFERENCES "r_assessment_envelope"(__row_id),
 "AssessmentSelection" INTEGER REFERENCES "r_assessment_selection"(__row_id),
 "AssessmentReceipt" INTEGER REFERENCES "r_assessment_receipt"(__row_id),
 "Cursor" INTEGER REFERENCES "r_cursor"(__row_id),
 "Cancellation" INTEGER REFERENCES "r_cancellation"(__row_id),
 "ReservedRecord" INTEGER REFERENCES "r_reserved_record"(__row_id),
 "SavedDraft" INTEGER REFERENCES "r_saved_draft"(__row_id),
 "ImportOrigin" INTEGER REFERENCES "r_import_origin"(__row_id),
 "ImportAdmission" INTEGER REFERENCES "r_import_admission"(__row_id),
 CHECK(family!='StoredContext' OR ("StoredContext" IS NOT NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='StoredProposal' OR ("StoredContext" IS NULL AND "StoredProposal" IS NOT NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='Checked' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NOT NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='StoredOperation' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NOT NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='ApprovalEvidence' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NOT NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='AssessmentEnvelope' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NOT NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='AssessmentSelection' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NOT NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='AssessmentReceipt' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NOT NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='Cursor' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NOT NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='Cancellation' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NOT NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='ReservedRecord' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NOT NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='SavedDraft' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NOT NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='ImportOrigin' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NOT NULL AND "ImportAdmission" IS NULL)),
 CHECK(family!='ImportAdmission' OR ("StoredContext" IS NULL AND "StoredProposal" IS NULL AND "Checked" IS NULL AND "StoredOperation" IS NULL AND "ApprovalEvidence" IS NULL AND "AssessmentEnvelope" IS NULL AND "AssessmentSelection" IS NULL AND "AssessmentReceipt" IS NULL AND "Cursor" IS NULL AND "Cancellation" IS NULL AND "ReservedRecord" IS NULL AND "SavedDraft" IS NULL AND "ImportOrigin" IS NULL AND "ImportAdmission" IS NOT NULL))
) STRICT;
CREATE TABLE source_content(digest TEXT PRIMARY KEY, byte_size INTEGER NOT NULL CHECK(byte_size>=0), utf8_content BLOB NOT NULL, workflow_digest TEXT NOT NULL) STRICT;
CREATE TABLE source_staging(key TEXT PRIMARY KEY, workflow_digest TEXT NOT NULL, source_version_row INTEGER NOT NULL REFERENCES r_payload(__row_id)) STRICT;
CREATE TABLE media_chunk(digest TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), byte_size INTEGER NOT NULL, content BLOB NOT NULL, historical_workflow_digest TEXT NOT NULL, PRIMARY KEY(digest,ordinal)) STRICT;
CREATE TABLE image_staging(key TEXT PRIMARY KEY, workflow_digest TEXT NOT NULL, image_asset_row INTEGER NOT NULL REFERENCES r_payload(__row_id)) STRICT;
CREATE TABLE continuity_name(continuity_id TEXT PRIMARY KEY, key TEXT NOT NULL UNIQUE, name TEXT NOT NULL, workflow_digest TEXT NOT NULL) STRICT;
-- BLOBs above are actual source/media content only, never application metadata.
CREATE TRIGGER workflow_entries_no_update BEFORE UPDATE ON workflow_entries BEGIN SELECT RAISE(ABORT,'immutable workflow entry'); END;
CREATE TRIGGER workflow_entries_no_delete BEFORE DELETE ON workflow_entries BEGIN SELECT RAISE(ABORT,'immutable workflow entry'); END;

-- One lookup index spans typed evidence and actual content; no serialized fallback.
CREATE VIEW workflow_index AS
 SELECT key,digest FROM workflow_entries
 UNION ALL SELECT 'source:'||digest,workflow_digest FROM source_content
 UNION ALL SELECT key,workflow_digest FROM source_staging
 UNION ALL SELECT 'image-bytes:'||digest||':'||ordinal,historical_workflow_digest FROM media_chunk
 UNION ALL SELECT key,workflow_digest FROM image_staging
 UNION ALL SELECT key,workflow_digest FROM continuity_name;
CREATE TRIGGER source_content_no_update BEFORE UPDATE ON source_content BEGIN SELECT RAISE(ABORT,'immutable workflow content'); END;
CREATE TRIGGER source_content_no_delete BEFORE DELETE ON source_content BEGIN SELECT RAISE(ABORT,'immutable workflow content'); END;
CREATE TRIGGER source_staging_no_update BEFORE UPDATE ON source_staging BEGIN SELECT RAISE(ABORT,'immutable workflow content'); END;
CREATE TRIGGER source_staging_no_delete BEFORE DELETE ON source_staging BEGIN SELECT RAISE(ABORT,'immutable workflow content'); END;
CREATE TRIGGER media_chunk_no_update BEFORE UPDATE ON media_chunk BEGIN SELECT RAISE(ABORT,'immutable workflow content'); END;
CREATE TRIGGER media_chunk_no_delete BEFORE DELETE ON media_chunk BEGIN SELECT RAISE(ABORT,'immutable workflow content'); END;
CREATE TRIGGER image_staging_no_update BEFORE UPDATE ON image_staging BEGIN SELECT RAISE(ABORT,'immutable workflow content'); END;
CREATE TRIGGER image_staging_no_delete BEFORE DELETE ON image_staging BEGIN SELECT RAISE(ABORT,'immutable workflow content'); END;
CREATE TRIGGER continuity_name_no_update BEFORE UPDATE ON continuity_name BEGIN SELECT RAISE(ABORT,'immutable workflow content'); END;
CREATE TRIGGER continuity_name_no_delete BEFORE DELETE ON continuity_name BEGIN SELECT RAISE(ABORT,'immutable workflow content'); END;
