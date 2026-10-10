//! Incremental named event edits; existing expansion, accounting and impact remain authoritative.
use super::*;
use universe_domain::{expr::Expr, temporal::TemporalExpression};
use universe_protocol::writing::*;

impl Workflow<'_> {
    pub(super) fn writing_event_corrections(
        &self,
        input: &CheckChanges,
        ctx: &Context,
        base: &[RecordVersion],
        ops: &mut Vec<Value>,
        result: &mut WritingCheck,
    ) -> anyhow::Result<()> {
        if input.event_corrections.is_empty() && input.event_withdrawals.is_empty() {
            return Ok(());
        }
        let u = self.kernel.universe();
        let mut corrected = BTreeSet::new();
        for withdrawal in &input.event_withdrawals {
            let built = (|| -> anyhow::Result<Value> {
                if withdrawal.reason.trim().is_empty() { anyhow::bail!("Explain the author's occurrence withdrawal."); }
                let original = base.iter().find(|r|r.record_version_id.as_str()==withdrawal.event_handle)
                    .ok_or_else(||anyhow::anyhow!("Retrieve the current occurred-event edit handle before withdrawing it; stale, absent or restricted handles cannot be edited."))?;
                let Payload::Event(e) = &original.payload else { anyhow::bail!("Retrieve an occurred-event edit handle."); };
                if e.occurrence != OccurrenceMode::Occurred || !(e.action.as_ref().is_some_and(|a|base.iter().any(|r|r.identity.record_id==a.record && matches!(&r.payload,Payload::ActionDefinition(d) if d.scope.context==ctx.frame.context))) || (e.action.is_none() && !e.effects.is_empty() && e.effects.iter().all(|effect|effect.scope.context==ctx.frame.context))) { anyhow::bail!("Retrieve an occurred event in this selected author context."); }
                if !corrected.insert(original.identity.record_id.clone()) { anyhow::bail!("Submit one correction or withdrawal per event in this delta."); }
                Ok(json!({"kind":"withdraw_event","record":RecordRef::new(u.clone(),original.identity.record_id.clone()),"expected_version":original.record_version_id,"rationale":withdrawal.reason}))
            })();
            match built {
                Ok(op)=>{ops.push(op);result.additions.push(format!("Withdraw occurrence support; no non-occurrence or opposite claim asserted; reason: {}",withdrawal.reason));},
                Err(e)=>result.clarifications.push(e.to_string()),
            }
        }
        for correction in &input.event_corrections {
            let built = (|| -> anyhow::Result<Vec<Value>> {
                if correction.reason.trim().is_empty() {
                    anyhow::bail!("Explain the author's event correction.");
                }
                let original = base
                    .iter()
                    .find(|r| r.identity.record_id.as_str() == correction.event_handle)
                    .ok_or_else(|| {
                        anyhow::anyhow!("Retrieve the pinned occurred event before correcting it.")
                    })?;
                if !corrected.insert(original.identity.record_id.clone()) {
                    anyhow::bail!("Submit one incremental correction per event in this delta.");
                }
                let Payload::Event(old) = &original.payload else {
                    anyhow::bail!("Correction handle does not select an occurred event.");
                };
                if old.occurrence != OccurrenceMode::Occurred {
                    anyhow::bail!("This ordinary correction path supports occurred events only.");
                }
                let mut replacement = old.clone();
                // The edited occurrence is not a prerequisite for itself. Remove it
                // before compiling preceding withdrawals, so an explicitly corrected
                // dependent is not validated with its obsolete frozen balance.
                let derivation_base:Vec<_>=base.iter().filter(|r|r.identity.record_id!=original.identity.record_id && !matches!(&r.payload,Payload::Assertion(a)if a.established_by.as_ref().is_some_and(|e|e.event.record==original.identity.record_id))).cloned().collect();
                let mut rows = super::writing_connected::candidate_records(u, ctx, &derivation_base, ops)?;
                let original_action=old.action.as_ref().and_then(|a|rows.iter().find(|r|r.identity.record_id==a.record)).and_then(|r|if let Payload::ActionDefinition(a)=&r.payload {Some(a)}else{None}).ok_or_else(||anyhow::anyhow!("The original event lacks a readable declared action; use explicit advanced correction."))?;
                let original_contract=original_action.consequence_contract.as_ref().ok_or_else(||anyhow::anyhow!("The original event's consequences are not contract-derived; use explicit advanced correction."))?;
                if old.effects.iter().any(|effect| {
                    !original_contract
                        .slots
                        .iter()
                        .any(|slot| slot.slot == effect.slot)
                }) {
                    anyhow::bail!("Manually authored effects outside the declared contract require explicit advanced correction; none were dropped.");
                }
                if let Some(action) = &correction.action {
                    let matches:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::ActionDefinition(a)if a.key==*action||a.labels.values().any(|v|v==action))).collect();
                    if matches.len() != 1 {
                        anyhow::bail!("Which exact authored action is '{action}'? Research its contract before correcting the event.");
                    }
                    replacement.action = Some(RecordRef::new(
                        u.clone(),
                        matches[0].identity.record_id.clone(),
                    ));
                }
                if let Some(participants) = &correction.participants {
                    replacement.participants=participants.iter().map(|(role,name)|super::writing_connected::object(&rows,name,&ctx.frame).map(|id|EventParticipant{role:role.clone(),record:RecordRef::new(u.clone(),id)}).ok_or_else(||anyhow::anyhow!("Which exact object fills corrected role '{role}' as '{name}'?"))).collect::<anyhow::Result<_>>()?;
                }
                if let Some(tick) = &correction.at_tick {
                    let TemporalExpression::Exact { calendar, .. } = &old.time else {
                        anyhow::bail!("The event's calendar is unresolved; ordinary coordinate correction cannot choose a calendar.");
                    };
                    replacement.time = TemporalExpression::Exact {
                        calendar: calendar.clone(),
                        value: tick.clone(),
                    };
                }
                if let Some(world) = &correction.world {
                    replacement.worlds = vec![self
                        .focus(&json!({"world":world}), &rows)?
                        .ok_or_else(denied)?];
                }
                let mut changes = vec![];
                if let Some(dependencies) = &correction.requires_knowledge {
                    replacement.preconditions.retain(|p| {
                        !matches!(
                            p,
                            Expr::Attitude {
                                attitude: EpistemicAttitudeKind::Knows,
                                ..
                            }
                        )
                    });
                    for dependency in dependencies {
                        let holder =
                            super::writing_connected::object(&rows, &dependency.holder, &ctx.frame)
                                .ok_or_else(|| {
                                    anyhow::anyhow!(
                                        "Which exact holder is '{}' ?",
                                        dependency.holder
                                    )
                                })?;
                        let claim = super::writing_connected::claim(
                            u,
                            &rows,
                            &ctx.frame,
                            &dependency.claim,
                        )?;
                        let proposition =
                            super::writing_connected::define(&mut changes, u, &claim, &rows);
                        replacement.preconditions.push(Expr::Attitude {
                            holder: RecordRef::new(u.clone(), holder),
                            proposition,
                            attitude: EpistemicAttitudeKind::Knows,
                        });
                    }
                }
                let action = replacement
                    .action
                    .as_ref()
                    .and_then(|a| rows.iter().find(|r| r.identity.record_id == a.record))
                    .and_then(|r| {
                        if let Payload::ActionDefinition(a) = &r.payload {
                            Some(a.clone())
                        } else {
                            None
                        }
                    })
                    .ok_or_else(|| {
                        anyhow::anyhow!("Retrieve the event's applicable authored action contract.")
                    })?;
                // Exclude only this event's obsolete generated evidence before deriving its new effects.
                rows.retain(|r|r.identity.record_id!=original.identity.record_id && !matches!(&r.payload,Payload::Assertion(a)if a.established_by.as_ref().is_some_and(|e|e.event.record==original.identity.record_id)));
                // Removing the old occurrence also removes its boundary on earlier
                // generated stock. Derive against the remaining authored events,
                // not intervals frozen while the old occurrence still existed.
                let expanded = universe_rules::events::expand(&rows)
                    .map_err(|e| anyhow::anyhow!(e))?;
                rows.retain(|r| !matches!(&r.payload,Payload::Assertion(a)if a.established_by.is_some()));
                for (id, assertion) in expanded {
                    rows.push(RecordVersion::build(
                        universe_domain::ids::RecordVersionId::generate(&mut rand::rng()),
                        RecordIdentity::new(u.clone(), id, RecordKind::Assertion),
                        Payload::Assertion(assertion),
                    )?);
                }
                replacement.effects.clear();
                for (id, proposition, effect) in crate::consequences::author_effects(
                    &rows,
                    &original.identity.record_id,
                    &replacement,
                    &action,
                    &ctx.frame,
                )? {
                    changes.push(
                        json!({"kind":"define_proposition","client_ref":id,"record":proposition}),
                    );
                    replacement.effects.push(effect);
                }
                changes.push(json!({"kind":"revise_event","record":RecordRef::new(u.clone(),original.identity.record_id.clone()),"expected_version":original.record_version_id,"replacement":replacement}));
                let mut candidate = ops.clone();
                candidate.extend(changes.clone());
                super::writing_connected::candidate_records(u, ctx, base, &candidate)?;
                Ok(changes)
            })();
            match built {
                Ok(mut changes) => {
                    ops.append(&mut changes);
                    result.additions.push(format!("Occurred event correction: {}; reason {}. Consequences rechecked; dependent events are not automatically repaired.",correction.event_handle,correction.reason));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        Ok(())
    }
}
