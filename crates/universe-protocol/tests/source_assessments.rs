//! Cross-language fixtures were frozen before this implementation. Expected
//! bytes/hashes are not computed with the production serializer under test.
use serde_json::{json, Value};
use universe_domain::canonical::Canonical;
use universe_protocol::{assessment::*, response::Validation, validation_scope::*};
fn examples() -> Value {
    serde_json::from_str(include_str!(
        "../../../docs/decisions/d03-d08/examples.json"
    ))
    .unwrap()
}
fn proofs() -> Value {
    serde_json::from_str(include_str!(
        "../../../docs/decisions/d03-d08/proof-results.json"
    ))
    .unwrap()
}
fn decode(v: &Value) -> Result<SourceAssessmentV1, String> {
    SourceAssessmentV1::decode(&serde_json::to_vec(v).unwrap())
}
fn hash_value(d: Sha256Hex) -> Value {
    serde_json::to_value(d).unwrap()
}
#[test]
fn independent_bytes_digests_and_connected_production_binding() {
    let e = examples();
    let p = proofs();
    for (example, proof) in [
        (&e, "assessment"),
        (&e["production_bound_example"], "production_assessment"),
    ] {
        let envelope: AssessmentEnvelope =
            universe_protocol::wire::decode(&serde_json::to_vec(&example["assessment"]).unwrap())
                .unwrap();
        envelope.verify().unwrap();
        assert_eq!(
            serde_json::to_value(&envelope).unwrap(),
            example["assessment"]
        );
        let body = &envelope.body;
        assert_eq!(
            body.canonical_bytes().unwrap(),
            p["bindings"][proof]["canonical_utf8"]
                .as_str()
                .unwrap()
                .as_bytes()
        );
        assert_eq!(
            hash_value(body.digest().unwrap()),
            p["bindings"][proof]["sha256"]
        );
        assert_eq!(
            decode(&serde_json::from_slice::<Value>(&body.canonical_bytes().unwrap()).unwrap())
                .unwrap()
                .canonical_bytes()
                .unwrap(),
            body.canonical_bytes().unwrap()
        );
        body.verify_source_bytes(|_| Some(e["source_a"].as_str().unwrap().as_bytes().to_vec()))
            .unwrap();
        body.bind_frozen_proposal(&body.proposal, &body.base_frame)
            .unwrap();
        let binding: SourceValidationBindingV1 = universe_protocol::wire::decode(
            &serde_json::to_vec(&example["final_binding"]).unwrap(),
        )
        .unwrap();
        let validation: Validation =
            serde_json::from_value(example["execution_core"].clone()).unwrap();
        assert_eq!(
            hash_value(execution_result_digest(&validation)),
            example["final_binding"]["execution_result_digest"]
        );
        assert_eq!(
            hash_value(body.inventory_digest().unwrap()),
            example["final_binding"]["submitted_input"]["inventory_digest"]
        );
        assert_eq!(
            hash_value(binding.digest().unwrap()),
            example["validation_v3"]["final_binding_digest"]
        );
        let proof = if proof == "assessment" {
            "final_validation"
        } else {
            "production_final_validation"
        };
        assert_eq!(
            binding.to_canonical().to_bytes(),
            p["bindings"][proof]["canonical_utf8"]
                .as_str()
                .unwrap()
                .as_bytes()
        );
    }
}
#[test]
fn material_mutations_change_assessment_and_final_bindings() {
    let e = examples();
    let original = e["assessment"]["body"].clone();
    let baseline = decode(&original).unwrap();
    let before = hash_value(baseline.digest().unwrap());
    let mut mutations = Vec::new();
    let mut v = original.clone();
    v["sources"][0]["blob_digest"] = json!("a".repeat(64));
    mutations.push(v);
    let mut v = original.clone();
    v["sources"][0]["source_version"]["version"] = json!("ver_000000000000000000000099");
    mutations.push(v);
    let mut v = original.clone();
    v["sources"][0]["ranges"][0]["end"] = json!(46);
    v["declared_inventory"][2]["range"]["end"] = json!(46);
    mutations.push(v);
    let mut v = original.clone();
    v["proposal"]["digest"] = json!("b".repeat(64));
    mutations.push(v);
    let mut v = original.clone();
    v["proposal"]["version"] = json!(2);
    mutations.push(v);
    let mut v = original.clone();
    v["claim_mappings"][1]["modality"] = json!("negated");
    mutations.push(v);
    let mut v = original.clone();
    v["claim_mappings"][1]["semantic"]["polarity"] = json!("refutation");
    mutations.push(v);
    let mut v = original.clone();
    v["declared_inventory"][1]["statement"] = json!("A changed declared interpretation.");
    mutations.push(v);
    let mut v = original.clone();
    v["assessor"]["assessed_at"] = json!("2026-10-02T20:00:01Z");
    mutations.push(v);
    let mut v = original.clone();
    v["claim_mappings"].as_array_mut().unwrap().reverse();
    mutations.push(v);
    for v in mutations {
        let body = decode(&v).unwrap();
        let after = hash_value(body.digest().unwrap());
        assert_ne!(before, after);
        let mut binding: SourceValidationBindingV1 =
            serde_json::from_value(e["final_binding"].clone()).unwrap();
        let prior = hash_value(binding.digest().unwrap());
        binding.selection.selected.as_mut().unwrap().digest = body.digest().unwrap();
        if let AssessmentState::Bound {
            assessment_reference,
            ..
        } = &mut binding.assessment_state
        {
            assessment_reference.digest = body.digest().unwrap();
        }
        assert_ne!(prior, hash_value(binding.digest().unwrap()));
    }
    let unresolved = decode(&e["unresolved_body_example"]).unwrap();
    let mut changed = e["unresolved_body_example"].clone();
    changed["unresolved"][0]["detail"] = json!("Another unresolved interpretation.");
    assert_ne!(
        hash_value(unresolved.digest().unwrap()),
        hash_value(decode(&changed).unwrap().digest().unwrap())
    );
}
#[test]
fn malformed_unsupported_and_unaccounted_payloads_fail() {
    let original = examples()["assessment"]["body"].clone();
    let bad = [
        ("/kind", json!("source_assessment_v2")),
        ("/proposal/digest", json!("A".repeat(64))),
        ("/proposal/version", json!(0)),
        ("/assessor/tool", json!({})),
        ("/assessor/method", json!("external_model_review")),
        ("/assessor/assessed_at", json!("2026-02-30T00:00:00Z")),
        ("/sources/0/representation", json!("mutable-url")),
        ("/sources/0/ranges/0/end", json!(48)),
        ("/sources/0/ranges/0/start", json!(47)),
        (
            "/sources/0/source_version/universe",
            json!("unv_000000000000000000000099"),
        ),
        ("/declared_inventory/0/mapping_ids", json!([])),
        ("/declared_inventory/0/range/end", json!(48)),
        ("/declared_inventory/0/source_key", json!("missing")),
        ("/claim_mappings/0/item_ids", json!(["missing"])),
        (
            "/claim_mappings/0/context/version",
            json!("ver_000000000000000000000099"),
        ),
        ("/claim_mappings/0/occurrence", json!("unknown")),
        (
            "/claim_mappings/0/narration_position",
            json!({"kind":"unknown","reason":"unclear"}),
        ),
        (
            "/claim_mappings/0/story_time",
            json!({"kind":"unspecified"}),
        ),
        ("/claim_mappings/0/judgment", json!("unresolved")),
        ("/claim_mappings/0/semantic/kind", json!("compiled_prose")),
        ("/conclusion", json!("inconsistent")),
        ("/inventory_declaration/kind", json!("no_material_claims")),
        ("/inventory_declaration/rationale", json!("")),
    ];
    for (path, value) in bad {
        let mut v = original.clone();
        *v.pointer_mut(path).unwrap() = value;
        assert!(decode(&v).is_err(), "{path}");
    }
    for path in [
        "/sources",
        "/dependencies",
        "/declared_inventory",
        "/claim_mappings",
        "/claim_mappings/0/referents",
        "/claim_mappings/0/item_ids",
    ] {
        let mut v = original.clone();
        let a = v.pointer_mut(path).unwrap().as_array_mut().unwrap();
        a.push(a[0].clone());
        assert!(decode(&v).is_err(), "duplicate {path}");
    }
    for path in [
        "",
        "/assessor",
        "/sources/0",
        "/claim_mappings/0",
        "/claim_mappings/0/semantic",
    ] {
        let mut v = original.clone();
        v.pointer_mut(path)
            .unwrap()
            .as_object_mut()
            .unwrap()
            .insert("digest".into(), json!("self-reference"));
        assert!(decode(&v).is_err(), "unknown {path}");
    }
    for (path, key) in [
        ("/assessor", "tool"),
        ("/sources/0", "work_edition"),
        ("/sources/0", "passage_id"),
        ("/claim_mappings/0", "realm"),
    ] {
        let mut v = original.clone();
        v.pointer_mut(path)
            .unwrap()
            .as_object_mut()
            .unwrap()
            .remove(key);
        assert!(decode(&v).is_err(), "missing nullable {key}");
    }
    let text = serde_json::to_string(&original).unwrap();
    let duplicated = text.replacen(
        "\"kind\":\"source_assessment_v1\"",
        "\"kind\":\"source_assessment_v1\",\"kind\":\"source_assessment_v1\"",
        1,
    );
    assert!(SourceAssessmentV1::decode(duplicated.as_bytes()).is_err());
    assert!(SourceAssessmentV1::decode(&[0xff]).is_err());
    assert!(
        SourceAssessmentV1::decode(&vec![b' '; universe_protocol::MAX_FRAME_BYTES + 1]).is_err()
    );
}
#[test]
fn bytes_and_frozen_binding_checks_do_not_trust_caller_hashes() {
    let e = examples();
    let body = decode(&e["assessment"]["body"]).unwrap();
    assert!(body.verify_source_bytes(|_| None).is_err());
    assert!(body
        .verify_source_bytes(|_| Some(e["source_b"].as_str().unwrap().as_bytes().to_vec()))
        .is_err());
    let mut v = e["assessment"]["body"].clone();
    v["sources"][0]["ranges"][0]["start"] = json!(12);
    v["declared_inventory"].as_array_mut().unwrap().clear();
    v["claim_mappings"].as_array_mut().unwrap().clear();
    v["inventory_declaration"]["kind"] = json!("no_material_claims");
    let body = decode(&v).unwrap();
    assert!(body
        .verify_source_bytes(|_| Some(e["source_a"].as_str().unwrap().as_bytes().to_vec()))
        .is_err());
    let mut proposal = body.proposal.clone();
    proposal.digest = "0".repeat(64);
    assert!(body
        .bind_frozen_proposal(&proposal, &body.base_frame)
        .is_err());
    let mut frame = body.base_frame.clone();
    frame.personal_sequence = Some("another".into());
    assert!(body.bind_frozen_proposal(&body.proposal, &frame).is_err());
}
#[test]
fn external_attribution_empty_inventory_and_nullable_roundtrip() {
    let mut v = examples()["assessment"]["body"].clone();
    v["assessor"]["method"] = json!("external_model_review");
    v["assessor"]["tool"] = json!({"name":"review tool", "version":"1", "model_revision":"fixed-revision", "procedure_digest":"a".repeat(64)});
    v["sources"][0]["work_edition"] = Value::Null;
    v["sources"][0]["passage_id"] = Value::Null;
    v["declared_inventory"] = json!([]);
    v["claim_mappings"] = json!([]);
    v["inventory_declaration"]["kind"] = json!("no_material_claims");
    let body = decode(&v).unwrap();
    assert_eq!(serde_json::to_value(&body).unwrap(), v);
    assert_eq!(
        body.to_canonical().to_bytes(),
        universe_domain::canonical::canonical_serde(&body).to_bytes()
    );
}
#[test]
fn selection_and_final_binding_reject_incoherent_or_restricted_scope() {
    let e = examples();
    for path in [
        "/selection/generation",
        "/submitted_input/proposal/version",
        "/selection/proposal/version",
    ] {
        let mut v = e["final_binding"].clone();
        *v.pointer_mut(path).unwrap() = json!(99);
        let binding: SourceValidationBindingV1 = serde_json::from_value(v).unwrap();
        assert!(binding.digest().is_err(), "{path}");
    }
    let mut v = e["final_binding"].clone();
    v["assessment_state"] = json!({"kind":"restricted"});
    assert!(serde_json::from_value::<SourceValidationBindingV1>(v).is_err());
    let binding: SourceValidationBindingV1 =
        serde_json::from_value(e["fresh_record_only_binding"].clone()).unwrap();
    binding.digest().unwrap();
    let mut v = e["selection"].clone();
    v.as_object_mut().unwrap().remove("selected");
    assert!(serde_json::from_value::<AssessmentSelection>(v).is_err());
}

#[test]
fn independent_unicode_escapes_exact_u64_and_object_order_fixture() {
    let fixture: Value = serde_json::from_str(include_str!(
        "../../../fixtures/source-assessments/edge.json"
    ))
    .unwrap();
    let body = decode(&fixture["body"]).unwrap();
    assert_eq!(
        body.canonical_bytes().unwrap(),
        fixture["canonical_utf8"].as_str().unwrap().as_bytes()
    );
    assert_eq!(hash_value(body.digest().unwrap()), fixture["digest"]);
    let text = serde_json::to_string_pretty(&fixture["body"]).unwrap();
    assert_eq!(
        SourceAssessmentV1::decode(text.as_bytes())
            .unwrap()
            .canonical_bytes()
            .unwrap(),
        body.canonical_bytes().unwrap()
    );
    let mut changed = fixture["body"].clone();
    changed["base_frame"]["personalSequence"] = json!("é and é remain distinct");
    assert_ne!(
        hash_value(decode(&changed).unwrap().digest().unwrap()),
        fixture["digest"]
    );
}

#[test]
fn all_semantic_variants_roundtrip_and_unresolved_dispositions_remain_accounted() {
    let e = examples();
    let reference = e["assessment"]["body"]["dependencies"][0].clone();
    for semantic in [
        json!({"kind":"knowledge", "holder":reference, "content":reference, "acquisition":[reference]}),
        json!({"kind":"source_description", "subject":reference, "depiction":"subjective", "implied_claims":[reference]}),
    ] {
        let mut v = e["assessment"]["body"].clone();
        v["claim_mappings"][0]["semantic"] = semantic;
        let parsed = decode(&v).unwrap();
        for mapping in &parsed.claim_mappings {
            assert_eq!(
                mapping.semantic.to_canonical(),
                universe_domain::canonical::canonical_serde(&mapping.semantic)
            );
            assert_eq!(
                mapping.narration_position.to_canonical(),
                universe_domain::canonical::canonical_serde(&mapping.narration_position)
            );
        }
        assert_eq!(serde_json::to_value(parsed).unwrap(), v);
    }
    let mut v = e["unresolved_body_example"].clone();
    assert!(decode(&v).is_ok());
    v["conclusion"] = json!("consistent_with_declared_inventory");
    assert!(decode(&v).is_err());
    v = e["unresolved_body_example"].clone();
    v["claim_mappings"][0]["judgment"] = json!("contradicted");
    v["conclusion"] = json!("inconsistent");
    assert!(decode(&v).is_ok());
    v["unresolved"][0]["item_ids"] = json!(["missing"]);
    assert!(decode(&v).is_err());
    let mut v = e["assessment"].clone();
    v["digest"] = json!("0".repeat(64));
    assert!(serde_json::from_value::<AssessmentEnvelope>(v)
        .unwrap()
        .verify()
        .is_err());
}

#[test]
fn assessment_is_rejected_as_a_canonical_domain_operation() {
    let body = examples()["assessment"]["body"].clone();
    for kind in [
        "source_assessment_v1",
        "attach_assessment",
        "select_assessment",
    ] {
        assert!(serde_json::from_value::<universe_domain::DomainOperation>(
            json!({"kind":kind, "body":body})
        )
        .is_err());
    }
}

#[test]
fn proposal_assessment_actions_are_closed_and_selection_requires_explicit_null() {
    use universe_protocol::{response::ProposalOutcome, Request};
    let e = examples();
    let body = e["assessment"]["body"].clone();
    let attach = json!({"action":"attach_assessment","universe":"Example",
        "context_id":"ctx_000000000000000000000001","proposal_reference":body["proposal"],
        "expected_selection_generation":0,"body":body,"idempotency_key":"attach"});
    let decoded = Request::from_tool("universe_propose", attach.clone()).unwrap();
    assert_eq!(serde_json::to_value(decoded).unwrap()["args"], attach);
    let mut select = attach.clone();
    select["action"] = json!("select_assessment");
    select.as_object_mut().unwrap().remove("body");
    select["assessment_reference"] = Value::Null;
    Request::from_tool("universe_propose", select.clone()).unwrap();
    let mut missing = select.clone();
    missing
        .as_object_mut()
        .unwrap()
        .remove("assessment_reference");
    assert!(Request::from_tool("universe_propose", missing).is_err());
    for mut invalid in [attach.clone(), select.clone()] {
        invalid["operations"] = json!([]);
        assert!(Request::from_tool("universe_propose", invalid).is_err());
    }
    let mut invalid = attach;
    invalid["body"]["assessor"]["extra"] = json!("forbidden");
    assert!(Request::from_tool("universe_propose", invalid).is_err());
    let selection = json!({"proposal":body["proposal"],"generation":1,"selected":null});
    let outcome: ProposalOutcome = serde_json::from_value(selection.clone()).unwrap();
    assert!(matches!(outcome, ProposalOutcome::AssessmentSelection(_)));
    assert_eq!(serde_json::to_value(outcome).unwrap(), selection);
    let malformed = json!({"proposal":body["proposal"],"generation":1});
    assert!(serde_json::from_value::<ProposalOutcome>(malformed).is_err());
}

#[test]
fn assessment_view_is_closed_and_exact_reference_requires_that_view() {
    use universe_protocol::Request;
    let reference = examples()["assessment"]["body"]["proposal"].clone();
    let mut args = json!({"universe":"Example","proposal_id":reference["proposal_id"],
        "version":reference["version"],"view_group":"assessment",
        "assessment_reference":{"assessment_id":examples()["assessment"]["assessment_id"],
        "digest":examples()["assessment"]["digest"]}});
    Request::from_tool("universe_get_proposal", args.clone()).unwrap();
    args["view_group"] = json!("payload");
    assert!(Request::from_tool("universe_get_proposal", args.clone()).is_err());
    args.as_object_mut().unwrap().remove("view_group");
    assert!(Request::from_tool("universe_get_proposal", args.clone()).is_err());
    args["view_group"] = json!("assessment");
    args["assessment_reference"] = Value::Null;
    assert!(Request::from_tool("universe_get_proposal", args).is_err());
}
