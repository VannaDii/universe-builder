//! Real socket tests; credentials stay inside protected temporary installations.
use serde_json::json;
use std::{collections::BTreeSet, path::Path, time::Duration};
use tokio_util::sync::CancellationToken;
use universe_client::installation::EngineClient;
use universe_domain::ids::*;
use universe_protocol::{installation::*, Request};
use universe_service::{registry::Registry, runtime};
fn describe(name: &str) -> EngineRequest {
    EngineRequest::Tool {
        request: Box::new(
            serde_json::from_value::<Request>(
                json!({"tool":"universe_describe","args":{"mode":"summary","universe":name}}),
            )
            .unwrap(),
        ),
    }
}
async fn connect(root: &Path, p: &ProfileId, name: &str) -> EngineClient {
    for _ in 0..100 {
        if let Ok(c) = EngineClient::connect(root, p, name).await {
            return c;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("engine did not become ready")
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn shared_engine_authentication_catalog_revocation_and_restart() {
    let d = tempfile::tempdir().unwrap();
    let root = d.path().join("installation");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let r = root.clone();
    let s = stop.clone();
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut desktop = connect(&root, &author, "desktop").await;
    let first = desktop.welcome.service_instance.clone();
    let u = desktop
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Straße".into(),
        })
        .await
        .unwrap();
    let uid: UniverseId = serde_json::from_value(u["universe_id"].clone()).unwrap();
    let agent: ProfileId = serde_json::from_value(
        desktop.call(EngineRequest::Enroll).await.unwrap()["profile_id"].clone(),
    )
    .unwrap();
    let mut mcp = connect(&root, &agent, "author administrative desktop").await;
    assert_eq!(mcp.welcome.service_instance, first);
    assert!(!mcp.welcome.author);
    let mut idle_agents = Vec::new();
    for _ in 0..7 {
        idle_agents.push(connect(&root, &agent, "idle agent").await);
    }
    assert!(EngineClient::connect(&root, &agent, "ninth connection")
        .await
        .is_err());
    assert!(desktop.call(EngineRequest::Status).await.is_ok());
    drop(idle_agents);
    assert!(mcp
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None
            },
            name: "forbidden".into()
        })
        .await
        .is_err());
    assert!(mcp.call(describe("STRASSE")).await.is_err());
    assert_eq!(
        mcp.call(EngineRequest::Status).await.unwrap()["universes"],
        json!([])
    );
    let grant = GrantSpec {
        profile_id: agent.clone(),
        universe_id: uid.clone(),
        worlds: None,
        propose: true,
        edit: false,
        protected: false,
        limits: Default::default(),
    };
    desktop.call(EngineRequest::Grant { grant }).await.unwrap();
    let summary = mcp.call(describe("STRASSE")).await.unwrap();
    assert_eq!(summary["universe_id"], u["universe_id"]);
    desktop
        .call(EngineRequest::RenameUniverse {
            universe_id: uid.clone(),
            name: "New Name".into(),
        })
        .await
        .unwrap();
    assert_eq!(
        mcp.call(describe("Straße")).await.unwrap()["universe"],
        "New Name"
    );
    // Alias collision rolls back the catalog, preserving the original identity.
    assert!(desktop
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None
            },
            name: "STRASSE".into()
        })
        .await
        .is_err());
    assert_eq!(
        desktop.call(EngineRequest::Status).await.unwrap()["universes"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    let doctor = desktop.call(EngineRequest::Doctor).await.unwrap();
    assert_eq!(doctor["packages"][0]["storage"]["journal_mode"], "wal");
    assert_eq!(doctor["packages"][0]["storage"]["synchronous"], 2);
    assert!(mcp.call(EngineRequest::Doctor).await.is_err());
    // Desktop disconnect does not own the engine's lifetime.
    drop(desktop);
    assert_eq!(
        mcp.call(EngineRequest::Status).await.unwrap()["service_instance"],
        first
    );
    let mut admin = connect(&root, &author, "maintenance").await;
    admin
        .call(EngineRequest::Revoke {
            profile_id: agent.clone(),
        })
        .await
        .unwrap();
    assert!(mcp.call(describe("New Name")).await.is_err());
    assert!(EngineClient::connect(&root, &agent, "author")
        .await
        .is_err());
    assert!(runtime::serve(&root, CancellationToken::new())
        .await
        .is_err());
    drop(admin);
    drop(mcp);
    stop.cancel();
    server.await.unwrap().unwrap();
    let stop = CancellationToken::new();
    let r = root.clone();
    let s = stop.clone();
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut admin = connect(&root, &author, "desktop").await;
    assert_ne!(admin.welcome.service_instance, first);
    assert_eq!(
        admin.call(describe("STRASSE")).await.unwrap()["universe_id"],
        u["universe_id"]
    );
    // Missing packages remain visible to the author as failed diagnostics.
    let path = root
        .join("packages")
        .join(format!("{}.sqlite", uid.as_str()));
    let moved = path.with_extension("temporarily-moved");
    std::fs::rename(&path, &moved).unwrap();
    let diagnostic = admin.call(EngineRequest::Doctor).await.unwrap();
    assert!(diagnostic["packages"][0]["error"].is_string());
    std::fs::rename(moved, path).unwrap();
    drop(admin);
    stop.cancel();
    server.await.unwrap().unwrap();
}
#[test]
fn world_grants_do_not_expand_to_shared_or_protected_writes() {
    let d = tempfile::tempdir().unwrap();
    let root = d.path().join("installation");
    let author = runtime::initialize(&root).unwrap();
    let mut registry = Registry::open(&root).unwrap();
    // Test credentials are read by test code, never printed or written to output.
    let profile = Credential::new(universe_store::credentials::read(&root, &author).unwrap());
    let p = registry
        .authenticate(&EngineHello {
            protocol_version: universe_protocol::PROTOCOL_VERSION.into(),
            profile_id: author,
            credential: profile,
            client_name: "test".into(),
        })
        .unwrap();
    let u = UniverseId::generate(&mut rand::rng());
    let c = ContinuityId::generate(&mut rand::rng());
    let path = root.join("packages/u.db");
    let kernel = universe_store::kernel::Kernel::create(
        &path,
        u.clone(),
        "U",
        c,
        &PrincipalId::generate(&mut rand::rng()),
    )
    .unwrap();
    registry.register(&p, &u, "U", &path).unwrap();
    let agent = registry.enroll(&p).unwrap();
    let w = WorldId::generate(&mut rand::rng());
    let worlds = BTreeSet::from([w.clone()]);
    registry
        .grant(
            &p,
            &GrantSpec {
                profile_id: agent.clone(),
                universe_id: u.clone(),
                worlds: Some(vec![w]),
                propose: true,
                edit: true,
                protected: false,
                limits: Default::default(),
            },
        )
        .unwrap();
    let ap = universe_service::registry::Principal {
        id: agent,
        author: false,
    };
    assert!(registry
        .authorize_write(&ap, &u, &worlds, false, false, true)
        .is_ok());
    assert!(registry
        .authorize_write(&ap, &u, &worlds, true, false, true)
        .is_err());
    assert!(registry
        .authorize_write(&ap, &u, &worlds, false, true, true)
        .is_err());
    assert!(registry
        .authorize_write(&ap, &u, &BTreeSet::new(), false, false, true)
        .is_err());
    let other = BTreeSet::from([WorldId::generate(&mut rand::rng())]);
    assert!(registry
        .authorize_write(&ap, &u, &other, false, false, true)
        .is_err());
    // Listed with zero children must stay empty, never become unrestricted.
    let db = rusqlite::Connection::open(root.join("installation.sqlite")).unwrap();
    db.execute("DELETE FROM grant_worlds", []).unwrap();
    db.execute("UPDATE grants SET entities_state='listed',predicates_state='listed',continuities_state='listed'", []).unwrap();
    assert_eq!(registry.scope(&ap, &u).unwrap(), Some(BTreeSet::new()));
    let limits = registry.limits(&ap, &u).unwrap();
    assert_eq!(limits.entities, Some(vec![]));
    assert_eq!(limits.predicates, Some(vec![]));
    assert_eq!(limits.continuities, Some(vec![]));
    assert!(registry
        .authorize_write(&ap, &u, &worlds, false, false, true)
        .is_err());
    // Replacing listed boundaries with all removes their child rows atomically.
    registry
        .grant(
            &p,
            &GrantSpec {
                profile_id: ap.id.clone(),
                universe_id: u.clone(),
                worlds: None,
                propose: false,
                edit: false,
                protected: false,
                limits: GrantLimits::default(),
            },
        )
        .unwrap();
    assert_eq!(registry.scope(&ap, &u).unwrap(), None);
    assert_eq!(registry.limits(&ap, &u).unwrap(), GrantLimits::default());
    assert!(registry
        .authorize_write(&ap, &u, &worlds, false, false, false)
        .is_err());
    registry.withdraw_grant(&p, &ap.id, &u).unwrap();
    assert!(registry.scope(&ap, &u).is_err());
    assert!(registry.limits(&ap, &u).is_err());
    registry.begin_purge(&p, &u).unwrap();
    drop(kernel);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn relational_grants_credentials_restart_and_independent_inspection() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("installation");
    let author = runtime::initialize(&root).unwrap();
    let secret = universe_store::credentials::read(&root, &author).unwrap();
    let stop = CancellationToken::new();
    let r = root.clone();
    let s = stop.clone();
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut admin = connect(&root, &author, "qualification").await;
    let u = admin
        .call(EngineRequest::CreateUniverse {
            name: "Relational".into(),
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
        })
        .await
        .unwrap();
    let uid: UniverseId = serde_json::from_value(u["universe_id"].clone()).unwrap();
    let agent: ProfileId = serde_json::from_value(
        admin.call(EngineRequest::Enroll).await.unwrap()["profile_id"].clone(),
    )
    .unwrap();
    let agent_secret = universe_store::credentials::read(&root, &agent).unwrap();
    let mut client = connect(&root, &agent, "qualification").await;
    assert!(client.call(describe("Relational")).await.is_err());
    let a = RecordId::generate(&mut rand::rng());
    let b = RecordId::generate(&mut rand::rng());
    let grant = GrantSpec {
        profile_id: agent.clone(),
        universe_id: uid.clone(),
        worlds: Some(vec![WorldId::generate(&mut rand::rng())]),
        propose: true,
        edit: true,
        protected: false,
        limits: GrantLimits {
            entities: Some(vec![b.clone(), a.clone(), b]),
            predicates: Some(vec![a]),
            continuities: Some(vec![
                serde_json::from_value(u["continuity_id"].clone()).unwrap()
            ]),
            expires_at: Some(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_secs()
                    + 3600,
            ),
            delegated_commit: true,
            allow_shared: true,
        },
    };
    admin
        .call(EngineRequest::Grant {
            grant: grant.clone(),
        })
        .await
        .unwrap();
    assert!(client.call(describe("Relational")).await.is_ok());
    // Real client requests enforce each relational write boundary independently.
    for (index, limits) in [
        GrantLimits {
            entities: Some(vec![RecordId::generate(&mut rand::rng())]),
            ..Default::default()
        },
        GrantLimits {
            predicates: Some(vec![RecordId::generate(&mut rand::rng())]),
            ..Default::default()
        },
        GrantLimits {
            continuities: Some(vec![ContinuityId::generate(&mut rand::rng())]),
            ..Default::default()
        },
    ]
    .into_iter()
    .enumerate()
    {
        let restricted = GrantSpec {
            worlds: None,
            limits,
            ..grant.clone()
        };
        admin
            .call(EngineRequest::Grant { grant: restricted })
            .await
            .unwrap();
        let context = client.call(EngineRequest::Tool { request: Box::new(serde_json::from_value(json!({
            "tool":"universe_open_context", "args":{
                "universe":"Relational", "continuity_id":u["continuity_id"], "revision":{"kind":"head"},
                "represented_context":u["context_id"], "temporal_query":{"kind":"timeless"}, "temporal_systems":[], "perspective":"author"
            }
        })).unwrap()) }).await.unwrap()["result"]["context_id"].clone();
        let proposal = EngineRequest::Tool { request: Box::new(serde_json::from_value(json!({
            "tool":"universe_propose", "args":{
                "action":"create", "universe":"Relational", "context_id":context,
                "operations":[{"kind":"create_entity", "client_ref":"outside", "record":{
                    "names":[], "classification":null, "classificationResolution":"unclassified", "worldAssociations":[], "labels":{"en":"Outside boundary"}, "metadata":{}
                }}], "submission":"submitted", "rationale":"Negative scope control", "idempotency_key":format!("restricted-{index}")
            }
        })).unwrap()) };
        assert!(client.call(proposal).await.is_err());
    }
    admin
        .call(EngineRequest::Grant {
            grant: grant.clone(),
        })
        .await
        .unwrap();
    let report_before = admin.call(EngineRequest::Profiles).await.unwrap();
    assert_eq!(report_before["grants"], json!([grant]));
    let archive = dir.path().join("universe.sqlite");
    admin
        .call(EngineRequest::ExportLogical {
            complete_history: false,
            universe: universe_protocol::request::Selector("Relational".into()),
            destination: archive.clone(),
            record_ids: vec![],
        })
        .await
        .unwrap();
    drop(admin);
    drop(client);
    stop.cancel();
    server.await.unwrap().unwrap();
    let stop = CancellationToken::new();
    let r = root.clone();
    let s = stop.clone();
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut admin = connect(&root, &author, "restart").await;
    let mut client = connect(&root, &agent, "restart").await;
    assert!(secret == universe_store::credentials::read(&root, &author).unwrap());
    assert!(agent_secret == universe_store::credentials::read(&root, &agent).unwrap());
    assert_eq!(
        admin.call(EngineRequest::Profiles).await.unwrap(),
        report_before
    );
    assert!(client.call(describe("Relational")).await.is_ok());
    let reports = json!({"grant":grant,"profiles":report_before,"doctor":admin.call(EngineRequest::Doctor).await.unwrap(),"status":admin.call(EngineRequest::Status).await.unwrap()});
    let report = dir.path().join("report.json");
    // The independent inspector reads authority expectations without any secrets.
    let mut witness = serde_json::to_value(&grant).unwrap();
    witness["reports"] = reports;
    std::fs::write(&report, serde_json::to_vec(&witness).unwrap()).unwrap();
    let inspection = std::process::Command::new("python3")
        .arg(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../scripts/verify_installation_relational.py"
        ))
        .args([root.as_os_str(), report.as_os_str(), archive.as_os_str()])
        .output()
        .unwrap();
    assert!(
        inspection.status.success(),
        "{}",
        String::from_utf8_lossy(&inspection.stderr)
    );
    // Expiration invalidates an already authenticated connection.
    let db = rusqlite::Connection::open(root.join("installation.sqlite")).unwrap();
    db.execute(
        "UPDATE grants SET expires_at='1' WHERE profile=?1",
        [agent.as_str()],
    )
    .unwrap();
    assert!(client.call(describe("Relational")).await.is_err());
    admin.call(EngineRequest::Grant { grant }).await.unwrap();
    admin
        .call(EngineRequest::Revoke {
            profile_id: agent.clone(),
        })
        .await
        .unwrap();
    assert!(client.call(describe("Relational")).await.is_err());
    assert!(EngineClient::connect(&root, &agent, "revoked")
        .await
        .is_err());
    drop(db);
    drop(client);
    drop(admin);
    stop.cancel();
    server.await.unwrap().unwrap();
    // Revocation survives restart independently of the unchanged private credential.
    let registry = Registry::open(&root).unwrap();
    assert!(registry
        .authenticate(&EngineHello {
            protocol_version: universe_protocol::PROTOCOL_VERSION.into(),
            profile_id: agent,
            credential: Credential::new(agent_secret),
            client_name: "revoked-after-restart".into(),
        })
        .is_err());
}

#[test]
fn legacy_installation_is_rejected_without_conversion() {
    let dir = tempfile::tempdir().unwrap();
    let root = universe_store::ownership::private_dir(&dir.path().join("installation")).unwrap();
    let path = root.join("installation.sqlite");
    universe_store::ownership::protected_file(&path, true).unwrap();
    let db = rusqlite::Connection::open(&path).unwrap();
    db.execute_batch(
        "CREATE TABLE grants(profile TEXT, universe TEXT, worlds TEXT); PRAGMA user_version=2;",
    )
    .unwrap();
    drop(db);
    let before = std::fs::read(&path).unwrap();
    assert!(Registry::open(&root).is_err());
    assert_eq!(before, std::fs::read(&path).unwrap());
}
