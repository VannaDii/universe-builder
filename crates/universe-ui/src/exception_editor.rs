//! An exception is a reviewed decision plus an exact-version scoped record.
use super::select::{Choice, RichSelect, SelectionEvent};
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{chronology::Chronology, ids::RecordId, records::DomainOperation, Frame};

#[component]
pub fn ExceptionEditor(
    frame: Frame,
    profile: String,
    clock: Option<Chronology>,
    records: Vec<Value>,
    findings: Value,
    disabled: bool,
    onadd: EventHandler<Vec<Value>>,
) -> Element {
    let mut selected = use_signal(String::new);
    let mut period = use_signal(|| "declared".to_owned());
    let mut start = use_signal(String::new);
    let mut end = use_signal(String::new);
    let mut rationale = use_signal(String::new);
    let mut status = use_signal(String::new);
    let targets: Vec<_> = records
        .into_iter()
        .filter(|r| {
            r["payload"]["record_kind"] == "boundary"
                || (r["payload"]["record_kind"] == "rule"
                    && r["payload"]["commitPolicy"] == "block_unless_exception")
        })
        .collect();
    rsx! { details { class:"panel", summary {"Accept a scoped exception"}
        p {"Explain the departure and pin it to the current rule or boundary version. Its finding remains visible. Structural invariants cannot be waived. Validation checks the interval and the author’s authority before this can enter canon."}
        label { r#for:"exception-target", "Rule or boundary" }
        RichSelect { id:"exception-target", disabled, value:selected(), options:std::iter::once(Choice::new("","Choose the exact target")).chain(targets.iter().map(|r|Choice::described(r["identity"]["record_id"].as_str().unwrap_or_default(),r["payload"]["labels"]["en"].as_str().or_else(||r["payload"]["key"].as_str()).unwrap_or("Boundary"),"A reviewed exception applies only to this version and scope."))).collect(), onchange:move|e:SelectionEvent|selected.set(e.value()) }
        label { r#for:"exception-period", "Effective period" }
        RichSelect {id:"exception-period",disabled,value:period(),options:vec![Choice::described("declared","The target’s declared period","Preserve its existing validity; do not extend it."),Choice::described("interval","A narrower authored interval","Use the universe’s authored calendar; the end is exclusive.")],onchange:move|e:SelectionEvent|period.set(e.value())}
        if period()=="interval" {
            label { r#for:"exception-start", "Start date or tick" }input{id:"exception-start",disabled,value:start,oninput:move|e|start.set(e.value())}
            label { r#for:"exception-end", "Exclusive end date or tick" }input{id:"exception-end",disabled,value:end,oninput:move|e|end.set(e.value())}
        }
        label { r#for:"exception-reason", "Why this exception is appropriate" }textarea{id:"exception-reason",disabled,value:rationale,oninput:move|e|rationale.set(e.value())}
        button { disabled:disabled||selected().is_empty()||rationale().trim().is_empty(), onclick:move|_|{
            let result=(|| {
                let target=targets.iter().find(|r|r["identity"]["record_id"]==selected()).ok_or("Select an existing target.")?;
                let decision=RecordId::generate(&mut rand::rng());
                let rr=|id:String|json!({"universe":frame.universe,"record":id});
                let payload=&target["payload"];
                let scope=if payload["record_kind"]=="boundary" { payload["scope"].clone() } else {json!({"applicability":payload["applicability"],"context":frame.context})};
                let validity=if period()=="declared" {payload["validity"].clone()} else {
                    let clock=clock.as_ref().ok_or("An authored calendar is required.")?;
                    let a=clock.coordinate(&start())?;let b=clock.coordinate(&end())?;
                    if a.parse::<i128>().map_err(|e|e.to_string())?>=b.parse::<i128>().map_err(|e|e.to_string())? {return Err("The end must follow the start.".into());}
                    json!({"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":a},"end":{"kind":"exact","value":b}})
                };
                let fingerprints:Vec<_>=findings.as_array().into_iter().flatten().filter(|f|f["rule_id"]==selected()).map(|f|f["fingerprint"].clone()).collect();
                let operations=vec![json!({"kind":"record_issue_decision","client_ref":decision,"record":{"fingerprints":fingerprints,"mode":"accept","scope":selected(),"rationale":rationale(),"principal":profile.replacen("prf_","prn_",1)}}),json!({"kind":"add_exception","client_ref":RecordId::generate(&mut rand::rng()),"record":{"rule":rr(selected()),"ruleVersion":target["record_version_id"],"scope":scope,"validity":validity,"authorizingDecision":rr(decision.to_string()),"rationale":rationale()}})];
                for op in &operations {serde_json::from_value::<DomainOperation>(op.clone()).map_err(|e|e.to_string())?;}
                Ok::<_,String>(operations)
            })();match result {Ok(ops)=>{onadd.call(ops);status.set("Exception added to the draft. Validate and review its exact scope before approving.".into());},Err(e)=>status.set(e)}
        },"Add exception to draft" }
        p {role:"status","{status}"}
    } }
}
