//! Closed typed workflow envelopes. JSON is only a transient API boundary.
use crate::{relational, Connection, StoreError, StoreResult};
use base64::{engine::general_purpose::STANDARD, Engine};
use rusqlite::{params, types::Value as SqlValue, OptionalExtension};
use serde_json::Value;
use sha2::{Digest, Sha256};
use universe_domain::canonical::canonical_serde;

fn invalid(message: &str) -> StoreError {
    StoreError::StorageFailure(message.into())
}
fn digest(value: &Value) -> String {
    hex::encode(Sha256::digest(canonical_serde(value).to_bytes()))
}
fn family(key: &str) -> StoreResult<&'static str> {
    Ok(match key.split(':').next().unwrap_or("") {
        "context" => "StoredContext",
        "proposal" => "StoredProposal",
        "reserved-record" => "ReservedRecord",
        "validation" => "Checked",
        "operation" | "request" | "job" => "StoredOperation",
        "cancel" => "Cancellation",
        "approval" => "ApprovalEvidence",
        "assessment" => "AssessmentEnvelope",
        "assessment-selection" => "AssessmentSelection",
        "assessment-receipt" => "AssessmentReceipt",
        "cursor" => "Cursor",
        "draft" => "SavedDraft",
        "logical-import-origin" => "ImportOrigin",
        "logical-import-admission" => "ImportAdmission",
        _ => return Err(invalid("unknown workflow key family")),
    })
}
fn chunk_key(key: &str) -> StoreResult<(&str, i64)> {
    let (hash, ordinal) = key
        .strip_prefix("image-bytes:")
        .and_then(|s| s.rsplit_once(':'))
        .ok_or_else(|| invalid("invalid media key"))?;
    let index: i64 = ordinal
        .parse()
        .map_err(|_| invalid("invalid media ordinal"))?;
    if index < 0 || ordinal != index.to_string() {
        return Err(invalid("invalid media ordinal"));
    }
    Ok((hash, index))
}

pub(crate) fn put(tx: &rusqlite::Transaction<'_>, key: &str, value: &Value) -> StoreResult<()> {
    if canonical_serde(value).to_bytes().len() > 4 * 1_048_576 {
        return Err(invalid("workflow entry too large"));
    }
    let hash = digest(value);
    // Reconstruct and verify even an identical retry; a corrupt body cannot be
    // accepted just because the envelope retained the requested digest.
    if let Some(old) = get(tx, key)? {
        if old != *value {
            return Err(invalid("immutable workflow key conflict"));
        }
        return Ok(());
    }
    if let Some(id) = key.strip_prefix("source:") {
        let text = value
            .as_str()
            .ok_or_else(|| invalid("source content must be UTF-8 text"))?;
        if hex::encode(Sha256::digest(text.as_bytes())) != id {
            return Err(invalid("source content digest mismatch"));
        }
        tx.execute(
            "INSERT INTO source_content VALUES(?1,?2,?3,?4)",
            params![id, text.len() as i64, text.as_bytes(), hash],
        )?;
    } else if key.starts_with("image-bytes:") {
        let (id, ordinal) = chunk_key(key)?;
        let text = value
            .as_str()
            .ok_or_else(|| invalid("invalid media chunk"))?;
        let bytes = STANDARD
            .decode(text)
            .map_err(|_| invalid("invalid media encoding"))?;
        if STANDARD.encode(&bytes) != text {
            return Err(invalid("noncanonical media encoding"));
        }
        tx.execute(
            "INSERT INTO media_chunk VALUES(?1,?2,?3,?4,?5)",
            params![id, ordinal, bytes.len() as i64, bytes, hash],
        )?;
    } else if let Some(id) = key.strip_prefix("continuity-name:") {
        let name = value
            .as_str()
            .ok_or_else(|| invalid("invalid continuity name"))?;
        tx.execute(
            "INSERT INTO continuity_name VALUES(?1,?2,?3,?4)",
            params![id, key, name, hash],
        )?;
    } else if key.starts_with("source-version:") || key.starts_with("image-asset:") {
        let kind = if key.starts_with("source-version:") {
            "source_version"
        } else {
            "image_asset"
        };
        if value.get("record_kind").and_then(Value::as_str) != Some(kind) {
            return Err(invalid("staging kind mismatch"));
        }
        let row = relational::put(tx, "Payload", value)?;
        let table = if kind == "source_version" {
            "source_staging"
        } else {
            "image_staging"
        };
        tx.execute(
            &format!("INSERT INTO {table} VALUES(?1,?2,?3)"),
            params![key, hash, row],
        )?;
    } else {
        let model = family(key)?;
        let row = relational::put(tx, model, value)?;
        tx.execute(&format!("INSERT INTO workflow_entries(key,family,digest,digest_recipe,\"{model}\") VALUES(?1,?2,?3,'workflow-canonical',?4)"),params![key,model,hash,row])?;
    }
    Ok(())
}

pub(crate) fn get(c: &Connection, key: &str) -> StoreResult<Option<Value>> {
    let expected: Option<String> = c
        .query_row(
            "SELECT digest FROM workflow_index WHERE key=?1",
            [key],
            |r| r.get(0),
        )
        .optional()?;
    let Some(expected) = expected else {
        return Ok(None);
    };
    let value = if let Some(id) = key.strip_prefix("source:") {
        let (size, bytes): (i64, Vec<u8>) = c.query_row(
            "SELECT byte_size,utf8_content FROM source_content WHERE digest=?1",
            [id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )?;
        if size != bytes.len() as i64 || hex::encode(Sha256::digest(&bytes)) != id {
            return Err(invalid("source content integrity failure"));
        }
        Value::String(String::from_utf8(bytes).map_err(|_| invalid("invalid source UTF-8"))?)
    } else if key.starts_with("image-bytes:") {
        let (id, ordinal) = chunk_key(key)?;
        let (size, bytes): (i64, Vec<u8>) = c.query_row(
            "SELECT byte_size,content FROM media_chunk WHERE digest=?1 AND ordinal=?2",
            params![id, ordinal],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )?;
        if size != bytes.len() as i64 {
            return Err(invalid("media size mismatch"));
        }
        Value::String(STANDARD.encode(bytes))
    } else if key.starts_with("continuity-name:") {
        Value::String(c.query_row(
            "SELECT name FROM continuity_name WHERE key=?1",
            [key],
            |r| r.get(0),
        )?)
    } else if key.starts_with("source-version:") || key.starts_with("image-asset:") {
        let (table, column) = if key.starts_with("source-version:") {
            ("source_staging", "source_version_row")
        } else {
            ("image_staging", "image_asset_row")
        };
        let row: i64 = c.query_row(
            &format!("SELECT {column} FROM {table} WHERE key=?1"),
            [key],
            |r| r.get(0),
        )?;
        relational::get(c, "Payload", SqlValue::Integer(row))?
    } else {
        let model = family(key)?;
        let (stored_family, recipe, row): (String, String, i64) = c.query_row(
            &format!("SELECT family,digest_recipe,\"{model}\" FROM workflow_entries WHERE key=?1"),
            [key],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )?;
        if stored_family != model || recipe != "workflow-canonical" {
            return Err(invalid("workflow family mismatch"));
        }
        relational::get(c, model, SqlValue::Integer(row))?
    };
    if digest(&value) != expected {
        return Err(invalid("workflow integrity failure"));
    }
    Ok(Some(value))
}
