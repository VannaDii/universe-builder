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
#[component]
pub fn DraftChanges(operations: String, disabled: bool, onremove: EventHandler<usize>) -> Element {
    let Ok(ops) = serde_json::from_str::<Vec<Value>>(&operations) else {
        return rsx! {p{role:"alert","This saved draft cannot be decoded. Its stored version is preserved; reopen a valid saved draft before editing."}};
    };
    rsx! {div{class:"draft-changes",
        h3{"Draft changes"}
        if ops.is_empty(){p{"No changes added yet."}}
        for (i,op) in ops.into_iter().enumerate(){details{key:"{i}",summary{"{i + 1}. " {caption(op["kind"].as_str().unwrap_or("change"))}}ReadValue{value:op}button{class:"secondary",disabled,onclick:move|_|onremove.call(i),"Remove this change"}}}
    }}
}
