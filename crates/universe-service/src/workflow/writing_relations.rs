//! Named finite adapters for existing relation occurrences and authored maxima.
use super::*;
use universe_protocol::writing::*;

pub(super) fn relation<'a>(
    rows: &'a [RecordVersion],
    name: &str,
) -> anyhow::Result<(&'a RecordVersion, &'a RelationDef)> {
    let found: Vec<_> = rows
        .iter()
        .filter_map(|r| {
            if let Payload::Relation(d) = &r.payload {
                (d.key == name || d.labels.values().any(|v| v == name)).then_some((r, d))
            } else {
                None
            }
        })
        .collect();
    match found.as_slice() {
        [one] => Ok(*one),
        _ => anyhow::bail!("Which exact authored relationship is '{name}'?"),
    }
}
fn object(rows: &[RecordVersion], name: &str, frame: &Frame) -> anyhow::Result<RecordId> {
    super::writing_connected::object(rows, name, frame)
        .ok_or_else(|| anyhow::anyhow!("Which exact authored participant is '{name}'?"))
}
fn scope(
    w: &Workflow<'_>,
    rows: &[RecordVersion],
    ctx: &Context,
    text: &str,
) -> anyhow::Result<universe_domain::scope::Scope> {
    Ok(universe_domain::scope::Scope {
        context: ctx.frame.context.clone(),
        applicability: super::writing_contracts::applicability(w, text, rows)?,
        realm: None,
    })
}
pub(super) fn supported_limit(r: &Rule) -> bool {
    r.relation_cardinality.is_some()
        && r.executable
        && r.kind == RuleKind::PhysicalConstraint
        && r.commit_policy == CommitPolicy::AlwaysBlock
        && r.applicability == Applicability::UniverseWide
        && r.validity == universe_domain::scope::Validity::Unspecified
        && r.subject_types.is_empty()
        && r.target_predicates.is_empty()
        && r.expression == universe_domain::expr::Expr::Lit { value: true }
        && r.capabilities == [crate::cardinality::CAPABILITY]
        && r.knowledge_boundary.is_none()
        && r.knowledge_policy.is_none()
        && r.channel_chronology.is_none()
}
impl Workflow<'_> {
    pub(super) fn writing_relations(
        &self,
        input: &CheckChanges,
        ctx: &Context,
        base: &[RecordVersion],
        ops: &mut Vec<Value>,
        result: &mut WritingCheck,
    ) -> anyhow::Result<()> {
        if input.relation_definitions.is_empty()
            && input.relation_limits.is_empty()
            && input.relationships.is_empty()
            && input.relation_corrections.is_empty()
            && input.relation_limit_corrections.is_empty()
            && input.relationship_corrections.is_empty()
            && input.relationship_endings.is_empty()
        {
            return Ok(());
        }
        let mut rows =
            super::writing_connected::candidate_records(self.kernel.universe(), ctx, base, ops)?;
        let u = self.kernel.universe();
        for d in &input.relation_definitions {
            let build = || -> anyhow::Result<Value> {
                if !d.introduce||d.name.trim().is_empty()||rows.iter().any(|r|matches!(&r.payload,Payload::Relation(old)if old.key==d.name||old.labels.values().any(|n|n==&d.name))){anyhow::bail!("Explicitly introduce a unique relationship name; existing definitions are not replaced.")}
                let mut names = BTreeSet::new();
                if d.roles.is_empty()
                    || d.roles
                        .iter()
                        .any(|r| r.name.trim().is_empty() || !names.insert(&r.name))
                {
                    anyhow::bail!("Declare distinct nonempty relationship role names.")
                }
                Ok(
                    json!({"kind":"define_relation","client_ref":RecordId::generate(&mut rand::rng()),"record":{"namespace":"authoring","key":d.name,"labels":{},"roles":d.roles.iter().map(|r|json!({"name":r.name,"participantTypes":[],"multiplicity":if r.multiple{"multiple"}else{"single"},"ordered":false})).collect::<Vec<_>>()}}),
                )
            };
            match build() {
                Ok(op) => {
                    ops.push(op);
                    rows = super::writing_connected::candidate_records(u, ctx, base, ops)?;
                    result.additions.push(format!(
                        "Author relationship declaration: {}; private contract review required.",
                        d.name
                    ));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        for l in &input.relation_limits {
            let build = || -> anyhow::Result<Value> {
                if l.name.trim().is_empty()
                    || rows
                        .iter()
                        .any(|r| matches!(&r.payload,Payload::Rule(r)if r.key==l.name))
                {
                    anyhow::bail!(
                        "Choose a unique explicit limit name; existing policies are not replaced."
                    )
                }
                let (record, d) = relation(&rows, &l.relation)?;
                if !d.roles.iter().any(|r| r.name == l.counted_role)
                    || matches!(&l.grouping,WritingRelationGrouping::Role{role}if !d.roles.iter().any(|r|&r.name==role))
                {
                    anyhow::bail!(
                        "Grouping and counted roles must be actual declared relationship roles."
                    )
                }
                let time = super::writing_connected::time(&ctx.frame, &rows, &l.at_tick)?;
                let validity = super::writing_contracts::validity(&time, &l.lifetime)?;
                Ok(
                    json!({"kind":"define_rule","client_ref":RecordId::generate(&mut rand::rng()),"record":{"namespace":"authoring","key":l.name,"labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"targetPredicates":[],"expression":{"kind":"lit","value":true},"capabilities":[crate::cardinality::CAPABILITY],"executable":true,"validity":{"kind":"unspecified"},"relationCardinality":{"relation":{"universe":u,"record":record.identity.record_id},"grouping":l.grouping,"countedRole":l.counted_role,"maximum":l.maximum,"scope":scope(self,&rows,ctx,&l.scope)?,"validity":validity}}}),
                )
            };
            match build() {
                Ok(op) => {
                    ops.push(op);
                    rows = super::writing_connected::candidate_records(u, ctx, base, ops)?;
                    result.additions.push(format!("Author relationship limit: {}; maximum {}; private contract review required.",l.name,l.maximum));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        let mut revised = BTreeSet::new();
        for patch in &input.relation_corrections {
            let build = || -> anyhow::Result<Value> {
                if patch.reason.trim().is_empty() || patch.roles.is_empty() {
                    anyhow::bail!("Specify changed role fields and the author's reason; omitted fields stay unchanged.")
                }
                let (original, definition) = relation(base, &patch.name)?;
                let mut replacement = definition.clone();
                let mut seen = BTreeSet::new();
                for role in &patch.roles {
                    if !seen.insert(&role.name)
                        || (role.multiple.is_none()
                            && role.ordered.is_none()
                            && role.participant_types.is_none())
                    {
                        anyhow::bail!(
                            "Specify each changed declared role once with explicit changed fields."
                        )
                    }
                    let target = replacement
                        .roles
                        .iter_mut()
                        .find(|r| r.name == role.name)
                        .ok_or_else(|| {
                            anyhow::anyhow!(
                                "'{}' is not a declared role of this relationship.",
                                role.name
                            )
                        })?;
                    if let Some(multiple) = role.multiple {
                        target.multiplicity = if multiple {
                            Multiplicity::Multiple
                        } else {
                            Multiplicity::Single
                        };
                    }
                    if let Some(ordered) = role.ordered {
                        target.ordered = ordered;
                    }
                    if let Some(types) = &role.participant_types {
                        target.participant_types=types.iter().map(|name| {
                            let matches:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::EntityType(d) if d.key==*name||d.name==*name||d.labels.values().any(|v|v==name))).collect();
                            let [record]=matches.as_slice() else { anyhow::bail!("Which exact participant type is '{}' ?",name); };
                            Ok(record.identity.record_id.clone())
                        }).collect::<anyhow::Result<Vec<_>>>()?;
                    }
                }
                Ok(
                    json!({"kind":"revise_definition","record":{"universe":u,"record":original.identity.record_id},"expected_version":original.record_version_id,"replacement":Payload::Relation(replacement)}),
                )
            };
            match build() {
                Ok(op) => {
                    if !revised.insert(op["record"]["record"].clone().to_string()) {
                        result
                            .clarifications
                            .push("Revise each relationship contract only once per delta.".into());
                        continue;
                    }
                    ops.push(op);
                    rows = super::writing_connected::candidate_records(u, ctx, base, ops)?;
                    result.additions.push(format!("Relationship contract correction: {} — {}; private contract review required.",patch.name,patch.reason));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        for patch in &input.relation_limit_corrections {
            let build = || -> anyhow::Result<Value> {
                if patch.reason.trim().is_empty()
                    || (patch.maximum.is_none()
                        && patch.grouping.is_none()
                        && patch.counted_role.is_none()
                        && patch.scope.is_none()
                        && patch.at_tick.is_none()
                        && patch.lifetime.is_none())
                {
                    anyhow::bail!("Specify changed limit fields and the author's reason.")
                }
                let matches: Vec<_> = base
                    .iter()
                    .filter_map(|r| match &r.payload {
                        Payload::Rule(d)
                            if d.key == patch.name
                                || d.labels.values().any(|v| v == &patch.name) =>
                        {
                            Some((r, d))
                        }
                        _ => None,
                    })
                    .collect();
                let [(original, rule)] = matches.as_slice() else {
                    anyhow::bail!(
                        "Which exact authored relationship limit is '{}' ?",
                        patch.name
                    );
                };
                if !supported_limit(rule) {
                    anyhow::bail!("This relationship limit requires advanced contract review; its metadata will not be discarded.")
                }
                let mut replacement = (*rule).clone();
                let limit = replacement.relation_cardinality.as_mut().unwrap();
                let def = rows
                    .iter()
                    .find_map(|r| {
                        if r.identity.record_id == limit.relation.record {
                            if let Payload::Relation(d) = &r.payload {
                                Some(d)
                            } else {
                                None
                            }
                        } else {
                            None
                        }
                    })
                    .ok_or_else(|| {
                        anyhow::anyhow!(
                            "Retrieve the relationship definition before changing its limit."
                        )
                    })?;
                if let Some(max) = patch.maximum {
                    limit.maximum = max;
                }
                if let Some(grouping) = &patch.grouping {
                    limit.grouping = serde_json::from_value(serde_json::to_value(grouping)?)?;
                }
                if let Some(role) = &patch.counted_role {
                    limit.counted_role = role.clone();
                }
                if !def.roles.iter().any(|r| r.name == limit.counted_role)
                    || matches!(&limit.grouping,universe_domain::records::CardinalityKey::Role{role}if !def.roles.iter().any(|r|&r.name==role))
                {
                    anyhow::bail!(
                        "Grouping and counted roles must be actual declared relationship roles."
                    )
                }
                if let Some(text) = &patch.scope {
                    limit.scope.applicability =
                        super::writing_contracts::applicability(self, text, &rows)?;
                }
                match (&patch.at_tick,&patch.lifetime) {
                    (None,None)=>{},
                    (Some(_),Some(lifetime))=>{let time=super::writing_connected::time(&ctx.frame,&rows,&patch.at_tick)?;limit.validity=super::writing_contracts::validity(&time,lifetime)?;},
                    _=>anyhow::bail!("Time correction requires both explicit tick and lifetime; omission preserves existing validity."),
                }
                Ok(
                    json!({"kind":"revise_definition","record":{"universe":u,"record":original.identity.record_id},"expected_version":original.record_version_id,"replacement":Payload::Rule(replacement)}),
                )
            };
            match build() {
                Ok(op) => {
                    if !revised.insert(op["record"]["record"].clone().to_string()) {
                        result
                            .clarifications
                            .push("Revise each relationship contract only once per delta.".into());
                        continue;
                    }
                    ops.push(op);
                    rows = super::writing_connected::candidate_records(u, ctx, base, ops)?;
                    result.additions.push(format!(
                        "Relationship limit correction: {} — {}; private contract review required.",
                        patch.name, patch.reason
                    ));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        let mut edited = BTreeSet::new();
        for correction in &input.relationship_corrections {
            let mut build = || -> anyhow::Result<Vec<Value>> {
                if correction.reason.trim().is_empty() {
                    anyhow::bail!("Explain the author's relationship correction.")
                }
                let (record, assertion, proposition, definition) =
                    authored(base, &correction.relationship_handle, &ctx.frame)?;
                if !edited.insert(record.identity.record_id.clone()) {
                    anyhow::bail!(
                        "Submit only one correction or ending for each relationship in a delta."
                    )
                }
                let mut replacement = proposition.clone();
                for (role, participants) in &correction.participants {
                    let def = definition
                        .roles
                        .iter()
                        .find(|r| &r.name == role)
                        .ok_or_else(|| {
                            anyhow::anyhow!("'{role}' is not a declared role of this relationship.")
                        })?;
                    if def.multiplicity == Multiplicity::Single && participants.len() > 1 {
                        anyhow::bail!("Role '{role}' permits only one participant per occurrence.")
                    }
                    replacement.roles.retain(|r| &r.role != role);
                    for name in participants {
                        replacement.roles.push(PropositionRole {
                            role: role.clone(),
                            participant: RecordRef::new(
                                u.clone(),
                                object(&rows, name, &ctx.frame)?,
                            ),
                        });
                    }
                }
                if replacement == *proposition {
                    return Ok(vec![]);
                }
                let id = RecordId::generate(&mut rand::rng());
                let mut next = assertion.clone();
                next.proposition = RecordRef::new(u.clone(), id.clone());
                next.basis = universe_domain::scope::EvidenceBasis::ImportedClaim;
                Ok(vec![
                    json!({"kind":"define_proposition","client_ref":id,"record":replacement}),
                    json!({"kind":"supersede_assertion","record":{"universe":u,"record":record.identity.record_id},"expected_version":record.record_version_id,"replacement":next,"rationale":correction.reason}),
                ])
            };
            match build() {
                Ok(changes) if changes.is_empty() => result
                    .unchanged
                    .push("Relationship participants unchanged.".into()),
                Ok(changes) => {
                    ops.extend(changes);
                    rows = super::writing_connected::candidate_records(u, ctx, base, ops)?;
                    result.additions.push(format!(
                        "Authored relationship participant correction: {}",
                        correction.reason
                    ));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        for ending in &input.relationship_endings {
            let mut build = || -> anyhow::Result<Value> {
                if ending.reason.trim().is_empty() {
                    anyhow::bail!("Explain the author's relationship ending.")
                }
                let (record, assertion, _, _) =
                    authored(base, &ending.relationship_handle, &ctx.frame)?;
                if !edited.insert(record.identity.record_id.clone()) {
                    anyhow::bail!(
                        "Submit only one correction or ending for each relationship in a delta."
                    )
                }
                let universe_domain::scope::Validity::CalendarInterval { calendar, .. } =
                    &assertion.validity
                else {
                    anyhow::bail!("Ending requires an authored calendar interval; instant or unspecified relationships require explicit historical correction.")
                };
                Ok(
                    json!({"kind":"end_assertion_at","record":{"universe":u,"record":record.identity.record_id},"expected_version":record.record_version_id,"at":{"kind":"exact","calendar":calendar,"value":ending.end_tick},"basis":{"kind":"imported_claim"}}),
                )
            };
            match build() {
                Ok(op) => {
                    ops.push(op);
                    rows = super::writing_connected::candidate_records(u, ctx, base, ops)?;
                    result.additions.push(format!(
                        "Authored relationship ends at {}: {}",
                        ending.end_tick, ending.reason
                    ));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        for r in &input.relationships {
            if !matches!(
                r.statement.as_str(),
                "objective" | "dialogue" | "belief" | "plan" | "hypothetical" | "metaphor"
            ) {
                result
                    .clarifications
                    .push("Unknown relationship statement intent.".into());
                continue;
            }
            if r.statement != "objective" {
                result
                    .excluded
                    .push(format!("{}: {} ({})", r.subject, r.relation, r.statement));
                continue;
            }
            let build = || -> anyhow::Result<Option<Value>> {
                let (record, d) = relation(&rows, &r.relation)?;
                let mut roles = vec![];
                for (role, participants) in &r.participants {
                    let def = d.roles.iter().find(|d| &d.name == role).ok_or_else(|| {
                        anyhow::anyhow!("'{role}' is not a declared role of '{}'.", r.relation)
                    })?;
                    if def.multiplicity == Multiplicity::Single && participants.len() > 1 {
                        anyhow::bail!("Role '{role}' permits only one participant per occurrence.")
                    }
                    for p in participants {
                        roles.push(PropositionRole {
                            role: role.clone(),
                            participant: RecordRef::new(u.clone(), object(&rows, p, &ctx.frame)?),
                        });
                    }
                }
                let proposition = Proposition {
                    predicate: RecordRef::new(u.clone(), record.identity.record_id.clone()),
                    subject: RecordRef::new(u.clone(), object(&rows, &r.subject, &ctx.frame)?),
                    roles,
                    value: None,
                    quantification: Quantification::Particular,
                    context: ctx.frame.context.clone(),
                };
                let time = super::writing_connected::time(&ctx.frame, &rows, &r.at_tick)?;
                let validity = super::writing_contracts::validity(&time, &r.lifetime)?;
                let scope = scope(self, &rows, ctx, &r.scope)?;
                let polarity = if r.negated {
                    universe_domain::scope::Polarity::Refutation
                } else {
                    universe_domain::scope::Polarity::Support
                };
                if rows.iter().any(|row|matches!(&row.payload,Payload::Proposition(p)if p==&proposition)&&rows.iter().any(|a|matches!(&a.payload,Payload::Assertion(a)if a.proposition.record==row.identity.record_id&&a.polarity==polarity&&a.scope==scope&&a.validity==validity&&a.attribute_mode==AttributeMode::Instance&&a.precision==universe_domain::scope::Precision::Exact&&a.alternatives.is_empty()))){return Ok(None)}
                let id = RecordId::generate(&mut rand::rng());
                Ok(Some(
                    json!({"kind":"record_relation","client_ref":id,"proposition":proposition,"assertion":{"attributeMode":"instance","proposition":{"universe":u,"record":id},"polarity":polarity,"scope":scope,"validity":validity,"persistence":"explicit_interval","precision":"exact","basis":{"kind":"imported_claim"}}}),
                ))
            };
            match build() {
                Ok(Some(op)) => {
                    ops.push(op);
                    rows = super::writing_connected::candidate_records(u, ctx, base, ops)?;
                    result
                        .additions
                        .push(format!("{}: relationship {}", r.subject, r.relation));
                }
                Ok(None) => result
                    .unchanged
                    .push(format!("{}: relationship {}", r.subject, r.relation)),
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        Ok(())
    }
}

pub(super) fn correctable(a: &Assertion) -> bool {
    a.established_by.is_none() && a.attribute_mode == AttributeMode::Instance
}
fn authored<'a>(
    rows: &'a [RecordVersion],
    handle: &str,
    frame: &Frame,
) -> anyhow::Result<(
    &'a RecordVersion,
    &'a Assertion,
    &'a Proposition,
    &'a RelationDef,
)> {
    let missing = || {
        anyhow::anyhow!(
            "Retrieve the current pinned authored relationship handle before editing it."
        )
    };
    let record = rows
        .iter()
        .find(|r| r.record_version_id.as_str() == handle)
        .ok_or_else(missing)?;
    let Payload::Assertion(a) = &record.payload else {
        return Err(missing());
    };
    if !correctable(a) || a.scope.context != frame.context {
        return Err(missing());
    }
    let p = rows
        .iter()
        .find_map(|r| {
            if r.identity.record_id == a.proposition.record {
                if let Payload::Proposition(p) = &r.payload {
                    Some(p)
                } else {
                    None
                }
            } else {
                None
            }
        })
        .ok_or_else(missing)?;
    let d = rows
        .iter()
        .find_map(|r| {
            if r.identity.record_id == p.predicate.record {
                if let Payload::Relation(d) = &r.payload {
                    Some(d)
                } else {
                    None
                }
            } else {
                None
            }
        })
        .ok_or_else(missing)?;
    Ok((record, a, p, d))
}
