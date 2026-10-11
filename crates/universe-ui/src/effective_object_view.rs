//! Presentation of returned effective-object evidence; no state inference.
use super::readable::{caption, ReadValue};
use dioxus::prelude::*;
use serde_json::{json, Value};
fn text(v: &Value) -> &str {
    v.as_str().unwrap_or("Not reported")
}
fn name(r: &Value) -> String {
    let p = &r["payload"];
    p["labels"]["en"]
        .as_str()
        .or_else(|| p["names"][0]["text"].as_str())
        .or_else(|| p["key"].as_str())
        .or_else(|| p["selector"].as_str())
        .map(str::to_string)
        .unwrap_or_else(|| {
            format!(
                "{} · {}",
                caption(p["record_kind"].as_str().unwrap_or("record")),
                text(&r["identity"]["record_id"])
            )
        })
}
fn dependency<'a>(object: &'a Value, id: &Value) -> Option<&'a Value> {
    std::iter::once(&object["identity"])
        .chain(object["ancestry"].as_array().into_iter().flatten())
        .chain(object["dependencies"].as_array().into_iter().flatten())
        .find(|r| r["identity"]["record_id"] == *id)
}
pub(super) fn reference_name(object: &Value, id: &Value) -> String {
    dependency(object, id)
        .map(name)
        .unwrap_or_else(|| format!("Record {}", text(id)))
}
fn applicability(v: &Value) -> &'static str {
    match v.as_bool() {
        Some(true) => "Applies in this query",
        Some(false) => "Does not apply in this query",
        None => "Applicability unresolved",
    }
}
pub(super) fn value_text(v: &Value, object: &Value) -> String {
    match v["kind"].as_str().unwrap_or_default() {
        "integer" | "decimal" => text(&v["digits"]).into(),
        "text" => text(&v["text"]).into(),
        "boolean" => match v["value"].as_bool() {
            Some(true) => "True",
            Some(false) => "False",
            None => "Not reported",
        }
        .into(),
        "rational" => format!("{}/{}", text(&v["numerator"]), text(&v["denominator"])),
        "quantity" => {
            let unit = v["unit"]
                .as_str()
                .and_then(|unit| unit.strip_prefix("unit_"))
                .map(|suffix| json!(format!("rec_{suffix}")))
                .and_then(|id| dependency(object, &id).map(name))
                .unwrap_or_else(|| text(&v["unit"]).into());
            format!("{} {unit}", value_text(&v["value"], object))
        }
        "range" => format!(
            "{}{} to {}{}",
            if v["lower_inclusive"] == true {
                "["
            } else {
                "("
            },
            value_text(&v["lower"], object),
            value_text(&v["upper"], object),
            if v["upper_inclusive"] == true {
                "]"
            } else {
                ")"
            }
        ),
        "entity_ref" | "record_ref" | "proposition_ref" => {
            format!("Record {}", text(&v["ref"]["record"]))
        }
        "enum" => text(&v["key"]).into(),
        "sequence" | "set" => format!(
            "{}: {}",
            caption(text(&v["kind"])),
            v["items"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|v| value_text(v, object))
                .collect::<Vec<_>>()
                .join(", ")
        ),
        _ => format!("{} · see exact value details", caption(text(&v["kind"]))),
    }
}
fn bound(v: &Value) -> String {
    match v["kind"].as_str() {
        Some("exact") => text(&v["value"]).into(),
        Some("unbounded") => "unbounded".into(),
        Some("unknown") => "unknown".into(),
        _ => "uncertain bound · see details".into(),
    }
}
fn time_text(v: &Value) -> String {
    match v["kind"].as_str() {
        Some("timeless") => "All authored validities; no temporal claim".into(),
        Some("at") => time_text(&v["time"]),
        Some("instant") => format!("At {}", time_text(&v["at"])),
        Some("unknown") => "Time unknown".into(),
        Some("exact") => format!("{} in calendar {}", text(&v["value"]), text(&v["calendar"])),
        Some("calendar_interval") | Some("interval") => format!(
            "{} to {} (end exclusive) in calendar {}",
            bound(&v["start"]),
            bound(&v["end"]),
            text(&v["calendar"])
        ),
        Some("unspecified") => "Unspecified".into(),
        Some("at_event") => format!("{} event {}", text(&v["side"]), text(&v["event"]["record"])),
        _ => format!("{} · see exact time details", caption(text(&v["kind"]))),
    }
}
#[component]
fn Unknowns(values: Value) -> Element {
    rsx! {ul{for value in values.as_array().into_iter().flatten(){li{{caption(text(value).split(':').next().unwrap_or("Unknown"))}}}}}
}
#[component]
fn EvidenceLane(title: String, note: String, rows: Value, object: Value) -> Element {
    rsx! {section{class:"panel",h4{"{title}"}p{"{note}"}
        if rows.as_array().is_none_or(|r|r.is_empty()){p{"No visible evidence returned. This does not establish absence."}}
        for (i,row) in rows.as_array().into_iter().flatten().enumerate(){article{key:"{i}",
            if row["record"]["payload"]["record_kind"]=="assertion"{
                h5{{reference_name(&object,&dependency(&object,&row["record"]["payload"]["proposition"]["record"]).map(|r|r["payload"]["predicate"]["record"].clone()).unwrap_or(Value::Null))}}
                if let Some(p)=dependency(&object,&row["record"]["payload"]["proposition"]["record"]){
                    if dependency(&object,&p["payload"]["predicate"]["record"]).is_some_and(|r|r["payload"]["record_kind"]=="relation") {
                        p{{format!("Declared participants: {}",p["payload"]["roles"].as_array().map(|roles|if roles.is_empty(){"None declared".into()}else{roles.iter().map(|role|format!("{}: {}",text(&role["role"]),reference_name(&object,&role["participant"]["record"]))).collect::<Vec<_>>().join("; ")}).unwrap_or("Not returned".into()))}}
                    }else{p{{format!("Declared value: {}",value_text(&p["payload"]["value"],&object))}}}
                }
                else{p{"Proposition details were not returned; value remains unavailable."}}
                p{{format!("{} evidence · precision {}",caption(text(&row["record"]["payload"]["polarity"])),caption(text(&row["record"]["payload"]["precision"])))}}
                p{{format!("Validity: {}",time_text(&row["record"]["payload"]["validity"]))}}
                if row["record"]["payload"]["alternatives"].as_array().is_some_and(|a|!a.is_empty()){p{{format!("Authored alternatives: {}",row["record"]["payload"]["alternatives"].as_array().unwrap().iter().map(|v|value_text(v,&object)).collect::<Vec<_>>().join("; "))}}}
            }else{
                h5{{name(&row["record"])}}
                if row["record"]["payload"]["record_kind"]=="rule"{p{{format!("{} · publication policy {}",caption(text(&row["record"]["payload"]["kind"])),caption(text(&row["record"]["payload"]["commitPolicy"])))}}}
                if row["record"]["payload"]["record_kind"]=="action_definition"{ul{for req in row["record"]["payload"]["requirements"].as_array().into_iter().flatten(){li{{format!("Role {} requires {}",text(&req["role"]),reference_name(&object,&req["predicate"]["record"]))}}}}}
            }
            p{{applicability(&row["applicability"])}}
            Unknowns{values:row["unknowns"].clone()}
            details{summary{"Exact records, qualification and references"}ReadValue{value:json!({"evidence":row,"proposition":dependency(&object,&row["record"]["payload"]["proposition"]["record"])})}}
        }}
    }}
}
#[component]
fn ObjectView(object: Value, derived: Value) -> Element {
    if object["coverage"] == "restricted" {
        return rsx! {p{"Object evidence is restricted in this view."}};
    }
    rsx! {article{class:"panel",h3{{name(&object["identity"])}}
        p{{format!("Object coverage: {}",caption(text(&object["coverage"])))}}
        for (heading,status) in [("Active names",Some(true)),("Names not active at selected time",Some(false)),("Names with unresolved applicability",None)] {
            section{h4{"{heading}"}
                for row in object["contextual_names"].as_array().into_iter().flatten().filter(|r|r["applicability"].as_bool()==status){
                    p{{format!("{} · language: {} · community: {} · role: {}",text(&row["name"]["text"]),row["name"]["language"].as_str().unwrap_or("Unspecified"),row["name"]["community"].as_str().unwrap_or("Unspecified"),row["name"]["role"].as_str().unwrap_or("Unspecified"))}}
                    p{{time_text(&row["name"]["validity"])}}
                }
            }
        }
        section{h4{"Identity and classification"}
            if object["identity"]["payload"]["record_kind"]=="entity_type" {
                p{{format!("Reusable definition: {}; parent: {}",name(&object["identity"]),caption(text(&object["identity"]["payload"]["parentResolution"])))}}
                if !object["identity"]["payload"]["parent"].is_null(){p{{reference_name(&object,&object["identity"]["payload"]["parent"])}}}
            }else{p{{format!("Classification: {}",caption(text(&object["identity"]["payload"]["classificationResolution"])))}}}
            if !object["identity"]["payload"]["classification"].is_null(){p{{reference_name(&object,&object["identity"]["payload"]["classification"])}}}
            details{summary{"Exact identity and classification record"}ReadValue{value:object["identity"].clone()}}
        }
        section{h4{"Definition ancestry"}p{{format!("Ancestry complete: {}",match object["ancestry_complete"].as_bool(){Some(true)=>"Yes",Some(false)=>"No",None=>"Not reported"})}}
            ol{for r in object["ancestry"].as_array().into_iter().flatten(){li{{name(r)}details{summary{"Exact ancestor record"}ReadValue{value:r.clone()}}}}}
        }
        EvidenceLane{title:"Shared definition attributes",note:"Continuing definition evidence, kept separate from instance stock.",rows:object["shared_attributes"].clone(),object:object.clone()}
        EvidenceLane{title:"Instance facts",note:"Asserted instance state. Qualified, opposing or unresolved evidence is not collapsed to a single current value.",rows:object["instance_facts"].clone(),object:object.clone()}
        section{h4{"Derived abilities and state"}
            p{"Returned derived values apply to this query; they remain separate from authored facts. Review coverage, conflicts and unknowns."}
            if derived.as_array().is_none_or(|rows|rows.is_empty()){p{"No visible derived values returned. This does not establish absence."}}
            for row in derived.as_array().into_iter().flatten(){article{
                p{{format!("Derived {}: {}",reference_name(&object,&row["predicate"]["record"]),value_text(&row["value"],&object))}}
                details{summary{"Exact derivation and evidence"}ReadValue{value:row.clone()}}
            }}
        }
        EvidenceLane{title:"Initial-value candidates",note:"Authored starting candidates; these are not current stock and do not refill an instance.",rows:object["initial_value_candidates"].clone(),object:object.clone()}
        section{class:"panel",h4{"Initialization history"}p{{format!("History coverage: {}",caption(text(&object["initialization_history_coverage"])))}}
            if object["initialization_history_coverage"]=="restricted"{p{"Initialization history is restricted. No receipt details are shown."}}
            else{
                if object["initialization_receipts"].as_array().is_none_or(|r|r.is_empty()){p{"No visible initialization receipts returned. This does not establish that initialization never occurred."}}
                for r in object["initialization_receipts"].as_array().into_iter().flatten(){article{p{{format!("Initialized {} in revision {}",reference_name(&object,&r["property"]),text(&r["revision"]))}}details{summary{"Exact initialization receipt and source revision"}ReadValue{value:r.clone()}}}}
            }
        }
        EvidenceLane{title:"Behavioral requirements",note:"Declared requirements describe possible behavior; they do not establish that an action occurred.",rows:object["behavioral_requirements"].clone(),object:object.clone()}
        EvidenceLane{title:"Applicable policies",note:"Returned policy evidence includes unresolved applicability. A listed policy is not a passing validation.",rows:object["rules"].clone(),object:object.clone()}
        section{class:"panel",h4{"Conflicts"}
            if object["conflicts"].as_array().is_none_or(|r|r.is_empty()){p{"No visible conflicts returned; review coverage and unknowns."}}
            for conflict in object["conflicts"].as_array().into_iter().flatten(){article{p{{format!("{} · {} · {}",reference_name(&object,&conflict["predicate"]),if conflict["initial_values"]==true{"Initial candidates"}else{"Shared / instance evidence"},applicability(&conflict["applicability"]))}}details{summary{"Exact conflicting assertion versions"}ReadValue{value:conflict.clone()}}}}
        }
        section{class:"panel",h4{"Unknowns"}Unknowns{values:object["unknowns"].clone()}details{summary{"Exact unknown markers"}ReadValue{value:object["unknowns"].clone()}}}
        details{summary{"Exact returned dependencies"}ReadValue{value:object["dependencies"].clone()}}
    }}
}
#[component]
pub fn EffectiveState(response: Value) -> Element {
    let state = &response["result"];
    rsx! {section{class:"panel",h3{"Effective object state"}
        dl{dt{"Queried revision"}dd{{text(&response["frame"]["revision"])}}
            dt{"Represented context"}dd{{text(&response["frame"]["context"]["record"])}}
            dt{"World focus"}dd{{response["world_focus"].as_str().unwrap_or("No world focus")}}
            dt{"Queried time"}dd{{time_text(&response["frame"]["time"])}}
            dt{"Perspective"}dd{ReadValue{value:response["frame"]["perspective"].clone()}}
            dt{"Coverage"}dd{{caption(text(&state["coverage"]))}}
            dt{"Delivery complete"}dd{{match response["delivery"]["complete"].as_bool(){Some(true)=>"Yes",Some(false)=>"No",None=>"Not reported"}}}
        }
        p{"Only returned evidence is shown. Empty lists do not establish absence; shared definitions and initial candidates are separate from current stock."}
        details{summary{"Exact queried frame and authorization scope"}ReadValue{value:json!({"frame":response["frame"],"world_focus":response["world_focus"],"authorization_scope":response["authorization_scope"],"delivery":response["delivery"]})}}
        if state["coverage"]=="restricted"{p{"State evidence is restricted in this view."}}
        else{
            if state["objects"].as_array().is_none_or(|o|o.is_empty()){p{"No visible effective objects returned."}}
            for object in state["objects"].as_array().into_iter().flatten(){ObjectView{object:object.clone(),derived:Value::Array(state["derived"].as_array().into_iter().flatten().filter(|row|row["subject"]["record"]==object["identity"]["identity"]["record_id"]).cloned().collect())}}
            if !state["unsupported_capabilities"].is_null(){section{h4{"State limitations"}ReadValue{value:state["unsupported_capabilities"].clone()}}}
            details{summary{"Other returned state evidence and exact references"}ReadValue{value:json!({"derived":state["derived"],"epistemic":state["epistemic"],"chronology":state["chronology"],"unresolved_assertion_ids":state["unresolved_assertion_ids"],"assertions":state["assertions"],"propositions":state["propositions"],"completeness":state["completeness"]})}}
        }
    }}
}
#[cfg(test)]
#[path = "effective_object_tests.rs"]
pub(crate) mod tests;
