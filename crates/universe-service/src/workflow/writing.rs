//! Small public authoring interface over the existing canonical workflow.
use super::*;
use std::collections::BTreeMap;
use universe_protocol::writing::{CheckChanges, FactValue, WritingCheck};

impl Workflow<'_> {
    pub(super) fn check_writing_changes(&mut self, input: CheckChanges) -> anyhow::Result<Value> {
        let ctx = self.context(&input.context_id)?;
        let args = serde_json::to_value(&input)?;
        if !matches!(ctx.frame.perspective, Perspective::Author) {
            return self.wrap(&args,Some(ctx.frame),None,true,None,json!(WritingCheck{status:"needs_clarification".into(),candidate_handle:None,additions:vec![],unchanged:vec![],clarifications:vec!["Canon changes require an explicitly selected authorized author-perspective context; this restricted view is research only.".into()],excluded:vec![],unknowns:vec![],validation:None,impact:None}));
        }
        let base = self
            .kernel
            .records(&ctx.frame.continuity, &ctx.frame.revision)?;
        let visible = self.visible_ids(&base)?;
        let records: Vec<_> = base
            .iter()
            .filter(|r| visible.contains(&r.identity.record_id))
            .collect();
        let mut result = WritingCheck {
            status: "needs_clarification".into(),
            candidate_handle: None,
            additions: vec![],
            unchanged: vec![],
            clarifications: input.questions.clone(),
            excluded: vec![],
            unknowns: vec![],
            validation: None,
            impact: None,
        };
        let binding = hash(&(&args, &ctx.frame, &self.principal.id));

        let key = format!("writing:{binding}");
        let receipt = self.operation_key("propose", &key);
        if result.clarifications.is_empty() && self.kernel.workflow_get(&receipt)?.is_some() {
            if !self.permissions.0 {
                return Err(ProtocolError::PolicyDenied {
                    message: "current grant does not permit proposals".into(),
                }
                .into());
            }
            let prior = self.operation(&receipt)?;
            let p = prior.status.proposal.ok_or_else(denied)?;
            result
                .additions
                .push("Reused the exact original uncommitted candidate.".into());
            return self.finish_writing_check(input, args, ctx, result, p);
        }
        let mut names = BTreeMap::<String, RecordId>::new();
        let mut properties = BTreeMap::<String, (RecordId, PropertyDef)>::new();
        let mut operations = vec![];
        let mut assertions = BTreeSet::new();
        let mut ambiguous_new = BTreeSet::new();
        let mut new_properties = BTreeMap::new();
        let mut emitted_properties = BTreeSet::new();
        self.writing_units(
            &input,
            &records.iter().map(|r| (*r).clone()).collect::<Vec<_>>(),
            &mut operations,
            &mut result,
        )?;
        let property_records = super::writing_connected::candidate_records(
            self.kernel.universe(),
            &ctx,
            &records.iter().map(|r| (*r).clone()).collect::<Vec<_>>(),
            &operations,
        )?;
        self.writing_properties(
            &input,
            &property_records,
            &mut properties,
            &mut operations,
            &mut result,
        )?;

        for object in input.changes.iter().filter(|o| {
            o.introduce
                && (o.facts.is_empty() || o.facts.iter().any(|f| f.statement == "objective"))
        }) {
            if names.contains_key(&object.name) {
                result.clarifications.push(format!("Are the repeated introductions of '{}' the same object or separate identities?", object.name));
                ambiguous_new.insert(object.name.clone());
                continue;
            }
            names.insert(object.name.clone(), RecordId::generate(&mut rand::rng()));
        }
        let mut definition_ids = BTreeMap::new();
        let mut ambiguous_definitions = BTreeSet::new();
        for definition in input.definitions.iter().filter(|d| d.introduce) {
            if definition.name.trim().is_empty() {
                return Err(ProtocolError::invalid_argument(
                    "definitions.name",
                    "nonempty definition name required",
                )
                .into());
            }
            if definition_ids
                .insert(
                    definition.name.clone(),
                    RecordId::generate(&mut rand::rng()),
                )
                .is_some()
            {
                ambiguous_definitions.insert(definition.name.clone());
                result.clarifications.push(format!(
                    "Are the repeated definitions '{}' the same type?",
                    definition.name
                ));
            }
        }
        let resolve_definition = |name: &str| -> Option<RecordId> {
            if ambiguous_definitions.contains(name) {
                return None;
            }
            let mut ids: BTreeSet<_> = records
                .iter()
                .filter_map(|r| match &r.payload {
                    Payload::EntityType(t)
                        if t.name == name
                            || t.key == name
                            || t.labels.values().any(|v| v == name) =>
                    {
                        Some(r.identity.record_id.clone())
                    }
                    _ => None,
                })
                .collect();
            if let Some(id) = definition_ids.get(name) {
                ids.insert(id.clone());
            }
            (ids.len() == 1).then(|| ids.into_iter().next().unwrap())
        };
        for definition in &input.definitions {
            let Some(id) = resolve_definition(&definition.name) else {
                result.clarifications.push(format!("Which exact reusable definition is '{}', or is it an explicitly new definition?", definition.name));
                continue;
            };
            if definition.introduce {
                let parent = if let Some(name) = &definition.parent {
                    let Some(parent) = resolve_definition(name) else {
                        result
                            .clarifications
                            .push(format!("Which exact parent definition is '{}'?", name));
                        continue;
                    };
                    Some(parent)
                } else {
                    None
                };
                let applicability = match definition.scope.as_str() {
                    "universe" => Applicability::UniverseWide,
                    "unspecified" => Applicability::Unspecified,
                    world => match self
                        .focus(&json!({"world":world}), &base)
                        .and_then(|id| id.ok_or_else(denied))
                    {
                        Ok(id) => Applicability::Worlds {
                            world_ids: vec![id],
                        },
                        Err(_) => {
                            result
                                .clarifications
                                .push(format!("Which accessible authored world is '{}'?", world));
                            continue;
                        }
                    },
                };
                if definition.scope == "unspecified" {
                    result.unknowns.push(format!(
                        "The applicability of definition '{}' remains unspecified.",
                        definition.name
                    ));
                }
                operations.push(json!({"kind":"introduce_definition","client_ref":id,"namespace":"authoring","key":definition.name,"name":definition.name,"parent":parent,"applicability":applicability,"classification_executable":true}));
                result
                    .additions
                    .push(format!("New reusable definition: {}", definition.name));
            } else if definition.parent.is_some() {
                result.clarifications.push("Changing an existing definition's ancestry requires an explicit definition revision, not classification refinement.".into());
            }
        }
        let resolve = |name: &str| -> Option<RecordId> {
            if ambiguous_new.contains(name) {
                return None;
            }
            let matches: Vec<_> = records
                .iter()
                .filter(|r| match &r.payload {
                    Payload::Entity(e) => {
                        e.labels.values().any(|s| s == name)
                            || e.names.iter().any(|n| {
                                n.text == name
                                    && universe_rules::time::applies(&n.validity, &ctx.frame.time)
                                        != Some(false)
                            })
                    }
                    _ => false,
                })
                .collect();
            let mut ids: BTreeSet<_> = matches
                .iter()
                .map(|r| r.identity.record_id.clone())
                .collect();
            if let Some(id) = names.get(name) {
                ids.insert(id.clone());
            }
            (ids.len() == 1).then(|| ids.into_iter().next().unwrap())
        };
        let shared_objects: Vec<_> = input
            .definitions
            .iter()
            .map(|d| universe_protocol::writing::ObjectChange {
                name: d.name.clone(),
                introduce: false,
                classification: None,
                facts: d.shared_attributes.clone(),
            })
            .collect();
        let initial_objects: Vec<_> = input
            .definitions
            .iter()
            .map(|d| universe_protocol::writing::ObjectChange {
                name: d.name.clone(),
                introduce: false,
                classification: None,
                facts: d.initial_values.clone(),
            })
            .collect();
        for (object, shared, initial) in input
            .changes
            .iter()
            .map(|o| (o, false, false))
            .chain(shared_objects.iter().map(|o| (o, true, false)))
            .chain(initial_objects.iter().map(|o| (o, true, true)))
        {
            if object.name.trim().is_empty() {
                return Err(ProtocolError::invalid_argument(
                    "changes.name",
                    "nonempty object name required",
                )
                .into());
            }
            for fact in &object.facts {
                if !matches!(
                    fact.statement.as_str(),
                    "objective" | "dialogue" | "belief" | "plan" | "hypothetical" | "metaphor"
                ) {
                    return Err(ProtocolError::invalid_argument(
                        "statement",
                        "unknown statement mode",
                    )
                    .into());
                }
                if fact.statement != "objective" {
                    result.excluded.push(format!(
                        "{} {}: {} claim, not an objective fact",
                        object.name, fact.property, fact.statement
                    ));
                }
            }
            if !object.facts.is_empty() && object.facts.iter().all(|f| f.statement != "objective") {
                if object.introduce {
                    result.clarifications.push(format!("Does the objective narration separately establish '{}' as a real new object?", object.name));
                }
                continue;
            }
            if ambiguous_new.contains(&object.name) {
                continue;
            }
            let classification = if let Some(name) = &object.classification {
                let Some(id) = resolve_definition(name) else {
                    result.clarifications.push(format!(
                        "Which exact classification definition is '{}'?",
                        name
                    ));
                    continue;
                };
                Some(id)
            } else {
                None
            };
            let subject = if shared {
                let Some(id) = resolve_definition(&object.name) else {
                    continue;
                };
                id
            } else if object.introduce {
                let id = names.get(&object.name).cloned().ok_or_else(|| {
                    ProtocolError::invalid_argument("introduce", "ambiguous new identity")
                })?;
                operations.push(json!({"kind":"introduce_instance","client_ref":id,"name":{"text":object.name,"validity":{"kind":"unspecified"}},"classification":classification,"world_associations":[]}));
                result
                    .additions
                    .push(format!("New object: {}", object.name));
                id
            } else if let Some(id) = resolve(&object.name) {
                id
            } else {
                result.clarifications.push(format!(
                    "Which existing object is '{}', or is this a new independent object?",
                    object.name
                ));
                continue;
            };
            if !shared && !object.introduce {
                if let Some(classification) = classification {
                    let current = records
                        .iter()
                        .find(|r| r.identity.record_id == subject)
                        .ok_or_else(denied)?;
                    if matches!(&current.payload, Payload::Entity(e) if e.classification.as_ref() == Some(&classification) && e.classification_resolution == universe_domain::records::ClassificationResolution::Resolved)
                    {
                        result
                            .unchanged
                            .push(format!("{}: classification", object.name));
                    } else {
                        operations.push(json!({"kind":"refine_classification","record":{"universe":self.kernel.universe(),"record":subject},"expected_version":current.record_version_id,"entity_type":classification}));
                        result
                            .additions
                            .push(format!("Refined classification: {}", object.name));
                    }
                }
            }
            for fact in &object.facts {
                if !matches!(
                    fact.statement.as_str(),
                    "objective" | "dialogue" | "belief" | "plan" | "hypothetical" | "metaphor"
                ) {
                    return Err(ProtocolError::invalid_argument(
                        "statement",
                        "expected objective, dialogue, belief, plan, hypothetical or metaphor",
                    )
                    .into());
                }
                if fact.statement != "objective" {
                    continue;
                }
                if fact.property.trim().is_empty() {
                    return Err(ProtocolError::invalid_argument(
                        "property",
                        "nonempty property name required",
                    )
                    .into());
                }
                let (value, shape) = match &fact.value {
                    FactValue::Text(text) => {
                        (json!({"kind":"text","text":text}), json!({"kind":"text"}))
                    }
                    FactValue::Boolean(value) => (
                        json!({"kind":"boolean","value":value}),
                        json!({"kind":"boolean"}),
                    ),
                    FactValue::Number(n) => {
                        let kind = if !n.to_string().chars().any(|c| matches!(c, '.' | 'e' | 'E')) {
                            "integer"
                        } else {
                            "decimal"
                        };
                        (
                            json!({"kind":kind,"digits":n.to_string()}),
                            json!({"kind":kind}),
                        )
                    }
                    FactValue::Quantity { .. } => {
                        let typed = match super::writing_connected::fact_value(
                            self.kernel.universe(),
                            &property_records,
                            &ctx.frame,
                            &fact.value,
                        ) {
                            Ok(value) => value,
                            Err(e) => {
                                result.clarifications.push(e.to_string());
                                continue;
                            }
                        };
                        let universe_domain::value::Value::Quantity { unit, .. } = &typed else {
                            unreachable!()
                        };
                        (json!(typed), json!({"kind":"quantity","unit":unit}))
                    }
                    FactValue::Object { object: name } => {
                        let Some(id) = resolve(name) else {
                            result
                                .clarifications
                                .push(format!("Which object does '{}' refer to?", name));
                            continue;
                        };
                        (
                            json!({"kind":"entity_ref","ref":{"universe":self.kernel.universe(),"record":id}}),
                            json!({"kind":"entity_ref","subject_types":[]}),
                        )
                    }
                };
                let property = if let Some(p) = properties.get(&fact.property) {
                    p.clone()
                } else {
                    let found: Vec<_> = records
                        .iter()
                        .filter_map(|r| match &r.payload {
                            Payload::Property(p)
                                if p.key == fact.property
                                    || p.labels.values().any(|s| s == &fact.property) =>
                            {
                                Some((r.identity.record_id.clone(), p.clone()))
                            }
                            _ => None,
                        })
                        .collect();
                    let p = match found.as_slice() {
                        [p] => p.clone(),
                        [] => {
                            let id = RecordId::generate(&mut rand::rng());
                            let definition = json!({"namespace":"authoring","key":fact.property,"labels":{},"subjectTypes":[],"value":shape,"multiplicity":"multiple","persistence":"unspecified","exclusive":false,"symmetric":false,"transitive":false});
                            new_properties.insert(id.clone(), definition.clone());
                            (id, serde_json::from_value(definition)?)
                        }
                        _ => {
                            result.clarifications.push(format!(
                                "Which authored property named '{}' applies?",
                                fact.property
                            ));
                            continue;
                        }
                    };
                    properties.insert(fact.property.clone(), p.clone());
                    p
                };
                let actual_shape: ValueShape = serde_json::from_value(shape)?;
                if property.1.value != actual_shape
                    && !matches!(
                        (&property.1.value, &actual_shape),
                        (ValueShape::EntityRef { .. }, ValueShape::EntityRef { .. })
                    )
                {
                    result.clarifications.push(format!("The value for '{} {}' does not match the existing property definition; clarify its intended value/unit/type.", object.name, fact.property));
                    continue;
                }
                let applicability = match fact.scope.as_str() {
                    "universe" => Applicability::UniverseWide,
                    "unspecified" => Applicability::Unspecified,
                    world => match self
                        .focus(&json!({"world":world}), &base)
                        .and_then(|id| id.ok_or_else(denied))
                    {
                        Ok(id) => Applicability::Worlds {
                            world_ids: vec![id],
                        },
                        Err(_) => {
                            result
                                .clarifications
                                .push(format!("Which accessible authored world is '{}'?", world));
                            continue;
                        }
                    },
                };
                let when = if fact.at_tick.is_some() {
                    "scene"
                } else {
                    fact.when.as_str()
                };
                if when != "scene"
                    && !matches!(
                        fact.lifetime,
                        universe_protocol::writing::FactLifetime::Unspecified
                    )
                {
                    result.clarifications.push(
                        "What authored scene time starts this explicit fact lifetime?".into(),
                    );
                    continue;
                }
                let fact_time = if when == "scene" && fact.at_tick.is_some() {
                    match super::writing_connected::time(
                        &ctx.frame,
                        &records.iter().map(|r| (*r).clone()).collect::<Vec<_>>(),
                        &fact.at_tick,
                    ) {
                        Ok(time) => FrameTime::At { time },
                        Err(e) => {
                            result.clarifications.push(e.to_string());
                            continue;
                        }
                    }
                } else {
                    ctx.frame.time.clone()
                };
                let validity = match when {
                    "unspecified" => universe_domain::scope::Validity::Unspecified,
                    "scene" => match &fact_time {
                        FrameTime::At { time } => {
                            use universe_domain::scope::{PersistenceSemantics, Validity};
                            use universe_domain::temporal::{TemporalBound, TemporalExpression};
                            use universe_protocol::writing::FactLifetime;
                            match (&fact.lifetime, time) {
                                (FactLifetime::Unspecified, _)
                                    if property.1.persistence
                                        != PersistenceSemantics::PersistentUntilChanged =>
                                {
                                    Validity::Instant { at: time.clone() }
                                }
                                (lifetime, TemporalExpression::Exact { calendar, value }) => {
                                    Validity::CalendarInterval {
                                        calendar: calendar.clone(),
                                        start: TemporalBound::Exact {
                                            value: value.clone(),
                                        },
                                        end: match lifetime {
                                            FactLifetime::Until { end_tick } => {
                                                TemporalBound::Exact {
                                                    value: end_tick.clone(),
                                                }
                                            }
                                            _ => TemporalBound::Unbounded,
                                        },
                                    }
                                }
                                _ => {
                                    result.clarifications.push(
                                        "What exact calendar time/lifetime applies to this fact?"
                                            .into(),
                                    );
                                    continue;
                                }
                            }
                        }
                        _ => {
                            result
                                .clarifications
                                .push("What story time do these scene facts hold at?".into());
                            continue;
                        }
                    },
                    _ => {
                        return Err(ProtocolError::invalid_argument(
                            "when",
                            "expected scene or unspecified",
                        )
                        .into());
                    }
                };
                let scope = universe_domain::scope::Scope {
                    applicability,
                    context: ctx.frame.context.clone(),
                    realm: None,
                };
                let value_typed: universe_domain::value::Value =
                    serde_json::from_value(value.clone())?;
                let polarity = if fact.negated {
                    universe_domain::scope::Polarity::Refutation
                } else {
                    universe_domain::scope::Polarity::Support
                };
                let already = records.iter().any(|r| if let Payload::Proposition(p) = &r.payload {
                    p.subject.record == subject && p.predicate.record == property.0 && p.value.as_ref() == Some(&value_typed) && p.context == ctx.frame.context && records.iter().any(|a| matches!(&a.payload, Payload::Assertion(a) if a.proposition.record == r.identity.record_id && a.attribute_mode == if initial { universe_domain::records::AttributeMode::InitialValue } else if shared { universe_domain::records::AttributeMode::Shared } else { universe_domain::records::AttributeMode::Instance } && a.polarity == polarity && a.precision == universe_domain::scope::Precision::Exact && a.alternatives.is_empty() && a.scope == scope && (a.validity == validity || matches!(&fact_time, FrameTime::At {..}) && universe_rules::time::applies(&a.validity, &fact_time) == Some(true))))
                } else { false });
                let assertion_binding = hash(&(
                    &subject,
                    &property.0,
                    &value,
                    &scope,
                    &validity,
                    &polarity,
                    &initial,
                    &shared,
                ));
                if already || !assertions.insert(assertion_binding) {
                    result
                        .unchanged
                        .push(format!("{}: {}", object.name, fact.property));
                    continue;
                }
                if fact.scope == "unspecified" {
                    result.unknowns.push(
                        "The world/universe applicability of the new facts remains unspecified."
                            .into(),
                    );
                }
                if when == "unspecified" {
                    result.unknowns.push(
                        "The story-time validity of the new facts remains unspecified.".into(),
                    );
                }
                if let Some(definition) = new_properties.get(&property.0) {
                    if emitted_properties.insert(property.0.clone()) {
                        operations.push(json!({"kind":"define_property","client_ref":property.0,"record":definition}));
                    }
                }
                let proposition = RecordId::generate(&mut rand::rng());
                if shared && new_properties.contains_key(&property.0) {
                    operations.push(json!({"kind":"add_named_attribute","client_ref":proposition,"subject":{"universe":self.kernel.universe(),"record":subject},"namespace":property.1.namespace,"key":property.1.key,"value_shape":property.1.value,"subject_types":property.1.subject_types,"multiplicity":property.1.multiplicity,"value":value,"evidence":{"attributeMode":if initial {"initial_value"}else{"shared"},"polarity":polarity,"scope":scope,"validity":validity,"persistence":property.1.persistence,"precision":"exact","basis":{"kind":"imported_claim"}}}));
                } else {
                    operations.push(json!({"kind":"assert_proposition","client_ref":proposition,"proposition":{"subject":{"universe":self.kernel.universe(),"record":subject},"predicate":{"universe":self.kernel.universe(),"record":property.0},"value":value,"context":ctx.frame.context,"quantification":"particular"},"assertion":{"attributeMode":if initial {"initial_value"}else if shared {"shared"}else{"instance"},"proposition":{"universe":self.kernel.universe(),"record":proposition},"polarity":polarity,"scope":scope,"validity":validity,"persistence":property.1.persistence,"precision":"exact","basis":{"kind":"imported_claim"}}}));
                }
                result.additions.push(format!(
                    "{}: {} {}",
                    object.name,
                    fact.property,
                    if fact.negated {
                        format!("not {}", serde_json::to_string(&fact.value)?)
                    } else {
                        serde_json::to_string(&fact.value)?
                    }
                ));
            }
        }
        self.writing_aliases(
            &input,
            &ctx,
            &records.iter().map(|r| (*r).clone()).collect::<Vec<_>>(),
            &mut operations,
            &mut result,
        )?;
        self.writing_contracts(
            &input,
            &ctx,
            &records.iter().map(|r| (*r).clone()).collect::<Vec<_>>(),
            &mut operations,
            &mut result,
        )?;
        self.writing_relations(
            &input,
            &ctx,
            &records.iter().map(|r| (*r).clone()).collect::<Vec<_>>(),
            &mut operations,
            &mut result,
        )?;
        self.writing_initializations(
            &input,
            &ctx,
            &records.iter().map(|r| (*r).clone()).collect::<Vec<_>>(),
            &mut operations,
            &mut result,
        )?;
        self.writing_event_corrections(
            &input,
            &ctx,
            &records.iter().map(|r| (*r).clone()).collect::<Vec<_>>(),
            &mut operations,
            &mut result,
        )?;
        self.connected_writing(
            &input,
            &ctx,
            &records.iter().map(|r| (*r).clone()).collect::<Vec<_>>(),
            &mut operations,
            &mut result,
        )?;
        result.clarifications.sort();
        result.clarifications.dedup();
        result.unknowns.sort();
        result.unknowns.dedup();
        if !result.clarifications.is_empty() || operations.is_empty() {
            result.status = if !result.clarifications.is_empty() {
                "needs_clarification"
            } else if self.scope.is_some() {
                "incomplete"
            } else {
                "no_changes"
            }
            .into();
            return self.wrap(
                &args,
                Some(ctx.frame),
                None,
                true,
                None,
                serde_json::to_value(result)?,
            );
        }
        if !self.permissions.0 {
            return Err(ProtocolError::PolicyDenied {
                message: "current grant does not permit proposals".into(),
            }
            .into());
        }
        let admission = self.execute(Request::from_tool("universe_open_context", json!({"universe":input.universe,"continuity_id":ctx.frame.continuity,"revision":{"kind":"exact","revision_id":ctx.frame.revision},"represented_context":ctx.frame.context.record,"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))?)?;
        let mut rationale = "Provisional factual deltas from author writing; no author approval or source publication implied.".to_string();
        for ending in &input.fact_endings {
            rationale.push_str(&format!("\nProposed fact ending reason: {}", ending.reason));
        }
        let prepared = json!({"action":"create","universe":input.universe,"context_id":admission["result"]["context_id"],"operations":operations,"submission":"draft","rationale":rationale,"idempotency_key":key});
        let proposed = self.execute(Request::from_tool("universe_propose", prepared)?)?;
        let p = serde_json::from_value::<Proposal>(proposed["result"].clone())?;
        self.finish_writing_check(input, args, ctx, result, p)
    }

    fn finish_writing_check(
        &mut self,
        input: CheckChanges,
        args: Value,
        ctx: Context,
        mut result: WritingCheck,
        p: Proposal,
    ) -> anyhow::Result<Value> {
        let admission = self.execute(Request::from_tool("universe_open_context", json!({"universe":input.universe,"continuity_id":ctx.frame.continuity,"revision":{"kind":"exact","revision_id":ctx.frame.revision},"represented_context":ctx.frame.context.record,"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))?)?;
        let admission_id = admission["result"]["context_id"].clone();
        let reference = json!({"proposal_id":p.proposal_id,"version":p.version,"digest":p.digest});
        let validation = self.execute(Request::from_tool("universe_validate", json!({"mode":"proposal","universe":input.universe,"context_id":admission_id,"proposal_reference":reference,"check_scope":"universe"}))?)?;
        let impact = self.execute(Request::from_tool("universe_get_impact", json!({"mode":"proposal","universe":input.universe,"context_id":admission_id,"proposal_reference":reference,"scope":"universe","byte_budget":65536}))?)?;
        result.candidate_handle = Some(p.proposal_id.to_string());
        let execution = &validation["result"]["execution"];
        let complete = validation["result"]["kind"] == "evaluated"
            && execution["coverage"] == "complete"
            && execution["unsupported_capabilities"]
                .as_array()
                .is_some_and(Vec::is_empty)
            && execution["findings"].is_array()
            && impact["delivery"]["complete"] == true
            && impact["result"]["coverage"] == "complete";
        let unresolved = execution["findings"].as_array().is_some_and(|f| {
            f.iter()
                .any(|f| f["outcome"] != "supported" || f["coverage"] != "complete")
        });
        let conflict = execution["findings"].as_array().is_some_and(|f| {
            f.iter()
                .any(|f| f["outcome"] == "conflicting" || f["outcome"] == "refuted")
        }) || execution["opposing_evidence"]
            .as_array()
            .is_some_and(|f| !f.is_empty());
        result.status = if !complete {
            "incomplete"
        } else if conflict {
            "conflict"
        } else if unresolved || !result.clarifications.is_empty() {
            "needs_clarification"
        } else {
            "checked_candidate"
        }
        .into();
        result.validation = Some(validation["result"].clone());
        result.impact = Some(impact["result"].clone());
        self.wrap(
            &args,
            Some(ctx.frame),
            None,
            true,
            None,
            serde_json::to_value(result)?,
        )
    }
}

impl Workflow<'_> {
    pub(super) fn read_writing_facts(
        &mut self,
        input: universe_protocol::writing::ReadFacts,
    ) -> anyhow::Result<Value> {
        let ctx = self.context(&input.context_id)?;
        let args = serde_json::to_value(&input)?;
        let all = self
            .kernel
            .records(&ctx.frame.continuity, &ctx.frame.revision)?;
        let mut visible = self.visible_ids(&all)?;
        visible = visible
            .intersection(&perspective_ids(&all, &ctx.frame)?)
            .cloned()
            .collect();
        let records: Vec<_> = all
            .into_iter()
            .filter(|r| visible.contains(&r.identity.record_id))
            .collect();
        let world_focus = match &input.world {
            Some(world) => self.focus(&json!({"world":world}), &records)?,
            None => None,
        };
        let label = |id: &RecordId| {
            records
                .iter()
                .find(|r| &r.identity.record_id == id)
                .and_then(|r| match &r.payload {
                    Payload::Entity(e) => e
                        .labels
                        .values()
                        .next()
                        .cloned()
                        .or_else(|| e.names.first().map(|n| n.text.clone())),
                    Payload::EntityType(t) => Some(t.name.clone()),
                    Payload::ActionDefinition(a) => Some(a.key.clone()),
                    Payload::Property(p) => Some(p.key.clone()),
                    Payload::Unit(u) => Some(u.key.clone()),
                    Payload::World(w) => Some(w.selector.clone()),
                    Payload::Calendar(c) => Some(
                        c.labels
                            .values()
                            .next()
                            .cloned()
                            .unwrap_or_else(|| c.key.clone()),
                    ),
                    _ => None,
                })
        };
        let clocks:Vec<_>=records.iter().filter(|r|r.identity.record_id==ctx.frame.context.record).filter_map(|r| if let Payload::RepresentedContext(c)=&r.payload {
            c.chronology.as_ref().map(|clock| json!({"calendar_id":clock.calendar,"calendar_name":label(&RecordId::parse(&clock.calendar.as_str().replacen("cal_","rec_",1)).expect("calendar record")),"current":clock.current,"first_interaction":clock.first_interaction,"units":clock.system}))
        } else { None }).collect();
        let mut objects = vec![];
        for name in &input.object_names {
            let matches: Vec<_> = records
                .iter()
                .filter(|r| match &r.payload {
                    Payload::Entity(e) => {
                        e.labels.values().any(|v| v == name)
                            || e.names.iter().any(|n| {
                                n.text == *name
                                    && universe_rules::events::applies(
                                        &n.validity,
                                        &ctx.frame.time,
                                        &records,
                                    ) != Some(false)
                            })
                    }
                    Payload::EntityType(t) => {
                        t.name == *name || t.key == *name || t.labels.values().any(|v| v == name)
                    }
                    _ => false,
                })
                .collect();
            if matches.len() != 1 {
                objects.push(json!({"name":name,"identity":if matches.is_empty(){"not_found"}else{"ambiguous"},"matches":matches.len(),"coverage":if self.scope.is_some() || !matches!(ctx.frame.perspective,Perspective::Author){"restricted"}else{"complete"},"facts":[],"unknowns":["No unique visible identity established; this does not introduce an object."]}));
                continue;
            }
            let mut state_args = json!({"universe":input.universe,"context_id":input.context_id,"entity_ids":[matches[0].identity.record_id],"predicate_filters":[]});
            if let Some(world) = &input.world {
                state_args["world"] = json!(world);
            }
            let state = self.execute(Request::from_tool("universe_get_state", state_args)?)?;
            let state: State = serde_json::from_value(state["result"].clone())?;
            let object = state.objects.first().ok_or_else(denied)?;
            let mut facts = vec![];
            let mut initial = vec![];
            let mut inherited = vec![];
            for (group, rows) in [
                ("instance", &object.instance_facts),
                ("shared", &object.shared_attributes),
                ("initial_candidate", &object.initial_value_candidates),
            ] {
                for row in rows {
                    let Payload::Assertion(assertion) = &row.record.payload else {
                        continue;
                    };
                    let Some(proposition) = object
                        .dependencies
                        .iter()
                        .find(|r| r.identity.record_id == assertion.proposition.record)
                    else {
                        continue;
                    };
                    let Payload::Proposition(proposition) = &proposition.payload else {
                        continue;
                    };
                    let Some(property) = object
                        .dependencies
                        .iter()
                        .find(|r| r.identity.record_id == proposition.predicate.record)
                    else {
                        continue;
                    };
                    let Payload::Property(property) = &property.payload else {
                        continue;
                    };
                    let value = proposition
                        .value
                        .as_ref()
                        .and_then(|v| plain_value(v, &label));
                    let conflicts: Vec<_> = object
                        .conflicts
                        .iter()
                        .filter(|c| {
                            c.initial_values == (group == "initial_candidate")
                                && c.assertions.contains(&row.record.record_version_id)
                        })
                        .collect();
                    let outcome = if row.applicability != Some(true)
                        || !row.unknowns.is_empty()
                        || value.is_none()
                    {
                        "unknown"
                    } else if conflicts.iter().any(|c| c.applicability == Some(true)) {
                        "conflicting"
                    } else if !conflicts.is_empty() {
                        "unknown"
                    } else if assertion.polarity == universe_domain::scope::Polarity::Support {
                        "supported"
                    } else {
                        "refuted"
                    };
                    let scope = match &assertion.scope.applicability {
                        Applicability::UniverseWide => "universe".into(),
                        Applicability::Unspecified => "unspecified".into(),
                        Applicability::Conditional => "conditional, unresolved".into(),
                        Applicability::Worlds { world_ids } => world_ids
                            .iter()
                            .map(|id| {
                                label(
                                    &RecordId::parse(&id.as_str().replacen("wld_", "rec_", 1))
                                        .expect("world record"),
                                )
                                .unwrap_or_else(|| "unknown world".into())
                            })
                            .collect::<Vec<_>>()
                            .join(", "),
                    };
                    let item = json!({"fact_handle":if assertion.established_by.is_none(){Some(row.record.record_version_id.to_string())}else{None},"property":property.key,"value":value,"state":outcome,"group":group,"scope":scope,"time":plain_time(&serde_json::to_value(&assertion.validity)?,&label),"unknowns":row.unknowns,"value_type":serde_json::to_value(&property.value)?["kind"],"unit":match proposition.value.as_ref(){Some(universe_domain::value::Value::Quantity{unit,..})=>unit.to_record_id().ok().and_then(|id|label(&id)),_=>None},"unsupported_plain_value":value.is_none(),"multiple_values_allowed":property.multiplicity==universe_domain::records::Multiplicity::Multiple,"exclusive":property.exclusive});
                    if group == "initial_candidate" {
                        initial.push(item)
                    } else if group == "shared" {
                        inherited.push(item)
                    } else {
                        facts.push(item)
                    }
                }
            }
            for derived in state
                .derived
                .iter()
                .filter(|d| d.subject.record == object.identity.identity.record_id)
            {
                if let Some(Payload::Property(property)) = records
                    .iter()
                    .find(|r| r.identity.record_id == derived.predicate.record)
                    .map(|r| &r.payload)
                {
                    let value = plain_value(&derived.value, &label);
                    facts.push(json!({"property":property.key,"state":if value.is_some(){"supported"}else{"unknown"},"value":value,"value_type":serde_json::to_value(&property.value)?["kind"],"unit":match &derived.value{universe_domain::value::Value::Quantity{unit,..}=>unit.to_record_id().ok().and_then(|id|label(&id)),_=>None},"unsupported_plain_value":value.is_none(),"group":"derived","scope":"pinned research context","time":plain_time(&serde_json::to_value(&ctx.frame.time)?,&label),"unknowns":if value.is_some(){vec![]}else{vec!["plain value presentation unavailable"]}}));
                }
            }
            let occurred_events:Vec<_>=records.iter().filter_map(|r|if let Payload::Event(e)=&r.payload {
                (e.occurrence==universe_domain::records::OccurrenceMode::Occurred && e.participants.iter().any(|p|p.record.record==matches[0].identity.record_id)).then(||json!({"handle":r.identity.record_id,"time":plain_time(&json!(e.time),&label),"action":e.action.as_ref().and_then(|a|label(&a.record)),"participants":e.participants.iter().map(|p|json!({"role":p.role,"object":label(&p.record.record)})).collect::<Vec<_>>(),"requires_knowledge":e.preconditions.iter().filter_map(|condition|if let universe_domain::expr::Expr::Attitude{holder,proposition,attitude:EpistemicAttitudeKind::Knows}=condition {records.iter().find(|r|r.identity.record_id==proposition.record).and_then(|r|if let Payload::Proposition(p)=&r.payload {Some(json!({"holder":label(&holder.record),"claim":{"subject":label(&p.subject.record),"property":label(&p.predicate.record),"value":p.value.as_ref().and_then(|v|plain_value(v,&label))}}))}else{None})}else{None}).collect::<Vec<_>>(),"worlds":e.worlds.iter().filter_map(|w|RecordId::parse(&w.as_str().replacen("wld_","rec_",1)).ok().and_then(|id|label(&id))).collect::<Vec<_>>()}))
            }else{None}).collect();
            objects.push(json!({"name":name,"identity":"resolved","kind":if matches!(matches[0].payload,Payload::EntityType(_)){"definition"}else{"instance"},"classification":object.ancestry.first().and_then(|r|label(&r.identity.record_id)),"ancestry":object.ancestry.iter().filter_map(|r|label(&r.identity.record_id)).collect::<Vec<_>>(),"ancestry_complete":object.ancestry_complete,"names":match &matches[0].payload {Payload::Entity(e) if matches!(ctx.frame.perspective,Perspective::Author)=>e.names.iter().filter(|n|universe_rules::events::applies(&n.validity,&ctx.frame.time,&records)!=Some(false)).map(|n|json!({"text":n.text,"language":n.language,"community":n.community,"role":n.role,"time":plain_time(&json!(n.validity),&label),"time_applicable":universe_rules::events::applies(&n.validity,&ctx.frame.time,&records)})).collect::<Vec<_>>(),_=>vec![]},"facts":facts,"occurred_events":occurred_events,"inherited_attributes":inherited,"initial_value_candidates":initial,"coverage":object.coverage,"unknowns":object.unknowns,"state_coverage":state.coverage,"limitations":state.unsupported_capabilities}));
        }
        self.wrap(&args,Some(ctx.frame.clone()),world_focus,true,None,json!({"objects":objects,"clocks":clocks,"research_time":plain_time(&serde_json::to_value(&ctx.frame.time)?,&label),"coverage":if self.scope.is_some() || !matches!(ctx.frame.perspective,Perspective::Author){"restricted"}else{"bounded"},"limitation":"Plain projection of existing effective evidence; absence is unknown, initial candidates are not current facts, and bounded evidence is not universal prose completeness."}))
    }
}

pub(super) fn plain_value(
    value: &universe_domain::value::Value,
    label: &impl Fn(&RecordId) -> Option<String>,
) -> Option<Value> {
    use universe_domain::value::Value as V;
    Some(match value {
        V::Text { text } => json!(text),
        V::Boolean { value } => json!(value),
        V::Integer { digits } | V::Decimal { digits } => serde_json::from_str::<Value>(digits)
            .ok()
            .filter(Value::is_number)?,
        V::EntityRef { record } => json!({"object":label(&record.record)?}),
        V::Quantity { value, unit } => {
            json!({"amount":plain_value(value,label)?.as_number()?,"unit":label(&unit.to_record_id().ok()?)?})
        }
        _ => return None,
    })
}
pub(super) fn plain_time(value: &Value, label: &impl Fn(&RecordId) -> Option<String>) -> String {
    let calendar = value
        .get("calendar")
        .and_then(Value::as_str)
        .and_then(|v| RecordId::parse(&v.replacen("cal_", "rec_", 1)).ok())
        .and_then(|id| label(&id))
        .unwrap_or_else(|| "unresolved clock".into());
    let bound = |v: &Value| {
        v["value"]
            .as_str()
            .unwrap_or(match v["kind"].as_str() {
                Some("unbounded") => "unbounded",
                _ => "unknown",
            })
            .to_string()
    };
    match value["kind"].as_str(){
        Some("timeless")=>"all story-time validities (author research)".into(),
        Some("at")=>plain_time(&value["time"],label),
        Some("exact")=>format!("{calendar}: {}",value["value"].as_str().unwrap_or("unknown")),
        Some("calendar_interval")=>format!("{calendar}: from {} inclusive to {} exclusive",bound(&value["start"]),bound(&value["end"])),
        Some("instant")=>plain_time(&value["at"],label),
        Some("unspecified")=>"no temporal claim stated".into(),
        _=>"temporal applicability requires authored context; no plain exact-time presentation available".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn small_changes_compile_and_check_without_publishing_or_inventing_time() {
        let dir = tempfile::tempdir().unwrap();
        let u = UniverseId::parse("unv_000000000000000000000001").unwrap();
        let c = ContinuityId::parse("cont_000000000000000000000001").unwrap();
        let principal = PrincipalId::parse("prn_000000000000000000000001").unwrap();
        let profile = ProfileId::parse("prf_000000000000000000000001").unwrap();
        let context = RecordId::parse("rec_000000000000000000000001").unwrap();
        let mut kernel = Kernel::create(
            &dir.path().join("world.sqlite"),
            u.clone(),
            "Writing",
            c.clone(),
            &principal,
        )
        .unwrap();
        let payload: Payload = serde_json::from_value(json!({"record_kind":"represented_context","universe":u,"kind":{"kind":"objective"},"labels":{}})).unwrap();
        let row = RecordVersion::build(
            RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(u.clone(), context.clone(), payload.kind()),
            payload,
        )
        .unwrap();
        let revision = kernel
            .commit(&CommitInput {
                universe: u,
                continuity: c.clone(),
                expected_head: kernel.head(&c).unwrap(),
                principal,
                decision: "seed".into(),
                reason: "context".into(),
                idempotency_key: "seed".into(),
                changes: vec![Assignment {
                    record_id: context.clone(),
                    expected: None,
                    next: Some(row),
                }],
            })
            .unwrap();
        let mut workflow = Workflow {
            kernel: &mut kernel,
            authority: None,
            principal: Principal {
                id: profile.clone(),
                author: false,
            },
            approval_author: profile,
            scope: None,
            permissions: (true, false, true),
            name: "Writing".into(),
        };
        let opened=workflow.execute(Request::from_tool("universe_open_context",json!({"universe":"Writing","continuity_id":c,"revision":{"kind":"head"},"represented_context":context,"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"})).unwrap()).unwrap();
        let args = json!({"universe":"Writing","context_id":opened["result"]["context_id"],"changes":[{"name":"Mara","introduce":true,"facts":[{"property":"age","value":30,"scope":"universe"}]},{"name":"Blue pistol","introduce":true,"facts":[{"property":"owner","value":{"object":"Mara"}}]},{"name":"Imagined dragon","facts":[{"property":"colour","value":"red","statement":"belief"}]}]});
        let result = workflow
            .execute(Request::from_tool("universe_check_changes", args.clone()).unwrap())
            .unwrap();
        assert!(result["result"]["candidate_handle"].is_string(), "{result}");
        assert_eq!(result["result"]["validation"]["kind"], "evaluated");
        assert_eq!(result["result"]["clarifications"], json!([]));
        assert_eq!(result["result"]["unknowns"].as_array().unwrap().len(), 2);
        assert_eq!(result["result"]["excluded"].as_array().unwrap().len(), 1);
        assert_eq!(workflow.kernel.head(&c).unwrap(), revision);
        let held_args = json!({"universe":"Writing","context_id":opened["result"]["context_id"],"changes":[{"name":"Seal","introduce":true,"facts":[{"property":"owner","value":{"object":"Guessed Iven"}}]},{"name":"Guessed Iven","introduce":true}],"questions":["Who is He?"]});
        let workflow_keys_before_hold = workflow.kernel.workflow_keys("").unwrap();
        let held = workflow
            .execute(Request::from_tool("universe_check_changes", held_args.clone()).unwrap())
            .unwrap();
        assert_eq!(held["result"]["status"], "needs_clarification");
        assert!(held["result"]["candidate_handle"].is_null());
        assert!(held["result"]["validation"].is_null());
        assert!(held["result"]["impact"].is_null());
        assert_eq!(
            workflow.kernel.workflow_keys("").unwrap(),
            workflow_keys_before_hold
        );
        // Same corrected delta must remain able to reserve and validate its new identities.
        let mut corrected = held_args;
        corrected["questions"] = json!([]);
        let corrected = workflow
            .execute(Request::from_tool("universe_check_changes", corrected).unwrap())
            .unwrap();
        assert!(corrected["result"]["candidate_handle"].is_string());
        assert_eq!(corrected["result"]["validation"]["kind"], "evaluated");
        assert_eq!(workflow.kernel.head(&c).unwrap(), revision);
        let again = workflow
            .execute(Request::from_tool("universe_check_changes", args).unwrap())
            .unwrap();
        assert_eq!(
            result["result"]["candidate_handle"],
            again["result"]["candidate_handle"]
        );
        assert_eq!(workflow.kernel.head(&c).unwrap(), revision);
        let excluded=workflow.execute(Request::from_tool("universe_check_changes",json!({"universe":"Writing","context_id":opened["result"]["context_id"],"changes":[{"name":"Dreamed dragon","facts":[{"property":"exists","value":true,"statement":"hypothetical"}]}]})).unwrap()).unwrap();
        assert_eq!(excluded["result"]["status"], "no_changes");
        assert!(excluded["result"]["candidate_handle"].is_null());
        let ambiguous=workflow.execute(Request::from_tool("universe_check_changes",json!({"universe":"Writing","context_id":opened["result"]["context_id"],"changes":[{"name":"Pistol","introduce":true},{"name":"Pistol","introduce":true},{"name":"Box","introduce":true,"facts":[{"property":"contains","value":{"object":"Pistol"}}]}]})).unwrap()).unwrap();
        assert_eq!(ambiguous["result"]["status"], "needs_clarification");
        assert!(ambiguous["result"]["candidate_handle"].is_null());
        assert!(ambiguous["result"]["validation"].is_null());
        assert!(ambiguous["result"]["clarifications"]
            .as_array()
            .unwrap()
            .iter()
            .any(|q| q.as_str().unwrap().contains("Which object")));
        workflow.permissions.0 = false;
        let retry = json!({"universe":"Writing","context_id":opened["result"]["context_id"],"changes":[{"name":"Mara","introduce":true,"facts":[{"property":"age","value":30,"scope":"universe"}]},{"name":"Blue pistol","introduce":true,"facts":[{"property":"owner","value":{"object":"Mara"}}]},{"name":"Imagined dragon","facts":[{"property":"colour","value":"red","statement":"belief"}]}]});
        assert!(workflow
            .execute(Request::from_tool("universe_check_changes", retry).unwrap())
            .is_err());
        assert_eq!(workflow.kernel.head(&c).unwrap(), revision);
        workflow.permissions.0 = true;
        let p: StoredProposal = workflow
            .load(&format!(
                "proposal:{}:{:020}",
                result["result"]["candidate_handle"].as_str().unwrap(),
                1
            ))
            .unwrap();
        let next = workflow
            .kernel
            .commit(&CommitInput {
                universe: workflow.kernel.universe().clone(),
                continuity: c.clone(),
                expected_head: revision.clone(),
                principal: PrincipalId::parse("prn_000000000000000000000001").unwrap(),
                decision: "fixture canon".into(),
                reason: "functional lookup regression".into(),
                idempotency_key: "fixture publish".into(),
                changes: p.changes.clone(),
            })
            .unwrap();
        let pinned=workflow.execute(Request::from_tool("universe_read_facts",json!({"universe":"Writing","context_id":opened["result"]["context_id"],"object_names":["Mara"]})).unwrap()).unwrap();
        assert_eq!(pinned["result"]["objects"][0]["identity"], "not_found");
        let fresh=workflow.execute(Request::from_tool("universe_open_context",json!({"universe":"Writing","continuity_id":c,"revision":{"kind":"head"},"represented_context":context,"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"})).unwrap()).unwrap();
        let read=workflow.execute(Request::from_tool("universe_read_facts",json!({"universe":"Writing","context_id":fresh["result"]["context_id"],"object_names":["Mara","Blue pistol","Dreamed dragon"]})).unwrap()).unwrap();
        assert_eq!(read["result"]["objects"][0]["facts"][0]["property"], "age");
        assert_eq!(read["result"]["objects"][0]["facts"][0]["value"], json!(30));
        assert_eq!(
            read["result"]["objects"][0]["facts"][0]["state"],
            "supported"
        );
        assert_eq!(
            read["result"]["objects"][1]["facts"][0]["value"],
            json!({"object":"Mara"})
        );
        assert_eq!(read["result"]["objects"][2]["identity"], "not_found");
        let equal=workflow.execute(Request::from_tool("universe_check_changes",json!({"universe":"Writing","context_id":fresh["result"]["context_id"],"changes":[{"name":"Mara","facts":[{"property":"age","value":30,"scope":"universe"}]}]})).unwrap()).unwrap();
        assert_eq!(equal["result"]["status"], "no_changes");
        assert!(equal["result"]["candidate_handle"].is_null());
        let contrary=workflow.execute(Request::from_tool("universe_check_changes",json!({"universe":"Writing","context_id":fresh["result"]["context_id"],"changes":[{"name":"Mara","facts":[{"property":"age","value":30,"negated":true,"scope":"universe"}]}]})).unwrap()).unwrap();
        assert_eq!(contrary["result"]["status"], "incomplete", "{contrary}");
        assert_eq!(
            contrary["result"]["validation"]["execution"]["opposing_evidence"][0]["kind"],
            "definite"
        );
        assert_eq!(workflow.kernel.head(&c).unwrap(), next);
    }
}
