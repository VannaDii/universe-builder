//! Explicit authored contexts; parentage is structure, never inherited truth.
use super::*;
use universe_protocol::writing::{CheckChanges, WritingCheck};

pub(super) fn named_context(rows: &[RecordVersion], name: &str) -> Option<RecordId> {
    let matches:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::RepresentedContext(c) if r.identity.record_id.as_str()==name || c.labels.values().any(|n|n==name) || matches!(&c.kind,RepresentedContextKind::Authored{label}if label==name))).collect();
    let [row] = matches.as_slice() else {
        return None;
    };
    Some(row.identity.record_id.clone())
}
impl Workflow<'_> {
    pub(super) fn writing_story_contexts(
        &self,
        input: &CheckChanges,
        ctx: &Context,
        rows: &[RecordVersion],
        operations: &mut Vec<Value>,
        result: &mut WritingCheck,
    ) -> anyhow::Result<()> {
        let mut introduced = BTreeSet::new();
        for context in &input.story_contexts {
            let built = (|| -> anyhow::Result<Option<Value>> {
                if context.name.trim().is_empty() {
                    anyhow::bail!("Name the authored context explicitly.");
                }
                if named_context(rows, &context.name).is_some() {
                    return Ok(None);
                }
                if rows.iter().any(|r|matches!(&r.payload,Payload::RepresentedContext(c)if c.labels.values().any(|n|n==&context.name)||matches!(&c.kind,RepresentedContextKind::Authored{label}if label==&context.name))) {anyhow::bail!("Select one accessible authored context; this name is ambiguous.");}
                if !context.introduce || self.scope.is_some() {
                    anyhow::bail!("Select an accessible context or explicitly introduce it with universe-wide authoring access.");
                }
                if !introduced.insert(&context.name) {
                    anyhow::bail!("Declare each new context once per delta.");
                }
                let parent = named_context(rows, &context.parent).ok_or_else(|| {
                    anyhow::anyhow!("Select one accessible parent context explicitly.")
                })?;
                let calendars:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::Calendar(c)if c.key==context.calendar||c.labels.values().any(|n|n==&context.calendar))).collect();
                let [calendar] = calendars.as_slice() else {
                    anyhow::bail!("Select one accessible authored calendar explicitly.");
                };
                let calendar_id = CalendarId::parse(
                    &calendar
                        .identity
                        .record_id
                        .as_str()
                        .replacen("rec_", "cal_", 1),
                )?;
                let clocks: Vec<_> = rows
                    .iter()
                    .filter_map(|r| {
                        if let Payload::RepresentedContext(c) = &r.payload {
                            c.chronology.as_ref().filter(|c| c.calendar == calendar_id)
                        } else {
                            None
                        }
                    })
                    .collect();
                let Some(clock) = clocks.first() else {
                    anyhow::bail!("This calendar has no authored clock system; declare it before creating a timed context.");
                };
                if clocks.iter().any(|other| other.system != clock.system) {
                    anyhow::bail!("The selected calendar has conflicting authored clock systems.");
                }
                let mut chronology = (*clock).clone();
                let time = chronology
                    .coordinate(&context.story_time)
                    .map_err(|e| anyhow::anyhow!(e))?;
                chronology.first_interaction = time.clone();
                chronology.current = time;
                chronology.validate().map_err(|e| anyhow::anyhow!(e))?;
                let kind = serde_json::to_value(context.kind)?
                    .as_str()
                    .unwrap()
                    .to_string();
                Ok(Some(
                    json!({"kind":"record_narrative_reference","client_ref":RecordId::generate(&mut rand::rng()),"record":"represented_context","payload":{"record_kind":"represented_context","universe":ctx.frame.universe,"kind":{"kind":"authored","label":format!("{kind}: {}",context.name)},"parent":{"universe":ctx.frame.universe,"record":parent},"chronology":chronology,"labels":{"en":context.name}}}),
                ))
            })();
            match built {
                Ok(Some(op)) => {
                    operations.push(op);
                    result.additions.push(format!("New authored context: {} (parent {}; explicit time {}). Publish and open it before adding local facts.",context.name,context.parent,context.story_time));
                }
                Ok(None) => result
                    .unchanged
                    .push(format!("Existing context: {}", context.name)),
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        Ok(())
    }
}
