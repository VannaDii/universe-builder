//! Private author decisions over existing proposal, provenance and commit workflows.
use super::*;
use std::collections::BTreeMap;
use universe_protocol::installation::AuthorWritingAction;

impl Workflow<'_> {
    pub fn author_writing(
        &mut self,
        universe: Selector,
        action: AuthorWritingAction,
    ) -> anyhow::Result<Value> {
        if !self.principal.author {
            return Err(denied());
        }
        match action {
            AuthorWritingAction::Inspect { candidate } => {
                let p = self.proposal(&candidate)?;
                if !matches!(p.proposal.submission, Submission::Submitted) {
                    return Err(ProtocolError::ApprovalStale.into());
                }
                if !p.author_origin
                    || !p
                        .proposal
                        .operations
                        .iter()
                        .any(|op| matches!(op, DomainOperation::AddSourceAnchor { .. }))
                {
                    return Err(ProtocolError::PolicyDenied {
                        message: "Reopen requires an author-prepared exact-source writing review."
                            .into(),
                    }
                    .into());
                }
                self.writing_author_review(&universe, &p.proposal)
            }
            AuthorWritingAction::Publish {
                candidate,
                validation_run,
                idempotency_key,
            } => {
                let p = self.proposal(&candidate)?;
                let args = json!({"universe":universe,"proposal_reference":candidate,"expected_base_revision":p.proposal.base_frame.revision,"validation_run":validation_run,"idempotency_key":idempotency_key});
                // A completed original receipt survives head changes; never approve a new operation on retry.
                let key = self.operation_key("commit", &idempotency_key);
                if self.kernel.workflow_get(&key)?.is_none() {
                    self.approve(&candidate, &validation_run)?;
                }
                self.execute(Request::from_tool("universe_commit", args)?)
            }
            AuthorWritingAction::Reject { candidate } => {
                let key = format!("writing-reject:{}", hash(&candidate));
                let receipt = self.operation_key("propose", &key);
                if self.kernel.workflow_get(&receipt)?.is_some() {
                    return Ok(serde_json::to_value(
                        self.operation(&receipt)?
                            .status
                            .proposal
                            .ok_or_else(denied)?,
                    )?);
                }
                let keys = self
                    .kernel
                    .workflow_keys(&format!("proposal:{candidate}:"))?;
                let p: StoredProposal = self.load(keys.last().ok_or_else(denied)?)?;
                let candidate = ProposalRef {
                    proposal_id: p.proposal.proposal_id.clone(),
                    version: p.proposal.version,
                    digest: p.proposal.digest.clone(),
                };
                let p = self.proposal(&candidate)?;
                self.writing_author_current(&p.proposal)?;
                let ctx = self.writing_author_context(&universe, &p.proposal)?;
                let result = self.execute(Request::from_tool("universe_propose", json!({"action":"withdraw","universe":universe,"context_id":ctx,"proposal_reference":candidate,"idempotency_key":key}))?)?;
                Ok(result["result"].clone())
            }
            AuthorWritingAction::Prepare {
                candidate,
                label,
                text,
            } => self.prepare_writing_source(universe, candidate, label, text, false, None),
            AuthorWritingAction::PrepareContracts {
                candidate,
                label,
                text,
            } => self.prepare_writing_source(universe, candidate, label, text, true, None),
            AuthorWritingAction::EditKnowledge {
                context_id,
                correction,
                label,
                text,
            } => {
                if text.trim().is_empty() || correction.reason.trim().is_empty() {
                    return Err(ProtocolError::invalid_argument(
                        "text/reason",
                        "Explicit author source and reason required",
                    )
                    .into());
                }
                let selected: Context = self.load(&format!("context:{context_id}"))?;
                if selected.expires < now() {
                    return Err(ProtocolError::ContextExpired.into());
                }
                if self.kernel.head(&selected.frame.continuity)? != selected.frame.revision {
                    return Err(ProtocolError::ApprovalStale.into());
                }
                let reopened = self.writing_author_context_frame(&universe, &selected.frame)?;
                let ctx = self.context(&reopened)?;
                let base = self
                    .kernel
                    .records(&ctx.frame.continuity, &ctx.frame.revision)?;
                let visible = self.visible_ids(&base)?;
                let rows: Vec<_> = base
                    .into_iter()
                    .filter(|r| visible.contains(&r.identity.record_id))
                    .collect();
                let correction=super::writing_dates::normalize(correction,&ctx.frame,&rows)?;
                let ops = super::writing_connected::attitude_edit(
                    self.kernel.universe(),
                    &rows,
                    &ctx.frame,
                    &correction,
                    true,
                )?;
                let key = format!(
                    "author-knowledge-edit:{}",
                    hash(&(&ctx.frame, &correction, &label, &text))
                );
                let receipt = self.operation_key("propose", &key);
                let candidate = if self.kernel.workflow_get(&receipt)?.is_some() {
                    self.operation(&receipt)?
                        .status
                        .proposal
                        .ok_or_else(denied)?
                } else {
                    let proposed=self.execute(Request::from_tool("universe_propose",json!({"action":"create","universe":universe,"context_id":reopened,"operations":ops,"submission":"draft","rationale":correction.reason,"idempotency_key":key}))?)?;
                    field::<Proposal>(&proposed, "result")?
                };
                self.prepare_writing_source(
                    universe,
                    candidate.proposal_id,
                    label,
                    text,
                    false,
                    Some(correction.reason),
                )
            }
            AuthorWritingAction::EstablishKnowledge {
                context_id,
                declaration,
                rationale,
                label,
                text,
            } => {
                if rationale.trim().is_empty() || text.trim().is_empty() {
                    return Err(ProtocolError::invalid_argument(
                        "rationale/text",
                        "Explicit author rationale and source required",
                    )
                    .into());
                }
                let selected: Context = self.load(&format!("context:{context_id}"))?;
                if selected.expires < now() {
                    return Err(ProtocolError::ContextExpired.into());
                }
                if self.kernel.head(&selected.frame.continuity)? != selected.frame.revision {
                    return Err(ProtocolError::ApprovalStale.into());
                }
                let reopened = self.writing_author_context_frame(&universe, &selected.frame)?;
                let ctx = self.context(&reopened)?;
                let base = self
                    .kernel
                    .records(&ctx.frame.continuity, &ctx.frame.revision)?;
                let visible = self.visible_ids(&base)?;
                let rows: Vec<_> = base
                    .into_iter()
                    .filter(|r| visible.contains(&r.identity.record_id))
                    .collect();
                let declaration=super::writing_dates::normalize(declaration,&ctx.frame,&rows)?;
                let policies: Vec<_> = rows
                    .iter()
                    .filter_map(|r| {
                        if let Payload::Rule(r) = &r.payload {
                            r.knowledge_policy
                                .as_ref()
                                .filter(|p| p.context == ctx.frame.context)
                        } else {
                            None
                        }
                    })
                    .collect();
                if policies.len() != 1 || policies[0].mode != KnowledgeMode::AuthorEstablished {
                    return Err(ProtocolError::invalid_argument(
                        "knowledge policy",
                        "Select the exact authored author-established context policy.",
                    )
                    .into());
                }
                let holder =
                    super::writing_connected::object(&rows, &declaration.holder, &ctx.frame)
                        .ok_or_else(|| {
                            ProtocolError::invalid_argument(
                                "holder",
                                "Resolve the exact authored holder.",
                            )
                        })?;
                let claim = super::writing_connected::claim(
                    self.kernel.universe(),
                    &rows,
                    &ctx.frame,
                    &declaration.claim,
                )?;
                let at = super::writing_connected::time(
                    &ctx.frame,
                    &rows,
                    &Some(declaration.at_tick.clone()),
                )?;
                let world = self
                    .focus(&json!({"world":declaration.world}), &rows)?
                    .map(|id| {
                        RecordRef::new(
                            self.kernel.universe().clone(),
                            RecordId::parse(&id.as_str().replacen("wld_", "rec_", 1))
                                .expect("validated world ID"),
                        )
                    });
                let key = format!(
                    "author-knowledge:{}",
                    hash(&(&ctx.frame, &declaration, &rationale, &label, &text))
                );
                let receipt = self.operation_key("propose", &key);
                let candidate = if self.kernel.workflow_get(&receipt)?.is_some() {
                    self.operation(&receipt)?
                        .status
                        .proposal
                        .ok_or_else(denied)?
                } else {
                    let mut ops = vec![];
                    let prop = super::writing_connected::define(
                        &mut ops,
                        self.kernel.universe(),
                        &claim,
                        &rows,
                    );
                    let attitude = EpistemicAttitude {
                        holder: RecordRef::new(self.kernel.universe().clone(), holder),
                        proposition: prop,
                        attitude: EpistemicAttitudeKind::Knows,
                        certainty: None,
                        validity: super::writing_contracts::validity(&at, &declaration.lifetime)?,
                        basis: universe_domain::scope::EvidenceBasis::AuthorDecision {
                            note: rationale.clone(),
                        },
                        acquisition: Some(KnowledgeAcquisition {
                            truth_context: ctx.frame.context.clone(),
                            time: at,
                            world,
                            basis: KnowledgeBasis::AuthorEstablished,
                        }),
                    };
                    ops.push(json!({"kind":"add_belief","client_ref":RecordId::generate(&mut rand::rng()),"record":attitude}));
                    let admission = self.writing_author_context_frame(&universe, &ctx.frame)?;
                    let proposed=self.execute(Request::from_tool("universe_propose",json!({"action":"create","universe":universe,"context_id":admission,"operations":ops,"submission":"draft","rationale":rationale,"idempotency_key":key}))?)?;
                    let p: Proposal = field(&proposed, "result")?;
                    p
                };
                self.prepare_writing_source(
                    universe,
                    candidate.proposal_id,
                    label,
                    text,
                    false,
                    Some(rationale),
                )
            }
            AuthorWritingAction::Accept {
                candidate,
                fingerprint,
                scope,
                rationale,
            } => {
                if rationale.trim().is_empty() {
                    return Err(ProtocolError::invalid_argument(
                        "rationale",
                        "author acceptance requires a reason",
                    )
                    .into());
                }
                let key = format!(
                    "writing-accept:{}",
                    hash(&(&candidate, &fingerprint, &scope, &rationale))
                );
                let receipt = self.operation_key("propose", &key);
                if self.kernel.workflow_get(&receipt)?.is_some() {
                    let p = self
                        .operation(&receipt)?
                        .status
                        .proposal
                        .ok_or_else(denied)?;
                    return self.writing_author_review(&universe, &p);
                }
                let p = self.proposal(&candidate)?;
                self.writing_author_current(&p.proposal)?;
                let checked = self.check(&p)?;
                // This is the existing opt-in resource resolution route, not a general bypass.
                let records = self
                    .kernel
                    .preview(&self.input(&p, "acceptance-review".into())?)?;
                let gaps = crate::resources::assess(&records, &p.proposal.base_frame)?;
                let gap = gaps.iter().find(|g| g.fingerprint == fingerprint && g.acceptance.is_none() && scope == format!("resource:{}",g.proposition)).ok_or_else(|| ProtocolError::invalid_argument("scope", "select an exact current unresolved resource finding and its resource scope"))?;
                let finding = checked
                    .validation
                    .findings
                    .iter()
                    .find(|f| f.fingerprint == gap.fingerprint)
                    .ok_or_else(denied)?;
                let mut operations = p.proposal.operations.clone();
                operations.push(DomainOperation::RecordIssueDecision {
                    client_ref: RecordId::generate(&mut rand::rng()).to_string(),
                    record: IssueDecision {
                        fingerprints: vec![finding.fingerprint.clone()],
                        mode: IssueDecisionMode::Accept,
                        scope: scope.clone(),
                        rationale: rationale.clone(),
                        principal: PrincipalId::parse(
                            &self.principal.id.as_str().replacen("prf_", "prn_", 1),
                        )?,
                    },
                });
                let ctx = self.writing_author_context(&universe, &p.proposal)?;
                // Existing source versions must retain their immutable identities in the revised candidate.
                let versions = p
                    .changes
                    .iter()
                    .filter_map(|c| c.next.as_ref())
                    .filter(|r| matches!(r.payload, Payload::SourceVersion(_)))
                    .map(|r| (r.identity.record_id.clone(), r.record_version_id.clone()))
                    .collect();
                let proposed = self.execute_allocated(Request::from_tool("universe_propose", json!({"action":"revise","universe":universe,"context_id":ctx,"proposal_reference":candidate,"operations":operations,"submission":"submitted","rationale":rationale,"idempotency_key":key}))?, &versions)?;
                self.writing_author_review(&universe, &field(&proposed, "result")?)
            }
        }
    }
    fn prepare_writing_source(
        &mut self,
        universe: Selector,
        candidate: ProposalId,
        label: String,
        text: String,
        contracts: bool,
        knowledge_rationale: Option<String>,
    ) -> anyhow::Result<Value> {
        if text.trim().is_empty() {
            return Err(
                ProtocolError::invalid_argument("text", "author source must not be empty").into(),
            );
        }
        let key = format!(
            "{}:{}",
            if contracts {
                "writing-contracts-prepare"
            } else {
                "writing-prepare"
            },
            if knowledge_rationale.is_some() {
                hash(&(&candidate, &label, &text, &knowledge_rationale))
            } else {
                hash(&(&candidate, &label, &text))
            }
        );
        let receipt = self.operation_key("propose", &key);
        if self.kernel.workflow_get(&receipt)?.is_some() {
            let p = self
                .operation(&receipt)?
                .status
                .proposal
                .ok_or_else(denied)?;
            return self.writing_author_review(&universe, &p);
        }
        let keys = self
            .kernel
            .workflow_keys(&format!("proposal:{candidate}:"))?;
        let stored: StoredProposal = self.load(keys.last().ok_or_else(denied)?)?;
        let candidate = ProposalRef {
            proposal_id: stored.proposal.proposal_id.clone(),
            version: stored.proposal.version,
            digest: stored.proposal.digest.clone(),
        };
        let p = self.proposal(&candidate)?;
        self.writing_author_current(&p.proposal)?;
        if !matches!(p.proposal.submission, Submission::Draft) {
            return Err(ProtocolError::ApprovalStale.into());
        }
        let originals = self.kernel.records(
            &p.proposal.base_frame.continuity,
            &p.proposal.base_frame.revision,
        )?;
        if p.proposal.operations.iter().any(|op| {
            if let DomainOperation::RecordNarrativeReference{record:RecordKind::RepresentedContext,payload:Payload::RepresentedContext(c),..}=op {
                return !contracts || !matches!(c.kind,RepresentedContextKind::Authored{..}) || c.parent.is_none() || c.chronology.is_none();
            }
            if let DomainOperation::AddBelief { record, .. } = op {
                if record
                    .acquisition
                    .as_ref()
                    .is_some_and(|a| matches!(a.basis, KnowledgeBasis::AuthorEstablished))
                {
                    return knowledge_rationale.as_ref().is_none_or(|rationale| {
                        !p.author_origin
                            || record.basis
                                != universe_domain::scope::EvidenceBasis::AuthorDecision {
                                    note: rationale.clone(),
                                }
                    });
                }
            }
            if matches!(op,DomainOperation::ReviseCommunication{..}|DomainOperation::ReviseInterpretation{..}) {return false;}
            if let DomainOperation::ReviseAttitude {record,expected_version,replacement,..}=op {
                let Some(original)=originals.iter().find(|r|r.identity.record_id==record.record && &r.record_version_id==expected_version) else{return true;};
                let Payload::EpistemicAttitude(old)=&original.payload else{return true;};
                if old.holder!=replacement.holder || old.attitude!=replacement.attitude || old.acquisition!=replacement.acquisition || old.basis!=replacement.basis {return true;}
                if old.attitude==EpistemicAttitudeKind::Knows && (old.proposition!=replacement.proposition || old.certainty!=replacement.certainty) {return true;}
                if old.attitude==EpistemicAttitudeKind::Knows && old.acquisition.as_ref().is_some_and(|a|a.basis==KnowledgeBasis::AuthorEstablished) {return knowledge_rationale.is_none() || !p.author_origin || old.proposition!=replacement.proposition || old.certainty!=replacement.certainty || old.acquisition!=replacement.acquisition || old.basis!=replacement.basis;}
                return false;
            }
            if let DomainOperation::ReviseItemPower {record,expected_version,replacement,rationale}=op {
                return !contracts || rationale.trim().is_empty() || !originals.iter().any(|r|r.identity.record_id==record.record && &r.record_version_id==expected_version && matches!(&r.payload,Payload::ItemPower(old) if old.item==replacement.item && old.holder_predicate==replacement.holder_predicate && old.power_predicate==replacement.power_predicate && old.scope.context==replacement.scope.context));
            }
            if let DomainOperation::ReviseDefinition {
                record,
                expected_version,
                replacement,
            } = op
            {
                if !contracts {
                    return true;
                }
                let Some(original) = originals.iter().find(|r| {
                    r.identity.record_id == record.record
                        && &r.record_version_id == expected_version
                }) else {
                    return true;
                };
                return match (&original.payload, replacement.as_ref()) {
                    (Payload::Property(old), Payload::Property(new)) => {
                        let mut permitted = old.clone();
                        permitted.multiplicity = new.multiplicity;
                        permitted.persistence = new.persistence;
                        &permitted != new
                    }
                    (Payload::EntityType(old), Payload::EntityType(new)) => {
                        let mut permitted = old.clone();
                        permitted.parent = new.parent.clone();
                        permitted.parent_resolution = new.parent_resolution;
                        permitted.applicability = new.applicability.clone();
                        &permitted != new
                    }
                    (Payload::ActionDefinition(old), Payload::ActionDefinition(new)) => {
                        let mut permitted = old.clone();
                        permitted.requirements = new.requirements.clone();
                        permitted.consequence_contract = new.consequence_contract.clone();
                        permitted.scope.applicability = new.scope.applicability.clone();
                        permitted.validity = new.validity.clone();
                        &permitted != new
                    }
                    (Payload::Relation(old), Payload::Relation(new)) => {
                        let mut permitted = old.clone();
                        if old.roles.len()!=new.roles.len() {return true;}
                        for (before,after) in permitted.roles.iter_mut().zip(&new.roles) {
                            if before.name!=after.name {return true;}
                            before.multiplicity=after.multiplicity;
                            before.ordered=after.ordered;
                            before.participant_types=after.participant_types.clone();
                        }
                        &permitted != new
                    }
                    (Payload::Rule(old), Payload::Rule(new)) if super::writing_relations::supported_limit(old) && super::writing_relations::supported_limit(new) => {
                        let mut permitted=old.clone();
                        let before=permitted.relation_cardinality.as_mut().unwrap();
                        let after=new.relation_cardinality.as_ref().unwrap();
                        before.maximum=after.maximum; before.grouping=after.grouping.clone(); before.counted_role=after.counted_role.clone();
                        before.scope.applicability=after.scope.applicability.clone();before.validity=after.validity.clone();
                        &permitted != new
                    }
                    (Payload::Rule(old), Payload::Rule(new)) => !super::writing_contracts::permitted_policy_correction(old,new),
                    _ => true,
                };
            }
            if let DomainOperation::AddName {record,expected_version,..}=op {
                return !originals.iter().any(|r|r.identity.record_id==record.record && &r.record_version_id==expected_version && matches!(r.payload,Payload::Entity(_)));
            }
            if let DomainOperation::EndAssertionAt { record, expected_version, .. } | DomainOperation::RetractAssertion { record, expected_version, .. } = op {
                return !originals.iter().any(|r| r.identity.record_id==record.record && &r.record_version_id==expected_version && matches!(&r.payload,Payload::Assertion(a) if a.established_by.is_none() && originals.iter().any(|p|p.identity.record_id==a.proposition.record && matches!(&p.payload,Payload::Proposition(p) if originals.iter().any(|d|d.identity.record_id==p.predicate.record && (matches!(d.payload,Payload::Property(_)) || (matches!(op,DomainOperation::EndAssertionAt{..}) && super::writing_relations::correctable(a) && matches!(d.payload,Payload::Relation(_)))))))));
            }
            if let DomainOperation::WithdrawEvent { record, expected_version, rationale } = op {
                return rationale.trim().is_empty() || !originals.iter().any(|r|r.identity.record_id==record.record && &r.record_version_id==expected_version && matches!(&r.payload,Payload::Event(e) if e.occurrence==OccurrenceMode::Occurred));
            }
            if let DomainOperation::SetCompleteness { record, .. } = op {
                return !contracts
                    || !matches!(record.completeness, CompletenessKind::ObjectiveReality);
            }
            if contracts
                && matches!(
                    op,
                    DomainOperation::DefineAction { .. } | DomainOperation::DefineRelation { .. } | DomainOperation::DefineItemPower { .. }
                )
            {
                return false;
            }
            if let DomainOperation::DefineUnit { record, .. } = op {
                return !contracts || record.base.is_some() || record.scale_to_base.is_some();
            }
            if let DomainOperation::DefineRule { record, .. } = op {
                return !contracts
                    || !(super::writing_contracts::supported_policy(record)
                        || super::writing_contracts::supported_knowledge_policy(record)
                        || super::writing_relations::supported_limit(record));
            }
            !matches!(
                op,
                DomainOperation::IntroduceInstance { .. }
                    | DomainOperation::CreateWorld { .. }
                    | DomainOperation::IntroduceDefinition { .. }
                    | DomainOperation::AddNamedAttribute { .. }
                    | DomainOperation::AddName { .. }
                    | DomainOperation::RefineClassification { .. }
                    | DomainOperation::DefineProperty { .. }
                    | DomainOperation::RecordRelation { .. }
                    | DomainOperation::AssertProposition { .. }
                    | DomainOperation::DefineProposition { .. }
                    | DomainOperation::InitializeInstance { .. }
                    | DomainOperation::ReviseEvent { .. }
                    | DomainOperation::RecordEvent { .. }
                    | DomainOperation::RecordCommunication { .. }
                    | DomainOperation::AddBelief { .. }
                    | DomainOperation::EndAssertionAt { .. }
                    | DomainOperation::RetractAssertion { .. }
                    | DomainOperation::SupersedeAssertion { .. }
            )
        }) {
            return Err(ProtocolError::PolicyDenied{message:"Source preparation accepts agent factual deltas only; protected contracts require explicit author contract review; creative acceptance requires a separate explicit author decision.".into()}.into());
        }
        let mut ops = p.proposal.operations.clone();
        // Exact staged bytes are author input; no model-authored source or approval.
        let staged = self.stage_source(label, text.clone())?;
        let mut source_ops: Vec<DomainOperation> = field(&staged, "operations")?;
        let source_version = source_ops
            .iter()
            .find_map(|op| match op {
                DomainOperation::RecordNarrativeReference {
                    client_ref,
                    payload: Payload::SourceVersion(_),
                    ..
                } => RecordId::parse(client_ref).ok(),
                _ => None,
            })
            .ok_or_else(denied)?;
        let version = RecordVersionId::generate(&mut rand::rng());
        let anchor = RecordId::generate(&mut rand::rng());
        source_ops.push(DomainOperation::AddSourceAnchor {
            client_ref: anchor.to_string(),
            record: Anchor {
                source_version: universe_domain::value::VersionRef {
                    universe: Some(self.kernel.universe().clone()),
                    record: source_version.clone(),
                    version: version.clone(),
                },
                locator: AnchorLocator::ByteRange {
                    start: 0,
                    end: text.len() as u64,
                },
                excerpt_digest: hex::encode(Sha256::digest(text.as_bytes())),
                excerpt: text,
                context: Some(p.proposal.base_frame.context.clone()),
            },
        });
        let basis = universe_domain::scope::EvidenceBasis::SourceAnchor {
            anchor: RecordRef::new(self.kernel.universe().clone(), anchor),
            verified: true,
        };
        for op in &mut ops {
            match op {
                DomainOperation::AssertProposition { assertion, .. }
                | DomainOperation::RecordRelation { assertion, .. } => {
                    assertion.basis = basis.clone()
                }
                DomainOperation::EndAssertionAt {
                    basis: end_basis, ..
                } => *end_basis = basis.clone(),
                DomainOperation::SupersedeAssertion { replacement, .. } => {
                    replacement.basis = basis.clone()
                }
                DomainOperation::AddNamedAttribute { evidence, .. } => {
                    evidence.basis = basis.clone()
                }
                DomainOperation::AddBelief { record, .. } if knowledge_rationale.is_none() => {
                    record.basis = basis.clone()
                }
                _ => (),
            }
        }
        source_ops.extend(ops);
        let ctx = self.writing_author_context(&universe, &p.proposal)?;
        let rationale = format!(
            "{}\n{}",
            if let Some(rationale) = &knowledge_rationale {
                rationale.as_str()
            } else if contracts {
                "Author explicitly declared these supported contracts/policies with exact source; separate approval still required."
            } else {
                "Author selected exact source passage for factual review; publication still requires separate exact approval."
            },
            p.proposal.rationale
        );
        let request = Request::from_tool(
            "universe_propose",
            json!({"action":"revise","universe":universe,"context_id":ctx,"proposal_reference":candidate,"operations":source_ops,"submission":"submitted","rationale":rationale,"idempotency_key":key}),
        )?;
        let proposed =
            self.execute_allocated(request, &BTreeMap::from([(source_version, version)]))?;
        let p: Proposal = field(&proposed, "result")?;
        self.writing_author_review(&universe, &p)
    }
    fn writing_author_context_frame(
        &mut self,
        universe: &Selector,
        frame: &Frame,
    ) -> anyhow::Result<ContextId> {
        let opened=self.execute(Request::from_tool("universe_open_context",json!({"universe":universe,"continuity_id":frame.continuity,"revision":{"kind":"exact","revision_id":frame.revision},"represented_context":frame.context.record,"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))?)?;
        field(&opened["result"], "context_id")
    }
    fn writing_author_current(&self, p: &Proposal) -> anyhow::Result<()> {
        if !self.latest(p)?
            || p.withdrawn
            || self.kernel.head(&p.base_frame.continuity)? != p.base_frame.revision
        {
            return Err(ProtocolError::ApprovalStale.into());
        }
        Ok(())
    }
    fn writing_author_context(
        &mut self,
        universe: &Selector,
        p: &Proposal,
    ) -> anyhow::Result<Value> {
        let opened = self.execute(Request::from_tool("universe_open_context", json!({"universe":universe,"continuity_id":p.base_frame.continuity,"revision":{"kind":"exact","revision_id":p.base_frame.revision},"represented_context":p.base_frame.context.record,"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))?)?;
        Ok(opened["result"]["context_id"].clone())
    }
    fn writing_author_review(
        &mut self,
        universe: &Selector,
        p: &Proposal,
    ) -> anyhow::Result<Value> {
        self.writing_author_current(p)?;
        let reference = ProposalRef {
            proposal_id: p.proposal_id.clone(),
            version: p.version,
            digest: p.digest.clone(),
        };
        let ctx = self.writing_author_context(universe, p)?;
        let validation = self.execute(Request::from_tool("universe_validate", json!({"mode":"proposal","universe":universe,"context_id":ctx,"proposal_reference":reference,"check_scope":"universe"}))?)?;
        let impact = self.execute(Request::from_tool("universe_get_impact", json!({"mode":"proposal","universe":universe,"context_id":ctx,"proposal_reference":reference,"scope":"universe","byte_budget":65536}))?)?;
        let checked: Checked = self.load(&format!(
            "validation:{}",
            validation["result"]["execution"]["run_id"]
                .as_str()
                .ok_or_else(denied)?
        ))?;
        let stored = self.proposal(&reference)?;
        let mut records = self
            .kernel
            .records(&p.base_frame.continuity, &p.base_frame.revision)?;
        let originals = records.clone();
        for change in &stored.changes {
            records.retain(|r| r.identity.record_id != change.record_id);
            records.extend(change.next.clone());
        }
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
                    Payload::Property(d) => Some(d.key.clone()),
                    Payload::Relation(d) => Some(d.key.clone()),
                    Payload::Realm(r) => r.labels.values().next().cloned(),
                    Payload::ActionDefinition(d) => Some(d.key.clone()),
                    Payload::Rule(d) => Some(d.key.clone()),
                    Payload::World(d) => Some(d.selector.clone()),
                    Payload::Calendar(d) => Some(
                        d.labels
                            .values()
                            .next()
                            .cloned()
                            .unwrap_or_else(|| d.key.clone()),
                    ),
                    Payload::Unit(d) => Some(d.key.clone()),
                    _ => None,
                })
        };
        let describe_claim = |reference: &RecordRef| {
            records.iter().find(|r|r.identity.record_id==reference.record).and_then(|r| if let Payload::Proposition(p)=&r.payload {Some(json!({"subject":label(&p.subject.record),"property":label(&p.predicate.record),"value":p.value.as_ref().and_then(|v|writing::plain_value(v,&label)).unwrap_or_else(||json!({"participants":p.roles.iter().map(|r|json!({"role":r.role,"object":label(&r.participant.record)})).collect::<Vec<_>>()}))}))}else{None}).unwrap_or(json!({"unknown_claim":reference.record}))
        };
        let mut summary = vec![];
        let mut factual_edits = BTreeSet::new();
        for op in &p.operations {
            match op {
                DomainOperation::ReviseCommunication{record,replacement,rationale,..}=>summary.push(format!("Historical message correction: {}; sender {}; intended recipients {}; actual recipients {}; sent {}; received {}; channel {}; distortion {}; content {}; reason: {}. Dependent knowledge/actions are rechecked; a later message is a separate declaration.",label(&record.record).unwrap_or_else(||"message".into()),label(&replacement.sender.record).unwrap_or_else(||"unresolved".into()),replacement.intended_recipients.iter().filter_map(|r|label(&r.record)).collect::<Vec<_>>().join(", "),replacement.actual_recipients.iter().filter_map(|r|label(&r.record)).collect::<Vec<_>>().join(", "),writing::plain_time(&json!(replacement.sent_at),&label),replacement.received_at.as_ref().map(|v|writing::plain_time(&json!(v),&label)).unwrap_or_else(||"no established receipt".into()),replacement.channel.as_deref().unwrap_or("unspecified"),replacement.distorted,replacement.content.iter().map(|v|describe_claim(v).to_string()).collect::<Vec<_>>().join("; "),rationale)),
                DomainOperation::ReviseInterpretation{interpretation,rationale,..}=>summary.push(format!("Historical justified interpretation correction: {}; holder, message, acquisition time and basis retained; reason: {}",interpretation.as_ref().map(|v|describe_claim(v).to_string()).unwrap_or_else(||"interpretation removed; knowledge may become unsupported".into()),rationale)),_=>()
            }
        }

        for op in &p.operations {
            if let DomainOperation::ReviseAttitude {
                record,
                replacement,
                rationale,
                ..
            } = op
            {
                if let Some(Payload::EpistemicAttitude(old)) = originals
                    .iter()
                    .find(|r| r.identity.record_id == record.record)
                    .map(|r| &r.payload)
                {
                    let claim = |rows: &[RecordVersion], id: &RecordId| {
                        rows.iter()
                            .find(|r| &r.identity.record_id == id)
                            .and_then(|r| {
                                if let Payload::Proposition(p) = &r.payload {
                                    Some(format!(
                                        "{}.{} = {}",
                                        label(&p.subject.record)
                                            .unwrap_or_else(|| "unresolved".into()),
                                        label(&p.predicate.record)
                                            .unwrap_or_else(|| "unresolved".into()),
                                        p.value
                                            .as_ref()
                                            .and_then(|v| writing::plain_value(v, &label))
                                            .unwrap_or(Value::Null)
                                    ))
                                } else {
                                    None
                                }
                            })
                            .unwrap_or_else(|| "unresolved claim".into())
                    };
                    summary.push(format!("Historical attitude correction: {} {:?}; original claim {}, time {}; proposed claim {}, time {}; acquisition and basis retained; reason: {}",label(&old.holder.record).unwrap_or_else(||"unresolved holder".into()),old.attitude,claim(&originals,&old.proposition.record),writing::plain_time(&json!(old.validity),&label),claim(&records,&replacement.proposition.record),writing::plain_time(&json!(replacement.validity),&label),rationale));
                }
            }
        }
        for op in &p.operations {
            if let DomainOperation::ReviseItemPower {
                record,
                replacement,
                rationale,
                ..
            } = op
            {
                if let Some(Payload::ItemPower(old)) = originals
                    .iter()
                    .find(|r| r.identity.record_id == record.record)
                    .map(|r| &r.payload)
                {
                    summary.push(format!("Correct item grant: {} — {}; original value {}, time {}; proposed value {}, time {}, scope {}; reason: {}",label(&old.item.record).unwrap_or_else(||"unresolved".into()),label(&old.power_predicate.record).unwrap_or_else(||"unresolved".into()),writing::plain_value(&old.value,&label).unwrap_or(Value::Null),writing::plain_time(&json!(old.validity),&label),writing::plain_value(&replacement.value,&label).unwrap_or(Value::Null),writing::plain_time(&json!(replacement.validity),&label),super::writing_connected::plain_scope(&replacement.scope,&label),rationale));
                }
            }
        }
        for op in &p.operations {
            if let DomainOperation::WithdrawEvent { record, rationale, .. } = op {
                if let Some(Payload::Event(e))=originals.iter().find(|r|r.identity.record_id==record.record).map(|r|&r.payload) {
                    summary.push(format!("Withdraw occurred event: {}; time {}; generated effects removed; no non-occurrence asserted; reason: {}",e.action.as_ref().and_then(|a|label(&a.record)).unwrap_or_else(||"authored occurrence".into()),writing::plain_time(&json!(e.time),&label),rationale));
                }
            }
        }
        for op in &p.operations {
            let target = match op {
                DomainOperation::SupersedeAssertion { record, .. }
                | DomainOperation::EndAssertionAt { record, .. }
                | DomainOperation::RetractAssertion { record, .. } => record,
                _ => continue,
            };
            let Some(Payload::Assertion(original)) = originals
                .iter()
                .find(|r| r.identity.record_id == target.record)
                .map(|r| &r.payload)
            else {
                continue;
            };
            factual_edits.insert(target.record.clone());
            let old = describe_claim(&original.proposition);
            let line = match op {
                DomainOperation::SupersedeAssertion {
                    replacement,
                    rationale,
                    ..
                } => format!(
                    "Correct earlier fact: {old}; replacement {}; reason: {rationale}",
                    describe_claim(&replacement.proposition)
                ),
                DomainOperation::EndAssertionAt { at, .. } => format!(
                    "End fact duration: {old}; end {}; earlier support remains",
                    writing::plain_time(&serde_json::to_value(at)?, &label)
                ),
                DomainOperation::RetractAssertion { rationale, .. } => format!(
                    "Withdraw fact support: {old}; no opposite claim asserted; reason: {rationale}"
                ),
                _ => unreachable!(),
            };
            summary.push(line);
        }
        for line in p
            .rationale
            .lines()
            .filter(|l| l.starts_with("Proposed fact ending reason:"))
        {
            summary.push(line.to_string());
        }
        for row in stored.changes.iter().filter_map(|c| c.next.as_ref()) {
            match &row.payload {
                Payload::Entity(e) => summary.push(format!(
                    "Proposed identity: {}; classification {}; authored names {}",
                    label(&row.identity.record_id)
                        .unwrap_or_else(|| row.identity.record_id.to_string()),
                    e.classification.as_ref().map(|id| label(id).unwrap_or_else(|| "unresolved".into())).unwrap_or_else(|| "unclassified".into()),
                    e.names.iter().map(|n|json!({"text":n.text,"language":n.language,"community":n.community,"role":n.role,"time":writing::plain_time(&json!(n.validity),&label)})).collect::<Vec<_>>().iter().map(|n|n.to_string()).collect::<Vec<_>>().join(", ")
                )),
                Payload::EntityType(t) => summary.push(format!("Proposed reusable definition: {}; parent {}; applicability {}",t.name,t.parent.as_ref().map(|id|label(id).unwrap_or_else(|| "unresolved".into())).unwrap_or_else(|| "root".into()),serde_json::to_value(&t.applicability)?)),
                Payload::Assertion(a) if !factual_edits.contains(&row.identity.record_id) => {
                    if let Some(proposition) = records
                        .iter()
                        .find(|r| r.identity.record_id == a.proposition.record)
                        .and_then(|r| {
                            if let Payload::Proposition(p) = &r.payload {
                                Some(p)
                            } else {
                                None
                            }
                        })
                    {
                        summary.push(format!(
                            "Proposed fact: {} — {} = {}; mode {:?}; polarity {:?}; validity {}; scope {}",
                            label(&proposition.subject.record)
                                .unwrap_or_else(|| proposition.subject.record.to_string()),
                            label(&proposition.predicate.record)
                                .unwrap_or_else(|| proposition.predicate.record.to_string()),
                            proposition
                                .value
                                .as_ref()
                                .and_then(|v| writing::plain_value(v, &label))
                                .unwrap_or_else(|| json!({"participants":proposition.roles.iter().map(|r|json!({"role":r.role,"object":label(&r.participant.record)})).collect::<Vec<_>>()})),
                            a.attribute_mode,
                            a.polarity,
                            writing::plain_time(&serde_json::to_value(&a.validity)?, &label),
                            serde_json::to_value(&a.scope.applicability)?
                        ));
                    }
                }
                Payload::Anchor(a) => summary.push(format!(
                    "Exact author source: {} UTF-8 bytes; digest {}",
                    a.excerpt.len(),
                    a.excerpt_digest
                )),
                Payload::Event(e) => summary.push(format!("Proposed occurred action: {}; time {}; participants {}; preconditions {}; effects {}. Exact source shares this reviewed editorial commit; no direct event anchor link.", e.action.as_ref().and_then(|r|label(&r.record)).unwrap_or_default(), serde_json::to_value(&e.time)?, serde_json::to_value(&e.participants)?, serde_json::to_value(&e.preconditions)?, serde_json::to_value(&e.effects)?)),
                Payload::Communication(c) => summary.push(format!("Proposed communication: sender {}; actual recipients {}; claims {}; receipt {}; distorted {}. Content alone is not objective truth; exact source shares this reviewed editorial commit without a direct message anchor link.", label(&c.sender.record).unwrap_or_default(), c.actual_recipients.iter().filter_map(|r|label(&r.record)).collect::<Vec<_>>().join(", "), serde_json::to_value(c.content.iter().map(&describe_claim).collect::<Vec<_>>())?, serde_json::to_value(&c.received_at)?, c.distorted)),
                Payload::EpistemicAttitude(a) => {if let universe_domain::scope::EvidenceBasis::AuthorDecision{note}=&a.basis {summary.push(format!("Explicit author knowledge decision: {note}; attributed knowledge only, no objective fact asserted"));} summary.push(format!("Proposed attitude: {} {:?}; claim {}; acquisition {}; validity {}",label(&a.holder.record).unwrap_or_default(),a.attitude,describe_claim(&a.proposition),serde_json::to_value(&a.acquisition)?,serde_json::to_value(&a.validity)?));},
                Payload::Unit(d) => summary.push(format!("Author unit declaration: {}; dimension {}; symbol {}; no conversion declared",d.key,d.dimension,d.symbol)),
                Payload::Property(d) => summary.push(format!("Proposed property: {}; values {:?}; persistence {:?}",d.key,d.multiplicity,d.persistence)),
                Payload::Relation(d)=>summary.push(format!("Author relationship declaration: {}; roles {}",d.key,d.roles.iter().map(|r|format!("{} ({:?}, ordered {}, participant types {})",r.name,r.multiplicity,r.ordered,if r.participant_types.is_empty(){"unrestricted".into()}else{r.participant_types.iter().map(|id|label(id).unwrap_or_else(||"unresolved".into())).collect::<Vec<_>>().join(", ")})).collect::<Vec<_>>().join(", "))),
                Payload::Rule(d) if d.relation_cardinality.is_some()=>{let c=d.relation_cardinality.as_ref().unwrap();summary.push(format!("Author relationship limit: {}; relationship {}; counted role {}; maximum {}; grouping {}; scope {}; time {}",d.key,label(&c.relation.record).unwrap_or_else(||"unresolved".into()),c.counted_role,c.maximum,serde_json::to_value(&c.grouping)?,super::writing_connected::plain_scope(&c.scope,&label),writing::plain_time(&serde_json::to_value(&c.validity)?,&label)));},
                Payload::Completeness(c) => summary.push(format!("Author exhaustive set: {}; property {}; members {}",label(&c.subject.record).unwrap_or_else(||"unresolved".into()),c.predicate,c.members.iter().map(|m|label(&m.record).unwrap_or_else(||"unresolved".into())).collect::<Vec<_>>().join(", "))),
                Payload::ItemPower(p) => summary.push(format!("Author possession-dependent ability: {}; holder property {}; ability {}; value {}; scope {}; time {}. Ownership relations do not establish possession.",label(&p.item.record).unwrap_or_else(||"unresolved".into()),label(&p.holder_predicate.record).unwrap_or_else(||"unresolved".into()),label(&p.power_predicate.record).unwrap_or_else(||"unresolved".into()),writing::plain_value(&p.value,&label).unwrap_or(Value::Null),super::writing_connected::plain_scope(&p.scope,&label),writing::plain_time(&serde_json::to_value(&p.validity)?,&label))),
                Payload::ActionDefinition(d) => summary.push(format!("Author action declaration: {}",super::writing_connected::plain_action(d,&label))),
                Payload::Rule(d) if d.knowledge_policy.is_some()=>{let policy=d.knowledge_policy.as_ref().unwrap();summary.push(format!("Author knowledge policy: {}; selected context {}; mode {:?}; no automatic understanding or objective truth",d.key,label(&policy.context.record).unwrap_or_else(||"selected context".into()),policy.mode));},
                Payload::Rule(d) if d.channel_chronology.is_some()=>{let channel=d.channel_chronology.as_ref().unwrap();summary.push(format!("Author channel policy: {}; channel {}; forward-only {}; minimum delay {:?}; maximum delay {:?} authored ticks",d.key,channel.channel,channel.forward_only,channel.minimum_delay,channel.maximum_delay));},
                Payload::Rule(d) => {
                    let targets:Vec<_>=d.target_predicates.iter().map(|key|records.iter().find_map(|r| if let Payload::Property(p)=&r.payload { (format!("{}:{}",p.namespace,p.key)==*key).then(||p.key.clone()) }else{None}).unwrap_or_else(||"unresolved property".into())).collect();
                    let scope=match &d.applicability { Applicability::UniverseWide=>json!("universe"),Applicability::Worlds{world_ids}=>json!({"worlds":world_ids.iter().filter_map(|w|RecordId::parse(&w.as_str().replacen("wld_","rec_",1)).ok().and_then(|id|label(&id))).collect::<Vec<_>>()}),_=>json!("unresolved") };
                    summary.push(format!("Author constraint declaration: {}; properties {}; policy {:?}; scope {}; time {}",d.key,targets.join(", "),d.commit_policy,scope,writing::plain_time(&json!(d.validity),&label)));
                },
                Payload::IssueDecision(d) => summary.push(format!(
                    "Author creative acceptance: {}; reason {}",
                    d.scope, d.rationale
                )),
                _ => (),
            }
        }
        Ok(
            json!({"acceptance_options":crate::resources::assess(&records,&p.base_frame)?.iter().filter(|g|g.acceptance.is_none()).map(|g|json!({"fingerprint":g.fingerprint,"scope":format!("resource:{}",g.proposition)})).collect::<Vec<_>>(),"summary":summary,"candidate":reference,"validation":validation["result"],"impact":impact["result"],"publishable":checked.admissible && impact["delivery"]["complete"] == true && impact["result"]["coverage"] == "complete","review":self.review(&reference)?}),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn author_source_exact_review_publication_and_recovery() {
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
        let args = json!({"universe":"Writing","context_id":opened["result"]["context_id"],"changes":[{"name":"Mara","introduce":true,"facts":[{"property":"age","value":30}]}]});

        let checked = workflow
            .execute(Request::from_tool("universe_check_changes", args).unwrap())
            .unwrap();
        let candidate: ProposalRef = serde_json::from_value(
            checked["result"]["validation"]["submitted_input"]["proposal"].clone(),
        )
        .unwrap();
        let prepare = AuthorWritingAction::Prepare {
            candidate: candidate.proposal_id.clone(),
            label: "Selected writing".into(),
            text: "Mara was thirty years old. é".into(),
        };
        assert!(workflow
            .author_writing(Selector("Writing".into()), prepare.clone())
            .is_err());
        workflow.principal.author = true;
        workflow.permissions = (true, true, true);
        let review = workflow
            .author_writing(Selector("Writing".into()), prepare.clone())
            .unwrap();
        assert_eq!(workflow.kernel.head(&c).unwrap(), revision);
        assert_eq!(review["publishable"], true, "{review}");
        let prepared: ProposalRef = field(&review, "candidate").unwrap();
        let p = workflow.proposal(&prepared).unwrap();
        let anchor = p
            .changes
            .iter()
            .filter_map(|c| c.next.as_ref())
            .find_map(|r| {
                if let Payload::Anchor(a) = &r.payload {
                    Some(a)
                } else {
                    None
                }
            })
            .unwrap();
        let source = p
            .changes
            .iter()
            .filter_map(|c| c.next.as_ref())
            .find(|r| r.identity.record_id == anchor.source_version.record)
            .unwrap();
        assert_eq!(anchor.source_version.version, source.record_version_id);
        assert_eq!(anchor.excerpt, "Mara was thirty years old. é");
        assert_eq!(
            anchor.excerpt_digest,
            hex::encode(Sha256::digest(anchor.excerpt.as_bytes()))
        );
        assert_eq!(
            workflow
                .author_writing(Selector("Writing".into()), prepare)
                .unwrap()["candidate"],
            review["candidate"]
        );
        assert!(workflow
            .author_writing(
                Selector("Writing".into()),
                AuthorWritingAction::Prepare {
                    candidate: candidate.proposal_id.clone(),
                    label: "Selected writing".into(),
                    text: "Different author bytes".into()
                }
            )
            .is_err());
        let run: ValidationRunId =
            serde_json::from_value(review["validation"]["execution"]["run_id"].clone()).unwrap();
        let commit = json!({"universe":"Writing","proposal_reference":prepared,"expected_base_revision":revision,"validation_run":run,"idempotency_key":"author-commit"});
        assert!(workflow
            .execute(Request::from_tool("universe_commit", commit).unwrap())
            .is_err());
        let Payload::SourceVersion(source_payload) = &source.payload else {
            panic!("source version")
        };
        let source_key = format!("source:{}", source_payload.digest);
        assert!(workflow.save(source_key, &"altered source bytes").is_err());
        assert_eq!(workflow.kernel.head(&c).unwrap(), revision);
        let publish = AuthorWritingAction::Publish {
            candidate: prepared.clone(),
            validation_run: run,
            idempotency_key: "author-commit".into(),
        };
        let receipt = workflow
            .author_writing(Selector("Writing".into()), publish.clone())
            .unwrap();
        assert_ne!(workflow.kernel.head(&c).unwrap(), revision);
        assert_eq!(
            workflow
                .author_writing(Selector("Writing".into()), publish)
                .unwrap(),
            receipt
        );
        assert!(workflow
            .author_writing(
                Selector("Writing".into()),
                AuthorWritingAction::Reject {
                    candidate: prepared.proposal_id
                }
            )
            .is_err());

        let fresh=workflow.execute(Request::from_tool("universe_open_context",json!({"universe":"Writing","continuity_id":c,"revision":{"kind":"head"},"represented_context":context,"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"})).unwrap()).unwrap();
        let facts=workflow.execute(Request::from_tool("universe_read_facts",json!({"universe":"Writing","context_id":fresh["result"]["context_id"],"object_names":["Mara"]})).unwrap()).unwrap();
        assert!(facts["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["property"] == "age" && f["value"] == 30));
        assert_eq!(facts["frame"]["revision"], receipt["result"]["revision"]);
        let rr = |n: u64| json!({"universe":workflow.kernel.universe(),"record":format!("rec_{n:024x}")});
        let mut ops = vec![
            json!({"kind":"define_calendar","client_ref":format!("rec_{:024x}",6),"record":{"namespace":"story","key":"days","labels":{},"unitStructure":{},"conversions":[]}}),
            json!({"kind":"create_entity","client_ref":format!("rec_{:024x}",3),"record":{"names":[],"classificationResolution":"unclassified","worldAssociations":[],"labels":{"en":"Reserve"},"metadata":{}}}),
            json!({"kind":"define_property","client_ref":format!("rec_{:024x}",4),"record":{"namespace":"resource","key":"rounds","labels":{},"subjectTypes":[],"value":{"kind":"integer"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}}),
            json!({"kind":"define_rule","client_ref":format!("rec_{:024x}",9),"record":{"namespace":"resource","key":"accounting","labels":{},"kind":"physical_constraint","commitPolicy":"block_unless_exception","applicability":{"kind":"universe_wide"},"subjectTypes":[],"targetPredicates":["resource:rounds"],"expression":{"kind":"lit","value":true},"capabilities":["resources.accounting.v1"],"executable":true,"validity":{"kind":"unspecified"}}}),
        ];
        for (n, value, start, end) in [(10, 1, 0, 5), (12, 2, 5, 20)] {
            ops.push(json!({"kind":"assert_proposition","client_ref":format!("rec_{n:024x}"),"proposition":{"subject":rr(3),"predicate":rr(4),"value":{"kind":"integer","digits":value.to_string()},"quantification":"particular","context":rr(1)},"assertion":{"attributeMode":"instance","proposition":rr(n),"polarity":"support","scope":{"context":rr(1),"applicability":{"kind":"universe_wide"}},"validity":{"kind":"calendar_interval","calendar":format!("cal_{:024x}",6),"start":{"kind":"exact","value":start.to_string()},"end":{"kind":"exact","value":end.to_string()}},"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Author stock history"}}}));
        }
        // Authored accounting definitions are fixture canon, independent of passage admission.
        let definitions: Vec<DomainOperation> = ops
            .drain(..4)
            .map(|v| serde_json::from_value(v).unwrap())
            .collect();
        let head = workflow.kernel.head(&c).unwrap();
        let base = workflow.kernel.records(&c, &head).unwrap();
        workflow
            .kernel
            .commit(&CommitInput {
                universe: workflow.kernel.universe().clone(),
                continuity: c.clone(),
                expected_head: head.clone(),
                principal: PrincipalId::parse("prn_000000000000000000000001").unwrap(),
                decision: "authored stock definitions".into(),
                reason: "Fixture author declared resource accounting".into(),
                idempotency_key: "stock-definitions".into(),
                changes: operations::compile(
                    workflow.kernel.universe(),
                    &head,
                    &base,
                    &definitions,
                )
                .unwrap(),
            })
            .unwrap();
        let fresh=workflow.execute(Request::from_tool("universe_open_context",json!({"universe":"Writing","continuity_id":c,"revision":{"kind":"head"},"represented_context":context,"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"})).unwrap()).unwrap();
        workflow.principal.author = false;
        let forbidden=workflow.execute(Request::from_tool("universe_propose",json!({"action":"create","universe":"Writing","context_id":fresh["result"]["context_id"],"operations":[{"kind":"record_issue_decision","client_ref":format!("rec_{:024x}",99),"record":{"fingerprints":["forged-fingerprint"],"mode":"accept","scope":"resource:forged","rationale":"Agent attempted acceptance","principal":"prn_000000000000000000000001"}}],"submission":"draft","rationale":"Raw advanced operation","idempotency_key":"forbidden-writing-operation"})).unwrap()).unwrap();
        let forbidden: Proposal = field(&forbidden, "result").unwrap();
        workflow.principal.author = true;
        let keys_before = workflow.kernel.workflow_keys("").unwrap();
        assert!(workflow
            .author_writing(
                Selector("Writing".into()),
                AuthorWritingAction::Prepare {
                    candidate: forbidden.proposal_id.clone(),
                    label: "Forbidden preparation".into(),
                    text: "Author prose".into()
                }
            )
            .is_err());
        assert!(workflow
            .author_writing(
                Selector("Writing".into()),
                AuthorWritingAction::PrepareContracts {
                    candidate: forbidden.proposal_id,
                    label: "Forbidden contract preparation".into(),
                    text: "Author prose".into()
                }
            )
            .is_err());
        assert_eq!(workflow.kernel.workflow_keys("").unwrap(), keys_before);
        let stock=workflow.execute(Request::from_tool("universe_propose",json!({"action":"create","universe":"Writing","context_id":fresh["result"]["context_id"],"operations":ops,"submission":"draft","rationale":"Authored stock history","idempotency_key":"stock"})).unwrap()).unwrap();
        let stock: Proposal = field(&stock, "result").unwrap();
        let review = workflow
            .author_writing(
                Selector("Writing".into()),
                AuthorWritingAction::Prepare {
                    candidate: stock.proposal_id,
                    label: "Stock passage".into(),
                    text: "The reserve had one round earlier and two rounds later.".into(),
                },
            )
            .unwrap();
        assert_eq!(review["publishable"], false);
        let candidate: ProposalRef = field(&review, "candidate").unwrap();
        let option = &review["acceptance_options"][0];
        let acceptance = AuthorWritingAction::Accept {
            candidate: candidate.clone(),
            fingerprint: field(option, "fingerprint").unwrap(),
            scope: field(option, "scope").unwrap(),
            rationale: "Author accepts the unexplained arrival for this reserve.".into(),
        };
        let mut wrong = acceptance.clone();
        if let AuthorWritingAction::Accept { scope, .. } = &mut wrong {
            *scope = "resource:wrong".into();
        }
        assert!(workflow
            .author_writing(Selector("Writing".into()), wrong)
            .is_err());
        let accepted = workflow
            .author_writing(Selector("Writing".into()), acceptance.clone())
            .unwrap();
        assert_eq!(accepted["publishable"], true, "{accepted}");
        assert_ne!(accepted["candidate"], review["candidate"]);
        assert_eq!(
            workflow
                .author_writing(Selector("Writing".into()), acceptance)
                .unwrap()["candidate"],
            accepted["candidate"]
        );
        let accepted: ProposalRef = field(&accepted, "candidate").unwrap();
        let old_run: ValidationRunId =
            serde_json::from_value(review["validation"]["execution"]["run_id"].clone()).unwrap();
        assert!(workflow
            .author_writing(
                Selector("Writing".into()),
                AuthorWritingAction::Publish {
                    candidate: accepted.clone(),
                    validation_run: old_run,
                    idempotency_key: "stale-stock".into()
                }
            )
            .is_err());
        let before_rejection = workflow.kernel.head(&c).unwrap();
        let rejection = AuthorWritingAction::Reject {
            candidate: accepted.proposal_id.clone(),
        };
        let rejected = workflow
            .author_writing(Selector("Writing".into()), rejection.clone())
            .unwrap();
        assert_eq!(rejected["withdrawn"], true);
        assert_eq!(
            workflow
                .author_writing(Selector("Writing".into()), rejection)
                .unwrap(),
            rejected
        );
        assert_eq!(workflow.kernel.head(&c).unwrap(), before_rejection);
        // Creative acceptance permits only its exact resource issue, after fresh review.
        for (op, n) in ops.iter_mut().zip([110_u64, 112]) {
            op["client_ref"] = json!(format!("rec_{n:024x}"));
            op["assertion"]["proposition"]["record"] = json!(format!("rec_{n:024x}"));
        }
        let retry=workflow.execute(Request::from_tool("universe_propose",json!({"action":"create","universe":"Writing","context_id":fresh["result"]["context_id"],"operations":ops,"submission":"draft","rationale":"Authored nonoverlapping stock history","idempotency_key":"stock-accepted-publication"})).unwrap()).unwrap();
        let retry: Proposal = field(&retry, "result").unwrap();
        let review = workflow
            .author_writing(
                Selector("Writing".into()),
                AuthorWritingAction::Prepare {
                    candidate: retry.proposal_id,
                    label: "Stock passage".into(),
                    text: "The reserve had one round earlier and two rounds later.".into(),
                },
            )
            .unwrap();
        let option = &review["acceptance_options"][0];
        let accepted = workflow
            .author_writing(
                Selector("Writing".into()),
                AuthorWritingAction::Accept {
                    candidate: field(&review, "candidate").unwrap(),
                    fingerprint: field(option, "fingerprint").unwrap(),
                    scope: field(option, "scope").unwrap(),
                    rationale: "Author explicitly accepts this unexplained arrival.".into(),
                },
            )
            .unwrap();
        assert_eq!(accepted["publishable"], true, "{accepted}");
        let published = workflow
            .author_writing(
                Selector("Writing".into()),
                AuthorWritingAction::Publish {
                    candidate: field(&accepted, "candidate").unwrap(),
                    validation_run: serde_json::from_value(
                        accepted["validation"]["execution"]["run_id"].clone(),
                    )
                    .unwrap(),
                    idempotency_key: "accepted-stock-publication".into(),
                },
            )
            .unwrap();
        assert!(published["result"]["revision"].is_string(), "{published}");
        let at=workflow.execute(Request::from_tool("universe_open_context",json!({"universe":"Writing","continuity_id":c,"revision":{"kind":"head"},"represented_context":context,"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":"cal_000000000000000000000006","value":"6"}},"temporal_systems":[],"perspective":"author"})).unwrap()).unwrap();
        let read=workflow.execute(Request::from_tool("universe_read_facts",json!({"universe":"Writing","context_id":at["result"]["context_id"],"object_names":["Reserve"]})).unwrap()).unwrap();
        assert!(
            read["result"]["objects"][0]["facts"]
                .as_array()
                .unwrap()
                .iter()
                .any(|f| f["property"] == "rounds"
                    && f["value"] == 2
                    && f["state"] == "unknown"
                    && f["unknowns"].as_array().unwrap().iter().any(|u| u
                        .as_str()
                        .unwrap()
                        .starts_with("resource_arrival_unexplained"))),
            "{read}"
        );
    }
}
