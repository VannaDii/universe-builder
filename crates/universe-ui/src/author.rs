//! Native author client. Every canon action uses the authenticated engine.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::ids::*;
use universe_protocol::{
    installation::{DraftContent, EngineRequest},
    request::{ProposalRef, Selector},
    Request,
};
pub(super) async fn send(
    root: String,
    profile: String,
    request: EngineRequest,
) -> Result<Value, String> {
    let profile = ProfileId::parse(&profile).map_err(|e| e.to_string())?;
    let helper = universe_client::installation::sibling_engine().map_err(|e| e.to_string())?;
    let mut client = universe_client::installation::EngineClient::ensure_running(
        std::path::Path::new(&root),
        &profile,
        &helper,
        "native-author",
    )
    .await
    .map_err(|e| e.to_string())?;
    client.call(request).await.map_err(|e| e.to_string())
}
pub(super) fn tool(name: &str, args: Value) -> Result<EngineRequest, String> {
    Ok(EngineRequest::Tool {
        request: Box::new(Request::from_tool(name, args).map_err(|e| e.to_string())?),
    })
}
async fn definition_records(
    root: &str,
    profile: &str,
    universe: &str,
    context: &Value,
) -> Result<Vec<Value>, String> {
    let described = send(
        root.into(),
        profile.into(),
        tool(
            "universe_describe",
            json!({"mode":"definitions","universe":universe,"context_id":context}),
        )?,
    )
    .await?;
    let ids = described["result"]["definition_ids"]
        .as_array()
        .ok_or("Missing definition index")?;
    let mut records = Vec::new();
    for chunk in ids.chunks(100) {
        let read=send(root.into(),profile.into(),tool("universe_get",json!({"universe":universe,"context_id":context,"record_ids":chunk,"field_groups":[]}))?).await?;
        records.extend(
            read["result"]["records"]
                .as_array()
                .ok_or("Missing definitions")?
                .iter()
                .cloned(),
        );
    }
    Ok(records)
}
async fn load_proposal(root: String, profile: String, mut args: Value) -> Result<Value, String> {
    let mut combined = Value::Null;
    for _ in 0..100 {
        let page = send(
            root.clone(),
            profile.clone(),
            tool("universe_get_proposal", args.clone())?,
        )
        .await?;
        if combined.is_null() {
            combined = page.clone();
        } else {
            if combined["result"]["digest"] != page["result"]["digest"] {
                return Err("Proposal changed between pages".into());
            }
            for key in ["operations", "compiled_changes"] {
                let mut rows = combined["result"][key]
                    .as_array()
                    .cloned()
                    .unwrap_or_default();
                rows.extend(
                    page["result"][key]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .cloned(),
                );
                combined["result"][key] = json!(rows);
            }
        }
        if page["delivery"]["complete"] == true {
            combined["delivery"] = page["delivery"].clone();
            return Ok(combined);
        }
        args["cursor"] = page["delivery"]["cursor"].clone();
    }
    Err("Proposal exceeds the native review page limit".into())
}
fn reference(proposal: &Value) -> Result<ProposalRef, String> {
    serde_json::from_value(json!({"proposal_id":proposal["proposal_id"],"version":proposal["version"],"digest":proposal["digest"]})).map_err(|e|e.to_string())
}
fn key() -> String {
    format!(
        "native-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    )
}
pub(super) fn choices(hits: &[Value], definitions: &[Value], operations: &str) -> Vec<Value> {
    let mut options = hits.to_vec();
    for r in definitions {
        let p = &r["payload"];
        let id = &r["identity"]["recordId"];
        let id = if id.is_null() {
            &r["identity"]["record_id"]
        } else {
            id
        };
        options.retain(|o| o["record_id"] != *id);
        let assertion_label=if p["record_kind"]=="assertion" {definitions.iter().find(|row|row["identity"]["record_id"]==p["proposition"]["record"]).map(|claim|{let object=json!({"dependencies":definitions});let claim=&claim["payload"];format!("{} — {}: {} ({})",super::effective_object_view::reference_name(&object,&claim["subject"]["record"]),super::effective_object_view::reference_name(&object,&claim["predicate"]["record"]),super::effective_object_view::value_text(&claim["value"],&object),p["polarity"].as_str().unwrap_or("polarity unavailable"))})}else{None};
        options.push(json!({"kind":p["record_kind"],"record_id":id,"record_version_id":r["record_version_id"],"label":if let Some(label)=assertion_label{label}else if p["record_kind"]=="communication" {super::communication_editor::label(p,id)}else{p["labels"]["en"].as_str().or_else(||p["title"].as_str()).or_else(||p["versionLabel"].as_str()).or_else(||p["sceneId"].as_str()).or_else(||p["name"].as_str()).or_else(||p["key"].as_str()).or_else(||p["names"][0]["text"].as_str()).unwrap_or("Definition").to_string()},"definition":p}));
    }
    for op in serde_json::from_str::<Vec<Value>>(operations).unwrap_or_default() {
        let kind = match op["kind"].as_str().unwrap_or_default() {
            "create_entity" | "introduce_instance" => "entity",
            "create_world" => "world",
            "create_work" => "work",
            "create_saga" => "saga",
            "define_property" => "property",
            "define_relation" => "relation",
            "define_type" | "introduce_definition" => "entity_type",
            "define_unit" => "unit",
            "define_calendar" => "calendar",
            "define_action" => "action_definition",
            "record_communication" => "communication",
            "add_belief" => "epistemic_attitude",
            "define_rule" => "rule",
            "assert_proposition" | "record_relation" | "define_proposition" => "proposition",
            _ => continue,
        };
        let label = op["name"]
            .as_str()
            .or_else(|| op["name"]["text"].as_str())
            .or_else(|| op["record"]["labels"]["en"].as_str())
            .or_else(|| op["record"]["title"].as_str())
            .or_else(|| op["record"]["selector"].as_str())
            .unwrap_or("Draft record");
        options.push(
            json!({"kind":kind,"record_id":op["client_ref"],"label":if kind=="communication"{format!("{} (draft)",super::communication_editor::label(&op["record"],&op["client_ref"]))}else{format!("{label} (draft)")},"definition":if op["kind"]=="introduce_definition" {&op} else if kind=="proposition" && op["kind"]!="define_proposition" {&op["proposition"]} else {&op["record"]}}),
        );
    }
    options
}
/// Keep the existing single draft bound to its context until explicitly cleared.
pub(crate) fn workspace_context(
    library: &Value,
    draft: &Value,
    requested: &str,
) -> Result<Value, String> {
    let previous = &draft["content"]["represented_context"];
    let context = if !requested.is_empty() {
        json!(requested)
    } else if !draft.is_null() {
        previous.clone()
    } else {
        library["contexts"][0].clone()
    };
    if !draft.is_null()
        && context != *previous
        && (draft["content"]["operations"]
            .as_array()
            .is_none_or(|ops| !ops.is_empty())
            || !draft["content"]["proposal"].is_null()
            || !draft["content"]["rationale"]
                .as_str()
                .unwrap_or_default()
                .trim()
                .is_empty())
    {
        return Err("Finish or explicitly clear/withdraw the existing draft before switching its story context.".into());
    }
    Ok(context)
}
#[component]
pub fn AuthorApp() -> Element {
    let mut root = use_signal(|| std::env::var("UNIVERSE_INSTALLATION").unwrap_or_default());
    let mut profile = use_signal(|| std::env::var("UNIVERSE_PROFILE").unwrap_or_default());
    let mut catalog = use_signal(Vec::<String>::new);
    let mut selected = use_signal(String::new);
    let mut continuity = use_signal(String::new);
    let mut continuities = use_signal(Vec::<Value>::new);
    let mut new_universe = use_signal(String::new);
    let mut starting_clock = use_signal(|| None::<universe_domain::chronology::UniverseStart>);
    let mut clock_record = use_signal(Value::default);
    let mut ctx = use_signal(Value::default);
    let mut search_text = use_signal(String::new);
    let mut selected_context = use_signal(String::new);
    let mut search_kind = use_signal(String::new);
    let mut applied_query = use_signal(String::new);
    let mut applied_kind = use_signal(String::new);
    let mut scope_view = use_signal(String::new);
    let mut hits = use_signal(Vec::<Value>::new);
    let mut definitions = use_signal(Vec::<Value>::new);
    let mut worlds = use_signal(Vec::<String>::new);
    let mut focus = use_signal(String::new);
    let mut operations = use_signal(|| "[]".to_string());
    let mut rationale = use_signal(String::new);
    let mut proposal = use_signal(Value::default);
    let mut draft_proposal = use_signal(Value::default);
    let mut validation = use_signal(Value::default);
    let mut review = use_signal(Value::default);
    let mut inspected = use_signal(Value::default);
    let mut approved = use_signal(|| false);
    let mut author_profile = use_signal(String::new);
    let mut busy = use_signal(|| false);
    let mut generation = use_signal(|| 0_u64);
    let mut status = use_signal(|| {
        "Connect an enrolled author profile to open your universe library.".to_string()
    });
    let mut backup_path = use_signal(String::new);
    let mut source_label = use_signal(String::new);
    let mut source_text = use_signal(String::new);
    let mut proposal_id = use_signal(String::new);
    let mut proposal_version = use_signal(|| "1".to_string());
    let mut next_page = use_signal(Value::default);
    let mut applied_focus = use_signal(String::new);
    let mut draft_version = use_signal(|| 0_u64);
    let mut draft_base = use_signal(Value::default);
    let mut saved_content = use_signal(Value::default);
    let mut saving = use_signal(|| false);
    let mut autosave_failed = use_signal(|| false);
    let mut draft_status =
        use_signal(|| "Draft autosave starts when a universe is opened.".to_string());
    // One save in flight per editor. Compare-and-set protects against other windows.
    // Scope changes invalidate callbacks; typed draft operations are serialized internally.
    use_effect(move || {
        let c = ctx();
        if c.is_null() || draft_base().is_null() {
            return;
        }
        let editor_operations = operations();
        let typed_operations =
            match serde_json::from_str::<Vec<universe_domain::DomainOperation>>(&editor_operations)
            {
                Ok(ops) => ops,
                Err(e) => {
                    autosave_failed.set(true);
                    draft_status.set(format!("Draft not saved: {e}"));
                    return;
                }
            };
        let content = json!({"base_revision":draft_base(),"represented_context":c["frame"]["context"]["record"],"operations":typed_operations,"rationale":rationale(),"proposal":draft_proposal()});
        if content == saved_content() || saving() || autosave_failed() {
            return;
        }
        saving.set(true);
        draft_status.set("Saving draft… Canon is unchanged.".into());
        let (r, p, u, g, version) = (root(), profile(), selected(), generation(), draft_version());
        spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
            if generation() != g {
                saving.set(false);
                return;
            }
            // Debounce edits without sending a stale text snapshot.
            if editor_operations != operations()
                || content["rationale"] != rationale()
                || content["base_revision"] != draft_base()
                || content["proposal"] != draft_proposal()
            {
                saving.set(false);
                return;
            }
            let result = async {
                let content: DraftContent =
                    serde_json::from_value(content.clone()).map_err(|e| e.to_string())?;
                send(
                    r,
                    p,
                    EngineRequest::SaveDraft {
                        universe: Selector(u),
                        continuity_id: serde_json::from_value(c["frame"]["continuity"].clone())
                            .map_err(|e| e.to_string())?,
                        expected_version: version,
                        content,
                    },
                )
                .await
            }
            .await;
            if generation() == g {
                match result {
                    Ok(v) => {
                        draft_version.set(v["version"].as_u64().unwrap_or(version));
                        saved_content.set(content);
                        draft_status.set("Draft saved locally. Canon is unchanged.".into());
                    }
                    Err(e) => {
                        autosave_failed.set(true);
                        draft_status.set(format!("Draft not saved: {e}. Reopen the saved draft to recover from a conflict."));
                    }
                }
            }
            saving.set(false);
        });
    });
    let inspector_key = inspected()["records"][0]["record_version_id"]
        .as_str()
        .unwrap_or_default()
        .to_string();
    rsx! {
        style{"{super::STYLE}"}
        main{
            header{p{class:"eyebrow","UNIVERSE BUILDER"}h1{"Author with a clear record."}p{"Explore a pinned revision. Review every change before it becomes canon."}}
            section{class:"panel","aria-label":"Engine connection",
                label{r#for:"author-root","Installation folder"}input{id:"author-root",value:root,disabled:busy()||saving()||autosave_failed(),oninput:move|e|{root.set(e.value());catalog.set(vec![]);selected.set(String::new());selected_context.set(String::new());ctx.set(Value::Null);draft_base.set(Value::Null);inspected.set(Value::Null);proposal.set(Value::Null);generation+=1;}}
                label{r#for:"author-profile","Enrolled profile ID"}input{id:"author-profile",value:profile,disabled:busy()||saving()||autosave_failed(),oninput:move|e|{profile.set(e.value());catalog.set(vec![]);selected.set(String::new());selected_context.set(String::new());ctx.set(Value::Null);draft_base.set(Value::Null);inspected.set(Value::Null);proposal.set(Value::Null);generation+=1;}}
                button{disabled:busy()||saving()||autosave_failed(),onclick:move|_|{busy.set(true);let(r,p)=(root(),profile());spawn(async move{match send(r.clone(),p.clone(),EngineRequest::Status).await{Ok(v)=>{author_profile.set(if v["author"]==true{format!("{r}:{p}")}else{String::new()});catalog.set(v["universes"].as_array().into_iter().flatten().filter_map(|u|u["name"].as_str().map(str::to_string)).collect());status.set(if v["author"]==true{"Connected as author. Choose a universe.".into()}else{"Connected profile is not an author; approval controls will be denied.".into()});},Err(e)=>status.set(e)}busy.set(false);});},"Connect library"}
            }
            section{class:"scope","aria-label":"Universe selection",
                div{label{r#for:"author-universe","Universe"}super::select::RichSelect {id:"author-universe",value:selected(),disabled:busy()||saving()||autosave_failed(),onchange:move|e: crate::select::SelectionEvent|{selected.set(e.value());selected_context.set(String::new());continuity.set(String::new());continuities.set(vec![]);draft_proposal.set(Value::Null);ctx.set(Value::Null);proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);hits.set(vec![]);focus.set(String::new());operations.set("[]".into());rationale.set(String::new());draft_base.set(Value::Null);inspected.set(Value::Null);next_page.set(Value::Null);generation+=1;},options:std::iter::once(super::select::Choice::new("", "Choose a universe")).chain(catalog().into_iter().map(|name|super::select::Choice::described(name.clone(),name,"Open this universe’s library and pinned canon."))).collect()}}
                if !ctx().is_null() && !definitions().is_empty(){div{label{r#for:"author-context","Writing context"}super::select::RichSelect{id:"author-context",disabled:busy()||saving()||autosave_failed()||operations().trim()!="[]"||!rationale().trim().is_empty()||!draft_proposal().is_null(),value:selected_context(),options:super::select::record_choices(&choices(&hits(),&definitions(),"[]"),&["represented_context"],"Choose a context"),onchange:move|e:super::select::SelectionEvent|{selected_context.set(e.value());ctx.set(Value::Null);draft_base.set(Value::Null);status.set("Context selected. Open its current revision before editing.".into());generation+=1;}}p{"Open the selected context before editing. Finish or explicitly clear the current draft before switching."}}}
                button{disabled:busy()||saving()||autosave_failed()||selected().is_empty(),onclick:move|_|{busy.set(true);let(r,p,u,g,chosen,chosen_context)=(root(),profile(),selected(),generation(),continuity(),selected_context());spawn(async move{let result=async{let library=send(r.clone(),p.clone(),EngineRequest::Library{universe:Selector(u.clone())}).await?;let cont=if chosen.is_empty(){library["storage"]["heads"][0][0].clone()}else{json!(chosen)};let draft=send(r.clone(),p.clone(),EngineRequest::LoadDraft{universe:Selector(u.clone()),continuity_id:serde_json::from_value(cont.clone()).map_err(|e|e.to_string())?}).await?;let context=workspace_context(&library,&draft,&chosen_context)?;let opened=send(r.clone(),p.clone(),tool("universe_open_context",json!({"universe":u,"continuity_id":cont,"revision":{"kind":"head"},"represented_context":context,"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))?).await?;let context_read=send(r.clone(),p.clone(),tool("universe_get",json!({"universe":u,"universe_id":opened["result"]["frame"]["universe"],"context_id":opened["result"]["context_id"],"record_ids":[opened["result"]["frame"]["context"]["record"]],"field_groups":[]}))?).await?;let loaded_clock=context_read["result"]["records"][0].clone();let loaded_definitions=definition_records(&r,&p,&u,&opened["result"]["context_id"]).await?;let found=send(r,p,tool("universe_search",json!({"universe":u,"context_id":opened["result"]["context_id"],"query":"","typed_filters":{"record_kinds":[]},"limit":100}))?).await?;Ok::<_,String>((library,opened,found,draft,loaded_definitions,loaded_clock))}.await;if generation()==g{match result{Ok((library,opened,found,draft,loaded_definitions,loaded_clock))=>{selected_context.set(opened["result"]["frame"]["context"]["record"].as_str().unwrap_or_default().into());continuity.set(opened["result"]["frame"]["continuity"].as_str().unwrap_or_default().into());continuities.set(library["continuities"].as_array().cloned().unwrap_or_default());clock_record.set(loaded_clock);definitions.set(loaded_definitions);draft_version.set(draft["version"].as_u64().unwrap_or(0));let content=if draft.is_null() || draft["content"]["represented_context"]!=opened["result"]["frame"]["context"]["record"]{json!({"base_revision":opened["result"]["frame"]["revision"],"represented_context":opened["result"]["frame"]["context"]["record"],"operations":[],"rationale":"","proposal":null})}else{draft["content"].clone()};draft_proposal.set(content["proposal"].clone());operations.set(content["operations"].to_string());rationale.set(content["rationale"].as_str().unwrap_or_default().into());draft_base.set(content["base_revision"].clone());saved_content.set(if draft.is_null(){content}else{draft["content"].clone()});autosave_failed.set(false);draft_status.set(if draft.is_null(){"Draft autosave is on. Canon is unchanged.".into()}else{"Saved draft recovered. Canon is unchanged.".into()});focus.set(String::new());applied_focus.set(String::new());search_text.set(String::new());search_kind.set(String::new());applied_query.set(String::new());applied_kind.set(String::new());scope_view.set(String::new());next_page.set(found["delivery"]["cursor"].clone());inspected.set(Value::Null);worlds.set(library["worlds"].as_array().into_iter().flatten().filter_map(|w|w["name"].as_str().map(str::to_string)).collect());ctx.set(opened["result"].clone());hits.set(found["result"]["hits"].as_array().cloned().unwrap_or_default());proposal.set(Value::Null);review.set(Value::Null);validation.set(Value::Null);approved.set(false);status.set(format!("Pinned revision {}. {}",opened["result"]["frame"]["revision"],if found["delivery"]["complete"]==true{"Explorer loaded."}else{"First 100 records shown."}));},Err(e)=>status.set(e)}busy.set(false);}});},"Open current revision"}
            }
            if !continuities().is_empty(){section{class:"scope",label{r#for:"author-continuity","Continuity"}super::select::RichSelect{id:"author-continuity",disabled:busy()||saving()||autosave_failed(),value:continuity(),options:continuities().iter().map(|c|super::select::Choice::described(c["id"].as_str().unwrap_or_default(),c["name"].as_str().unwrap_or("Continuity"),"Independent canon with a pinned baseline. Open its revision to load its own saved draft.")).collect(),onchange:move|e:super::select::SelectionEvent|{continuity.set(e.value());selected_context.set(String::new());ctx.set(Value::Null);draft_base.set(Value::Null);generation+=1;}}}}
            details{class:"panel",summary{"Create a universe"}
                div{label{r#for:"new-universe","New universe name"}input{id:"new-universe",value:new_universe,oninput:move|e|new_universe.set(e.value())}}
                super::chronology::StartClock{onchange:move|start|starting_clock.set(start)}
                button{disabled:busy()||saving()||autosave_failed()||new_universe().trim().is_empty()||starting_clock().is_none(),onclick:move|_|{busy.set(true);let(r,p,name)=(root(),profile(),new_universe());let Some(start)=starting_clock()else{busy.set(false);return;};spawn(async move{match send(r,p,EngineRequest::CreateUniverse{name:name.clone(),start}).await{Ok(_)=>{catalog.write().push(name.clone());selected.set(name);ctx.set(Value::Null);generation+=1;status.set("Universe created. Open its current revision to begin.".into());},Err(e)=>status.set(e)}busy.set(false);});},"Create universe"}
            }
            p{class:"status",role:"status","aria-live":"polite","{status}"}
            if !ctx().is_null(){
                for clock_key in [clock_record()["record_version_id"].as_str().unwrap_or_default().to_string()]{super::chronology::StoryClock{key:"{clock_key}",record:clock_record(),disabled:busy()||saving(),onadd:move|op:Value|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.push(op);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}}
                if let Ok(frame)=serde_json::from_value::<universe_domain::Frame>(ctx()["frame"].clone()){
                    super::state_view::StateView{key:"{frame.revision}-{selected}-{focus}",root:root(),profile:profile(),universe:selected(),frame,clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),choices:choices(&hits(),&definitions(),"[]"),world:focus()}
                }
                if let Ok(frame)=serde_json::from_value::<universe_domain::Frame>(ctx()["frame"].clone()){
                    super::continuities::Continuities{key:"{frame.universe}-{frame.continuity}-{frame.revision}",root:root(),profile:profile(),universe:selected(),frame:frame.clone(),heads:continuities(),disabled:busy()||saving(),onfork:move|id:String|{continuity.set(id);ctx.set(Value::Null);draft_base.set(Value::Null);generation+=1;status.set("Continuity created. Open its revision to begin an independent draft.".into());},onadd:move|added:Vec<Value>|{let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations())else{status.set("The recovered draft cannot be decoded; it has been preserved.".into());return;};ops.extend(added);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}
                }
                if let Ok(frame)=serde_json::from_value::<universe_domain::Frame>(ctx()["frame"].clone()){
                    super::timeline::Timeline{key:"{frame.universe}-{frame.revision}",root:root(),profile:profile(),universe:selected(),context:ctx()["context_id"].clone(),frame,choices:choices(&hits(),&definitions(),"[]"),clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok()}
                }
                div{class:"workspace",
                    for writing_key in [format!("{}:{}:{}",root(),profile(),selected())] { div {key:"{writing_key}", super::writing_review::WritingReview { root:root(), profile:profile(), universe:selected() }}}
                    section{class:"panel","aria-label":"Explorer",h2{"Canon explorer"}
                        label{r#for:"author-world","World focus"}super::select::RichSelect {id:"author-world",value:focus(),disabled:busy()||saving(),onchange:move|e: crate::select::SelectionEvent|{focus.set(e.value());next_page.set(Value::Null);},options:std::iter::once(super::select::Choice::described("", "All worlds · shared · unassigned", "Search the whole universe, including records without world associations.")).chain(worlds().into_iter().map(|name|super::select::Choice::described(name.clone(),name,"Focus on this world’s explicitly associated records."))).collect()}
                        label{r#for:"explorer-query","Search canon"}input{id:"explorer-query",disabled:busy(),value:search_text,oninput:move|e|{search_text.set(e.value());next_page.set(Value::Null);}}
                        label{r#for:"explorer-kind","Record kind"}super::select::RichSelect {id:"explorer-kind",disabled:busy(),value:search_kind(),onchange:move|e: crate::select::SelectionEvent|{search_kind.set(e.value());next_page.set(Value::Null);},options:super::select::choices(&[("","All record kinds"),("entity","Entity"),("world","World"),("work","Work"),("work_version","Work Version"),("saga","Saga"),("entity_type","Entity Type"),("property","Property"),("relation","Relation"),("calendar","Calendar"),("unit","Unit"),("event","Event"),("communication","Communication"),("proposition","Proposition"),("item_power","Item Power"),("assertion","Assertion"),("source","Source"),("anchor","Anchor"),("issue_decision","Issue Decision"),("represented_context","Represented Context"),("scene_ref","Scene Reference")])}
                        label{r#for:"explorer-scope","Show within loaded results"}super::select::RichSelect {id:"explorer-scope",value:scope_view(),onchange:move|e: crate::select::SelectionEvent|scope_view.set(e.value()),options:super::select::choices(&[("","All loaded records"),("shared","Shared identities"),("unassigned","Unassigned / universe wide")])}
                        button{disabled:busy()||saving(),onclick:move|_|{busy.set(true);let(r,p,u,c,w,q,k,g)=(root(),profile(),selected(),ctx(),focus(),search_text(),search_kind(),generation());spawn(async move{let mut args=json!({"universe":u,"universe_id":c["frame"]["universe"],"context_id":c["context_id"],"query":q,"typed_filters":{"record_kinds":if k.is_empty(){vec![]}else{vec![k.clone()]}},"limit":100});if !w.is_empty(){args["world"]=json!(w);}let result=match tool("universe_search",args){Ok(req)=>send(r,p,req).await,Err(e)=>Err(e)};if generation()==g{match result{Ok(v)=>{hits.set(v["result"]["hits"].as_array().cloned().unwrap_or_default());next_page.set(v["delivery"]["cursor"].clone());applied_focus.set(w);applied_query.set(q);applied_kind.set(k);inspected.set(Value::Null);status.set("Explorer refreshed at the pinned revision.".into());},Err(e)=>status.set(e)}busy.set(false);}});},"Apply focus"}
                        ul{for hit in hits().into_iter().filter(|h|scope_view().is_empty()||h["scope_category"]==scope_view()){li{button{class:"secondary",disabled:busy()||saving(),onclick:{let id=hit["record_id"].clone();move|_|{busy.set(true);let(r,p,u,c,id,g)=(root(),profile(),selected(),ctx(),id.clone(),generation());spawn(async move{let result=match tool("universe_get",json!({"universe":u,"universe_id":c["frame"]["universe"],"context_id":c["context_id"],"record_ids":[id],"field_groups":["payload","evidence","history"]})){Ok(req)=>send(r,p,req).await,Err(e)=>Err(e)};if generation()==g{match result{Ok(v)=>{if let Some(rows)=v["result"]["records"].as_array(){for row in rows{definitions.write().retain(|old|old["identity"]!=row["identity"]);definitions.write().push(row.clone());}}inspected.set(v["result"].clone());},Err(e)=>status.set(e)}busy.set(false);}});}}, {hit["label"].as_str().unwrap_or_default().to_owned()}}small{{format!("{} · {}",hit["kind"],hit["scope_category"])}}}}}
                        if !next_page().is_null(){button{disabled:busy()||saving()||focus()!=applied_focus(),onclick:move|_|{busy.set(true);let(r,p,u,c,w,q,k,page,g)=(root(),profile(),selected(),ctx(),applied_focus(),applied_query(),applied_kind(),next_page(),generation());spawn(async move{let mut args=json!({"universe":u,"universe_id":c["frame"]["universe"],"context_id":c["context_id"],"query":q,"typed_filters":{"record_kinds":if k.is_empty(){vec![]}else{vec![k]}},"limit":100,"cursor":page});if !w.is_empty(){args["world"]=json!(w);}let result=match tool("universe_search",args){Ok(req)=>send(r,p,req).await,Err(e)=>Err(e)};if generation()==g{match result{Ok(v)=>{hits.write().extend(v["result"]["hits"].as_array().cloned().unwrap_or_default());next_page.set(v["delivery"]["cursor"].clone());status.set("Next page loaded from the same pinned revision.".into());},Err(e)=>status.set(e)}busy.set(false);}});},"Load more records"}}
                        if !inspected().is_null(){super::readable::ReadValue{value:inspected()} super::history::History{records:inspected(),disabled:busy(),onadd:move|op:Value|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.push(op);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}}
                        if let Ok(frame)=serde_json::from_value::<universe_domain::Frame>(ctx()["frame"].clone()){
                            div{key:"{inspector_key}",
                            if inspected()["records"][0]["payload"]["record_kind"]=="action_definition"{
                                super::action_editor::ActionEditor{frame:frame.clone(),choices:choices(&hits(),&definitions(),&operations()),original:inspected()["records"][0].clone(),disabled:busy(),onadd:move|op:Value|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.push(op);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                            }
                            if inspected()["records"][0]["payload"]["record_kind"]=="event"{
                                super::event_correction::EventCorrection{root:root(),profile:profile(),universe:selected(),context:ctx()["context_id"].clone(),frame:frame.clone(),original:inspected()["records"][0].clone(),clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),disabled:busy(),onadd:move|added:Vec<Value>|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.extend(added);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                            }
                            if inspected()["records"][0]["payload"]["record_kind"]=="assertion"{
                                super::claim_editor::RelationshipCorrection{root:root(),profile:profile(),universe:selected(),context:ctx()["context_id"].clone(),frame:frame.clone(),original:inspected()["records"][0].clone(),available:choices(&hits(),&definitions(),&operations()),generation,clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),disabled:busy(),onadd:move|added:Vec<Value>|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.extend(added);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                            }
                            super::inspector_editor::InspectorEditor{frame,selected:inspected()["records"][0].clone(),evidence:inspected()["evidence"].as_array().cloned().unwrap_or_default(),choices:choices(&hits(),&definitions(),&operations()),clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),disabled:busy(),onadd:move|added:Vec<Value>|{let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations())else{status.set("The recovered draft cannot be decoded. It has been preserved.".into());return;};ops.extend(added);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}
                            }
                        }
                    }
                    section{class:"panel","aria-label":"Proposal editor",h2{"Draft a change"}
                        p{role:"status","aria-live":"polite","{draft_status}"}
                        if autosave_failed(){button{disabled:busy(),onclick:move|_|autosave_failed.set(false),"Retry draft save"}button{class:"secondary",disabled:busy()||saving(),onclick:move|_|{ctx.set(Value::Null);draft_base.set(Value::Null);autosave_failed.set(false);generation+=1;status.set("Unsaved editor text discarded. Open the current revision to recover the saved draft.".into());},"Discard unsaved editor text and reopen"}}
                        if draft_base()!=ctx()["frame"]["revision"]{p{"This draft uses a different revision. Review its operations before explicitly rebasing."}button{disabled:busy(),onclick:move|_|{draft_base.set(ctx()["frame"]["revision"].clone());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);},"Rebase draft to this revision"}}
                        if let Ok(frame)=serde_json::from_value::<universe_domain::Frame>(ctx()["frame"].clone()){
                            div{key:"{frame.universe}-{frame.revision}-{frame.context.record}",
                            if let Ok(context)=serde_json::from_value::<ContextId>(ctx()["context_id"].clone()){
                                super::appearance_editor::AppearanceEditor{root:root(),profile:profile(),universe:selected(),context_id:context,frame:frame.clone(),choices:choices(&hits(),&definitions(),&operations()),inspected:inspected(),clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),disabled:busy(),onadd:move|added:Vec<Value>|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.extend(added);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                            }
                            super::identity_editor::IdentityEditor{frame:frame.clone(),choices:choices(&hits(),&definitions(),&operations()),inspected:inspected(),disabled:busy(),onadd:move|op:Value|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.push(op);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                            if let Ok(context)=serde_json::from_value::<ContextId>(ctx()["context_id"].clone()){
                                super::initialization_editor::InitializationEditor{root:root(),profile:profile(),universe:selected(),context,frame:frame.clone(),clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),choices:choices(&hits(),&definitions(),&operations()),disabled:busy(),onadd:move|op:Value|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.push(op);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                            }
                            super::event_editor::EventEditor{frame:frame.clone(),clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),choices:choices(&hits(),&definitions(),&operations()),disabled:busy(),onadd:move|added:Vec<Value>|{let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations())else{status.set("The recovered draft cannot be decoded; it has been preserved.".into());return;};ops.extend(added);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}
                            super::communication_editor::CommunicationEditor{frame:frame.clone(),clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),choices:choices(&hits(),&definitions(),&operations()),disabled:busy(),onadd:move|op:Value|{let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations())else{status.set("The draft cannot be decoded; reopen its saved version before adding a message.".into());return;};ops.push(op);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}
                            super::knowledge_editor::KnowledgeEditor{frame:frame.clone(),clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),choices:choices(&hits(),&definitions(),&operations()),disabled:busy(),onadd:move|op:Value|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.push(op);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                            super::policy_editor::PolicyEditor{frame:frame.clone(),clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),choices:choices(&hits(),&definitions(),&operations()),namespaces:super::select::namespace_choices(&definitions(),&operations()),disabled:busy(),onadd:move|op:Value|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.push(op);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                            super::exception_editor::ExceptionEditor{frame:frame.clone(),profile:profile(),clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),records:definitions(),findings:validation()["execution"]["findings"].clone(),disabled:busy(),onadd:move|added:Vec<Value>|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.extend(added);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                            super::history::Issues{findings:validation()["execution"]["findings"].clone(),profile:profile(),disabled:busy(),onadd:move|op:Value|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.push(op);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                            super::pack_editor::PackEditor{oninstall:move|added:Vec<Value>|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.extend(added);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}},frame:frame.clone(),records:definitions(),disabled:busy(),onadd:move|op:Value|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.push(op);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                            super::claim_editor::ClaimEditor{frame,clock:serde_json::from_value(clock_record()["payload"]["chronology"].clone()).ok(),choices:choices(&hits(),&definitions(),&operations()),disabled:busy(),onadd:move|op:Value|{let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations())else{status.set("This draft cannot be decoded; reopen a saved draft before adding a claim.".into());return;};ops.push(op);operations.set(serde_json::to_string_pretty(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}
                        super::definitions::DefinitionEditor{choices:choices(&hits(),&definitions(),&operations()),disabled:busy(),namespaces:super::select::namespace_choices(&definitions(),&operations()),onadd:move|op:Value|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){ops.push(op);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}
                        }
                        }
                        super::readable::DraftChanges{operations:operations(),disabled:busy(),onremove:move|index:usize|{if let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations()){if index<ops.len(){ops.remove(index);operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}}}

                        label{r#for:"draft-rationale","Reason for this change"}textarea{id:"draft-rationale",rows:3,value:rationale,disabled:busy(),oninput:move|e|{rationale.set(e.value());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);}}
                        button{disabled:busy()||rationale().trim().is_empty()||operations().trim()=="[]"||draft_base()!=ctx()["frame"]["revision"],onclick:move|_|{busy.set(true);let(r,p,u,c,ops,reason,g)=(root(),profile(),selected(),ctx(),operations(),rationale(),generation());let previous=draft_proposal();spawn(async move{let result=async{let ops:Vec<Value>=serde_json::from_str(&ops).map_err(|e|e.to_string())?;let mut args=json!({"action":if previous.is_null(){"create"}else{"revise"},"universe":u,"universe_id":c["frame"]["universe"],"context_id":c["context_id"],"operations":ops,"submission":"submitted","rationale":reason,"idempotency_key":key()});if !previous.is_null(){args["proposal_reference"]=previous;}send(r,p,tool("universe_propose",args)?).await}.await;if generation()==g{match result{Ok(v)=>{proposal.set(v["result"].clone());validation.set(Value::Null);review.set(Value::Null);approved.set(false);draft_proposal.set(serde_json::to_value(reference(&v["result"]).expect("typed proposal")).unwrap());status.set("Proposal saved. Canon is unchanged. Validate and review it next.".into());},Err(e)=>status.set(e)}busy.set(false);}});},"Save proposal for review"}
                        hr{}
                        button{class:"secondary",disabled:busy()||saving(),onclick:move|_|{draft_proposal.set(Value::Null);operations.set("[]".into());rationale.set(String::new());draft_base.set(ctx()["frame"]["revision"].clone());proposal.set(Value::Null);validation.set(Value::Null);review.set(Value::Null);approved.set(false);},"Start a new empty draft"}
                        h3{"Review an agent proposal"}label{r#for:"agent-proposal","Proposal ID"}input{id:"agent-proposal",value:proposal_id,oninput:move|e|proposal_id.set(e.value())}label{r#for:"agent-version","Exact version"}input{id:"agent-version",value:proposal_version,oninput:move|e|proposal_version.set(e.value())}
                        button{disabled:busy()||saving(),onclick:move|_|{busy.set(true);let(r,p,u,id,version,g)=(root(),profile(),selected(),proposal_id(),proposal_version(),generation());spawn(async move{let result=async{let version:u64=version.parse().map_err(|_|"Version must be a positive integer".to_string())?;load_proposal(r,p,json!({"universe":u,"proposal_id":id,"version":version})).await}.await;if generation()==g{match result{Ok(v)=>{proposal.set(v["result"].clone());validation.set(Value::Null);review.set(Value::Null);approved.set(false);status.set("Agent proposal loaded. Its base must match your pinned revision.".into());},Err(e)=>status.set(e)}busy.set(false);}});},"Load exact proposal"}
                    }
                }
                if !proposal().is_null(){section{class:"panel","aria-label":"Exact proposal review",h2{"Review changes and evidence"}p{{format!("Proposal {} · version {}",proposal()["proposal_id"],proposal()["version"])}}
                    button{class:"secondary",disabled:busy()||saving()||proposal()["withdrawn"]==true,onclick:move|_|{busy.set(true);let(r,p,u,pr,g)=(root(),profile(),selected(),proposal(),generation());spawn(async move{let result=async{let f=&pr["base_frame"];let opened=send(r.clone(),p.clone(),tool("universe_open_context",json!({"universe":u,"continuity_id":f["continuity"],"revision":{"kind":"exact","revision_id":f["revision"]},"represented_context":f["context"]["record"],"temporal_query":f["time"],"temporal_systems":[],"perspective":"author"}))?).await?;send(r,p,tool("universe_propose",json!({"action":"withdraw","universe":u,"context_id":opened["result"]["context_id"],"proposal_reference":reference(&pr)?,"idempotency_key":format!("native-withdraw-{}",pr["digest"])}))?).await}.await;if generation()==g{match result{Ok(v)=>{proposal.set(v["result"].clone());validation.set(Value::Null);review.set(Value::Null);approved.set(false);status.set("Proposal withdrawn. It cannot publish new canon.".into());},Err(e)=>status.set(e)}busy.set(false);}});},"Withdraw this proposal"}
                    button{disabled:busy()||saving(),onclick:move|_|{busy.set(true);review.set(Value::Null);approved.set(false);let(r,p,u,c,pr,g)=(root(),profile(),selected(),ctx(),proposal(),generation());spawn(async move{let result=async{let reference=reference(&pr)?;let checked=send(r.clone(),p.clone(),tool("universe_validate",json!({"mode":"proposal","universe":u,"universe_id":c["frame"]["universe"],"context_id":c["context_id"],"proposal_reference":reference,"check_scope":"universe"}))?).await?;let effects=send(r,p,EngineRequest::Review{universe:Selector(u),proposal_reference:reference}).await?;Ok::<_,String>((checked,effects))}.await;if generation()==g{match result{Ok((v,e))=>{validation.set(v["result"].clone());review.set(e);approved.set(false);status.set("Read the resolved changes, complete world footprint, and coverage before approving.".into());},Err(e)=>status.set(e)}busy.set(false);}});},"Validate and show exact changes"}
                    if !review().is_null(){
                        section{class:"panel","aria-label":"Source assessment review",
                            h3{"Source assessment"}
                            p{"This is the assessor's declaration about the submitted material. Byte verification and engine checks are separate."}
                            p{{format!("Selection generation: {}",review()["assessment_review"]["selection"]["generation"])}}
                            super::readable::ReadValue{value:review()["assessment_review"]["state"].clone()}
                            if !review()["assessment_review"]["envelope"].is_null(){
                                p{"Exact attachment"}super::readable::ReadValue{value:review()["assessment_review"]["envelope"]["assessment_id"].clone()}
                                p{"Attachment digest"}super::readable::ReadValue{value:review()["assessment_review"]["envelope"]["digest"].clone()}
                                for (label, member) in [("Assessor", "assessor"),("Submitted sources and ranges", "sources"),("Exact dependencies", "dependencies"),("Declared inventory", "declared_inventory"),("Inventory declaration and exclusions", "inventory_declaration"),("Claim mappings and unchanged evidence", "claim_mappings"),("Unresolved material", "unresolved"),("Assessor declares", "conclusion")] {
                                    details{open:true,summary{"{label}"}super::readable::ReadValue{value:review()["assessment_review"]["envelope"]["body"][member].clone()}}
                                }
                            }
                        }
                        super::readable::OperationReview{operations:proposal()["operations"].clone()}
                        p{"Write footprint"}super::readable::ReadValue{value:review()["footprint"].clone()}details{open:true,summary{"Resolved record changes"}super::readable::ReadValue{value:review()["diff"].clone()}}super::readable::ValidationReview{value:validation(),choices:choices(&hits(),&definitions(),&operations())}
                        for acceptance_key in [format!("{}-{}-{}",root(),profile(),proposal()["digest"])] {div{key:"{acceptance_key}",
                            super::resource_acceptance::ResourceAcceptance{validation:validation(),choices:choices(&hits(),&definitions(),&proposal()["operations"].to_string()),profile:profile(),author:author_profile()==format!("{}:{}",root(),profile()),disabled:busy()||saving()||proposal()["withdrawn"]==true,onaccept:move|decision:Value|{
                                busy.set(true);let(r,p,u,c,pr,g)=(root(),profile(),selected(),ctx(),proposal(),generation());
                                spawn(async move{let result=async{
                                    send(r,p,super::resource_acceptance::revision_request(&u,&c["context_id"],&pr,decision,&key())?).await
                                }.await;if generation()==g{match result{Ok(v)=>{
                                    let revised=v["result"].clone();
                                    if draft_proposal()["proposal_id"]==pr["proposal_id"]{operations.set(revised["operations"].to_string());draft_proposal.set(serde_json::to_value(reference(&revised).expect("typed proposal")).unwrap());}
                                    proposal.set(revised);validation.set(Value::Null);review.set(Value::Null);approved.set(false);status.set("Exact resource acceptance recorded in the revised proposal. Validate and review it, then approve separately. Arrival remains unexplained.".into());
                                },Err(e)=>status.set(e)}busy.set(false);}});
                            }}
                        }}
                        button{disabled:busy()||saving()||approved()||validation()["final_binding_digest"].is_null(),onclick:move|_|{busy.set(true);let(r,p,u,pr,v,g)=(root(),profile(),selected(),proposal(),validation(),generation());spawn(async move{let result=async{send(r,p,EngineRequest::Approve{universe:Selector(u),proposal_reference:reference(&pr)?,validation_run:serde_json::from_value(v["execution"]["run_id"].clone()).map_err(|e|e.to_string())?}).await}.await;if generation()==g{match result{Ok(_)=>{approved.set(true);status.set("Exact proposal approved. Commit publishes these reviewed changes atomically.".into());},Err(e)=>status.set(e)}busy.set(false);}});},"Approve this exact proposal"}
                        button{disabled:busy()||saving()||!approved(),onclick:move|_|{busy.set(true);let(r,p,u,pr,v,g)=(root(),profile(),selected(),proposal(),validation(),generation());spawn(async move{let result=async{send(r,p,tool("universe_commit",json!({"universe":u,"universe_id":pr["base_frame"]["universe"],"proposal_reference":reference(&pr)?,"expected_base_revision":pr["base_frame"]["revision"],"validation_run":v["execution"]["run_id"],"idempotency_key":format!("native-commit-{}",pr["digest"])}))?).await}.await;if generation()==g{match result{Ok(v)=>{approved.set(false);if draft_proposal()["proposal_id"]==pr["proposal_id"]{draft_proposal.set(Value::Null);operations.set("[]".into());rationale.set(String::new());draft_base.set(v["result"]["revision"].clone());}status.set(format!("Committed revision {}. Open current revision to query the result.",v["result"]["revision"]));},Err(e)=>status.set(e)}busy.set(false);}});},"Commit approved changes"}
                    }
                }}
                for admin_key in [format!("{}-{}-{}",root(),profile(),selected())] {div{key:"{admin_key}",super::administration::Administration{root:root(),profile:profile(),universe:selected(),universe_id:ctx()["frame"]["universe"].as_str().unwrap_or_default().to_string(),onpurged:move|_|{ctx.set(Value::Null);selected.set(String::new());hits.set(vec![]);inspected.set(Value::Null);operations.set("[]".into());rationale.set(String::new());proposal.set(Value::Null);review.set(Value::Null);validation.set(Value::Null);approved.set(false);generation+=1;}}}}
                for scope_key in [format!("{}-{}-{}",selected(),profile(),root())] {div{key:"{scope_key}",super::transfer::Transfer{root:root(),profile:profile(),universe:selected()}}}
                details{class:"panel",summary{"Source text and recovery"}
                    label{r#for:"source-label","Source label"}input{id:"source-label",value:source_label,oninput:move|e|source_label.set(e.value())}label{r#for:"source-text","Exact UTF-8 source text"}textarea{id:"source-text",rows:6,value:source_text,oninput:move|e|source_text.set(e.value())}
                    button{disabled:busy()||saving(),onclick:move|_|{busy.set(true);let(r,p,u,label,text,g)=(root(),profile(),selected(),source_label(),source_text(),generation());spawn(async move{match send(r,p,EngineRequest::StageSource{universe:Selector(u),label,text}).await{Ok(v) if generation()==g=>{let Ok(mut ops)=serde_json::from_str::<Vec<Value>>(&operations())else{status.set("The recovered draft cannot be decoded. It has been preserved; start a new empty draft explicitly before staging a source.".into());busy.set(false);return;};ops.extend(v["operations"].as_array().cloned().unwrap_or_default());operations.set(serde_json::to_string(&ops).unwrap());proposal.set(Value::Null);review.set(Value::Null);validation.set(Value::Null);approved.set(false);status.set("Source staged. Save and review its proposal to admit the source records.".into());},Ok(_)=>{},Err(e)=>status.set(e)}busy.set(false);});},"Stage source as a proposal"}
                    label{r#for:"backup-path","New backup file path"}input{id:"backup-path",value:backup_path,oninput:move|e|backup_path.set(e.value())}
                    button{disabled:busy()||saving()||backup_path().is_empty(),onclick:move|_|{busy.set(true);let(r,p,u,destination)=(root(),profile(),selected(),backup_path());spawn(async move{match send(r,p,EngineRequest::Backup{universe:Selector(u),destination:destination.into()}).await{Ok(_)=>status.set("Verified whole-universe backup created, including immutable history and sources.".into()),Err(e)=>status.set(e)}busy.set(false);});},"Create verified backup"}
                }
            }
            footer{"Closing this window leaves the engine running. An approval applies only to the exact proposal, base revision and validation shown. Unsupported checks remain visible and blocking policies cannot be waived here."}
        }
    }
}
