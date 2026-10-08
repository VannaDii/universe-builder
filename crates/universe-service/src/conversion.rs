//! Explicit offline conversion of installation authority and protected credentials.
use rusqlite::{params, OptionalExtension};
use sha2::{Digest, Sha256};
use std::os::unix::fs::PermissionsExt;
use std::{fs::File, path::Path};
use universe_domain::ids::*;
use universe_protocol::installation::GrantLimits;
use universe_store::{kernel::operator_conversion as io, ownership::private_dir};

#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyCredential {
    format_version: u32,
    profile_id: ProfileId,
    credential: String,
}
fn credential(path: &Path) -> anyhow::Result<LegacyCredential> {
    use std::io::Read;
    let f = io::read_original(path)?;
    anyhow::ensure!(
        f.metadata()?.len() <= 4096,
        "credential file exceeds 4096 bytes"
    );
    let mut bytes = Vec::new();
    f.take(4097).read_to_end(&mut bytes)?;
    let value: LegacyCredential = serde_json::from_slice(&bytes)
        .map_err(|_| anyhow::anyhow!("invalid protected credential; repair original copy"))?;
    anyhow::ensure!(
        value.format_version == 1 && !value.credential.is_empty(),
        "unsupported credential input"
    );
    Ok(value)
}
pub fn convert_credential(source: &Path, destination: &Path) -> anyhow::Result<serde_json::Value> {
    anyhow::ensure!(!destination.exists(), "destination already exists");
    let parent = private_dir(
        destination
            .parent()
            .ok_or_else(|| anyhow::anyhow!("parent required"))?,
    )?;
    let hash = io::original_hash(source)?;
    let value = credential(source)?;
    let temp = tempfile::Builder::new()
        .prefix(".credential-conversion-")
        .tempdir_in(&parent)?;
    std::fs::set_permissions(temp.path(), std::fs::Permissions::from_mode(0o700))?;
    universe_store::credentials::write(temp.path(), &value.profile_id, &value.credential)?;
    let converted = universe_store::credentials::read(temp.path(), &value.profile_id)?;
    anyhow::ensure!(
        converted == value.credential,
        "credential whole-data comparison failed"
    );
    anyhow::ensure!(
        io::original_hash(source)? == hash,
        "credential source changed"
    );
    io::publish_file(
        &temp
            .path()
            .join(format!("profiles/{}.sqlite", value.profile_id)),
        destination,
    )?;
    Ok(
        serde_json::json!({"source_sha256":hash,"original_preserved":true,"credential_verified":true}),
    )
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallationPoint {
    Rows,
    Audited,
    BeforePublish,
}
pub fn convert_installation(
    source: &Path,
    destination: &Path,
) -> anyhow::Result<serde_json::Value> {
    convert_installation_with_hook(source, destination, |_| Ok(()))
}
pub fn convert_installation_with_hook(
    source: &Path,
    destination: &Path,
    mut hook: impl FnMut(InstallationPoint) -> anyhow::Result<()>,
) -> anyhow::Result<serde_json::Value> {
    anyhow::ensure!(
        !destination.exists(),
        "destination already exists; use a fresh private directory"
    );
    let parent = private_dir(
        destination
            .parent()
            .ok_or_else(|| anyhow::anyhow!("destination parent required"))?,
    )?;
    // The source directory itself must already be private; do not create it.
    anyhow::ensure!(source.is_dir(), "source installation directory missing");
    private_dir(source)?;
    anyhow::ensure!(
        source.join("profiles").is_dir(),
        "source profiles directory missing"
    );
    private_dir(&source.join("profiles"))?;
    let source_db = source.join("installation.sqlite");
    let hash = io::original_hash(&source_db)?;
    let input = io::open_original(&source_db)?;
    let scalars = [
        "settings",
        "profiles",
        "catalog",
        "aliases",
        "purge_pending",
        "audit",
    ];
    let mut allowed = scalars.to_vec();
    allowed.extend(["grants", "grant_limits", "import_preview"]);
    io::check_inventory(&input, &allowed)?;
    anyhow::ensure!(
        io::columns(&input, "grants")?
            == [
                "profile",
                "universe",
                "worlds",
                "propose",
                "edit",
                "protected"
            ],
        "unsupported grant columns; no evidence omitted"
    );
    anyhow::ensure!(
        io::columns(&input, "grant_limits")? == ["profile", "universe", "limits"],
        "unsupported grant-limit columns; no evidence omitted"
    );
    let invalid_flags:i64=input.query_row("SELECT count(*) FROM grants WHERE propose NOT IN (0,1) OR edit NOT IN (0,1) OR protected NOT IN (0,1) OR propose IS NULL OR edit IS NULL OR protected IS NULL",[],|r|r.get(0))?;
    anyhow::ensure!(
        invalid_flags == 0,
        "invalid legacy grant flags; repair a copy rather than coerce authority"
    );
    let purges: i64 = input.query_row("SELECT count(*) FROM purge_pending", [], |r| r.get(0))?;
    anyhow::ensure!(
        purges == 0,
        "pending purge requires operator recovery before conversion; no deletion performed"
    );
    if !io::columns(&input, "import_preview")?.is_empty() {
        let count: i64 =
            input.query_row("SELECT count(*) FROM import_preview", [], |r| r.get(0))?;
        anyhow::ensure!(count==0,"legacy import previews require explicit restaging from retained archives; no preview omitted");
    }
    let temp = tempfile::Builder::new()
        .prefix(".installation-conversion-")
        .tempdir_in(parent)?;
    std::fs::set_permissions(temp.path(), std::fs::Permissions::from_mode(0o700))?;
    let root = temp.path().join("target");
    private_dir(&root)?;
    private_dir(&root.join("profiles"))?;
    private_dir(&root.join("packages"))?;
    let target_path = root.join("installation.sqlite");
    universe_store::ownership::protected_file(&target_path, true)?;
    let mut target = rusqlite::Connection::open(&target_path)?;
    target.execute_batch(include_str!(
        "../../../docs/decisions/relational-storage/installation.sql"
    ))?;
    target.execute_batch("PRAGMA synchronous=FULL;")?;
    let tx = target.transaction()?;
    tx.execute_batch("PRAGMA defer_foreign_keys=ON;")?;
    for table in scalars {
        io::copy_scalar_table(&input, &tx, table)?;
    }
    let profiles: Vec<(String, String)> = input
        .prepare("SELECT id,hash FROM profiles ORDER BY id")?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<Result<_, _>>()?;
    // Inventory all credentials, including unenrolled files left by interrupted enrollment.
    let mut credential_hashes = Vec::new();
    for entry in std::fs::read_dir(source.join("profiles"))? {
        let path = entry?.path();
        anyhow::ensure!(
            path.extension().and_then(|s| s.to_str()) == Some("json"),
            "unsupported profile file; retain source and repair a copy"
        );
        let original_hash = io::original_hash(&path)?;
        let value = credential(&path)?;
        anyhow::ensure!(
            path.file_stem().and_then(|s| s.to_str()) == Some(value.profile_id.as_str()),
            "credential filename identity mismatch"
        );
        if let Some((_, expected)) = profiles
            .iter()
            .find(|(id, _)| id == value.profile_id.as_str())
        {
            anyhow::ensure!(
                hex::encode(Sha256::digest(value.credential.as_bytes())) == *expected,
                "credential does not match enrolled hash; original retained"
            );
        }
        universe_store::credentials::write(&root, &value.profile_id, &value.credential)?;
        anyhow::ensure!(
            universe_store::credentials::read(&root, &value.profile_id)? == value.credential,
            "exact credential comparison failed"
        );
        credential_hashes.push((path, value.profile_id, original_hash));
    }
    for (profile, _) in &profiles {
        ProfileId::parse(profile)?;
        anyhow::ensure!(
            credential_hashes
                .iter()
                .any(|(_, id, _)| id.as_str() == profile),
            "enrolled profile {profile} has no recoverable credential; original retained"
        );
    }
    let grants:Vec<(String,String,Option<String>,bool,bool,bool)>=input.prepare("SELECT profile,universe,worlds,propose,edit,protected FROM grants ORDER BY profile,universe")?.query_map([],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?,r.get(4)?,r.get(5)?)))?.collect::<Result<_,_>>()?;
    for (profile, universe, worlds, propose, edit, protected) in &grants {
        ProfileId::parse(profile)?;
        UniverseId::parse(universe)?;
        let worlds: Option<Vec<WorldId>> = worlds
            .as_ref()
            .map(|s| serde_json::from_str(s))
            .transpose()?;
        let limits: Option<String> = input
            .query_row(
                "SELECT limits FROM grant_limits WHERE profile=?1 AND universe=?2",
                params![profile, universe],
                |r| r.get(0),
            )
            .optional()?;
        let limits: GrantLimits = limits
            .map(|s| serde_json::from_str(&s))
            .transpose()?
            .unwrap_or_default();
        let state = |listed: bool| if listed { "listed" } else { "all" };
        tx.execute(
            "INSERT INTO grants VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
            params![
                profile,
                universe,
                state(worlds.is_some()),
                propose,
                edit,
                protected,
                state(limits.entities.is_some()),
                state(limits.predicates.is_some()),
                state(limits.continuities.is_some()),
                limits.expires_at.map(|s| s.to_string()),
                limits.delegated_commit,
                limits.allow_shared
            ],
        )?;
        for (table, values) in [
            (
                "grant_worlds",
                worlds.map(|v| v.into_iter().map(|i| i.to_string()).collect::<Vec<_>>()),
            ),
            (
                "grant_entities",
                limits
                    .entities
                    .map(|v| v.into_iter().map(|i| i.to_string()).collect()),
            ),
            (
                "grant_predicates",
                limits
                    .predicates
                    .map(|v| v.into_iter().map(|i| i.to_string()).collect()),
            ),
            (
                "grant_continuities",
                limits
                    .continuities
                    .map(|v| v.into_iter().map(|i| i.to_string()).collect()),
            ),
        ] {
            for (ordinal, id) in values.unwrap_or_default().iter().enumerate() {
                tx.execute(
                    &format!("INSERT INTO {table} VALUES(?,?,?,?)"),
                    params![profile, universe, ordinal as i64, id],
                )?;
            }
        }
        hook(InstallationPoint::Rows)?;
    }
    let orphan_limits:i64=input.query_row("SELECT count(*) FROM grant_limits l WHERE NOT EXISTS(SELECT 1 FROM grants g WHERE g.profile=l.profile AND g.universe=l.universe)",[],|r|r.get(0))?;
    anyhow::ensure!(orphan_limits == 0, "orphan grant limits; repair a copy");
    tx.commit()?;
    for table in scalars {
        io::compare_scalar_table(&input, &target, table)?;
    }
    // Use the ordinary independent installation reader, not the insert mapping.
    let registry = crate::registry::Registry::open(&root)?;
    for (profile, universe, worlds, propose, edit, protected) in &grants {
        let expected_worlds: Option<Vec<WorldId>> = worlds
            .as_ref()
            .map(|s| serde_json::from_str(s))
            .transpose()?;
        let original_limits: Option<String> = input
            .query_row(
                "SELECT limits FROM grant_limits WHERE profile=?1 AND universe=?2",
                params![profile, universe],
                |r| r.get(0),
            )
            .optional()?;
        let expected_limits: GrantLimits = original_limits
            .map(|s| serde_json::from_str(&s))
            .transpose()?
            .unwrap_or_default();
        let actual =
            registry.read_grant(&ProfileId::parse(profile)?, &UniverseId::parse(universe)?)?;
        anyhow::ensure!(
            actual.worlds == expected_worlds
                && actual.propose == *propose
                && actual.edit == *edit
                && actual.protected == *protected
                && serde_json::to_value(&actual.limits)? == serde_json::to_value(expected_limits)?,
            "whole-grant comparison failed"
        );
    }
    drop(registry);
    hook(InstallationPoint::Audited)?;
    target.execute_batch("PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;")?;
    let fk: i64 = target.query_row("SELECT count(*) FROM pragma_foreign_key_check", [], |r| {
        r.get(0)
    })?;
    anyhow::ensure!(fk == 0, "installation foreign key audit failed");
    drop(target);
    anyhow::ensure!(
        io::original_hash(&source_db)? == hash,
        "installation source changed"
    );
    for (path, _, original) in &credential_hashes {
        anyhow::ensure!(
            io::original_hash(path)? == *original,
            "credential source changed"
        );
    }
    File::open(&target_path)?.sync_all()?;
    File::open(root.join("profiles"))?.sync_all()?;
    File::open(&root)?.sync_all()?;
    hook(InstallationPoint::BeforePublish)?;
    io::verify_original_database(&source_db, &hash)?;
    let current_paths = std::fs::read_dir(source.join("profiles"))?
        .map(|entry| entry.map(|e| e.path()))
        .collect::<Result<std::collections::BTreeSet<_>, _>>()?;
    let expected_paths = credential_hashes
        .iter()
        .map(|(path, _, _)| path.clone())
        .collect::<std::collections::BTreeSet<_>>();
    anyhow::ensure!(
        current_paths == expected_paths,
        "source credential inventory changed; retry from an offline snapshot"
    );
    for (path, _, original) in &credential_hashes {
        anyhow::ensure!(
            io::original_hash(path)? == *original,
            "credential source changed before publication"
        );
    }

    // renameatx_np/renameat2 provides atomic directory publication without replacing
    // any destination created concurrently. No live installation cutover occurs.
    universe_store::kernel::operator_conversion::publish_directory(&root, destination)?;
    Ok(
        serde_json::json!({"source_sha256":hash,"profiles":profiles.len(),"credentials":credential_hashes.len(),"grants":grants.len(),"compared_tables":scalars.len(),"original_preserved":true,"catalog_paths_preserved":true}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    fn id(prefix: &str, n: u64) -> String {
        format!("{prefix}_{n:024x}")
    }
    fn fixture(parent: &Path) -> std::path::PathBuf {
        let root = parent.join("legacy-installation");
        private_dir(&root).unwrap();
        private_dir(&root.join("profiles")).unwrap();
        let path = root.join("installation.sqlite");
        universe_store::ownership::protected_file(&path, true).unwrap();
        let c = rusqlite::Connection::open(&path).unwrap();
        c.execute_batch("CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL); CREATE TABLE profiles(id TEXT PRIMARY KEY,hash TEXT NOT NULL,author INTEGER NOT NULL,revoked INTEGER NOT NULL); CREATE TABLE catalog(id TEXT PRIMARY KEY,name TEXT NOT NULL,path TEXT NOT NULL,device TEXT NOT NULL,inode TEXT NOT NULL); CREATE TABLE aliases(key TEXT PRIMARY KEY,universe TEXT NOT NULL); CREATE TABLE grants(profile TEXT,universe TEXT,worlds TEXT,propose INTEGER,edit INTEGER,protected INTEGER); CREATE TABLE grant_limits(profile TEXT,universe TEXT,limits TEXT); CREATE TABLE purge_pending(universe TEXT,path TEXT,device TEXT,inode TEXT); CREATE TABLE audit(sequence INTEGER PRIMARY KEY,actor TEXT,action TEXT,target TEXT);").unwrap();
        c.execute(
            "INSERT INTO settings VALUES('normalization',?1)",
            [universe_store::selector::NORMALIZATION_VERSION],
        )
        .unwrap();
        c.execute(
            "INSERT INTO catalog VALUES(?1,'Universe','/retained/original.sqlite','123','456')",
            [id("unv", 1)],
        )
        .unwrap();
        c.execute("INSERT INTO aliases VALUES('universe',?1)", [id("unv", 1)])
            .unwrap();
        for n in 1..=3 {
            let profile = id("prf", n);
            let secret = format!("Synthetic credential café {n}\n");
            if n != 3 {
                c.execute(
                    "INSERT INTO profiles VALUES(?1,?2,?3,?4)",
                    params![
                        profile,
                        hex::encode(Sha256::digest(secret.as_bytes())),
                        n == 1,
                        n == 2
                    ],
                )
                .unwrap();
            }
            let path = root.join(format!("profiles/{profile}.json"));
            std::fs::write(&path,serde_json::to_vec(&serde_json::json!({"format_version":1,"profile_id":profile,"credential":secret})).unwrap()).unwrap();
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
        }
        c.execute(
            "INSERT INTO grants VALUES(?1,?2,?3,1,1,0)",
            params![
                id("prf", 2),
                id("unv", 1),
                serde_json::to_string(&vec![id("wld", 2), id("wld", 1)]).unwrap()
            ],
        )
        .unwrap();
        let limits = serde_json::json!({"entities":[id("rec",2),id("rec",1)],"predicates":[],"continuities":null,"expires_at":42,"delegated_commit":false,"allow_shared":true});
        c.execute(
            "INSERT INTO grant_limits VALUES(?1,?2,?3)",
            params![id("prf", 2), id("unv", 1), limits.to_string()],
        )
        .unwrap();
        c.execute(
            "INSERT INTO audit VALUES(7,?1,'revoke',?2)",
            params![id("prf", 1), id("prf", 2)],
        )
        .unwrap();
        drop(c);
        root
    }
    fn originals(root: &Path) -> Vec<(std::path::PathBuf, Vec<u8>)> {
        let mut paths = vec![root.join("installation.sqlite")];
        paths.extend(
            std::fs::read_dir(root.join("profiles"))
                .unwrap()
                .map(|e| e.unwrap().path()),
        );
        paths.sort();
        paths
            .into_iter()
            .map(|p| {
                let b = std::fs::read(&p).unwrap();
                (p, b)
            })
            .collect()
    }
    #[test]
    fn preserves_installation_authority_credentials_revocation_and_orphans() {
        let d = tempfile::tempdir().unwrap();
        std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        let source = fixture(d.path());
        let bytes = originals(&source);
        let dest = d.path().join("converted");
        let report = convert_installation(&source, &dest).unwrap();
        assert_eq!(report["credentials"], 3);
        assert_eq!(report["profiles"], 2);
        for (p, b) in &bytes {
            assert_eq!(std::fs::read(p).unwrap(), *b);
        }
        let input = io::open_original(&source.join("installation.sqlite")).unwrap();
        let output = io::open_original(&dest.join("installation.sqlite")).unwrap();
        for table in [
            "settings",
            "profiles",
            "catalog",
            "aliases",
            "audit",
            "purge_pending",
        ] {
            io::compare_scalar_table(&input, &output, table).unwrap();
        }
        for n in 1..=3 {
            assert!(
                universe_store::credentials::read(&dest, &ProfileId::parse(&id("prf", n)).unwrap())
                    .unwrap()
                    == format!("Synthetic credential café {n}\n")
            );
        }
        assert_eq!(
            std::fs::metadata(dest.join("installation.sqlite"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
        assert!(convert_installation(&source, &dest).is_err());
        convert_installation(&source, &d.path().join("retry")).unwrap();
    }
    #[test]
    fn installation_interruptions_and_startup_preserve_originals() {
        let d = tempfile::tempdir().unwrap();
        std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        let source = fixture(d.path());
        let bytes = originals(&source);
        assert!(crate::registry::Registry::open(&source).is_err());
        for point in [
            InstallationPoint::Rows,
            InstallationPoint::Audited,
            InstallationPoint::BeforePublish,
        ] {
            let dest = d.path().join(format!("{point:?}"));
            assert!(convert_installation_with_hook(&source, &dest, |p| {
                anyhow::ensure!(p != point, "interrupted");
                Ok(())
            })
            .is_err());
            assert!(!dest.exists());
            for (p, b) in &bytes {
                assert_eq!(std::fs::read(p).unwrap(), *b);
            }
            convert_installation(&source, &dest).unwrap();
        }
    }
    #[test]
    fn missing_mismatching_credentials_and_pending_work_block_all_publication() {
        for failure in ["missing", "hash", "purge", "orphan-limits", "invalid-flags"] {
            let d = tempfile::tempdir().unwrap();
            std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
            let source = fixture(d.path());
            let c = rusqlite::Connection::open(source.join("installation.sqlite")).unwrap();
            match failure {
                "missing" => {
                    std::fs::remove_file(source.join(format!("profiles/{}.json", id("prf", 1))))
                        .unwrap()
                }
                "hash" => {
                    c.execute("UPDATE profiles SET hash='incorrect'", [])
                        .unwrap();
                }
                "purge" => {
                    c.execute("INSERT INTO purge_pending VALUES('u','p','d','i')", [])
                        .unwrap();
                }
                "invalid-flags" => {
                    c.execute("UPDATE grants SET edit=2", []).unwrap();
                }
                "orphan-limits" => {
                    c.execute(
                        "INSERT INTO grant_limits VALUES('orphan','universe','{}')",
                        [],
                    )
                    .unwrap();
                }
                _ => unreachable!(),
            }
            drop(c);
            let bytes = originals(&source);
            let dest = d.path().join("bad");
            assert!(convert_installation(&source, &dest).is_err(), "{failure}");
            assert!(!dest.exists());
            for (p, b) in bytes {
                assert_eq!(std::fs::read(p).unwrap(), b);
            }
        }
    }
    #[test]
    fn process_termination_worker() {
        let Ok(root) = std::env::var("UNIVERSE_INSTALLATION_KILL_ROOT") else {
            return;
        };
        let point = std::env::var("UNIVERSE_INSTALLATION_KILL_POINT").unwrap();
        let root = std::path::PathBuf::from(root);
        let _ = convert_installation_with_hook(
            &root.join("legacy-installation"),
            &root.join("killed"),
            |p| {
                if format!("{p:?}") == point {
                    std::process::abort();
                }
                Ok(())
            },
        );
        panic!("worker did not terminate");
    }
    #[test]
    fn abrupt_process_termination_and_retry_preserve_original_installation() {
        use std::os::unix::process::ExitStatusExt;
        for point in ["Rows", "Audited", "BeforePublish"] {
            let d = tempfile::tempdir().unwrap();
            std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
            let source = fixture(d.path());
            let before = originals(&source);
            let status = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "conversion::tests::process_termination_worker",
                    "--nocapture",
                ])
                .env("UNIVERSE_INSTALLATION_KILL_ROOT", d.path())
                .env("UNIVERSE_INSTALLATION_KILL_POINT", point)
                .status()
                .unwrap();
            assert!(status.signal().is_some());
            assert!(!d.path().join("killed").exists());
            for (path, bytes) in before {
                assert_eq!(std::fs::read(path).unwrap(), bytes);
            }
            convert_installation(&source, &d.path().join("retry")).unwrap();
        }
    }
    #[test]
    fn directory_publication_race_is_no_clobber() {
        let d = tempfile::tempdir().unwrap();
        std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        let source = fixture(d.path());
        let dest = d.path().join("race");
        assert!(convert_installation_with_hook(&source, &dest, |p| {
            if p == InstallationPoint::BeforePublish {
                std::fs::create_dir(&dest)?;
                std::fs::write(dest.join("retained"), b"other operator")?;
            }
            Ok(())
        })
        .is_err());
        assert_eq!(
            std::fs::read(dest.join("retained")).unwrap(),
            b"other operator"
        );
    }
    #[test]
    fn standalone_credential_is_exact_private_and_never_replaces() {
        let d = tempfile::tempdir().unwrap();
        std::fs::set_permissions(d.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        let source = fixture(d.path());
        let file = source.join(format!("profiles/{}.json", id("prf", 1)));
        let bytes = std::fs::read(&file).unwrap();
        let dest = d.path().join("profile.sqlite");
        convert_credential(&file, &dest).unwrap();
        let c = io::open_original(&dest).unwrap();
        let (profile, secret): (String, String) = c
            .query_row("SELECT profile_id,credential FROM credential", [], |r| {
                Ok((r.get(0)?, r.get(1)?))
            })
            .unwrap();
        assert_eq!(profile, id("prf", 1));
        assert!(secret == "Synthetic credential café 1\n");
        assert!(convert_credential(&file, &dest).is_err());
        assert_eq!(std::fs::read(file).unwrap(), bytes);
    }
}
