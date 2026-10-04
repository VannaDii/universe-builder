use sha2::Digest;
use std::collections::BTreeMap;
use universe_domain::{ids::*, records::*, scope::Validity, value::RecordRef};
use universe_store::{kernel::*, Database};
fn payload(u: &UniverseId, id: RecordId, payload: Payload) -> RecordVersion {
    RecordVersion::build(
        RecordVersionId::generate(&mut rand::rng()),
        RecordIdentity::new(u.clone(), id, payload.kind()),
        payload,
    )
    .unwrap()
}
#[test]
fn images_survive_source_removal_history_backup_filtered_export_and_clone() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("universe.sqlite");
    let u = UniverseId::generate(&mut rand::rng());
    let c = ContinuityId::generate(&mut rand::rng());
    let p = PrincipalId::generate(&mut rand::rng());
    let mut k = Kernel::create(&path, u.clone(), "Images", c.clone(), &p).unwrap();
    let source = dir.path().join("Original.png");
    // Incompressible-ish pixels exercise several 256 KiB chunks, without external fixtures.
    let image = image::RgbImage::from_fn(512, 512, |x, y| {
        let n = x
            .wrapping_mul(747796405)
            .wrapping_add(y.wrapping_mul(2891336453));
        image::Rgb([(n >> 3) as u8, (n >> 14) as u8, (n >> 23) as u8])
    });
    image.save(&source).unwrap();
    let bytes = std::fs::read(&source).unwrap();
    assert!(bytes.len() > 256 * 1024);
    let (asset_id, asset) = k.stage_image(&source).unwrap();
    std::fs::remove_file(&source).unwrap();
    assert_eq!(k.image_bytes(&asset).unwrap(), bytes);
    assert!(k
        .image_preview(&asset)
        .unwrap()
        .starts_with("data:image/jpeg;base64,"));
    let entity = RecordId::generate(&mut rand::rng());
    let appearance = RecordId::generate(&mut rand::rng());
    let reference = Appearance {
        target: AppearanceTarget::Entry {
            entry: RecordRef::new(u.clone(), entity.clone()),
        },
        label: "The brass instrument".into(),
        physical_description: "Patinated brass; three cobalt dials".into(),
        atmosphere: "A quiet, uneven ticking".into(),
        images: vec![AppearanceImage {
            asset: RecordRef::new(u.clone(), asset_id.clone()),
            caption: "The dial arrangement remains fixed".into(),
            purpose: ImagePurpose::Detail,
        }],
        links: vec![],
        validity: Validity::Unspecified,
    };
    let old = payload(
        &u,
        appearance.clone(),
        Payload::Appearance(reference.clone()),
    );
    let records = vec![
        payload(
            &u,
            entity.clone(),
            Payload::Entity(Entity {
                names: vec![],
                classification: None,
                classification_resolution:
                    universe_domain::records::ClassificationResolution::Unclassified,
                world_associations: vec![],
                labels: BTreeMap::new(),
                metadata: BTreeMap::new(),
            }),
        ),
        payload(&u, asset_id.clone(), Payload::ImageAsset(asset.clone())),
        old.clone(),
    ];
    let mut input = CommitInput {
        universe: u.clone(),
        continuity: c.clone(),
        expected_head: k.head(&c).unwrap(),
        principal: p,
        decision: "author test".into(),
        reason: "appearance".into(),
        idempotency_key: "first".into(),
        changes: records
            .into_iter()
            .map(|r| Assignment {
                record_id: r.identity.record_id.clone(),
                expected: None,
                next: Some(r),
            })
            .collect(),
    };
    let first = k.commit(&input).unwrap();
    let mut revised = reference;
    revised.physical_description = "Brass darkened after the fire".into();
    input.expected_head = first.clone();
    input.idempotency_key = "revision".into();
    input.changes = vec![Assignment {
        record_id: appearance.clone(),
        expected: Some(old.record_version_id.clone()),
        next: Some(payload(
            &u,
            appearance.clone(),
            Payload::Appearance(revised),
        )),
    }];
    let head = k.commit(&input).unwrap();
    let extra_source = "Uncommitted source — café 🌕
";
    let extra_hash = hex::encode(sha2::Sha256::digest(extra_source.as_bytes()));
    k.workflow_put(&[(
        format!("source:{extra_hash}"),
        serde_json::Value::String(extra_source.into()),
    )])
    .unwrap();
    let extra_image = dir.path().join("draft.png");
    image::RgbImage::new(2, 2).save(&extra_image).unwrap();
    let extra_bytes = std::fs::read(&extra_image).unwrap();
    let (_, extra_asset) = k.stage_image(&extra_image).unwrap();
    std::fs::remove_file(extra_image).unwrap();
    let backup = dir.path().join("backup.sqlite");
    k.backup(&backup).unwrap();
    let archive = dir.path().join("images.sqlite");
    k.export_logical(&archive, std::slice::from_ref(&entity))
        .unwrap();
    let full = dir.path().join("complete-history.sqlite");
    k.export_relational(&full, &[], true).unwrap();
    let inspect = std::process::Command::new("python3")
        .arg(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../scripts/inspect_relational_archive.py"
        ))
        .args([&full, &backup])
        .output()
        .unwrap();
    assert!(
        inspect.status.success(),
        "{}",
        String::from_utf8_lossy(&inspect.stderr)
    );
    let full_archive = LogicalArchive::read(&full).unwrap();
    for target in [u.clone(), UniverseId::generate(&mut rand::rng())] {
        let (restored, guard) = full_archive
            .stage(dir.path(), target, "Complete media")
            .unwrap();
        assert_eq!(restored.image_bytes(&asset).unwrap(), bytes);
        assert_eq!(restored.image_bytes(&extra_asset).unwrap(), extra_bytes);
        assert_eq!(
            restored
                .workflow_evidence_get(&format!("source:{extra_hash}"))
                .unwrap(),
            Some(serde_json::Value::String(extra_source.into()))
        );
        let path = guard.path().join("package.sqlite");
        drop(restored);
        let restarted = Kernel::open(&path).unwrap();
        assert_eq!(restarted.image_bytes(&extra_asset).unwrap(), extra_bytes);
        assert_eq!(restarted.image_bytes(&asset).unwrap(), bytes);
    }
    // Recompute the archive checksum after removing a chunk: semantic validation
    // must still reject the archive, rather than trusting a valid envelope hash.
    let broken = dir.path().join("broken.sqlite");
    std::fs::copy(&archive, &broken).unwrap();
    let damaged = rusqlite::Connection::open(&broken).unwrap();
    damaged.execute_batch("DROP TRIGGER media_chunk_no_delete; DELETE FROM media_chunk WHERE ordinal=0; CREATE TRIGGER media_chunk_no_delete BEFORE DELETE ON media_chunk BEGIN SELECT RAISE(ABORT,'immutable workflow content'); END;").unwrap();
    drop(damaged);
    let hash = std::process::Command::new("python3")
        .arg(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../scripts/relational_archive_test_fixture.py"
        ))
        .arg("rehash")
        .arg(&broken)
        .output()
        .unwrap();
    assert!(
        hash.status.success(),
        "{}",
        String::from_utf8_lossy(&hash.stderr)
    );
    assert!(LogicalArchive::read(&broken).is_err());
    // A correctly rehashed typed body with a dangling semantic reference still fails.
    let dangling = dir.path().join("dangling.sqlite");
    std::fs::copy(&archive, &dangling).unwrap();
    let damaged = rusqlite::Connection::open(&dangling).unwrap();
    let trigger: String = damaged
        .query_row(
            "SELECT sql FROM sqlite_master WHERE name='r_record_ref_no_update'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    damaged
        .execute_batch("DROP TRIGGER r_record_ref_no_update")
        .unwrap();
    assert!(
        damaged
            .execute(
                "UPDATE r_record_ref SET record='rec_ffffffffffffffffffffffff' WHERE record=?1",
                [entity.as_str()]
            )
            .unwrap()
            > 0
    );
    damaged.execute_batch(&trigger).unwrap();
    drop(damaged);
    let rewrite = std::process::Command::new("python3")
        .arg(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../scripts/relational_archive_test_fixture.py"
        ))
        .arg("redigest")
        .arg(&dangling)
        .output()
        .unwrap();
    assert!(
        rewrite.status.success(),
        "{}",
        String::from_utf8_lossy(&rewrite.stderr)
    );
    assert!(LogicalArchive::read(&dangling).is_err());
    let clone = UniverseId::generate(&mut rand::rng());
    let (recovered, _guard) = LogicalArchive::read(&archive)
        .unwrap()
        .stage(dir.path(), clone.clone(), "Clone")
        .unwrap();
    assert_eq!(recovered.image_bytes(&asset).unwrap(), bytes);
    assert!(recovered
        .workflow_get(&format!("source:{extra_hash}"))
        .unwrap()
        .is_none());
    assert!(recovered.image_bytes(&extra_asset).is_err());
    assert!(recovered.records(&c,&first).unwrap().iter().any(|r|matches!(&r.payload,Payload::Appearance(a) if a.physical_description=="Patinated brass; three cobalt dials")));
    let restored = Kernel::open(&backup).unwrap();
    assert_eq!(restored.head(&c).unwrap(), head);
    assert_eq!(restored.image_bytes(&asset).unwrap(), bytes);
    drop(k);
    let restarted = Kernel::open(&path).unwrap();
    assert_eq!(restarted.image_bytes(&asset).unwrap(), bytes);
    drop(restarted);
    // A checksummed workflow table alone cannot hide a missing original chunk.
    let db = Database::open_existing(&path).unwrap();
    let conn = db.connect().unwrap();
    conn.execute_batch("DROP TRIGGER media_chunk_no_delete")
        .unwrap();
    conn.execute(
        "DELETE FROM media_chunk WHERE digest=?1 AND ordinal=0",
        [&asset.digest],
    )
    .unwrap();
    drop(conn);
    assert!(Kernel::open(&path).is_err());
}
#[test]
fn rejects_non_images_oversized_inputs_and_missing_or_forged_assets() {
    let d = tempfile::tempdir().unwrap();
    let u = UniverseId::generate(&mut rand::rng());
    let c = ContinuityId::generate(&mut rand::rng());
    let p = PrincipalId::generate(&mut rand::rng());
    let mut k = Kernel::create(
        &d.path().join("u.sqlite"),
        u.clone(),
        "Images",
        c.clone(),
        &p,
    )
    .unwrap();
    let source = d.path().join("fake.png");
    std::fs::write(&source, b"<svg><script>alert(1)</script></svg>").unwrap();
    assert!(k.stage_image(&source).is_err());
    let file = std::fs::File::create(&source).unwrap();
    file.set_len(MAX_IMAGE_BYTES as u64 + 1).unwrap();
    assert!(k.stage_image(&source).is_err());
    image::RgbImage::new(2, 2).save(&source).unwrap();
    let alias = d.path().join("alias.png");
    std::os::unix::fs::symlink(&source, &alias).unwrap();
    assert!(k.stage_image(&alias).is_err());
    assert!(k.stage_image(d.path()).is_err());
    let (id, mut a) = k.stage_image(&source).unwrap();
    a.digest = "a".repeat(64);
    assert!(k.image_bytes(&a).is_err());
    let r = payload(&u, id.clone(), Payload::ImageAsset(a));
    let input = CommitInput {
        universe: u,
        continuity: c.clone(),
        expected_head: k.head(&c).unwrap(),
        principal: p,
        decision: "test".into(),
        reason: "test".into(),
        idempotency_key: "missing".into(),
        changes: vec![Assignment {
            record_id: id,
            expected: None,
            next: Some(r),
        }],
    };
    assert!(k.commit(&input).is_err());
}
