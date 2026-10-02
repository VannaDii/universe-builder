//! Explicit attitude authoring; recording knowledge never silently asserts reality.
use super::select::{Choice, RichSelect, SelectionEvent};
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{chronology::Chronology, ids::RecordId, records::DomainOperation, Frame};
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
    let mut status = use_signal(String::new);
    rsx! {details{class:"panel",summary{"Belief, knowledge and memory"}
        p{"Record an explicit attitude toward an existing proposition. A belief does not establish objective truth. Sending, receiving, observing or being present never automatically establishes knowledge."}
        label{r#for:"knowledge-holder","Whose attitude"}RichSelect{id:"knowledge-holder",disabled,value:holder(),options:super::select::record_choices(&choices,&["entity"],"Choose a character"),onchange:move|e:SelectionEvent|holder.set(e.value())}
        label{r#for:"knowledge-proposition","Proposition"}RichSelect{id:"knowledge-proposition",disabled,value:proposition(),options:super::select::record_choices(&choices,&["proposition"],"Choose an existing proposition"),onchange:move|e:SelectionEvent|proposition.set(e.value())}
        label{r#for:"knowledge-kind","Attitude"}RichSelect{id:"knowledge-kind",disabled,value:attitude(),options:vec![Choice::new("","Choose an attitude"),Choice::described("believes","Believes","The character accepts it; objective truth remains separate."),Choice::described("suspects","Suspects","Tentative belief without established knowledge."),Choice::described("rejects","Rejects","The character rejects it; this does not refute reality."),Choice::described("remembers","Remembers","Explicit remembered content, which may be mistaken."),Choice::described("knows","Knows","An author-established acquisition supported by the explanation below.")],onchange:move|e:SelectionEvent|attitude.set(e.value())}
        label{r#for:"knowledge-start","Acquired at the authored calendar date or tick"}input{id:"knowledge-start",disabled,value:start,oninput:move|e|start.set(e.value())}
        label{class:"check-label",input{r#type:"checkbox",disabled,checked:lasting,onchange:move|e|lasting.set(e.checked())}"Explicitly continues without an end"}
        if !lasting(){label{r#for:"knowledge-end","Exclusive end date or tick"}input{id:"knowledge-end",disabled,value:end,oninput:move|e|end.set(e.value())}}
        label{r#for:"knowledge-basis","Acquisition or interpretation basis"}textarea{id:"knowledge-basis",disabled,value:basis,oninput:move|e|basis.set(e.value())}
        button{disabled,onclick:move|_|{
            let result=(||{
                let clock=clock.as_ref().ok_or("This represented context needs an authored clock.")?;
                if holder().is_empty()||proposition().is_empty()||attitude().is_empty()||basis().trim().is_empty(){return Err("Choose the character, proposition and attitude, and explain its basis.".to_owned());}
                let a=clock.coordinate(&start())?;let b=if lasting(){json!({"kind":"unbounded"})}else{let b=clock.coordinate(&end())?;if a.parse::<i128>().map_err(|e|e.to_string())?>=b.parse::<i128>().map_err(|e|e.to_string())?{return Err("The end must be later than acquisition.".into());}json!({"kind":"exact","value":b})};
                let rr=|id:String|json!({"universe":frame.universe,"record":id});
                let op=json!({"kind":"add_belief","client_ref":RecordId::generate(&mut rand::rng()),"record":{"holder":rr(holder()),"proposition":rr(proposition()),"attitude":attitude(),"certainty":null,"validity":{"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":a},"end":b},"basis":{"kind":"author_decision","note":basis()}}});
                serde_json::from_value::<DomainOperation>(op.clone()).map_err(|e|e.to_string())?;Ok::<_,String>(op)
            })();match result{Ok(op)=>{onadd.call(op);status.set("Attitude added to the draft for review.".into());},Err(e)=>status.set(e)}
        },"Add attitude to draft"}
        p{role:"status","{status}"}
    }}
}
