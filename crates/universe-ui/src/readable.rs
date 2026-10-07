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
