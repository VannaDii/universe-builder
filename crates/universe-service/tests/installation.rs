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
    let profile: ProfileFile = serde_json::from_slice(
        &std::fs::read(
            root.join("profiles")
                .join(format!("{}.json", author.as_str())),
        )
        .unwrap(),
    )
    .unwrap();
    let p = registry
        .authenticate(&EngineHello {
            protocol_version: universe_protocol::PROTOCOL_VERSION.into(),
            profile_id: author,
            credential: profile.credential,
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
    drop(kernel);
}
