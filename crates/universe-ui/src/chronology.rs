//! Typed starting clock and explicit story-time transitions.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{
    chronology::{Chronology, TimeChangeKind, UniverseStart},
    ids::CalendarId,
};

#[component]
pub fn StartClock(onchange: EventHandler<Option<UniverseStart>>) -> Element {
    let mut kind = use_signal(String::new);
    let mut timestamp = use_signal(String::new);
    let mut name = use_signal(String::new);
    let mut unit = use_signal(String::new);
    let mut month = use_signal(String::new);
    let mut error = use_signal(String::new);
    use_effect(move || {
        let result = (|| {
            let start = match kind().as_str() {
                "gregorian" => UniverseStart::Gregorian {
                    timestamp: timestamp(),
                },
                "fictional" => UniverseStart::Fictional {
                    calendar_name: name(),
                    initial_tick: timestamp(),
                    tick_label: unit(),
                    ticks_per_month: if month().trim().is_empty() {
                        None
                    } else {
                        Some(month().parse().map_err(|_| {
                            "Month length must be a positive whole number.".to_string()
                        })?)
                    },
                },
                _ => return Err("Choose a calendar and provide the first interaction time.".into()),
            };
            start.build(CalendarId::parse("cal_000000000000000000000001").unwrap())?;
            Ok::<_, String>(start)
        })();
        match result {
            Ok(start) => {
                error.set(String::new());
                onchange.call(Some(start));
            }
            Err(e) => {
                error.set(e);
                onchange.call(None);
            }
        }
    });
    rsx! {fieldset{legend{"First fictional interaction"}
        p{"Set the story’s starting time. Opening the app, editing records and waiting do not advance it."}
        label{r#for:"start-calendar","Calendar"}super::select::RichSelect{id:"start-calendar",value:kind(),options:vec![super::select::Choice::new("","Choose a calendar"),super::select::Choice::described("gregorian","Gregorian","An authored date and time with an explicit offset; no real-time synchronization."),super::select::Choice::described("fictional","Fictional calendar","Name the clock and its integer tick unit; month length is optional and explicit.")],onchange:move|e:super::select::SelectionEvent|{kind.set(e.value());timestamp.set(String::new());}}
        if kind()=="fictional"{
            label{r#for:"start-clock-name","Calendar name"}input{id:"start-clock-name",value:name,oninput:move|e|name.set(e.value())}
            label{r#for:"start-clock-unit","Tick unit, such as days or cycles"}input{id:"start-clock-unit",value:unit,oninput:move|e|unit.set(e.value())}
            label{r#for:"start-clock-month","Ticks per month (leave blank if not defined)"}input{id:"start-clock-month",value:month,oninput:move|e|month.set(e.value())}
        }
        label{r#for:"start-clock-time","Author-provided first interaction timestamp"}input{id:"start-clock-time",value:timestamp,placeholder:if kind()=="gregorian"{"2042-06-01T12:00:00+00:00"}else{"Exact fictional coordinate"},oninput:move|e|timestamp.set(e.value())}
        if !error().is_empty(){p{class:"hint","{error}"}}
    }}
}
#[component]
pub fn StoryClock(record: Value, disabled: bool, onadd: EventHandler<Value>) -> Element {
    let Ok(clock) = serde_json::from_value::<Chronology>(record["payload"]["chronology"].clone())
    else {
        return rsx! {p{"This older context has no authored first-interaction clock. No current fictional date is inferred."}};
    };
    let mut next = use_signal(String::new);
    let mut mode = use_signal(String::new);
    let mut reason = use_signal(String::new);
    let mut error = use_signal(String::new);
    let mut months = use_signal(String::new);
    let mut relative = use_signal(String::new);
    let current = clock.display(&clock.current).unwrap_or_else(|e| e);
    let first = clock
        .display(&clock.first_interaction)
        .unwrap_or_else(|e| e);
    rsx! {section{class:"panel","aria-label":"Story clock",h2{"Story time"}p{strong{"Current authored time: "}"{current}"}p{"First interaction: {first}"}
        p{"This date belongs to the pinned revision. Time moves only through a reviewed change. Timed attributes use the chosen clock; other world clocks are not synchronized implicitly."}
        details{summary{"Propose a change of story time"}
            label{r#for:"clock-mode","Transition"}super::select::RichSelect{id:"clock-mode",disabled,value:mode(),options:vec![super::select::Choice::new("","Choose explicitly"),super::select::Choice::described("elapsed","Elapsed story time","Explicit forward passage with an authored explanation."),super::select::Choice::described("time_travel","Time travel","An explicit jump, forward or backward, with an authored explanation.")],onchange:move|e:super::select::SelectionEvent|mode.set(e.value())}
            label{r#for:"clock-next","New fictional timestamp"}input{id:"clock-next",disabled,value:next,oninput:move|e|next.set(e.value())}
            label{r#for:"clock-reason","What accounts for this transition?"}textarea{id:"clock-reason",disabled,value:reason,oninput:move|e|reason.set(e.value())}
            button{disabled,onclick:{let clock=clock.clone();move|_|{
                let kind=match mode().as_str(){"elapsed"=>TimeChangeKind::Elapsed,"time_travel"=>TimeChangeKind::TimeTravel,_=>{error.set("Choose elapsed time or time travel.".into());return;}};
                let mut candidate=clock.clone();match candidate.change(&next(),kind,&reason()){
                    Ok(())=>{onadd.call(json!({"kind":"set_story_time","record":{"universe":record["identity"]["universe_id"],"record":record["identity"]["record_id"]},"expected_version":record["record_version_id"],"value":next(),"mode":kind,"reason":reason()}));error.set(String::new());},Err(e)=>error.set(e)
                }
            }},"Add time transition to draft"}
            if !error().is_empty(){p{role:"alert","{error}"}}
        }
        details{summary{"Resolve “N months ago”"}p{"Measured from the current authored time. This preview does not advance time or create an event."}
            label{r#for:"clock-month-offset","Number of months"}input{id:"clock-month-offset",value:months,oninput:move|e|months.set(e.value())}
            button{onclick:move|_|{let result=months().parse::<u32>().map_err(|_|"Enter a nonnegative whole number.".to_string()).and_then(|n|clock.months_ago(&clock.current,n)).and_then(|v|clock.display(&v));relative.set(result.unwrap_or_else(|e|e));},"Resolve date"}p{role:"status","{relative}"}
        }
    }}
}
