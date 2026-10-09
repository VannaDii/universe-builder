//! Named explicit starts over the existing approved-source initialization compiler.
use super::*;
use universe_domain::{scope::*, temporal::*};
use universe_protocol::writing::*;

impl Workflow<'_> {
    pub(super) fn writing_initializations(
        &self,
        input: &CheckChanges,
        ctx: &Context,
        base: &[RecordVersion],
        ops: &mut Vec<Value>,
        result: &mut WritingCheck,
    ) -> anyhow::Result<()> {
        if input.initializations.is_empty() {
            return Ok(());
        }
        let rows =
            super::writing_connected::candidate_records(self.kernel.universe(), ctx, base, ops)?;
        let u = self.kernel.universe();
        for request in &input.initializations {
            let build = (|| -> anyhow::Result<Vec<Value>> {
                let instance =
                    super::writing_connected::object(&rows, &request.instance, &ctx.frame)
                        .ok_or_else(|| {
                            anyhow::anyhow!("Which exact instance is '{}' ?", request.instance)
                        })?;
                if request.initial_value_handles.is_empty() {
                    anyhow::bail!(
                        "Select an approved initial-value source for this instance start."
                    );
                }
                let applicability = match request.scope.as_str() {
                    "universe" => Applicability::UniverseWide,
                    "unspecified" => {
                        anyhow::bail!("What authored jurisdiction applies to this instance start?")
                    }
                    world => Applicability::Worlds {
                        world_ids: vec![self
                            .focus(&json!({"world":world}), &rows)?
                            .ok_or_else(denied)?],
                    },
                };
                let scope = Scope {
                    context: ctx.frame.context.clone(),
                    applicability,
                    realm: None,
                };
                let mut operations = vec![];
                let (start, event) = match &request.start {
                    WritingInstanceStart::Existing { handle } => {
                        let row=base.iter().find(|r|r.identity.record_id.as_str()==handle).ok_or_else(||anyhow::anyhow!("Retrieve the pinned occurred-event handle for the explicit instance start."))?;
                        let Payload::Event(e) = &row.payload else {
                            anyhow::bail!("Instance start handle must select an occurred event.");
                        };
                        (row.identity.record_id.clone(), e.clone())
                    }
                    WritingInstanceStart::Occurred { event } => {
                        let nested: CheckChanges = serde_json::from_value(
                            json!({"universe":input.universe,"context_id":input.context_id,"events":[event]}),
                        )?;
                        let mut partial = result.clone();
                        partial.clarifications.clear();
                        self.connected_writing(&nested, ctx, &rows, &mut operations, &mut partial)?;
                        if !partial.clarifications.is_empty() {
                            anyhow::bail!("{}", partial.clarifications.join("; "));
                        }
                        let selected = operations
                            .iter()
                            .find(|o| o["kind"] == "record_event")
                            .ok_or_else(denied)?;
                        (
                            serde_json::from_value(selected["client_ref"].clone())?,
                            serde_json::from_value::<Event>(selected["record"].clone())?,
                        )
                    }
                };
                let TemporalExpression::Exact { calendar, value } = &event.time else {
                    anyhow::bail!("An exact authored instance-start time is required.");
                };
                let end=match &request.lifetime {
                    FactLifetime::UntilChanged=>TemporalBound::Unbounded,
                    FactLifetime::Until{end_tick}=>TemporalBound::Exact{value:end_tick.clone()},
                    FactLifetime::Unspecified=>anyhow::bail!("What explicit interval or until_changed lifetime applies to initialized values?"),
                };
                let validity = Validity::CalendarInterval {
                    calendar: calendar.clone(),
                    start: TemporalBound::Exact {
                        value: value.clone(),
                    },
                    end,
                };
                for handle in &request.initial_value_handles {
                    let source=base.iter().find(|r|r.record_version_id.as_str()==handle).ok_or_else(||anyhow::anyhow!("Publish and retrieve the approved initial-value definition before initialization."))?;
                    if !matches!(&source.payload,Payload::Assertion(a)if a.attribute_mode==AttributeMode::InitialValue)
                    {
                        anyhow::bail!(
                            "Selected source is not an approved initial-value definition."
                        );
                    }
                    operations.push(json!({"kind":"initialize_instance","client_ref":RecordId::generate(&mut rand::rng()),"instance":RecordRef::new(u.clone(),instance.clone()),"start":RecordRef::new(u.clone(),start.clone()),"definition":{"universe":u,"record":source.identity.record_id,"version":source.record_version_id},"scope":scope,"validity":validity}));
                }
                // Existing compiler checks ancestry, occurred start, selected source and jurisdiction.
                let mut candidate = ops.clone();
                candidate.extend(operations.clone());
                super::writing_connected::candidate_records(u, ctx, base, &candidate)?;
                Ok(operations)
            })();
            match build {
                Ok(mut operations) => {
                    ops.append(&mut operations);
                    result.additions.push(format!(
                        "Explicit instance start and selected initialization: {}",
                        request.instance
                    ));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        Ok(())
    }
}
