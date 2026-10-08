//! Authored delivery records; receipt never infers understanding.
use super::select::{Choice, RichSelect, SelectionEvent};
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{chronology::Chronology, ids::RecordId, DomainOperation, Frame};

pub(super) fn label(record: &Value, id: &Value) -> String {
    format!(
        "Message via {} · sent {} · {}",
        record["channel"].as_str().unwrap_or("unspecified channel"),
        record["sentAt"]["value"]
            .as_str()
            .unwrap_or("unspecified time"),
        id.as_str().unwrap_or("pending record")
    )
}

#[derive(Clone, Default)]
struct Form {
    sender: String,
    intended: Vec<String>,
    actual: Vec<String>,
    content: Vec<String>,
    channel: String,
    sent_known: bool,
    sent: String,
    receipt: String,
    received: String,
    distorted: bool,
}
impl Form {
    fn build(
        &self,
        frame: &Frame,
        clock: Option<&Chronology>,
        choices: &[Value],
    ) -> Result<Value, String> {
        let exists = |id: &str, kind: &str| {
            choices
                .iter()
                .any(|r| r["kind"] == kind && r["record_id"] == id)
        };
        if !exists(&self.sender, "entity")
            || self
                .intended
                .iter()
                .chain(&self.actual)
                .any(|r| !exists(r, "entity"))
            || self.content.iter().any(|r| !exists(r, "proposition"))
        {
            return Err(
                "Choose an existing sender, recipient entities and content propositions.".into(),
            );
        }
        let time = |text: &str| -> Result<Value, String> {
            let clock = clock.ok_or("An authored calendar is required for an exact time.")?;
            Ok(json!({"kind":"exact","calendar":clock.calendar,"value":clock.coordinate(text)?}))
        };
        let sent = if self.sent_known {
            time(&self.sent)?
        } else {
            json!({"kind":"unspecified"})
        };
        let received = match self.receipt.as_str() {
            "" | "none" => Value::Null,
            "unspecified" => json!({"kind":"unspecified"}),
            "exact" => time(&self.received)?,
            _ => return Err("Choose whether a receipt time is recorded.".into()),
        };
        if !self.actual.is_empty() && received.is_null() {
            return Err(
                "Actual recipients require an explicit receipt time, which may be unspecified."
                    .into(),
            );
        }
        let rr = |id: &str| json!({"universe":frame.universe,"record":id});
        let refs = |ids: &[String]| ids.iter().map(|id| rr(id)).collect::<Vec<_>>();
        let op:DomainOperation=serde_json::from_value(json!({"kind":"record_communication","client_ref":RecordId::generate(&mut rand::rng()),"record":{
            "sender":rr(&self.sender),"intendedRecipients":refs(&self.intended),"actualRecipients":refs(&self.actual),"content":refs(&self.content),
            "channel":if self.channel.is_empty(){Value::Null}else{json!(self.channel)},"sentAt":sent,"receivedAt":received,"distorted":self.distorted}})).map_err(|e|e.to_string())?;
        serde_json::to_value(op).map_err(|e| e.to_string())
    }
}
fn toggle(values: &mut Vec<String>, value: String, checked: bool) {
    values.retain(|v| v != &value);
    if checked {
        values.push(value);
    }
}
#[component]
pub fn CommunicationEditor(
    frame: Frame,
    clock: Option<Chronology>,
    choices: Vec<Value>,
    disabled: bool,
    onadd: EventHandler<Value>,
) -> Element {
    let mut form = use_signal(Form::default);
    let mut status = use_signal(String::new);
    rsx! { details { class:"panel", summary {"Communication and delivery"}
        p {"Select intended and actual recipients separately. Empty recipient lists remain empty. Actual receipt does not establish understanding or knowledge; record an explicit interpretation through knowledge acquisition separately."}
        label {r#for:"message-sender","Sender"}RichSelect{id:"message-sender",disabled,value:form().sender,options:super::select::record_choices(&choices,&["entity"],"Choose a sender"),onchange:move|e:SelectionEvent|form.write().sender=e.value()}
        for (group,label,kind) in [("intended","Intended recipients","entity"),("actual","Actual recipients","entity"),("content","Proposition content","proposition")] {
            fieldset { legend {"{label}"}
                p {"Only the checked records are included."}
                for row in choices.iter().filter(|r|r["kind"]==kind) {
                    label { class:"check-label",
                        input {r#type:"checkbox",disabled,checked:{let f=form();let values=match group{"intended"=>f.intended,"actual"=>f.actual,_=>f.content};values.iter().any(|v|row["record_id"]==*v)},onchange:{let id=row["record_id"].as_str().unwrap_or_default().to_string();move|e|{let mut f=form.write();let values=match group{"intended"=>&mut f.intended,"actual"=>&mut f.actual,_=>&mut f.content};toggle(values,id.clone(),e.checked());}}}
                        {row["label"].as_str().unwrap_or("Existing record")}
                    }
                }
            }
        }
        label {r#for:"message-channel","Channel (leave blank if unspecified)"}input{id:"message-channel",disabled,value:form().channel,oninput:move|e|form.write().channel=e.value()}
        label {class:"check-label",input{r#type:"checkbox",disabled,checked:form().sent_known,onchange:move|e|form.write().sent_known=e.checked()}"Record an exact send time"}
        if form().sent_known {label{r#for:"message-sent","Sent date or tick"}input{id:"message-sent",disabled,value:form().sent,oninput:move|e|form.write().sent=e.value()}}
        label{r#for:"message-receipt","Receipt time"}RichSelect{id:"message-receipt",disabled,value:form().receipt,options:vec![Choice::new("","No receipt recorded"),Choice::new("unspecified","Receipt time unspecified"),Choice::new("exact","Exact receipt time")],onchange:move|e:SelectionEvent|form.write().receipt=e.value()}
        if form().receipt=="exact" {label{r#for:"message-received","Received date or tick"}input{id:"message-received",disabled,value:form().received,oninput:move|e|form.write().received=e.value()}}
        p {"Times use this context’s authored calendar. Channel policies validate chronology; no conversion or delivery is inferred."}
        label{class:"check-label",input{r#type:"checkbox",disabled,checked:form().distorted,onchange:move|e|form.write().distorted=e.checked()}"The message was distorted"}
        button{disabled,onclick:move|_|match form().build(&frame,clock.as_ref(),&choices){Ok(op)=>{onadd.call(op);status.set("Communication added to the draft. Review, validate and approve before publication.".into());},Err(e)=>status.set(e)},"Add communication to draft"}
        p{role:"status","{status}"}
    } }
}
#[cfg(test)]
#[path = "communication_tests.rs"]
mod tests;
