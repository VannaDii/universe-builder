//! Typed identity and narrative edits, all staged into the same proposal draft.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{ids::*, records::DomainOperation, Frame};
#[derive(Clone, Default)]
struct Form {
    kind: String,
    name: String,
    work_kind: String,
    worlds: Vec<String>,
    role: String,
    work: String,
    order: String,
    binding: String,
}
fn checked(value: Value) -> Result<Value, String> {
    let operation: DomainOperation = serde_json::from_value(value).map_err(|e| e.to_string())?;
    serde_json::to_value(operation).map_err(|e| e.to_string())
}
impl Form {
    fn create(&self, frame: &Frame) -> Result<Value, String> {
        if self.name.trim().is_empty() {
            return Err("Enter a name.".into());
        }
        if !self.worlds.is_empty() && self.role.trim().is_empty() {
            return Err("Describe the role of the selected worlds.".into());
        }
        let associations:Vec<_>=self.worlds.iter().map(|id|json!({"world":id,"role":self.role,"validity":{"kind":"unspecified"},"qualifiers":{}})).collect();
        let (kind, record) = match self.kind.as_str() {
            "entity" => (
                "create_entity",
                json!({"names":[],"types":[],"worldAssociations":associations,"labels":{"en":self.name},"metadata":{}}),
            ),
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
        summary{"Create an entity, world, work or saga"}
        label{r#for:"draft-kind","Record kind"}super::select::RichSelect {id:"draft-kind",disabled,value:form.read().kind.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().kind=e.value(),options:super::select::choices(&[("","Choose a kind"),("entity","Character or entity"),("world","World"),("work","Narrative work"),("saga","Saga or series"),("work_version","Version of a narrative work")])}
        label{r#for:"draft-name","Name or version label"}input{id:"draft-name",disabled,value:form.read().name.clone(),oninput:move|e|form.write().name=e.value()}
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
        button{class:"secondary",disabled,onclick:{let frame=frame.clone();move|_|match form.read().create(&frame){Ok(op)=>{onadd.call(op);error.set(String::new());},Err(e)=>error.set(e)}},"Add to draft"}
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
            f.create(&frame()).unwrap()["record"]["worldAssociations"]
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
