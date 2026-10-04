//! Offline, explicit conversion. Original files are opened read-only; input SQL
//! is never installed in a target. Publication is no-clobber and same-directory.
use super::*;
use rusqlite::{params_from_iter, types::Value as Cell};
use std::{
    fs::File,
    io::Read,
    os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConversionPoint {
    Rows,
    Audited,
    BeforePublish,
}
#[derive(Debug, Serialize)]
pub struct ConversionReport {
    pub source_sha256: String,
    pub records: usize,
    pub workflows: usize,
    pub compared_tables: usize,
    pub original_preserved: bool,
}
pub fn read_original(path: &Path) -> StoreResult<File> {
    let f = std::fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(path)?;
    let m = f.metadata()?;
    if !m.is_file()
        || m.nlink() != 1
        || m.uid() != unsafe { libc::geteuid() }
        || m.mode() & 0o077 != 0
        || m.len() > MAX_RESTORE_BYTES
    {
        return Err(invalid(
            "conversion input requires an owned private regular file within 8 GiB",
        ));
    }
    Ok(f)
}
pub fn original_hash(path: &Path) -> StoreResult<String> {
    let mut file = read_original(path)?;
    let mut hash = Sha256::new();
    let mut buffer = [0u8; 65536];
    loop {
        let n = file.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        hash.update(&buffer[..n]);
    }
    Ok(hex::encode(hash.finalize()))
}
pub fn open_original(path: &Path) -> StoreResult<Connection> {
    read_original(path)?;
    // Offline inputs only. Refuse WAL state rather than creating/changing SHM.
    for suffix in ["-wal", "-shm", "-journal"] {
        if Path::new(&format!("{}{suffix}", path.display())).exists() {
            return Err(invalid("source has journal sidecars; stop its writer and obtain a clean offline snapshot before conversion"));
        }
    }
    let c = Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    c.execute_batch("PRAGMA trusted_schema=OFF; PRAGMA query_only=ON; BEGIN;")?;
    let check: String = c.query_row("PRAGMA integrity_check", [], |r| r.get(0))?;
    if check != "ok" {
        return Err(invalid(
            "source SQLite integrity failure; retain source and repair a copy",
        ));
    }
    Ok(c)
}
pub fn verify_original_database(path: &Path, expected: &str) -> StoreResult<()> {
    let _current = open_original(path)?;
    if original_hash(path)? != expected {
        return Err(invalid(
            "source changed during conversion; repeat with an offline snapshot",
        ));
    }
    Ok(())
}
fn quote(s: &str) -> String {
    format!("\"{}\"", s.replace('"', "\"\""))
}
pub fn columns(c: &Connection, table: &str) -> StoreResult<Vec<String>> {
    Ok(c.prepare(&format!("PRAGMA table_info({})", quote(table)))?
        .query_map([], |r| r.get(1))?
        .collect::<Result<_, _>>()?)
}
fn rows(c: &Connection, table: &str) -> StoreResult<Vec<Vec<Cell>>> {
    let cols = columns(c, table)?;
    if cols.is_empty() {
        return Err(invalid(&format!("missing input table {table}")));
    }
    let mut s = c.prepare(&format!(
        "SELECT * FROM {} ORDER BY {} LIMIT 2000001",
        quote(table),
        cols.iter().map(|s| quote(s)).collect::<Vec<_>>().join(",")
    ))?;
    let result = s
        .query_map([], |r| {
            (0..cols.len())
                .map(|i| r.get(i))
                .collect::<Result<Vec<Cell>, _>>()
        })?
        .collect::<Result<Vec<_>, _>>()?;
    if result.len() > 2_000_000 {
        return Err(invalid("conversion row budget exceeded"));
    }
    Ok(result)
}
pub fn copy_scalar_table(source: &Connection, target: &Connection, table: &str) -> StoreResult<()> {
    if columns(source, table)? != columns(target, table)? {
        return Err(invalid(&format!(
            "unsupported columns in {table}; original retained"
        )));
    }
    let cols = columns(target, table)?;
    let mut stmt = target.prepare(&format!(
        "INSERT INTO {} VALUES({})",
        quote(table),
        vec!["?"; cols.len()].join(",")
    ))?;
    for row in rows(source, table)? {
        stmt.execute(params_from_iter(row))?;
    }
    Ok(())
}
pub fn compare_scalar_table(
    source: &Connection,
    target: &Connection,
    table: &str,
) -> StoreResult<()> {
    if columns(source, table)? != columns(target, table)?
        || rows(source, table)? != rows(target, table)?
    {
        return Err(invalid(&format!(
            "independent whole-table comparison failed: {table}"
        )));
    }
    Ok(())
}
pub fn check_inventory(source: &Connection, allowed: &[&str]) -> StoreResult<()> {
    let tables:Vec<String>=source.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")?.query_map([],|r|r.get(0))?.collect::<Result<_,_>>()?;
    for table in tables {
        if allowed.contains(&"projection_heads")
            && matches!(
                table.as_str(),
                "search_index"
                    | "search_index_data"
                    | "search_index_idx"
                    | "search_index_content"
                    | "search_index_docsize"
                    | "search_index_config"
            )
        {
            continue;
        }
        if !allowed.contains(&table.as_str()) {
            return Err(invalid(&format!("unsupported input table {table}; no rows omitted; retain source for explicit repair")));
        }
    }
    Ok(())
}
pub fn publish_file(private: &Path, destination: &Path) -> StoreResult<()> {
    File::open(private)?.sync_all()?;
    publish_directory(private, destination)
}
const SCALARS: &[&str] = &[
    "universes",
    "record_identities",
    "continuities",
    "commits",
    "commit_changes",
    "world_name_reservations",
    "head_membership",
    "operation_receipts",
];
const CACHE: &[&str] = &[
    "projection_heads",
    "projection_state",
    "reference_index",
    "typed_projection",
    "world_projection",
    "narrative_projection",
];

/// Only known historical recipes are accepted, never a guessed/rehashed mismatch.
fn source_payload_digest(kind: &str, version: Option<&str>, value: &Value) -> StoreResult<String> {
    let discriminator = match version {
        Some("v1") => format!("{kind}:v1:v1"),
        None => kind.into(),
        _ => return Err(invalid("unsupported legacy payload digest recipe")),
    };
    let mut h = Sha256::new();
    h.update(discriminator);
    h.update(b":");
    h.update(canonical_serde(value).to_bytes());
    Ok(hex::encode(h.finalize()))
}
type ClassificationEvidence = (String, Vec<String>);
type SerializedRecord = (
    String,
    String,
    String,
    String,
    Option<String>,
    Vec<u8>,
    String,
);
fn normalize(mut value: Value) -> StoreResult<(Value, Option<ClassificationEvidence>)> {
    let kind = value
        .get("record_kind")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned();
    let (vector, selected, status, zero, relationship) = match kind.as_str() {
        "entity" => (
            "types",
            "classification",
            "classificationResolution",
            "unclassified",
            "membership",
        ),
        "entity_type" => ("parents", "parent", "parentResolution", "root", "parent"),
        _ => return Ok((value, None)),
    };
    let Some(candidates) = value.as_object_mut().and_then(|v| v.remove(vector)) else {
        return Ok((value, None));
    };
    let candidates: Vec<String> = serde_json::from_value(candidates)
        .map_err(|_| invalid("invalid classification candidates"))?;
    value[selected] = if candidates.len() == 1 {
        Value::String(candidates[0].clone())
    } else {
        Value::Null
    };
    value[status] = Value::String(
        match candidates.len() {
            0 => zero,
            1 => "resolved",
            _ => "ambiguous",
        }
        .into(),
    );
    // Applicability was not declared in old inputs. Preserve that uncertainty.
    if kind == "entity_type" {
        if value.get("name").is_none() {
            return Err(invalid("legacy entity_type lacks authored name; supply an explicit repaired copy with name before conversion"));
        }
        if value.get("applicability").is_none() {
            value["applicability"] = serde_json::json!({"kind":"unspecified"});
        }
    }
    Ok((value, Some((relationship.into(), candidates))))
}
fn normalize_draft(key: &str, mut value: Value) -> StoreResult<Value> {
    if key.starts_with("draft:") && value["content"]["operations"].is_string() {
        let text = value["content"]["operations"].as_str().unwrap();
        let operations:Vec<DomainOperation>=serde_json::from_str(text).map_err(|_|invalid(&format!("unrecoverable draft {key}: repair ordered operation JSON in a copy; no partial target published")))?;
        value["content"]["operations"] =
            serde_json::to_value(operations).map_err(|_| invalid("draft encoding"))?;
    }
    Ok(value)
}
pub fn convert_package(source: &Path, destination: &Path) -> StoreResult<ConversionReport> {
    convert_package_with_hook(source, destination, |_| Ok(()))
}
pub fn convert_package_with_hook(
    source: &Path,
    destination: &Path,
    mut hook: impl FnMut(ConversionPoint) -> StoreResult<()>,
) -> StoreResult<ConversionReport> {
    if destination.exists() {
        return Err(invalid(
            "conversion destination already exists; choose a fresh path",
        ));
    }
    let parent = crate::ownership::private_dir(
        destination
            .parent()
            .ok_or_else(|| invalid("destination parent required"))?,
    )?;
    let original = original_hash(source)?;
    let input = open_original(source)?;
    if columns(&input, "record_versions")?
        .iter()
        .any(|s| s == "payload_row")
    {
        return convert_relational_package(source, destination, &input, &original, &mut hook);
    }
    let mut allowed = SCALARS.to_vec();
    allowed.extend(CACHE);
    allowed.extend([
        "schema_meta",
        "record_versions",
        "workflow_entries",
        "snapshot_membership",
    ]);
    check_inventory(&input, &allowed)?;
    if !columns(&input,"schema_meta")?.is_empty()
        && (columns(&input,"schema_meta")? != ["key","value"] || rows(&input,"schema_meta")?.iter().any(|row| !matches!(row.as_slice(),[Cell::Text(key),Cell::Integer(1|2)] if key=="schema_version"))) {
        return Err(invalid("unsupported legacy schema metadata; no evidence omitted"));
    }
    if columns(&input, "workflow_entries")? != ["key", "payload", "digest"]
        || columns(&input, "snapshot_membership")?
            != ["universe_id", "revision_id", "membership", "checksum"]
    {
        return Err(invalid(
            "unsupported serialized workflow/snapshot columns; no evidence omitted",
        ));
    }
    let cols = columns(&input, "record_versions")?;
    if cols
        != [
            "universe_id",
            "id",
            "record_id",
            "kind",
            "schema_version",
            "payload",
            "digest",
        ]
        && cols
            != [
                "universe_id",
                "id",
                "record_id",
                "kind",
                "payload",
                "digest",
            ]
    {
        return Err(invalid(
            "unsupported serialized record layout; original retained",
        ));
    }
    let temp = tempfile::Builder::new()
        .prefix(".operator-conversion-")
        .tempdir_in(parent)?;
    std::fs::set_permissions(temp.path(), std::fs::Permissions::from_mode(0o700))?;
    let path = temp.path().join("package.sqlite");
    crate::ownership::protected_file(&path, true)?;
    let db = Database::open(&path)?;
    let mut target = db.connect()?;
    let tx = target.transaction()?;
    tx.execute_batch("PRAGMA defer_foreign_keys=ON;")?;
    for table in SCALARS {
        copy_scalar_table(&input, &tx, table)?;
    }
    let oversized:i64=input.query_row("SELECT (SELECT count(*) FROM record_versions WHERE length(payload)>4194304)+(SELECT count(*) FROM workflow_entries WHERE length(payload)>4194304)",[],|r|r.get(0))?;
    if oversized != 0 {
        return Err(invalid("serialized conversion body exceeds 4 MiB limit"));
    }
    let versioned = cols.iter().any(|s| s == "schema_version");
    let sql = if versioned {
        "SELECT universe_id,id,record_id,kind,schema_version,payload,digest FROM record_versions ORDER BY id LIMIT 1000001"
    } else {
        "SELECT universe_id,id,record_id,kind,NULL,payload,digest FROM record_versions ORDER BY id LIMIT 1000001"
    };
    let records: Vec<SerializedRecord> = input
        .prepare(sql)?
        .query_map([], |r| {
            Ok((
                r.get(0)?,
                r.get(1)?,
                r.get(2)?,
                r.get(3)?,
                r.get(4)?,
                r.get(5)?,
                r.get(6)?,
            ))
        })?
        .collect::<Result<_, _>>()?;
    if records.len() > MAX_VERSIONS {
        return Err(invalid("conversion version budget exceeded"));
    }
    for (u, id, rid, kind, recipe, bytes, old_hash) in &records {
        let original: Value =
            serde_json::from_slice(bytes).map_err(|_| invalid(&format!("invalid payload {id}")))?;
        if source_payload_digest(kind, recipe.as_deref(), &original)? != *old_hash {
            return Err(invalid(&format!("original digest mismatch at version {id}; repair source evidence, never rehash into success")));
        }
        let (normalized, evidence) = normalize(original)?;
        let payload: Payload = serde_json::from_value(normalized).map_err(|e| {
            invalid(&format!(
                "unsupported body at version {id}: {e}; repair a copy"
            ))
        })?;
        let record = RecordVersion::build(
            RecordVersionId::parse(id).map_err(|_| invalid("version id"))?,
            RecordIdentity::new(
                UniverseId::parse(u).map_err(|_| invalid("universe id"))?,
                RecordId::parse(rid).map_err(|_| invalid("record id"))?,
                RecordKind::parse(kind).map_err(|_| invalid("record kind"))?,
            ),
            payload,
        )
        .map_err(|_| invalid("kind mismatch"))?;
        insert_version(&tx, &record)?;
        tx.execute(
            "INSERT INTO import_record_digest VALUES(?,?,?,?)",
            params![u, id, old_hash, record.payload_digest.as_str()],
        )?;
        if let Some((relationship, candidates)) = evidence {
            for (ordinal, candidate) in candidates.iter().enumerate() {
                let candidate_kind: Option<String> = tx
                    .query_row(
                        "SELECT kind FROM record_identities WHERE universe_id=?1 AND id=?2",
                        params![u, candidate],
                        |r| r.get(0),
                    )
                    .optional()?;
                if candidate_kind.as_deref() != Some("entity_type") {
                    return Err(invalid(&format!("invalid ancestry at {id}: candidate {candidate} is missing, cross-universe or wrong kind; repair a copy")));
                }
                tx.execute(
                    "INSERT INTO classification_evidence VALUES(?,?,?,?,?)",
                    params![u, id, relationship, ordinal as i64, candidate],
                )?;
            }
        }
        hook(ConversionPoint::Rows)?;
    }
    let workflows: Vec<(String, Vec<u8>, String)> = input
        .prepare("SELECT key,payload,digest FROM workflow_entries ORDER BY key LIMIT 2000001")?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
        .collect::<Result<_, _>>()?;
    if workflows.len() > 2_000_000 {
        return Err(invalid("conversion workflow budget exceeded"));
    }
    for (key, bytes, hash) in &workflows {
        let original: Value = serde_json::from_slice(bytes)
            .map_err(|_| invalid(&format!("invalid workflow {key}")))?;
        if digest(&original) != *hash {
            return Err(invalid(&format!(
                "original workflow digest mismatch: {key}"
            )));
        }
        let value = normalize_draft(key, original)?;
        crate::workflow_storage::put(&tx, key, &value).map_err(|e| {
            invalid(&format!(
                "workflow {key} cannot be converted: {e}; repair source copy"
            ))
        })?;
        tx.execute(
            "INSERT INTO import_workflow_digest VALUES(?,?,?)",
            params![key, hash, digest(&value)],
        )?;
        hook(ConversionPoint::Rows)?;
    }
    // Serialized snapshots are verifiable caches, not omitted author evidence.
    for row in rows(&input, "snapshot_membership")? {
        let [Cell::Text(u), Cell::Text(rev), Cell::Blob(bytes), Cell::Text(hash)] = row.as_slice()
        else {
            return Err(invalid("unsupported snapshot layout"));
        };
        let map: Membership =
            serde_json::from_slice(bytes).map_err(|_| invalid("invalid snapshot membership"))?;
        if digest(&map) != *hash {
            return Err(invalid("original snapshot checksum mismatch"));
        }
        tx.execute(
            "INSERT INTO snapshot_membership VALUES(?,?,?)",
            params![u, rev, hash],
        )?;
        for (record, version) in map {
            tx.execute(
                "INSERT INTO snapshot_member VALUES(?,?,?,?)",
                params![u, rev, record, version],
            )?;
        }
    }
    let universe: String = tx.query_row("SELECT id FROM universes", [], |r| r.get(0))?;
    let revisions: Vec<(String, String)> = tx
        .prepare("SELECT id,continuity_id FROM commits ORDER BY sequence,id")?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<Result<_, _>>()?;
    let mut indexed = BTreeSet::new();
    for (revision, continuity) in revisions {
        let map = resolve(&tx, &universe, &continuity, &revision, &mut BTreeSet::new())?;
        for version in map.values() {
            if indexed.insert(version.clone()) {
                index_definition(&tx, &load(&tx, &universe, version)?, &map)?;
            }
        }
    }
    tx.commit()?;
    // Preserve owning-installation workflow authority. Nothing is regenerated or
    // registered here; normal commit validation must still verify exact bindings.
    let u: String = target.query_row("SELECT id FROM universes", [], |r| r.get(0))?;
    verify_canonical(&target, &u)?;
    verify_content_links(&target)?;
    verify_history(&target, &u)?;
    audit_ancestry(&target, &u)?;
    for row in rows(&input, "snapshot_membership")? {
        let [Cell::Text(universe), Cell::Text(revision), Cell::Blob(bytes), Cell::Text(_)] =
            row.as_slice()
        else {
            return Err(invalid("snapshot audit layout"));
        };
        let continuity: String = target.query_row(
            "SELECT continuity_id FROM commits WHERE universe_id=?1 AND id=?2",
            params![universe, revision],
            |r| r.get(0),
        )?;
        let expected: Membership =
            serde_json::from_slice(bytes).map_err(|_| invalid("snapshot audit decoding"))?;
        if resolve(
            &target,
            universe,
            &continuity,
            revision,
            &mut BTreeSet::new(),
        )? != expected
        {
            return Err(invalid(&format!(
                "snapshot differs from factual history at {revision}"
            )));
        }
        let retained:Membership=target.prepare("SELECT record_id,version_id FROM snapshot_member WHERE universe_id=?1 AND revision_id=?2 ORDER BY record_id")?.query_map(params![universe,revision],|r|Ok((r.get(0)?,r.get(1)?)))?.collect::<Result<_,_>>()?;
        if retained != expected {
            return Err(invalid("whole-snapshot comparison failed"));
        }
    }
    let heads: Vec<(String, String)> = target
        .prepare("SELECT id,head_commit FROM continuities")?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<Result<_, _>>()?;
    for (continuity, revision) in heads {
        let retained:Membership=target.prepare("SELECT record_id,version_id FROM head_membership WHERE universe_id=?1 AND continuity_id=?2")?.query_map(params![u,continuity],|r|Ok((r.get(0)?,r.get(1)?)))?.collect::<Result<_,_>>()?;
        if resolve(&target, &u, &continuity, &revision, &mut BTreeSet::new())? != retained {
            return Err(invalid(&format!(
                "head membership differs from factual history: {continuity}"
            )));
        }
    }
    // Compare independently from the write loop, using target domain reconstruction.
    for table in SCALARS {
        compare_scalar_table(&input, &target, table)?;
    }
    for (universe, id, _, kind, recipe, bytes, hash) in &records {
        let original: Value =
            serde_json::from_slice(bytes).map_err(|_| invalid("audit payload"))?;
        if source_payload_digest(kind, recipe.as_deref(), &original)? != *hash {
            return Err(invalid("audit source digest"));
        }
        let (expected, evidence) = normalize(original)?;
        let actual = load(&target, universe, id)?;
        if serde_json::to_value(&actual.payload).map_err(|_| invalid("audit encoding"))? != expected
        {
            return Err(invalid(&format!("whole-body comparison failed: {id}")));
        }
        let provenance:(String,String)=target.query_row("SELECT source_digest,normalized_digest FROM import_record_digest WHERE universe_id=?1 AND version_id=?2",params![universe,id],|r|Ok((r.get(0)?,r.get(1)?)))?;
        if provenance != (hash.clone(), actual.payload_digest.as_str().into()) {
            return Err(invalid("audit digest provenance mismatch"));
        }
        if let Some((relationship, candidates)) = evidence {
            let retained:Vec<String>=target.prepare("SELECT type_id FROM classification_evidence WHERE universe_id=?1 AND version_id=?2 AND relationship=?3 ORDER BY ordinal")?.query_map(params![universe,id,relationship],|r|r.get(0))?.collect::<Result<_,_>>()?;
            if retained != candidates {
                return Err(invalid("classification evidence comparison failed"));
            }
        }
    }
    for (key, bytes, hash) in &workflows {
        let expected = normalize_draft(
            key,
            serde_json::from_slice(bytes).map_err(|_| invalid("audit workflow"))?,
        )?;
        if crate::workflow_storage::evidence(&target, key)?.as_ref() != Some(&expected) {
            return Err(invalid(&format!("whole-workflow comparison failed: {key}")));
        }
        let actual: (String, String) = target.query_row(
            "SELECT source_digest,normalized_digest FROM import_workflow_digest WHERE key=?1",
            [key],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )?;
        if actual != (hash.clone(), digest(&expected)) {
            return Err(invalid("workflow provenance comparison failed"));
        }
    }
    let violations: i64 =
        target.query_row("SELECT count(*) FROM pragma_foreign_key_check", [], |r| {
            r.get(0)
        })?;
    if violations != 0 {
        return Err(invalid("converted foreign key audit failed"));
    }
    hook(ConversionPoint::Audited)?;
    target.execute_batch("PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;")?;
    drop(target);
    if original_hash(source)? != original {
        return Err(invalid(
            "source changed during conversion; repeat using an offline copy",
        ));
    }
    hook(ConversionPoint::BeforePublish)?;
    verify_original_database(source, &original)?;
    publish_file(&path, destination)?;
    Ok(ConversionReport {
        source_sha256: original,
        records: records.len(),
        workflows: workflows.len(),
        compared_tables: SCALARS.len(),
        original_preserved: true,
    })
}

pub fn publish_directory(private: &Path, destination: &Path) -> StoreResult<()> {
    use std::os::unix::ffi::OsStrExt;
    let from = std::ffi::CString::new(private.as_os_str().as_bytes())
        .map_err(|_| invalid("invalid path"))?;
    let to = std::ffi::CString::new(destination.as_os_str().as_bytes())
        .map_err(|_| invalid("invalid path"))?;
    #[cfg(target_os = "macos")]
    let result = unsafe {
        libc::renameatx_np(
            libc::AT_FDCWD,
            from.as_ptr(),
            libc::AT_FDCWD,
            to.as_ptr(),
            libc::RENAME_EXCL,
        )
    };
    #[cfg(target_os = "linux")]
    let result = unsafe {
        libc::renameat2(
            libc::AT_FDCWD,
            from.as_ptr(),
            libc::AT_FDCWD,
            to.as_ptr(),
            libc::RENAME_NOREPLACE,
        )
    };
    if result != 0 {
        return Err(StoreError::Io(std::io::Error::last_os_error()));
    }
    File::open(
        destination
            .parent()
            .ok_or_else(|| invalid("parent required"))?,
    )?
    .sync_all()?;
    Ok(())
}

fn audit_ancestry(c: &Connection, u: &str) -> StoreResult<()> {
    fn visit(
        id: &str,
        graph: &BTreeMap<String, Vec<String>>,
        active: &mut BTreeSet<String>,
        done: &mut BTreeSet<String>,
    ) -> StoreResult<()> {
        if done.contains(id) {
            return Ok(());
        }
        if active.len() >= 64 || !active.insert(id.into()) {
            return Err(invalid(&format!(
                "invalid ancestry cycle/depth at {id}; repair retained source copy"
            )));
        }
        for parent in graph.get(id).into_iter().flatten() {
            if !graph.contains_key(parent) {
                return Err(invalid(&format!("invalid ancestry {id} -> {parent}: definition missing from historical snapshot")));
            }
            visit(parent, graph, active, done)?;
        }
        active.remove(id);
        done.insert(id.into());
        Ok(())
    }
    let revisions: Vec<(String, String)> = c
        .prepare("SELECT id,continuity_id FROM commits")?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<Result<_, _>>()?;
    for (revision, continuity) in revisions {
        let membership = resolve(c, u, &continuity, &revision, &mut BTreeSet::new())?;
        let mut graph = BTreeMap::new();
        for (id, version) in &membership {
            if let Payload::EntityType(t) = load(c, u, version)?.payload {
                let mut candidates:Vec<String>=c.prepare("SELECT type_id FROM classification_evidence WHERE universe_id=?1 AND version_id=?2 AND relationship='parent' ORDER BY ordinal")?.query_map(params![u,version],|r|r.get(0))?.collect::<Result<_,_>>()?;
                if candidates.is_empty() {
                    candidates.extend(t.parent.map(|p| p.to_string()));
                }
                graph.insert(id.clone(), candidates);
            }
        }
        for version in membership.values() {
            let candidates:Vec<String>=c.prepare("SELECT type_id FROM classification_evidence WHERE universe_id=?1 AND version_id=?2 AND relationship='membership'")?.query_map(params![u,version],|r|r.get(0))?.collect::<Result<_,_>>()?;
            for candidate in candidates {
                if !graph.contains_key(&candidate) {
                    return Err(invalid(&format!("invalid classification at {version}: {candidate} missing from revision {revision}")));
                }
            }
        }
        let mut done = BTreeSet::new();
        for id in graph.keys() {
            visit(id, &graph, &mut BTreeSet::new(), &mut done)?;
        }
    }
    Ok(())
}

// A prior fully relational package can lack only the new conversion-provenance
// table. Exact schema comparison precedes row transfer; input SQL is never run.
fn convert_relational_package(
    source: &Path,
    destination: &Path,
    input: &Connection,
    original: &str,
    hook: &mut impl FnMut(ConversionPoint) -> StoreResult<()>,
) -> StoreResult<ConversionReport> {
    let temp = tempfile::Builder::new()
        .prefix(".operator-conversion-")
        .tempdir_in(
            destination
                .parent()
                .ok_or_else(|| invalid("parent required"))?,
        )?;
    std::fs::set_permissions(temp.path(), std::fs::Permissions::from_mode(0o700))?;
    let path = temp.path().join("package.sqlite");
    crate::ownership::protected_file(&path, true)?;
    let mut target = Database::open(&path)?.connect()?;
    let source_schema = crate::transfer::schema(input)?;
    let missing = !source_schema
        .iter()
        .any(|(_, name, _, _)| name == "import_workflow_digest");
    let expected = crate::transfer::schema(&target)?
        .into_iter()
        .filter(|(_, _, table, _)| !missing || table != "import_workflow_digest")
        .collect::<Vec<_>>();
    if source_schema != expected {
        return Err(invalid(
            "unrecognized relational legacy schema; preserve original for explicit repair",
        ));
    }
    let tx = target.transaction()?;
    tx.execute_batch("PRAGMA defer_foreign_keys=ON; DELETE FROM projection_state;")?;
    let tables = crate::transfer::tables(input)?;
    for table in &tables {
        copy_scalar_table(input, &tx, table)?;
        hook(ConversionPoint::Rows)?;
    }
    tx.commit()?;
    for table in &tables {
        compare_scalar_table(input, &target, table)?;
    }
    let u: String = target.query_row("SELECT id FROM universes", [], |r| r.get(0))?;
    verify_canonical(&target, &u)?;
    verify_content_links(&target)?;
    verify_history(&target, &u)?;
    audit_ancestry(&target, &u)?;
    let records: i64 =
        target.query_row("SELECT count(*) FROM record_versions", [], |r| r.get(0))?;
    let workflows: i64 =
        target.query_row("SELECT count(*) FROM workflow_index", [], |r| r.get(0))?;
    hook(ConversionPoint::Audited)?;
    target.execute_batch("PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;")?;
    drop(target);
    if original_hash(source)? != original {
        return Err(invalid("source changed during conversion"));
    }
    hook(ConversionPoint::BeforePublish)?;
    verify_original_database(source, original)?;
    publish_file(&path, destination)?;
    Ok(ConversionReport {
        source_sha256: original.into(),
        records: records as usize,
        workflows: workflows as usize,
        compared_tables: tables.len(),
        original_preserved: true,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{os::unix::fs::PermissionsExt, path::PathBuf};
    fn id(prefix: &str, n: u64) -> String {
        format!("{prefix}_{n:024x}")
    }
    fn record(n: u64, version: u64, payload: Payload) -> RecordVersion {
        RecordVersion::build(
            RecordVersionId::parse(&id("ver", version)).unwrap(),
            RecordIdentity::new(
                UniverseId::parse(&id("unv", 1)).unwrap(),
                RecordId::parse(&id("rec", n)).unwrap(),
                payload.kind(),
            ),
            payload,
        )
        .unwrap()
    }
    fn fixture(root: &Path) -> PathBuf {
        let path = root.join("original.sqlite");
        let u = UniverseId::parse(&id("unv", 1)).unwrap();
        let cont = ContinuityId::parse(&id("cont", 1)).unwrap();
        let principal = PrincipalId::parse(&id("prn", 1)).unwrap();
        let mut k = Kernel::create(
            &path,
            u.clone(),
            "Conversion café",
            cont.clone(),
            &principal,
        )
        .unwrap();
        let typ = |n| {
            Payload::EntityType(EntityType {
                namespace: "author".into(),
                key: format!("type{n}"),
                labels: BTreeMap::new(),
                name: format!("Type {n}"),
                parent: None,
                parent_resolution: ParentResolution::Root,
                applicability: universe_domain::scope::Applicability::Unspecified,
                classification_executable: true,
            })
        };
        let entity = Payload::Entity(Entity {
            names: vec![],
            classification: None,
            classification_resolution: ClassificationResolution::Unclassified,
            world_associations: vec![],
            labels: BTreeMap::from([("en".into(), "café".into())]),
            metadata: BTreeMap::new(),
        });
        let records = vec![
            record(1, 1, typ(1)),
            record(2, 2, typ(2)),
            record(3, 3, entity.clone()),
            record(4, 4, typ(4)),
            record(
                8,
                8,
                Payload::RepresentedContext(RepresentedContext {
                    universe: u.clone(),
                    kind: RepresentedContextKind::Objective,
                    parent: None,
                    chronology: None,
                    labels: BTreeMap::new(),
                }),
            ),
        ];
        let first = k
            .commit(&CommitInput {
                universe: u.clone(),
                continuity: cont.clone(),
                expected_head: k.head(&cont).unwrap(),
                principal: principal.clone(),
                decision: "authored".into(),
                reason: "first".into(),
                idempotency_key: "first".into(),
                changes: records
                    .iter()
                    .map(|r| Assignment {
                        record_id: r.identity.record_id.clone(),
                        expected: None,
                        next: Some(r.clone()),
                    })
                    .collect(),
            })
            .unwrap();
        k.cache_snapshot(&cont, &first, |_| Ok(())).unwrap();
        let branch = ContinuityId::parse(&id("cont", 2)).unwrap();
        k.branch(&branch, &cont, &first, &principal).unwrap();
        k.commit(&CommitInput {
            universe: u.clone(),
            continuity: cont.clone(),
            expected_head: first,
            principal,
            decision: "authored".into(),
            reason: "tombstone".into(),
            idempotency_key: "second".into(),
            changes: vec![Assignment {
                record_id: RecordId::parse(&id("rec", 3)).unwrap(),
                expected: Some(RecordVersionId::parse(&id("ver", 3)).unwrap()),
                next: None,
            }],
        })
        .unwrap();
        let text = "Exact source café\n";
        let text_hash = hex::encode(Sha256::digest(text.as_bytes()));
        k.workflow_put(&[
            (format!("source:{text_hash}"), Value::String(text.into())),
            (
                format!("continuity-name:{cont}"),
                Value::String("Main".into()),
            ),
        ])
        .unwrap();
        let draft = serde_json::json!({"version":1,"content":{"base_revision":k.head(&cont).unwrap(),"represented_context":id("rec",8),"operations":[],"rationale":"Unsubmitted café"}});
        let key = format!("draft:{}:{cont}:{:020}", id("prf", 1), 1);
        k.workflow_put(&[(key, draft)]).unwrap();
        let c = &k.conn;
        let snapshots: Vec<(String, String, Membership, String)> = c
            .prepare("SELECT universe_id,revision_id,checksum FROM snapshot_membership")
            .unwrap()
            .query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                ))
            })
            .unwrap()
            .map(|r| {
                let (u, rev, hash) = r.unwrap();
                let map = c
                    .prepare(
                        "SELECT record_id,version_id FROM snapshot_member WHERE revision_id=?1",
                    )
                    .unwrap()
                    .query_map([&rev], |r| Ok((r.get(0)?, r.get(1)?)))
                    .unwrap()
                    .collect::<Result<Membership, _>>()
                    .unwrap();
                (u, rev, map, hash)
            })
            .collect();
        let workflow: Vec<(String, Value)> = k
            .workflow_keys("")
            .unwrap()
            .into_iter()
            .map(|key| {
                let body = k.workflow_evidence_get(&key).unwrap().unwrap();
                (key, body)
            })
            .collect();
        let legacy = root.join("legacy.sqlite");
        crate::ownership::protected_file(&legacy, true).unwrap();
        let out = Connection::open(&legacy).unwrap();
        out.execute_batch("PRAGMA foreign_keys=OFF;").unwrap();
        // Test fixture writes serialized cells directly, independently of conversion.
        for table in SCALARS {
            let sql: String = c
                .query_row(
                    "SELECT sql FROM sqlite_master WHERE name=?1",
                    [table],
                    |r| r.get(0),
                )
                .unwrap();
            out.execute_batch(&sql).unwrap();
            copy_scalar_table(c, &out, table).unwrap();
        }
        out.execute_batch("CREATE TABLE record_versions(universe_id TEXT,id TEXT,record_id TEXT,kind TEXT,schema_version TEXT,payload BLOB,digest TEXT); CREATE TABLE workflow_entries(key TEXT PRIMARY KEY,payload BLOB,digest TEXT); CREATE TABLE snapshot_membership(universe_id TEXT,revision_id TEXT,membership BLOB,checksum TEXT);").unwrap();
        for r in records {
            let mut body = serde_json::to_value(&r.payload).unwrap();
            if r.identity.record_id.as_str() == id("rec", 3) {
                let obj = body.as_object_mut().unwrap();
                obj.remove("classification");
                obj.remove("classificationResolution");
                obj.insert(
                    "types".into(),
                    serde_json::json!([id("rec", 2), id("rec", 1)]),
                );
            }
            if r.identity.record_id.as_str() == id("rec", 4) {
                let obj = body.as_object_mut().unwrap();
                obj.remove("parent");
                obj.remove("parentResolution");
                obj.remove("applicability");
                obj.insert(
                    "parents".into(),
                    serde_json::json!([id("rec", 2), id("rec", 1)]),
                );
                obj.insert("classificationExecutable".into(), serde_json::json!(false));
            }
            let bytes = canonical_serde(&body).to_bytes();
            let mut h = Sha256::new();
            h.update(format!("{}:v1:v1:", r.identity.record_kind.as_str()));
            h.update(&bytes);
            out.execute(
                "INSERT INTO record_versions VALUES(?,?,?,?,?,?,?)",
                params![
                    u.as_str(),
                    r.record_version_id.as_str(),
                    r.identity.record_id.as_str(),
                    r.identity.record_kind.as_str(),
                    "v1",
                    bytes,
                    hex::encode(h.finalize())
                ],
            )
            .unwrap();
        }
        for (key, mut body) in workflow {
            if key.starts_with("draft:") {
                body["content"]["operations"] = Value::String("[]".into());
            }
            out.execute(
                "INSERT INTO workflow_entries VALUES(?,?,?)",
                params![key, canonical_serde(&body).to_bytes(), digest(&body)],
            )
            .unwrap();
        }
        for (u, rev, map, hash) in snapshots {
            out.execute(
                "INSERT INTO snapshot_membership VALUES(?,?,?,?)",
                params![u, rev, canonical_serde(&map).to_bytes(), hash],
            )
            .unwrap();
        }
        out.close().unwrap();
        drop(k);
        std::fs::remove_file(path).unwrap();
        legacy
    }
    #[test]
    fn preserves_full_history_workflows_provenance_and_ambiguity_and_retries() {
        let d = tempfile::tempdir().unwrap();
        std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        let source = fixture(d.path());
        let original = std::fs::read(&source).unwrap();
        let dest = d.path().join("converted.sqlite");
        let report = convert_package(&source, &dest).unwrap();
        assert_eq!(report.records, 5);
        assert_eq!(report.workflows, 3);
        assert_eq!(std::fs::read(&source).unwrap(), original);
        let k = Kernel::open(&dest).unwrap();
        assert_eq!(
            k.record_history(
                &ContinuityId::parse(&id("cont", 1)).unwrap(),
                &k.head(&ContinuityId::parse(&id("cont", 1)).unwrap())
                    .unwrap(),
                &RecordId::parse(&id("rec", 3)).unwrap()
            )
            .unwrap()
            .len(),
            2
        );
        let entity = k
            .record_version(&RecordVersionId::parse(&id("ver", 3)).unwrap())
            .unwrap();
        let Payload::Entity(e) = entity.payload else {
            panic!()
        };
        assert_eq!(
            e.classification_resolution,
            ClassificationResolution::Ambiguous
        );
        assert!(e.classification.is_none());
        let ordered: Vec<String> = k
            .conn
            .prepare("SELECT type_id FROM classification_evidence WHERE relationship='membership' ORDER BY ordinal")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        assert_eq!(ordered, vec![id("rec", 2), id("rec", 1)]);
        let typ = k
            .record_version(&RecordVersionId::parse(&id("ver", 4)).unwrap())
            .unwrap();
        let Payload::EntityType(t) = typ.payload else {
            panic!()
        };
        assert_eq!(t.parent_resolution, ParentResolution::Ambiguous);
        assert!(t.parent.is_none());
        assert!(!t.classification_executable);
        assert_eq!(
            t.applicability,
            universe_domain::scope::Applicability::Unspecified
        );
        assert!(convert_package(&source, &dest).is_err());
        let retry = d.path().join("retry.sqlite");
        convert_package(&source, &retry).unwrap();
        let c = open_original(&source).unwrap();
        let t = Connection::open(&retry).unwrap();
        for table in SCALARS {
            compare_scalar_table(&c, &t, table).unwrap();
        }
        assert_eq!(std::fs::read(source).unwrap(), original);
    }
    #[test]
    fn interruptions_before_publication_leave_original_and_allow_retry() {
        let d = tempfile::tempdir().unwrap();
        std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        let source = fixture(d.path());
        let original = std::fs::read(&source).unwrap();
        for point in [
            ConversionPoint::Rows,
            ConversionPoint::Audited,
            ConversionPoint::BeforePublish,
        ] {
            let dest = d.path().join(format!("{point:?}.sqlite"));
            assert!(
                convert_package_with_hook(&source, &dest, |p| if p == point {
                    Err(invalid("simulated interruption"))
                } else {
                    Ok(())
                })
                .is_err()
            );
            assert!(!dest.exists());
            assert_eq!(std::fs::read(&source).unwrap(), original);
            convert_package(&source, &dest).unwrap();
        }
        assert!(!std::fs::read_dir(d.path()).unwrap().any(|p| p
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".operator-conversion-")));
    }
    #[test]
    fn startup_invalid_drafts_digests_ancestry_and_unknown_data_do_not_convert() {
        for failure in [
            "draft",
            "digest",
            "missing",
            "cycle",
            "unknown",
            "snapshot",
            "unnamed",
            "wrong-kind",
        ] {
            let d = tempfile::tempdir().unwrap();
            std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
            let source = fixture(d.path());
            let c = Connection::open(&source).unwrap();
            match failure {
                "draft" => {
                    let mut body: Value = serde_json::from_slice(
                        &c.query_row(
                            "SELECT payload FROM workflow_entries WHERE key LIKE 'draft:%'",
                            [],
                            |r| r.get::<_, Vec<u8>>(0),
                        )
                        .unwrap(),
                    )
                    .unwrap();
                    body["content"]["operations"] = Value::String("[incomplete".into());
                    c.execute(
                        "UPDATE workflow_entries SET payload=?1,digest=?2 WHERE key LIKE 'draft:%'",
                        params![canonical_serde(&body).to_bytes(), digest(&body)],
                    )
                    .unwrap();
                }
                "digest" => {
                    c.execute(
                        "UPDATE record_versions SET digest=?1 WHERE id=?2",
                        params!["0".repeat(64), id("ver", 3)],
                    )
                    .unwrap();
                }
                "missing" | "cycle" => {
                    let version = if failure == "missing" {
                        id("ver", 3)
                    } else {
                        id("ver", 1)
                    };
                    let (kind, bytes): (String, Vec<u8>) = c
                        .query_row(
                            "SELECT kind,payload FROM record_versions WHERE id=?1",
                            [&version],
                            |r| Ok((r.get(0)?, r.get(1)?)),
                        )
                        .unwrap();
                    let mut body: Value = serde_json::from_slice(&bytes).unwrap();
                    if failure == "missing" {
                        body["types"] = serde_json::json!([id("rec", 99)]);
                    } else {
                        body["parent"] = Value::String(id("rec", 1));
                        body["parentResolution"] = Value::String("resolved".into());
                    }
                    let hash = source_payload_digest(&kind, Some("v1"), &body).unwrap();
                    c.execute(
                        "UPDATE record_versions SET payload=?1,digest=?2 WHERE id=?3",
                        params![canonical_serde(&body).to_bytes(), hash, version],
                    )
                    .unwrap();
                }
                "unnamed" | "wrong-kind" => {
                    let version = if failure == "unnamed" {
                        id("ver", 1)
                    } else {
                        id("ver", 3)
                    };
                    let (kind, bytes): (String, Vec<u8>) = c
                        .query_row(
                            "SELECT kind,payload FROM record_versions WHERE id=?1",
                            [&version],
                            |r| Ok((r.get(0)?, r.get(1)?)),
                        )
                        .unwrap();
                    let mut body: Value = serde_json::from_slice(&bytes).unwrap();
                    if failure == "unnamed" {
                        let obj = body.as_object_mut().unwrap();
                        for key in ["name", "parent", "parentResolution", "applicability"] {
                            obj.remove(key);
                        }
                        body["parents"] = serde_json::json!([]);
                    } else {
                        body["types"] = serde_json::json!([id("rec", 3)]);
                    }
                    let hash = source_payload_digest(&kind, Some("v1"), &body).unwrap();
                    c.execute(
                        "UPDATE record_versions SET payload=?1,digest=?2 WHERE id=?3",
                        params![canonical_serde(&body).to_bytes(), hash, version],
                    )
                    .unwrap();
                }
                "unknown" => {
                    c.execute_batch("CREATE TABLE unknown_author_data(body TEXT); INSERT INTO unknown_author_data VALUES('retain me');").unwrap();
                }
                "snapshot" => {
                    let map: Membership = BTreeMap::new();
                    c.execute(
                        "UPDATE snapshot_membership SET membership=?1,checksum=?2",
                        params![canonical_serde(&map).to_bytes(), digest(&map)],
                    )
                    .unwrap();
                }
                _ => unreachable!(),
            }
            drop(c);
            let original = std::fs::read(&source).unwrap();
            assert!(Database::open_existing(&source).is_err());
            assert_eq!(std::fs::read(&source).unwrap(), original);
            let dest = d.path().join("bad.sqlite");
            assert!(convert_package(&source, &dest).is_err(), "{failure}");
            assert!(!dest.exists());
            assert_eq!(std::fs::read(&source).unwrap(), original);
        }
    }
    #[test]
    fn generate_operator_fixture() {
        if let Ok(root) = std::env::var("UNIVERSE_OPERATOR_PROOF_ROOT") {
            fixture(Path::new(&root));
        }
    }
    #[test]
    fn process_termination_worker() {
        let Ok(root) = std::env::var("UNIVERSE_CONVERSION_KILL_ROOT") else {
            return;
        };
        let point = std::env::var("UNIVERSE_CONVERSION_KILL_POINT").unwrap();
        let root = PathBuf::from(root);
        let _ = convert_package_with_hook(
            &root.join("legacy.sqlite"),
            &root.join("killed.sqlite"),
            |p| {
                if format!("{p:?}") == point {
                    unsafe { libc::raise(libc::SIGKILL) };
                }
                Ok(())
            },
        );
        panic!("worker did not terminate at requested point");
    }
    #[test]
    fn process_kill_before_publication_preserves_recoverable_inputs() {
        use std::os::unix::process::ExitStatusExt;
        for point in ["Rows", "Audited", "BeforePublish"] {
            let d = tempfile::tempdir().unwrap();
            std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
            let source = fixture(d.path());
            let bytes = std::fs::read(&source).unwrap();
            let status = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "kernel::operator_conversion::tests::process_termination_worker",
                    "--nocapture",
                ])
                .env("UNIVERSE_CONVERSION_KILL_ROOT", d.path())
                .env("UNIVERSE_CONVERSION_KILL_POINT", point)
                .status()
                .unwrap();
            assert_eq!(status.signal(), Some(libc::SIGKILL));
            assert!(!d.path().join("killed.sqlite").exists());
            assert_eq!(std::fs::read(&source).unwrap(), bytes);
            convert_package(&source, &d.path().join("retry.sqlite")).unwrap();
        }
    }
    #[test]
    fn publication_race_never_overwrites_an_existing_destination() {
        let d = tempfile::tempdir().unwrap();
        std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        let source = fixture(d.path());
        let destination = d.path().join("race.sqlite");
        assert!(convert_package_with_hook(&source, &destination, |point| {
            if point == ConversionPoint::BeforePublish {
                std::fs::write(&destination, b"other operator target")?;
            }
            Ok(())
        })
        .is_err());
        assert_eq!(
            std::fs::read(destination).unwrap(),
            b"other operator target"
        );
    }
    #[test]
    fn explicit_relational_conversion_preserves_every_typed_table() {
        let d = tempfile::tempdir().unwrap();
        std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        let source = fixture(d.path());
        let first = d.path().join("first.sqlite");
        convert_package(&source, &first).unwrap();
        let c = Connection::open(&first).unwrap();
        c.execute_batch("DROP TABLE import_workflow_digest;")
            .unwrap();
        drop(c);
        let original = std::fs::read(&first).unwrap();
        assert!(Database::open_existing(&first).is_err());
        let second = d.path().join("second.sqlite");
        convert_package(&first, &second).unwrap();
        assert_eq!(std::fs::read(&first).unwrap(), original);
        let input = open_original(&first).unwrap();
        let output = open_original(&second).unwrap();
        for table in crate::transfer::tables(&input).unwrap() {
            compare_scalar_table(&input, &output, &table).unwrap();
        }
        drop(input);
        drop(output);
        Kernel::open(&second).unwrap();
    }
    #[test]
    fn source_sidecars_and_unsafe_paths_are_refused() {
        let d = tempfile::tempdir().unwrap();
        std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        let source = fixture(d.path());
        let dest = d.path().join("out.sqlite");
        let wal = PathBuf::from(format!("{}-wal", source.display()));
        std::fs::write(&wal, b"recovery").unwrap();
        assert!(convert_package(&source, &dest).is_err());
        assert_eq!(std::fs::read(&wal).unwrap(), b"recovery");
        std::fs::remove_file(wal).unwrap();
        let link = d.path().join("link.sqlite");
        std::os::unix::fs::symlink(&source, &link).unwrap();
        assert!(convert_package(&link, &dest).is_err());
        std::fs::set_permissions(&source, std::fs::Permissions::from_mode(0o644)).unwrap();
        assert!(convert_package(&source, &dest).is_err());
    }
}
