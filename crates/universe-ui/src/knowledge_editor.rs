//! Explicit attitude authoring; recording knowledge never silently asserts reality.
use super::select::{Choice, RichSelect, SelectionEvent};
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{chronology::Chronology, ids::RecordId, records::DomainOperation, Frame};
#[derive(Clone, Default)]
struct Form {
    holder: String,
    proposition: String,
    attitude: String,
    start: String,
    end: String,
    lasting: bool,
    basis: String,
    context: String,
    acquired: String,
    mode: String,
    communication: String,
    interpretation: String,
    world: String,
}
fn contexts(choices: &[Value], frame: &Frame) -> Vec<Choice> {
    let mut result =
        super::select::record_choices(choices, &["represented_context"], "Choose truth context");
    if !result
        .iter()
        .any(|c| c.value == frame.context.record.as_str())
    {
        result.push(Choice::new(
            frame.context.record.as_str(),
            "Current represented context",
        ));
    }
    result
}
impl Form {
    fn build(
        &self,
        frame: &Frame,
        clock: Option<&Chronology>,
        choices: &[Value],
    ) -> Result<Value, String> {
        if self.holder.is_empty()
            || self.proposition.is_empty()
            || !["believes", "suspects", "rejects", "remembers", "knows"]
                .contains(&self.attitude.as_str())
            || self.basis.trim().is_empty()
        {
            return Err(
                "Choose the character, proposition and attitude, and explain its basis.".into(),
            );
        }
        let selected_clock = if self.attitude == "knows" {
            if self.context.is_empty()
                || !contexts(choices, frame)
                    .iter()
                    .any(|c| c.value == self.context)
            {
                return Err("Choose an existing truth context.".into());
            }
            choices
                .iter()
                .find(|r| r["record_id"] == self.context)
                .and_then(|r| {
                    serde_json::from_value::<Chronology>(r["definition"]["chronology"].clone()).ok()
                })
                .or_else(|| {
                    (self.context == frame.context.record.as_str())
                        .then(|| clock.cloned())
                        .flatten()
                })
        } else {
            clock.cloned()
        }
        .ok_or("The selected context needs an authored clock.")?;
        let a = selected_clock.coordinate(&self.start)?;
        let b = if self.lasting {
            json!({"kind":"unbounded"})
        } else {
            let b = selected_clock.coordinate(&self.end)?;
            if a.parse::<i128>().map_err(|e| e.to_string())?
                >= b.parse::<i128>().map_err(|e| e.to_string())?
            {
                return Err("The end must be later than attitude onset.".into());
            }
            json!({"kind":"exact","value":b})
        };
        let rr = |id: &str| json!({"universe":frame.universe,"record":id});
        let mut record = json!({"holder":rr(&self.holder),"proposition":rr(&self.proposition),"attitude":self.attitude,"validity":{"kind":"calendar_interval","calendar":selected_clock.calendar,"start":{"kind":"exact","value":a},"end":b},"basis":{"kind":"author_decision","note":self.basis}});
        if self.attitude == "knows" {
            let acquired = selected_clock.coordinate(&self.acquired)?;
            if acquired.parse::<i128>().map_err(|e| e.to_string())?
                > a.parse::<i128>().map_err(|e| e.to_string())?
            {
                return Err("Acquisition must be at or before attitude onset.".into());
            }
            let basis = match self.mode.as_str() {
                "author_established" => json!({"kind":"author_established"}),
                "communication_receipt" => {
                    if self.communication.is_empty()
                        || !choices.iter().any(|r| {
                            r["kind"] == "communication" && r["record_id"] == self.communication
                        })
                        || self.interpretation != self.proposition
                    {
                        return Err("Choose a message and explicitly select the claimed proposition as its interpretation.".into());
                    }
                    json!({"kind":"communication_receipt","communication":rr(&self.communication),"interpretation":rr(&self.interpretation)})
                }
                _ => return Err("Choose how knowledge was acquired.".into()),
            };
            let mut acquisition = json!({"truthContext":rr(&self.context),"time":{"kind":"exact","calendar":selected_clock.calendar,"value":acquired},"basis":basis});
            if !self.world.is_empty() {
                if !choices
                    .iter()
                    .any(|r| r["kind"] == "world" && r["record_id"] == self.world)
                {
                    return Err("Choose an existing truth world.".into());
                }
                acquisition["world"] = rr(&self.world);
            }
            record["acquisition"] = acquisition;
        }
        let op:DomainOperation=serde_json::from_value(json!({"kind":"add_belief","client_ref":RecordId::generate(&mut rand::rng()),"record":record})).map_err(|e|e.to_string())?;
        serde_json::to_value(op).map_err(|e| e.to_string())
    }
}
#[component]
pub fn KnowledgeEditor(
    frame: Frame,
    clock: Option<Chronology>,
    choices: Vec<Value>,
    disabled: bool,
    onadd: EventHandler<Value>,
) -> Element {
    let mut holder = use_signal(String::new);
    let mut proposition = use_signal(String::new);
    let mut attitude = use_signal(String::new);
    let mut start = use_signal(String::new);
    let mut end = use_signal(String::new);
    let mut lasting = use_signal(|| false);
    let mut basis = use_signal(String::new);
    let mut truth_context = use_signal(String::new);
    let mut acquired = use_signal(String::new);
    let mut mode = use_signal(String::new);
    let mut communication = use_signal(String::new);
    let mut interpretation = use_signal(String::new);
    let mut world = use_signal(String::new);
    let mut status = use_signal(String::new);
    rsx! {details{class:"panel",summary{"Belief, knowledge and memory"}
        p{"Record an explicit attitude toward an existing proposition. A belief does not establish objective truth. Sending, receiving, observing or being present never automatically establishes knowledge."}
        label{r#for:"knowledge-holder","Whose attitude"}RichSelect{id:"knowledge-holder",disabled,value:holder(),options:super::select::record_choices(&choices,&["entity"],"Choose a character"),onchange:move|e:SelectionEvent|holder.set(e.value())}
        label{r#for:"knowledge-proposition","Proposition"}RichSelect{id:"knowledge-proposition",disabled,value:proposition(),options:super::select::record_choices(&choices,&["proposition"],"Choose an existing proposition"),onchange:move|e:SelectionEvent|proposition.set(e.value())}
        label{r#for:"knowledge-kind","Attitude"}RichSelect{id:"knowledge-kind",disabled,value:attitude(),options:vec![Choice::new("","Choose an attitude"),Choice::described("believes","Believes","The character accepts it; objective truth remains separate."),Choice::described("suspects","Suspects","Tentative belief without established knowledge."),Choice::described("rejects","Rejects","The character rejects it; this does not refute reality."),Choice::described("remembers","Remembers","Explicit remembered content, which may be mistaken."),Choice::described("knows","Knows","Explicit author establishment or interpreted communication receipt, checked against authored policies.")],onchange:move|e:SelectionEvent|attitude.set(e.value())}
        if attitude()=="knows" {
            label{r#for:"knowledge-truth-context","Truth context"}RichSelect{id:"knowledge-truth-context",disabled,value:truth_context(),options:contexts(&choices,&frame),onchange:move|e:SelectionEvent|truth_context.set(e.value())}
            label{r#for:"knowledge-world","Truth world"}RichSelect{id:"knowledge-world",disabled,value:world(),options:super::select::record_choices(&choices,&["world"],"Universe-wide truth evidence"),onchange:move|e:SelectionEvent|world.set(e.value())}
            label{r#for:"knowledge-acquisition","How knowledge was acquired"}RichSelect{id:"knowledge-acquisition",disabled,value:mode(),options:vec![Choice::new("","Choose an acquisition path"),Choice::new("author_established","Explicit author establishment"),Choice::new("communication_receipt","Interpreted communication receipt")],onchange:move|e:SelectionEvent|mode.set(e.value())}
            if mode()=="communication_receipt" {
                label{r#for:"knowledge-message","Received message"}RichSelect{id:"knowledge-message",disabled,value:communication(),options:super::select::record_choices(&choices,&["communication"],"Choose a message"),onchange:move|e:SelectionEvent|communication.set(e.value())}
                label{r#for:"knowledge-interpretation","Explicitly interpreted proposition"}RichSelect{id:"knowledge-interpretation",disabled,value:interpretation(),options:super::select::record_choices(&choices,&["proposition"],"Choose the claimed proposition"),onchange:move|e:SelectionEvent|interpretation.set(e.value())}
                p{"Receipt alone does not establish understanding. Review checks the actual recipient, content, receipt time and supported truth."}
            }
            label{r#for:"knowledge-acquired","Acquisition date or tick in the truth context"}input{id:"knowledge-acquired",disabled,value:acquired,oninput:move|e|acquired.set(e.value())}
            p{"Attitude onset and acquisition use the selected truth context’s clock. No clock conversion is inferred."}
        }
        label{r#for:"knowledge-start","Attitude begins at authored calendar date or tick"}input{id:"knowledge-start",disabled,value:start,oninput:move|e|start.set(e.value())}
        label{class:"check-label",input{r#type:"checkbox",disabled,checked:lasting,onchange:move|e|lasting.set(e.checked())}"Explicitly continues without an end"}
        if !lasting(){label{r#for:"knowledge-end","Exclusive end date or tick"}input{id:"knowledge-end",disabled,value:end,oninput:move|e|end.set(e.value())}}
        label{r#for:"knowledge-basis","Acquisition or interpretation basis"}textarea{id:"knowledge-basis",disabled,value:basis,oninput:move|e|basis.set(e.value())}
        button{disabled,onclick:move|_|{
            let result=Form{holder:holder(),proposition:proposition(),attitude:attitude(),start:start(),end:end(),lasting:lasting(),basis:basis(),context:truth_context(),acquired:acquired(),mode:mode(),communication:communication(),interpretation:interpretation(),world:world()}.build(&frame,clock.as_ref(),&choices);match result{Ok(op)=>{onadd.call(op);status.set("Attitude added to the draft for review.".into());},Err(e)=>status.set(e)}
        },"Add attitude to draft"}
        p{role:"status","{status}"}
    }}
}

#[cfg(test)]
#[path = "knowledge_tests.rs"]
mod tests;
