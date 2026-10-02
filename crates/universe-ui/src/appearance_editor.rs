//! Shared appearance authoring for every entry. Source images stay in the package.
use super::select::{Choice, RichSelect};
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{ids::*, records::*, scope::Validity, value::RecordRef, Frame};
use universe_protocol::{installation::EngineRequest, request::Selector};
#[derive(Clone, Default)]
struct Form {
    target: String,
    label: String,
    description: String,
    atmosphere: String,
    images: Vec<AppearanceImage>,
    links: Vec<AppearanceLink>,
    related: String,
    relationship: String,
    note: String,
    timed: bool,
    start: String,
    end: String,
    existing: Option<(RecordId, RecordVersionId)>,
    previews: std::collections::BTreeMap<String, String>,
    staged: Vec<Value>,
}
impl Form {
    fn appearance(
        &self,
        frame: &Frame,
        clock: Option<&universe_domain::chronology::Chronology>,
    ) -> Result<Appearance, String> {
        if self.label.trim().is_empty() {
            return Err("Name this appearance reference.".into());
        }
        if self.description.trim().is_empty()
            && self.atmosphere.trim().is_empty()
            && self.images.is_empty()
            && self.links.is_empty()
        {
            return Err("Add a description, image or relationship.".into());
        }
        let target = if self.target.is_empty() {
            AppearanceTarget::Universe
        } else {
            AppearanceTarget::Entry {
                entry: RecordRef::new(
                    frame.universe.clone(),
                    RecordId::parse(&self.target).map_err(|e| e.to_string())?,
                ),
            }
        };
        let validity = if self.timed {
            let c =
                clock.ok_or("An authored calendar is required for dated appearance references.")?;
            let bound = |s: &str| -> Result<universe_domain::temporal::TemporalBound, String> {
                if s.trim().is_empty() {
                    Ok(universe_domain::temporal::TemporalBound::Unbounded)
                } else {
                    Ok(universe_domain::temporal::TemporalBound::Exact {
                        value: c.coordinate(s)?,
                    })
                }
            };
            Validity::CalendarInterval {
                calendar: c.calendar.clone(),
                start: bound(&self.start)?,
                end: bound(&self.end)?,
            }
        } else {
            Validity::Unspecified
        };
        Ok(Appearance {
            target,
            label: self.label.clone(),
            physical_description: self.description.clone(),
            atmosphere: self.atmosphere.clone(),
            images: self.images.clone(),
            links: self.links.clone(),
            validity,
        })
    }
}
#[component]
pub fn AppearanceEditor(
    root: String,
    profile: String,
    universe: String,
    context_id: ContextId,
    frame: Frame,
    choices: Vec<Value>,
    inspected: Value,
    clock: Option<universe_domain::chronology::Chronology>,
    disabled: bool,
    onadd: EventHandler<Vec<Value>>,
) -> Element {
    let mut form = use_signal(Form::default);
    let mut status = use_signal(String::new);
    let mut busy = use_signal(|| false);
    let mut references = use_signal(Vec::<RecordVersion>::new);
    let mut selected_reference = use_signal(String::new);
    let mut targets = vec![Choice::described(
        "",
        "This universe",
        "Overall visual and sensory reference for the universe.",
    )];
    targets.extend(choices.iter().map(|c| {
        let id = c["record_id"].as_str().unwrap_or_default();
        Choice::described(
            id,
            c["label"].as_str().unwrap_or(id),
            format!(
                "{} · Optional appearance reference",
                c["kind"].as_str().unwrap_or("Entry")
            ),
        )
    }));
    let selected = inspected["records"][0].clone();
    if let Some(id) = selected["identity"]["record_id"].as_str() {
        if !targets.iter().any(|c| c.value == id) {
            targets.push(Choice::described(
                id,
                "Inspected entry",
                "Use the entry currently open in the inspector.",
            ));
        }
    }
    let related = targets
        .iter()
        .filter(|c| !c.value.is_empty())
        .cloned()
        .collect::<Vec<_>>();
    let loaded = serde_json::from_value::<RecordVersion>(selected).ok();
    let loaded = references()
        .into_iter()
        .find(|r| r.identity.record_id.as_str() == selected_reference())
        .or(loaded);
    let edit = loaded.filter(|r| matches!(r.payload, Payload::Appearance(_)));
    let unavailable = disabled || busy();
    rsx! {details{class:"panel",
        summary{"Appearance and atmosphere — any entry"}
        p{"Describe physical details, materials, colours, textures, sound, scent and mood. Images are optional references; captions state what should remain consistent."}
        p{role:"status","aria-live":"polite","{status}"}
        button{disabled:unavailable,onclick:{let root=root.clone();let profile=profile.clone();let universe=universe.clone();let context=context_id.clone();let anchor=frame.context.record.to_string();move|_|{let anchor=anchor.clone();let(root,profile,universe,context,target)=(root.clone(),profile.clone(),universe.clone(),context.clone(),form.read().target.clone());busy.set(true);spawn(async move{let args=json!({"universe":universe,"context_id":context,"focus_ids":if target.is_empty(){vec![anchor]}else{vec![target.clone()]},"purpose":"Appearance reference library","byte_budget":65536});let result=match super::author::tool("universe_get_context",args){Ok(req)=>super::author::send(root,profile,req).await,Err(e)=>Err(e)};match result{Ok(v)=>{let records:Vec<RecordVersion>=serde_json::from_value(v["result"]["records"].clone()).unwrap_or_default();references.set(records.into_iter().filter(|r|matches!(&r.payload,Payload::Appearance(a) if match &a.target{AppearanceTarget::Universe=>target.is_empty(),AppearanceTarget::Entry{entry}=>entry.record.as_str()==target})).collect());selected_reference.set(String::new());status.set(if v["result"]["coverage"]=="complete"{"Appearance references loaded."}else{"Partial reference list. Use the explorer to find additional appearance records."}.into());},Err(e)=>status.set(e)}busy.set(false);});}},"Find saved appearances for this entry"}
        if !references.read().is_empty(){RichSelect{id:"appearance-existing",value:selected_reference(),disabled:unavailable,options:references.read().iter().map(|r|{let Payload::Appearance(a)=&r.payload else{unreachable!()};Choice::described(r.identity.record_id.to_string(),a.label.clone(),a.physical_description.chars().take(120).collect::<String>())}).collect::<Vec<_>>(),onchange:move|e:super::select::SelectionEvent|selected_reference.set(e.value())}}
        if let Some(record)=edit {button{disabled:unavailable,onclick:{let root=root.clone();let profile=profile.clone();let universe=universe.clone();let context=context_id.clone();let clock=clock.clone();move|_|{
            let Payload::Appearance(a)=record.payload.clone()else{return;};
            if let Validity::CalendarInterval{calendar,..}=&a.validity{if clock.as_ref().is_none_or(|c|&c.calendar!=calendar){status.set("Open this reference in its authored calendar before editing its dates.".into());return;}}
            let (timed,start,end)=match &a.validity{Validity::CalendarInterval{calendar,start,end}=>{let display=|bound:&universe_domain::temporal::TemporalBound|match bound{universe_domain::temporal::TemporalBound::Exact{value}=>clock.as_ref().filter(|c|&c.calendar==calendar).and_then(|c|c.display(value).ok()).unwrap_or_else(||value.clone()),_=>String::new()};(true,display(start),display(end))},_=>(false,String::new(),String::new())};
            form.set(Form{target:match a.target{AppearanceTarget::Universe=>String::new(),AppearanceTarget::Entry{entry}=>entry.record.to_string()},label:a.label,description:a.physical_description,atmosphere:a.atmosphere,images:a.images.clone(),links:a.links,timed,start,end,existing:Some((record.identity.record_id.clone(),record.record_version_id.clone())),..Default::default()});
            let(root,profile,universe,context)=(root.clone(),profile.clone(),universe.clone(),context.clone());busy.set(true);
            spawn(async move{for image in a.images{match super::author::send(root.clone(),profile.clone(),EngineRequest::ImagePreview{universe:Selector(universe.clone()),context_id:context.clone(),asset:image.asset.record.clone()}).await{Ok(v)=>{if let Some(preview)=v["preview"].as_str(){form.write().previews.insert(image.asset.record.to_string(),preview.into());}},Err(e)=>status.set(e)}}busy.set(false);});
        }},"Load selected appearance and images"}}
        label{r#for:"appearance-target","Entry"}RichSelect{id:"appearance-target",value:form.read().target.clone(),options:targets,disabled:unavailable,onchange:move|e:super::select::SelectionEvent|form.write().target=e.value()}
        label{r#for:"appearance-label","Reference name"}input{id:"appearance-label",value:form.read().label.clone(),disabled:unavailable,oninput:move|e|form.write().label=e.value()}
        label{r#for:"appearance-description","Physical description (optional)"}textarea{id:"appearance-description",rows:5,value:form.read().description.clone(),disabled:unavailable,oninput:move|e|form.write().description=e.value()}
        label{r#for:"appearance-atmosphere","Atmosphere and sensory details (optional)"}textarea{id:"appearance-atmosphere",rows:3,value:form.read().atmosphere.clone(),disabled:unavailable,oninput:move|e|form.write().atmosphere=e.value()}
        label{r#for:"appearance-image","Add a reference image"}input{id:"appearance-image",r#type:"file",accept:"image/png,image/jpeg,image/webp",disabled:unavailable||form.read().images.len()>=16,onchange:{let root=root.clone();let profile=profile.clone();let universe=universe.clone();let uid=frame.universe.clone();move|e|{let Some(file)=e.files().into_iter().next()else{return;};let(root,profile,universe,uid)=(root.clone(),profile.clone(),universe.clone(),uid.clone());busy.set(true);spawn(async move{match super::author::send(root,profile,EngineRequest::StageImage{universe:Selector(universe),source:file.path()}).await{Ok(v)=>{if let Some(id)=v["asset_id"].as_str().and_then(|s|RecordId::parse(s).ok()){let mut f=form.write();f.images.push(AppearanceImage{asset:RecordRef::new(uid,id.clone()),caption:String::new(),purpose:ImagePurpose::Appearance});f.previews.insert(id.to_string(),v["preview"].as_str().unwrap_or_default().into());if let Some(ops)=v["operations"].as_array(){f.staged.extend(ops.clone());}status.set("Image copied into the universe package. Add this reference to the draft to retain the attachment.".into());}},Err(e)=>status.set(e)}busy.set(false);});}}}
        small{"PNG, JPEG or WebP · up to 10 MiB, 8192 pixels per edge and 32 megapixels. Originals remain intact in backups and exports."}
        for (index,image) in form.read().images.clone().into_iter().enumerate(){figure{key:"{image.asset.record}",
            if let Some(preview)=form.read().previews.get(image.asset.record.as_str()){img{src:preview.clone(),alt:if image.caption.is_empty(){"Appearance reference image".into()}else{image.caption.clone()},style:"max-width:100%;max-height:320px;object-fit:contain"}}
            label{r#for:format!("appearance-caption-{index}"),"Caption / details to preserve"}textarea{id:format!("appearance-caption-{index}"),rows:2,value:image.caption.clone(),disabled:unavailable,oninput:move|e|form.write().images[index].caption=e.value()}
            label{r#for:format!("appearance-purpose-{index}"),"Image purpose"}RichSelect{id:format!("appearance-purpose-{index}"),value:match image.purpose{ImagePurpose::Appearance=>"appearance",ImagePurpose::Detail=>"detail",ImagePurpose::Inspiration=>"inspiration"}.to_string(),options:vec![Choice::described("appearance","Appearance reference","Use the authored caption and image together as a visual reference."),Choice::described("detail","Detail reference","A close-up or specific material, shape or colour."),Choice::described("inspiration","Inspiration only","Suggests a mood; does not establish the exact appearance.")],disabled:unavailable,onchange:move|e:super::select::SelectionEvent|form.write().images[index].purpose=match e.value().as_str(){"detail"=>ImagePurpose::Detail,"inspiration"=>ImagePurpose::Inspiration,_=>ImagePurpose::Appearance}}
            button{class:"secondary",disabled:unavailable,onclick:move|_|{form.write().images.remove(index);},"Remove image from this reference"}
        }}
        label{r#for:"appearance-related","Related entry (optional)"}RichSelect{id:"appearance-related",value:form.read().related.clone(),options:related,disabled:unavailable,onchange:move|e:super::select::SelectionEvent|form.write().related=e.value()}
        label{r#for:"appearance-relationship","Visual relationship"}RichSelect{id:"appearance-relationship",value:form.read().relationship.clone(),options:vec![Choice::described("matches","Matches","Shares explicitly described visual characteristics."),Choice::described("complements","Complements","Coordinates with this entry without being identical."),Choice::described("contrasts","Contrasts","Intentionally differs in the described features."),Choice::described("detail_of","Detail of","Shows a part or close-up of the related entry.")],disabled:unavailable,onchange:move|e:super::select::SelectionEvent|form.write().relationship=e.value()}
        label{r#for:"appearance-note","What connects these appearances?"}textarea{id:"appearance-note",value:form.read().note.clone(),disabled:unavailable,oninput:move|e|form.write().note=e.value()}
        button{disabled:unavailable||form.read().related.is_empty()||form.read().relationship.is_empty()||form.read().links.len()>=32,onclick:{let uid=frame.universe.clone();move|_|{let mut f=form.write();let Ok(id)=RecordId::parse(&f.related)else{return;};let relationship=match f.relationship.as_str(){"complements"=>AppearanceRelationship::Complements,"contrasts"=>AppearanceRelationship::Contrasts,"detail_of"=>AppearanceRelationship::DetailOf,_=>AppearanceRelationship::Matches};let note=f.note.clone();f.links.push(AppearanceLink{entry:RecordRef::new(uid.clone(),id),relationship,note});f.note.clear();}},"Add appearance relationship"}
        for (index,link) in form.read().links.clone().into_iter().enumerate(){p{"{link.relationship:?}: {link.note}"}button{class:"secondary",disabled:unavailable,onclick:move|_|{form.write().links.remove(index);},"Remove relationship"}}
        label{input{r#type:"checkbox",checked:form.read().timed,disabled:unavailable,onchange:move|e|form.write().timed=e.checked()}"Limit this appearance to a story-time interval"}
        if form.read().timed{p{"Use the current authored calendar. Start is inclusive; end is exclusive. Blank means explicitly unbounded."}label{r#for:"appearance-start","Starts"}input{id:"appearance-start",value:form.read().start.clone(),disabled:unavailable,oninput:move|e|form.write().start=e.value()}label{r#for:"appearance-end","Ends"}input{id:"appearance-end",value:form.read().end.clone(),disabled:unavailable,oninput:move|e|form.write().end=e.value()}}
        button{disabled:unavailable,onclick:move|_|{let f=form.read().clone();match f.appearance(&frame,clock.as_ref()){Ok(record)=>{let op=match f.existing{Some((id,version))=>DomainOperation::ReviseAppearance{record:RecordRef::new(frame.universe.clone(),id),expected_version:version,replacement:record},None=>DomainOperation::CreateAppearance{client_ref:RecordId::generate(&mut rand::rng()).to_string(),record}};let mut ops=f.staged;ops.push(serde_json::to_value(op).unwrap());onadd.call(ops);form.set(Form::default());status.set("Appearance added to the proposal draft. Check the autosave status above, then review and approve to change canon.".into());},Err(e)=>status.set(e)}},"Add appearance to draft"}
    }}
}
