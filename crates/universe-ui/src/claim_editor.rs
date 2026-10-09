//! Typed claim composition; the service alone interprets definitions and permissions.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{ids::*, records::DomainOperation, value::validate_value, Frame};

#[derive(Clone, Default)]
pub(super) struct Form {
    pub(super) attribute_mode: String,
    pub(super) subject: String,
    pub(super) predicate: String,
    pub(super) kind: String,
    pub(super) value: String,
    pub(super) denominator: String,
    pub(super) upper: String,
    pub(super) unit: String,
    pub(super) lower_edge: String,
    pub(super) upper_edge: String,
    pub(super) alternatives: String,
    pub(super) start_kind: String,
    pub(super) end_kind: String,
    pub(super) until: String,
    pub(super) calendar: String,
    pub(super) roles: Vec<(String, String)>,
    pub(super) precision: String,
    pub(super) polarity: String,
    pub(super) applicability: String,
    pub(super) worlds: String,
    pub(super) validity: String,
    pub(super) when: String,
    pub(super) note: String,
}
impl Form {
    pub(super) fn typed_value(
        &self,
        frame: &Frame,
        clock: Option<&universe_domain::chronology::Chronology>,
    ) -> Result<Value, String> {
        let rr = |s: &str| -> Result<Value, String> {
            let id = RecordId::parse(s.trim()).map_err(|e| e.to_string())?;
            Ok(json!({"universe":frame.universe,"record":id}))
        };
        let coordinate = |value: &str| -> Result<String, String> {
            if let Some(c) = clock.filter(|c| c.calendar.as_str() == self.calendar.trim()) {
                c.coordinate(value)
            } else {
                Ok(value.into())
            }
        };
        let time = |value: &str| -> Result<Value, String> {
            let calendar = CalendarId::parse(self.calendar.trim()).map_err(|e| e.to_string())?;
            if value.trim().is_empty() {
                return Err("Enter a fictional-time value; an empty field is not zero.".into());
            }
            Ok(json!({"kind":"exact","calendar":calendar,"value":coordinate(value)?}))
        };
        let value = match self.kind.as_str() {
            "text" => json!({"kind":"text","text":self.value}),
            "integer" | "decimal" => json!({"kind":self.kind,"digits":self.value}),
            "rational" => {
                json!({"kind":"rational","numerator":self.value,"denominator":self.denominator})
            }
            "boolean" => match self.value.as_str() {
                "true" => json!({"kind":"boolean","value":true}),
                "false" => json!({"kind":"boolean","value":false}),
                _ => return Err("Choose true or false explicitly.".into()),
            },
            "entity_ref" => json!({"kind":"entity_ref","ref":rr(&self.value)?}),
            "temporal" => json!({"kind":"temporal","temporal":time(&self.value)?}),
            "quantity" => {
                json!({"kind":"quantity","value":{"kind":"decimal","digits":self.value},"unit":UnitId::parse(self.unit.trim()).map_err(|e|e.to_string())?})
            }
            "range" => {
                if !["inclusive", "exclusive"].contains(&self.lower_edge.as_str())
                    || !["inclusive", "exclusive"].contains(&self.upper_edge.as_str())
                {
                    return Err("Choose both range boundaries explicitly.".into());
                }
                json!({"kind":"range","lower":{"kind":"decimal","digits":self.value},"upper":{"kind":"decimal","digits":self.upper},"lower_inclusive":self.lower_edge=="inclusive","upper_inclusive":self.upper_edge=="inclusive"})
            }
            "relationship" => Value::Null,
            _ => return Err("Choose a value type or relationship.".into()),
        };
        if !value.is_null() {
            let typed: universe_domain::value::Value =
                serde_json::from_value(value.clone()).map_err(|e| e.to_string())?;
            validate_value(&typed).map_err(|e| e.to_string())?;
        }
        Ok(value)
    }
    pub(super) fn build(
        &self,
        frame: &Frame,
        clock: Option<&universe_domain::chronology::Chronology>,
    ) -> Result<DomainOperation, String> {
        if !["instance", "shared", "initial_value"].contains(&self.attribute_mode.as_str()) {
            return Err(
                "Choose an instance fact, shared attribute or initial-value attribute.".into(),
            );
        }
        if self.kind == "relationship" && self.attribute_mode != "instance" {
            return Err(
                "Definition-owned attributes require a property value, not a relationship.".into(),
            );
        }
        let rr = |s: &str| -> Result<Value, String> {
            let id = RecordId::parse(s.trim()).map_err(|e| e.to_string())?;
            Ok(json!({"universe":frame.universe,"record":id}))
        };
        let coordinate = |value: &str| -> Result<String, String> {
            if let Some(c) = clock.filter(|c| c.calendar.as_str() == self.calendar.trim()) {
                c.coordinate(value)
            } else {
                Ok(value.into())
            }
        };
        let time = |value: &str| -> Result<Value, String> {
            let calendar = CalendarId::parse(self.calendar.trim()).map_err(|e| e.to_string())?;
            if value.trim().is_empty() {
                return Err("Enter a fictional-time value; an empty field is not zero.".into());
            }
            Ok(json!({"kind":"exact","calendar":calendar,"value":coordinate(value)?}))
        };
        let value = self.typed_value(frame, clock)?;
        let mut roles = Vec::new();
        if self.kind == "relationship" {
            if self.roles.is_empty() {
                return Err("Add at least one named relationship role.".into());
            }
            for (role, participant) in &self.roles {
                if role.trim().is_empty() {
                    return Err("Every relationship participant needs a role name.".into());
                }
                roles.push(json!({"role":role,"participant":rr(participant)?}));
            }
        }
        let applicability = match self.applicability.as_str() {
            "universe_wide" => json!({"kind":"universe_wide"}),
            "unspecified" => json!({"kind":"unspecified"}),
            "worlds" => {
                let ids: Vec<_> = self
                    .worlds
                    .split(',')
                    .map(|s| WorldId::parse(s.trim()).map_err(|e| e.to_string()))
                    .collect::<Result<_, _>>()?;
                json!({"kind":"worlds","world_ids":ids})
            }
            _ => return Err("Choose the claim's applicability explicitly.".into()),
        };
        let bound = |kind: &str, value: &str| -> Result<Value, String> {
            match kind {
                "unknown" | "unbounded" => Ok(json!({"kind":kind})),
                "exact" if !value.trim().is_empty() => {
                    Ok(json!({"kind":"exact","value":coordinate(value)?}))
                }
                _ => Err(
                    "Choose each interval endpoint; a blank is neither unknown nor unbounded."
                        .into(),
                ),
            }
        };
        let validity = match self.validity.as_str() {
            "unspecified" | "unknown" => json!({"kind":self.validity}),
            "instant" => json!({"kind":"instant","at":time(&self.when)?}),
            "timer" => {
                let start = coordinate(&self.when)?
                    .parse::<i128>()
                    .map_err(|_| "A timer needs an exact start in the chosen clock.".to_string())?;
                let duration = self
                    .until
                    .parse::<i128>()
                    .map_err(|_| "Enter the timer duration in clock ticks.".to_string())?;
                if duration <= 0 {
                    return Err("A timer duration must be positive.".into());
                }
                let end = start
                    .checked_add(duration)
                    .ok_or("Timer end exceeds the supported clock range.")?;
                json!({"kind":"calendar_interval","calendar":CalendarId::parse(self.calendar.trim()).map_err(|e|e.to_string())?,"start":{"kind":"exact","value":start.to_string()},"end":{"kind":"exact","value":end.to_string()}})
            }
            "interval" => {
                json!({"kind":"calendar_interval","calendar":CalendarId::parse(self.calendar.trim()).map_err(|e|e.to_string())?,"start":bound(&self.start_kind,&self.when)?,"end":bound(&self.end_kind,&self.until)?})
            }
            _ => return Err("Choose temporal meaning explicitly.".into()),
        };
        if self.note.trim().is_empty() {
            return Err("Explain the basis for this authored claim.".into());
        }
        let mut alternatives = Vec::new();
        if self.precision == "one_of" {
            if !["text", "integer", "decimal", "boolean", "entity_ref"]
                .contains(&self.kind.as_str())
            {
                return Err("Alternatives support text, integers, decimals, booleans and entity references.".into());
            }
            for item in self.alternatives.lines() {
                let alternative = match self.kind.as_str() {
                    "text" => json!({"kind":"text","text":item}),
                    "boolean" => match item {
                        "true" => json!({"kind":"boolean","value":true}),
                        "false" => json!({"kind":"boolean","value":false}),
                        _ => return Err("Each Boolean alternative must be true or false.".into()),
                    },
                    "entity_ref" => json!({"kind":"entity_ref","ref":rr(item)?}),
                    _ => json!({"kind":self.kind,"digits":item}),
                };
                validate_value(
                    &serde_json::from_value(alternative.clone()).map_err(|e| e.to_string())?,
                )
                .map_err(|e| e.to_string())?;
                alternatives.push(alternative);
            }
            if alternatives.len() < 2 {
                return Err("Enter at least two alternatives, one per line.".into());
            }
        }
        let id = RecordId::generate(&mut rand::rng());
        let op = json!({
            "kind":if self.kind=="relationship"{"record_relation"}else{"assert_proposition"},
            "client_ref":id,
            "proposition":{"predicate":rr(&self.predicate)?,"subject":rr(&self.subject)?,"roles":roles,"value":value,"quantification":"particular","context":frame.context},
            "assertion":{"attributeMode":self.attribute_mode,"proposition":{"universe":frame.universe,"record":id},"polarity":self.polarity,"scope":{"applicability":applicability,"context":frame.context},"validity":validity,"persistence":if ["interval","timer"].contains(&self.validity.as_str()){"explicit_interval"}else if self.validity=="instant"{"instantaneous_observation"}else{"unspecified"},"precision":self.precision,"alternatives":alternatives,"basis":{"kind":"author_decision","note":self.note}}
        });
        serde_json::from_value(op).map_err(|e| e.to_string())
    }
}

#[component]
pub fn ClaimEditor(
    clock: Option<universe_domain::chronology::Chronology>,
    frame: Frame,
    choices: Vec<Value>,
    disabled: bool,
    onadd: EventHandler<Value>,
) -> Element {
    let mut form = use_signal(Form::default);
    let mut role = use_signal(String::new);
    let mut participant = use_signal(String::new);
    let mut error = use_signal(String::new);
    rsx! {
            details {
                summary { "Add a typed value or relationship" }
                p { "Choose records from the loaded explorer or draft. Load more explorer records if needed. Add the completed claim to your draft to save it. Definitions and evidence are checked before approval." }
                label{r#for:"claim-owner-mode","Attribute ownership"}
                super::select::RichSelect{id:"claim-owner-mode",disabled,value:form.read().attribute_mode.clone(),options:super::select::choices(&[("","Choose ownership"),("instance","Current instance fact"),("shared","Definition-owned shared attribute"),("initial_value","Definition-owned initial-value attribute")]),onchange:move|e:crate::select::SelectionEvent|{let mut f=form.write();f.attribute_mode=e.value();f.subject.clear();}}
                if form.read().attribute_mode!="instance"{p{"Shared attributes remain definition facts. Initial values are candidates for explicit reviewed initialization; neither creates current instance stock."}}
                label { r#for:"claim-subject", "Attribute owner" }
                super::select::RichSelect { id:"claim-subject", disabled, value:form.read().subject.clone(), onchange:move|e: crate::select::SelectionEvent|form.write().subject=e.value(),options:super::select::record_choices(&choices, if form.read().attribute_mode=="instance" {&["entity"]} else {&["entity_type"]}, "Choose the attribute owner")}
                label { r#for:"claim-predicate", "Property or relation definition ID" }
                super::select::RichSelect { id:"claim-predicate", disabled, value:form.read().predicate.clone(), onchange:move|e: crate::select::SelectionEvent|form.write().predicate=e.value(),options:super::select::record_choices(&choices, &["property","relation"], "Choose a property or relationship")}
                label { r#for:"claim-kind", "Value or relationship type" }
                super::select::RichSelect { id:"claim-kind", disabled, value:form.read().kind.clone(), onchange:move|e: crate::select::SelectionEvent|{let mut f=form.write();f.kind=e.value();f.value.clear();},
                    options:super::select::choices(&[("","Choose a type"),("text","Text"),("integer","Exact integer"),("decimal","Exact decimal"),("rational","Rational"),("quantity","Decimal quantity with unit"),("range","Decimal range"),("boolean","Boolean"),("entity_ref","Entity reference"),("temporal","Fictional-time value"),("relationship","Relationship")])}
                if form.read().kind=="boolean" {
                    label{r#for:"claim-bool","Boolean value"}
                    super::select::RichSelect {id:"claim-bool",disabled,value:form.read().value.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().value=e.value(),options:super::select::choices(&[("","Choose explicitly"),("true","True"),("false","False")])}
                } else if form.read().kind=="relationship" {
                    label{r#for:"claim-role","Role name"}input{id:"claim-role",disabled,value:role,oninput:move|e|role.set(e.value())}
                    label{r#for:"claim-participant","Participant entity ID"}super::select::RichSelect{id:"claim-participant",disabled,value:participant(),options:super::select::record_choices(&choices,&["entity"],"Choose a participant"),onchange:move|e:super::select::SelectionEvent|participant.set(e.value())}
                    button{class:"secondary",disabled,onclick:move|_|{if role().trim().is_empty()||RecordId::parse(participant().trim()).is_err(){error.set("Enter a role and a valid participant record ID.".into());}else{form.write().roles.push((role(),participant()));role.set(String::new());participant.set(String::new());error.set(String::new());}},"Add participant"}
                    ul{for (i,(name,id)) in form.read().roles.clone().into_iter().enumerate(){li{"{name}: {id} "
    button{class:"secondary",disabled,onclick:move|_|{form.write().roles.remove(i);},"Remove participant"}}}}
                } else if form.read().kind=="entity_ref"{
                    label{r#for:"claim-entity-value","Referenced entity"}super::select::RichSelect{id:"claim-entity-value",disabled,value:form.read().value.clone(),options:super::select::record_choices(&choices,&["entity"],"Choose an entity"),onchange:move|e:super::select::SelectionEvent|form.write().value=e.value()}
                } else {
                    label{r#for:"claim-value","Value (numerator for a rational)"}input{id:"claim-value",disabled,value:form.read().value.clone(),oninput:move|e|form.write().value=e.value()}
                    if form.read().kind=="rational"{label{r#for:"claim-denominator","Denominator"}input{id:"claim-denominator",disabled,value:form.read().denominator.clone(),oninput:move|e|form.write().denominator=e.value()}}
                }
                if form.read().kind=="quantity"{label{r#for:"claim-unit","Unit ID"}super::select::RichSelect{id:"claim-unit",disabled,value:form.read().unit.clone(),options:super::select::typed_id_choices(&choices,"unit","unit_","Choose a unit"),onchange:move|e:super::select::SelectionEvent|form.write().unit=e.value()}}
                if form.read().kind=="range"{
                    label{r#for:"claim-upper","Upper value"}input{id:"claim-upper",disabled,value:form.read().upper.clone(),oninput:move|e|form.write().upper=e.value()}
                    label{r#for:"claim-lower-edge","Lower boundary"}super::select::RichSelect {id:"claim-lower-edge",disabled,value:form.read().lower_edge.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().lower_edge=e.value(),options:super::select::choices(&[("","Choose boundary"),("inclusive","Includes lower value"),("exclusive","Excludes lower value")])}
                    label{r#for:"claim-upper-edge","Upper boundary"}super::select::RichSelect {id:"claim-upper-edge",disabled,value:form.read().upper_edge.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().upper_edge=e.value(),options:super::select::choices(&[("","Choose boundary"),("inclusive","Includes upper value"),("exclusive","Excludes upper value")])}
                }
                label{r#for:"claim-precision","Precision"}
                super::select::RichSelect {id:"claim-precision",disabled,value:form.read().precision.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().precision=e.value(),options:super::select::choices(&[("","Choose precision"),("exact","Exact"),("approximate","Approximate"),("unresolved","Unresolved"),("range","Bounded range"),("one_of","One of the stated alternatives")])}
                if form.read().precision=="one_of"{label{r#for:"claim-alternatives","Possible values, one per line"}textarea{id:"claim-alternatives",disabled,value:form.read().alternatives.clone(),oninput:move|e|form.write().alternatives=e.value()}p{"Alternatives remain unresolved. Enter values of the selected type; no alternative is selected as fact."}}
                label{r#for:"claim-polarity","Evidence polarity"}
                super::select::RichSelect {id:"claim-polarity",disabled,value:form.read().polarity.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().polarity=e.value(),options:super::select::choices(&[("","Choose polarity"),("support","Support"),("refutation","Refute")])}
                label{r#for:"claim-applicability","Where this claim applies"}
                super::select::RichSelect {id:"claim-applicability",disabled,value:form.read().applicability.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().applicability=e.value(),options:super::select::choices(&[("","Choose applicability"),("universe_wide","Universe wide"),("worlds","Named worlds"),("unspecified","Unspecified scope")])}
                if form.read().applicability=="worlds"{label{r#for:"claim-worlds","World IDs, separated by commas"}input{id:"claim-worlds",disabled,value:form.read().worlds.clone(),oninput:move|e|form.write().worlds=e.value()}}
                label{r#for:"claim-validity","When this claim holds"}
                super::select::RichSelect {id:"claim-validity",disabled,value:form.read().validity.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().validity=e.value(),options:super::select::choices(&[("","Choose temporal meaning"),("unspecified","No temporal claim"),("unknown","Time unknown"),("instant","Named-calendar instant"),("interval","Explicit interval endpoints"),("timer","Timed attribute / effect")])}
                if ["instant","interval","timer"].contains(&form.read().validity.as_str()) || form.read().kind=="temporal" {
                    label{r#for:"claim-calendar","Calendar ID"}super::select::RichSelect{id:"claim-calendar",disabled,value:form.read().calendar.clone(),options:super::select::typed_id_choices(&choices,"calendar","cal_","Choose a calendar"),onchange:move|e:super::select::SelectionEvent|form.write().calendar=e.value()}
                }
                if form.read().validity=="instant"{label{r#for:"claim-when","Fictional-time value"}input{id:"claim-when",disabled,value:form.read().when.clone(),oninput:move|e|form.write().when=e.value()}}
                if form.read().validity=="timer"{
                    label{r#for:"timer-start","Timer starts at this fictional timestamp"}input{id:"timer-start",disabled,value:form.read().when.clone(),oninput:move|e|form.write().when=e.value()}
                    label{r#for:"timer-duration","Duration in this clock’s ticks (seconds for Gregorian)"}input{id:"timer-duration",disabled,value:form.read().until.clone(),oninput:move|e|form.write().until=e.value()}
                    p{"The effect is supported from the start up to, but excluding, expiry. Real elapsed time never runs this timer."}
                }
                if form.read().validity=="interval"{
                    p{"Exact intervals include their start and exclude their end. These validity endpoints have no implied clock conversion. Unknown endpoints do not mean unbounded."}
                    label{r#for:"claim-start-kind","Start endpoint"}super::select::RichSelect {id:"claim-start-kind",disabled,value:form.read().start_kind.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().start_kind=e.value(),options:super::select::choices(&[("","Choose endpoint"),("exact","Exact"),("unknown","Unknown"),("unbounded","Unbounded")])}
                    if form.read().start_kind=="exact"{label{r#for:"claim-start","Inclusive start"}input{id:"claim-start",disabled,value:form.read().when.clone(),oninput:move|e|form.write().when=e.value()}}
                    label{r#for:"claim-end-kind","End endpoint"}super::select::RichSelect {id:"claim-end-kind",disabled,value:form.read().end_kind.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().end_kind=e.value(),options:super::select::choices(&[("","Choose endpoint"),("exact","Exact"),("unknown","Unknown"),("unbounded","Unbounded")])}
                    if form.read().end_kind=="exact"{label{r#for:"claim-end","Exclusive end"}input{id:"claim-end",disabled,value:form.read().until.clone(),oninput:move|e|form.write().until=e.value()}}
                }
                label{r#for:"claim-note","Basis for this claim"}textarea{id:"claim-note",disabled,value:form.read().note.clone(),oninput:move|e|form.write().note=e.value()}
                if !error().is_empty(){p{role:"alert","{error}"}}
                button{class:"secondary",disabled,onclick:move|_|{match form.read().build(&frame,clock.as_ref()){Ok(op)=>{onadd.call(serde_json::to_value(op).expect("typed operation"));error.set(String::new());},Err(e)=>error.set(e)}},"Add typed claim to draft"}
            }
        }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn frame() -> Frame {
        serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"time":{"kind":"timeless"},"perspective":"author"})).unwrap()
    }
    fn form() -> Form {
        Form {
            attribute_mode: "instance".into(),
            subject: "rec_000000000000000000000002".into(),
            predicate: "rec_000000000000000000000003".into(),
            kind: "integer".into(),
            precision: "exact".into(),
            polarity: "support".into(),
            applicability: "universe_wide".into(),
            validity: "unspecified".into(),
            note: "Authored test".into(),
            ..Form::default()
        }
    }
    #[test]
    fn blanks_are_not_zero_false_or_unbounded() {
        let mut f = form();
        assert!(f.build(&frame(), None).is_err());
        f.kind = "boolean".into();
        assert!(f.build(&frame(), None).is_err());
        f.value = "false".into();
        assert!(f.build(&frame(), None).is_ok());
        f.validity = "instant".into();
        f.calendar = "cal_000000000000000000000001".into();
        assert!(f.build(&frame(), None).is_err());
    }
    #[test]
    fn exact_values_and_unknown_time_remain_distinct() {
        let mut f = form();
        f.kind = "decimal".into();
        f.polarity = "refutation".into();
        f.value = "12345678901234567890.0010".into();
        f.validity = "unknown".into();
        let op = serde_json::to_value(f.build(&frame(), None).unwrap()).unwrap();
        assert_eq!(op["proposition"]["value"]["digits"], f.value);
        assert_eq!(op["assertion"]["validity"]["kind"], "unknown");
        assert_eq!(op["assertion"]["polarity"], "refutation");
        assert_eq!(op["assertion"]["scope"]["context"], json!(frame().context));
        f.kind = "rational".into();
        f.value = "1".into();
        f.denominator = "0".into();
        assert!(f.build(&frame(), None).is_err());
    }
    #[test]
    fn relationship_roles_and_worlds_are_explicit() {
        let mut f = form();
        f.kind = "relationship".into();
        assert!(f.build(&frame(), None).is_err());
        f.roles
            .push(("recipient".into(), "rec_000000000000000000000004".into()));
        f.applicability = "worlds".into();
        assert!(f.build(&frame(), None).is_err());
        f.worlds = "wld_000000000000000000000005".into();
        let op = serde_json::to_value(f.build(&frame(), None).unwrap()).unwrap();
        assert_eq!(op["kind"], "record_relation");
        assert_eq!(op["proposition"]["roles"][0]["role"], "recipient");
        assert!(op["proposition"].get("value").is_none());
    }
}
#[cfg(test)]
mod qualified_tests {
    use super::*;
    #[test]
    fn ranges_alternatives_and_interval_endpoints_require_explicit_input() {
        let frame:Frame=serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"time":{"kind":"timeless"},"perspective":"author"})).unwrap();
        let mut f = Form {
            attribute_mode: "instance".into(),
            subject: "rec_000000000000000000000002".into(),
            predicate: "rec_000000000000000000000003".into(),
            kind: "range".into(),
            value: "1.00".into(),
            upper: "3.00".into(),
            precision: "range".into(),
            polarity: "support".into(),
            applicability: "universe_wide".into(),
            validity: "interval".into(),
            note: "Authored bounds".into(),
            ..Default::default()
        };
        assert!(f.build(&frame, None).is_err());
        f.lower_edge = "inclusive".into();
        f.upper_edge = "exclusive".into();
        f.start_kind = "unknown".into();
        f.end_kind = "unbounded".into();
        assert!(f.build(&frame, None).is_err());
        f.calendar = "cal_000000000000000000000004".into();
        let op = serde_json::to_value(f.build(&frame, None).unwrap()).unwrap();
        assert_eq!(op["assertion"]["validity"]["start"]["kind"], "unknown");
        assert_eq!(op["assertion"]["validity"]["end"]["kind"], "unbounded");
        assert_eq!(op["proposition"]["value"]["upper_inclusive"], false);
        f.kind = "decimal".into();
        f.precision = "one_of".into();
        assert!(f.build(&frame, None).is_err());
        f.alternatives = "1.00\n3.00".into();
        let op = serde_json::to_value(f.build(&frame, None).unwrap()).unwrap();
        assert_eq!(op["assertion"]["alternatives"].as_array().unwrap().len(), 2);
        f.start_kind = "exact".into();
        assert!(f.build(&frame, None).is_err());
    }
}

#[cfg(test)]
mod timer_tests {
    use super::*;
    #[test]
    fn gregorian_timer_uses_authored_start_and_rejects_empty_negative_and_overflow() {
        let frame:Frame=serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"time":{"kind":"timeless"},"perspective":"author"})).unwrap();
        let (clock, _) = universe_domain::chronology::UniverseStart::Gregorian {
            timestamp: "2040-01-01T00:00:00+00:00".into(),
        }
        .build(CalendarId::parse("cal_000000000000000000000004").unwrap())
        .unwrap();
        let mut f = Form {
            attribute_mode: "instance".into(),
            subject: "rec_000000000000000000000002".into(),
            predicate: "rec_000000000000000000000003".into(),
            kind: "boolean".into(),
            value: "true".into(),
            precision: "exact".into(),
            polarity: "support".into(),
            applicability: "universe_wide".into(),
            validity: "timer".into(),
            calendar: clock.calendar.to_string(),
            when: "2040-01-01T00:00:00+00:00".into(),
            until: "60".into(),
            note: "Battery effect lasts one minute".into(),
            ..Default::default()
        };
        let op = serde_json::to_value(f.build(&frame, Some(&clock)).unwrap()).unwrap();
        let start = op["assertion"]["validity"]["start"]["value"]
            .as_str()
            .unwrap()
            .parse::<i128>()
            .unwrap();
        let end = op["assertion"]["validity"]["end"]["value"]
            .as_str()
            .unwrap()
            .parse::<i128>()
            .unwrap();
        assert_eq!(end - start, 60);
        assert_eq!(op["assertion"]["persistence"], "explicit_interval");
        for duration in ["", "0", "-1", "99999999999999999999999999999999999999999"] {
            f.until = duration.into();
            assert!(f.build(&frame, Some(&clock)).is_err());
        }
        assert_eq!(clock.current, clock.first_interaction);
    }
}

#[cfg(test)]
#[path = "definition_workflow.rs"]
mod definition_workflow;

/// Correct one declared role, or explicitly end and replace this authored occurrence.
pub(super) fn relationship_operations(
    frame: &Frame,
    original: &Value,
    choices: &[Value],
    role: &str,
    participants: &[String],
    reason: &str,
    transfer: Option<(&str, Option<&universe_domain::chronology::Chronology>)>,
) -> Result<Vec<Value>, String> {
    let mut assertion = original["payload"].clone();
    if assertion["record_kind"] != "assertion"
        || !assertion["establishedBy"].is_null()
        || assertion["attributeMode"] != "instance"
    {
        return Err(
            "Select an authored instance relationship; generated effects require event correction."
                .into(),
        );
    }
    if reason.trim().is_empty() {
        return Err("Explain this explicit relationship correction or transfer.".into());
    }
    let mut proposition = choices
        .iter()
        .find(|r| r["record_id"] == assertion["proposition"]["record"])
        .map(|r| r["definition"].clone())
        .ok_or("Load the pinned relationship references first.")?;
    let definition = choices
        .iter()
        .find(|r| r["record_id"] == proposition["predicate"]["record"] && r["kind"] == "relation")
        .ok_or("This assertion is not a loaded relationship.")?;
    let declared = definition["definition"]["roles"]
        .as_array()
        .ok_or("Relationship roles unavailable.")?;
    let contract = declared
        .iter()
        .find(|r| r["name"] == role)
        .ok_or("Choose a declared role.")?;
    if contract["multiplicity"] == "single" && participants.len() > 1 {
        return Err("This role allows only one participant per occurrence.".into());
    }
    let roles = proposition["roles"]
        .as_array_mut()
        .ok_or("Relationship participant bindings unavailable.")?;
    roles.retain(|r| r["role"] != role);
    for id in participants {
        let id = RecordId::parse(id).map_err(|e| e.to_string())?;
        if !choices
            .iter()
            .any(|r| r["record_id"] == id.as_str() && r["kind"] == "entity")
        {
            return Err("Choose participants from the loaded authored entities.".into());
        }
        roles.push(json!({"role":role,"participant":{"universe":frame.universe,"record":id}}));
    }
    let id = RecordId::generate(&mut rand::rng());
    assertion["proposition"] = json!({"universe":frame.universe,"record":id});
    assertion["basis"] = json!({"kind":"author_decision","note":reason});
    assertion.as_object_mut().unwrap().remove("record_kind");
    proposition.as_object_mut().unwrap().remove("record_kind");
    let ops = if let Some((end, clock)) = transfer {
        if assertion["polarity"] != "support" {
            return Err("Explicit transfers require a supported authored relationship.".into());
        }
        let ending = crate::inspector_editor::operation(
            frame,
            original,
            "end_assertion_at",
            end,
            reason,
            clock,
        )?;
        assertion["validity"]["start"] = json!({"kind":"exact","value":ending["at"]["value"]});
        vec![
            ending,
            json!({"kind":"record_relation","client_ref":id,"proposition":proposition,"assertion":assertion}),
        ]
    } else {
        vec![
            json!({"kind":"define_proposition","client_ref":id,"record":proposition}),
            json!({"kind":"supersede_assertion","record":{"universe":frame.universe,"record":original["identity"]["record_id"]},"expected_version":original["record_version_id"],"replacement":assertion,"rationale":reason}),
        ]
    };
    ops.into_iter()
        .map(|op| {
            serde_json::from_value::<DomainOperation>(op)
                .and_then(serde_json::to_value)
                .map_err(|e| e.to_string())
        })
        .collect()
}

#[component]
pub(super) fn RelationshipCorrection(
    root: String,
    profile: String,
    universe: String,
    context: Value,
    frame: Frame,
    original: Value,
    clock: Option<universe_domain::chronology::Chronology>,
    available: Vec<Value>,
    generation: Signal<u64>,
    disabled: bool,
    onadd: EventHandler<Vec<Value>>,
) -> Element {
    let mut loaded = use_signal(Vec::<Value>::new);
    let mut review = use_signal(Value::default);
    let mut busy = use_signal(|| false);
    let mut error = use_signal(String::new);
    let mut mode = use_signal(String::new);
    let mut role = use_signal(String::new);
    let mut participant = use_signal(String::new);
    let mut participants = use_signal(Vec::<String>::new);
    let mut reason = use_signal(String::new);
    let mut end = use_signal(String::new);
    if !original["payload"]["establishedBy"].is_null()
        || original["payload"]["attributeMode"] != "instance"
    {
        return rsx! {};
    }
    let mut choices = available;
    for row in loaded() {
        choices.retain(|r| r["record_id"] != row["record_id"]);
        choices.push(row);
    }
    let proposition = choices
        .iter()
        .find(|r| r["record_id"] == original["payload"]["proposition"]["record"]);
    let definition = proposition.and_then(|p| {
        choices.iter().find(|r| {
            r["record_id"] == p["definition"]["predicate"]["record"] && r["kind"] == "relation"
        })
    });
    let declared = definition
        .and_then(|r| r["definition"]["roles"].as_array())
        .cloned()
        .unwrap_or_default();
    rsx! {details{summary{"Correct relationship participants or explicitly transfer"}
        p{"Load this pinned assertion. Replace only one role's participants; other roles, subject, scope and history stay unchanged. An explicit transfer ends this occurrence and starts the replacement at your chosen time, retaining its original end. Nothing is ended automatically. Participant choices include loaded explorer entities; load any additional explorer pages before selecting a replacement."}
        button{disabled:disabled||busy(),onclick:{let(root,profile,universe,context,original)=(root.clone(),profile.clone(),universe.clone(),context.clone(),original.clone());move|_|{busy.set(true);let g=generation();let(root,profile,universe,context,original)=(root.clone(),profile.clone(),universe.clone(),context.clone(),original.clone());spawn(async move{let result=crate::event_correction::load(root,profile,universe,context,&original).await;if generation()!=g{return;}match result{Ok((c,r))=>{loaded.set(c);review.set(r);error.set(String::new());},Err(e)=>error.set(e)}busy.set(false);});}},"Load relationship for correction"}
        if !declared.is_empty() && !review().is_null(){
            details{summary{"Related authored records and coverage"}crate::readable::ReadValue{value:review()}}
            label{r#for:"relationship-change-mode","Explicit change"}crate::select::RichSelect{id:"relationship-change-mode",disabled,value:mode(),options:crate::select::choices(&[("","Keep relationship"),("correct","Correct historical participants"),("transfer","End and transfer at an authored time")]),onchange:move|e:crate::select::SelectionEvent|mode.set(e.value())}
            label{r#for:"relationship-change-role","Declared role to replace"}crate::select::RichSelect{id:"relationship-change-role",disabled,value:role(),options:{let mut options=vec![crate::select::Choice::new("","Keep until role selected")];for r in &declared{if let Some(name)=r["name"].as_str(){options.push(crate::select::Choice::new(name,name));}}options},onchange:move|e:crate::select::SelectionEvent|{role.set(e.value());participants.set(vec![]);}}
            label{r#for:"relationship-change-participant","New participant"}crate::select::RichSelect{id:"relationship-change-participant",disabled,value:participant(),options:crate::select::record_choices(&choices,&["entity"],"Choose participant"),onchange:move|e:crate::select::SelectionEvent|participant.set(e.value())}
            button{class:"secondary",disabled:disabled||participant().is_empty(),onclick:move|_|{participants.write().push(participant());participant.set(String::new());},"Add to replacement list"}
            ul{for (i,id) in participants().into_iter().enumerate(){li{ {choices.iter().find(|r|r["record_id"]==id).and_then(|r|r["label"].as_str()).unwrap_or("Unavailable participant").to_owned()}button{class:"secondary",disabled,onclick:move|_|{participants.write().remove(i);},"Remove"}}}}
            p{"An empty replacement list explicitly clears only the chosen role. Ordered roles use this list order."}
            if mode()=="transfer"{label{r#for:"relationship-transfer-time","Exclusive old end and new start"}input{id:"relationship-transfer-time",disabled,value:end,oninput:move|e|end.set(e.value())}}
            label{r#for:"relationship-change-reason","Author reason"}textarea{id:"relationship-change-reason",disabled,value:reason,oninput:move|e|reason.set(e.value())}
            button{disabled:disabled||busy()||mode().is_empty()||role().is_empty(),onclick:{let original=original.clone();move|_|{let end_value=end();match relationship_operations(&frame,&original,&choices,&role(),&participants(),&reason(),if mode()=="transfer"{Some((&end_value,clock.as_ref()))}else{None}){Ok(ops)=>{onadd.call(ops);error.set(String::new());},Err(e)=>error.set(e)}}},"Add explicit relationship change to draft"}
        }
        if !error().is_empty(){p{role:"alert","{error}"}}
    }}
}
