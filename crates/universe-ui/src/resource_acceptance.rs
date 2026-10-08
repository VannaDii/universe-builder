//! Exact author acceptance leaves resource arrival unexplained.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{ids::*, DomainOperation};

fn findings(validation: &Value, choices: &[Value]) -> Vec<Value> {
    if validation["kind"] != "evaluated" {
        return vec![];
    }
    validation["execution"]["findings"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|f| {
            f["coverage"] == "complete"
                && f["outcome"] == "not_established"
                && f["records"].as_array().is_some_and(|r| r.len() == 2)
                && f["fingerprint"].as_str().is_some_and(|s| !s.is_empty())
                && choices.iter().any(|r| {
                    r["kind"] == "rule"
                        && r["record_id"] == f["rule_id"]
                        && r["definition"]["capabilities"]
                            .as_array()
                            .is_some_and(|c| c.iter().any(|v| v == "resources.accounting.v1"))
                })
        })
        .cloned()
        .collect()
}

pub(crate) fn operation(
    validation: &Value,
    choices: &[Value],
    fingerprint: &str,
    profile: &str,
    author: bool,
    rationale: &str,
) -> Result<Value, String> {
    if !author {
        return Err("Only the author can accept an unexplained resource count.".into());
    }
    if rationale.trim().is_empty() {
        return Err("Explain why you accept this unexplained count.".into());
    }
    let finding = findings(validation, choices)
        .into_iter()
        .find(|f| f["fingerprint"] == fingerprint)
        .ok_or("Choose a current, complete resource finding.")?;
    let record = RecordId::parse(
        finding["records"][0]["record"]
            .as_str()
            .ok_or("Missing resource claim.")?,
    )
    .map_err(|e| e.to_string())?;
    let profile = ProfileId::parse(profile).map_err(|e| e.to_string())?;
    let op = json!({"kind":"record_issue_decision","client_ref":RecordId::generate(&mut rand::rng()),
        "record":{"fingerprints":[fingerprint],"mode":"accept","scope":format!("resource:{record}"),
        "rationale":rationale,"principal":profile.as_str().replacen("prf_","prn_",1)}});
    serde_json::from_value::<DomainOperation>(op.clone()).map_err(|e| e.to_string())?;
    Ok(op)
}

pub(crate) fn revision_request(
    universe: &str,
    context: &Value,
    proposal: &Value,
    decision: Value,
    key: &str,
) -> Result<universe_protocol::installation::EngineRequest, String> {
    let mut ops = proposal["operations"]
        .as_array()
        .cloned()
        .ok_or("Load the complete proposal before accepting a finding.")?;
    ops.push(decision);
    crate::author::tool(
        "universe_propose",
        json!({"action":"revise","universe":universe,
        "context_id":context,"proposal_reference":{"proposal_id":proposal["proposal_id"],"version":proposal["version"],"digest":proposal["digest"]},
        "operations":ops,"submission":"submitted","rationale":proposal["rationale"],"idempotency_key":key}),
    )
}

#[component]
pub fn ResourceAcceptance(
    validation: Value,
    choices: Vec<Value>,
    profile: String,
    author: bool,
    disabled: bool,
    onaccept: EventHandler<Value>,
) -> Element {
    let mut selected = use_signal(String::new);
    let mut rationale = use_signal(String::new);
    let mut status = use_signal(String::new);
    let available = findings(&validation, &choices);
    if !author || available.is_empty() {
        return rsx! {};
    }
    rsx! { section { class:"panel", h3 {"Accept an unexplained resource count"}
        p {"This creative decision accepts the exact count while leaving its arrival unexplained. It creates no arrival event. Changed claims or predecessors need fresh acceptance. Ordinary approval remains a separate step."}
        label {r#for:"resource-finding","Resource finding"}
        super::select::RichSelect {id:"resource-finding",disabled,value:selected(),options:std::iter::once(super::select::Choice::new("","Choose a resource finding")).chain(available.iter().map(|f|super::select::Choice::new(f["fingerprint"].as_str().unwrap_or_default(),format!("Unexplained count · {}",f["records"][0]["record"])))).collect(),onchange:move|e:super::select::SelectionEvent|selected.set(e.value())}
        label {r#for:"resource-rationale","Why you accept this unexplained count"}
        textarea {id:"resource-rationale",disabled,value:rationale,oninput:move|e|rationale.set(e.value())}
        button {disabled:disabled||rationale().trim().is_empty()||!available.iter().any(|f|f["fingerprint"]==selected()),onclick:move|_|{
            match operation(&validation,&choices,&selected(),&profile,author,&rationale()) {
                Ok(op)=>{onaccept.call(op);selected.set(String::new());rationale.set(String::new());status.set(String::new());},
                Err(e)=>status.set(e),
            }
        },"Record exact acceptance and revise proposal"}
        p {role:"status","{status}"}
    } }
}

#[cfg(test)]
#[path = "resource_acceptance_tests.rs"]
mod tests;
