//! Typed occurrences and possession-dependent powers; all changes enter a proposal.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{chronology::Chronology, ids::RecordId, records::DomainOperation, Frame};

#[component]
pub fn EventEditor(
    frame: Frame,
    clock: Option<Chronology>,
    choices: Vec<Value>,
    disabled: bool,
    onadd: EventHandler<Vec<Value>>,
) -> Element {
    let mut title = use_signal(String::new);
    let mut item = use_signal(String::new);
    let mut holder = use_signal(String::new);
    let mut predicate = use_signal(String::new);
    let mut power = use_signal(String::new);
    let mut polarity = use_signal(String::new);
    let mut occurrence = use_signal(String::new);
    let mut action = use_signal(String::new);
    let mut start = use_signal(String::new);
    let mut end = use_signal(String::new);
    let mut duration = use_signal(String::new);
    let mut world = use_signal(String::new);
    let mut region = use_signal(String::new);
    let mut error = use_signal(String::new);
    let mut power_start = use_signal(String::new);
    let mut power_end = use_signal(String::new);
    let mut power_duration = use_signal(String::new);
    let entities = super::select::record_choices(&choices, &["entity"], "Choose an entity");
    let holder_properties: Vec<_> = choices
        .iter()
        .filter(|c| {
            c["kind"] == "property"
                && c["definition"]["value"]["kind"] == "entity_ref"
                && c["definition"]["multiplicity"] == "single"
        })
        .cloned()
        .collect();
    let boolean_properties: Vec<_> = choices
        .iter()
        .filter(|c| c["kind"] == "property" && c["definition"]["value"]["kind"] == "boolean")
        .cloned()
        .collect();
    let properties = super::select::record_choices(
        &holder_properties,
        &["property"],
        "Choose a single holder property",
    );
    let powers =
        super::select::record_choices(&boolean_properties, &["property"], "Choose a Boolean power");
    rsx! {
        super::action_editor::ActionEditor {frame:frame.clone(),choices:choices.clone(),disabled,onadd:move|op:Value|onadd.call(vec![op])}
        details{summary{"Record an item transfer, loss or timed effect"}
        p{"Only an occurred event changes state. Select the item’s holder property and the holder. Refutation records loss of that possession. Existing authored evidence is retained for conflict checking."}
        label{r#for:"event-title","Event name"}input{id:"event-title",disabled,value:title,oninput:move|e|title.set(e.value())}
        label{r#for:"event-occurrence","Occurrence"}super::select::RichSelect{id:"event-occurrence",disabled,value:occurrence(),options:vec![super::select::Choice::new("","Choose occurrence"),super::select::Choice::described("occurred","Occurred","Establishes the declared state effects after this event."),super::select::Choice::described("planned","Planned","Preserves a plan; it does not establish its effects."),super::select::Choice::described("reported","Reported","Preserves an account; it does not establish objective occurrence."),super::select::Choice::described("hypothetical","Hypothetical","A considered possibility with no objective effects.")],onchange:move|e:super::select::SelectionEvent|occurrence.set(e.value())}
        label{r#for:"event-action","Declared action"}super::select::RichSelect{id:"event-action",disabled,value:action(),options:super::select::record_choices(&choices,&["action_definition"],"Choose an action"),onchange:move|e:super::select::SelectionEvent|action.set(e.value())}
        label{r#for:"event-item","Item or subject"}super::select::RichSelect{id:"event-item",disabled,value:item(),options:entities.clone(),onchange:move|e:super::select::SelectionEvent|item.set(e.value())}
        label{r#for:"event-holder-property","Holder property (single entity reference)"}super::select::RichSelect{id:"event-holder-property",disabled,value:predicate(),options:properties.clone(),onchange:move|e:super::select::SelectionEvent|predicate.set(e.value())}
        label{r#for:"event-holder","Holder"}super::select::RichSelect{id:"event-holder",disabled,value:holder(),options:entities.clone(),onchange:move|e:super::select::SelectionEvent|holder.set(e.value())}
        label{r#for:"event-polarity","Possession effect"}super::select::RichSelect{id:"event-polarity",disabled,value:polarity(),options:super::select::choices(&[("","Choose an effect"),("support","Has possession"),("refutation","Loses / does not have possession")]),onchange:move|e:super::select::SelectionEvent|polarity.set(e.value())}
        label{r#for:"event-start","Event timestamp in the story calendar"}input{id:"event-start",disabled,value:start,oninput:move|e|start.set(e.value())}
        label{r#for:"event-duration","Effect duration"}super::select::RichSelect{id:"event-duration",disabled,value:duration(),options:vec![super::select::Choice::new("","Choose explicitly"),super::select::Choice::described("persistent","Until explicitly changed","A later occurred possession change ends this generated effect."),super::select::Choice::described("end","Until an exact timestamp","The effect stops at the exclusive end, even without another event.")],onchange:move|e:super::select::SelectionEvent|duration.set(e.value())}
        if duration()=="end"{label{r#for:"event-end","Exclusive end timestamp"}input{id:"event-end",disabled,value:end,oninput:move|e|end.set(e.value())}}
        label{r#for:"event-world","World (blank explicitly means universe wide)"}super::select::RichSelect{id:"event-world",disabled,value:world(),options:super::select::typed_id_choices(&choices,"world","wld_","Universe wide"),onchange:move|e:super::select::SelectionEvent|world.set(e.value())}
        label{r#for:"event-region","Region (optional)"}super::select::RichSelect{id:"event-region",disabled,value:region(),options:super::select::record_choices(&choices,&["entity","realm"],"No region declared"),onchange:move|e:super::select::SelectionEvent|region.set(e.value())}
        button{disabled,onclick:{let frame=frame.clone();let clock=clock.clone();move|_|{
            let result=(||{
                if title().trim().is_empty()||occurrence().is_empty()||action().is_empty()||item().is_empty()||holder().is_empty()||predicate().is_empty()||polarity().is_empty(){return Err("Name the event and choose its action, occurrence, item, property, holder and effect.".into());}
                let clock=clock.as_ref().ok_or("This context needs an authored calendar.")?;
                let start=clock.coordinate(&start())?;
                let end=match duration().as_str(){"persistent"=>json!({"kind":"unbounded"}),"end"=>{let end=clock.coordinate(&end())?;if end.parse::<i128>().unwrap()<=start.parse::<i128>().unwrap(){return Err("The end must follow the event.".into());}json!({"kind":"exact","value":end})},_=>return Err("Choose an effect duration.".into())};
                let reference=|id:String|json!({"universe":frame.universe,"record":id});
                let prop=RecordId::generate(&mut rand::rng());let event=RecordId::generate(&mut rand::rng());
                let worlds=if world().is_empty(){vec![]}else{vec![world()]};
                let scope=json!({"context":frame.context,"applicability":if worlds.is_empty(){json!({"kind":"universe_wide"})}else{json!({"kind":"worlds","world_ids":worlds})}});
                let ops=vec![json!({"kind":"define_proposition","client_ref":prop,"record":{"subject":reference(item()),"predicate":reference(predicate()),"value":{"kind":"entity_ref","ref":reference(holder())},"quantification":"particular","context":frame.context}}),json!({"kind":"record_event","client_ref":event,"record":{"occurrence":occurrence(),"action":reference(action()),"time":{"kind":"exact","calendar":clock.calendar,"value":start},"worlds":worlds,"region":if region().is_empty(){Value::Null}else{reference(region())},"participants":[{"record":reference(item()),"role":"item"},{"record":reference(holder()),"role":"holder"}],"effects":[{"slot":"possession","proposition":reference(prop.to_string()),"polarity":polarity(),"validity":{"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":start},"end":end},"scope":scope,"order":0}],"labels":{"en":title()}}})];
                for op in &ops{serde_json::from_value::<DomainOperation>(op.clone()).map_err(|e|e.to_string())?;}
                Ok::<_,String>(ops)
            })();match result{Ok(ops)=>{onadd.call(ops);error.set(String::new());},Err(e)=>error.set(e)}
        }},"Add event and its effect to draft"}
        hr{}h3{"Power bestowed by this item"}p{"Use the item and holder property selected above. The chosen Boolean power is true only while established possession and this definition apply. Unknown or refuted possession does not grant it."}
        label{r#for:"event-power","Boolean power property"}super::select::RichSelect{id:"event-power",disabled,value:power(),options:powers,onchange:move|e:super::select::SelectionEvent|power.set(e.value())}
        label{r#for:"power-start","Power starts at the authored date or tick"}input{id:"power-start",disabled,value:power_start,oninput:move|e|power_start.set(e.value())}
        label{r#for:"power-end","Power duration"}super::select::RichSelect{id:"power-end",disabled,value:power_end(),options:vec![super::select::Choice::new("","Choose a duration"),super::select::Choice::described("persistent","No scheduled end","The power still requires established possession."),super::select::Choice::described("timer","Expires on a timer","The power expires independently of ownership; the holder keeps the item.")],onchange:move|e:super::select::SelectionEvent|power_end.set(e.value())}
        if power_end()=="timer"{label{r#for:"power-duration","Positive duration in this calendar’s ticks"}input{id:"power-duration",disabled,value:power_duration,oninput:move|e|power_duration.set(e.value())}}
        button{disabled,onclick:move|_|{
            let result=(||{let clock=clock.as_ref().ok_or("This context needs an authored clock.")?;if item().is_empty()||predicate().is_empty()||power().is_empty(){return Err("Choose item, holder property and Boolean power.".into());}
                let start=clock.coordinate(&power_start())?;
                let end=match power_end().as_str(){"persistent"=>json!({"kind":"unbounded"}),"timer"=>{let n=power_duration().parse::<i128>().map_err(|_|"Enter a positive whole-tick duration.")?;if n<=0{return Err("Duration must be positive.".into());}let end=start.parse::<i128>().map_err(|e|e.to_string())?.checked_add(n).ok_or("Power timer exceeds this clock’s range.")?;json!({"kind":"exact","value":end.to_string()})},_=>return Err("Choose how long the power lasts.".into())};
                let rr=|id:String|json!({"universe":frame.universe,"record":id});
                let applicability=if world().is_empty(){json!({"kind":"universe_wide"})}else{json!({"kind":"worlds","world_ids":[world()]})};
                let op=json!({"kind":"define_item_power","client_ref":RecordId::generate(&mut rand::rng()),"record":{"item":rr(item()),"holderPredicate":rr(predicate()),"powerPredicate":rr(power()),"value":{"kind":"boolean","value":true},"scope":{"context":frame.context,"applicability":applicability},"validity":{"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":start},"end":end}}});
                serde_json::from_value::<DomainOperation>(op.clone()).map_err(|e|e.to_string())?;Ok::<_,String>(op)
            })();match result{Ok(op)=>{onadd.call(vec![op]);error.set(String::new());},Err(e)=>error.set(e)}
        },"Add possession-dependent power to draft"}
        if !error().is_empty(){p{role:"alert","{error}"}}
    }}
}
