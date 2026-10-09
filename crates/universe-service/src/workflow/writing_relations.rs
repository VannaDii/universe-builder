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
