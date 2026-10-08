use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use universe_domain::{ids::*, records::*, Frame, FrameTime, Perspective, RecordRef};
use universe_protocol::{
    examples::id, request::*, response::*, ProtocolError, ProtocolResult, Request, Response,
    PROTOCOL_VERSION,
};

#[derive(Clone)]
struct Universe {
    id: UniverseId,
    name: String,
    worlds: Vec<WorldSummary>,
    records: Vec<RecordVersion>,
}
struct Receipt {
    universe: UniverseId,
    fingerprint: String,
    proposal: Proposal,
}
/// All state is bounded and disposable. Losing the process loses proposals,
/// contexts and fixture receipts. This is never a production recovery store.
pub struct Fixture {
    universes: Vec<Universe>,
    contexts: HashMap<ContextId, Frame>,
    proposals: HashMap<(ProposalId, u64), (UniverseId, Proposal)>,
    receipts: HashMap<(UniverseId, String), Receipt>,
    next: u64,
}
impl Default for Fixture {
    fn default() -> Self {
        Self::new()
    }
}
impl Fixture {
    pub fn new() -> Self {
        let mut universes = Vec::new();
        for (n, name) in [(1, "The Ashen Cycle"), (2, "The Glass Archive")] {
            let uid = UniverseId::parse(&id("unv", n)).unwrap();
            let worlds = if n == 1 {
                vec![
                    WorldSummary {
                        id: WorldId::parse(&id("wld", 1)).unwrap(),
                        name: Selector("Aster".into()),
                    },
                    WorldSummary {
                        id: WorldId::parse(&id("wld", 2)).unwrap(),
                        name: Selector("Nacre".into()),
                    },
                ]
            } else {
                vec![WorldSummary {
                    id: WorldId::parse(&id("wld", 3)).unwrap(),
                    name: Selector("Aster".into()),
                }]
            };
            let mut records = Vec::new();
            for world in &worlds {
                records.push(record(
                    &uid,
                    100 + world.id.0.as_bytes().last().copied().unwrap() as u64,
                    Payload::World(World {
                        selector: world.name.0.clone(),
                        aliases: vec![],
                        setting_type: None,
                        labels: BTreeMap::new(),
                        metadata: BTreeMap::new(),
                    }),
                ));
            }
            let label = if n == 1 {
                "Mara — seal custodian"
            } else {
                "Iven — archivist"
            };
            let associations: Vec<_> = worlds
                .iter()
                .map(|w| WorldAssociation {
                    world: w.id.clone(),
                    role: "setting".into(),
                    validity: Default::default(),
                    qualifiers: BTreeMap::new(),
                })
                .collect();
            records.push(record(
                &uid,
                n * 10,
                Payload::Entity(Entity {
                    names: vec![],
                    classification: None,
                    classification_resolution:
                        universe_domain::records::ClassificationResolution::Unclassified,
                    world_associations: associations.clone(),
                    labels: BTreeMap::from([("en".into(), label.into())]),
                    metadata: BTreeMap::new(),
                }),
            ));
            records.push(record(
                &uid,
                n * 10 + 1,
                Payload::Work(Work {
                    kind: WorkKind::Novel,
                    title: if n == 1 {
                        "Across Aster and Nacre"
                    } else {
                        "The Glass Archive"
                    }
                    .into(),
                    labels: BTreeMap::new(),
                    source_refs: vec![],
                    versions: vec![],
                    world_associations: associations,
                }),
            ));
            records.push(record(
                &uid,
                n * 10 + 2,
                Payload::Entity(Entity {
                    names: vec![],
                    classification: None,
                    classification_resolution:
                        universe_domain::records::ClassificationResolution::Unclassified,
                    world_associations: vec![],
                    labels: BTreeMap::from([("en".into(), "Unassigned traveler".into())]),
                    metadata: BTreeMap::new(),
                }),
            ));
            universes.push(Universe {
                id: uid,
                name: name.into(),
                worlds,
                records,
            });
        }
        Self {
            universes,
            contexts: HashMap::new(),
            proposals: HashMap::new(),
            receipts: HashMap::new(),
            next: 1000,
        }
    }
    fn allocate(&mut self, prefix: &str) -> String {
        self.next += 1;
        id(prefix, self.next)
    }
    pub fn handle(&mut self, request_id: u64, request: Request) -> ProtocolResult<Response> {
        request.validate()?;
        let universe = self
            .universes
            .iter()
            .find(|u| u.name == request.universe().0)
            .cloned()
            .ok_or_else(|| ProtocolError::not_found("universe"))?;
        let data = serde_json::to_value(&request).expect("typed request");
        let args = &data["args"];
        if args
            .get("universe_id")
            .and_then(Value::as_str)
            .is_some_and(|id| id != universe.id.as_str())
        {
            return Err(ProtocolError::UniverseScopeMismatch {
                message: "universe guard does not match".into(),
            });
        }
        let frame = if let Some(context) = args.get("context_id").and_then(Value::as_str) {
            let context = ContextId::parse(context).map_err(|e| ProtocolError::from_domain(&e))?;
            let frame = self
                .contexts
                .get(&context)
                .filter(|f| f.universe == universe.id)
                .ok_or_else(|| ProtocolError::not_found("context"))?;
            Some(frame.clone())
        } else {
            None
        };
        let world = if let Some(name) = args.get("world").and_then(Value::as_str) {
            let world = universe
                .worlds
                .iter()
                .find(|w| w.name.0 == name)
                .ok_or_else(|| ProtocolError::not_found("world"))?;
            if args
                .get("world_id")
                .and_then(Value::as_str)
                .is_some_and(|id| id != world.id.as_str())
            {
                return Err(ProtocolError::WorldScopeConflict {
                    message: "world guard does not match".into(),
                });
            }
            Some(world.id.clone())
        } else {
            None
        };
        // Every explicitly supplied record target must belong to this universe.
        for key in ["record_ids", "entity_ids", "focus_ids", "changed_records"] {
            if let Some(ids) = args.get(key).and_then(Value::as_array) {
                for target in ids {
                    if !universe
                        .records
                        .iter()
                        .any(|r| Some(r.identity.record_id.as_str()) == target.as_str())
                    {
                        return Err(ProtocolError::not_found("record"));
                    }
                }
            }
        }
        // Fixture has no historical search cursor or partial delivery support yet.
        if args.get("cursor").is_some() {
            return Err(unsupported("fixture pagination"));
        }
        let scope = Scope {
            request_id,
            universe: &universe,
            frame: frame.clone(),
            world: world.clone(),
        };
        match request {
   Request::Describe(_) => Ok(Response::Describe(scope.wrap(Description{fixture:true,worlds:universe.worlds.clone(),capabilities:capabilities(),definition_ids:vec![],continuities:vec![]}))),
   Request::OpenContext(a) => {
    if self.contexts.len()>=128{return Err(limit())}
    if a.continuity_id.as_str()!=id("cont",1) || a.represented_context.as_str()!=id("rec",90) || !matches!(a.temporal_query,FrameTime::Timeless) || !matches!(a.perspective,Perspective::Author) || !a.temporal_systems.is_empty() {return Err(unsupported("fixture supports main, objective, timeless author frame only"))}
    if let RevisionSelector::Exact{revision_id}=&a.revision {if revision_id.as_str()!=id("rev",1){return Err(ProtocolError::not_found("revision"))}}
    let context_id=ContextId::parse(&self.allocate("ctx")).unwrap();
    let frame=Frame{universe:universe.id.clone(),continuity:a.continuity_id,revision:RevisionId::parse(&id("rev",1)).unwrap(),context:RecordRef::new(universe.id.clone(),a.represented_context),time:a.temporal_query,perspective:a.perspective,reader_scene:a.reader_scene,personal_sequence:None};
    self.contexts.insert(context_id.clone(),frame.clone());
    Ok(Response::OpenContext(Scope{frame:Some(frame.clone()),..scope}.wrap(OpenedContext{context_id,frame})))
   }
   Request::Search(a) => {
    let mut hits=Vec::new();
    for r in &universe.records {
     let label=label(r);let world_ids=record_worlds(r,&universe);
     if !label.to_lowercase().contains(&a.query.to_lowercase()) || (!a.typed_filters.record_kinds.is_empty() && !a.typed_filters.record_kinds.contains(&r.identity.record_kind)) {continue}
     if world.as_ref().is_some_and(|w|!world_ids.is_empty()&&!world_ids.contains(w)){continue}
     let scope_category=if world_ids.is_empty(){ScopeCategory::Unassigned}else if world.is_some(){ScopeCategory::SelectedWorld}else{ScopeCategory::Shared};
     hits.push(SearchHit{record_id:r.identity.record_id.clone(),kind:r.identity.record_kind,label,world_ids,scope_category});
    }
    // Do not drop results while claiming complete delivery.
    if hits.len()>a.limit as usize{return Err(limit())}
    Ok(Response::Search(scope.wrap(SearchResults{hits})))
   }
   Request::Get(a) => {
    if a.field_groups.is_empty() || a.field_groups.iter().any(|g|!matches!(g,FieldGroup::Payload)){return Err(unsupported("fixture get supports the payload field group only"))}
    let mut records=Vec::new();for id in a.record_ids {let r=universe.records.iter().find(|r|r.identity.record_id==id).ok_or_else(||ProtocolError::not_found("record"))?;
     let ws=record_worlds(r,&universe);if world.as_ref().is_some_and(|w|!ws.is_empty()&&!ws.contains(w)){return Err(ProtocolError::WorldScopeConflict{message:"record outside selected world".into()})}
     records.push(r.clone());
    }Ok(Response::Get(scope.wrap(Records{records,summaries:vec![],evidence:vec![],history:vec![],history_coverage:None})))
   }
   Request::Propose(action) => {
    if matches!(action, Propose::AttachAssessment{..}|Propose::SelectAssessment{..}) {
     return Err(unsupported("assessment actions require a persistent installation"));
    }
    let key=args["idempotency_key"].as_str().unwrap().to_owned();
    let mut semantic=args.clone();semantic.as_object_mut().unwrap().remove("universe");semantic.as_object_mut().unwrap().remove("universe_id");
    semantic.as_object_mut().unwrap().remove("context_id");semantic["frame"]=serde_json::to_value(&frame).unwrap();
    semantic.as_object_mut().unwrap().remove("world");semantic.as_object_mut().unwrap().remove("world_id");semantic["resolved_world"]=serde_json::to_value(&world).unwrap();
    // Context handles are immutable; resolved universe keys isolate receipts.
    let fingerprint=hex::encode(Sha256::digest(universe_domain::canonical::canonical_serde(&semantic).to_bytes()));
    let receipt_key=(universe.id.clone(),key);
    if let Some(receipt)=self.receipts.get(&receipt_key) {
     if receipt.fingerprint!=fingerprint{return Err(ProtocolError::IdempotencyKeyReused{message:"different proposal content".into()})}
     return Ok(Response::Propose(scope.wrap(ProposalOutcome::Proposal(Box::new(receipt.proposal.clone())))))
    }
    if self.receipts.len()>=256 {return Err(limit())}
    let operation_id=OperationId::parse(&self.allocate("op")).unwrap();
    let mut proposal=match action {
     Propose::Create{operations,submission,rationale,..}=>Proposal{base_frame:frame.clone().expect("proposal context checked"),world_scope:world.clone(),proposal_id:ProposalId::parse(&self.allocate("prp")).unwrap(),version:1,digest:String::new(),submission,operations,compiled_changes:vec![],rationale,canonical:false,operation_id:operation_id.clone(),withdrawn:false},
     Propose::Revise{proposal_reference,operations,submission,rationale,..}=>{
      let mut p=self.bound_proposal(&universe.id,&proposal_reference)?;p.version+=1;p.base_frame=frame.clone().expect("context checked");p.world_scope=world.clone();p.operations=operations;p.submission=submission;p.rationale=rationale;p
     }
     Propose::Submit{proposal_reference,..}=>{let mut p=self.bound_proposal(&universe.id,&proposal_reference)?;p.version+=1;p.submission=Submission::Submitted;p}
     Propose::Withdraw{proposal_reference,..}=>{let mut p=self.bound_proposal(&universe.id,&proposal_reference)?;p.version+=1;p.withdrawn=true;p}
     Propose::AttachAssessment{..}|Propose::SelectAssessment{..}=>unreachable!("rejected before fixture mutation"),
    };
    // Explicit foreign namespace references cannot become fixture proposals.
    reject_foreign_references(&serde_json::to_value(&proposal.operations).unwrap(),&universe.id)?;
    validate_world_references(&serde_json::to_value(&proposal.operations).unwrap(), &universe)?;
    validate_write_envelope(&proposal.operations, proposal.world_scope.as_ref(), &universe)?;
    proposal.operation_id=operation_id;
    proposal.digest=hex::encode(Sha256::digest(universe_domain::canonical::canonical_serde(&serde_json::json!({"frame":proposal.base_frame,"world_scope":proposal.world_scope,"version":proposal.version,"operations":proposal.operations,"rationale":proposal.rationale,"submission":proposal.submission,"withdrawn":proposal.withdrawn})).to_bytes()));
    self.proposals.insert((proposal.proposal_id.clone(),proposal.version),(universe.id.clone(),proposal.clone()));
    self.receipts.insert(receipt_key,Receipt{universe:universe.id.clone(),fingerprint,proposal:proposal.clone()});
    Ok(Response::Propose(scope.wrap(ProposalOutcome::Proposal(Box::new(proposal)))))
   }
   Request::GetProposal(a)=>{
    if a.view_group.as_ref().is_some_and(|g|!matches!(g,ProposalView::Payload)){return Err(unsupported("fixture proposal view supports the payload field group only"))}
    let p=self.proposals.get(&(a.proposal_id,a.version)).filter(|(u,p)|*u==universe.id&&p.version==a.version).map(|(_,p)|p.clone()).ok_or_else(||ProtocolError::not_found("proposal version"))?;
    Ok(Response::GetProposal(scope.wrap(ProposalViewResult::Proposal(Box::new(p)))))
   }
   Request::GetOperation(a)=>{
    let receipt=match a {
     GetOperation::Id{operation_id,..}=>self.receipts.values().find(|r|r.universe==universe.id&&r.proposal.operation_id==operation_id),
     GetOperation::Key{operation_kind:OperationKind::Propose,idempotency_key,..}=>self.receipts.get(&(universe.id.clone(),idempotency_key)),
     _=>None,
    }.ok_or_else(||ProtocolError::not_found("operation"))?;
    Ok(Response::GetOperation(scope.wrap(universe_protocol::validation_scope::OperationStatusV3::from_stored(operation_status(receipt.proposal.clone()), None))))
   }
   Request::CancelOperation(a)=>{
    let receipt=self.receipts.values().find(|r|r.universe==universe.id&&r.proposal.operation_id==a.operation_id).ok_or_else(||ProtocolError::not_found("operation"))?;
    // Already admitted proposals are complete. Cancellation never pretends to undo them.
    let mut status=operation_status(receipt.proposal.clone());status.cancellation_requested=true;
    Ok(Response::CancelOperation(scope.wrap(universe_protocol::validation_scope::OperationStatusV3::from_stored(status, None))))
   }
   Request::Commit(_)=>Err(ProtocolError::PolicyDenied{message:"fixture cannot commit canon; author approval and durable storage are unavailable".into()}),
   Request::GetState(_)|Request::GetContext(_)|Request::Validate(_)|Request::GetImpact(_)=>Err(unsupported("store-backed semantic evaluation is not implemented")),
  }
    }
    fn bound_proposal(&self, u: &UniverseId, r: &ProposalRef) -> ProtocolResult<Proposal> {
        let p = self
            .proposals
            .get(&(r.proposal_id.clone(), r.version))
            .filter(|(owner, p)| owner == u && p.digest == r.digest)
            .map(|(_, p)| p)
            .ok_or_else(|| ProtocolError::not_found("exact proposal"))?;
        let latest = self
            .proposals
            .keys()
            .filter(|(id, _)| *id == r.proposal_id)
            .map(|(_, version)| *version)
            .max()
            .unwrap_or(r.version);
        if latest != r.version || p.withdrawn {
            return Err(ProtocolError::invalid_argument(
                "proposal_reference",
                "stale or withdrawn proposal cannot be changed",
            ));
        }
        Ok(p.clone())
    }
}
fn record(u: &UniverseId, n: u64, payload: Payload) -> RecordVersion {
    RecordVersion::build(
        RecordVersionId::parse(&id("ver", n)).unwrap(),
        RecordIdentity::new(
            u.clone(),
            RecordId::parse(&id("rec", n)).unwrap(),
            payload.kind(),
        ),
        payload,
    )
    .unwrap()
}
fn label(r: &RecordVersion) -> String {
    match &r.payload {
        Payload::World(w) => w.selector.clone(),
        Payload::Entity(e) => e.labels.get("en").cloned().unwrap_or_default(),
        Payload::Work(w) => w.title.clone(),
        _ => r.identity.record_id.to_owned(),
    }
}
fn record_worlds(r: &RecordVersion, u: &Universe) -> Vec<WorldId> {
    match &r.payload {
        Payload::Entity(e) => e
            .world_associations
            .iter()
            .map(|a| a.world.clone())
            .collect(),
        Payload::Work(w) => w
            .world_associations
            .iter()
            .map(|a| a.world.clone())
            .collect(),
        Payload::World(w) => u
            .worlds
            .iter()
            .filter(|x| x.name.0 == w.selector)
            .map(|x| x.id.clone())
            .collect(),
        _ => vec![],
    }
}
fn reject_foreign_references(v: &Value, u: &UniverseId) -> ProtocolResult<()> {
    match v {
        Value::Object(m) => {
            if m.get("universe")
                .and_then(Value::as_str)
                .is_some_and(|s| s != u.as_str())
            {
                return Err(ProtocolError::UniverseScopeMismatch {
                    message: "foreign reference".into(),
                });
            }
            for x in m.values() {
                reject_foreign_references(x, u)?
            }
        }
        Value::Array(a) => {
            for x in a {
                reject_foreign_references(x, u)?
            }
        }
        _ => {}
    }
    Ok(())
}
/// Validate only the typed WorldAssociation and Applicability wire shapes.
/// Arbitrary labels and metadata text are not routing identifiers.
fn validate_world_references(v: &Value, u: &Universe) -> ProtocolResult<()> {
    let check = |id: &str| {
        if u.worlds.iter().any(|w| w.id.as_str() == id) {
            Ok(())
        } else {
            Err(ProtocolError::WorldNotFoundOrNotAccessible {
                message: "referenced world is outside this fixture universe".into(),
            })
        }
    };
    match v {
        Value::Object(m) => {
            if m.contains_key("role") && m.contains_key("validity") && m.contains_key("qualifiers")
            {
                if let Some(id) = m.get("world").and_then(Value::as_str) {
                    check(id)?;
                }
            }
            if m.get("kind").and_then(Value::as_str) == Some("worlds") {
                if let Some(ids) = m.get("world_ids").and_then(Value::as_array) {
                    for id in ids.iter().filter_map(Value::as_str) {
                        check(id)?;
                    }
                }
            }
            for child in m.values() {
                validate_world_references(child, u)?;
            }
        }
        Value::Array(a) => {
            for child in a {
                validate_world_references(child, u)?;
            }
        }
        _ => {}
    }
    Ok(())
}

/// The fixture can prove simple identity/work footprints. More complex
/// world-scoped effects require the real operation compiler (WP07).
fn validate_write_envelope(
    ops: &[DomainOperation],
    world: Option<&WorldId>,
    u: &Universe,
) -> ProtocolResult<()> {
    let Some(world) = world else { return Ok(()) };
    let check = |worlds: Vec<WorldId>| {
        if !worlds.is_empty() && worlds.iter().all(|id| id == world) {
            Ok(())
        } else {
            Err(ProtocolError::WorldScopeConflict { message: "all proposed effects must have explicit applicability within the selected world".into() })
        }
    };
    let existing = |target: &RecordRef, version: &RecordVersionId| {
        let r = u
            .records
            .iter()
            .find(|r| {
                r.identity.record_id == target.record
                    && target.universe.as_ref().is_none_or(|owner| owner == &u.id)
            })
            .ok_or_else(|| ProtocolError::not_found("proposal target"))?;
        if &r.record_version_id != version {
            return Err(ProtocolError::invalid_argument(
                "expected_version",
                "fixture target version mismatch",
            ));
        }
        check(record_worlds(r, u))
    };
    for op in ops {
        match op {
            DomainOperation::CreateEntity { record, .. } => check(
                record
                    .world_associations
                    .iter()
                    .map(|a| a.world.clone())
                    .collect(),
            )?,
            DomainOperation::CreateWork { record, .. } => check(
                record
                    .world_associations
                    .iter()
                    .map(|a| a.world.clone())
                    .collect(),
            )?,
            DomainOperation::AddName {
                record,
                expected_version,
                ..
            }
            | DomainOperation::AddTypeMembership {
                record,
                expected_version,
                ..
            }
            | DomainOperation::RenameWorldSelector {
                record,
                expected_version,
                ..
            }
            | DomainOperation::AddWorldAlias {
                record,
                expected_version,
                ..
            }
            | DomainOperation::TombstoneRecord {
                record,
                expected_version,
                ..
            } => existing(record, expected_version)?,
            DomainOperation::AssociateWorkWorld {
                record,
                expected_version,
                association,
            } => {
                existing(record, expected_version)?;
                check(vec![association.world.clone()])?;
            }
            _ => {
                return Err(unsupported(
                    "fixture cannot prove this operation's world-scoped write footprint",
                ))
            }
        }
    }
    Ok(())
}

fn operation_status(p: Proposal) -> OperationStatus {
    OperationStatus {
        validation: None,
        failure: None,
        operation_id: p.operation_id.clone(),
        kind: OperationKind::Propose,
        state: OperationState::Succeeded,
        proposal: Some(p),
        receipt: None,
        cancellation_requested: false,
    }
}
struct Scope<'a> {
    request_id: u64,
    universe: &'a Universe,
    frame: Option<Frame>,
    world: Option<WorldId>,
}
impl Scope<'_> {
    fn wrap<T>(&self, result: T) -> Envelope<T> {
        Envelope {
            contract_version: PROTOCOL_VERSION.into(),
            request_id: self.request_id,
            universe_id: self.universe.id.clone(),
            universe: Selector(self.universe.name.clone()),
            alias_matched: false,
            frame: self.frame.clone(),
            world_focus: self.world.clone(),
            authorization_scope: "disposable-fixture/read-propose-only".into(),
            delivery: Delivery {
                complete: true,
                cursor: None,
            },
            result,
        }
    }
}
pub fn capabilities() -> Vec<Capability> {
    vec![
        Capability {
            id: "fixture.read-propose.v1".into(),
            status: CapabilityStatus::Implemented,
            limitation: "Disposable state; no persistence or production authentication".into(),
        },
        Capability {
            id: "rule.boolean_evidence.v1".into(),
            status: CapabilityStatus::Implemented,
            limitation: "Pure literal Boolean expressions only; not store-backed validation".into(),
        },
        Capability {
            id: "assertion.qualified.v1".into(),
            status: CapabilityStatus::DescriptiveOnly,
            limitation: "Typed representation; state evaluation unavailable".into(),
        },
        Capability {
            id: "canon.commit.v1".into(),
            status: CapabilityStatus::Unsupported,
            limitation: "No canon mutation in fixture mode".into(),
        },
        Capability {
            id: "rule.finite_constraints.v1".into(),
            status: CapabilityStatus::Unsupported,
            limitation: "Unsupported operators never claim complete evaluation".into(),
        },
    ]
}
fn unsupported(message: &str) -> ProtocolError {
    ProtocolError::UnsupportedSemantics {
        message: message.into(),
    }
}
fn limit() -> ProtocolError {
    ProtocolError::EvaluationLimitReached {
        message: "fixture capacity reached".into(),
    }
}
