//! Supported opt-in contracts; generic rule wrappers are deliberately fixed.
use super::*;
#[derive(Clone, Default)]
struct Form {
    namespace: String,
    key: String,
    channel: String,
    order: String,
    minimum: String,
    maximum_delay: String,
    context: String,
    knowledge: String,
    relation: String,
    grouping: String,
    group_role: String,
    counted_role: String,
    maximum: String,
    applicability: String,
    worlds: Vec<String>,
    realm: String,
    validity: String,
    start: String,
    end: String,
}
fn roles(choices: &[Value], relation: &str) -> Vec<String> {
    choices
        .iter()
        .find(|r| r["kind"] == "relation" && r["record_id"] == relation)
        .and_then(|r| r["definition"]["roles"].as_array())
        .into_iter()
        .flatten()
        .filter_map(|r| r["name"].as_str().map(str::to_owned))
        .collect()
}
fn contexts(choices: &[Value], frame: &Frame) -> Vec<Choice> {
    let mut options = super::super::select::record_choices(
        choices,
        &["represented_context"],
        "Choose the truth context",
    );
    if !options
        .iter()
        .any(|o| o.value == frame.context.record.as_str())
    {
        options.push(Choice::new(
            frame.context.record.as_str(),
            "Current represented context",
        ));
    }
    options
}
impl Form {
    fn build(
        &self,
        mode: &str,
        frame: &Frame,
        clock: Option<&Chronology>,
        choices: &[Value],
    ) -> Result<Value, String> {
        if self.namespace.trim().is_empty() || self.key.trim().is_empty() {
            return Err("Name the policy and its namespace.".into());
        }
        let rr = |id: &str| json!({"universe":frame.universe,"record":id});
        let context = || -> Result<Value, String> {
            if self.context.is_empty()
                || !contexts(choices, frame)
                    .iter()
                    .any(|o| o.value == self.context)
            {
                return Err("Choose an existing truth context.".into());
            }
            Ok(rr(&self.context))
        };
        let mut rule = json!({"namespace":self.namespace,"key":self.key,"labels":{"en":self.key},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"targetPredicates":[],"expression":{"kind":"lit","value":true},"executable":true,"validity":{"kind":"unspecified"}});
        let capability = match mode {
            "chronology" => {
                if self.channel.trim().is_empty() || self.channel.len() > 256 {
                    return Err("Enter a channel name of at most 256 bytes.".into());
                }
                let forward = match self.order.as_str() {
                    "forward" => true,
                    "signed" => false,
                    _ => return Err("Choose the transmission order explicitly.".into()),
                };
                let delay = |text: &str| -> Result<Option<i128>, String> {
                    if text.trim().is_empty() {
                        Ok(None)
                    } else {
                        text.trim()
                            .parse()
                            .map(Some)
                            .map_err(|_| "Delay bounds must be signed whole clock ticks.".into())
                    }
                };
                let (min, max) = (delay(&self.minimum)?, delay(&self.maximum_delay)?);
                if min.zip(max).is_some_and(|(a, b)| a > b) || forward && max.is_some_and(|m| m < 0)
                {
                    return Err(
                        "Delay bounds contradict each other or forward transmission.".into(),
                    );
                }
                rule["channelChronology"] = json!({"channel":self.channel,"forwardOnly":forward,"minimumDelay":min.map(|v|v.to_string()),"maximumDelay":max.map(|v|v.to_string())});
                "communications.chronology.v1"
            }
            "knowledge" => {
                if !["author_established", "justified"].contains(&self.knowledge.as_str()) {
                    return Err("Choose the knowledge basis explicitly.".into());
                }
                rule["knowledgePolicy"] = json!({"context":context()?,"mode":self.knowledge});
                "knowledge.acquisition.v1"
            }
            "cardinality" => {
                let declared = roles(choices, &self.relation);
                if declared.is_empty() || !declared.contains(&self.counted_role) {
                    return Err("Choose a relation and one of its declared counted roles.".into());
                }
                let grouping = match self.grouping.as_str() {
                    "subject" => json!({"kind":"subject"}),
                    "role" if declared.contains(&self.group_role) => {
                        json!({"kind":"role","role":self.group_role})
                    }
                    _ => return Err("Choose subject grouping or a declared grouping role.".into()),
                };
                let maximum: u32 = self
                    .maximum
                    .trim()
                    .parse()
                    .map_err(|_| "Maximum must be a whole number from 0 through 4294967295.")?;
                let applicability = match self.applicability.as_str() {
                    "universe_wide" => json!({"kind":"universe_wide"}),
                    "worlds" if !self.worlds.is_empty() => {
                        let available =
                            super::super::select::typed_id_choices(choices, "world", "wld_", "");
                        if !self
                            .worlds
                            .iter()
                            .all(|w| available.iter().any(|a| &a.value == w))
                        {
                            return Err("Choose existing worlds for the scope.".into());
                        }
                        json!({"kind":"worlds","world_ids":self.worlds})
                    }
                    _ => return Err("Choose universe-wide scope or at least one world.".into()),
                };
                let mut scope = json!({"context":context()?,"applicability":applicability});
                if !self.realm.is_empty() {
                    if !choices
                        .iter()
                        .any(|r| r["kind"] == "realm" && r["record_id"] == self.realm)
                    {
                        return Err("Choose an existing realm.".into());
                    }
                    scope["realm"] = rr(&self.realm);
                }
                let validity = if self.validity == "unspecified" {
                    json!({"kind":"unspecified"})
                } else {
                    let selected_clock = choices
                        .iter()
                        .find(|r| {
                            r["kind"] == "represented_context" && r["record_id"] == self.context
                        })
                        .and_then(|r| {
                            serde_json::from_value::<Chronology>(
                                r["definition"]["chronology"].clone(),
                            )
                            .ok()
                        });
                    let clock = selected_clock
                        .as_ref()
                        .or_else(|| {
                            (self.context == frame.context.record.as_str())
                                .then_some(clock)
                                .flatten()
                        })
                        .ok_or(
                            "The selected context needs an authored clock for exact validity.",
                        )?;
                    let start = clock.coordinate(&self.start)?;
                    match self.validity.as_str() {
                        "instant" => {
                            json!({"kind":"instant","at":{"kind":"exact","calendar":clock.calendar,"value":start}})
                        }
                        "interval" => {
                            let end = clock.coordinate(&self.end)?;
                            if start.parse::<i128>().map_err(|e| e.to_string())?
                                >= end.parse::<i128>().map_err(|e| e.to_string())?
                            {
                                return Err("The exclusive end must follow the start.".into());
                            }
                            json!({"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":start},"end":{"kind":"exact","value":end}})
                        }
                        _ => return Err("Choose validity explicitly.".into()),
                    }
                };
                rule["relationCardinality"] = json!({"relation":rr(&self.relation),"grouping":grouping,"countedRole":self.counted_role,"maximum":maximum,"scope":scope,"validity":validity});
                "relations.cardinality.v1"
            }
            _ => return Err("Choose a supported factual policy.".into()),
        };
        rule["capabilities"] = json!([capability]);
        let op: DomainOperation = serde_json::from_value(json!({"kind":"define_rule","client_ref":RecordId::generate(&mut rand::rng()),"record":rule})).map_err(|e|e.to_string())?;
        serde_json::to_value(op).map_err(|e| e.to_string())
    }
}
#[component]
pub(super) fn FactualPolicy(
    mode: String,
    frame: Frame,
    clock: Option<Chronology>,
    choices: Vec<Value>,
    namespaces: Vec<Choice>,
    disabled: bool,
    onadd: EventHandler<Value>,
) -> Element {
    let mut form = use_signal(Form::default);
    let mut status = use_signal(String::new);
    let declared = roles(&choices, &form.read().relation);
    let role_options = |prompt: &str| {
        std::iter::once(Choice::new("", prompt))
            .chain(declared.iter().map(|r| Choice::new(r, r)))
            .collect::<Vec<_>>()
    };
    rsx! {fieldset{legend{"Author an opt-in factual policy"}
        p{"This policy starts only after validation, exact author approval and publication. It rechecks existing facts. Missing or uncertain evidence stays unresolved and prevents certification."}
        label{r#for:"factual-namespace","Namespace"}RichSelect{id:"factual-namespace",disabled,value:form.read().namespace.clone(),options:namespaces,allow_new:true,onchange:move|e:SelectionEvent|form.write().namespace=e.value()}
        label{r#for:"factual-key","Policy name"}input{id:"factual-key",disabled,value:form.read().key.clone(),oninput:move|e|form.write().key=e.value()}
        if mode=="chronology" {
            label{r#for:"factual-channel","Communication channel"}input{id:"factual-channel",disabled,value:form.read().channel.clone(),oninput:move|e|form.write().channel=e.value()}
            label{r#for:"factual-order","Transmission order"}RichSelect{id:"factual-order",disabled,value:form.read().order.clone(),options:super::super::select::choices(&[("","Choose explicitly"),("forward","Forward only"),("signed","Allow authored negative delays")]),onchange:move|e:SelectionEvent|form.write().order=e.value()}
            p{"Bounds are inclusive signed integer ticks on each message’s same authored clock. Blank means no bound. Delivery and clock conversions are not inferred."}
            label{r#for:"factual-minimum","Minimum delay (optional)"}input{id:"factual-minimum",disabled,value:form.read().minimum.clone(),oninput:move|e|form.write().minimum=e.value()}
            label{r#for:"factual-delay-maximum","Maximum delay (optional)"}input{id:"factual-delay-maximum",disabled,value:form.read().maximum_delay.clone(),oninput:move|e|form.write().maximum_delay=e.value()}
        } else {
            label{r#for:"factual-context","Truth context"}RichSelect{id:"factual-context",disabled,value:form.read().context.clone(),options:contexts(&choices,&frame),onchange:move|e:SelectionEvent|form.write().context=e.value()}
            if mode=="knowledge" {
                label{r#for:"factual-knowledge","Knowledge basis"}RichSelect{id:"factual-knowledge",disabled,value:form.read().knowledge.clone(),options:super::super::select::choices(&[("","Choose explicitly"),("author_established","Author-established knowledge"),("justified","Justified interpreted receipt")]),onchange:move|e:SelectionEvent|form.write().knowledge=e.value()}
                p{"Author-established knowledge needs an attributable author decision. Justified knowledge needs explicit interpretation, actual receipt, chronology and supported truth at acquisition. Receipt alone does not imply understanding."}
            } else if mode=="cardinality" {
                label{r#for:"factual-relation","Relation definition"}RichSelect{id:"factual-relation",disabled,value:form.read().relation.clone(),options:super::super::select::record_choices(&choices,&["relation"],"Choose a relation"),onchange:move|e:SelectionEvent|{let mut f=form.write();f.relation=e.value();f.group_role.clear();f.counted_role.clear();}}
                label{r#for:"factual-group","Group participants by"}RichSelect{id:"factual-group",disabled,value:form.read().grouping.clone(),options:super::super::select::choices(&[("","Choose grouping"),("subject","Relation subject"),("role","Declared relation role")]),onchange:move|e:SelectionEvent|form.write().grouping=e.value()}
                if form.read().grouping=="role" {label{r#for:"factual-group-role","Grouping role"}RichSelect{id:"factual-group-role",disabled,value:form.read().group_role.clone(),options:role_options("Choose a grouping role"),onchange:move|e:SelectionEvent|form.write().group_role=e.value()}}
                label{r#for:"factual-count-role","Counted role"}RichSelect{id:"factual-count-role",disabled,value:form.read().counted_role.clone(),options:role_options("Choose a counted role"),onchange:move|e:SelectionEvent|form.write().counted_role=e.value()}
                label{r#for:"factual-maximum","Maximum distinct participants"}input{id:"factual-maximum",disabled,value:form.read().maximum.clone(),oninput:move|e|form.write().maximum=e.value()}
                p{"Counts distinct identities across overlapping supported relation instances. Repeated evidence counts once; sequential participants can pass. Multiplicity inside one relation is separate. Minimum counts and completeness inference are unavailable."}
                label{r#for:"factual-scope","World scope"}RichSelect{id:"factual-scope",disabled,value:form.read().applicability.clone(),options:super::super::select::choices(&[("","Choose scope"),("universe_wide","Universe-wide"),("worlds","Selected worlds")]),onchange:move|e:SelectionEvent|form.write().applicability=e.value()}
                if form.read().applicability=="worlds" {fieldset{legend{"Worlds"}
                    for w in super::super::select::typed_id_choices(&choices,"world","wld_","").into_iter().filter(|w|!w.value.is_empty()) {label{class:"check-label",input{r#type:"checkbox",disabled,checked:form.read().worlds.contains(&w.value),onchange:{let id=w.value.clone();move|e|{let mut f=form.write();if e.checked(){if !f.worlds.contains(&id){f.worlds.push(id.clone());}}else{f.worlds.retain(|w|w!=&id);}}}}{w.label}}}
                }}
                label{r#for:"factual-realm","Realm (optional)"}RichSelect{id:"factual-realm",disabled,value:form.read().realm.clone(),options:super::super::select::record_choices(&choices,&["realm"],"No realm restriction"),onchange:move|e:SelectionEvent|form.write().realm=e.value()}
                label{r#for:"factual-validity","Count validity"}RichSelect{id:"factual-validity",disabled,value:form.read().validity.clone(),options:super::super::select::choices(&[("","Choose validity"),("unspecified","No rule time restriction"),("instant","Exact instant"),("interval","Exact half-open interval")]),onchange:move|e:SelectionEvent|form.write().validity=e.value()}
                if ["instant","interval"].contains(&form.read().validity.as_str()) {label{r#for:"factual-start","Start date or exact tick in the truth context’s clock"}input{id:"factual-start",disabled,value:form.read().start.clone(),oninput:move|e|form.write().start=e.value()}}
                if form.read().validity=="interval" {label{r#for:"factual-end","Exclusive end"}input{id:"factual-end",disabled,value:form.read().end.clone(),oninput:move|e|form.write().end=e.value()}}
            }
        }
        button{disabled,onclick:move|_|match form.read().build(&mode,&frame,clock.as_ref(),&choices){Ok(op)=>{onadd.call(op);status.set("Policy added to draft; canon is unchanged.".into());},Err(e)=>status.set(e)},"Add factual policy to draft"}
        p{role:"status","{status}"}
    }}
}
#[cfg(test)]
#[path = "factual_policy_tests.rs"]
mod tests;
