use dioxus::prelude::*;
use serde_json::Value;
use universe_domain::ids::*;
use universe_protocol::{
    installation::{EngineRequest, ImportMode},
    request::Selector,
};
#[component]
pub fn Transfer(root: String, profile: String, universe: String) -> Element {
    let mut destination = use_signal(String::new);
    let mut history = use_signal(|| false);
    let mut selected_ids = use_signal(String::new);
    let mut source = use_signal(String::new);
    let mut legacy_source = use_signal(String::new);
    let mut legacy_output = use_signal(String::new);
    let mut maintenance = use_signal(Value::default);
    let mut name = use_signal(String::new);
    let mut mode = use_signal(|| "clone".to_string());
    let mut preview = use_signal(Value::default);
    let mut busy = use_signal(|| false);
    let mut status = use_signal(String::new);
    rsx! { details {
        summary { "Logical export and reviewed import" }
        p { "Exports preserve factual history and exact source and image content. Canon-only exports omit workflows; complete-history exports preserve them as historical evidence with inactive approvals and delegations. A filtered export includes dependencies and declares omissions; it must be imported as a named clone." }
        label{r#for:"logical-destination","New export file path"}input{id:"logical-destination",disabled:busy(),value:destination,oninput:move|e|destination.set(e.value())}
        label{input{r#type:"checkbox",checked:history(),disabled:busy(),onchange:move|e|history.set(e.checked())}"Include complete workflow history"}
        label{r#for:"logical-selection","Optional record IDs to export, separated by commas"}input{id:"logical-selection",disabled:busy(),value:selected_ids,oninput:move|e|selected_ids.set(e.value())}
        button{disabled:busy()||destination().trim().is_empty(),onclick:{let(root,profile,universe)=(root.clone(),profile.clone(),universe.clone());move|_|{busy.set(true);let(r,p,u,path,ids,complete_history)=(root.clone(),profile.clone(),universe.clone(),destination(),selected_ids(),history());spawn(async move{let result=async{let record_ids=if ids.trim().is_empty(){vec![]}else{ids.split(',').map(|s|RecordId::parse(s.trim()).map_err(|e|e.to_string())).collect::<Result<_,_>>()?};super::author::send(r,p,EngineRequest::ExportLogical{universe:Selector(u),destination:path.into(),record_ids,complete_history}).await}.await;match result{Ok(v)=>status.set(if v["complete"]==true{if v["includes_workflow"]==true {"Complete-history relational archive exported.".into()} else {"Canon-only relational archive exported; workflows omitted.".into()}}else{format!("Filtered archive exported; {} records omitted. Referenced dependencies are included.",v["omitted_records"])}),Err(e)=>status.set(e)}busy.set(false);});}},"Export logical archive"}
        hr{}
        label{r#for:"logical-source","Logical archive file path"}input{id:"logical-source",disabled:busy(),value:source,oninput:move|e|{source.set(e.value());preview.set(Value::Null);}}
        label{r#for:"import-name","Imported universe name"}input{id:"import-name",disabled:busy(),value:name,oninput:move|e|{name.set(e.value());preview.set(Value::Null);}}
        label{r#for:"import-mode","Identity handling"}super::select::RichSelect {id:"import-mode",disabled:busy(),value:mode(),onchange:move|e: crate::select::SelectionEvent|{mode.set(e.value());preview.set(Value::Null);},options:super::select::choices(&[("clone","Named clone with a new universe identity"),("restore","Restore original identities; reject conflicts")])}
        button{disabled:busy()||source().is_empty()||name().trim().is_empty(),onclick:{let(root,profile)=(root.clone(),profile.clone());move|_|{busy.set(true);let(r,p,path,name,kind)=(root.clone(),profile.clone(),source(),name(),mode());spawn(async move{match super::author::send(r,p,EngineRequest::PreviewImport{source:path.into(),name,mode:if kind=="clone"{ImportMode::Clone}else{ImportMode::Restore}}).await{Ok(v)=>{preview.set(v);status.set("Preview validated. Review the mapping and conflicts before importing.".into());},Err(e)=>status.set(e)}busy.set(false);});}},"Validate import preview"}
        if !preview().is_null(){
            super::readable::ReadValue{value:preview()}
            button{disabled:busy()||preview()["conflicts"].as_array().is_none_or(|c|!c.is_empty()),onclick:{let(root,profile)=(root.clone(),profile.clone());move|_|{busy.set(true);let(r,p,v)=(root.clone(),profile.clone(),preview());spawn(async move{let result=async{super::author::send(r,p,EngineRequest::AcceptImport{preview_id:serde_json::from_value(v["preview_id"].clone()).map_err(|e|e.to_string())?,digest:v["digest"].as_str().ok_or("Missing preview digest")?.into()}).await}.await;match result{Ok(_)=>{preview.set(Value::Null);status.set("Reviewed archive imported. Reconnect the library to open it.".into());},Err(e)=>status.set(e)}busy.set(false);});}},"Import this reviewed archive"}
        }
        details{summary{"Convert a legacy package"}
            p{"Conversion writes a new logical archive. Record and version identities are preserved; old revision and continuity identifiers receive a visible mapping. Unsupported source or workflow data is rejected. The original file is retained. Import still requires an exact preview."}
            label{r#for:"legacy-source","Legacy v0.3 package path"}input{id:"legacy-source",disabled:busy(),value:legacy_source,oninput:move|e|legacy_source.set(e.value())}
            label{r#for:"legacy-output","New converted archive path"}input{id:"legacy-output",disabled:busy(),value:legacy_output,oninput:move|e|legacy_output.set(e.value())}
            button{disabled:busy()||legacy_source().is_empty()||legacy_output().is_empty(),onclick:{let(root,profile)=(root.clone(),profile.clone());move|_|{busy.set(true);let(r,p,source,destination)=(root.clone(),profile.clone(),legacy_source(),legacy_output());spawn(async move{match super::author::send(r,p,EngineRequest::ConvertLegacy{source:source.into(),destination:destination.into()}).await{Ok(v)=>{maintenance.set(v);status.set("Legacy copy converted. Review the identity mapping, then validate an import preview.".into());},Err(e)=>status.set(e)}busy.set(false);});}},"Convert a copy"}
        }
        details{summary{"Retention and storage maintenance"}
            p{"All canon history, source bytes, proposals, drafts and retry receipts are retained. Maintenance only collects rebuildable snapshot caches and unused SQLite pages. Every whole-package backup contains its own pinned source bytes."}
            button{disabled:busy(),onclick:{let(root,profile,universe)=(root.clone(),profile.clone(),universe.clone());move|_|{busy.set(true);let(r,p,u)=(root.clone(),profile.clone(),universe.clone());spawn(async move{match super::author::send(r,p,EngineRequest::Maintain{universe:Selector(u),collect:true}).await{Ok(v)=>{maintenance.set(v);status.set("Rebuildable caches collected; retained history and sources verified.".into());},Err(e)=>status.set(e)}busy.set(false);});}},"Compact retained package"}
        }
        if !maintenance().is_null(){super::readable::ReadValue{value:maintenance()}}
        p{role:"status","aria-live":"polite","{status}"}
    }}
}
