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
                types: vec![],
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
    let backup = dir.path().join("backup.sqlite");
    k.backup(&backup).unwrap();
    let archive = dir.path().join("images.jsonl");
    k.export_logical(&archive, &[entity]).unwrap();
    // Recompute the archive checksum after removing a chunk: semantic validation
    // must still reject the archive, rather than trusting a valid envelope hash.
    use sha2::{Digest, Sha256};
    let mut damaged = Vec::new();
    let mut rows = 0usize;
    let mut removed = false;
    for line in std::fs::read_to_string(&archive).unwrap().lines() {
        let row: serde_json::Value = serde_json::from_str(line).unwrap();
        if row["entry"] == "checksum" {
            continue;
        }
        if row["entry"] == "image_chunk" && !removed {
            removed = true;
            continue;
        }
        damaged.extend_from_slice(line.as_bytes());
        damaged.push(b'\n');
        rows += 1;
    }
    assert!(removed);
    let hash = hex::encode(Sha256::digest(&damaged));
    damaged.extend(
        serde_json::to_vec(&serde_json::json!({"entry":"checksum","sha256":hash,"rows":rows}))
            .unwrap(),
    );
    damaged.push(b'\n');
    let broken = dir.path().join("broken.jsonl");
    use std::os::unix::fs::PermissionsExt;
    std::fs::write(&broken, damaged).unwrap();
    std::fs::set_permissions(&broken, std::fs::Permissions::from_mode(0o600)).unwrap();
    assert!(LogicalArchive::read(&broken)
        .unwrap()
        .stage(dir.path(), UniverseId::generate(&mut rand::rng()), "Broken")
        .is_err());
    let clone = UniverseId::generate(&mut rand::rng());
    let (recovered, _guard) = LogicalArchive::read(&archive)
        .unwrap()
        .stage(dir.path(), clone.clone(), "Clone")
        .unwrap();
    assert_eq!(recovered.image_bytes(&asset).unwrap(), bytes);
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
    conn.execute_batch("DROP TRIGGER workflow_entries_no_delete")
        .unwrap();
    conn.execute(
        "DELETE FROM workflow_entries WHERE key=?1",
        [format!("image-bytes:{}:0", asset.digest)],
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
