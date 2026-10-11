//! Typed identity and narrative edits, all staged into the same proposal draft.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{ids::*, records::DomainOperation, Frame};
#[derive(Clone, Default)]
pub(super) struct Form {
    pub(super) kind: String,
    pub(super) name: String,
    pub(super) classification: String,
    pub(super) work_kind: String,
    pub(super) worlds: Vec<String>,
    pub(super) role: String,
    pub(super) work: String,
    pub(super) order: String,
    pub(super) binding: String,
    pub(super) context_kind: String,
    pub(super) parent_context: String,
    pub(super) calendar: String,
    pub(super) story_time: String,
    pub(super) narrator: String,
    pub(super) scene_viewpoint: String,
    pub(super) scene_events: Vec<String>,
    pub(super) scene_disclosures: Vec<String>,
}
fn checked(value: Value) -> Result<Value, String> {
    let operation: DomainOperation = serde_json::from_value(value).map_err(|e| e.to_string())?;
    serde_json::to_value(operation).map_err(|e| e.to_string())
}
impl Form {
    pub(super) fn create_context(&self, frame: &Frame, choices: &[Value]) -> Result<Value, String> {
        if self.name.trim().is_empty()
            || !["dream", "account", "embedded", "narrator"].contains(&self.context_kind.as_str())
        {
            return Err("Name the context and choose its explicit kind.".into());
        }
        let parent = RecordId::parse(&self.parent_context)
            .map_err(|_| "Choose an existing parent context.")?;
        if !choices
            .iter()
            .any(|c| c["kind"] == "represented_context" && c["record_id"] == self.parent_context)
        {
            return Err("Choose an existing parent context.".into());
        }
        let calendar =
            CalendarId::parse(&self.calendar).map_err(|_| "Choose an authored calendar.")?;
        let clocks: Vec<universe_domain::chronology::Chronology> = choices
            .iter()
            .filter(|c| c["kind"] == "represented_context")
            .filter_map(|c| serde_json::from_value(c["definition"]["chronology"].clone()).ok())
            .filter(|c: &universe_domain::chronology::Chronology| c.calendar == calendar)
            .collect();
        let Some(clock) = clocks.first() else {
            return Err("Load an existing context with this authored clock system.".into());
        };
        if clocks.iter().any(|other| other.system != clock.system) {
            return Err("The calendar has conflicting authored clock systems.".into());
        }
        let mut chronology = clock.clone();
        let time = chronology.coordinate(&self.story_time)?;
        chronology.first_interaction = time.clone();
        chronology.current = time;
        chronology.validate()?;
        let kind=if self.context_kind=="narrator" {
            if !choices.iter().any(|c|c["kind"]=="entity"&&c["record_id"]==self.narrator){return Err("Choose an existing narrator entity.".into());}
            json!({"kind":"narrator","narrator":{"universe":frame.universe,"record":RecordId::parse(&self.narrator).map_err(|e|e.to_string())?}})
        }else{json!({"kind":"authored","label":format!("{}: {}",self.context_kind,self.name)})};
        checked(
            json!({"kind":"record_narrative_reference","client_ref":RecordId::generate(&mut rand::rng()),"record":"represented_context","payload":{"record_kind":"represented_context","universe":frame.universe,"kind":kind,"parent":{"universe":frame.universe,"record":parent},"chronology":chronology,"labels":{"en":self.name}}}),
        )
    }
    pub(super) fn create_scene(&self,frame:&Frame,choices:&[Value])->Result<Value,String>{
        if self.name.trim().is_empty(){return Err("Name the scene.".into());}
        let edition=choices.iter().find(|c|c["kind"]=="work_version"&&c["record_id"]==self.work&&c["record_version_id"].is_string()).ok_or("Inspect the published edition to load its exact version, then select it.")?;
        let context=choices.iter().find(|c|c["kind"]=="represented_context"&&c["record_id"]==self.parent_context&&c["definition"]["kind"]["kind"]=="narrator"&&c["definition"]["chronology"].is_object()).ok_or("Choose an authored narrator context with narration time.")?;
        let viewpoint=if self.scene_viewpoint.is_empty(){Value::Null}else{if !choices.iter().any(|c|c["kind"]=="entity"&&c["record_id"]==self.scene_viewpoint){return Err("Choose an existing viewpoint entity.".into());}json!({"universe":frame.universe,"record":self.scene_viewpoint})};
        let order=if self.order.is_empty(){None}else{Some(self.order.parse::<u64>().map_err(|_|"Reader order is a whole nonnegative position.")?)};
        let events:Vec<_>=self.scene_events.iter().map(|id|{if !choices.iter().any(|c|c["kind"]=="event"&&c["record_id"]==*id&&c["definition"]["occurrence"]=="occurred"){return Err("Inspect and select an occurred event explicitly.");}Ok(json!({"universe":frame.universe,"record":id}))}).collect::<Result<_,_>>()?;
        let disclosures:Vec<_>=self.scene_disclosures.iter().map(|id|{if !choices.iter().any(|c|["entity","assertion","event"].contains(&c["kind"].as_str().unwrap_or_default())&&c["record_id"]==*id){return Err("Inspect and select a disclosure target explicitly.");}Ok(json!({"universe":frame.universe,"record":id}))}).collect::<Result<_,_>>()?;
        checked(json!({"kind":"record_narrative_reference","client_ref":RecordId::generate(&mut rand::rng()),"record":"scene_ref","payload":{"record_kind":"scene_ref","workVersion":{"universe":frame.universe,"record":edition["record_id"],"version":edition["record_version_id"]},"sceneId":self.name,"disclosedRecords":disclosures,"viewpoint":viewpoint,"narrativePosition":order,"depictedEvents":events,"narrationFrame":{"universe":frame.universe,"record":context["record_id"]},"worldAssociations":[]}}))
    }
    pub(super) fn create(&self, frame: &Frame) -> Result<Value, String> {
        if self.name.trim().is_empty() {
            return Err("Enter a name.".into());
        }
        if !self.worlds.is_empty() && self.role.trim().is_empty() {
            return Err("Describe the role of the selected worlds.".into());
        }
        let associations:Vec<_>=self.worlds.iter().map(|id|json!({"world":id,"role":self.role,"validity":{"kind":"unspecified"},"qualifiers":{}})).collect();
        let (kind, record) = match self.kind.as_str() {
            "entity" => {
                let classification = if self.classification.is_empty() {
                    None
                } else {
                    Some(
                        RecordId::parse(&self.classification)
                            .map_err(|_| "Choose an existing classification.")?,
                    )
                };
                return checked(
                    json!({"kind":"introduce_instance","client_ref":RecordId::generate(&mut rand::rng()),"name":{"text":self.name,"validity":{"kind":"unspecified"}},"classification":classification,"world_associations":associations}),
                );
            }
            "world" => (
                "create_world",
                json!({"selector":self.name,"labels":{},"metadata":{}}),
            ),
            "work" => (
                "create_work",
                json!({"kind":self.work_kind,"title":self.name,"labels":{},"sourceRefs":[],"versions":[],"worldAssociations":associations}),
            ),
            "saga" => (
                "create_saga",
                json!({"title":self.name,"labels":{},"memberships":[]}),
            ),
            "work_version" => {
                let work = RecordId::parse(&self.work).map_err(|_| "Choose the parent work.")?;
                let binding = match self.binding.as_str() {
                    "current" => {
                        json!({"kind":"bound","continuity":frame.continuity,"revision":frame.revision})
                    }
                    "unbound" => json!({"kind":"unbound"}),
                    _ => return Err("Choose a canon binding explicitly.".into()),
                };
                return checked(
                    json!({"kind":"record_narrative_reference","client_ref":RecordId::generate(&mut rand::rng()),"record":"work_version","payload":{"record_kind":"work_version","work":{"universe":frame.universe,"record":work},"versionLabel":self.name,"binding":binding}}),
                );
            }
            _ => return Err("Choose a record kind.".into()),
        };
        checked(
            json!({"kind":kind,"client_ref":RecordId::generate(&mut rand::rng()),"record":record}),
        )
    }
    fn membership(&self, frame: &Frame, selected: &Value) -> Result<Value, String> {
        if self.role.trim().is_empty() {
            return Err("Enter the work's role in this saga.".into());
        }
        let work = RecordId::parse(&self.work).map_err(|_| "Choose a work.")?;
        let order = if self.order.trim().is_empty() {
            None
        } else {
            Some(self.order.parse::<u64>().map_err(|_| {
                "Order must be a whole nonnegative position, or blank for unordered."
            })?)
        };
        checked(
            json!({"kind":"set_saga_membership","record":{"universe":frame.universe,"record":selected["identity"]["record_id"]},"expected_version":selected["record_version_id"],"membership":{"work":{"universe":frame.universe,"record":work},"role":self.role,"order":order}}),
        )
    }
}
#[component]
pub fn IdentityEditor(
    frame: Frame,
    choices: Vec<Value>,
    inspected: Value,
    disabled: bool,
    onadd: EventHandler<Value>,
) -> Element {
    let mut form = use_signal(Form::default);
    let mut error = use_signal(String::new);
    let worlds: Vec<_> = choices
        .iter()
        .filter(|c| c["kind"] == "world")
        .cloned()
        .collect();
    let works: Vec<_> = choices
        .iter()
        .filter(|c| c["kind"] == "work")
        .cloned()
        .collect();
    let selected = inspected["records"][0].clone();
    rsx! {details{open:true,
        summary{"Create an entity, world, work, saga or story context"}
        label{r#for:"draft-kind","Record kind"}super::select::RichSelect {id:"draft-kind",disabled,value:form.read().kind.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().kind=e.value(),options:super::select::choices(&[("","Choose a kind"),("entity","Character or entity"),("world","World"),("story_context","Authored story context"),("scene_ref","Scene in a narrative edition"),("work","Narrative work"),("saga","Saga or series"),("work_version","Version of a narrative work")])}
        label{r#for:"draft-name","Name or version label"}input{id:"draft-name",disabled,value:form.read().name.clone(),oninput:move|e|form.write().name=e.value()}
        if form.read().kind=="entity"{
            label{r#for:"instance-classification","Classification (optional)"}
            super::select::RichSelect{id:"instance-classification",disabled,value:form.read().classification.clone(),onchange:move|e:crate::select::SelectionEvent|form.write().classification=e.value(),options:super::select::record_choices(&choices,&["entity_type"],"Leave unclassified")}
            p{"A name is enough to create an instance. Classification can be added later, then refined to a descendant without replacing its identity."}
        }
        if form.read().kind=="work"{label{r#for:"work-kind","Work kind"}super::select::RichSelect {id:"work-kind",disabled,value:form.read().work_kind.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().work_kind=e.value(),options:super::select::choices(&[("","Choose a work kind"),("novel","Novel"),("story","Story"),("series_chapter","Series Chapter"),("play","Play"),("film","Film"),("other","Other")])}}
        if ["entity","work"].contains(&form.read().kind.as_str()){
            fieldset{legend{"World associations"}p{"Selecting several worlds preserves one shared identity. Leaving all unchecked declares no association; it does not establish location."}
                for w in worlds {label{class:"check-label",input{r#type:"checkbox",disabled,checked:form.read().worlds.contains(&w["record_id"].as_str().unwrap_or_default().replacen("rec_","wld_",1)),onchange:{let id=w["record_id"].as_str().unwrap_or_default().replacen("rec_","wld_",1);move|e|{if e.checked(){form.write().worlds.push(id.clone());}else{form.write().worlds.retain(|x|x!=&id);}}}}{w["label"].as_str().unwrap_or_default().to_string()}}}
                if !form.read().worlds.is_empty(){label{r#for:"world-role","Association role"}input{id:"world-role",disabled,value:form.read().role.clone(),oninput:move|e|form.write().role=e.value()}}
            }
        }
        if form.read().kind=="work_version"{
            label{r#for:"version-work","Parent work"}super::select::RichSelect {id:"version-work",disabled,value:form.read().work.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().work=e.value(),options:super::select::record_choices(&works, &["work"], "Choose a work")}
            label{r#for:"work-binding","Canon binding"}super::select::RichSelect {id:"work-binding",disabled,value:form.read().binding.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().binding=e.value(),options:super::select::choices(&[("","Choose explicitly"),("current","The currently pinned continuity and revision"),("unbound","Explicitly unbound / under review")])}
        }
        if form.read().kind=="story_context" {
            p{"Parentage does not copy facts or make this context objective reality. Publish it before selecting it for local writing."}
            label{r#for:"context-kind","Context kind"}super::select::RichSelect{id:"context-kind",disabled,value:form.read().context_kind.clone(),options:super::select::choices(&[("","Choose explicitly"),("dream","Dream"),("account","Account"),("embedded","Embedded story"),("narrator","Narrator account")]),onchange:move|e:crate::select::SelectionEvent|form.write().context_kind=e.value()}
            if form.read().context_kind=="narrator"{label{r#for:"context-narrator","Existing narrator entity"}super::select::RichSelect{id:"context-narrator",disabled,value:form.read().narrator.clone(),options:super::select::record_choices(&choices,&["entity"],"Choose explicitly"),onchange:move|e:crate::select::SelectionEvent|form.write().narrator=e.value()}}
            label{r#for:"context-parent","Parent context"}super::select::RichSelect{id:"context-parent",disabled,value:form.read().parent_context.clone(),options:super::select::record_choices(&choices,&["represented_context"],"Choose parent explicitly"),onchange:move|e:crate::select::SelectionEvent|form.write().parent_context=e.value()}
            label{r#for:"context-calendar","Authored calendar"}super::select::RichSelect{id:"context-calendar",disabled,value:form.read().calendar.clone(),options:super::select::typed_id_choices(&choices,"calendar","cal_","Choose calendar explicitly"),onchange:move|e:crate::select::SelectionEvent|form.write().calendar=e.value()}
            label{r#for:"context-story-time","Initial story time (exact fictional tick or Gregorian timestamp)"}input{id:"context-story-time",disabled,value:form.read().story_time.clone(),oninput:move|e|form.write().story_time=e.value()}
        }
        if form.read().kind=="scene_ref"{
            p{"Inspect an edition and any depicted events to load their pinned references. Depicted event times, narration time and reader order stay separate. No disclosures are inferred."}
            label{r#for:"scene-edition","Published work edition"}super::select::RichSelect{id:"scene-edition",disabled,value:form.read().work.clone(),options:super::select::record_choices(&choices,&["work_version"],"Inspect and choose edition"),onchange:move|e:crate::select::SelectionEvent|form.write().work=e.value()}
            label{r#for:"scene-narration","Narration context and time"}super::select::RichSelect{id:"scene-narration",disabled,value:form.read().parent_context.clone(),options:super::select::record_choices(&choices,&["represented_context"],"Choose narrator context"),onchange:move|e:crate::select::SelectionEvent|form.write().parent_context=e.value()}
            label{r#for:"scene-viewpoint","Viewpoint (optional)"}super::select::RichSelect{id:"scene-viewpoint",disabled,value:form.read().scene_viewpoint.clone(),options:super::select::record_choices(&choices,&["entity"],"Unspecified"),onchange:move|e:crate::select::SelectionEvent|form.write().scene_viewpoint=e.value()}
            label{r#for:"scene-order","Reader order (optional, not story time)"}input{id:"scene-order",disabled,value:form.read().order.clone(),oninput:move|e|form.write().order=e.value()}
            p{"Explicit reader reveals (independent of depiction and character knowledge). Inspect targets first; they must match the edition’s pinned canon."}
            for target in choices.iter().filter(|c|["entity","assertion","event"].contains(&c["kind"].as_str().unwrap_or_default())){label{class:"check-label",input{r#type:"checkbox",disabled,checked:form.read().scene_disclosures.iter().any(|id|target["record_id"]==*id),onchange:{let id=target["record_id"].as_str().unwrap_or_default().to_string();move|e|{if e.checked(){form.write().scene_disclosures.push(id.clone());}else{form.write().scene_disclosures.retain(|old|old!=&id);}}}}{format!("Reveal: {}",target["label"].as_str().unwrap_or_default())}}}
            for event in choices.iter().filter(|c|c["kind"]=="event"&&c["definition"]["occurrence"]=="occurred"){label{class:"check-label",input{r#type:"checkbox",disabled,checked:form.read().scene_events.iter().any(|id|event["record_id"]==*id),onchange:{let id=event["record_id"].as_str().unwrap_or_default().to_string();move|e|{if e.checked(){form.write().scene_events.push(id.clone());}else{form.write().scene_events.retain(|old|old!=&id);}}}}{event["label"].as_str().unwrap_or_default().to_string()}}}
        }
        button{class:"secondary",disabled,onclick:{let frame=frame.clone();move|_|match if form.read().kind=="story_context"{form.read().create_context(&frame,&choices)}else if form.read().kind=="scene_ref"{form.read().create_scene(&frame,&choices)}else{form.read().create(&frame)}{Ok(op)=>{onadd.call(op);error.set(String::new());},Err(e)=>error.set(e)}},"Add to draft"}
        if selected["payload"]["record_kind"]=="saga"{
            h3{"Add or reorder work in the inspected saga"}
            label{r#for:"saga-work","Work"}super::select::RichSelect {id:"saga-work",disabled,value:form.read().work.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().work=e.value(),options:super::select::record_choices(&works, &["work"], "Choose a work")}
            label{r#for:"saga-role","Membership role"}input{id:"saga-role",disabled,value:form.read().role.clone(),oninput:move|e|form.write().role=e.value()}
            label{r#for:"saga-order","Order (blank means unordered)"}input{id:"saga-order",disabled,value:form.read().order.clone(),oninput:move|e|form.write().order=e.value()}
            button{class:"secondary",disabled,onclick:{let frame=frame.clone();move|_|match form.read().membership(&frame,&selected){Ok(op)=>{onadd.call(op);error.set(String::new());},Err(e)=>error.set(e)}},"Add saga membership change"}
        }
        if !error().is_empty(){p{role:"alert","{error}"}}
    }}
}
#[cfg(test)]
mod tests {
    use super::*;
    fn frame() -> Frame {
        serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"time":{"kind":"timeless"},"perspective":"author"})).unwrap()
    }
    #[test]
    fn incremental_identity_operations_are_typed_and_visible_in_drafts() {
        let mut form = Form {
            kind: "entity".into(),
            name: "Mara".into(),
            ..Default::default()
        };
        let minimal = form.create(&frame()).unwrap();
        assert_eq!(minimal["kind"], "introduce_instance");
        assert_eq!(minimal["name"]["text"], "Mara");
        assert!(minimal["classification"].is_null());
        assert!(minimal["world_associations"].as_array().unwrap().is_empty());
        let options = crate::author::choices(&[], &[], &json!([minimal]).to_string());
        assert_eq!(options[0]["record_id"], minimal["client_ref"]);
        assert_eq!(options[0]["label"], "Mara (draft)");
        assert_eq!(
            crate::readable::operation_summary(&minimal),
            "Create instance: Mara (unclassified)"
        );
        form.classification = "invalid".into();
        assert!(form.create(&frame()).is_err());
        form.classification = "rec_000000000000000000000002".into();
        let classified = form.create(&frame()).unwrap();
        assert_eq!(classified["classification"], form.classification);
        assert_eq!(
            crate::readable::operation_summary(&classified),
            "Create instance: Mara (classified)"
        );
        let selected = json!({"identity":{"record_id":"rec_000000000000000000000005"},"record_version_id":"ver_000000000000000000000005"});
        let refine = crate::inspector_editor::operation(
            &frame(),
            &selected,
            "refine_classification",
            &form.classification,
            "",
            None,
        )
        .unwrap();
        assert_eq!(refine["kind"], "refine_classification");
        assert_eq!(
            refine["record"]["record"],
            selected["identity"]["record_id"]
        );
        assert_eq!(refine["expected_version"], selected["record_version_id"]);
        assert!(
            crate::readable::operation_summary(&refine).contains("Set or refine classification")
        );
    }

    #[test]
    fn review_renders_incremental_identity_changes() {
        let op = Form {
            kind: "entity".into(),
            name: "Mara".into(),
            ..Default::default()
        }
        .create(&frame())
        .unwrap();
        let selected = json!({"identity":{"record_id":"rec_000000000000000000000005"},"record_version_id":"ver_000000000000000000000005"});
        let refine = crate::inspector_editor::operation(
            &frame(),
            &selected,
            "refine_classification",
            "rec_000000000000000000000002",
            "",
            None,
        )
        .unwrap();
        let mut dom = dioxus::core::VirtualDom::new_with_props(
            crate::readable::OperationReview,
            crate::readable::OperationReviewProps {
                operations: json!([op, refine]),
            },
        );
        let mutations = dom.rebuild_to_vec();
        for text in [
            "Create instance: Mara (unclassified)",
            "Set or refine classification",
        ] {
            assert!(mutations.edits.iter().any(|edit|matches!(edit,dioxus::core::Mutation::CreateTextNode { value, .. } if value.contains(text))),"missing review text: {text}");
        }
    }

    #[test]
    fn narrator_scene_form_keeps_time_order_and_edition_separate() {
        let frame=frame();
        let choices=vec![
            json!({"kind":"work_version","record_id":"rec_000000000000000000000002","record_version_id":"ver_000000000000000000000002"}),
            json!({"kind":"represented_context","record_id":"rec_000000000000000000000003","definition":{"kind":{"kind":"narrator"},"chronology":{}}}),
            json!({"kind":"entity","record_id":"rec_000000000000000000000004"}),
            json!({"kind":"event","record_id":"rec_000000000000000000000005","definition":{"occurrence":"occurred"}}),
        ];
        let mut form=Form{kind:"scene_ref".into(),name:"Earlier gate passage".into(),work:"rec_000000000000000000000002".into(),parent_context:"rec_000000000000000000000003".into(),order:"7".into(),scene_viewpoint:"rec_000000000000000000000004".into(),scene_events:vec!["rec_000000000000000000000005".into()],..Default::default()};
        let op=form.create_scene(&frame,&choices).unwrap();
        assert_eq!(op["payload"]["workVersion"]["version"],"ver_000000000000000000000002");
        assert_eq!(op["payload"]["narrativePosition"],7);
        assert_eq!(op["payload"]["narrationFrame"]["record"],"rec_000000000000000000000003");
        assert_eq!(op["payload"]["depictedEvents"][0]["record"],"rec_000000000000000000000005");
        assert!(op["payload"]["disclosedRecords"].is_null() || op["payload"]["disclosedRecords"].as_array().unwrap().is_empty());
        form.scene_disclosures=vec!["rec_000000000000000000000004".into()];
        let reveal=form.create_scene(&frame,&choices).unwrap();assert_eq!(reveal["payload"]["disclosedRecords"][0]["record"],form.scene_disclosures[0]);
        let selected=json!({"identity":{"record_id":"rec_000000000000000000000006"},"record_version_id":"ver_000000000000000000000006","payload":reveal["payload"]});
        let clear=crate::inspector_editor::operation(&frame,&selected,"scene_clear_disclosures","","Explicitly withhold the reveal",None).unwrap();
        assert!(clear["replacement"]["disclosedRecords"].as_array().is_none_or(Vec::is_empty));assert_eq!(clear["replacement"]["workVersion"],reveal["payload"]["workVersion"]);assert_eq!(clear["replacement"]["depictedEvents"],reveal["payload"]["depictedEvents"]);assert_eq!(clear["expected_version"],selected["record_version_id"]);
        assert!(crate::inspector_editor::operation(&frame,&selected,"scene_order","8","",None).is_err());
        let ordered=crate::inspector_editor::operation(&frame,&selected,"scene_order","8","Correct reader order",None).unwrap();assert_eq!(ordered["replacement"]["narrativePosition"],8);assert_eq!(ordered["replacement"]["disclosedRecords"],reveal["payload"]["disclosedRecords"]);
        let rows=vec![json!({"identity":{"record_id":"rec_000000000000000000000004"},"payload":{"record_kind":"entity","names":[{"text":"Gate"}]}}),json!({"identity":{"record_id":"rec_000000000000000000000008"},"payload":{"record_kind":"property","key":"location"}}),json!({"identity":{"record_id":"rec_000000000000000000000009"},"payload":{"record_kind":"proposition","subject":{"record":"rec_000000000000000000000004"},"predicate":{"record":"rec_000000000000000000000008"},"value":{"kind":"text","text":"ridge"}}}),json!({"identity":{"record_id":"rec_000000000000000000000010"},"payload":{"record_kind":"assertion","proposition":{"record":"rec_000000000000000000000009"},"polarity":"support"}})];
        let options=crate::author::choices(&[],&rows,"[]");assert_eq!(options.iter().find(|row|row["kind"]=="assertion").unwrap()["label"],"Gate — location: ridge (support)");
        let mut stale=choices.clone();stale[0]["record_version_id"]=Value::Null;
        assert!(form.create_scene(&frame,&stale).unwrap_err().contains("exact version"));
        form.order="tomorrow".into();assert!(form.create_scene(&frame,&choices).is_err());
    }
    #[test]
    fn shared_identity_and_work_binding_are_explicit() {
        let mut f = Form {
            kind: "entity".into(),
            name: "Traveler".into(),
            worlds: vec![
                "wld_000000000000000000000002".into(),
                "wld_000000000000000000000003".into(),
            ],
            ..Default::default()
        };
        assert!(f.create(&frame()).is_err());
        f.role = "appears in".into();
        assert_eq!(
            f.create(&frame()).unwrap()["world_associations"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        f.kind = "work_version".into();
        f.work = "rec_000000000000000000000004".into();
        assert!(f.create(&frame()).is_err());
        f.binding = "current".into();
        let op = f.create(&frame()).unwrap();
        assert_eq!(
            op["payload"]["binding"]["revision"],
            frame().revision.as_str()
        );
        let selected = json!({"identity":{"record_id":"rec_000000000000000000000005"},"record_version_id":"ver_000000000000000000000005"});
        assert!(f.membership(&frame(), &selected).is_ok());
        f.order = "-1".into();
        assert!(f.membership(&frame(), &selected).is_err());
    }
}

#[cfg(test)]
#[path = "identity_workflow.rs"]
pub(crate) mod workflow;
