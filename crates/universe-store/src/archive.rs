//! Bounded, path-free logical JSONL. Editorial history is data, never installation authority.
use super::*;
use std::io::{Read, Write};
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
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "entry", rename_all = "snake_case", deny_unknown_fields)]
enum Row {
    Manifest {
        manifest: ArchiveManifest,
    },
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
    Checksum {
        sha256: String,
        rows: usize,
    },
}
pub struct LogicalArchive {
    pub manifest: ArchiveManifest,
    rows: Vec<Row>,
    pub digest: String,
}
impl LogicalArchive {
    /// Only flat typed JSONL is accepted: no archive member names, SQL, or paths.
    pub fn read(path: &Path) -> StoreResult<Self> {
        let file = crate::ownership::protected_file(path, false)?;
        let mut bytes = Vec::new();
        file.take((MAX_BYTES + 1) as u64).read_to_end(&mut bytes)?;
        if bytes.len() > MAX_BYTES {
            return Err(invalid("logical archive exceeds 512 MiB"));
        }
        let mut rows = Vec::new();
        let mut hasher = Sha256::new();
        let mut checksum = None;
        for line in bytes.split_inclusive(|b| *b == b'\n') {
            if checksum.is_some() || line.len() > 2 * 1_048_576 || rows.len() > MAX_ROWS {
                return Err(invalid("archive framing or row budget exceeded"));
            }
            let row: Row =
                serde_json::from_slice(line).map_err(|_| invalid("invalid typed archive row"))?;
            if let Row::Checksum {
                sha256,
                rows: count,
            } = row
            {
                if count != rows.len() || sha256 != hex::encode(hasher.clone().finalize()) {
                    return Err(invalid("archive checksum mismatch"));
                }
                checksum = Some(sha256);
            } else {
                hasher.update(line);
                rows.push(row);
            }
        }
        let digest = checksum.ok_or_else(|| invalid("archive checksum missing"))?;
        let Some(Row::Manifest { manifest }) = rows.first() else {
            return Err(invalid("archive manifest must be first"));
        };
        if manifest.format != "universe-logical-v1"
            || !manifest.includes_history
            || manifest.includes_workflow
            || manifest.complete != (manifest.omitted_records == 0)
        {
            return Err(invalid("unsupported or inconsistent archive manifest"));
        }
        selector_key(&manifest.name)?;
        if rows
            .iter()
            .skip(1)
            .any(|r| matches!(r, Row::Manifest { .. }))
        {
            return Err(invalid("duplicate archive manifest"));
        }
        Ok(Self {
            manifest: manifest.clone(),
            rows,
            digest,
        })
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
                tx.execute(
                    "INSERT INTO workflow_entries VALUES(?1,?2,?3)",
                    params![
                        media::chunk_key(hash, *index),
                        canonical_serde(&value).to_bytes(),
                        digest(&value)
                    ],
                )?;
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
                tx.execute(
                    "INSERT OR IGNORE INTO workflow_entries VALUES(?1,?2,?3)",
                    params![
                        format!("image-asset:{}", record.identity.record_id),
                        canonical_serde(&value).to_bytes(),
                        digest(&value)
                    ],
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
        staged.insert("logical-import-origin".into(),serde_json::json!({"digest":self.digest,"source_universe":self.manifest.universe,"target_universe":target,"complete":self.manifest.complete,"omitted_records":self.manifest.omitted_records}));
        kernel.workflow_put(&staged.into_iter().collect::<Vec<_>>())?;
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
    pub fn export_logical(
        &self,
        destination: &Path,
        requested: &[RecordId],
    ) -> StoreResult<ArchiveManifest> {
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
            format: "universe-logical-v1".into(),
            universe: self.universe.clone(),
            name: self
                .conn
                .query_row("SELECT name FROM universes", [], |r| r.get(0))?,
            complete: included.len() == all_ids.len(),
            omitted_records: all_ids.len() - included.len(),
            includes_history: true,
            includes_workflow: false,
        };
        let mut rows = vec![Row::Manifest {
            manifest: manifest.clone(),
        }];
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
        let parent = destination
            .parent()
            .ok_or_else(|| invalid("export parent required"))?;
        let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
        let mut hasher = Sha256::new();
        let mut total = 0;
        for row in &rows {
            let mut bytes = serde_json::to_vec(row).map_err(|_| invalid("archive row encoding"))?;
            bytes.push(b'\n');
            total += bytes.len();
            if total > MAX_BYTES - 1024 {
                return Err(invalid("archive byte budget exceeded"));
            }
            hasher.update(&bytes);
            temporary.write_all(&bytes)?;
        }
        let trailer = Row::Checksum {
            sha256: hex::encode(hasher.finalize()),
            rows: rows.len(),
        };
        temporary
            .write_all(&serde_json::to_vec(&trailer).map_err(|_| invalid("checksum encoding"))?)?;
        temporary.write_all(b"\n")?;
        temporary.as_file().sync_all()?;
        // Read our own serialized representation before publishing a no-clobber file.
        LogicalArchive::read(temporary.path())?;
        temporary
            .persist_noclobber(destination)
            .map_err(|e| StoreError::Io(e.error))?;
        std::fs::File::open(parent)?.sync_all()?;
        Ok(manifest)
    }
}

#[path = "legacy.rs"]
mod legacy;
pub use legacy::convert_legacy;
