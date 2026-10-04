//! Explicit v0.3/schema-v0 typed-canon conversion. Never upgrades the input in place.
use super::*;
use universe_domain::records::{RecordIdentity, RecordKind};
/// Convert supported typed legacy canon into a validated logical archive for normal
/// mapping preview/approval. Ambiguous scaffold/source/workflow data fails closed.
pub fn convert_legacy(source: &Path, destination: &Path, scratch: &Path) -> StoreResult<Value> {
    let held = crate::ownership::protected_file(source, false)?;
    if held.metadata()?.len() > MAX_BYTES as u64 {
        return Err(invalid("legacy package exceeds conversion budget"));
    }
    let mut db = Connection::open_with_flags(source, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    db.execute_batch("PRAGMA trusted_schema=OFF; PRAGMA query_only=ON;")?;
    let tx = db.transaction()?;
    let version: i64 = tx.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    if version != 0 {
        return Err(invalid("explicit v0.3 conversion requires schema v0"));
    }
    let check: String = tx.query_row("PRAGMA integrity_check", [], |r| r.get(0))?;
    if check != "ok" {
        return Err(invalid("legacy integrity check failed"));
    }
    // These old side tables lack enough typed provenance to establish safe modern
    // semantics. Do not silently drop source assets, proposals, or retry authority.
    for table in [
        "source_versions",
        "anchors",
        "blob_refs",
        "changesets",
        "changeset_versions",
        "approvals",
        "operation_receipts",
        "idempotency_keys",
    ] {
        let count: i64 =
            tx.query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r.get(0))?;
        if count != 0 {
            return Err(invalid("legacy package contains source/workflow data requiring an explicit external migration; original retained"));
        }
    }
    let universes: Vec<(String, String)> = tx
        .prepare("SELECT id,name FROM universes LIMIT 2")?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<Result<_, _>>()?;
    if universes.len() != 1 {
        return Err(invalid("legacy conversion requires exactly one universe"));
    }
    let (u, name) = &universes[0];
    let universe = UniverseId::parse(u).map_err(|_| invalid("legacy universe identity"))?;
    let manifest = ArchiveManifest {
        format: "universe-logical-v1".into(),
        universe: universe.clone(),
        name: name.clone(),
        complete: true,
        omitted_records: 0,
        includes_history: true,
        includes_workflow: false,
    };
    let mut rows = Vec::new();
    let mut records = BTreeMap::new();
    let mut stmt=tx.prepare("SELECT id,record_id,universe_id,kind,payload,digest FROM record_versions ORDER BY id LIMIT 100001")?;
    let mut query = stmt.query([])?;
    while let Some(r) = query.next()? {
        if records.len() >= 100_000 {
            return Err(invalid("legacy version budget exceeded"));
        }
        let id: String = r.get(0)?;
        let record: String = r.get(1)?;
        let source_u: String = r.get(2)?;
        let kind: String = r.get(3)?;
        let bytes: Vec<u8> = r.get(4)?;
        let old_digest: String = r.get(5)?;
        if source_u != *u || bytes.len() > 1_048_576 {
            return Err(invalid("legacy record scope or size"));
        }
        let payload: Payload = serde_json::from_slice(&bytes)
            .map_err(|_| invalid("legacy payload has no lossless typed v0.4 representation"))?;
        let record = RecordVersion::build(
            RecordVersionId::parse(&id).map_err(|_| invalid("legacy version identity"))?,
            RecordIdentity::new(
                universe.clone(),
                RecordId::parse(&record).map_err(|_| invalid("legacy record identity"))?,
                RecordKind::parse(&kind).map_err(|_| invalid("legacy kind"))?,
            ),
            payload,
        )
        .map_err(|_| invalid("legacy typed record"))?;
        if record.payload_digest.as_str() != old_digest {
            return Err(invalid("legacy payload digest mismatch"));
        }
        records.insert(id, record.clone());
        rows.push(Row::Record {
            record: Box::new(record),
        });
    }
    let identities: i64 =
        tx.query_row("SELECT count(*) FROM record_identities", [], |r| r.get(0))?;
    if identities as usize
        != records
            .values()
            .map(|r| &r.identity.record_id)
            .collect::<BTreeSet<_>>()
            .len()
    {
        return Err(invalid(
            "legacy identities without typed versions require explicit resolution",
        ));
    }
    let idmap = |prefix: &str, id: &str| {
        format!(
            "{prefix}{}",
            &hex::encode(Sha256::digest(format!("{u}:{id}").as_bytes()))[..24]
        )
    };
    let conts: Vec<(String, String, Option<String>)> = tx
        .prepare("SELECT id,head_commit,baseline_commit FROM continuities ORDER BY id LIMIT 1001")?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
        .collect::<Result<_, _>>()?;
    if conts.is_empty() || conts.len() > 1000 || conts.iter().any(|(_, _, b)| b.is_some()) {
        return Err(invalid("legacy conversion requires explicit non-inherited continuities; ambiguous baselines are not inferred"));
    }
    let continuities: BTreeMap<_, _> = conts
        .iter()
        .map(|(id, _, _)| {
            Ok((
                id.clone(),
                ContinuityId::parse(&idmap("cont_", id))
                    .map_err(|_| invalid("mapped continuity"))?,
            ))
        })
        .collect::<StoreResult<_>>()?;
    #[derive(Clone)]
    struct OldCommit {
        id: String,
        cont: String,
        parent: Option<String>,
        author: String,
        reason: String,
    }
    let commits:Vec<_>=tx.prepare("SELECT id,continuity_id,parent_id,author,reason FROM commits ORDER BY canon_revision,id LIMIT 10001")?.query_map([],|r|Ok(OldCommit{id:r.get(0)?,cont:r.get(1)?,parent:r.get(2)?,author:r.get(3)?,reason:r.get(4)?}))?.collect::<Result<_,_>>()?;
    if commits.is_empty() || commits.len() > 10_000 {
        return Err(invalid("legacy commit budget or missing history"));
    }
    let revisions: BTreeMap<_, _> = commits
        .iter()
        .map(|c| {
            Ok((
                c.id.clone(),
                RevisionId::parse(&idmap("rev_", &c.id)).map_err(|_| invalid("mapped revision"))?,
            ))
        })
        .collect::<StoreResult<_>>()?;
    let mut snapshots: BTreeMap<String, (i64, BTreeMap<String, String>)> = BTreeMap::new();
    let mut work = 0usize;
    while snapshots.len() < commits.len() {
        let before = snapshots.len();
        for c in &commits {
            if snapshots.contains_key(&c.id)
                || c.parent
                    .as_ref()
                    .is_some_and(|p| !snapshots.contains_key(p))
            {
                continue;
            }
            let (sequence, mut membership) = if let Some(parent) = &c.parent {
                let (seq, m) = &snapshots[parent];
                (*seq + 1, m.clone())
            } else {
                (0, BTreeMap::new())
            };
            let mapped_cont = continuities
                .get(&c.cont)
                .ok_or_else(|| invalid("legacy commit continuity missing"))?;
            if let Some(parent) = &c.parent {
                if commits
                    .iter()
                    .find(|x| x.id == *parent)
                    .is_none_or(|p| p.cont != c.cont)
                {
                    return Err(invalid(
                        "legacy cross-continuity parent requires explicit mapping",
                    ));
                }
            }
            let changes:Vec<(String,String,Option<String>)>=tx.prepare("SELECT record_id,action,version_id FROM commit_changes WHERE commit_id=?1 ORDER BY id LIMIT 10001")?.query_map([&c.id],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?)))?.collect::<Result<_,_>>()?;
            let mut touched = BTreeSet::new();
            for (rec, action, next) in changes {
                if !touched.insert(rec.clone()) {
                    return Err(invalid("legacy commit changes an identity twice"));
                }
                let prior = membership.get(&rec).cloned();
                if !matches!(
                    (action.as_str(), prior.is_some(), next.is_some()),
                    ("create", false, true) | ("replace", true, true) | ("tombstone", true, false)
                ) {
                    return Err(invalid("legacy change action does not match its history"));
                }
                if let Some(version) = &next {
                    if records
                        .get(version)
                        .is_none_or(|v| v.identity.record_id.as_str() != rec)
                    {
                        return Err(invalid("legacy change targets the wrong record version"));
                    }
                    membership.insert(rec.clone(), version.clone());
                } else {
                    membership.remove(&rec);
                }
                rows.push(Row::Change {
                    revision: revisions[&c.id].clone(),
                    record: RecordId::parse(&rec).map_err(|_| invalid("legacy change identity"))?,
                    prior: prior
                        .map(|id| RecordVersionId::parse(&id).map_err(|_| invalid("legacy prior")))
                        .transpose()?,
                    next: next
                        .map(|id| RecordVersionId::parse(&id).map_err(|_| invalid("legacy next")))
                        .transpose()?,
                });
            }
            rows.push(Row::Commit {
                id: revisions[&c.id].clone(),
                continuity: mapped_cont.clone(),
                parent: c.parent.as_ref().map(|p| revisions[p].clone()),
                sequence,
                principal: c.author.clone(),
                decision: format!("legacy-conversion:{}", c.id),
                reason: c.reason.clone(),
                digest: digest(&membership),
            });
            work += membership.len() + 1;
            if work > 1_000_000 {
                return Err(invalid("legacy replay work budget exceeded"));
            }
            snapshots.insert(c.id.clone(), (sequence, membership));
        }
        if snapshots.len() == before {
            return Err(invalid("legacy history contains a cycle or missing parent"));
        }
    }
    for (id, head, _) in &conts {
        if !snapshots.contains_key(head)
            || commits
                .iter()
                .find(|c| &c.id == head)
                .is_none_or(|c| &c.cont != id)
        {
            return Err(invalid("legacy head has no matching history"));
        }
        rows.push(Row::Continuity {
            id: continuities[id].clone(),
            head: revisions[head].clone(),
            baseline: None,
        });
    }
    // Existing world identities must be represented in typed historical canon.
    let worlds: Vec<(String, String)> = tx
        .prepare("SELECT id,name FROM worlds ORDER BY id LIMIT 10001")?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<Result<_, _>>()?;
    for (id, name) in worlds {
        let world = WorldId::parse(&id).map_err(|_| invalid("legacy world id"))?;
        let rec = world_record(&world);
        if !records.values().any(|r| {
            r.identity.record_id.as_str() == rec
                && matches!(&r.payload,Payload::World(w) if w.selector==name)
        }) {
            return Err(invalid(
                "legacy world lacks a typed canonical history; refusing to invent its admission",
            ));
        }
    }
    let mut reservations = BTreeMap::new();
    for record in records.values() {
        if let Payload::World(w) = &record.payload {
            let first = rows
                .iter()
                .find_map(|row| match row {
                    Row::Change {
                        revision,
                        record: id,
                        ..
                    } if id == &record.identity.record_id => Some(revision.clone()),
                    _ => None,
                })
                .ok_or_else(|| invalid("legacy world never admitted"))?;
            for name in std::iter::once(&w.selector).chain(w.aliases.iter()) {
                let key = selector_key(name)?;
                if reservations
                    .insert(key, (record.identity.record_id.clone(), first.clone()))
                    .is_some_and(|(id, _)| id != record.identity.record_id)
                {
                    return Err(invalid("legacy world names were rebound"));
                }
            }
        }
    }
    for (name, (record, revision)) in reservations {
        rows.push(Row::Reservation {
            name,
            record,
            revision,
        });
    }
    drop(query);
    drop(stmt);
    tx.commit()?;
    let archive = LogicalArchive {
        manifest,
        rows,
        package: None,
        digest: digest(&(&continuities, &revisions)),
    };
    // Full typed snapshot and historical validation before publishing an archive.
    let (kernel, temporary) = archive.stage(scratch, universe.clone(), name)?;
    kernel.export_logical(destination, &[])?;
    drop(kernel);
    drop(temporary);
    Ok(
        serde_json::json!({"converted":true,"canonical":false,"universe":universe,"continuity_mapping":continuities,"revision_mapping":revisions,"record_and_version_ids":"preserved","workflow_authority":"not imported","next_step":"Validate an import preview, then approve that exact preview. The original package is unchanged."}),
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn legacy_conversion_preserves_typed_history_and_original_and_rejects_ambiguous_sources() {
        let d = tempfile::tempdir().unwrap();
        let source = d.path().join("legacy.sqlite");
        crate::ownership::protected_file(&source, true).unwrap();
        let db = Connection::open(&source).unwrap();
        db.execute_batch(include_str!("schema_v0.sql")).unwrap();
        let u = "unv_000000000000000000000001";
        let id = "rec_000000000000000000000001";
        let ver = "ver_000000000000000000000001";
        let payload:Payload=serde_json::from_value(serde_json::json!({"record_kind":"represented_context","universe":u,"kind":{"kind":"objective"},"labels":{"en":"Objective"}})).unwrap();
        let record = RecordVersion::build(
            RecordVersionId::parse(ver).unwrap(),
            RecordIdentity::new(
                UniverseId::parse(u).unwrap(),
                RecordId::parse(id).unwrap(),
                payload.kind(),
            ),
            payload,
        )
        .unwrap();
        db.execute(
            "INSERT INTO universes(id,name,created_at) VALUES(?1,'Legacy','then')",
            [u],
        )
        .unwrap();
        db.execute("INSERT INTO record_identities(id,universe_id,kind,created_at) VALUES(?1,?2,'represented_context','then')",params![id,u]).unwrap();
        db.execute("INSERT INTO record_versions(id,record_id,universe_id,kind,payload,digest,created_at) VALUES(?1,?2,?3,'represented_context',?4,?5,'then')",params![ver,id,u,serde_json::to_vec(&record.payload).unwrap(),record.payload_digest.as_str()]).unwrap();
        db.execute("INSERT INTO commits(id,universe_id,continuity_id,author,reason,created_at) VALUES('commit_old',?1,'cont_main','author','Original genesis','then')",[u]).unwrap();
        db.execute(
            "INSERT INTO commit_changes VALUES('cc_old','commit_old',?1,'create',?2)",
            params![id, ver],
        )
        .unwrap();
        db.execute(
            "INSERT INTO continuities VALUES('cont_main',?1,'commit_old',NULL,'then','then')",
            [u],
        )
        .unwrap();
        drop(db);
        let before = std::fs::read(&source).unwrap();
        let archive = d.path().join("converted.sqlite");
        let report = convert_legacy(&source, &archive, d.path()).unwrap();
        assert_eq!(std::fs::read(&source).unwrap(), before);
        assert_eq!(report["canonical"], false);
        assert!(!report["revision_mapping"]["commit_old"].is_null());
        let converted = LogicalArchive::read(&archive).unwrap();
        let (kernel, _tmp) = converted
            .stage(d.path(), UniverseId::parse(u).unwrap(), "Restored")
            .unwrap();
        let cont: ContinuityId =
            serde_json::from_value(report["continuity_mapping"]["cont_main"].clone()).unwrap();
        assert_eq!(
            kernel.records(&cont, &kernel.head(&cont).unwrap()).unwrap(),
            vec![record]
        );
        assert!(convert_legacy(&source, &archive, d.path()).is_err());
        let db = Connection::open(&source).unwrap();
        db.execute("INSERT INTO source_versions VALUES('sv_old',?1,'missing source','digest','text/plain','then')",[u]).unwrap();
        drop(db);
        let rejected = d.path().join("rejected.sqlite");
        assert!(convert_legacy(&source, &rejected, d.path()).is_err());
        assert!(!rejected.exists());
    }
}
