//! Installation authority controls. Credentials are never loaded into this view.
use super::author::send;
use dioxus::prelude::*;
use serde_json::Value;
use universe_domain::ids::*;
use universe_protocol::{
    installation::{EngineRequest, GrantLimits, GrantSpec},
    request::Selector,
};
fn ids<T>(
    input: &str,
    parse: impl Fn(&str) -> Result<T, universe_domain::DomainError>,
) -> Result<Option<Vec<T>>, String> {
    let values = input
        .split([',', ' ', '\n'])
        .filter(|s| !s.is_empty())
        .map(parse)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;
    Ok(if values.is_empty() {
        None
    } else {
        Some(values)
    })
}
fn listed(value: &Value) -> String {
    value
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .collect::<Vec<_>>()
        .join(", ")
}
#[component]
pub fn Administration(
    root: String,
    profile: String,
    universe: String,
    universe_id: String,
    onpurged: EventHandler<()>,
) -> Element {
    let mut data = use_signal(|| Value::Null);
    let mut selected = use_signal(String::new);
    let mut worlds = use_signal(String::new);
    let mut entities = use_signal(String::new);
    let mut predicates = use_signal(String::new);
    let mut continuities = use_signal(String::new);
    let mut hours = use_signal(|| "24".to_string());
    let mut propose = use_signal(|| false);
    let mut edit = use_signal(|| false);
    let mut protected = use_signal(|| false);
    let mut delegated = use_signal(|| false);
    let mut shared = use_signal(|| false);
    let mut busy = use_signal(|| false);
    let mut status = use_signal(String::new);
    let mut preview = use_signal(|| Value::Null);
    let mut confirmation = use_signal(String::new);
    rsx! {details{class:"panel",summary{"Profiles, grants and privileged maintenance"}
        p{"These controls require the installation author. Research access does not grant write authority. Entity and predicate boundaries limit writes; universe and world scope control reading."}
        button{disabled:busy(),onclick:{let(r,p)=(root.clone(),profile.clone());move|_|{busy.set(true);let(r,p)=(r.clone(),p.clone());spawn(async move{match send(r,p,EngineRequest::Profiles).await{Ok(v)=>data.set(v),Err(e)=>status.set(e)}busy.set(false);});}},"Load profiles and grants"}
        button{disabled:busy(),onclick:{let(r,p)=(root.clone(),profile.clone());move|_|{busy.set(true);let(r,p)=(r.clone(),p.clone());spawn(async move{match send(r.clone(),p.clone(),EngineRequest::Enroll).await{Ok(v)=>{selected.set(v["profile_id"].as_str().unwrap_or_default().into());match send(r,p,EngineRequest::Profiles).await{Ok(v)=>data.set(v),Err(e)=>status.set(e)}status.set("Profile enrolled with no universe access. Configure its grant below.".into());},Err(e)=>status.set(e)}busy.set(false);});}},"Enroll a profile"}
        label{r#for:"admin-profile","Profile"}super::select::RichSelect{id:"admin-profile",disabled:busy(),value:selected(),options:std::iter::once(super::select::Choice::new("","Choose a profile")).chain(data()["profiles"].as_array().into_iter().flatten().filter(|v|v["author"]!=true&&v["revoked"]!=true).map(|v|super::select::Choice::new(v["profile_id"].as_str().unwrap_or_default(),v["profile_id"].as_str().unwrap_or_default()))).collect(),onchange:{let u=universe_id.clone();move|e:super::select::SelectionEvent|{
            selected.set(e.value());let saved=data()["grants"].as_array().into_iter().flatten().find(|g|g["profile_id"]==e.value()&&g["universe_id"]==u).cloned().unwrap_or(Value::Null);
            worlds.set(listed(&saved["worlds"]));entities.set(listed(&saved["limits"]["entities"]));predicates.set(listed(&saved["limits"]["predicates"]));continuities.set(listed(&saved["limits"]["continuities"]));propose.set(saved["propose"]==true);edit.set(saved["edit"]==true);protected.set(saved["protected"]==true);delegated.set(saved["limits"]["delegated_commit"]==true);shared.set(saved["limits"]["allow_shared"]==true);
        }}}
        super::readable::ReadValue{value:data()["grants"].clone()}
        p{{format!("Grant target: {}",universe)}}
        label{r#for:"grant-worlds","Allowed world IDs (blank: universe research)"}input{id:"grant-worlds",disabled:busy(),value:worlds,oninput:move|e|worlds.set(e.value())}
        label{r#for:"grant-entities","Writable entity IDs (comma separated)"}input{id:"grant-entities",disabled:busy(),value:entities,oninput:move|e|entities.set(e.value())}
        label{r#for:"grant-predicates","Writable predicate IDs (comma separated)"}input{id:"grant-predicates",disabled:busy(),value:predicates,oninput:move|e|predicates.set(e.value())}
        label{r#for:"grant-continuities","Writable continuity IDs (comma separated)"}input{id:"grant-continuities",disabled:busy(),value:continuities,oninput:move|e|continuities.set(e.value())}
        label{r#for:"grant-hours","Expire in hours from saving (blank: no expiry)"}input{id:"grant-hours",disabled:busy(),value:hours,oninput:move|e|hours.set(e.value())}
        label{input{r#type:"checkbox",disabled:busy(),checked:propose(),onchange:move|e|propose.set(e.checked())}"May propose"}
        label{input{r#type:"checkbox",disabled:busy(),checked:edit(),onchange:move|e|edit.set(e.checked())}"May commit approved changes"}
        label{input{r#type:"checkbox",disabled:busy(),checked:protected(),onchange:move|e|protected.set(e.checked())}"May propose protected definitions and policy"}
        label{input{r#type:"checkbox",disabled:busy(),checked:delegated(),onchange:move|e|delegated.set(e.checked())}"Delegate commits within all explicit boundaries, without separate approval"}
        label{input{r#type:"checkbox",disabled:busy(),checked:shared(),onchange:move|e|shared.set(e.checked())}"Delegation also covers shared facts within these boundaries"}
        button{disabled:busy()||selected().is_empty()||universe_id.is_empty(),onclick:{let(r,p,u)=(root.clone(),profile.clone(),universe_id.clone());move|_|{
            let grant=(||->Result<GrantSpec,String>{let expires_at=if hours().trim().is_empty(){None}else{let hours=hours().parse::<u64>().map_err(|_|"Enter whole hours")?;if !(1..=8760).contains(&hours){return Err("Choose 1..8760 hours".into());}Some(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|e|e.to_string())?.as_secs()+hours*3600)};
                Ok(GrantSpec{profile_id:ProfileId::parse(&selected()).map_err(|e|e.to_string())?,universe_id:UniverseId::parse(&u).map_err(|e|e.to_string())?,worlds:ids(&worlds(),WorldId::parse)?,propose:propose(),edit:edit(),protected:protected(),limits:GrantLimits{entities:ids(&entities(),RecordId::parse)?,predicates:ids(&predicates(),RecordId::parse)?,continuities:ids(&continuities(),ContinuityId::parse)?,expires_at,delegated_commit:delegated(),allow_shared:shared()}})})();
            match grant{Err(e)=>status.set(e),Ok(grant)=>{busy.set(true);let(r,p)=(r.clone(),p.clone());spawn(async move{match send(r.clone(),p.clone(),EngineRequest::Grant{grant}).await{Ok(_)=>{status.set("Grant saved. Previously opened contexts must be reopened.".into());if let Ok(v)=send(r,p,EngineRequest::Profiles).await{data.set(v);}},Err(e)=>status.set(e)}busy.set(false);});}}
        }},"Save this grant"}
        button{disabled:busy()||selected().is_empty()||universe_id.is_empty(),onclick:{let(r,p,u)=(root.clone(),profile.clone(),universe_id.clone());move|_|{let (Ok(profile_id),Ok(universe_id))=(ProfileId::parse(&selected()),UniverseId::parse(&u))else{return;};busy.set(true);let(r,p)=(r.clone(),p.clone());spawn(async move{match send(r.clone(),p.clone(),EngineRequest::WithdrawGrant{profile_id,universe_id}).await{Ok(_)=>{status.set("Universe grant withdrawn.".into());if let Ok(v)=send(r,p,EngineRequest::Profiles).await{data.set(v);}},Err(e)=>status.set(e)}busy.set(false);});}},"Withdraw this universe grant"}
        button{disabled:busy()||selected().is_empty(),onclick:{let(r,p)=(root.clone(),profile.clone());move|_|{let Ok(profile_id)=ProfileId::parse(&selected())else{return;};busy.set(true);let(r,p)=(r.clone(),p.clone());spawn(async move{match send(r.clone(),p.clone(),EngineRequest::Revoke{profile_id}).await{Ok(_)=>{selected.set(String::new());status.set("Profile revoked across all universes.".into());if let Ok(v)=send(r,p,EngineRequest::Profiles).await{data.set(v);}},Err(e)=>status.set(e)}busy.set(false);});}},"Revoke profile everywhere"}
        hr{}h3{"Purge this entire universe package"}
        p{"This permanently removes every continuity, revision, source, image, draft and approval in this registered package. For ordinary edits, use a reviewed deletion or compensating revision. Backups, exports and client transcripts remain outside this operation."}
        button{disabled:busy()||universe_id.is_empty(),onclick:{let(r,p,u)=(root.clone(),profile.clone(),universe.clone());move|_|{busy.set(true);confirmation.set(String::new());let(r,p,u)=(r.clone(),p.clone(),u.clone());spawn(async move{match send(r,p,EngineRequest::PreviewPurge{universe:Selector(u)}).await{Ok(v)=>preview.set(v),Err(e)=>status.set(e)}busy.set(false);});}},"Preview purge impact"}
        if !preview().is_null(){super::readable::ReadValue{value:preview()["impact"].clone()}
            label{r#for:"purge-confirm",{format!("Type PURGE {} to confirm the preview",universe)}}input{id:"purge-confirm",disabled:busy(),value:confirmation,oninput:move|e|confirmation.set(e.value())}
            button{disabled:busy()||confirmation()!=format!("PURGE {}",universe),onclick:{let(r,p,u)=(root.clone(),profile.clone(),universe.clone());move|_|{busy.set(true);let(r,p,u,digest,confirmation)=(r.clone(),p.clone(),u.clone(),preview()["digest"].as_str().unwrap_or_default().to_string(),confirmation());spawn(async move{match send(r,p,EngineRequest::Purge{universe:Selector(u),digest,confirmation}).await{Ok(_)=>{preview.set(Value::Null);status.set("Universe package purged. External copies remain unchanged.".into());onpurged.call(());},Err(e)=>{preview.set(Value::Null);status.set(e)}}busy.set(false);});}},"Permanently purge entire package"}
        }
        p{role:"status","{status}"}
    }}
}
