//! Immutable history and compensating changes through the ordinary draft workflow.
use dioxus::prelude::*;
use serde_json::{json, Value};
#[component]
pub fn History(records: Value, disabled: bool, onadd: EventHandler<Value>) -> Element {
    let current = records["records"][0].clone();
    rsx! { details { class:"panel", summary {"Record history · restore a prior version"}
        p {"Restoring adds a compensating change to the draft. Review and validate it before approval; earlier revisions remain intact."}
        for entry in records["history"].as_array().cloned().unwrap_or_default() {
            article {
                p { {format!("{} · {}", entry["revision"].as_str().unwrap_or_default(), entry["reason"].as_str().unwrap_or_default())} }
                super::readable::ReadValue {value:entry["record"].clone()}
                button {disabled:disabled||!current["payload"]["establishedBy"].is_null()||!entry["record"]["payload"]["establishedBy"].is_null()||entry["record"].is_null()||current.is_null()||entry["record"]["record_version_id"]==current["record_version_id"],onclick:{let old=entry["record"].clone();let expected=current["record_version_id"].clone();move |_|onadd.call(json!({"kind":"adopt_record_version","source":old,"expected_version":expected}))},"Restore this version in draft"}
            }
        }
    }}
}
#[component]
pub fn Issues(
    findings: Value,
    profile: String,
    disabled: bool,
    onadd: EventHandler<Value>,
) -> Element {
    let mut selected = use_signal(String::new);
    let mut mode = use_signal(|| "defer".to_string());
    let mut rationale = use_signal(String::new);
    rsx! { details {class:"panel",summary{"Issue decisions"}
        p {"Record a decision about an exact finding. Acknowledging or resolving an issue does not waive a blocking rule; scoped exceptions require their own review."}
        label {r#for:"issue-finding","Finding"}
        super::select::RichSelect {id:"issue-finding",disabled,value:selected(),options:std::iter::once(super::select::Choice::new("","Choose a finding")).chain(findings.as_array().into_iter().flatten().map(|f|super::select::Choice::new(f["fingerprint"].as_str().unwrap_or_default(),format!("{} · {}",f["rule_id"],f["outcome"])))).collect(),onchange:move|e:super::select::SelectionEvent|selected.set(e.value())}
        label {r#for:"issue-mode","Decision"}
        super::select::RichSelect {id:"issue-mode",disabled,value:mode(),options:super::select::choices(&[("defer","Defer"),("accept","Accept"),("resolve","Resolve")]),onchange:move|e:super::select::SelectionEvent|mode.set(e.value())}
        label {r#for:"issue-rationale","Rationale"}textarea{id:"issue-rationale",disabled,value:rationale,oninput:move|e|rationale.set(e.value())}
        button {disabled:disabled||selected().is_empty()||rationale().trim().is_empty(),onclick:move|_|onadd.call(json!({"kind":"record_issue_decision","client_ref":universe_domain::ids::RecordId::generate(&mut rand::rng()),"record":{"fingerprints":[selected()],"mode":mode(),"scope":"Exact finding","rationale":rationale(),"principal":profile.replacen("prf_","prn_",1)}})),"Add issue decision to draft"}
    }}
}
