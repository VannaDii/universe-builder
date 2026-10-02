//! Pack contents and exact dependencies are selected through typed controls.
use super::select::{Choice, RichSelect, SelectionEvent};
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{ids::RecordId, records::DomainOperation, Frame};
#[component]
pub fn PackEditor(
    frame: Frame,
    records: Vec<Value>,
    disabled: bool,
    onadd: EventHandler<Value>,
    oninstall: EventHandler<Vec<Value>>,
) -> Element {
    let mut starter = use_signal(String::new);
    let mut selected = use_signal(String::new);
    let mut key = use_signal(String::new);
    let mut version = use_signal(String::new);
    let mut dependency = use_signal(String::new);
    let mut dependencies = use_signal(std::collections::BTreeMap::<String, String>::new);
    let mut status = use_signal(String::new);
    let mut content = use_signal(Vec::<String>::new);
    let mut member = use_signal(String::new);
    let packs: Vec<_> = records
        .iter()
        .filter(|r| r["payload"]["record_kind"] == "domain_pack")
        .cloned()
        .collect();
    rsx! {details{class:"panel",summary{"Data packs · install or upgrade"}
        p{"Group existing definitions in a versioned pack. Dependencies pin exact installed versions. Changes enter the draft for review; a pack never installs executable code."}
        label{r#for:"starter-pack","Bundled starter vocabulary"}RichSelect{id:"starter-pack",disabled,value:starter(),options:std::iter::once(Choice::new("","Choose a starter pack")).chain(universe_domain::starter::CATALOG.iter().map(|p|Choice::described(p.key,p.title,"Optional vocabulary with authored relationships; no inferred domain laws."))).collect(),onchange:move|e:SelectionEvent|starter.set(e.value())}
        button{disabled:disabled||starter().is_empty(),onclick:move|_|match universe_domain::starter::operations(&starter()){Ok(ops)=>{oninstall.call(ops.into_iter().map(|op|serde_json::to_value(op).unwrap()).collect());status.set("Starter definitions and pack added to the draft for review.".into());},Err(e)=>status.set(e)},"Add starter pack to draft"}
        label{r#for:"pack-choice","Pack"}RichSelect{id:"pack-choice",disabled,value:selected(),options:std::iter::once(Choice::described("","Create a new pack","Choose an existing pack to prepare an upgrade.")).chain(packs.iter().map(|r|Choice::described(r["identity"]["record_id"].as_str().unwrap_or_default(),r["payload"]["key"].as_str().unwrap_or("Pack"),format!("Installed version {}",r["payload"]["version"].as_str().unwrap_or_default())))).collect(),onchange:{let packs=packs.clone();move|e:SelectionEvent|{selected.set(e.value());if let Some(p)=packs.iter().find(|p|p["identity"]["record_id"]==e.value()){key.set(p["payload"]["key"].as_str().unwrap_or_default().into());dependencies.set(serde_json::from_value(p["payload"]["dependencies"].clone()).unwrap_or_default());content.set(serde_json::from_value(p["payload"]["records"].clone()).unwrap_or_default());}else{key.set(String::new());dependencies.set(Default::default());content.set(vec![]);}version.set(String::new());}}}
        label{r#for:"pack-key","Pack name"}input{id:"pack-key",disabled:disabled||!selected().is_empty(),value:key,oninput:move|e|key.set(e.value())}
        label{r#for:"pack-version","New exact version"}input{id:"pack-version",disabled,value:version,oninput:move|e|version.set(e.value())}
        label{r#for:"pack-dependency","Add an installed dependency"}RichSelect{id:"pack-dependency",disabled,value:dependency(),options:std::iter::once(Choice::new("","Choose a dependency")).chain(packs.iter().filter(|r|r["identity"]["record_id"]!=selected()).map(|r|Choice::described(r["identity"]["record_id"].as_str().unwrap_or_default(),r["payload"]["key"].as_str().unwrap_or("Pack"),format!("Pin version {}",r["payload"]["version"].as_str().unwrap_or_default())))).collect(),onchange:move|e:SelectionEvent|dependency.set(e.value())}
        button{disabled:disabled||dependency().is_empty(),onclick:{let packs=packs.clone();move|_|{if let Some(p)=packs.iter().find(|p|p["identity"]["record_id"]==dependency()){if let(Some(k),Some(v))=(p["payload"]["key"].as_str(),p["payload"]["version"].as_str()){dependencies.write().insert(k.into(),v.into());}}}},"Add exact dependency"}
        for (name,pin) in dependencies(){div{span{"{name} · {pin}"}button{disabled,onclick:move|_|{dependencies.write().remove(&name);},"Remove dependency"}}}
        label{r#for:"pack-member","Contributed definition"}RichSelect{id:"pack-member",disabled,value:member(),options:std::iter::once(Choice::new("","Choose an existing definition")).chain(records.iter().filter(|r|r["payload"]["record_kind"]!="domain_pack").map(|r|Choice::described(r["identity"]["record_id"].as_str().unwrap_or_default(),r["payload"]["key"].as_str().unwrap_or("Definition"),super::readable::caption(r["payload"]["record_kind"].as_str().unwrap_or("record"))))).collect(),onchange:move|e:SelectionEvent|member.set(e.value())}
        button{disabled:disabled||member().is_empty(),onclick:move|_|{let id=member();if !content().contains(&id){content.write().push(id);}},"Include definition"}
        for id in content(){div{span{"{id}"}button{disabled,onclick:move|_|content.write().retain(|v|v!=&id),"Remove definition"}}}
        button{disabled:disabled||key().trim().is_empty()||version().trim().is_empty(),onclick:move|_|{
            let old=packs.iter().find(|p|p["identity"]["record_id"]==selected());
            if old.is_some_and(|p|p["payload"]["version"]==version()){status.set("An upgrade requires a different version.".into());return;}
            let content=content();
            let capabilities=old.map(|p|p["payload"]["capabilities"].clone()).unwrap_or_else(||json!([]));
            let record=json!({"key":key().trim(),"version":version().trim(),"dependencies":dependencies(),"capabilities":capabilities,"records":content});
            let op=if let Some(old)=old{json!({"kind":"upgrade_pack","record":{"universe":frame.universe,"record":selected()},"expected_version":old["record_version_id"],"replacement":record})}else{json!({"kind":"install_pack","client_ref":RecordId::generate(&mut rand::rng()),"record":record})};
            match serde_json::from_value::<DomainOperation>(op.clone()){Ok(_)=>{onadd.call(op);status.set("Pack change added to draft. Review and validate before committing.".into());},Err(e)=>status.set(e.to_string())}
        },"Add pack change to draft"}
        p{role:"status","{status}"}
    }}
}
