//! Bounded relational archives. Editorial history is evidence, never installation authority.
use super::*;
use std::io::Read;
pub const MAX_ARCHIVE_BYTES: usize = 512 * 1_048_576;
const MAX_BYTES: usize = MAX_ARCHIVE_BYTES;
const MAX_ROWS: usize = 2_000_000;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ArchiveManifest {
    pub format: String,
    pub universe: UniverseId,
    pub name: String,
    pub complete: bool,
    pub omitted_records: usize,
    pub includes_history: bool,
    pub includes_workflow: bool,
}
#[derive(Debug, Clone)]
enum Row {
    Record {
        record: Box<RecordVersion>,
    },
    Continuity {
        id: ContinuityId,
        head: RevisionId,
        baseline: Option<RevisionId>,
    },
    Commit {
        id: RevisionId,
        continuity: ContinuityId,
        parent: Option<RevisionId>,
        sequence: i64,
        principal: String,
        decision: String,
        reason: String,
        digest: String,
    },
    Change {
        revision: RevisionId,
        record: RecordId,
        prior: Option<RecordVersionId>,
        next: Option<RecordVersionId>,
    },
    Reservation {
        name: String,
        record: RecordId,
        revision: RevisionId,
    },
    Text {
        digest: String,
        text: String,
    },
    ImageChunk {
        digest: String,
        index: usize,
        data: String,
    },
}
pub struct LogicalArchive {
    pub manifest: ArchiveManifest,
    rows: Vec<Row>,
    pub digest: String,
    package: Option<tempfile::TempDir>,
}
impl LogicalArchive {
    /// Copy into the trusted schema before any domain reader opens the input.
    pub fn read(path: &Path) -> StoreResult<Self> {
        let input = crate::ownership::protected_file(path, false)?;
        if input.metadata()?.len() > MAX_BYTES as u64 {
            return Err(invalid("logical archive exceeds 512 MiB"));
        }
        let temporary = tempfile::Builder::new()
            .prefix("relational-archive-")
            .tempdir()?;
        let snapshot = temporary.path().join("input.sqlite");
        let mut output = crate::ownership::protected_file(&snapshot, true)?;
        let copied = std::io::copy(&mut input.take((MAX_BYTES + 1) as u64), &mut output)?;
        if copied > MAX_BYTES as u64 {
            return Err(invalid("logical archive exceeds 512 MiB"));
        }
        output.sync_all()?;
        drop(output);
        let safe = temporary.path().join("package.sqlite");
        crate::ownership::protected_file(&safe, true)?;
        crate::transfer::trusted_copy(&snapshot, &safe, true, || Ok(()))?;
        let c = Database::open_existing(&safe)?.connect()?;
        let (row,recipe,digest,count,authority,manifest_hash):(i64,String,String,i64,String,String)=c.query_row("SELECT manifest_row,checksum_recipe,sha256,row_count,authority_state,manifest_sha256 FROM archive_integrity WHERE singleton=1",[],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?,r.get(4)?,r.get(5)?)))?;
        let (actual, rows) = crate::transfer::checksum(&c)?;
        if recipe != "typed-row-stream"
            || digest != actual
            || count != rows as i64
            || authority != "historical_evidence_only"
        {
            return Err(invalid("archive checksum mismatch"));
        }
        let manifest: ArchiveManifest = serde_json::from_value(crate::relational::get(
            &c,
            "ArchiveManifest",
            rusqlite::types::Value::Integer(row),
        )?)
        .map_err(|_| invalid("invalid archive manifest"))?;
        if digest_manifest(&manifest) != manifest_hash {
            return Err(invalid("archive manifest checksum mismatch"));
        }
        let manifest_rows: i64 =
            c.query_row("SELECT count(*) FROM r_archive_manifest", [], |r| r.get(0))?;
        if manifest_rows != 1 {
            return Err(invalid("archive must have exactly one manifest"));
        }
        if manifest.format != "universe-relational"
            || !manifest.includes_history
            || manifest.complete != (manifest.omitted_records == 0)
            || (manifest.includes_workflow && !manifest.complete)
        {
            return Err(invalid("inconsistent relational archive manifest"));
        }
        selector_key(&manifest.name)?;
        if !manifest.includes_workflow {
            for table in [
                "workflow_entries",
                "operation_receipts",
                "historical_workflow",
                "historical_receipt",
            ] {
                let count: i64 =
                    c.query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r.get(0))?;
                if count != 0 {
                    return Err(invalid("canon-only archive contains workflow evidence"));
                }
            }
        }
        drop(c);
        let kernel = Kernel::open(&safe)?;
        verify_content_links(&kernel.conn)?;
        if kernel.universe() != &manifest.universe {
            return Err(invalid("archive universe mismatch"));
        }
        let mut archive = kernel.collect_archive(&[])?;
        archive.manifest = manifest;
        archive.digest = hex::encode(Sha256::digest(
            format!("typed-row-stream:{digest}:manifest:{manifest_hash}").as_bytes(),
        ));
        // All history and exact content validate in the trusted copy; no second
        // reconstruction into another package is needed merely to read it.
        verify_history(&kernel.conn, kernel.universe.as_str())?;
        drop(kernel);
        archive.package = Some(temporary);
        Ok(archive)
    }
    pub fn record_count(&self) -> usize {
        self.rows
            .iter()
            .filter_map(|r| {
                if let Row::Record { record } = r {
                    Some(&record.identity.record_id)
                } else {
                    None
                }
            })
            .collect::<BTreeSet<_>>()
            .len()
    }
    /// Build a private staged package. Publication/approval belongs to the service.
    pub fn stage(
        &self,
        scratch: &Path,
        target: UniverseId,
        name: &str,
    ) -> StoreResult<(Kernel, tempfile::TempDir)> {
        selector_key(name)?;
        if !self.manifest.complete && target == self.manifest.universe {
            return Err(invalid(
                "filtered archives require an explicitly named clone",
            ));
        }
        if target == self.manifest.universe && self.manifest.includes_workflow {
            if let Some(package) = &self.package {
                let temporary = tempfile::Builder::new()
                    .prefix(".logical-import-")
                    .tempdir_in(scratch)?;
                let path = temporary.path().join("package.sqlite");
                crate::ownership::protected_file(&path, true)?;
                let db = Database::open(&path)?;
                let mut output = db.connect()?;
                let input =
                    Database::open_existing(package.path().join("package.sqlite"))?.connect()?;
                crate::transfer::copy_rows(&input, &mut output, || Ok(()))?;
                output.execute("UPDATE universes SET name=?1", [name])?;
                mark_historical(&output)?;
                let tx = output.transaction()?;
                crate::workflow_storage::put(
                    &tx,
                    &format!("logical-import-origin:{}", self.digest),
                    &serde_json::json!({"digest":self.digest,"source_universe":self.manifest.universe,"target_universe":target,"complete":self.manifest.complete,"omitted_records":self.manifest.omitted_records}),
                )?;
                tx.commit()?;
                drop(output);
                let kernel = Kernel::open(&path)?;
                return Ok((kernel, temporary));
            }
        }
        let temporary = tempfile::Builder::new()
            .prefix(".logical-import-")
            .tempdir_in(scratch)?;
        let path = temporary.path().join("package.sqlite");
        crate::ownership::protected_file(&path, true)?;
        let db = Database::open(&path)?;
        let mut conn = db.connect()?;
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        tx.execute_batch("PRAGMA defer_foreign_keys=ON;")?;
        tx.prepare_cached("INSERT INTO universes(id,name) VALUES(?1,?2)")?
            .execute(params![target.as_str(), name])?;
        let mut identities = BTreeMap::new();
        let mut version_ids = BTreeSet::new();
        let mut texts = BTreeMap::new();
        let mut records = Vec::new();
        for row in &self.rows {
            if let Row::Record { record } = row {
                if record.identity.universe_id != self.manifest.universe
                    || !record.verify_digest()
                    || !version_ids.insert(record.record_version_id.clone())
                {
                    return Err(invalid("invalid archive record identity, schema or digest"));
                }
                if let Some(kind) = identities.insert(
                    record.identity.record_id.clone(),
                    record.identity.record_kind,
                ) {
                    if kind != record.identity.record_kind {
                        return Err(invalid("archive identity changes kind"));
                    }
                }
                let mut payload = serde_json::to_value(&record.payload)
                    .map_err(|_| invalid("record encoding"))?;
                remap_references(&mut payload, &self.manifest.universe, &target);
                let mut payload: Payload =
                    serde_json::from_value(payload).map_err(|_| invalid("record mapping"))?;
                if let Payload::RepresentedContext(context) = &mut payload {
                    if context.universe != self.manifest.universe {
                        return Err(invalid("foreign represented context universe"));
                    }
                    context.universe = target.clone();
                }
                let mapped = RecordVersion::build(
                    record.record_version_id.clone(),
                    RecordIdentity::new(
                        target.clone(),
                        record.identity.record_id.clone(),
                        record.identity.record_kind,
                    ),
                    payload,
                )
                .map_err(|_| invalid("record mapping"))?;
                records.push(mapped);
            }
            if let Row::Text { digest, text } = row {
                if text.len() > 512_000
                    || hex::encode(Sha256::digest(text.as_bytes())) != *digest
                    || texts.insert(digest.clone(), text.clone()).is_some()
                {
                    return Err(invalid("invalid or duplicate source bytes"));
                }
            }
        }
        if records.len() > MAX_VERSIONS || identities.len() > MAX_RECORDS {
            return Err(invalid("archive record budget exceeded"));
        }
        for (id, kind) in &identities {
            tx.prepare_cached("INSERT INTO record_identities VALUES(?1,?2,?3)")?
                .execute(params![target.as_str(), id.as_str(), kind.as_str()])?;
        }
        for r in &records {
            let bytes = serde_json::to_vec(r).map_err(|_| invalid("record encoding"))?;
            if bytes.len() > 1_048_576 {
                return Err(invalid("archive record too large"));
            }
            insert_version(&tx, r)?;
        }
        for row in &self.rows {
            match row {
                Row::Continuity { id, head, baseline } => {
                    tx.prepare_cached("INSERT INTO continuities VALUES(?1,?2,?3,?4)")?
                        .execute(params![
                            target.as_str(),
                            id.as_str(),
                            head.as_str(),
                            baseline.as_ref().map(|v| v.as_str())
                        ])?;
                }
                Row::Commit {
                    id,
                    continuity,
                    parent,
                    sequence,
                    principal,
                    decision,
                    reason,
                    digest,
                } => {
                    tx.prepare_cached("INSERT INTO commits VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)")?
                        .execute(params![
                            target.as_str(),
                            id.as_str(),
                            continuity.as_str(),
                            parent.as_ref().map(|v| v.as_str()),
                            sequence,
                            principal,
                            decision,
                            reason,
                            digest
                        ])?;
                }
                Row::Change {
                    revision,
                    record,
                    prior,
                    next,
                } => {
                    tx.prepare_cached("INSERT INTO commit_changes VALUES(?1,?2,?3,?4,?5)")?
                        .execute(params![
                            target.as_str(),
                            revision.as_str(),
                            record.as_str(),
                            prior.as_ref().map(|v| v.as_str()),
                            next.as_ref().map(|v| v.as_str())
                        ])?;
                }
                Row::Reservation {
                    name,
                    record,
                    revision,
                } => {
                    if selector_key(name)? != *name {
                        return Err(invalid("non-normalized world reservation"));
                    }
                    tx.prepare_cached("INSERT INTO world_name_reservations VALUES(?1,?2,?3,?4)")?
                        .execute(params![
                            target.as_str(),
                            name,
                            record.as_str(),
                            revision.as_str()
                        ])?;
                }
                _ => {}
            }
        }
        let mut image_chunks = BTreeSet::new();
        for row in &self.rows {
            if let Row::ImageChunk {
                digest: hash,
                index,
                data,
            } = row
            {
                if hash.len() != 64
                    || !hash
                        .bytes()
                        .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
                    || *index >= media::MAX_IMAGE_BYTES.div_ceil(media::IMAGE_CHUNK)
                    || data.len() > media::IMAGE_CHUNK.div_ceil(3) * 4
                    || !image_chunks.insert((hash.clone(), *index))
                {
                    return Err(invalid("invalid or duplicate image chunk"));
                }
                let value = Value::String(data.clone());
                crate::workflow_storage::put(&tx, &media::chunk_key(hash, *index), &value)?;
            }
        }
        let mut used_chunks = BTreeSet::new();
        let mut image_receipts = BTreeMap::new();
        let mut verified_images = BTreeSet::new();
        for record in &records {
            if let Payload::ImageAsset(asset) = &record.payload {
                media::validate_image_metadata(asset)?;
                if verified_images.insert((
                    asset.digest.clone(),
                    asset.media_type.clone(),
                    asset.byte_size,
                    asset.width,
                    asset.height,
                )) {
                    let bytes = media::image_bytes_from(&tx, asset)?;
                    media::validate_image_bytes(asset, &bytes)?;
                }
                used_chunks.extend(
                    (0..(asset.byte_size as usize).div_ceil(media::IMAGE_CHUNK))
                        .map(|i| (asset.digest.clone(), i)),
                );
                let value =
                    serde_json::to_value(&record.payload).map_err(|_| invalid("image encoding"))?;
                if let Some(old) =
                    image_receipts.insert(record.identity.record_id.clone(), value.clone())
                {
                    if old != value {
                        return Err(invalid("archive changes immutable image import metadata"));
                    }
                }
                crate::workflow_storage::put(
                    &tx,
                    &format!("image-asset:{}", record.identity.record_id),
                    &value,
                )?;
            }
        }
        if used_chunks != image_chunks {
            return Err(invalid("archive contains unreferenced image chunks"));
        }
        tx.commit()?;
        drop(conn);
        let mut kernel = Kernel::open(&path)?;
        for r in &records {
            if let Payload::World(w) = &r.payload {
                for name in std::iter::once(&w.selector).chain(w.aliases.iter()) {
                    let reserved:Option<String>=kernel.conn.query_row("SELECT record_id FROM world_name_reservations WHERE universe_id=?1 AND name=?2",params![target.as_str(),selector_key(name)?],|r|r.get(0)).optional()?;
                    if reserved.as_deref() != Some(r.identity.record_id.as_str()) {
                        return Err(invalid("archive omits a historical world name reservation"));
                    }
                }
            }
        }
        // Validate every historical snapshot, not just today's heads. Bound replay work.
        let mut work = 0usize;
        for row in &self.rows {
            if let Row::Commit { id, continuity, .. } = row {
                let membership = kernel.snapshot(continuity, id)?;
                work += membership.len() + 1;
                if work > 10_000_000 {
                    return Err(invalid("archive historical validation budget exceeded"));
                }
                // snapshot already validates every reconstructed reference.
            }
        }
        let mut used_texts = BTreeSet::new();
        let mut staged = BTreeMap::new();
        for r in &records {
            if let Payload::SourceVersion(v) = &r.payload {
                let text = texts
                    .get(&v.digest)
                    .ok_or_else(|| invalid("archive source asset missing"))?;
                if text.len() as u64 != v.byte_size
                    || v.decoding.byte_length != v.byte_size
                    || v.decoding.encoding != "UTF-8"
                    || v.decoding.representation != "exact-utf8-v1"
                {
                    return Err(invalid("archive source decoding mismatch"));
                }
                used_texts.insert(v.digest.clone());
                let key = format!("source-version:{}", r.identity.record_id);
                let payload =
                    serde_json::to_value(&r.payload).map_err(|_| invalid("source encoding"))?;
                if staged
                    .insert(key, payload.clone())
                    .is_some_and(|old| old != payload)
                {
                    return Err(invalid("source version identity has multiple payloads"));
                }
            }
        }
        for r in &records {
            if let Payload::Anchor(a) = &r.payload {
                let source = records
                    .iter()
                    .find(|r| {
                        r.record_version_id == a.source_version.version
                            && r.identity.record_id == a.source_version.record
                    })
                    .ok_or_else(|| invalid("archive anchor version missing"))?;
                let Payload::SourceVersion(v) = &source.payload else {
                    return Err(invalid("archive anchor source kind"));
                };
                let AnchorLocator::ByteRange { start, end } = a.locator else {
                    return Err(invalid("archive anchor locator unsupported"));
                };
                let text = texts
                    .get(&v.digest)
                    .ok_or_else(|| invalid("archive source missing"))?;
                let excerpt = text
                    .get(start as usize..end as usize)
                    .ok_or_else(|| invalid("archive anchor UTF-8 boundaries"))?;
                if excerpt != a.excerpt
                    || hex::encode(Sha256::digest(excerpt.as_bytes())) != a.excerpt_digest
                {
                    return Err(invalid("archive anchor excerpt mismatch"));
                }
            }
        }
        if used_texts.len() != texts.len() {
            return Err(invalid("archive contains unreferenced source assets"));
        }
        for (id, text) in texts {
            staged.insert(format!("source:{id}"), Value::String(text));
        }
        if !self.digest.is_empty() {
            staged.insert(format!("logical-import-origin:{}",self.digest),serde_json::json!({"digest":self.digest,"source_universe":self.manifest.universe,"target_universe":target,"complete":self.manifest.complete,"omitted_records":self.manifest.omitted_records}));
        }
        if self.manifest.includes_workflow && self.package.is_some() {
            // Preserve original staging receipt bodies/bindings, including uncommitted assets.
            staged.retain(|key, _| {
                !key.starts_with("source-version:") && !key.starts_with("image-asset:")
            });
        }
        kernel.workflow_put(&staged.into_iter().collect::<Vec<_>>())?;
        if let Some(package) = &self.package {
            let input =
                Database::open_existing(package.path().join("package.sqlite"))?.connect()?;
            let tx = kernel.conn.transaction()?;
            if self.manifest.includes_workflow {
                let keys: Vec<String> = input
                    .prepare("SELECT key FROM workflow_index ORDER BY key")?
                    .query_map([], |r| r.get(0))?
                    .collect::<Result<_, _>>()?;
                for key in keys {
                    // Preserve original universe references and digest bindings in historical evidence.
                    let value = crate::workflow_storage::evidence(&input, &key)?
                        .ok_or_else(|| invalid("missing historical workflow"))?;
                    if key.starts_with("continuity-name:") {
                        continue;
                    }
                    crate::workflow_storage::put(&tx, &key, &value)?;
                    tx.execute("INSERT INTO historical_workflow SELECT key FROM workflow_entries WHERE key=?1",[key])?;
                }
                let mut stmt=input.prepare("SELECT principal,operation_kind,idempotency_key,payload_digest,revision_id FROM operation_receipts")?;
                let mut query = stmt.query([])?;
                while let Some(r) = query.next()? {
                    let values = (0..5)
                        .map(|i| r.get::<_, String>(i))
                        .collect::<Result<Vec<_>, _>>()?;
                    tx.execute(
                        "INSERT INTO operation_receipts VALUES(?1,?2,?3,?4,?5,?6)",
                        params![
                            target.as_str(),
                            values[0],
                            values[1],
                            values[2],
                            values[3],
                            values[4]
                        ],
                    )?;
                }
                tx.execute("INSERT INTO historical_receipt SELECT universe_id,principal,operation_kind,idempotency_key FROM operation_receipts",[])?;
            }
            let names: Vec<(String, String, String, String)> = input
                .prepare("SELECT continuity_id,key,name,workflow_digest FROM continuity_name")?
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?
                .collect::<Result<_, _>>()?;
            for (id, key, name, hash) in names {
                tx.execute(
                    "INSERT INTO continuity_name VALUES(?1,?2,?3,?4)",
                    params![id, key, name, hash],
                )?;
            }
            // Record original digest bindings on remapping without claiming they bind changed bodies.
            for r in &self.rows {
                if let Row::Record { record } = r {
                    let mapped = records
                        .iter()
                        .find(|v| v.record_version_id == record.record_version_id)
                        .ok_or_else(|| invalid("missing mapped record"))?;
                    let original: Option<String> = input
                        .query_row(
                            "SELECT source_digest FROM import_record_digest WHERE version_id=?1",
                            [record.record_version_id.as_str()],
                            |r| r.get(0),
                        )
                        .optional()?;
                    if original.is_some() || mapped.payload_digest != record.payload_digest {
                        tx.execute(
                            "INSERT INTO import_record_digest VALUES(?1,?2,?3,?4)",
                            params![
                                target.as_str(),
                                record.record_version_id.as_str(),
                                original
                                    .unwrap_or_else(|| record.payload_digest.as_str().to_owned()),
                                mapped.payload_digest.as_str()
                            ],
                        )?;
                    }
                }
            }
            tx.commit()?;
        }
        kernel.integrity()?;
        Ok((kernel, temporary))
    }
}
fn remap_references(value: &mut Value, source: &UniverseId, target: &UniverseId) {
    match value {
        Value::Object(map) => {
            // Closed typed payloads encode references as these exact object shapes.
            if map.contains_key("record")
                && map
                    .keys()
                    .all(|k| matches!(k.as_str(), "universe" | "record" | "version"))
                && map.get("universe").and_then(Value::as_str) == Some(source.as_str())
            {
                map.insert("universe".into(), Value::String(target.0.clone()));
            }
            for child in map.values_mut() {
                remap_references(child, source, target);
            }
        }
        Value::Array(values) => {
            for child in values {
                remap_references(child, source, target);
            }
        }
        _ => {}
    }
}
impl Kernel {
    fn collect_archive(&self, requested: &[RecordId]) -> StoreResult<LogicalArchive> {
        let ids: Vec<String> = self
            .conn
            .prepare("SELECT id FROM record_versions ORDER BY id")?
            .query_map([], |r| r.get(0))?
            .collect::<Result<_, _>>()?;
        if ids.len() > MAX_VERSIONS {
            return Err(invalid("archive version budget exceeded"));
        }
        let records: Vec<_> = ids
            .iter()
            .map(|id| load(&self.conn, self.universe.as_str(), id))
            .collect::<StoreResult<_>>()?;
        let all_ids: BTreeSet<_> = records
            .iter()
            .map(|r| r.identity.record_id.clone())
            .collect();
        let mut included = BTreeSet::new();
        let mut pending = if requested.is_empty() {
            all_ids.iter().cloned().collect()
        } else {
            requested.to_vec()
        };
        // Query frames and global definitions/policies remain usable in a filtered clone.
        pending.extend(
            records
                .iter()
                .filter(|r| {
                    matches!(
                        r.payload,
                        Payload::RepresentedContext(_)
                            | Payload::EntityType(_)
                            | Payload::Property(_)
                            | Payload::Relation(_)
                            | Payload::Unit(_)
                            | Payload::Calendar(_)
                            | Payload::ValueDefinition(_)
                            | Payload::Rule(_)
                            | Payload::Boundary(_)
                            | Payload::Completeness(_)
                            | Payload::Exception(_)
                    )
                })
                .map(|r| r.identity.record_id.clone()),
        );
        let mut attachments = BTreeMap::<RecordId, Vec<RecordId>>::new();
        for r in &records {
            if let Payload::Appearance(a) = &r.payload {
                match &a.target {
                    AppearanceTarget::Universe => pending.push(r.identity.record_id.clone()),
                    AppearanceTarget::Entry { entry } => attachments
                        .entry(entry.record.clone())
                        .or_default()
                        .push(r.identity.record_id.clone()),
                }
            }
        }
        while let Some(id) = pending.pop() {
            if !all_ids.contains(&id) {
                return Err(invalid("export identity unavailable"));
            }
            if !included.insert(id.clone()) {
                continue;
            }
            for r in records.iter().filter(|r| r.identity.record_id == id) {
                pending.extend(record_dependencies(r)?);
                pending.extend(attachments.get(&id).into_iter().flatten().cloned());
            }
        }
        let manifest = ArchiveManifest {
            format: "universe-relational".into(),
            universe: self.universe.clone(),
            name: self
                .conn
                .query_row("SELECT name FROM universes", [], |r| r.get(0))?,
            complete: included.len() == all_ids.len(),
            omitted_records: all_ids.len() - included.len(),
            includes_history: true,
            includes_workflow: false,
        };
        let mut rows = Vec::new();
        let mut texts = BTreeSet::new();
        let mut images = BTreeMap::new();
        for r in records
            .into_iter()
            .filter(|r| included.contains(&r.identity.record_id))
        {
            if let Payload::SourceVersion(v) = &r.payload {
                texts.insert(v.digest.clone());
            }
            if let Payload::ImageAsset(asset) = &r.payload {
                images.insert(asset.digest.clone(), asset.clone());
            }
            rows.push(Row::Record {
                record: Box::new(r),
            });
        }
        let continuities: Vec<(String, String, Option<String>)> = self
            .conn
            .prepare("SELECT id,head_commit,baseline_commit FROM continuities ORDER BY id")?
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
            .collect::<Result<_, _>>()?;
        for (id, head, baseline) in continuities {
            rows.push(Row::Continuity {
                id: ContinuityId::parse(&id).map_err(|_| invalid("continuity id"))?,
                head: RevisionId::parse(&head).map_err(|_| invalid("revision id"))?,
                baseline: baseline
                    .map(|s| RevisionId::parse(&s).map_err(|_| invalid("baseline id")))
                    .transpose()?,
            });
        }
        let mut stmt=self.conn.prepare("SELECT id,continuity_id,parent_id,sequence,principal,decision,reason,digest FROM commits ORDER BY continuity_id,sequence")?;
        let mut query = stmt.query([])?;
        while let Some(r) = query.next()? {
            let id: String = r.get(0)?;
            let c: String = r.get(1)?;
            let parent: Option<String> = r.get(2)?;
            rows.push(Row::Commit {
                id: RevisionId::parse(&id).map_err(|_| invalid("revision id"))?,
                continuity: ContinuityId::parse(&c).map_err(|_| invalid("continuity id"))?,
                parent: parent
                    .map(|s| RevisionId::parse(&s).map_err(|_| invalid("parent id")))
                    .transpose()?,
                sequence: r.get(3)?,
                principal: r.get(4)?,
                decision: r.get(5)?,
                reason: r.get(6)?,
                digest: r.get(7)?,
            });
        }
        let mut stmt=self.conn.prepare("SELECT revision_id,record_id,prior_version,version_id FROM commit_changes ORDER BY revision_id,record_id")?;
        let mut query = stmt.query([])?;
        while let Some(r) = query.next()? {
            let rec: String = r.get(1)?;
            let record = RecordId::parse(&rec).map_err(|_| invalid("record id"))?;
            if !included.contains(&record) {
                continue;
            }
            let rev: String = r.get(0)?;
            let prior: Option<String> = r.get(2)?;
            let next: Option<String> = r.get(3)?;
            rows.push(Row::Change {
                revision: RevisionId::parse(&rev).map_err(|_| invalid("revision id"))?,
                record,
                prior: prior
                    .map(|s| RecordVersionId::parse(&s).map_err(|_| invalid("prior version")))
                    .transpose()?,
                next: next
                    .map(|s| RecordVersionId::parse(&s).map_err(|_| invalid("next version")))
                    .transpose()?,
            });
        }
        let mut stmt = self.conn.prepare(
            "SELECT name,record_id,first_revision FROM world_name_reservations ORDER BY name",
        )?;
        let mut query = stmt.query([])?;
        while let Some(r) = query.next()? {
            let rec: String = r.get(1)?;
            let record = RecordId::parse(&rec).map_err(|_| invalid("record id"))?;
            if !included.contains(&record) {
                continue;
            }
            let rev: String = r.get(2)?;
            rows.push(Row::Reservation {
                name: r.get(0)?,
                record,
                revision: RevisionId::parse(&rev).map_err(|_| invalid("reservation revision"))?,
            });
        }
        for id in texts {
            let text = self
                .workflow_get(&format!("source:{id}"))?
                .and_then(|v| v.as_str().map(str::to_owned))
                .ok_or_else(|| invalid("source bytes unavailable"))?;
            rows.push(Row::Text { digest: id, text });
        }
        for asset in images.values() {
            self.image_bytes(asset)?;
            for index in 0..(asset.byte_size as usize).div_ceil(media::IMAGE_CHUNK) {
                let data = self
                    .workflow_get(&media::chunk_key(&asset.digest, index))?
                    .and_then(|v| v.as_str().map(str::to_owned))
                    .ok_or_else(|| invalid("image chunk unavailable"))?;
                rows.push(Row::ImageChunk {
                    digest: asset.digest.clone(),
                    index,
                    data,
                });
            }
        }
        if rows.len() > MAX_ROWS {
            return Err(invalid("archive row budget exceeded"));
        }
        Ok(LogicalArchive {
            manifest,
            rows,
            digest: String::new(),
            package: None,
        })
    }
    pub fn export_logical(
        &self,
        destination: &Path,
        requested: &[RecordId],
    ) -> StoreResult<ArchiveManifest> {
        self.export_relational(destination, requested, false)
    }
    pub fn export_relational(
        &self,
        destination: &Path,
        requested: &[RecordId],
        complete_history: bool,
    ) -> StoreResult<ArchiveManifest> {
        if complete_history && !requested.is_empty() {
            return Err(invalid("complete-history export requires all records"));
        }
        let parent = destination
            .parent()
            .ok_or_else(|| invalid("export parent required"))?;
        let directory = tempfile::Builder::new()
            .prefix(".relational-export-")
            .tempdir_in(parent)?;
        // Pin all canonical and workflow reads to one consistent SQLite snapshot.
        let snapshot = directory.path().join("snapshot.sqlite");
        self.backup(&snapshot)?;
        let source = Kernel::open(&snapshot)?;
        let mut logical = source.collect_archive(requested)?;
        let manifest = ArchiveManifest {
            includes_workflow: complete_history,
            ..logical.manifest.clone()
        };
        let path = directory.path().join("export.sqlite");
        let guard;
        if complete_history {
            crate::ownership::protected_file(&path, true)?;
            let db = Database::open(&path)?;
            let mut target = db.connect()?;
            crate::transfer::copy_rows(&source.conn, &mut target, || Ok(()))?;
            guard = None;
        } else {
            // Internal rows are transient typed values; no JSONL is persisted.
            logical.digest = String::new();
            logical.manifest.complete = true;
            let (staged, temporary) =
                logical.stage(directory.path(), manifest.universe.clone(), &manifest.name)?;
            drop(staged);
            let db = Database::open_existing(temporary.path().join("package.sqlite"))?;
            let c = db.connect()?;
            // Preserve existing digest provenance for the included factual versions.
            let tx = c.unchecked_transaction()?;
            let mut stmt=source.conn.prepare("SELECT universe_id,version_id,source_digest,normalized_digest FROM import_record_digest")?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                let values = (0..4)
                    .map(|i| r.get::<_, String>(i))
                    .collect::<Result<Vec<_>, _>>()?;
                let included: bool = tx.query_row(
                    "SELECT EXISTS(SELECT 1 FROM record_versions WHERE id=?1)",
                    [&values[1]],
                    |r| r.get(0),
                )?;
                if included {
                    tx.execute(
                        "INSERT INTO import_record_digest VALUES(?1,?2,?3,?4)",
                        params![values[0], values[1], values[2], values[3]],
                    )?;
                }
            }
            let names: Vec<(String, String, String, String)> = source
                .conn
                .prepare("SELECT continuity_id,key,name,workflow_digest FROM continuity_name")?
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?
                .collect::<Result<_, _>>()?;
            for (id, key, name, hash) in names {
                tx.execute(
                    "INSERT INTO continuity_name VALUES(?1,?2,?3,?4)",
                    params![id, key, name, hash],
                )?;
            }
            tx.commit()?;
            c.execute_batch("PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;")?;
            drop(c);
            std::fs::rename(db.path(), &path)?;
            guard = Some(temporary);
        }
        let db = Database::open_existing(&path)?;
        let mut c = db.connect()?;
        c.execute_batch(crate::transfer::EXPORT_SQL)?;
        let tx = c.transaction()?;
        let manifest_row = crate::relational::put(
            &tx,
            "ArchiveManifest",
            &serde_json::to_value(&manifest).map_err(|_| invalid("manifest encoding"))?,
        )?;
        let (checksum, count) = crate::transfer::checksum(&tx)?;
        tx.execute("INSERT INTO archive_integrity VALUES(1,?1,'typed-row-stream',?2,?3,'historical_evidence_only',?4)",params![manifest_row,checksum,count as i64,digest_manifest(&manifest)])?;
        tx.commit()?;
        c.execute_batch("PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;")?;
        drop(c);
        drop(source);
        drop(guard);
        if std::fs::metadata(&path)?.len() > MAX_BYTES as u64 {
            return Err(invalid("archive byte budget exceeded"));
        }
        LogicalArchive::read(&path)?;
        let mut publication = tempfile::NamedTempFile::new_in(parent)?;
        std::io::copy(&mut std::fs::File::open(&path)?, &mut publication)?;
        publication.as_file().sync_all()?;
        publication
            .persist_noclobber(destination)
            .map_err(|e| StoreError::Io(e.error))?;
        std::fs::File::open(parent)?.sync_all()?;
        Ok(manifest)
    }
}

#[path = "legacy.rs"]
mod legacy;
pub use legacy::convert_legacy;

pub(super) fn mark_historical(c: &Connection) -> StoreResult<()> {
    c.execute(
        "INSERT OR IGNORE INTO historical_workflow SELECT key FROM workflow_entries",
        [],
    )?;
    c.execute("INSERT OR IGNORE INTO historical_receipt SELECT universe_id,principal,operation_kind,idempotency_key FROM operation_receipts",[])?;
    Ok(())
}

fn digest_manifest(manifest: &ArchiveManifest) -> String {
    hex::encode(Sha256::digest(canonical_serde(manifest).to_bytes()))
}
