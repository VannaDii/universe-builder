//! Pinned event retrieval for the shared event editor, including review context.
use dioxus::prelude::*;
use serde_json::{json, Value};
use std::collections::BTreeSet;
use universe_domain::{chronology::Chronology, Frame};
fn references(v: &Value, ids: &mut BTreeSet<String>) {
    match v {
        Value::Object(o) => {
            if let Some(id) = o
                .get("record")
                .and_then(Value::as_str)
                .filter(|id| id.starts_with("rec_"))
            {
                ids.insert(id.into());
            }
            for v in o.values() {
                references(v, ids);
            }
        }
        Value::Array(a) => {
            for v in a {
                references(v, ids);
            }
        }
        _ => {}
    }
}
pub(super) async fn load(
    root: String,
    profile: String,
    universe: String,
    context: Value,
    original: &Value,
) -> Result<(Vec<Value>, Value), String> {
    let mut records = vec![];
    let mut ids = BTreeSet::new();
    references(&original["payload"], &mut ids);
    let mut seen = BTreeSet::new();
    // Event references, then their action/property dependencies, all at the same frame.
    for _ in 0..2 {
        let pending: Vec<_> = ids.difference(&seen).cloned().collect();
        if pending.is_empty() {
            break;
        }
        for chunk in pending.chunks(100) {
            let mut args = json!({"universe":universe,"context_id":context,"record_ids":chunk,"field_groups":[]});
            loop {
                let response = crate::author::send(
                    root.clone(),
                    profile.clone(),
                    crate::author::tool("universe_get", args.clone())?,
                )
                .await?;
                for record in response["result"]["records"]
                    .as_array()
                    .ok_or("Referenced records unavailable.")?
                {
                    references(&record["payload"], &mut ids);
                    records.push(record.clone());
                }
                if response["delivery"]["complete"] == true {
                    break;
                }
                let cursor = &response["delivery"]["cursor"];
                if cursor.is_null() {
                    return Err("Event reference retrieval is incomplete.".into());
                }
                args["cursor"] = cursor.clone();
            }
        }
        seen.extend(pending);
    }
    let review=crate::author::send(root,profile,crate::author::tool("universe_get_context",json!({"universe":universe,"context_id":context,"focus_ids":[original["identity"]["record_id"]],"purpose":"Review correction and affected authored dependencies","byte_budget":65536}))?).await?;
    Ok((crate::author::choices(&[], &records, "[]"), review))
}
#[component]
pub(super) fn EventCorrection(
    root: String,
    profile: String,
    universe: String,
    context: Value,
    frame: Frame,
    original: Value,
    clock: Option<Chronology>,
    disabled: bool,
    onadd: EventHandler<Vec<Value>>,
) -> Element {
    let mut choices = use_signal(Vec::new);
    let mut review = use_signal(Value::default);
    let mut error = use_signal(String::new);
    let mut busy = use_signal(|| false);
    rsx! {section{class:"panel",h3{"Correct the inspected event"}
        p{"Load its authored references from this pinned revision. Review related context and include dependent event corrections in the same draft. Validation checks the full candidate; generated assertions are rebuilt by the service."}
        button{disabled:disabled||busy(),onclick:{let(root,profile,universe,context,original)=(root.clone(),profile.clone(),universe.clone(),context.clone(),original.clone());move|_|{busy.set(true);let(root,profile,universe,context,original)=(root.clone(),profile.clone(),universe.clone(),context.clone(),original.clone());spawn(async move{match load(root,profile,universe,context,&original).await{Ok((c,r))=>{choices.set(c);review.set(r);error.set(String::new());},Err(e)=>error.set(e)}busy.set(false);});}},"Load event for correction"}
        if !error().is_empty(){p{role:"alert","{error}"}}
        if !review().is_null(){details{summary{"Related authored dependencies and returned coverage"}super::readable::ReadValue{value:review()}}
            div{super::consequence_event::ConsequenceEventEditor{frame,clock,choices:choices(),disabled:disabled||busy(),original:original.clone(),onadd}}
        }
    }}
}
