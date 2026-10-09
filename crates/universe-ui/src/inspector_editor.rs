//! Version-bound inspector edits. Every action creates a reviewable operation.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{chronology::Chronology, records::DomainOperation, Frame};

pub(super) fn operation(
    frame: &Frame,
    selected: &Value,
    action: &str,
    value: &str,
    reason: &str,
    clock: Option<&Chronology>,
) -> Result<Value, String> {
    if selected["payload"]["record_kind"] == "assertion"
        && !selected["payload"]["establishedBy"].is_null()
    {
        return Err(
            "Correct the establishing event; generated assertions are recompiled by the service."
                .into(),
        );
    }
    if value.trim().is_empty() && action != "retract_assertion" {
        return Err("Enter a value before adding this change.".into());
    }
    let mut op = json!({"kind":action,"record":{"universe":frame.universe,"record":selected["identity"]["record_id"]},"expected_version":selected["record_version_id"]});
    match action {
        "definition_label" | "property_multiplicity" | "definition_parent" => {
            op["kind"] = json!("revise_definition");
            let mut replacement = selected["payload"].clone();
            if action == "definition_label" {
                replacement["labels"]["en"] = json!(value);
            } else if action == "definition_parent" {
                if selected["payload"]["record_kind"] != "entity_type" {
                    return Err("Inspect a type before changing ancestry.".into());
                }
                replacement["parent"] = if value == "none" {
                    Value::Null
                } else {
                    json!(universe_domain::ids::RecordId::parse(value).map_err(|e| e.to_string())?)
                };
                replacement["parentResolution"] =
                    json!(if value == "none" { "root" } else { "resolved" });
            } else {
                if !["single", "multiple"].contains(&value) {
                    return Err("Choose a multiplicity.".into());
                }
                replacement["multiplicity"] = json!(value);
            }
            op["replacement"] = replacement;
        }
        "add_name" => {
            op["name"] = json!({"text":value,"language":null,"community":null,"role":null,"validity":{"kind":"unspecified"}})
        }
        "refine_classification" => op["entity_type"] = json!(value),
        "rename_world_selector" => op["new_selector"] = json!(value),
        "add_world_alias" => op["alias"] = json!(value),
        "retract_assertion" => {
            if reason.trim().is_empty() {
                return Err("Explain why this assertion is being retracted.".into());
            }
            op["rationale"] = json!(reason);
        }
        "end_assertion_at" => {
            if reason.trim().is_empty() {
                return Err("Explain why this assertion ends here.".into());
            }
            let validity = &selected["payload"]["validity"];
            if validity["kind"] != "calendar_interval" {
                return Err("Ending requires an existing named-calendar interval.".into());
            }
            let coordinate = if let Some(clock) =
                clock.filter(|c| validity["calendar"] == c.calendar.as_str())
            {
                clock.coordinate(value)?
            } else {
                value
                    .parse::<i128>()
                    .map_err(|_| "Enter an exact tick in this assertion's calendar.")?
                    .to_string()
            };
            op["at"] = json!({"kind":"exact","calendar":validity["calendar"],"value":coordinate});
            op["basis"] = json!({"kind":"author_decision","note":reason});
        }
        _ => return Err("Choose a supported change.".into()),
    }
    let typed: DomainOperation = serde_json::from_value(op).map_err(|e| e.to_string())?;
    serde_json::to_value(typed).map_err(|e| e.to_string())
}

#[component]
pub fn InspectorEditor(
    frame: Frame,
    selected: Value,
    choices: Vec<Value>,
    clock: Option<Chronology>,
    disabled: bool,
    onadd: EventHandler<Value>,
) -> Element {
    let mut action = use_signal(String::new);
    let mut value = use_signal(String::new);
    let mut reason = use_signal(String::new);
    let mut error = use_signal(String::new);
    if selected["payload"]["record_kind"] == "assertion"
        && !selected["payload"]["establishedBy"].is_null()
    {
        return rsx! {p{"Correct the establishing event. Its generated assertions cannot be edited directly."}};
    }
    let options = match selected["payload"]["record_kind"]
        .as_str()
        .unwrap_or_default()
    {
        "entity" => vec![
            ("", "Choose a change"),
            ("add_name", "Add a contextual name"),
            ("refine_classification", "Set or refine classification"),
        ],
        "world" => vec![
            ("", "Choose a change"),
            ("rename_world_selector", "Rename this world"),
            ("add_world_alias", "Add a world alias"),
        ],
        "property" => vec![
            ("", "Choose a change"),
            ("definition_label", "Revise display label"),
            ("property_multiplicity", "Revise multiplicity"),
        ],
        "entity_type" => vec![
            ("", "Choose a change"),
            ("definition_label", "Revise display label"),
            ("definition_parent", "Correct type ancestry"),
        ],
        "relation" | "unit" | "calendar" | "value_definition" | "rule" => vec![
            ("", "Choose a change"),
            ("definition_label", "Revise display label"),
        ],
        "assertion" => vec![
            ("", "Choose a change"),
            ("end_assertion_at", "End this assertion at a time"),
            ("retract_assertion", "Retract this assertion"),
        ],
        _ => return rsx! {},
    };
    rsx! {details{summary{"Change the inspected record"}
        p{"Changes enter the draft and require validation, exact approval and commit. Earlier revisions remain available."}
        super::select::RichSelect{id:"inspector-action",disabled,value:action(),options:super::select::choices(&options),onchange:move|e:super::select::SelectionEvent|{action.set(e.value());value.set(String::new());reason.set(String::new());error.set(String::new());}}
        if action()=="refine_classification"{
            p{"An unclassified instance can receive its first classification. Later refinements must use the same classification or a descendant; unrelated changes require an explicit correction."}
            label{r#for:"inspector-type","Classification"}
            super::select::RichSelect{id:"inspector-type",disabled,value:value(),options:super::select::record_choices(&choices,&["entity_type"],"Choose a type"),onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
        }else if action()=="definition_parent"{
            p{"This revises the type's ancestry; it does not reclassify or replace its instances. Existing inheritance, initialization and action constraints are rechecked."}
            label{r#for:"inspector-parent","Authored parent"}
            super::select::RichSelect{id:"inspector-parent",disabled,value:value(),options:{let mut options=super::select::record_choices(&choices,&["entity_type"],"Choose explicitly");options.insert(1,super::select::Choice::new("none","Explicit root — no parent"));options},onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
        }else if action()=="property_multiplicity"{
            label{r#for:"inspector-multiplicity","Multiplicity"}
            super::select::RichSelect{id:"inspector-multiplicity",disabled,value:value(),options:super::select::choices(&[("","Choose multiplicity"),("single","Single value"),("multiple","Multiple values")]),onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
        }else if !action().is_empty()&&action()!="retract_assertion"{
            label{r#for:"inspector-value",if action()=="end_assertion_at"{"Exclusive end in this assertion’s calendar"}else{"Name or alias"}}
            input{id:"inspector-value",disabled,value,oninput:move|e|value.set(e.value())}
        }
        if ["end_assertion_at","retract_assertion"].contains(&action().as_str()){
            label{r#for:"inspector-reason","Reason"}textarea{id:"inspector-reason",disabled,value:reason,oninput:move|e|reason.set(e.value())}
        }
        button{class:"secondary",disabled:disabled||action().is_empty(),onclick:move|_|match operation(&frame,&selected,&action(),&value(),&reason(),clock.as_ref()){Ok(op)=>{onadd.call(op);error.set(String::new());},Err(e)=>error.set(e)},"Add inspected change to draft"}
        if !error().is_empty(){p{role:"alert","{error}"}}
    }}
}
