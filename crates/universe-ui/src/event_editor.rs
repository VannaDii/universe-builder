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
    rsx! {
        super::action_editor::ActionEditor{frame:frame.clone(),choices:choices.clone(),disabled,onadd:move|op:Value|onadd.call(vec![op])}
        super::consequence_event::ConsequenceEventEditor{frame:frame.clone(),clock:clock.clone(),choices:choices.clone(),disabled,onadd}
        ItemPowerEditor{frame,clock,choices,disabled,onadd}
    }
}
#[derive(Default)]
pub(super) struct PowerForm {
    pub item: String,
    pub holder: String,
    pub power: String,
    pub world: String,
    pub start: String,
    pub duration: String,
    pub ticks: String,
    pub value: super::claim_editor::Form,
}
impl PowerForm {
    pub(super) fn build(&self, frame: &Frame, clock: Option<&Chronology>) -> Result<Value, String> {
        let clock = clock.ok_or("This context needs an authored clock.")?;
        if self.item.is_empty() || self.holder.is_empty() || self.power.is_empty() {
            return Err("Choose item, holder property and power property.".into());
        }
        let start = clock.coordinate(&self.start)?;
        let end = match self.duration.as_str() {
            "persistent" => json!({"kind":"unbounded"}),
            "timer" => {
                let n = self
                    .ticks
                    .parse::<i128>()
                    .map_err(|_| "Enter a positive whole-tick duration.")?;
                if n <= 0 {
                    return Err("Duration must be positive.".into());
                }
                let end = start
                    .parse::<i128>()
                    .map_err(|e| e.to_string())?
                    .checked_add(n)
                    .ok_or("Power timer exceeds this clock’s range.")?;
                json!({"kind":"exact","value":end.to_string()})
            }
            _ => return Err("Choose how long the power lasts.".into()),
        };
        if ![
            "boolean",
            "text",
            "integer",
            "decimal",
            "entity_ref",
            "quantity",
        ]
        .contains(&self.value.kind.as_str())
        {
            return Err("Choose a supported power property value.".into());
        }
        let value = self.value.typed_value(frame, Some(clock))?;
        let rr = |id: &str| json!({"universe":frame.universe,"record":id});
        let applicability = if self.world.is_empty() {
            json!({"kind":"universe_wide"})
        } else {
            json!({"kind":"worlds","world_ids":[self.world]})
        };
        let op = json!({"kind":"define_item_power","client_ref":RecordId::generate(&mut rand::rng()),"record":{"item":rr(&self.item),"holderPredicate":rr(&self.holder),"powerPredicate":rr(&self.power),"value":value,"scope":{"context":frame.context,"applicability":applicability},"validity":{"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":start},"end":end}}});
        serde_json::from_value::<DomainOperation>(op.clone()).map_err(|e| e.to_string())?;
        Ok(op)
    }
}
#[component]
fn ItemPowerEditor(
    frame: Frame,
    clock: Option<Chronology>,
    choices: Vec<Value>,
    disabled: bool,
    onadd: EventHandler<Vec<Value>>,
) -> Element {
    let mut item = use_signal(String::new);
    let mut predicate = use_signal(String::new);
    let mut power = use_signal(String::new);
    let mut world = use_signal(String::new);
    let mut power_start = use_signal(String::new);
    let mut power_end = use_signal(String::new);
    let mut power_duration = use_signal(String::new);
    let mut error = use_signal(String::new);
    let mut grant = use_signal(super::claim_editor::Form::default);
    let holder_properties: Vec<_> = choices
        .iter()
        .filter(|c| {
            c["kind"] == "property"
                && c["definition"]["value"]["kind"] == "entity_ref"
                && c["definition"]["multiplicity"] == "single"
        })
        .cloned()
        .collect();
    let value_properties: Vec<_> = choices
        .iter()
        .filter(|c| {
            c["kind"] == "property"
                && [
                    "boolean",
                    "text",
                    "integer",
                    "decimal",
                    "entity_ref",
                    "quantity",
                ]
                .contains(&c["definition"]["value"]["kind"].as_str().unwrap_or(""))
        })
        .cloned()
        .collect();
    let powers =
        super::select::record_choices(&value_properties, &["property"], "Choose a power property");
    rsx! {details{summary{"Define a possession-dependent item power"}
        label{r#for:"power-item","Item"}super::select::RichSelect{id:"power-item",disabled,value:item(),options:super::select::record_choices(&choices,&["entity"],"Choose an item"),onchange:move|e:super::select::SelectionEvent|item.set(e.value())}
        label{r#for:"power-holder-property","Holder property"}super::select::RichSelect{id:"power-holder-property",disabled,value:predicate(),options:super::select::record_choices(&holder_properties,&["property"],"Choose a single holder property"),onchange:move|e:super::select::SelectionEvent|predicate.set(e.value())}
        label{r#for:"power-world","World (blank means universe wide)"}super::select::RichSelect{id:"power-world",disabled,value:world(),options:super::select::typed_id_choices(&choices,"world","wld_","Universe wide"),onchange:move|e:super::select::SelectionEvent|world.set(e.value())}
        hr{}h3{"Power bestowed by this item"}p{"Select the item and its holder property. The explicit value applies only while the item’s declared holder property establishes possession and this definition applies. Ownership relationships do not supply possession. Unknown or refuted possession does not grant it."}
        label{r#for:"event-power","Power property"}super::select::RichSelect{id:"event-power",disabled,value:power(),options:powers,onchange:move|e:super::select::SelectionEvent|{let id=e.value();let row=value_properties.iter().find(|c|c["record_id"]==id);grant.set(super::claim_editor::Form{kind:row.and_then(|c|c["definition"]["value"]["kind"].as_str()).unwrap_or("").into(),unit:row.and_then(|c|c["definition"]["value"]["unit"].as_str()).unwrap_or("").into(),..Default::default()});power.set(id);}}

        if grant.read().kind=="boolean"{
            label{r#for:"power-value","Granted value"}super::select::RichSelect{id:"power-value",disabled,value:grant.read().value.clone(),options:super::select::choices(&[("","Choose explicitly"),("true","True"),("false","False")]),onchange:move|e:super::select::SelectionEvent|grant.write().value=e.value()}
        }else if grant.read().kind=="entity_ref"{
            label{r#for:"power-value","Granted object"}super::select::RichSelect{id:"power-value",disabled,value:grant.read().value.clone(),options:super::select::record_choices(&choices,&["entity"],"Choose object"),onchange:move|e:super::select::SelectionEvent|grant.write().value=e.value()}
        }else if !grant.read().kind.is_empty(){
            label{r#for:"power-value","Granted value"}input{id:"power-value",disabled,value:grant.read().value.clone(),oninput:move|e|grant.write().value=e.value()}
            if grant.read().kind=="quantity"{p{"Uses the power property’s authored unit; no conversion is inferred."}}
        }
        label{r#for:"power-start","Power starts at the authored date or tick"}input{id:"power-start",disabled,value:power_start,oninput:move|e|power_start.set(e.value())}
        label{r#for:"power-end","Power duration"}super::select::RichSelect{id:"power-end",disabled,value:power_end(),options:vec![super::select::Choice::new("","Choose a duration"),super::select::Choice::described("persistent","No scheduled end","The power still requires established possession."),super::select::Choice::described("timer","Expires on a timer","The power expires independently of ownership; the holder keeps the item.")],onchange:move|e:super::select::SelectionEvent|power_end.set(e.value())}
        if power_end()=="timer"{label{r#for:"power-duration","Positive duration in this calendar’s ticks"}input{id:"power-duration",disabled,value:power_duration,oninput:move|e|power_duration.set(e.value())}}
        button{disabled,onclick:move|_|{
            let result=PowerForm{item:item(),holder:predicate(),power:power(),world:world(),start:power_start(),duration:power_end(),ticks:power_duration(),value:grant()}.build(&frame,clock.as_ref());match result{Ok(op)=>{onadd.call(vec![op]);error.set(String::new());},Err(e)=>error.set(e)}
        },"Add possession-dependent power to draft"}
        if !error().is_empty(){p{role:"alert","{error}"}}
    }}
}
