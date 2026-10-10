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
        "definition_label"
        | "property_multiplicity"
        | "property_persistence"
        | "definition_parent" => {
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
            } else if action == "property_persistence" {
                if selected["payload"]["record_kind"] != "property"
                    || ![
                        "unspecified",
                        "persistent_until_changed",
                        "explicit_interval",
                    ]
                    .contains(&value)
                {
                    return Err("Choose a supported property persistence setting.".into());
                }
                replacement["persistence"] = json!(value);
            } else {
                if selected["payload"]["record_kind"] != "property"
                    || !["single", "multiple"].contains(&value)
                {
                    return Err("Choose a multiplicity.".into());
                }
                replacement["multiplicity"] = json!(value);
            }
            op["replacement"] = replacement;
        }
        "power_value" | "power_scope" | "power_start" | "power_end" => {
            if selected["payload"]["record_kind"] != "item_power" || reason.trim().is_empty() {
                return Err("Inspect a grant and explain the correction; its item and property targets stay unchanged.".into());
            }
            op["kind"] = json!("revise_item_power");
            let mut replacement = selected["payload"].clone();
            replacement.as_object_mut().unwrap().remove("record_kind");
            if action == "power_value" {
                let original = &selected["payload"]["value"];
                let form = super::claim_editor::Form {
                    kind: original["kind"].as_str().unwrap_or("").into(),
                    value: value.into(),
                    unit: original["unit"].as_str().unwrap_or("").into(),
                    ..Default::default()
                };
                replacement["value"] = form.typed_value(frame, clock)?;
            } else if action == "power_scope" {
                replacement["scope"]["applicability"] = if value == "universe" {
                    json!({"kind":"universe_wide"})
                } else {
                    json!({"kind":"worlds","world_ids":[universe_domain::ids::WorldId::parse(value).map_err(|e|e.to_string())?]})
                };
            } else {
                let validity = &mut replacement["validity"];
                if validity["kind"] != "calendar_interval" {
                    return Err("Inspect a grant with an authored calendar interval to edit its start or end.".into());
                }
                let coordinate = if let Some(c) =
                    clock.filter(|c| validity["calendar"] == c.calendar.as_str())
                {
                    c.coordinate(value)?
                } else {
                    value
                        .parse::<i128>()
                        .map_err(|_| "Enter an exact tick in the grant's calendar")?
                        .to_string()
                };
                if action == "power_end" {
                    let n = coordinate
                        .parse::<i128>()
                        .map_err(|_| "Invalid grant end")?;
                    if validity["end"]["kind"] == "exact"
                        && n > validity["end"]["value"]
                            .as_str()
                            .unwrap_or("")
                            .parse::<i128>()
                            .map_err(|_| "Unresolved original end")?
                    {
                        return Err(
                            "Ending cannot extend this grant; use an explicit validity correction."
                                .into(),
                        );
                    }
                    validity["end"] = json!({"kind":"exact","value":coordinate});
                } else {
                    validity["start"] = json!({"kind":"exact","value":coordinate});
                }
            }
            op["replacement"] = replacement;
            op["rationale"] = json!(reason);
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

#[derive(Clone, Default, PartialEq)]
pub(super) struct NameForm {
    pub text: String,
    pub language: String,
    pub community: String,
    pub role: String,
    pub validity: String,
    pub start: String,
    pub end: String,
    pub end_kind: String,
}
pub(super) fn name_operation(
    frame: &Frame,
    selected: &Value,
    form: &NameForm,
    clock: Option<&Chronology>,
) -> Result<Value, String> {
    if selected["payload"]["record_kind"] != "entity" || form.text.trim().is_empty() {
        return Err("Inspect an existing entity and enter its name.".into());
    }
    let validity = match form.validity.as_str() {
        "unspecified" | "unknown" => json!({"kind":form.validity}),
        "instant" | "interval" => {
            let clock = clock.ok_or("Select an authored clock before dating a name.")?;
            let start = clock.coordinate(&form.start)?;
            if form.validity == "instant" {
                json!({"kind":"instant","at":{"kind":"exact","calendar":clock.calendar,"value":start}})
            } else {
                let end = match form.end_kind.as_str() {
                    "exact" => json!({"kind":"exact","value":clock.coordinate(&form.end)?}),
                    "unknown" | "unbounded" => json!({"kind":form.end_kind}),
                    _ => return Err("Choose an explicit end meaning.".into()),
                };
                json!({"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":start},"end":end})
            }
        }
        _ => return Err("Choose the name's temporal meaning.".into()),
    };
    let optional = |v: &str| {
        if v.trim().is_empty() {
            None
        } else {
            Some(v.trim().to_string())
        }
    };
    let typed: DomainOperation = serde_json::from_value(json!({"kind":"add_name","record":{"universe":frame.universe,"record":selected["identity"]["record_id"]},"expected_version":selected["record_version_id"],"name":{"text":form.text.trim(),"language":optional(&form.language),"community":optional(&form.community),"role":optional(&form.role),"validity":validity}})).map_err(|e|e.to_string())?;
    serde_json::to_value(typed).map_err(|e| e.to_string())
}

/// Patches only one explicitly selected role/limit field, retaining all other metadata.
pub(super) fn contract_operation(
    frame: &Frame,
    selected: &Value,
    action: &str,
    role: &str,
    value: &str,
) -> Result<Value, String> {
    let mut replacement = selected["payload"].clone();
    if replacement["record_kind"] == "relation" {
        let roles = replacement["roles"]
            .as_array_mut()
            .ok_or("Relationship roles unavailable.")?;
        let target = roles
            .iter_mut()
            .find(|r| r["name"] == role)
            .ok_or("Choose an existing declared role.")?;
        match action {
            "role_multiple" => {
                if !["single", "multiple"].contains(&value) {
                    return Err("Choose explicit local multiplicity.".into());
                }
                target["multiplicity"] = json!(value);
            }
            "role_ordered" => {
                if !["true", "false"].contains(&value) {
                    return Err("Choose explicit participant ordering.".into());
                }
                target["ordered"] = json!(value == "true");
            }
            "role_type_add" | "role_type_remove" => {
                let id = universe_domain::ids::RecordId::parse(value).map_err(|e| e.to_string())?;
                let types = target["participantTypes"]
                    .as_array_mut()
                    .ok_or("Type restrictions unavailable.")?;
                if action == "role_type_add" {
                    if !types.contains(&json!(id)) {
                        types.push(json!(id));
                    }
                } else {
                    types.retain(|t| *t != json!(id));
                }
            }
            "role_type_clear" => target["participantTypes"] = json!([]),
            _ => return Err("Choose a supported relationship contract change.".into()),
        }
    } else if replacement["record_kind"] == "rule" && replacement["relationCardinality"].is_object()
    {
        let limit = &mut replacement["relationCardinality"];
        match action {
            "relation_maximum" => {
                limit["maximum"] = json!(value
                    .parse::<u32>()
                    .map_err(|_| "Enter an explicit nonnegative whole maximum.")?)
            }
            "relation_group_subject" => limit["grouping"] = json!({"kind":"subject"}),
            "relation_group_role" => {
                if value.trim().is_empty() {
                    return Err("Choose a declared grouping role.".into());
                }
                limit["grouping"] = json!({"kind":"role","role":value});
            }
            "relation_counted_role" => {
                if value.trim().is_empty() {
                    return Err("Choose a declared counted role.".into());
                }
                limit["countedRole"] = json!(value);
            }
            _ => return Err("Choose a supported relationship maximum change.".into()),
        }
    } else {
        return Err("Inspect a relationship or its authored maximum.".into());
    }
    let typed:DomainOperation=serde_json::from_value(json!({"kind":"revise_definition","record":{"universe":frame.universe,"record":selected["identity"]["record_id"]},"expected_version":selected["record_version_id"],"replacement":replacement})).map_err(|e|e.to_string())?;
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
    let mut role = use_signal(String::new);
    let mut name = use_signal(NameForm::default);
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
        "item_power" => vec![
            ("", "Keep grant"),
            ("power_value", "Correct granted value"),
            ("power_scope", "Correct grant scope"),
            ("power_start", "Correct interval start"),
            ("power_end", "End grant duration"),
        ],
        "property" => vec![
            ("", "Choose a change"),
            ("definition_label", "Revise display label"),
            ("property_multiplicity", "Revise multiplicity"),
            ("property_persistence", "Revise persistence"),
        ],
        "entity_type" => vec![
            ("", "Choose a change"),
            ("definition_label", "Revise display label"),
            ("definition_parent", "Correct type ancestry"),
        ],
        "relation" => vec![
            ("", "Keep contract"),
            ("definition_label", "Revise display label"),
            ("role_multiple", "Change local role multiplicity"),
            ("role_ordered", "Change participant ordering"),
            ("role_type_add", "Add participant type restriction"),
            ("role_type_remove", "Remove participant type restriction"),
            ("role_type_clear", "Explicitly clear type restrictions"),
        ],
        "rule" if selected["payload"]["relationCardinality"].is_object() => vec![
            ("", "Keep maximum contract"),
            ("relation_maximum", "Change cross-occurrence maximum"),
            ("relation_group_subject", "Group by subject"),
            ("relation_group_role", "Group by declared role"),
            ("relation_counted_role", "Change counted role"),
        ],
        "unit" | "calendar" | "value_definition" | "rule" => vec![
            ("", "Choose a change"),
            ("definition_label", "Revise display label"),
        ],
        "assertion" => vec![
            ("", "Choose a change"),
            (
                "end_assertion_at",
                "End fact duration; retain earlier support",
            ),
            (
                "retract_assertion",
                "Withdraw fact support; do not assert the opposite",
            ),
        ],
        _ => return rsx! {},
    };
    rsx! {details{summary{"Change the inspected record"}
        p{"Changes enter the draft and require validation, exact approval and commit. Earlier revisions remain available."}
        super::select::RichSelect{id:"inspector-action",disabled,value:action(),options:super::select::choices(&options),onchange:move|e:super::select::SelectionEvent|{action.set(e.value());name.set(NameForm::default());value.set(String::new());role.set(String::new());reason.set(String::new());error.set(String::new());}}
        if action()=="add_name" {
            p{"This adds a name to the selected identity; it does not merge identities or establish who knows the name."}
            label{r#for:"inspector-name-text","Name"}input{id:"inspector-name-text",disabled,value:name.read().text.clone(),oninput:move|e|name.write().text=e.value()}
            label{r#for:"inspector-name-language","Language (optional)"}input{id:"inspector-name-language",disabled,value:name.read().language.clone(),oninput:move|e|name.write().language=e.value()}
            label{r#for:"inspector-name-community","Community (optional)"}input{id:"inspector-name-community",disabled,value:name.read().community.clone(),oninput:move|e|name.write().community=e.value()}
            label{r#for:"inspector-name-role","Name role (optional)"}input{id:"inspector-name-role",disabled,value:name.read().role.clone(),oninput:move|e|name.write().role=e.value()}
            label{r#for:"inspector-name-validity","When this name applies"}
            super::select::RichSelect{id:"inspector-name-validity",disabled,value:name.read().validity.clone(),options:super::select::choices(&[("","Choose temporal meaning"),("unspecified","No temporal claim"),("unknown","Time unknown"),("instant","Named-calendar instant"),("interval","Explicit interval")]),onchange:move|e:super::select::SelectionEvent|name.write().validity=e.value()}
            if ["instant","interval"].contains(&name.read().validity.as_str()){
                p{{clock.as_ref().map(|c|match &c.system {universe_domain::chronology::ClockSystem::Fictional{tick_label,..}=>format!("Use exact {tick_label} in the selected authored clock."),universe_domain::chronology::ClockSystem::Gregorian{..}=>"Use an exact dated timestamp in the selected authored clock.".into()}).unwrap_or("No authored clock selected.".into())}}
                label{r#for:"inspector-name-start","Start / instant"}input{id:"inspector-name-start",disabled,value:name.read().start.clone(),oninput:move|e|name.write().start=e.value()}
            }
            if name.read().validity=="interval"{
                p{"Intervals include the start and exclude the end. Unknown is different from unbounded."}
                label{r#for:"inspector-name-end-kind","End meaning"}
                super::select::RichSelect{id:"inspector-name-end-kind",disabled,value:name.read().end_kind.clone(),options:super::select::choices(&[("","Choose end"),("exact","Exact end"),("unknown","Unknown end"),("unbounded","No end")]),onchange:move|e:super::select::SelectionEvent|name.write().end_kind=e.value()}
                if name.read().end_kind=="exact"{label{r#for:"inspector-name-end","Exclusive end"}input{id:"inspector-name-end",disabled,value:name.read().end.clone(),oninput:move|e|name.write().end=e.value()}}
            }
        }else if action().starts_with("role_") {
            p{"Only this selected field changes. Other roles, types, order, scope and time stay authored. Local multiplicity is separate from cross-occurrence maxima."}
            label{r#for:"inspector-relation-role","Declared role"}
            super::select::RichSelect{id:"inspector-relation-role",disabled,value:role(),options:{let mut options=vec![super::select::Choice::new("","Choose role")];for r in selected["payload"]["roles"].as_array().into_iter().flatten(){if let Some(name)=r["name"].as_str(){options.push(super::select::Choice::new(name,name));}}options},onchange:move|e:super::select::SelectionEvent|role.set(e.value())}
            if action()=="role_multiple" || action()=="role_ordered" {
                label{r#for:"inspector-role-value","Explicit new value"}
                super::select::RichSelect{id:"inspector-role-value",disabled,value:value(),options:if action()=="role_multiple"{super::select::choices(&[("","Keep until selected"),("single","Single participant"),("multiple","Multiple participants")])}else{super::select::choices(&[("","Keep until selected"),("true","Ordered"),("false","Unordered")])},onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
            }else if action()!="role_type_clear"{
                label{r#for:"inspector-role-type","Authored participant type"}
                super::select::RichSelect{id:"inspector-role-type",disabled,value:value(),options:super::select::record_choices(&choices,&["entity_type"],"Choose type"),onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
            }else{p{"This explicitly removes all type restrictions from only the selected role."}}
        }else if action().starts_with("relation_"){
            p{"Only the selected maximum/grouping field changes. Existing scope, validity and other policy metadata stay unchanged; affected relationships are rechecked."}
            if action()=="relation_maximum"{label{r#for:"inspector-relation-maximum","Maximum distinct participants"}input{id:"inspector-relation-maximum",disabled,value,oninput:move|e|value.set(e.value())}}
            else if action()!="relation_group_subject"{
                label{r#for:"inspector-limit-role","Declared relationship role"}
                super::select::RichSelect{id:"inspector-limit-role",disabled,value:value(),options:{let relation=&selected["payload"]["relationCardinality"]["relation"]["record"];let mut options=vec![super::select::Choice::new("","Choose role")];for r in choices.iter().find(|c|c["record_id"]==*relation).and_then(|c|c["definition"]["roles"].as_array()).into_iter().flatten(){if let Some(name)=r["name"].as_str(){options.push(super::select::Choice::new(name,name));}}options},onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
            }else{p{"Explicitly group by the relationship subject."}}
        }else if action()=="refine_classification"{
            p{"An unclassified instance can receive its first classification. Later refinements must use the same classification or a descendant; unrelated changes require an explicit correction."}
            label{r#for:"inspector-type","Classification"}
            super::select::RichSelect{id:"inspector-type",disabled,value:value(),options:super::select::record_choices(&choices,&["entity_type"],"Choose a type"),onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
        }else if action()=="definition_parent"{
            p{"This revises the type's ancestry; it does not reclassify or replace its instances. Existing inheritance, initialization and action constraints are rechecked."}
            label{r#for:"inspector-parent","Authored parent"}
            super::select::RichSelect{id:"inspector-parent",disabled,value:value(),options:{let mut options=super::select::record_choices(&choices,&["entity_type"],"Choose explicitly");options.insert(1,super::select::Choice::new("none","Explicit root — no parent"));options},onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
        }else if action().starts_with("power_"){
            p{"Only the selected grant field changes. Item, holder property, ability property, represented context and calendar stay unchanged; author contract review and separate approval are required."}
            if action()=="power_scope"{
                label{r#for:"inspector-power-scope","Explicit grant scope"}
                super::select::RichSelect{id:"inspector-power-scope",disabled,value:value(),options:{let mut c=super::select::typed_id_choices(&choices,"world","wld_","Choose scope");c.insert(1,super::select::Choice::new("universe","Universe wide"));c},onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
            }else if action()=="power_value" && selected["payload"]["value"]["kind"]=="boolean"{
                label{r#for:"inspector-power-value","Granted value"}
                super::select::RichSelect{id:"inspector-power-value",disabled,value:value(),options:super::select::choices(&[("","Keep until selected"),("true","True"),("false","False")]),onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
            }else if action()=="power_value" && selected["payload"]["value"]["kind"]=="entity_ref"{
                label{r#for:"inspector-power-object","Granted object"}
                super::select::RichSelect{id:"inspector-power-object",disabled,value:value(),options:super::select::record_choices(&choices,&["entity"],"Choose object"),onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
            }else{label{r#for:"inspector-power-value",if action()=="power_value"{"Granted value"}else{"Explicit date or tick in the grant's calendar"}}input{id:"inspector-power-value",disabled,value,oninput:move|e|value.set(e.value())}}
        }else if action()=="property_persistence"{
            p{"Only the default for new facts changes. Existing assertion lifetimes and other property settings stay authored; affected facts and events are rechecked."}
            label{r#for:"inspector-persistence","Persistence"}
            super::select::RichSelect{id:"inspector-persistence",disabled,value:value(),options:super::select::choices(&[("","Keep until selected"),("unspecified","Unspecified"),("persistent_until_changed","Until changed"),("explicit_interval","Explicit interval")]),onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
        }else if action()=="property_multiplicity"{
            label{r#for:"inspector-multiplicity","Multiplicity"}
            super::select::RichSelect{id:"inspector-multiplicity",disabled,value:value(),options:super::select::choices(&[("","Choose multiplicity"),("single","Single value"),("multiple","Multiple values")]),onchange:move|e:super::select::SelectionEvent|value.set(e.value())}
        }else if !action().is_empty()&&action()!="retract_assertion"{
            label{r#for:"inspector-value",if action()=="end_assertion_at"{"Exclusive end in this assertion’s calendar"}else{"Name or alias"}}
            input{id:"inspector-value",disabled,value,oninput:move|e|value.set(e.value())}
        }
        if action()=="end_assertion_at"{p{"This ends the authored interval; support before the end remains."}}
        if action()=="retract_assertion"{p{"This withdraws the assertion from the new revision. It does not claim the opposite; earlier revisions remain available."}}
        if action().starts_with("power_") || ["end_assertion_at","retract_assertion"].contains(&action().as_str()){
            label{r#for:"inspector-reason","Reason"}textarea{id:"inspector-reason",disabled,value:reason,oninput:move|e|reason.set(e.value())}
        }
        button{class:"secondary",disabled:disabled||action().is_empty(),onclick:move|_|match if action()=="add_name"{name_operation(&frame,&selected,&name(),clock.as_ref())}else if action().starts_with("role_")||action().starts_with("relation_"){contract_operation(&frame,&selected,&action(),&role(),&value())}else{operation(&frame,&selected,&action(),&value(),&reason(),clock.as_ref())}{Ok(op)=>{onadd.call(op);error.set(String::new());},Err(e)=>error.set(e)},"Add inspected change to draft"}
        if !error().is_empty(){p{role:"alert","{error}"}}
    }}
}
