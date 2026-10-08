//! Public bootstrap discovery uses the same visibility boundary as frame opening.
use super::*;

#[test]
fn summary_discovers_openable_heads_and_omits_hidden_contexts_and_branches() {
    let directory = tempfile::tempdir().unwrap();
    let universe = UniverseId::parse("unv_000000000000000000000001").unwrap();
    let continuity = ContinuityId::parse("cont_000000000000000000000001").unwrap();
    let hidden_branch = ContinuityId::parse("cont_000000000000000000000002").unwrap();
    let principal = PrincipalId::parse("prn_000000000000000000000001").unwrap();
    let profile = ProfileId::parse("prf_000000000000000000000001").unwrap();
    let mut kernel = Kernel::create(
        &directory.path().join("world.sqlite"),
        universe.clone(),
        "Discovery",
        continuity.clone(),
        &principal,
    )
    .unwrap();
    let rid = |n| RecordId::parse(&format!("rec_{n:024x}")).unwrap();
    let rr = |n| json!({"universe":universe,"record":rid(n)});
    let record = |n, value| {
        let payload: Payload = serde_json::from_value(value).unwrap();
        RecordVersion::build(
            RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
            RecordIdentity::new(universe.clone(), rid(n), payload.kind()),
            payload,
        )
        .unwrap()
    };
    let rows = [
        record(
            1,
            json!({"record_kind":"represented_context","universe":universe,"kind":{"kind":"objective"},"labels":{"en":"Reality"}}),
        ),
        record(10, json!({"record_kind":"world","selector":"Visible"})),
        record(20, json!({"record_kind":"world","selector":"Hidden"})),
        record(
            3,
            json!({"record_kind":"entity","names":[],"classification":null,"classificationResolution":"unclassified","worldAssociations":[{"world":"wld_000000000000000000000014","role":"setting","validity":{"kind":"unspecified"},"qualifiers":{}}],"labels":{},"metadata":{}}),
        ),
        record(
            2,
            json!({"record_kind":"represented_context","universe":universe,"kind":{"kind":"character","holder":rr(3)},"labels":{"en":"Hidden mind"}}),
        ),
    ];
    let first = kernel
        .commit(&CommitInput {
            universe: universe.clone(),
            continuity: continuity.clone(),
            expected_head: kernel.head(&continuity).unwrap(),
            principal: principal.clone(),
            decision: "seed".into(),
            reason: "test contexts".into(),
            idempotency_key: "seed".into(),
            changes: rows
                .iter()
                .map(|r| Assignment {
                    record_id: r.identity.record_id.clone(),
                    expected: None,
                    next: Some(r.clone()),
                })
                .collect(),
        })
        .unwrap();
    let fork = kernel
        .branch(&hidden_branch, &continuity, &first, &principal)
        .unwrap();
    kernel
        .workflow_put(&[(
            format!("continuity-name:{hidden_branch}"),
            json!("Hidden branch"),
        )])
        .unwrap();
    kernel
        .commit(&CommitInput {
            universe: universe.clone(),
            continuity: hidden_branch.clone(),
            expected_head: fork,
            principal,
            decision: "remove objective".into(),
            reason: "hidden context only".into(),
            idempotency_key: "hidden-only".into(),
            changes: vec![Assignment {
                record_id: rid(1),
                expected: Some(rows[0].record_version_id.clone()),
                next: None,
            }],
        })
        .unwrap();
    let mut workflow = Workflow {
        kernel: &mut kernel,
        authority: None,
        principal: Principal {
            id: profile.clone(),
            author: false,
        },
        approval_author: profile,
        scope: Some(BTreeSet::from([WorldId::parse(
            "wld_00000000000000000000000a",
        )
        .unwrap()])),
        permissions: (false, false, false),
        name: "Discovery".into(),
    };
    let summary = workflow
        .execute(
            Request::from_tool(
                "universe_describe",
                json!({"universe":"Discovery","mode":"summary"}),
            )
            .unwrap(),
        )
        .unwrap();
    let options = &summary["result"]["continuities"];
    assert_eq!(options.as_array().unwrap().len(), 1);
    assert_eq!(options[0]["id"], json!(continuity));
    assert_eq!(options[0]["revision_id"], json!(first));
    assert_eq!(
        options[0]["represented_contexts"].as_array().unwrap().len(),
        1
    );
    assert_eq!(options[0]["represented_contexts"][0]["id"], json!(rid(1)));
    assert!(!summary.to_string().contains("Hidden mind"));
    assert!(!summary.to_string().contains("Hidden branch"));
    let opened = workflow.execute(Request::from_tool("universe_open_context",json!({
        "universe":"Discovery","continuity_id":options[0]["id"],"revision":{"kind":"exact","revision_id":options[0]["revision_id"]},
        "represented_context":options[0]["represented_contexts"][0]["id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"
    })).unwrap()).unwrap();
    assert_eq!(opened["frame"]["revision"], json!(first));
    assert!(workflow.execute(Request::from_tool("universe_open_context",json!({
        "universe":"Discovery","continuity_id":continuity,"revision":{"kind":"head"},
        "represented_context":rid(2),"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"
    })).unwrap()).is_err());
    workflow.scope = None;
    let summary = workflow
        .execute(
            Request::from_tool(
                "universe_describe",
                json!({"universe":"Discovery","mode":"summary"}),
            )
            .unwrap(),
        )
        .unwrap();
    assert_eq!(
        summary["result"]["continuities"].as_array().unwrap().len(),
        2
    );
    assert!(summary.to_string().contains("Hidden mind"));
    assert!(summary.to_string().contains("Hidden branch"));
}
