//! Read-only domain details. The author interface never exposes editable JSON.
use dioxus::prelude::*;
use serde_json::Value;
pub fn caption(value: &str) -> String {
    let mut text = String::new();
    for (i, c) in value.chars().enumerate() {
        if c == '_' {
            text.push(' ');
        } else if c.is_uppercase() && i > 0 {
            text.push(' ');
            text.extend(c.to_lowercase());
        } else {
            text.push(c);
        }
    }
    let mut chars = text.chars();
    chars
        .next()
        .map(|c| c.to_uppercase().collect::<String>() + chars.as_str())
        .unwrap_or_default()
}
#[component]
pub fn ReadValue(value: Value) -> Element {
    match value {
        Value::Null => rsx! {span{"Not set"}},
        Value::Bool(b) => rsx! {span{if b{"Yes"}else{"No"}}},
        Value::String(s) => rsx! {span{class:"domain-text","{s}"}},
        Value::Number(n) => rsx! {span{"{n}"}},
        Value::Array(items) => {
            if items.is_empty() {
                rsx! { span { "None declared" } }
            } else {
                rsx! {
                    ul { class: "domain-list",
                        for (i, item) in items.into_iter().enumerate() {
                            li { key: "{i}", ReadValue { value: item } }
                        }
                    }
                }
            }
        }
        Value::Object(fields) => rsx! {
            dl { class: "domain-details",
                for (key, value) in fields {
                    div { key: "{key}",
                        dt { "{caption(&key)}" }
                        dd { ReadValue { value } }
                    }
                }
            }
        },
    }
}
pub(super) fn operation_summary(op: &Value) -> String {
    match op["kind"].as_str().unwrap_or_default() {
        "define_rule"
            if [
                "channelChronology",
                "knowledgePolicy",
                "relationCardinality",
            ]
            .iter()
            .any(|field| !op["record"][field].is_null()) =>
        {
            let kind = if !op["record"]["channelChronology"].is_null() {
                "communication chronology"
            } else if !op["record"]["knowledgePolicy"].is_null() {
                "knowledge basis"
            } else {
                "maximum cardinality"
            };
            format!(
                "Define {kind} policy: {}",
                op["record"]["key"].as_str().unwrap_or("Unnamed")
            )
        }
        "introduce_instance" => format!(
            "Create instance: {} ({})",
            op["name"]["text"].as_str().unwrap_or("Unnamed"),
            if op["classification"].is_null() {
                "unclassified"
            } else {
                "classified"
            }
        ),
        "refine_classification" => format!(
            "Set or refine classification: {} → {}",
            op["record"]["record"].as_str().unwrap_or("instance"),
            op["entity_type"].as_str().unwrap_or("classification")
        ),
        kind => caption(kind),
    }
}
#[component]
pub fn OperationReview(operations: Value) -> Element {
    rsx! {details{open:true,summary{"Authored changes"}
        for (i,op) in operations.as_array().into_iter().flatten().enumerate(){details{key:"{i}",summary{"{i + 1}. " {operation_summary(op)}}ReadValue{value:op.clone()}}}
    }}
}
#[component]
pub fn DraftChanges(operations: String, disabled: bool, onremove: EventHandler<usize>) -> Element {
    let Ok(ops) = serde_json::from_str::<Vec<Value>>(&operations) else {
        return rsx! {p{role:"alert","This saved draft cannot be decoded. Its stored version is preserved; reopen a valid saved draft before editing."}};
    };
    rsx! {div{class:"draft-changes",
        h3{"Draft changes"}
        if ops.is_empty(){p{"No changes added yet."}}
        for (i,op) in ops.into_iter().enumerate(){details{key:"{i}",summary{"{i + 1}. " {operation_summary(&op)}}ReadValue{value:op}button{class:"secondary",disabled,onclick:move|_|onremove.call(i),"Remove this change"}}}
    }}
}

/// Labels are drawn only from the currently authorized explorer and draft.
fn affected_label(id: &str, choices: &[Value]) -> String {
    choices
        .iter()
        .find(|r| r["record_id"] == id)
        .map(|r| {
            format!(
                "{}: {} ({id})",
                caption(r["kind"].as_str().unwrap_or("record")),
                r["label"].as_str().unwrap_or("Record")
            )
        })
        .unwrap_or_else(|| id.to_owned())
}
fn related_labels(record: &Value, choices: &[Value]) -> Vec<String> {
    let Some(row) = choices.iter().find(|r| r["record_id"] == record["record"]) else {
        return vec![];
    };
    let p = &row["definition"];
    [
        ("Holder", &p["holder"]),
        ("Proposition", &p["proposition"]),
        ("Message", &p["acquisition"]["basis"]["communication"]),
        (
            "Interpretation",
            &p["acquisition"]["basis"]["interpretation"],
        ),
        ("Relation", &p["relationCardinality"]["relation"]),
    ]
    .into_iter()
    .filter_map(|(label, r)| {
        r["record"]
            .as_str()
            .map(|id| format!("{label}: {}", affected_label(id, choices)))
    })
    .collect()
}
#[component]
pub fn ValidationReview(value: Value, choices: Vec<Value>) -> Element {
    // The restricted envelope has no author findings. Ignore even unexpected
    // attached fields rather than deriving any output from concealed data.
    if value["kind"] != "evaluated" {
        return rsx! {section{class:"panel",h3{"Validation unavailable in this view"}p{"Use an authorized author view to review findings and repair the draft. Restricted information remains concealed."}}};
    }
    let execution = &value["execution"];
    let findings = execution["findings"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    rsx! {section{class:"panel",h3{"Findings and repairs"}
        p{{format!("Execution coverage: {}",execution["coverage"].as_str().unwrap_or("Unavailable"))}}
        p{"For a finding below, inspect the affected records, remove and replace the affected draft operation, then revise and validate again. Changing canon requires reopening the current context and rebasing the draft. Acknowledging an issue does not waive a blocking policy."}
        if findings.is_empty(){p{"No findings returned. Check execution coverage before approval."}}
        for (i,finding) in findings.into_iter().enumerate(){article{key:"{i}",class:"panel",
            h4{{caption(finding["outcome"].as_str().unwrap_or("unavailable"))}}
            p{{finding["message"].as_str().unwrap_or("Inspect the policy and evidence before deciding how to repair this draft.")}}
            p{{format!("Policy: {}",affected_label(finding["rule_id"].as_str().unwrap_or("Unavailable"),&choices))}}
            p{{format!("Coverage: {}",finding["coverage"].as_str().unwrap_or("Unavailable"))}}
            h5{"Affected records"}
            ul{for record in finding["records"].as_array().cloned().unwrap_or_default(){li{{affected_label(record["record"].as_str().unwrap_or("Unavailable"),&choices)} ul{for label in related_labels(&record,&choices){li{"{label}"}}}}}}
            details{summary{"Exact evidence versions and finding reference"}ReadValue{value:serde_json::json!({"evidence":finding["evidence"],"fingerprint":finding["fingerprint"]})}}
        }}
        if execution["unsupported_capabilities"].as_array().is_some_and(|a|!a.is_empty()){
            h4{"Unresolved execution requirements"}p{"These capabilities were not established. Correct the supporting draft or policy before certification."}ReadValue{value:execution["unsupported_capabilities"].clone()}
        }
        if execution["opposing_evidence"].as_array().is_some_and(|a|!a.is_empty()){
            details{open:true,summary{"Opposing evidence requiring review"}ReadValue{value:execution["opposing_evidence"].clone()}}
        }
    }}
}
