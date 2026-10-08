//! Authored action contracts enter the existing protected proposal workflow.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{
    consequences::ConsequenceContract, ids::RecordId, records::DomainOperation, Frame,
};

fn property<'a>(choices: &'a [Value], id: &str) -> Result<&'a Value, String> {
    choices
        .iter()
        .find(|c| c["kind"] == "property" && c["record_id"] == id)
        .map(|c| &c["definition"])
        .ok_or_else(|| "Choose a returned property.".into())
}
fn reference(frame: &Frame, id: &str) -> Result<Value, String> {
    Ok(json!({"universe":frame.universe,"record":RecordId::parse(id).map_err(|e|e.to_string())?}))
}
#[derive(Clone, Default, PartialEq)]
pub(super) struct FixedValue {
    pub(super) source: String,
    pub(super) value: String,
    pub(super) extra: String,
    pub(super) lower: String,
    pub(super) upper: String,
    pub(super) calendar: String,
}
impl FixedValue {
    pub(super) fn build(
        &self,
        frame: &Frame,
        choices: &[Value],
        predicate: &str,
    ) -> Result<Value, String> {
        let shape = &property(choices, predicate)?["value"];
        let v = match self.source.as_str() {
            "proposition" => choices
                .iter()
                .find(|c| {
                    c["kind"] == "proposition"
                        && c["record_id"] == self.value
                        && c["definition"]["predicate"]["record"] == predicate
                })
                .map(|c| c["definition"]["value"].clone())
                .filter(|v| !v.is_null())
                .ok_or("Choose a returned proposition with a value for this property.")?,
            "literal" => match shape["kind"].as_str().unwrap_or_default() {
                "text" => json!({"kind":"text","text":self.value}),
                "boolean" => match self.value.as_str() {
                    "true" => json!({"kind":"boolean","value":true}),
                    "false" => json!({"kind":"boolean","value":false}),
                    _ => return Err("Choose true or false explicitly.".into()),
                },
                "integer" | "decimal" => json!({"kind":shape["kind"],"digits":self.value}),
                "rational" => {
                    json!({"kind":"rational","numerator":self.value,"denominator":self.extra})
                }
                "quantity" => {
                    json!({"kind":"quantity","value":{"kind":"decimal","digits":self.value},"unit":shape["unit"]})
                }
                "entity_ref" => json!({"kind":"entity_ref","ref":reference(frame,&self.value)?}),
                "range" => {
                    if !["inclusive", "exclusive"].contains(&self.lower.as_str())
                        || !["inclusive", "exclusive"].contains(&self.upper.as_str())
                    {
                        return Err("Choose both range boundaries.".into());
                    }
                    let mut v = json!({"kind":"range","lower":{"kind":"decimal","digits":self.value},"upper":{"kind":"decimal","digits":self.extra},"lower_inclusive":self.lower=="inclusive","upper_inclusive":self.upper=="inclusive"});
                    if !shape["unit"].is_null() {
                        v["unit"] = shape["unit"].clone();
                    }
                    v
                }
                "temporal" => {
                    json!({"kind":"temporal","temporal":{"kind":"exact","calendar":self.calendar,"value":self.value}})
                }
                _ => {
                    return Err(
                        "Choose an existing typed proposition value for this property shape."
                            .into(),
                    )
                }
            },
            _ => return Err("Choose how to supply the fixed value.".into()),
        };
        let typed: universe_domain::Value =
            serde_json::from_value(v.clone()).map_err(|e| e.to_string())?;
        universe_domain::value::validate_value(&typed).map_err(|e| e.to_string())?;
        Ok(v)
    }
}
#[derive(Clone, Default, PartialEq)]
struct SlotForm {
    slot: String,
    order: String,
    presence: String,
    role: String,
    predicate: String,
    condition: String,
    condition_role: String,
    condition_property: String,
    condition_value: FixedValue,
    change: String,
    polarity: String,
    value: FixedValue,
    delta: String,
    minimum: String,
    maximum: String,
    unit: String,
    lifetime: String,
    ticks: String,
}
impl SlotForm {
    fn build(&self, frame: &Frame, choices: &[Value]) -> Result<Value, String> {
        let target = property(choices, &self.predicate)?;
        let condition = match self.condition.as_str() {
            "always" => json!({"kind":"always"}),
            "attribute_equals" => {
                json!({"kind":"attribute_equals","role":self.condition_role,"predicate":reference(frame,&self.condition_property)?,"value":self.condition_value.build(frame,choices,&self.condition_property)?})
            }
            _ => return Err("Choose a supported effect condition.".into()),
        };
        let change = match self.change.as_str() {
            "set" => {
                json!({"kind":"set","polarity":self.polarity,"value":self.value.build(frame,choices,&self.predicate)?})
            }
            "delta" => {
                let expected =
                    match (
                        target["multiplicity"].as_str(),
                        target["value"]["kind"].as_str(),
                    ) {
                        (Some("single"), Some("integer")) => json!("none"),
                        (Some("single"), Some("quantity")) => target["value"]["unit"].clone(),
                        _ => return Err(
                            "A delta requires a single integer or exact-unit quantity property."
                                .into(),
                        ),
                    };
                if json!(self.unit) != expected {
                    return Err("Choose the target property's exact unit, or explicitly choose unitless for an integer. No conversion is inferred.".into());
                }
                json!({"kind":"delta","delta":self.delta,"minimum":self.minimum,"maximum":self.maximum,"unit":if self.unit=="none"{Value::Null}else{json!(self.unit)}})
            }
            _ => return Err("Choose a fixed assignment or bounded delta.".into()),
        };
        let lifetime = match self.lifetime.as_str() {
            "until_changed" => json!({"kind":"until_changed"}),
            "ticks" => json!({"kind":"ticks","count":self.ticks}),
            _ => return Err("Choose the effect lifetime.".into()),
        };
        Ok(
            json!({"slot":self.slot,"order":self.order.parse::<u8>().map_err(|_|"Enter a slot order from 0 to 63.")?,"presence":self.presence,"target":{"role":self.role,"predicate":reference(frame,&self.predicate)?},"condition":condition,"change":change,"lifetime":lifetime}),
        )
    }
}
#[derive(Clone, Default)]
struct ActionForm {
    namespace: String,
    key: String,
    mode: String,
    role: String,
    predicate: String,
    value: FixedValue,
    consequences: String,
    slots: Vec<SlotForm>,
}
impl ActionForm {
    fn build(&self, frame: &Frame, choices: &[Value]) -> Result<Value, String> {
        if self.namespace.trim().is_empty() || self.key.trim().is_empty() {
            return Err("Name the action and its namespace.".into());
        }
        let requirements = match self.mode.as_str() {
            "ordinary" => vec![],
            "attribute" => {
                if self.role.trim().is_empty() {
                    return Err("Name the role requiring the attribute.".into());
                }
                vec![
                    json!({"role":self.role,"predicate":reference(frame,&self.predicate)?,"value":self.value.build(frame,choices,&self.predicate)?}),
                ]
            }
            _ => return Err("Choose the action requirements.".into()),
        };
        let slots = match self.consequences.as_str() {
            "none" => {
                if !self.slots.is_empty() {
                    return Err("Remove declared slots before choosing no effects.".into());
                }
                vec![]
            }
            "declared" => {
                if self.slots.is_empty() {
                    return Err("Add a declared effect slot.".into());
                }
                self.slots
                    .iter()
                    .map(|s| s.build(frame, choices))
                    .collect::<Result<Vec<_>, _>>()?
            }
            _ => return Err("Choose no effects or declared consequences explicitly.".into()),
        };
        let contract: ConsequenceContract =
            serde_json::from_value(json!({"kind":"action_consequences","slots":slots}))
                .map_err(|e| e.to_string())?;
        let op:DomainOperation=serde_json::from_value(json!({"kind":"define_action","client_ref":RecordId::generate(&mut rand::rng()),"record":{"namespace":self.namespace,"key":self.key,"labels":{"en":self.key},"requirements":requirements,"consequenceContract":contract,"scope":{"context":frame.context,"applicability":{"kind":"universe_wide"}},"validity":{"kind":"unspecified"}}})).map_err(|e|e.to_string())?;
        serde_json::to_value(op).map_err(|e| e.to_string())
    }
}
#[component]
pub(super) fn ValueControls(
    id: String,
    value: FixedValue,
    predicate: String,
    choices: Vec<Value>,
    disabled: bool,
    onchange: EventHandler<FixedValue>,
) -> Element {
    let shape = property(&choices, &predicate)
        .ok()
        .map(|p| p["value"]["kind"].as_str().unwrap_or_default().to_string())
        .unwrap_or_default();
    rsx! {fieldset{legend{"Fixed typed value"}
        label{r#for:"{id}-source","Value source"}super::select::RichSelect{id:format!("{id}-source"),disabled,value:value.source.clone(),options:super::select::choices(&[("","Choose a source"),("literal","Enter a typed value"),("proposition","Copy an existing proposition's exact value")]),onchange:{let v=value.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.source=e.value();v.value.clear();onchange.call(v);}}}
        if value.source=="proposition"{label{r#for:"{id}-value","Proposition value (does not assert its truth)"}super::select::RichSelect{id:format!("{id}-value"),disabled,value:value.value.clone(),options:super::select::record_choices(&choices.iter().filter(|c|c["kind"]=="proposition"&&c["definition"]["predicate"]["record"]==predicate&&!c["definition"]["value"].is_null()).cloned().collect::<Vec<_>>(),&["proposition"],"Choose an exact returned value"),onchange:{let v=value.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.value=e.value();onchange.call(v);}}}}
        if value.source=="literal"{
            p{{format!("Property shape: {shape}. Units are retained exactly from the property.")}}
            if shape=="boolean"{label{r#for:"{id}-value","Boolean value"}super::select::RichSelect{id:format!("{id}-value"),disabled,value:value.value.clone(),options:super::select::choices(&[("","Choose explicitly"),("true","True"),("false","False")]),onchange:{let v=value.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.value=e.value();onchange.call(v);}}}}
            else if shape=="entity_ref"{label{r#for:"{id}-value","Entity value"}super::select::RichSelect{id:format!("{id}-value"),disabled,value:value.value.clone(),options:super::select::record_choices(&choices,&["entity"],"Choose an entity"),onchange:{let v=value.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.value=e.value();onchange.call(v);}}}}
            else if ["text","integer","decimal","rational","quantity","range","temporal"].contains(&shape.as_str()){
                label{r#for:"{id}-value","Exact value (numerator or lower bound when applicable)"}input{id:"{id}-value",disabled,value:value.value.clone(),oninput:{let v=value.clone();move|e|{let mut v=v.clone();v.value=e.value();onchange.call(v);}}}
                if shape=="rational"||shape=="range"{label{r#for:"{id}-extra","Denominator / upper bound"}input{id:"{id}-extra",disabled,value:value.extra.clone(),oninput:{let v=value.clone();move|e|{let mut v=v.clone();v.extra=e.value();onchange.call(v);}}}}
                if shape=="range"{
                    label{r#for:"{id}-lower","Lower boundary"}super::select::RichSelect{id:format!("{id}-lower"),disabled,value:value.lower.clone(),options:super::select::choices(&[("","Choose boundary"),("inclusive","Inclusive"),("exclusive","Exclusive")]),onchange:{let v=value.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.lower=e.value();onchange.call(v);}}}
                    label{r#for:"{id}-upper","Upper boundary"}super::select::RichSelect{id:format!("{id}-upper"),disabled,value:value.upper.clone(),options:super::select::choices(&[("","Choose boundary"),("inclusive","Inclusive"),("exclusive","Exclusive")]),onchange:{let v=value.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.upper=e.value();onchange.call(v);}}}
                }
                if shape=="temporal"{label{r#for:"{id}-calendar","Calendar for exact tick"}super::select::RichSelect{id:format!("{id}-calendar"),disabled,value:value.calendar.clone(),options:super::select::typed_id_choices(&choices,"calendar","cal_","Choose calendar"),onchange:{let v=value.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.calendar=e.value();onchange.call(v);}}}}
            }else{p{"Use an existing typed proposition value for this shape."}}
        }
    }}
}
#[component]
fn SlotControls(
    id: String,
    slot: SlotForm,
    choices: Vec<Value>,
    disabled: bool,
    onchange: EventHandler<SlotForm>,
) -> Element {
    let properties =
        super::select::record_choices(&choices, &["property"], "Choose a target property");
    rsx! {fieldset{legend{"Declared effect slot"}
    label{r#for:"{id}-slot","Slot name"}input{id:"{id}-slot",disabled,value:slot.slot.clone(),oninput:{let s=slot.clone();move|e|{let mut s=s.clone();s.slot=e.value();onchange.call(s);}}}
    label{r#for:"{id}-order","Unique order (0–63)"}input{id:"{id}-order",disabled,value:slot.order.clone(),oninput:{let s=slot.clone();move|e|{let mut s=s.clone();s.order=e.value();onchange.call(s);}}}
    label{r#for:"{id}-role","Owning participant role"}input{id:"{id}-role",disabled,value:slot.role.clone(),oninput:{let s=slot.clone();move|e|{let mut s=s.clone();s.role=e.value();onchange.call(s);}}}
    label{r#for:"{id}-presence","Required or permitted effect"}super::select::RichSelect{id:format!("{id}-presence"),disabled,value:slot.presence.clone(),options:super::select::choices(&[("","Choose presence"),("required","Required when condition holds"),("optional","Permitted when condition holds")]),onchange:{let s=slot.clone();move|e:super::select::SelectionEvent|{let mut s=s.clone();s.presence=e.value();onchange.call(s);}}}
    label{r#for:"{id}-predicate","Target property"}super::select::RichSelect{id:format!("{id}-predicate"),disabled,value:slot.predicate.clone(),options:properties.clone(),onchange:{let s=slot.clone();move|e:super::select::SelectionEvent|{let mut s=s.clone();s.predicate=e.value();onchange.call(s);}}}
    label{r#for:"{id}-condition","Supported condition"}super::select::RichSelect{id:format!("{id}-condition"),disabled,value:slot.condition.clone(),options:super::select::choices(&[("","Choose condition"),("always","Always"),("attribute_equals","An owning role’s attribute equals a value")]),onchange:{let s=slot.clone();move|e:super::select::SelectionEvent|{let mut s=s.clone();s.condition=e.value();onchange.call(s);}}}
    if slot.condition=="attribute_equals"{
    label{r#for:"{id}-condition_role","Condition participant role"}input{id:"{id}-condition_role",disabled,value:slot.condition_role.clone(),oninput:{let s=slot.clone();move|e|{let mut s=s.clone();s.condition_role=e.value();onchange.call(s);}}}
    label{r#for:"{id}-condition_property","Condition property"}super::select::RichSelect{id:format!("{id}-condition_property"),disabled,value:slot.condition_property.clone(),options:properties.clone(),onchange:{let s=slot.clone();move|e:super::select::SelectionEvent|{let mut s=s.clone();s.condition_property=e.value();onchange.call(s);}}}
    ValueControls{id:format!("{id}-condition-value"),value:slot.condition_value.clone(),predicate:slot.condition_property.clone(),choices:choices.clone(),disabled,onchange:{let s=slot.clone();move|v|{let mut s=s.clone();s.condition_value=v;onchange.call(s);}}}
    }
    label{r#for:"{id}-change","Consequence change"}super::select::RichSelect{id:format!("{id}-change"),disabled,value:slot.change.clone(),options:super::select::choices(&[("","Choose change"),("set","Assign a fixed value"),("delta","Apply a bounded resource delta")]),onchange:{let s=slot.clone();move|e:super::select::SelectionEvent|{let mut s=s.clone();s.change=e.value();onchange.call(s);}}}
    if slot.change=="set"{
    label{r#for:"{id}-polarity","Assignment evidence"}super::select::RichSelect{id:format!("{id}-polarity"),disabled,value:slot.polarity.clone(),options:super::select::choices(&[("","Choose polarity"),("support","Support this value"),("refutation","Refute this value")]),onchange:{let s=slot.clone();move|e:super::select::SelectionEvent|{let mut s=s.clone();s.polarity=e.value();onchange.call(s);}}}
    ValueControls{id:format!("{id}-fixed-value"),value:slot.value.clone(),predicate:slot.predicate.clone(),choices:choices.clone(),disabled,onchange:{let s=slot.clone();move|v|{let mut s=s.clone();s.value=v;onchange.call(s);}}}
    }
    if slot.change=="delta"{
    p{"Use exact whole-number strings. Negative consumes; positive replenishes. Bounds constrain the resulting stock. No unit conversion or transfer balancing is inferred."}
    label{r#for:"{id}-delta","Nonzero signed delta"}input{id:"{id}-delta",disabled,value:slot.delta.clone(),oninput:{let s=slot.clone();move|e|{let mut s=s.clone();s.delta=e.value();onchange.call(s);}}}
    label{r#for:"{id}-minimum","Minimum resulting stock"}input{id:"{id}-minimum",disabled,value:slot.minimum.clone(),oninput:{let s=slot.clone();move|e|{let mut s=s.clone();s.minimum=e.value();onchange.call(s);}}}
    label{r#for:"{id}-maximum","Maximum resulting stock"}input{id:"{id}-maximum",disabled,value:slot.maximum.clone(),oninput:{let s=slot.clone();move|e|{let mut s=s.clone();s.maximum=e.value();onchange.call(s);}}}
    label{r#for:"{id}-unit","Exact resource unit"}super::select::RichSelect{id:format!("{id}-unit"),disabled,value:slot.unit.clone(),options:{let mut units=super::select::typed_id_choices(&choices,"unit","unit_","Choose explicitly");units.insert(1,super::select::Choice::new("none","Unitless integer"));units},onchange:{let s=slot.clone();move|e:super::select::SelectionEvent|{let mut s=s.clone();s.unit=e.value();onchange.call(s);}}}
    }
    label{r#for:"{id}-lifetime","Effect lifetime"}super::select::RichSelect{id:format!("{id}-lifetime"),disabled,value:slot.lifetime.clone(),options:super::select::choices(&[("","Choose lifetime"),("until_changed","Until explicitly changed"),("ticks","Positive number of calendar ticks (fixed assignments only)")]),onchange:{let s=slot.clone();move|e:super::select::SelectionEvent|{let mut s=s.clone();s.lifetime=e.value();onchange.call(s);}}}
    if slot.lifetime=="ticks"{
    label{r#for:"{id}-ticks","Positive whole-tick lifetime"}input{id:"{id}-ticks",disabled,value:slot.ticks.clone(),oninput:{let s=slot.clone();move|e|{let mut s=s.clone();s.ticks=e.value();onchange.call(s);}}}
    }
    }}
}
#[component]
pub(super) fn ActionEditor(
    frame: Frame,
    choices: Vec<Value>,
    disabled: bool,
    onadd: EventHandler<Value>,
) -> Element {
    let mut form = use_signal(ActionForm::default);
    let mut error = use_signal(String::new);
    rsx! {details{summary{"Declare an action, requirements and consequences"}
        p{"Definitions enter protected review. Requirements and consequences are separate: an ordinary action may explicitly declare no effects. Labels never assign resource behavior."}
        label{r#for:"action-namespace","Namespace"}input{id:"action-namespace",disabled,value:form.read().namespace.clone(),oninput:move|e|form.write().namespace=e.value()}
        label{r#for:"action-key","Action name"}input{id:"action-key",disabled,value:form.read().key.clone(),oninput:move|e|form.write().key=e.value()}
        label{r#for:"action-mode","Requirements"}super::select::RichSelect{id:"action-mode",disabled,value:form.read().mode.clone(),options:super::select::choices(&[("","Choose explicitly"),("ordinary","Ordinary action, no special requirement"),("attribute","Requires an attribute or power")]),onchange:move|e:super::select::SelectionEvent|form.write().mode=e.value()}
        if form.read().mode=="attribute"{
            label{r#for:"action-role","Role requiring the attribute"}input{id:"action-role",disabled,value:form.read().role.clone(),oninput:move|e|form.write().role=e.value()}
            label{r#for:"action-property","Required attribute"}super::select::RichSelect{id:"action-property",disabled,value:form.read().predicate.clone(),options:super::select::record_choices(&choices,&["property"],"Choose an attribute"),onchange:move|e:super::select::SelectionEvent|form.write().predicate=e.value()}
            ValueControls{id:"action-required-value",value:form.read().value.clone(),predicate:form.read().predicate.clone(),choices:choices.clone(),disabled,onchange:move|v|form.write().value=v}
        }
        label{r#for:"action-consequences","Consequence contract"}super::select::RichSelect{id:"action-consequences",disabled,value:form.read().consequences.clone(),options:super::select::choices(&[("","Choose explicitly"),("none","No permitted effects"),("declared","Declare effect slots")]),onchange:move|e:super::select::SelectionEvent|form.write().consequences=e.value()}
        if form.read().consequences=="declared"{
            for (i,slot) in form.read().slots.clone().into_iter().enumerate(){section{key:"{i}",
                SlotControls{id:format!("action-slot-{i}"),slot,choices:choices.clone(),disabled,onchange:move|s|form.write().slots[i]=s}
                button{class:"secondary",disabled,onclick:move|_|{form.write().slots.remove(i);},"Remove this slot"}
            }}
            button{class:"secondary",disabled:disabled||form.read().slots.len()>=64,onclick:move|_|form.write().slots.push(SlotForm::default()),"Add effect slot"}
        }
        if !error().is_empty(){p{role:"alert","{error}"}}
        button{disabled,onclick:move|_|match form.read().build(&frame,&choices){Ok(op)=>{onadd.call(op);error.set(String::new());},Err(e)=>error.set(e)},"Add action definition to draft"}
    }}
}
#[cfg(test)]
#[path = "action_tests.rs"]
mod tests;
