//! Typed finite policy forms; authors never edit an expression or JSON document.
use super::select::{Choice, RichSelect, SelectionEvent};
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{chronology::Chronology, ids::RecordId, records::DomainOperation, Frame};
#[path = "factual_policy.rs"]
mod factual;
#[component]
pub fn PolicyEditor(
    frame: Frame,
    clock: Option<Chronology>,
    choices: Vec<Value>,
    namespaces: Vec<Choice>,
    disabled: bool,
    onadd: EventHandler<Value>,
) -> Element {
    let mut mode = use_signal(|| "rule".to_owned());
    let mut namespace = use_signal(String::new);
    let mut key = use_signal(String::new);
    let mut subject = use_signal(String::new);
    let mut predicate = use_signal(String::new);
    let mut kind = use_signal(String::new);
    let mut expected = use_signal(String::new);
    let mut world = use_signal(String::new);
    let mut period = use_signal(String::new);
    let mut start = use_signal(String::new);
    let mut end = use_signal(String::new);
    let mut member = use_signal(String::new);
    let mut members = use_signal(Vec::<String>::new);
    let mut empty = use_signal(|| false);
    let mut status = use_signal(String::new);
    let properties: Vec<_> = choices
        .iter()
        .filter(|r| {
            r["kind"] == "property"
                && if mode() == "rule" {
                    r["definition"]["value"]["kind"] == "boolean"
                } else {
                    r["definition"]["value"]["kind"] == "entity_ref"
                }
        })
        .cloned()
        .collect();
    rsx! {details{class:"panel",summary{"Factual policies, rules, protected areas and complete sets"}
        p{"Choose an explicit finite constraint. Laws and typical behavior produce findings; physical requirements can block publication. Unknown or unsupported evaluation never becomes a successful check."}
        label{r#for:"policy-mode","Definition"}RichSelect{id:"policy-mode",disabled,value:mode(),options:vec![Choice::described("rule","Boolean property rule","Require a selected property of one subject to be true or false."),Choice::described("boundary","Creative boundary","Protect additions and edits concerning one record."),Choice::described("complete","Complete membership set","Explicitly close one subject’s entity-reference collection in this scope and time."),Choice::described("chronology","Communication chronology","Opt in to authored channel order and delay bounds."),Choice::described("knowledge","Knowledge basis","Choose how knowledge is established in a truth context."),Choice::described("cardinality","Maximum relation participants","Count distinct participants across overlapping supported relation instances.")],onchange:move|e:SelectionEvent|{mode.set(e.value());kind.set(String::new());predicate.set(String::new());}}
        if ["chronology","knowledge","cardinality"].contains(&mode().as_str()) {
            factual::FactualPolicy{mode:mode(),frame,clock,choices,namespaces,disabled,onadd}
        } else {
        label{r#for:"policy-subject","Subject"}RichSelect{id:"policy-subject",disabled,value:subject(),options:super::select::record_choices(&choices,&["entity"],"Choose the subject"),onchange:move|e:SelectionEvent|subject.set(e.value())}
        if mode()!="complete" {
            label{r#for:"policy-namespace","Namespace"}RichSelect{id:"policy-namespace",disabled,value:namespace(),options:namespaces,allow_new:true,onchange:move|e:SelectionEvent|namespace.set(e.value())}
            label{r#for:"policy-key","Definition name"}input{id:"policy-key",disabled,value:key,oninput:move|e|key.set(e.value())}
        }
        if mode()!="boundary" {label{r#for:"policy-property","Property"}RichSelect{id:"policy-property",disabled,value:predicate(),options:super::select::record_choices(&properties,&["property"],"Choose a compatible property"),onchange:move|e:SelectionEvent|predicate.set(e.value())}}
        if mode()=="rule" {
            label{r#for:"policy-kind","Meaning"}RichSelect{id:"policy-kind",disabled,value:kind(),options:vec![Choice::new("","Choose rule meaning"),Choice::described("physical_constraint","Physical constraint","Blocks unless its evidence holds or an exact author exception applies."),Choice::described("operational_requirement","Operational requirement","Records an unfulfilled prerequisite as a finding."),Choice::described("law","Law or norm","Violation can occur; no punishment is automatically invented."),Choice::described("behavioral_tendency","Typical behavior","Advisory; an individual can depart from the tendency.")],onchange:move|e:SelectionEvent|kind.set(e.value())}
            label{r#for:"policy-expected","Required property value"}RichSelect{id:"policy-expected",disabled,value:expected(),options:vec![Choice::new("","Choose explicitly"),Choice::described("true","True","Require positive evidence for the property being true."),Choice::described("false","False","Require positive evidence for the property being false; missing is insufficient.")],onchange:move|e:SelectionEvent|expected.set(e.value())}
        }
        if mode()=="boundary" {label{r#for:"policy-boundary","Permission for new material"}RichSelect{id:"policy-boundary",disabled,value:kind(),options:vec![Choice::new("","Choose a boundary"),Choice::described("fixed","Fixed","An explicit exception or boundary revision is needed for changes."),Choice::described("proposal_required","Proposal required","New material follows the normal validation and author review."),Choice::described("author_reserved","Author reserved","Only author-originated changes may proceed."),Choice::described("intentionally_unresolved","Intentionally unanswered","Protect an unanswered question without inventing an objective answer."),Choice::described("prohibited","Prohibited","Block changes unless an exact authorized exception applies.")],onchange:move|e:SelectionEvent|kind.set(e.value())}}
        if mode()=="complete" {
            label{r#for:"policy-member","Member"}RichSelect{id:"policy-member",disabled,value:member(),options:super::select::record_choices(&choices,&["entity"],"Choose an existing member"),onchange:move|e:SelectionEvent|member.set(e.value())}
            button{disabled:disabled||member().is_empty(),onclick:move|_|{let v=member();if !members().contains(&v){members.write().push(v);}empty.set(false);},"Include member"}
            for id in members(){div{span{"{id}"}button{disabled,onclick:move|_|members.write().retain(|v|v!=&id),"Remove member"}}}
            label{class:"check-label",input{r#type:"checkbox",disabled:disabled||!members().is_empty(),checked:empty,onchange:move|e|empty.set(e.checked())}"This collection is explicitly empty"}
        }
        label{r#for:"policy-world","Applicability"}RichSelect{id:"policy-world",disabled,value:world(),options:std::iter::once(Choice::described("","Explicitly universe-wide","Applies in each world; it does not synchronize their clocks.")).chain(super::select::typed_id_choices(&choices,"world","wld_","Choose world").into_iter().filter(|c|!c.value.is_empty())).collect(),onchange:move|e:SelectionEvent|world.set(e.value())}
        label{r#for:"policy-period","Validity"}RichSelect{id:"policy-period",disabled,value:period(),options:vec![Choice::new("","Choose validity"),Choice::described("unspecified","No temporal claim","Use only with evidence that has no temporal claim."),Choice::described("interval","An authored interval","Exact start and exclusive end on the context’s calendar.")],onchange:move|e:SelectionEvent|period.set(e.value())}
        if period()=="interval" {label{r#for:"policy-start","Start date or tick"}input{id:"policy-start",disabled,value:start,oninput:move|e|start.set(e.value())}label{r#for:"policy-end","Exclusive end date or tick"}input{id:"policy-end",disabled,value:end,oninput:move|e|end.set(e.value())}}
        button{disabled,onclick:move|_|{
            let result=(||{
                if subject().is_empty(){return Err("Choose the subject.".to_owned());}
                let rr=|id:String|json!({"universe":frame.universe,"record":id});
                let applicability=if world().is_empty(){json!({"kind":"universe_wide"})}else{json!({"kind":"worlds","world_ids":[world()]})};
                let scope=json!({"applicability":applicability,"context":frame.context});
                let validity=match period().as_str(){"unspecified"=>json!({"kind":"unspecified"}),"interval"=>{let clock=clock.as_ref().ok_or("An authored calendar is required.")?;let a=clock.coordinate(&start())?;let b=clock.coordinate(&end())?;if a.parse::<i128>().map_err(|e|e.to_string())?>=b.parse::<i128>().map_err(|e|e.to_string())?{return Err("The end must follow the start.".into());}json!({"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":a},"end":{"kind":"exact","value":b}})},_=>return Err("Choose validity explicitly.".into())};
                let id=RecordId::generate(&mut rand::rng());
                let op=if mode()=="boundary" {
                    if key().trim().is_empty()||namespace().trim().is_empty()||kind().is_empty(){return Err("Name the boundary and choose its mode.".into());}
                    json!({"kind":"set_creative_boundary","client_ref":id,"record":{"key":format!("{}:{}",namespace(),key()),"area":{"kind":"record","universe":frame.universe,"record":subject()},"mode":kind(),"constraints":[],"scope":scope,"validity":validity}})
                }else{
                    let property=properties.iter().find(|r|r["record_id"]==predicate()).ok_or("Choose a compatible property.")?;let p=&property["definition"];let name=format!("{}:{}",p["namespace"].as_str().unwrap_or_default(),p["key"].as_str().unwrap_or_default());
                    if mode()=="complete" {if members().is_empty()&&!empty(){return Err("Include members or explicitly confirm an empty collection.".into());}json!({"kind":"set_completeness","client_ref":id,"record":{"subject":rr(subject()),"predicate":name,"members":members().into_iter().map(&rr).collect::<Vec<_>>(),"completeness":"objective_reality","scope":scope,"validity":validity}})}else{
                        if namespace().trim().is_empty()||key().trim().is_empty()||kind().is_empty()||expected().is_empty(){return Err("Name the rule, choose its meaning and required value.".into());}
                        let policy=match kind().as_str(){"physical_constraint"=>"block_unless_exception","behavioral_tendency"=>"advisory",_=>"record_finding"};
                        json!({"kind":"define_rule","client_ref":id,"record":{"namespace":namespace(),"key":key(),"labels":{"en":key()},"kind":kind(),"commitPolicy":policy,"applicability":applicability,"targetPredicates":[name],"expression":{"kind":"claim","subject":{"kind":"record","ref":rr(subject())},"predicate":name,"roles":[],"value":{"kind":"value","value":{"kind":"boolean","value":expected()=="true"}},"polarity":"support","context":{"kind":"record","ref":frame.context}},"capabilities":["basic.v1"],"executable":true,"validity":validity}})
                    }
                };serde_json::from_value::<DomainOperation>(op.clone()).map_err(|e|e.to_string())?;Ok::<_,String>(op)
            })();match result{Ok(op)=>{onadd.call(op);status.set("Definition added to draft for validation and review.".into());},Err(e)=>status.set(e)}
        },"Add definition to draft"}
        p{role:"status","{status}"}
        }
    }}
}
