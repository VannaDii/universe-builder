//! Executable contract examples, emitted by xtask alongside JSON Schemas.
use serde_json::{json, Value};
pub fn id(prefix: &str, n: u64) -> String {
    format!("{prefix}_{n:024x}")
}
pub fn proposal_reference() -> Value {
    json!({"proposal_id":id("prp",1),"version":1,"digest":"fixture-digest"})
}
pub fn operation() -> Value {
    json!({"kind":"create_entity","client_ref":"new_entity","record":{"names":[],"types":[],"worldAssociations":[],"labels":{"en":"The Lantern House"},"metadata":{}}})
}
pub fn valid() -> Vec<(&'static str, Value)> {
    let u = "The Ashen Cycle";
    let c = id("ctx", 1);
    vec![
        ("universe_describe", json!({"universe":u,"mode":"summary"})),
        (
            "universe_open_context",
            json!({"universe":u,"continuity_id":id("cont",1),"revision":{"kind":"head"},"represented_context":id("rec",90),"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}),
        ),
        (
            "universe_search",
            json!({"universe":u,"context_id":c,"query":"Mara","typed_filters":{"record_kinds":[]},"limit":25}),
        ),
        (
            "universe_get",
            json!({"universe":u,"context_id":c,"record_ids":[id("rec",10)],"field_groups":["payload"]}),
        ),
        (
            "universe_get_state",
            json!({"universe":u,"context_id":c,"entity_ids":[id("rec",10)],"predicate_filters":[]}),
        ),
        (
            "universe_get_context",
            json!({"universe":u,"context_id":c,"focus_ids":[id("rec",10)],"purpose":"research","byte_budget":24576}),
        ),
        (
            "universe_validate",
            json!({"universe":u,"context_id":c,"mode":"inline","operations":[operation()],"check_scope":"candidate"}),
        ),
        (
            "universe_propose",
            json!({"universe":u,"context_id":c,"action":"create","operations":[operation()],"submission":"draft","rationale":"Fixture proposal","idempotency_key":"fixture-1"}),
        ),
        (
            "universe_get_proposal",
            json!({"universe":u,"proposal_id":id("prp",1),"version":1}),
        ),
        (
            "universe_get_impact",
            json!({"universe":u,"context_id":c,"mode":"inline","changed_records":[id("rec",10)],"scope":"dependencies","byte_budget":24576}),
        ),
        (
            "universe_commit",
            json!({"universe":u,"proposal_reference":proposal_reference(),"expected_base_revision":id("rev",1),"validation_run":id("val",1),"idempotency_key":"commit-1"}),
        ),
        (
            "universe_get_operation",
            json!({"universe":u,"lookup":"key","operation_kind":"propose","idempotency_key":"fixture-1"}),
        ),
        (
            "universe_cancel_operation",
            json!({"universe":u,"operation_id":id("op",1),"idempotency_key":"cancel-1"}),
        ),
    ]
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::{tool_schemas, Request};
    #[test]
    fn all_thirteen_tools_have_valid_examples_and_closed_schemas() {
        assert_eq!(valid().len(), 13);
        assert_eq!(tool_schemas().len(), 13);
        for (tool, args) in valid() {
            let parsed = Request::from_tool(tool, args.clone()).unwrap();
            assert_eq!(parsed.tool_name(), tool);
            for replacement in [
                Value::Null,
                json!(""),
                json!("   "),
                json!("*"),
                json!("../other"),
            ] {
                let mut bad = args.clone();
                bad["universe"] = replacement;
                assert!(Request::from_tool(tool, bad).is_err(), "{tool}");
            }
            let mut bad = args.clone();
            bad.as_object_mut().unwrap().remove("universe");
            assert!(Request::from_tool(tool, bad).is_err());
            let mut bad = args.clone();
            bad["approved"] = json!(true);
            assert!(Request::from_tool(tool, bad).is_err());
            let mut bad = args.clone();
            bad["universe_id"] = json!("not-an-id");
            assert!(Request::from_tool(tool, bad).is_err());
            let mut bad = args.clone();
            bad["world_id"] = json!(id("wld", 1));
            assert!(Request::from_tool(tool, bad).is_err());
        }
    }
    #[test]
    fn conditional_world_fields_are_rejected() {
        for action in ["submit", "withdraw"] {
            let args = json!({"universe":"The Ashen Cycle","context_id":id("ctx",1),"action":action,"proposal_reference":proposal_reference(),"idempotency_key":"x","world":"Aster"});
            assert!(Request::from_tool("universe_propose", args).is_err());
        }
        let args = json!({"universe":"The Ashen Cycle","context_id":id("ctx",1),"mode":"proposal","proposal_reference":proposal_reference(),"check_scope":"candidate","world":"Aster"});
        assert!(Request::from_tool("universe_validate", args).is_err());
    }
    #[test]
    fn optional_does_not_mean_null_and_nested_payloads_are_closed() {
        let mut search = valid()[2].1.clone();
        search["world"] = Value::Null;
        assert!(Request::from_tool("universe_search", search).is_err());
        let mut prop = valid()[7].1.clone();
        prop["operations"][0]["record"]["approved"] = json!(true);
        assert!(Request::from_tool("universe_propose", prop).is_err());
    }
    #[test]
    fn duplicate_keys_and_excessive_depth_fail_before_admission() {
        assert!(crate::wire::decode::<Request>(br#"{"tool":"universe_describe","args":{"universe":"A","universe":"B","mode":"summary"}}"#).is_err());
        let nested = format!("{}0{}", "[".repeat(256), "]".repeat(256));
        assert!(crate::wire::decode::<Value>(nested.as_bytes()).is_err());
    }
}
