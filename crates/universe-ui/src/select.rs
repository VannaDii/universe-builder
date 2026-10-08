//! Accessible, filterable choices with visible help; values remain typed at call sites.
use dioxus::prelude::*;
#[derive(Clone, PartialEq)]
pub struct Choice {
    pub value: String,
    pub label: String,
    pub description: String,
}
impl Choice {
    pub fn new(value: impl Into<String>, label: impl Into<String>) -> Self {
        let value = value.into();
        let label = label.into();
        let description = help(&value).unwrap_or("Select this existing value.").into();
        Self {
            value,
            label,
            description,
        }
    }
    pub fn described(
        value: impl Into<String>,
        label: impl Into<String>,
        description: impl Into<String>,
    ) -> Self {
        Self {
            value: value.into(),
            label: label.into(),
            description: description.into(),
        }
    }
}
pub fn choices(items: &[(&str, &str)]) -> Vec<Choice> {
    items.iter().map(|(v, l)| Choice::new(*v, *l)).collect()
}
pub fn namespace_choices(records: &[serde_json::Value], operations: &str) -> Vec<Choice> {
    let mut grouped = std::collections::BTreeMap::<String, Vec<String>>::new();
    let draft = serde_json::from_str::<Vec<serde_json::Value>>(operations).unwrap_or_default();
    for data in records
        .iter()
        .map(|r| &r["payload"])
        .chain(draft.iter().map(|op| {
            if op["kind"] == "introduce_definition" {
                op
            } else {
                &op["record"]
            }
        }))
    {
        if let Some(namespace) = data["namespace"].as_str().filter(|n| !n.trim().is_empty()) {
            let name = data["labels"]["en"]
                .as_str()
                .or_else(|| data["name"].as_str())
                .or_else(|| data["key"].as_str())
                .unwrap_or("Definition");
            let labels = grouped.entry(namespace.into()).or_default();
            if !labels.iter().any(|v| v == name) {
                labels.push(name.into());
            }
        }
    }
    grouped
        .into_iter()
        .map(|(namespace, labels)| {
            Choice::described(
                namespace.clone(),
                namespace,
                format!(
                    "Existing group · {}",
                    labels.into_iter().take(3).collect::<Vec<_>>().join(", ")
                ),
            )
        })
        .collect()
}
pub fn typed_id_choices(
    records: &[serde_json::Value],
    kind: &str,
    prefix: &str,
    prompt: &str,
) -> Vec<Choice> {
    record_choices(records, &[kind], prompt)
        .into_iter()
        .map(|mut c| {
            if !c.value.is_empty() {
                c.value = c.value.replacen("rec_", prefix, 1);
            }
            c
        })
        .collect()
}
pub fn record_choices(records: &[serde_json::Value], kinds: &[&str], prompt: &str) -> Vec<Choice> {
    std::iter::once(Choice::new("", prompt))
        .chain(
            records
                .iter()
                .filter(|r| kinds.contains(&r["kind"].as_str().unwrap_or_default()))
                .map(|r| {
                    let kind = r["kind"].as_str().unwrap_or_default();
                    let id = r["record_id"].as_str().unwrap_or_default();
                    Choice::described(
                        id,
                        r["label"].as_str().unwrap_or(id),
                        help(kind)
                            .unwrap_or("An existing record in this pinned universe revision."),
                    )
                }),
        )
        .collect()
}
#[derive(Clone)]
pub struct SelectionEvent(String);
impl SelectionEvent {
    pub fn value(&self) -> String {
        self.0.clone()
    }
}
fn help(value: &str) -> Option<&'static str> {
    Some(match value {
        "" => "No selection. Choose deliberately; nothing is inferred.",
        "add_name" => "Keep the existing name and add another authored name.",
        "refine_classification" => "Set the first classification or narrow it to a descendant while keeping the instance identity.",
        "rename_world_selector" => "Use a new display name while retaining the prior alias.",
        "add_world_alias" => "Add an alternative lookup name for the same world.",
        "end_assertion_at" => "Keep earlier validity and exclude this moment and later times.",
        "retract_assertion" => {
            "Remove this evidence from the new revision; preserve past revisions."
        }
        "timer" => "Choose an explicit start and positive duration in the calendar’s ticks.",
        "entity" => "A character, object or place with one identity across worlds.",
        "world" => "A named setting within this universe, with its own declared clock.",
        "work" => "A story or other narrative that may depict several worlds.",
        "work_version" => "A named version of a work with an explicit canon binding.",
        "saga" => "A collection of works with authored roles and ordering.",
        "type" | "entity_type" => {
            "A reusable classification for entities; inheritance is explicit."
        }
        "property" => "A named value on an entity, with an explicit shape and multiplicity.",
        "relation" | "relationship" => {
            "Named roles connect participants without implying inverse effects."
        }
        "unit" => "An authored measurement unit; compatible conversion must be defined.",
        "calendar" => {
            "A named fictional clock; separate calendars are not automatically comparable."
        }
        "text" => "Authored wording preserved exactly, including Unicode.",
        "integer" => "An exact whole number, preserved without floating-point rounding.",
        "decimal" => "An exact decimal; a blank value is not zero.",
        "rational" => "An exact numerator and nonzero denominator.",
        "boolean" => "Choose true or false explicitly; absence is neither.",
        "entity_ref" => "Refer to one existing entity identity.",
        "temporal" => "A value in an explicitly named fictional calendar.",
        "quantity" => "An exact amount attached to a defined measurement unit.",
        "range" => "Authored lower and upper bounds, with explicit inclusivity.",
        "exact" => "An exact authored value; no uncertainty is implied.",
        "approximate" => "Qualified evidence that must not be treated as exact.",
        "one_of" => "Several possible values; none is silently chosen as fact.",
        "unresolved" => "The value has not been established.",
        "unknown" => "There is a time or boundary, but its value is unknown.",
        "unspecified" => "No claim has been made about this dimension.",
        "unbounded" => "The author explicitly declares no boundary in this direction.",
        "instant" => "A single moment in a named fictional calendar.",
        "interval" => "A validity interval; exact starts are included and ends excluded.",
        "inclusive" => "The boundary value is included.",
        "exclusive" => "The boundary value is excluded.",
        "support" => "Evidence supports the proposition; opposing evidence is retained.",
        "refutation" => "Explicit evidence against the proposition, not missing data.",
        "universe_wide" => "Applies throughout this universe, including shared records.",
        "worlds" => "Applies only to the explicitly selected worlds.",
        "single" => "At most one simultaneous value per subject in the same scope.",
        "multiple" => "Several values may coexist; exclusivity is not implied.",
        "shared" => "One identity explicitly associated with more than one world.",
        "unassigned" => "No world association is declared, or the record is universe wide.",
        "clone" => "Create a new universe identity and remap local references.",
        "restore" => "Keep original identities and reject any existing identity conflict.",
        "current" => "Bind to the exact continuity and revision currently open.",
        "unbound" => "Keep the work version explicitly unbound or under review.",
        "true" => "An explicit positive Boolean value.",
        "false" => "An explicit negative Boolean value; never inferred from absence.",
        "novel" => "A long-form narrative work.",
        "story" => "A short narrative work.",
        "series_chapter" => "A chapter belonging to a larger narrative series.",
        "play" => "A narrative written for performance.",
        "film" => "A screen narrative work.",
        "other" => "Another authored work kind without inferred semantics.",
        _ => return None,
    })
}
fn filtered_choices(options: &[Choice], query: &str, allow_new: bool) -> Vec<Choice> {
    let q = query.trim().to_lowercase();
    let mut matches: Vec<_> = options
        .iter()
        .filter(|c| {
            q.is_empty()
                || c.label.to_lowercase().contains(&q)
                || c.value.to_lowercase().contains(&q)
                || c.description.to_lowercase().contains(&q)
        })
        .cloned()
        .collect();
    if allow_new && !q.is_empty() && !options.iter().any(|c| c.value.trim().to_lowercase() == q) {
        matches.push(Choice::described(
            query.trim(),
            format!("Create “{}”", query.trim()),
            "Use a new value only when none of the existing choices fits.",
        ));
    }
    matches
}
#[component]
pub fn RichSelect(
    id: String,
    value: String,
    #[props(default)] disabled: bool,
    options: Vec<Choice>,
    #[props(default)] allow_new: bool,
    onchange: EventHandler<SelectionEvent>,
) -> Element {
    let mut open = use_signal(|| false);
    let mut query = use_signal(String::new);
    let mut active = use_signal(|| 0usize);
    let selected = options
        .iter()
        .find(|c| c.value == value)
        .map(|c| c.label.clone())
        .unwrap_or_else(|| {
            if value.is_empty() {
                "Choose a value".into()
            } else {
                value.clone()
            }
        });
    let matches = filtered_choices(&options, &query(), allow_new);
    let chosen = matches
        .get(active().min(matches.len().saturating_sub(1)))
        .cloned();
    let list_id = format!("{id}-options");
    let search_id = format!("{id}-search");
    let focus_id = id.clone();
    let close_id = id.clone();
    let close = move |_| {
        open.set(false);
        let id = serde_json::to_string(&close_id).unwrap();
        let _ = document::eval(&format!(
            "requestAnimationFrame(()=>document.getElementById({id})?.focus())"
        ));
    };
    let choose = move |choice: Choice| {
        onchange.call(SelectionEvent(choice.value));
        open.set(false);
        query.set(String::new());
        let id = serde_json::to_string(&focus_id).unwrap();
        let _ = document::eval(&format!(
            "requestAnimationFrame(()=>document.getElementById({id})?.focus())"
        ));
    };
    rsx! {div{class:"rich-select",
        button{id:id.clone(),r#type:"button",class:"rich-trigger",disabled,"aria-haspopup":"listbox","aria-expanded":open(),"aria-controls":list_id.clone(),onclick:move|_|{open.set(!open());query.set(String::new());active.set(0);},onkeydown:move|e|{if matches!(e.key(),Key::ArrowDown|Key::ArrowUp){e.prevent_default();open.set(true);active.set(0);}},span{"{selected}"}span{"aria-hidden":"true","⌄"}}
        if open()&&!disabled{div{class:"rich-popover",
            input{id:search_id,r#type:"search",role:"combobox","aria-label":format!("Search {}",super::readable::caption(&id)),"aria-expanded":"true","aria-controls":list_id.clone(),"aria-autocomplete":"list","aria-activedescendant":if matches.is_empty(){String::new()}else{format!("{id}-choice-{}",active().min(matches.len()-1))},placeholder:if allow_new{"Find an existing value or enter a new one"}else{"Find a choice"},value:query,oninput:move|e|{query.set(e.value());active.set(0);},onmounted:move|e|{spawn(async move{let _=e.set_focus(true).await;});},onkeydown:{let chosen=chosen.clone();let count=matches.len();let mut choose=choose.clone();let mut close=close.clone();move|e|match e.key(){Key::ArrowDown=>{e.prevent_default();active.set((active()+1).min(count.saturating_sub(1)));},Key::ArrowUp=>{e.prevent_default();active.set(active().saturating_sub(1));},Key::Enter=>{e.prevent_default();if let Some(c)=chosen.clone(){choose(c);}},Key::Escape=>{e.prevent_default();close(());},_=>{}}}}
            ul{id:list_id.clone(),role:"listbox","aria-label":format!("Choices for {}",super::readable::caption(&id)),
                for(i,choice)in matches.clone().into_iter().enumerate(){li{key:"{choice.value}",role:"presentation",button{id:format!("{id}-choice-{i}"),r#type:"button",role:"option",class:if active()==i{"rich-choice active"}else{"rich-choice"},"aria-selected":choice.value==value,onclick:{let mut choose=choose.clone();let choice=choice.clone();move|_|choose(choice.clone())},strong{"{choice.label}"}small{"{choice.description}"}}}}
                if chosen.is_none(){li{class:"rich-empty","No matching choices. Try a different search."}}
            }
            button{r#type:"button",class:"secondary",onclick:{let mut close=close.clone();move|_|close(())},"Close choices"}
        }}
    }}
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn namespace_search_reuses_existing_spelling_and_requires_explicit_creation() {
        let items = vec![
            Choice::described("Magic", "Magic", "Items, powers and enchantments"),
            Choice::described("places", "Places", "Regions and settlements"),
        ];
        let existing = filtered_choices(&items, "  MAGIC  ", true);
        assert_eq!(existing.len(), 1);
        assert_eq!(existing[0].value, "Magic");
        assert_eq!(
            filtered_choices(&items, "enchantment", false)[0].value,
            "Magic"
        );
        let similar = filtered_choices(&items, "Magi", true);
        assert_eq!(similar.len(), 2);
        assert_eq!(similar[0].value, "Magic");
        assert_eq!(similar[1].value, "Magi");
        assert!(filtered_choices(&items, "new", false).is_empty());
        assert_eq!(filtered_choices(&items, "   ", true).len(), 2);
    }
    #[test]
    fn namespace_suggestions_include_pinned_definitions_and_pending_drafts() {
        let records = vec![
            json!({"payload":{"record_kind":"property","namespace":"magic","key":"power","labels":{"en":"Granted powers"}}}),
            json!({"payload":{"record_kind":"property","namespace":"places","key":"region"}}),
        ];
        let draft=json!([{"record":{"namespace":"magic","key":"owner"}},{"record":{"namespace":"myth","key":"origin"}},{"kind":"introduce_definition","namespace":"magic","key":"device","name":"Device"}]).to_string();
        let items = namespace_choices(&records, &draft);
        assert_eq!(items.len(), 3);
        assert!(items[0].description.contains("Granted powers"));
        assert!(items[0].description.contains("owner"));
        assert!(items[0].description.contains("Device"));
        assert_eq!(items[1].value, "myth");
    }
}
