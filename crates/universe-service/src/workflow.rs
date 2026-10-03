//! Durable, frame-pinned application workflow shared by native and MCP clients.
use crate::{
    operations::{self, Footprint},
    registry::Principal,
};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use universe_domain::{
    canonical::canonical_serde, frame::*, ids::*, records::*, scope::Applicability,
    value::RecordRef,
};
use universe_protocol::{request::*, response::*, ProtocolError, Request};
use universe_store::kernel::{Assignment, CommitInput, Kernel};
const EVALUATOR: &str = "finite-policy-v5-input-scope";
use universe_protocol::validation_scope::*;
use validation_binding::ValidationCapture;
pub(crate) fn hash<T: Serialize>(v: &T) -> String {
    hex::encode(Sha256::digest(canonical_serde(v).to_bytes()))
}
fn field<T: DeserializeOwned>(v: &Value, key: &str) -> anyhow::Result<T> {
    Ok(serde_json::from_value(v.get(key).cloned().ok_or_else(
        || ProtocolError::invalid_argument(key, "required"),
    )?)?)
}
fn denied() -> anyhow::Error {
    ProtocolError::not_found("resource").into()
}
fn unsupported(message: &str) -> anyhow::Error {
    ProtocolError::UnsupportedSemantics {
        message: message.into(),
    }
    .into()
}
fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("clock after epoch")
        .as_secs()
}
#[derive(Clone, Serialize, Deserialize)]
struct Context {
    owner: ProfileId,
    scope: String,
    expires: u64,
    frame: Frame,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct StoredProposal {
    pub proposal: Proposal,
    pub owner: ProfileId,
    pub author_origin: bool,
    pub changes: Vec<Assignment>,
    pub footprint: Footprint,
}
#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct Checked {
    proposal_digest: String,
    validation: Validation,
    admissible: bool,
    #[serde(default)]
    report: Option<ValidationV3>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    capture: Option<ValidationCapture>,
}
#[derive(Clone, Serialize, Deserialize)]
struct StoredOperation {
    owner: ProfileId,
    digest: String,
    status: OperationStatus,
    input: Option<CommitInput>,
    footprint: Footprint,
    #[serde(default)]
    validation_capture: Option<ValidationCapture>,
}
pub(crate) struct ValidationTask {
    proposal: StoredProposal,
    base: Vec<RecordVersion>,
    candidate: Vec<RecordVersion>,
    author: ProfileId,
    restricted: bool,
    capture: Option<ValidationCapture>,
}
impl ValidationTask {
    pub(crate) fn evaluate(
        self,
        cancel: &std::sync::atomic::AtomicBool,
    ) -> anyhow::Result<Checked> {
        #[cfg(test)]
        if let Some((entered, release)) = EVALUATION_PAUSES
            .get_or_init(Default::default)
            .lock()
            .unwrap()
            .remove(&self.proposal.proposal.base_frame.universe)
        {
            let _ = entered.send(());
            while release.recv_timeout(std::time::Duration::from_millis(10))
                == Err(std::sync::mpsc::RecvTimeoutError::Timeout)
            {
                if cancel.load(std::sync::atomic::Ordering::Acquire) {
                    break;
                }
            }
        }
        if self.restricted {
            return Ok(Checked {
                proposal_digest: self.proposal.proposal.digest.clone(),
                admissible: false,
                report: None,
                capture: None,
                validation: Validation {
                    operation_id: None,
                    run_id: ValidationRunId::generate(&mut rand::rng()),
                    coverage: Coverage::Restricted,
                    findings: vec![],
                    opposing_evidence: vec![],
                    unsupported_capabilities: vec![
                        "Author validation required for complete evaluation scope".into(),
                    ],
                    input_digest: self.proposal.proposal.digest,
                    evaluator_version: EVALUATOR.into(),
                },
            });
        }
        let mut checked = Workflow::evaluate(
            &self.proposal,
            self.candidate,
            &self.base,
            &self.author,
            &|| {
                if cancel.load(std::sync::atomic::Ordering::Acquire) {
                    Err(unsupported("validation cancelled"))
                } else {
                    Ok(())
                }
            },
        )?;
        checked.capture = self.capture;
        Ok(checked)
    }
}
#[cfg(test)]
type EvaluationPauses = std::collections::BTreeMap<
    UniverseId,
    (std::sync::mpsc::Sender<()>, std::sync::mpsc::Receiver<()>),
>;
#[cfg(test)]
static EVALUATION_PAUSES: std::sync::OnceLock<std::sync::Mutex<EvaluationPauses>> =
    std::sync::OnceLock::new();
#[cfg(test)]
pub(crate) fn pause_evaluation(
    u: UniverseId,
) -> (std::sync::mpsc::Receiver<()>, std::sync::mpsc::Sender<()>) {
    let (entered, wait) = std::sync::mpsc::channel();
    let (release, blocked) = std::sync::mpsc::channel();
    EVALUATION_PAUSES
        .get_or_init(Default::default)
        .lock()
        .unwrap()
        .insert(u, (entered, blocked));
    (wait, release)
}
type ActiveJobs = std::collections::BTreeMap<
    (UniverseId, OperationId),
    std::sync::Arc<std::sync::atomic::AtomicBool>,
>;
static ACTIVE_JOBS: std::sync::OnceLock<std::sync::Mutex<ActiveJobs>> = std::sync::OnceLock::new();
pub(crate) fn start_validation(
    u: &UniverseId,
    id: &OperationId,
) -> Option<std::sync::Arc<std::sync::atomic::AtomicBool>> {
    let mut jobs = ACTIVE_JOBS.get_or_init(Default::default).lock().unwrap();
    let key = (u.clone(), id.clone());
    if jobs.contains_key(&key) {
        return None;
    }
    let flag = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    jobs.insert(key, flag.clone());
    Some(flag)
}
pub(crate) fn end_validation(u: &UniverseId, id: &OperationId) {
    ACTIVE_JOBS
        .get_or_init(Default::default)
        .lock()
        .unwrap()
        .remove(&(u.clone(), id.clone()));
}
pub(crate) fn cancel_universe_jobs(u: &UniverseId) {
    for ((universe, _), flag) in ACTIVE_JOBS
        .get_or_init(Default::default)
        .lock()
        .unwrap()
        .iter()
    {
        if universe == u {
            flag.store(true, std::sync::atomic::Ordering::Release);
        }
    }
}
fn active_validation(u: &UniverseId, id: &OperationId) -> bool {
    ACTIVE_JOBS
        .get_or_init(Default::default)
        .lock()
        .unwrap()
        .contains_key(&(u.clone(), id.clone()))
}
fn cancel_validation(u: &UniverseId, id: &OperationId) {
    if let Some(flag) = ACTIVE_JOBS
        .get_or_init(Default::default)
        .lock()
        .unwrap()
        .get(&(u.clone(), id.clone()))
    {
        flag.store(true, std::sync::atomic::Ordering::Release);
    }
}
pub struct Workflow<'a> {
    pub kernel: &'a mut Kernel,
    pub authority: Option<crate::runtime::Authority>,
    pub principal: Principal,
    pub approval_author: ProfileId,
    pub scope: Option<BTreeSet<WorldId>>,
    pub permissions: (bool, bool, bool),
    pub name: String,
}
impl Workflow<'_> {
    fn load<T: DeserializeOwned>(&self, key: &str) -> anyhow::Result<T> {
        Ok(serde_json::from_value(
            self.kernel.workflow_get(key)?.ok_or_else(denied)?,
        )?)
    }
    fn save<T: Serialize>(&mut self, key: String, v: &T) -> anyhow::Result<()> {
        self.persist(&[(key, serde_json::to_value(v)?)])
    }
    fn persist(&mut self, entries: &[(String, Value)]) -> anyhow::Result<()> {
        let authority = self.authority.clone();
        let _guard = authority.as_ref().map(|a| a.lock()).transpose()?;
        Ok(self.kernel.workflow_put(entries)?)
    }
    fn scope_hash(&self) -> String {
        hash(&(&self.scope, self.permissions, self.limits()))
    }
    fn limits(&self) -> universe_protocol::installation::GrantLimits {
        self.authority
            .as_ref()
            .map(|a| a.limits.clone())
            .unwrap_or_default()
    }
    fn write_boundaries(&self, p: &StoredProposal) -> anyhow::Result<()> {
        let limits = self.limits();
        if limits
            .continuities
            .as_ref()
            .is_some_and(|ids| !ids.contains(&p.proposal.base_frame.continuity))
        {
            return Err(denied());
        }
        if limits.entities.is_none() && limits.predicates.is_none() {
            return Ok(());
        }
        let base = self.kernel.records(
            &p.proposal.base_frame.continuity,
            &p.proposal.base_frame.revision,
        )?;
        let versions: Vec<_> = base
            .iter()
            .chain(p.changes.iter().filter_map(|c| c.next.as_ref()))
            .collect();
        let mut references = std::collections::BTreeMap::new();
        for record in &versions {
            references.insert(
                record.record_version_id.clone(),
                universe_store::kernel::record_dependencies(record)?,
            );
        }
        let entities: BTreeSet<_> = versions
            .iter()
            .filter(|r| matches!(r.payload, Payload::Entity(_)))
            .map(|r| r.identity.record_id.clone())
            .collect();
        let permitted = |r: &RecordVersion| {
            let proposition = match &r.payload {
                Payload::Proposition(p) => Some(p),
                Payload::Assertion(a) => versions.iter().find_map(|r| {
                    if r.identity.record_id == a.proposition.record {
                        if let Payload::Proposition(p) = &r.payload {
                            Some(p)
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                }),
                _ => None,
            };
            if let Some(p) = proposition {
                limits.entities.as_ref().is_none_or(|ids| {
                    versions
                        .iter()
                        .filter(|r| matches!(&r.payload,Payload::Proposition(value) if value == p))
                        .all(|r| {
                            references[&r.record_version_id]
                                .iter()
                                .filter(|id| entities.contains(*id))
                                .all(|id| ids.contains(id))
                        })
                        && ids.contains(&p.subject.record)
                        && p.roles
                            .iter()
                            .all(|role| ids.contains(&role.participant.record))
                }) && limits
                    .predicates
                    .as_ref()
                    .is_none_or(|ids| ids.contains(&p.predicate.record))
            } else {
                matches!(&r.payload, Payload::Entity(_))
                    && limits.predicates.is_none()
                    && limits
                        .entities
                        .as_ref()
                        .is_none_or(|ids| ids.contains(&r.identity.record_id))
            }
        };
        for change in &p.changes {
            if versions
                .iter()
                .filter(|r| r.identity.record_id == change.record_id)
                .any(|r| !permitted(r))
            {
                return Err(ProtocolError::PolicyDenied {
                    message: "write exceeds entity or predicate grant boundaries".into(),
                }
                .into());
            }
        }
        Ok(())
    }
    fn authorize(&self, f: &Footprint, commit: bool) -> anyhow::Result<()> {
        if (!commit && !self.permissions.0)
            || (commit && !self.permissions.1)
            || (f.protected && !self.permissions.2)
            || self
                .scope
                .as_ref()
                .is_some_and(|s| f.shared || f.worlds.is_empty() || !f.worlds.is_subset(s))
        {
            return Err(ProtocolError::PolicyDenied {
                message: "current grant does not cover the full write footprint".into(),
            }
            .into());
        }
        Ok(())
    }
    fn visible(&self, r: &RecordVersion) -> bool {
        self.scope
            .as_ref()
            .is_none_or(|s| operations::worlds(r).is_subset(s))
    }
    fn visible_ids(&self, records: &[RecordVersion]) -> anyhow::Result<BTreeSet<RecordId>> {
        let all: BTreeSet<_> = records
            .iter()
            .map(|r| r.identity.record_id.clone())
            .collect();
        if self.scope.is_none() {
            return Ok(all);
        }
        let mut hidden = BTreeSet::new();
        let mut reverse = std::collections::BTreeMap::<RecordId, Vec<RecordId>>::new();
        let mut edges = 0usize;
        for r in records {
            if !self.visible(r)
                || matches!(
                    r.payload,
                    Payload::IssueDecision(_)
                        | Payload::ImageAsset(_)
                        | Payload::Appearance(Appearance {
                            target: AppearanceTarget::Universe,
                            ..
                        })
                        | Payload::Source(_)
                        | Payload::SourceVersion(_)
                        | Payload::Anchor(_)
                )
            {
                hidden.insert(r.identity.record_id.clone());
            }
            for dependency in universe_store::kernel::record_dependencies(r)? {
                edges += 1;
                if edges > 5_000_000 {
                    return Err(ProtocolError::EvaluationLimitReached {
                        message: "Authorization dependency budget exceeded".into(),
                    }
                    .into());
                }
                if !all.contains(&dependency) {
                    hidden.insert(r.identity.record_id.clone());
                }
                reverse
                    .entry(dependency)
                    .or_default()
                    .push(r.identity.record_id.clone());
            }
        }
        let mut pending: Vec<_> = hidden.iter().cloned().collect();
        while let Some(id) = pending.pop() {
            for dependent in reverse.get(&id).into_iter().flatten() {
                if hidden.insert(dependent.clone()) {
                    pending.push(dependent.clone());
                }
            }
        }
        Ok(all.difference(&hidden).cloned().collect())
    }
    fn context(&self, id: &ContextId) -> anyhow::Result<Context> {
        let c: Context = self.load(&format!("context:{id}"))?;
        if c.owner != self.principal.id || c.scope != self.scope_hash() {
            return Err(denied());
        }
        if c.expires < now() {
            return Err(ProtocolError::ContextExpired.into());
        }
        Ok(c)
    }
    fn proposal(&self, r: &ProposalRef) -> anyhow::Result<StoredProposal> {
        let p: StoredProposal =
            self.load(&format!("proposal:{}:{:020}", r.proposal_id, r.version))?;
        if p.proposal.digest != r.digest {
            return Err(ProtocolError::ApprovalStale.into());
        }
        if !self.principal.author && p.owner != self.principal.id {
            return Err(denied());
        }
        if self
            .scope
            .as_ref()
            .is_some_and(|s| p.footprint.shared || !p.footprint.worlds.is_subset(s))
        {
            return Err(denied());
        }
        Ok(p)
    }
    fn latest(&self, p: &Proposal) -> anyhow::Result<bool> {
        let keys = self
            .kernel
            .workflow_keys(&format!("proposal:{}:", p.proposal_id))?;
        Ok(keys.last() == Some(&format!("proposal:{}:{:020}", p.proposal_id, p.version)))
    }
    fn input(&self, p: &StoredProposal, key: String) -> anyhow::Result<CommitInput> {
        Ok(CommitInput {
            universe: self.kernel.universe().clone(),
            continuity: p.proposal.base_frame.continuity.clone(),
            expected_head: p.proposal.base_frame.revision.clone(),
            principal: PrincipalId::parse(&self.principal.id.as_str().replacen("prf_", "prn_", 1))?,
            decision: p.proposal.digest.clone(),
            reason: p.proposal.rationale.clone(),
            idempotency_key: key,
            changes: p.changes.clone(),
        })
    }
    fn has_final(&self, c: &Checked, p: &StoredProposal) -> bool {
        // Assessment-aware publication is a separate goal. Preserve the existing
        // generation-zero record path, and revoke it after any selection change.
        let r = validation_binding::proposal_reference(p);
        if !self
            .assessment_selection_raw(&r)
            .is_ok_and(|s| s.generation == 0 && s.selected.is_none())
        {
            return false;
        }
        matches!(
            &c.report,
            Some(ValidationV3::Evaluated {
                final_binding_digest: Some(_),
                ..
            })
        ) && hash(&c.report) == hash(&Some(Self::report(p, c.validation.clone(), false, true)))
    }
    fn query_report(execution: Validation, frame: Frame, check_scope: CheckScope) -> ValidationV3 {
        if execution.coverage == Coverage::Restricted {
            return ValidationV3::restricted();
        }
        ValidationV3::Evaluated {
            execution: Box::new(execution),
            submitted_input: Box::new(SubmittedInput::Query {
                frame: Box::new(frame),
                check_scope,
            }),
            assessment: AssessmentState::Absent {},
            final_binding_digest: None,
        }
    }
    fn report(
        p: &StoredProposal,
        execution: Validation,
        legacy: bool,
        finished: bool,
    ) -> ValidationV3 {
        if execution.coverage == Coverage::Restricted {
            return ValidationV3::restricted();
        }
        // Compatibility for legacy/pending evidence and the existing unselected
        // publication gate. Completed validation uses its captured selection.
        let proposal = validation_binding::proposal_reference(p);
        let submitted_input = validation_binding::record_input(p);
        let assessment = if legacy {
            AssessmentState::UnavailableLegacy {}
        } else {
            AssessmentState::Absent {}
        };
        let final_binding_digest = if finished && !legacy {
            use universe_protocol::assessment::*;
            Some(
                SourceValidationBindingV1 {
                    kind: ValidationBindingKind::SourceValidationBindingV1,
                    proposal: proposal.clone(),
                    base_frame: p.proposal.base_frame.clone(),
                    selection: AssessmentSelection {
                        proposal,
                        generation: 0,
                        selected: None,
                    },
                    submitted_input: submitted_input.clone(),
                    assessment_state: assessment.clone(),
                    execution_result_digest: execution_result_digest(&execution),
                    evaluator_version: execution.evaluator_version.clone(),
                }
                .digest()
                .expect("verified generation-zero record binding"),
            )
        } else {
            None
        };
        ValidationV3::Evaluated {
            execution: Box::new(execution),
            submitted_input: Box::new(submitted_input),
            assessment,
            final_binding_digest,
        }
    }
    fn public_status(&self, status: OperationStatus) -> anyhow::Result<OperationStatusV3> {
        let report = if let Some(execution) = &status.validation {
            if self.scope.is_some() || execution.coverage == Coverage::Restricted {
                Some(ValidationV3::restricted())
            } else {
                let saved = self
                    .kernel
                    .workflow_get(&format!("validation:{}", execution.run_id))?;
                let checked = saved.map(serde_json::from_value::<Checked>).transpose()?;
                if let Some(mut report) = checked.and_then(|c| c.report) {
                    if let ValidationV3::Evaluated {
                        execution: core, ..
                    } = &mut report
                    {
                        *core = execution.clone();
                    }
                    Some(report)
                } else {
                    let proposal = status.proposal.as_ref().ok_or_else(denied)?;
                    let p: StoredProposal = self.load(&format!(
                        "proposal:{}:{:020}",
                        proposal.proposal_id, proposal.version
                    ))?;
                    let op: StoredOperation =
                        self.load(&format!("operation:{}", status.operation_id))?;
                    let mut report = match &op.validation_capture {
                        Some(capture) => capture.report(&p, *execution.clone(), false)?,
                        None => Self::report(
                            &p,
                            *execution.clone(),
                            execution.evaluator_version != EVALUATOR,
                            false,
                        ),
                    };
                    if matches!(
                        status.state,
                        OperationState::Failed
                            | OperationState::Cancelled
                            | OperationState::Interrupted
                    ) {
                        if let ValidationV3::Evaluated {
                            assessment,
                            submitted_input,
                            ..
                        } = &mut report
                        {
                            *assessment = AssessmentState::Unavailable {
                                reason: UnavailableReason::FailedOrCancelledCheck,
                            };
                            **submitted_input = validation_binding::record_input(&p);
                        }
                    }
                    Some(report)
                }
            }
        } else {
            None
        };
        let mut public = OperationStatusV3::from_stored(status, report);
        if self.scope.is_some() && public.validation.is_some() {
            public.failure = None;
            public.proposal = None;
        }
        Ok(public)
    }
    fn operation_key(&self, kind: &str, key: &str) -> String {
        format!("request:{}:{kind}:{}", self.principal.id, hash(&key))
    }
    fn operation(&self, key: &str) -> anyhow::Result<StoredOperation> {
        let mut op: StoredOperation = self.load(key)?;
        if op.status.kind == OperationKind::Validate && !key.starts_with("operation:") {
            op = self.load(&format!("operation:{}", op.status.operation_id))?;
        }
        if op.status.kind == OperationKind::Validate {
            for state in ["terminal", "running"] {
                if let Some(saved) = self
                    .kernel
                    .workflow_get(&format!("job:{}:{state}", op.status.operation_id))?
                {
                    op = serde_json::from_value(saved)?;
                    break;
                }
            }
        }
        if op.owner != self.principal.id {
            return Err(denied());
        }
        if self
            .scope
            .as_ref()
            .is_some_and(|s| op.footprint.shared || !op.footprint.worlds.is_subset(s))
        {
            return Err(denied());
        }
        if let Some(input) = &op.input {
            if let Some(revision) = self.kernel.receipt(input)? {
                op.status.state = OperationState::Succeeded;
                op.status.receipt = Some(CommitReceipt {
                    operation_id: op.status.operation_id.clone(),
                    proposal_id: op
                        .status
                        .proposal
                        .as_ref()
                        .ok_or_else(denied)?
                        .proposal_id
                        .clone(),
                    revision,
                });
            } else if self
                .kernel
                .workflow_get(&format!("cancel:{}", op.status.operation_id))?
                .is_some()
            {
                op.status.state = OperationState::Cancelled;
                op.status.cancellation_requested = true;
            } else {
                op.status.state = OperationState::Interrupted;
            }
        }
        if op.status.kind == OperationKind::Validate {
            if self
                .kernel
                .workflow_get(&format!("cancel:{}", op.status.operation_id))?
                .is_some()
            {
                op.status.state = OperationState::Cancelled;
                op.status.cancellation_requested = true;
            } else if matches!(op.status.state, OperationState::Running)
                && !active_validation(self.kernel.universe(), &op.status.operation_id)
            {
                op.status.state = OperationState::Interrupted;
            }
        }
        Ok(op)
    }
    #[cfg(test)]
    pub fn run_validation(&mut self, id: &OperationId) -> anyhow::Result<()> {
        if let Some(task) = self.prepare_validation(id)? {
            let result = task.evaluate(&std::sync::atomic::AtomicBool::new(false));
            self.finish_validation(id, result)?;
        }
        Ok(())
    }
    pub(crate) fn prepare_validation(
        &mut self,
        id: &OperationId,
    ) -> anyhow::Result<Option<ValidationTask>> {
        let op = self.operation(&format!("operation:{id}"))?;
        if op.status.kind != OperationKind::Validate
            || matches!(
                op.status.state,
                OperationState::Succeeded | OperationState::Failed | OperationState::Cancelled
            )
        {
            return Ok(None);
        }
        let proposal = op.status.proposal.as_ref().ok_or_else(denied)?;
        let p = self.proposal(&ProposalRef {
            proposal_id: proposal.proposal_id.clone(),
            version: proposal.version,
            digest: proposal.digest.clone(),
        })?;
        self.write_boundaries(&p)?;
        let restricted = self.scope.is_some();
        let capture = if restricted {
            None
        } else {
            Some(op.validation_capture.clone().ok_or_else(|| {
                unsupported("queued validation requires a fresh selection capture")
            })?)
        };
        if let Some(capture) = &capture {
            let authority = self.authority.clone();
            let guard = authority.as_ref().map(|a| a.lock()).transpose()?;
            self.verify_validation_authority(capture, guard.as_deref())?;
            self.verify_validation_capture(&p, capture)?;
        }
        let (base, candidate) = if restricted {
            (vec![], vec![])
        } else {
            for operation in &p.proposal.operations {
                if let DomainOperation::AdoptRecordVersion { source, .. } = operation {
                    if self.kernel.record_version(&source.record_version_id)? != **source {
                        return Err(denied());
                    }
                }
            }
            let candidate = self.kernel.preview(&self.input(&p, "validation".into())?)?;
            self.verify_sources(&candidate)?;
            (
                self.kernel.records(
                    &p.proposal.base_frame.continuity,
                    &p.proposal.base_frame.revision,
                )?,
                candidate,
            )
        };
        if self
            .kernel
            .workflow_get(&format!("job:{id}:running"))?
            .is_none()
        {
            let mut running = op;
            running.status.state = OperationState::Running;
            self.save(format!("job:{id}:running"), &running)?;
        }
        Ok(Some(ValidationTask {
            proposal: p,
            base,
            candidate,
            author: self.approval_author.clone(),
            restricted,
            capture,
        }))
    }
    pub(crate) fn finish_validation(
        &mut self,
        id: &OperationId,
        result: anyhow::Result<Checked>,
    ) -> anyhow::Result<()> {
        let mut op = self.operation(&format!("operation:{id}"))?;
        if matches!(
            op.status.state,
            OperationState::Cancelled | OperationState::Succeeded | OperationState::Failed
        ) {
            return Ok(());
        }
        let key = format!("job:{id}:terminal");
        match result {
            Ok(mut checked) => {
                checked.validation.operation_id = Some(id.clone());
                let proposal = op.status.proposal.as_ref().ok_or_else(denied)?;
                let p: StoredProposal = self.load(&format!(
                    "proposal:{}:{:020}",
                    proposal.proposal_id, proposal.version
                ))?;
                let capture = checked.capture.clone();
                checked.report = Some(match &capture {
                    Some(capture) => capture.report(&p, checked.validation.clone(), true)?,
                    None => ValidationV3::restricted(),
                });
                op.status.validation = Some(Box::new(checked.validation.clone()));
                op.status.state = OperationState::Succeeded;
                let entries = [
                    (
                        format!("validation:{}", checked.validation.run_id),
                        serde_json::to_value(&checked)?,
                    ),
                    (key.clone(), serde_json::to_value(&op)?),
                ];
                if let Err(error) = self.persist_bound_validation(&p, capture.as_ref(), &entries) {
                    // Never retain completed evidence for a superseded run.
                    op.status.validation = self
                        .load::<StoredOperation>(&format!("operation:{id}"))?
                        .status
                        .validation;
                    op.status.state = OperationState::Failed;
                    op.status.failure = Some(error.to_string());
                    self.save(key, &op)?;
                }
            }
            Err(error) => {
                op.status.state = OperationState::Failed;
                op.status.failure = Some(error.to_string());
                self.save(key, &op)?;
            }
        }
        Ok(())
    }
    fn check(&mut self, p: &StoredProposal) -> anyhow::Result<Checked> {
        if !matches!(p.proposal.base_frame.time, FrameTime::Timeless) {
            return Err(unsupported(
                "proposal validation requires an all-validities author frame",
            ));
        }
        if self.scope.is_some() {
            return Ok(Checked {
                proposal_digest: p.proposal.digest.clone(),
                admissible: false,
                report: None,
                capture: None,
                validation: Validation {
                    operation_id: None,
                    run_id: ValidationRunId::generate(&mut rand::rng()),
                    coverage: Coverage::Restricted,
                    findings: vec![],
                    opposing_evidence: vec![],
                    unsupported_capabilities: vec![
                        "An author must validate this proposal against the complete universe."
                            .into(),
                    ],
                    input_digest: p.proposal.digest.clone(),
                    evaluator_version: EVALUATOR.into(),
                },
            });
        }
        for operation in &p.proposal.operations {
            if let DomainOperation::AdoptRecordVersion { source, .. } = operation {
                if self.kernel.record_version(&source.record_version_id)? != **source {
                    return Err(ProtocolError::invalid_argument(
                        "adoption",
                        "source must be an existing immutable version",
                    )
                    .into());
                }
            }
        }
        let input = self.input(p, "validation".into())?;
        let candidate = self.kernel.preview(&input)?;
        self.verify_sources(&candidate)?;
        let base = self.kernel.records(
            &p.proposal.base_frame.continuity,
            &p.proposal.base_frame.revision,
        )?;
        Self::evaluate(p, candidate, &base, &self.approval_author, &|| Ok(()))
    }
    fn evaluate(
        p: &StoredProposal,
        candidate: Vec<RecordVersion>,
        base: &[RecordVersion],
        approval_author: &ProfileId,
        cancelled: &dyn Fn() -> anyhow::Result<()>,
    ) -> anyhow::Result<Checked> {
        let mut definitions = universe_schema::DefinitionRegistry::new();
        for record in &candidate {
            cancelled()?;
            definitions.add(record)?;
        }
        universe_schema::validate(&definitions)?;
        crate::validation::structural(&candidate)?;
        crate::actions::validate(
            &candidate,
            &p.changes.iter().map(|c| c.record_id.clone()).collect(),
            &p.proposal.base_frame,
        )?;
        for changed in p.changes.iter().filter_map(|c| c.next.as_ref()) {
            if let Payload::IssueDecision(decision) = &changed.payload {
                if !p.author_origin
                    || decision.principal.as_str()
                        != approval_author.as_str().replacen("prf_", "prn_", 1)
                {
                    return Err(ProtocolError::PolicyDenied {
                        message: "issue decisions must be authored by the installation author"
                            .into(),
                    }
                    .into());
                }
            }
            let context = match &changed.payload {
                Payload::Assertion(a) => Some(&a.scope.context),
                Payload::Proposition(p) => Some(&p.context),
                _ => None,
            };
            if context.is_some_and(|c| c != &p.proposal.base_frame.context) {
                return Err(ProtocolError::invalid_argument(
                    "operations",
                    "asserted changes must use the proposal represented context",
                )
                .into());
            }
        }
        for record in &candidate {
            cancelled()?;
            if let Payload::Event(e) = &record.payload {
                if e.occurrence != OccurrenceMode::Occurred {
                    continue;
                }
                let mut event_frame = p.proposal.base_frame.clone();
                event_frame.time = FrameTime::AtEvent {
                    event: RecordRef::new(
                        p.proposal.base_frame.universe.clone(),
                        record.identity.record_id.clone(),
                    ),
                    side: EventTimeSide::Before,
                };
                if let Some(effect) = e.effects.first() {
                    event_frame.context = effect.scope.context.clone();
                } else if let Some(action) = e
                    .action
                    .as_ref()
                    .and_then(|a| candidate.iter().find(|r| r.identity.record_id == a.record))
                {
                    if let Payload::ActionDefinition(a) = &action.payload {
                        event_frame.context = a.scope.context.clone();
                    }
                }
                for expression in &e.preconditions {
                    let (evidence, complete) = universe_rules::basic::evaluate(
                        expression,
                        &universe_rules::EvaluationContext {
                            frame: Some(&event_frame),
                            base_snapshot: &candidate,
                            candidate_changes: vec![],
                            index: None,
                            world_scope: Some(
                                e.worlds
                                    .iter()
                                    .map(|w| {
                                        RecordId::parse(&universe_store::kernel::world_record(w))
                                    })
                                    .collect::<Result<Vec<_>, _>>()?,
                            ),
                        },
                    );
                    if !complete || evidence.outcome() != universe_rules::EvidenceOutcome::Supported
                    {
                        return Err(ProtocolError::invalid_argument("event.preconditions","pre-event prerequisites are conflicting, unsupported or not established").into());
                    }
                }
            }
        }
        let evaluation_index = universe_rules::EvaluationIndex::new(&candidate);
        let mut findings = Vec::new();
        let mut unsupported_capabilities = Vec::new();
        let mut admissible = true;
        let worlds = if p.footprint.shared {
            candidate
                .iter()
                .filter(|r| matches!(r.payload, Payload::World(_)))
                .map(|r| r.identity.record_id.clone())
                .collect::<Vec<_>>()
        } else {
            p.footprint
                .worlds
                .iter()
                .map(|w| {
                    RecordId::parse(&universe_store::kernel::world_record(w))
                        .expect("world identity")
                })
                .collect()
        };
        // Enumerate the complete candidate, never a search result or focused page.
        for record in &candidate {
            cancelled()?;
            match &record.payload {
                Payload::Rule(rule) => {
                    if !rule.expression.uses_opposing_evidence()
                        && matches!(&rule.applicability,Applicability::Worlds{world_ids} if !p.footprint.shared && world_ids.iter().all(|w|!p.footprint.worlds.contains(w)))
                    {
                        continue;
                    }
                    let result = crate::rule_checks::evaluate_indexed(
                        Some(&evaluation_index),
                        record,
                        &candidate,
                        &p.proposal.base_frame,
                        &if rule.expression.uses_opposing_evidence() {
                            candidate
                                .iter()
                                .filter(|r| matches!(r.payload, Payload::World(_)))
                                .map(|r| r.identity.record_id.clone())
                                .collect()
                        } else {
                            worlds.clone()
                        },
                    );
                    let complete = result.complete;
                    let outcome = match result.evidence.outcome() {
                        universe_rules::EvidenceOutcome::Supported => EvidenceOutcome::Supported,
                        universe_rules::EvidenceOutcome::Refuted => EvidenceOutcome::Refuted,
                        universe_rules::EvidenceOutcome::Conflicting => {
                            EvidenceOutcome::Conflicting
                        }
                        universe_rules::EvidenceOutcome::NotEstablished => {
                            EvidenceOutcome::NotEstablished
                        }
                    };
                    let pass = result.accepted;
                    if !complete {
                        unsupported_capabilities
                            .push(format!("rule:{}", record.identity.record_id));
                    }
                    if matches!(
                        rule.commit_policy,
                        CommitPolicy::AlwaysBlock
                            | CommitPolicy::BlockUnlessException
                            | CommitPolicy::ScopeEnforced
                    ) && !pass
                    {
                        admissible = false;
                    }
                    findings.push(Finding {
                        fingerprint: FindingFingerprint(String::new()),
                        rule_id: record.identity.record_id.clone(),
                        outcome,
                        evidence: result.evidence.all_sources(),
                        coverage: if complete {
                            Coverage::Complete
                        } else {
                            Coverage::Unsupported
                        },
                    });
                }
                Payload::Boundary(boundary) => {
                    let (outcome, coverage, evidence, accepted) =
                        Self::boundary(record, boundary, p, &candidate, base)?;
                    if !accepted {
                        admissible = false;
                    }
                    if coverage != Coverage::Complete {
                        unsupported_capabilities
                            .push(format!("boundary:{}", record.identity.record_id));
                    }
                    findings.push(Finding {
                        fingerprint: FindingFingerprint(String::new()),
                        rule_id: record.identity.record_id.clone(),
                        outcome,
                        evidence,
                        coverage,
                    });
                }
                Payload::Exception(e) => {
                    let valid = crate::rule_checks::valid_exception(e, &candidate);
                    if !valid {
                        unsupported_capabilities.push(format!("exception:{}: stale rule version, unsupported scope or missing acceptance",record.identity.record_id));
                        admissible = false;
                    }
                }
                _ => {}
            }
        }
        cancelled()?;
        let (mut conflicts, mut gaps) = crate::validation::scalar_conflicts(&candidate);
        let (closed, unresolved) = crate::validation::completeness_conflicts(&candidate);
        conflicts.extend(closed);
        gaps.extend(unresolved);
        if !conflicts.is_empty() || !gaps.is_empty() {
            admissible = false;
        }
        unsupported_capabilities.extend(gaps);
        findings.extend(conflicts.into_iter().map(|(rule_id, evidence)| Finding {
            fingerprint: FindingFingerprint(String::new()),
            rule_id,
            outcome: EvidenceOutcome::Conflicting,
            evidence,
            coverage: Coverage::Complete,
        }));
        for finding in &mut findings {
            finding.fingerprint = FindingFingerprint(hash(&(
                &p.proposal.base_frame,
                &p.proposal.digest,
                EVALUATOR,
                &finding.rule_id,
                &finding.outcome,
                &finding.evidence,
            )));
        }
        let opposing_evidence = crate::validation::opposing_evidence(
            &candidate,
            &p.proposal.base_frame,
            &p.proposal.digest,
            EVALUATOR,
            &mut unsupported_capabilities,
        )?;
        let validation = Validation {
            operation_id: None,
            run_id: ValidationRunId::generate(&mut rand::rng()),
            coverage: if unsupported_capabilities.is_empty() {
                Coverage::Complete
            } else {
                Coverage::Partial
            },
            findings,
            opposing_evidence,
            unsupported_capabilities,
            input_digest: p.proposal.digest.clone(),
            evaluator_version: EVALUATOR.into(),
        };
        Ok(Checked {
            proposal_digest: p.proposal.digest.clone(),
            report: None,
            capture: None,
            validation,
            admissible,
        })
    }
    fn boundary(
        target: &RecordVersion,
        _boundary: &CreativeBoundary,
        p: &StoredProposal,
        candidate: &[RecordVersion],
        base: &[RecordVersion],
    ) -> anyhow::Result<(EvidenceOutcome, Coverage, Vec<RecordVersionId>, bool)> {
        let changes: Vec<_> = p
            .changes
            .iter()
            .flat_map(|change| {
                change.next.iter().chain(
                    base.iter()
                        .filter(move |r| r.identity.record_id == change.record_id),
                )
            })
            .collect();
        let result = crate::boundary_checks::evaluate(
            target,
            &changes,
            candidate,
            base,
            &p.proposal.base_frame,
            p.author_origin,
        )?;
        let outcome = match result.evidence.outcome() {
            universe_rules::EvidenceOutcome::Supported => EvidenceOutcome::Supported,
            universe_rules::EvidenceOutcome::Refuted => EvidenceOutcome::Refuted,
            universe_rules::EvidenceOutcome::Conflicting => EvidenceOutcome::Conflicting,
            universe_rules::EvidenceOutcome::NotEstablished => EvidenceOutcome::NotEstablished,
        };
        Ok((
            outcome,
            if result.complete {
                Coverage::Complete
            } else {
                Coverage::Unsupported
            },
            result.evidence.all_sources(),
            result.accepted,
        ))
    }
    fn verify_sources(&self, records: &[RecordVersion]) -> anyhow::Result<()> {
        for record in records {
            match &record.payload {
                Payload::ImageAsset(asset) => {
                    let staged: Payload =
                        self.load(&format!("image-asset:{}", record.identity.record_id))?;
                    if staged != record.payload {
                        return Err(ProtocolError::invalid_argument(
                            "image",
                            "image metadata differs from import receipt",
                        )
                        .into());
                    }
                    self.kernel.image_bytes(asset)?;
                }
                Payload::SourceVersion(v) => {
                    let staged: Payload =
                        self.load(&format!("source-version:{}", record.identity.record_id))?;
                    if staged != record.payload {
                        return Err(ProtocolError::invalid_argument(
                            "source",
                            "source import provenance differs from staging receipt",
                        )
                        .into());
                    }
                    let text: String = self.load(&format!("source:{}", v.digest))?;
                    if hex::encode(Sha256::digest(text.as_bytes())) != v.digest
                        || text.len() as u64 != v.byte_size
                        || v.decoding.byte_length != v.byte_size
                        || v.decoding.encoding != "UTF-8"
                        || v.decoding.representation != "exact-utf8-v1"
                    {
                        return Err(ProtocolError::invalid_argument(
                            "source",
                            "source digest, length or decoding differs",
                        )
                        .into());
                    }
                }
                Payload::Anchor(a) => {
                    let source = if let Some(r) = records
                        .iter()
                        .find(|r| r.record_version_id == a.source_version.version)
                    {
                        r.clone()
                    } else {
                        self.kernel.record_version(&a.source_version.version)?
                    };
                    if source.identity.record_id != a.source_version.record {
                        return Err(denied());
                    }
                    let Payload::SourceVersion(v) = &source.payload else {
                        return Err(denied());
                    };
                    let text: String = self.load(&format!("source:{}", v.digest))?;
                    let AnchorLocator::ByteRange { start, end } = a.locator else {
                        return Err(unsupported("only byte-accurate UTF-8 anchors are verified"));
                    };
                    let excerpt = text.get(start as usize..end as usize).ok_or_else(|| {
                        ProtocolError::invalid_argument("anchor", "invalid byte boundaries")
                    })?;
                    if excerpt != a.excerpt
                        || hex::encode(Sha256::digest(excerpt.as_bytes())) != a.excerpt_digest
                    {
                        return Err(ProtocolError::invalid_argument(
                            "anchor",
                            "excerpt does not match immutable source",
                        )
                        .into());
                    }
                }
                _ => {}
            }
        }
        Ok(())
    }
    pub fn stage_image(&mut self, source: std::path::PathBuf) -> anyhow::Result<Value> {
        if !self.principal.author {
            return Err(denied());
        }
        let (id, asset) = self.kernel.stage_image(&source)?;
        let preview = self.kernel.image_preview(&asset)?;
        Ok(
            json!({"canonical":false,"asset_id":id,"preview":preview,"metadata":asset,"operations":[DomainOperation::AddImageAsset{client_ref:id.to_string(),record:asset}]}),
        )
    }
    pub fn image_preview(&self, context: &ContextId, asset: &RecordId) -> anyhow::Result<Value> {
        if !self.principal.author {
            return Err(denied());
        }
        let context = self.context(context)?;
        let records = self
            .kernel
            .records(&context.frame.continuity, &context.frame.revision)?;
        let record = records
            .iter()
            .find(|r| &r.identity.record_id == asset)
            .ok_or_else(denied)?;
        let Payload::ImageAsset(image) = &record.payload else {
            return Err(denied());
        };
        Ok(json!({"asset_id":asset,"metadata":image,"preview":self.kernel.image_preview(image)?}))
    }
    pub fn stage_source(&mut self, label: String, text: String) -> anyhow::Result<Value> {
        if !self.principal.author {
            return Err(denied());
        }
        if text.len() > 512_000 || label.trim().is_empty() || label.len() > 256 {
            return Err(ProtocolError::invalid_argument(
                "source",
                "source label and text exceed limits",
            )
            .into());
        }
        let digest = hex::encode(Sha256::digest(text.as_bytes()));
        self.save(format!("source:{digest}"), &text)?;
        let source = RecordId::generate(&mut rand::rng());
        let version = RecordId::generate(&mut rand::rng());
        let payload = Payload::Source(Source {
            label,
            external_id: None,
            origin: Default::default(),
            versions: vec![version.clone()],
        });
        let version_payload = Payload::SourceVersion(SourceVersion {
            source: RecordRef::new(self.kernel.universe().clone(), source.clone()),
            digest,
            media_type: "text/plain; charset=utf-8".into(),
            byte_size: text.len() as u64,
            import_actor: PrincipalId::parse(
                &self.principal.id.as_str().replacen("prf_", "prn_", 1),
            )?,
            import_time: chrono::Utc::now().to_rfc3339(),
            decoding: DecodingDescriptor {
                encoding: "UTF-8".into(),
                representation: "exact-utf8-v1".into(),
                byte_length: text.len() as u64,
            },
            origin: Default::default(),
        });
        self.save(format!("source-version:{version}"), &version_payload)?;
        Ok(
            json!({"canonical":false,"operations":[DomainOperation::RecordNarrativeReference{client_ref:source.0,record:RecordKind::Source,payload},DomainOperation::RecordNarrativeReference{client_ref:version.0,record:RecordKind::SourceVersion,payload:version_payload}]}),
        )
    }
    pub fn review(&self, r: &ProposalRef) -> anyhow::Result<Value> {
        if !self.principal.author {
            return Err(denied());
        }
        let p = self.proposal(r)?;
        let assessment = self.assessment_review(r, None)?;
        let base = self.kernel.records(
            &p.proposal.base_frame.continuity,
            &p.proposal.base_frame.revision,
        )?;
        let diff:Vec<_>=p.changes.iter().map(|change|json!({"record":change.record_id,"before":base.iter().find(|r|r.identity.record_id==change.record_id),"after":change.next})).collect();
        Ok(
            json!({"proposal":p.proposal,"changes":p.changes,"diff":diff,"footprint":p.footprint,"latest":self.latest(&p.proposal)?,"assessment_review":assessment}),
        )
    }
    pub fn approve(&mut self, r: &ProposalRef, run: &ValidationRunId) -> anyhow::Result<Value> {
        if !self.principal.author {
            return Err(denied());
        }
        let p = self.proposal(r)?;
        let checked: Checked = self.load(&format!("validation:{run}"))?;
        if !self.latest(&p.proposal)?
            || p.proposal.withdrawn
            || !matches!(p.proposal.submission, Submission::Submitted)
            || checked.proposal_digest != r.digest
            || !self.has_final(&checked, &p)
            || checked.validation.evaluator_version != EVALUATOR
            || !checked.admissible
            || self.kernel.head(&p.proposal.base_frame.continuity)?
                != p.proposal.base_frame.revision
        {
            return Err(ProtocolError::ApprovalStale.into());
        }
        // Approval binds both the exact resolved proposal and evaluator evidence.
        self.save(format!("approval:{}:{}:{run}",self.approval_author,r.digest),&json!({"author":self.principal.id,"proposal":r,"validation_digest":hash(&checked),"evaluator":EVALUATOR}))?;
        Ok(json!({"approved":r,"validation_run":run}))
    }
    pub fn execute(&mut self, request: Request) -> anyhow::Result<Value> {
        request.validate()?;
        let raw = serde_json::to_value(&request)?;
        let args = &raw["args"];
        if args.get("cursor").is_some()
            && !matches!(
                request,
                Request::Search(_)
                    | Request::GetOperation(_)
                    | Request::GetContext(_)
                    | Request::GetProposal(_)
            )
        {
            return Err(unsupported("this result does not support pagination"));
        }
        let mut frame = None;
        let mut world_focus = None;
        let mut cursor = None;
        let mut complete = true;
        let result = match request {
            Request::OpenContext(a) => {
                if let FrameTime::At { ref time } = a.temporal_query {
                    if universe_rules::time::relation(
                        time,
                        universe_domain::temporal::TemporalRelation::During,
                        time,
                    )
                    .is_none()
                    {
                        return Err(unsupported(
                            "temporal query requires an exact or bounded named-calendar interval",
                        ));
                    }
                }
                let revision = match a.revision {
                    RevisionSelector::Head => self.kernel.head(&a.continuity_id)?,
                    RevisionSelector::Exact { revision_id } => revision_id,
                };
                let records = self.kernel.records(&a.continuity_id, &revision)?;
                let visibility = self.visible_ids(&records)?;
                if let FrameTime::AtEvent { event, .. } = &a.temporal_query {
                    if !records.iter().any(|r| r.identity.record_id==event.record&&event.universe.as_ref()==Some(self.kernel.universe())&&visibility.contains(&r.identity.record_id)&&matches!(&r.payload,Payload::Event(e) if e.occurrence==OccurrenceMode::Occurred&&universe_rules::events::exact(&e.time).is_ok())){return Err(denied());}
                }
                let query_clock = match &a.temporal_query {
                    FrameTime::At {
                        time:
                            universe_domain::temporal::TemporalExpression::Exact { calendar, .. }
                            | universe_domain::temporal::TemporalExpression::Interval { calendar, .. },
                    } => Some(calendar),
                    _ => None,
                };
                for calendar in a.temporal_systems.iter().chain(query_clock) {
                    let id = calendar.as_str().replacen("cal_", "rec_", 1);
                    if !records.iter().any(|r| {
                        r.identity.record_id.as_str() == id
                            && matches!(r.payload, Payload::Calendar(_))
                            && visibility.contains(&r.identity.record_id)
                    }) {
                        return Err(denied());
                    }
                }
                if !records.iter().any(|r| {
                    r.identity.record_id == a.represented_context
                        && matches!(r.payload, Payload::RepresentedContext(_))
                        && visibility.contains(&r.identity.record_id)
                }) {
                    return Err(denied());
                }
                let f = Frame {
                    universe: self.kernel.universe().clone(),
                    continuity: a.continuity_id,
                    revision,
                    context: RecordRef::new(self.kernel.universe().clone(), a.represented_context),
                    time: a.temporal_query,
                    perspective: a.perspective,
                    reader_scene: a.reader_scene,
                    personal_sequence: None,
                };
                perspective_ids(&records, &f)?;
                let context_id = ContextId::generate(&mut rand::rng());
                self.save(
                    format!("context:{context_id}"),
                    &Context {
                        owner: self.principal.id.clone(),
                        scope: self.scope_hash(),
                        expires: now() + 3600,
                        frame: f.clone(),
                    },
                )?;
                frame = Some(f.clone());
                serde_json::to_value(OpenedContext {
                    context_id,
                    frame: f,
                })?
            }
            Request::Describe(ref a) => {
                let records = if let Some(id) = args.get("context_id") {
                    let c = self.context(&serde_json::from_value(id.clone())?)?;
                    frame = Some(c.frame.clone());
                    self.kernel
                        .records(&c.frame.continuity, &c.frame.revision)?
                } else {
                    vec![]
                };
                world_focus = self.focus(args, &records)?;
                let mut visibility = self.visible_ids(&records)?;
                if let Some(f) = &frame {
                    visibility = visibility
                        .intersection(&perspective_ids(&records, f)?)
                        .cloned()
                        .collect();
                }
                let worlds = records
                    .iter()
                    .filter(|r| visibility.contains(&r.identity.record_id))
                    .filter_map(|r| {
                        if let Payload::World(w) = &r.payload {
                            Some(WorldSummary {
                                id: universe_store::kernel::record_world(&r.identity.record_id),
                                name: Selector(w.selector.clone()),
                            })
                        } else {
                            None
                        }
                    })
                    .collect();
                let definition_ids = if matches!(a, Describe::Definitions { .. }) {
                    records
                        .iter()
                        .filter(|r| {
                            visibility.contains(&r.identity.record_id)
                                && operations::protected(&r.payload)
                                && world_focus.as_ref().is_none_or(|w| {
                                    let ws = operations::worlds(r);
                                    ws.is_empty() || ws.contains(w)
                                })
                        })
                        .map(|r| r.identity.record_id.clone())
                        .collect()
                } else {
                    vec![]
                };
                serde_json::to_value(Description{fixture:false,worlds,definition_ids,capabilities:vec![Capability{id:"source_assessment.v1".into(),status:CapabilityStatus::Partial,limitation:"Authenticated immutable attachment and generation-checked selection through universe_propose. Pinned permission-checked assessment retrieval and shared author review are available. Validation/approval/commit integration and native interaction qualification remain unavailable.".into()},Capability{id:"canon.commit.v1".into(),status:CapabilityStatus::Implemented,limitation:"Exact author approval or explicit expiring entity/predicate/continuity delegation; fresh complete validation and current grants required".into()},Capability{id:"opposing_evidence.v1".into(),status:CapabilityStatus::Implemented,limitation:"Candidate-wide polarity diagnostics and explicitly scoped NoOpposingEvidence policies. Unresolved comparisons remain partial; no prose or integrated-story qualification.".into()},Capability{id:"basic.v1".into(),status:CapabilityStatus::Implemented,limitation:"Exact scalar, finite collection and integer-tick temporal expressions; unsupported blocking checks fail admission".into()},Capability{id:"events.owner_attributes.v1".into(),status:CapabilityStatus::Implemented,limitation:"New/revised events require declared actions. Mandatory values resolve on exactly one participant per owning role at pre-event time; direct and explicit item grants share evidence. Missing, muted, conflicting and unsupported prerequisites block use. Legacy actionless events remain readable but are not certified; prose/action classification still requires author review.".into()},Capability{id:"events.v1".into(),status:CapabilityStatus::Implemented,limitation:"Exact occurred-event effects, explicit within-event order, pre/post state and possession powers. Noncommuting effects from separate simultaneous events and complex causality are rejected.".into()},
                    Capability{id:"knowledge.explicit.v1".into(),status:CapabilityStatus::Implemented,limitation:"Explicit, time-bound holder attitudes in their represented context. Presence, sending and receipt do not infer knowledge.".into()},
                    Capability{id:"perspective.views.v1".into(),status:CapabilityStatus::Implemented,limitation:"Character and narrator views require matching represented contexts. Reader views require an exact scene and explicit disclosures in its bound work edition. No automatic knowledge inference.".into()},
                    Capability{id:"history.v1".into(),status:CapabilityStatus::Implemented,limitation:"Typed summaries, evidence and pinned record history; history is limited to 100 changes per record and unrestricted author-perspective reads. Native restoration produces a reviewed compensating revision.".into()},
                    Capability{id:"knowledge.inference".into(),status:CapabilityStatus::Unsupported,limitation:"Automatic perception, understanding, nested attitude inference and memory decay require explicit author records.".into()},
                    Capability{id:"scoped.exceptions.v1".into(),status:CapabilityStatus::Partial,limitation:"Exact rule or boundary version with author acceptance and scope containment. Named-clock periods are partitioned at evidence and exception boundaries; original findings remain visible. Independent clocks and realm-dependent constraint inference remain unresolved.".into()},
                    Capability{id:"completeness.v1".into(),status:CapabilityStatus::Partial,limitation:"Exact objective membership and matching scope only; observer-known sets never close reality.".into()},
                    Capability{id:"impact.jobs.v1".into(),status:CapabilityStatus::Implemented,limitation:"Conservative full-universe dependency closure, durable queued validation, bound cursors and explicit work limits; no incremental result cache.".into()},
                    Capability{id:"continuities.packs.v1".into(),status:CapabilityStatus::Implemented,limitation:"Pinned forks, reviewed historical adoption and exact-version data-pack dependencies. No automatic parent propagation.".into()},
                    Capability{id:"cross_calendar.causality".into(),status:CapabilityStatus::Unsupported,limitation:"No inferred synchronization, route, speed, travel feasibility or causality across independent clocks.".into()},
                    Capability{id:"appearance.references.v1".into(),status:CapabilityStatus::Implemented,limitation:"Optional appearance records on any entry or universe; exact embedded PNG/JPEG/WebP assets, captions and explicit visual relationships. Text and metadata accompany context briefs; pixels do not imply facts or executable rules.".into()},
                    Capability{id:"descriptive.domain_records".into(),status:CapabilityStatus::DescriptiveOnly,limitation:"Custom domain data round-trips without acquiring executable laws from prose or labels.".into()}]})?
            }
            Request::Search(_)
            | Request::Get(_)
            | Request::GetState(_)
            | Request::GetContext(_) => {
                let ctx = self.context(&field(args, "context_id")?)?;
                frame = Some(ctx.frame.clone());
                let all = self
                    .kernel
                    .records(&ctx.frame.continuity, &ctx.frame.revision)?;
                world_focus = self.focus(args, &all)?;
                let mut visibility = self.visible_ids(&all)?;
                let perspective = perspective_ids(&all, &ctx.frame)?;
                visibility = visibility.intersection(&perspective).cloned().collect();
                let rule_ids: Vec<_> = all
                    .iter()
                    .filter(|r| matches!(r.payload, Payload::Rule(_)))
                    .map(|r| r.identity.record_id.clone())
                    .collect();
                let appearance_targets: Vec<_> = all
                    .iter()
                    .filter_map(|r| match &r.payload {
                        Payload::Appearance(a)
                            if universe_rules::time::applies(&a.validity, &ctx.frame.time)
                                != Some(false) =>
                        {
                            Some((r.identity.record_id.clone(), a.target.clone()))
                        }
                        _ => None,
                    })
                    .collect();
                let visible: Vec<_> = all
                    .into_iter()
                    .filter(|r| visibility.contains(&r.identity.record_id))
                    .collect();
                let seeds: Vec<_> = visible
                    .iter()
                    .filter(|r| {
                        world_focus.as_ref().is_none_or(|w| {
                            let ws = operations::worlds(r);
                            ws.is_empty() || ws.contains(w)
                        })
                    })
                    .map(|r| r.identity.record_id.clone())
                    .collect();
                let included = if world_focus.is_none() {
                    // visibility already closes authorization dependencies. Every
                    // visible record is present without another full graph walk.
                    seeds.into_iter().collect()
                } else {
                    dependency_closure(&visible, seeds)?.0
                };
                let accessible: Vec<_> = visible
                    .into_iter()
                    .filter(|r| included.contains(&r.identity.record_id))
                    .collect();
                match raw["tool"].as_str().unwrap_or("") {
                    "universe_search" => {
                        let query: String = field(args, "query")?;
                        let filters: Filters = field(args, "typed_filters")?;
                        let limit: usize = field(args, "limit")?;
                        let indexed: BTreeSet<_> = self
                            .kernel
                            .search(&ctx.frame.continuity, &ctx.frame.revision, &query)?
                            .into_iter()
                            .map(|r| r.identity.record_id)
                            .collect();
                        let mut hits: Vec<_> = accessible
                            .iter()
                            .filter(|r| {
                                filters.record_kinds.is_empty()
                                    || filters.record_kinds.contains(&r.identity.record_kind)
                            })
                            .filter(|r| {
                                query.is_empty()
                                    || indexed.contains(&r.identity.record_id)
                                    || name_matches(r, &query)
                                    || r.identity.record_id.as_str() == query
                            })
                            .map(|r| {
                                let ws = operations::worlds(r);
                                SearchHit {
                                    record_id: r.identity.record_id.clone(),
                                    kind: r.identity.record_kind,
                                    label: label(r),
                                    world_ids: ws.iter().cloned().collect(),
                                    scope_category: if ws.is_empty() {
                                        ScopeCategory::Unassigned
                                    } else if world_focus.as_ref().is_some_and(|w| !ws.contains(w))
                                    {
                                        ScopeCategory::RequiredDependency
                                    } else if ws.len() > 1 {
                                        ScopeCategory::Shared
                                    } else {
                                        ScopeCategory::SelectedWorld
                                    },
                                }
                            })
                            .collect();
                        hits.sort_by(|a, b| a.record_id.cmp(&b.record_id));
                        let offset = self.offset(args, &ctx.frame)?;
                        let end = (offset + limit).min(hits.len());
                        if offset > hits.len() {
                            return Err(denied());
                        }
                        if end < hits.len() {
                            cursor = Some(self.cursor(args, &ctx.frame, end)?);
                            complete = false;
                        }
                        serde_json::to_value(SearchResults {
                            hits: hits[offset..end].to_vec(),
                        })?
                    }
                    "universe_get" => {
                        let ids: Vec<RecordId> = field(args, "record_ids")?;
                        let groups: Vec<FieldGroup> = field(args, "field_groups")?;
                        let mut records = Vec::new();
                        for id in &ids {
                            if let Some(record) =
                                accessible.iter().find(|r| r.identity.record_id == *id)
                            {
                                records.push(record.clone());
                            } else if self.scope.is_some()
                                || !matches!(ctx.frame.perspective, Perspective::Author)
                                || !groups.iter().any(|g| matches!(g, FieldGroup::History))
                                || self
                                    .kernel
                                    .record_history(&ctx.frame.continuity, &ctx.frame.revision, id)?
                                    .is_empty()
                            {
                                return Err(denied());
                            }
                        }
                        let summaries = if groups.iter().any(|g| matches!(g, FieldGroup::Summary)) {
                            records
                                .iter()
                                .map(|r| RecordSummary {
                                    record_id: r.identity.record_id.clone(),
                                    kind: r.identity.record_kind,
                                    label: label(r),
                                })
                                .collect()
                        } else {
                            vec![]
                        };
                        let evidence = if groups.iter().any(|g| matches!(g, FieldGroup::Evidence)) {
                            let (needed, _) = research_closure(&accessible, ids.clone())?;
                            accessible
                                .iter()
                                .filter(|r| {
                                    needed.contains(&r.identity.record_id)
                                        && !ids.contains(&r.identity.record_id)
                                })
                                .cloned()
                                .collect()
                        } else {
                            vec![]
                        };
                        let mut history = Vec::new();
                        let history_coverage =
                            if groups.iter().any(|g| matches!(g, FieldGroup::History)) {
                                if self.scope.is_some()
                                    || !matches!(ctx.frame.perspective, Perspective::Author)
                                {
                                    Some(Coverage::Restricted)
                                } else {
                                    for id in &ids {
                                        for entry in self.kernel.record_history(
                                            &ctx.frame.continuity,
                                            &ctx.frame.revision,
                                            id,
                                        )? {
                                            history.push(serde_json::from_value(entry)?);
                                        }
                                    }
                                    Some(Coverage::Complete)
                                }
                            } else {
                                None
                            };
                        if !groups.is_empty()
                            && !groups.iter().any(|g| matches!(g, FieldGroup::Payload))
                        {
                            records.clear();
                        }
                        serde_json::to_value(Records {
                            records,
                            summaries,
                            evidence,
                            history,
                            history_coverage,
                        })?
                    }
                    "universe_get_state" => {
                        let ids: Vec<RecordId> = field(args, "entity_ids")?;
                        for id in &ids {
                            if !accessible.iter().any(|r| r.identity.record_id == *id) {
                                return Err(denied());
                            }
                        }
                        let query_time = if let Some(id) = args.get("event") {
                            let event: RecordId = serde_json::from_value(id.clone())?;
                            if !accessible.iter().any(|r|r.identity.record_id==event&&matches!(&r.payload,Payload::Event(e) if e.occurrence==OccurrenceMode::Occurred)){return Err(denied());}
                            FrameTime::AtEvent {
                                event: RecordRef::new(self.kernel.universe().clone(), event),
                                side: field(args, "event_side")?,
                            }
                        } else {
                            ctx.frame.time.clone()
                        };
                        frame = Some(Frame {
                            time: query_time.clone(),
                            ..ctx.frame.clone()
                        });
                        let matches_focus = |scope: &universe_domain::scope::Scope| {
                            world_focus.as_ref().is_none_or(|w|!matches!(&scope.applicability,Applicability::Worlds{world_ids} if !world_ids.contains(w)))
                        };
                        let predicates: Vec<RecordId> = field(args, "predicate_filters")?;
                        let propositions: BTreeSet<_> = accessible
                            .iter()
                            .filter_map(|r| {
                                if let Payload::Proposition(p) = &r.payload {
                                    if ids.contains(&p.subject.record)
                                        && p.context == ctx.frame.context
                                        && (predicates.is_empty()
                                            || predicates.contains(&p.predicate.record))
                                    {
                                        Some(r.identity.record_id.clone())
                                    } else {
                                        None
                                    }
                                } else {
                                    None
                                }
                            })
                            .collect();
                        let assertions:Vec<_>=accessible.iter().filter(|r|matches!(&r.payload,Payload::Assertion(a) if propositions.contains(&a.proposition.record)&&matches_focus(&a.scope)&&a.scope.context==ctx.frame.context&&universe_rules::events::applies(&a.validity,&query_time,&accessible)!=Some(false))).cloned().collect();
                        let completeness=accessible.iter().filter(|r|matches!(&r.payload,Payload::Completeness(c) if ids.contains(&c.subject.record)&&matches_focus(&c.scope)&&c.scope.context==ctx.frame.context&&universe_rules::events::applies(&c.validity,&query_time,&accessible)!=Some(false)&&(predicates.is_empty()||predicates.iter().any(|p|p.as_str()==c.predicate)))).cloned().collect();
                        let proposition_records = accessible
                            .iter()
                            .filter(|r| propositions.contains(&r.identity.record_id))
                            .cloned()
                            .collect();
                        let chronology = accessible.iter().find_map(|r| {
                            if r.identity.record_id == ctx.frame.context.record {
                                if let Payload::RepresentedContext(c) = &r.payload {
                                    c.chronology.clone()
                                } else {
                                    None
                                }
                            } else {
                                None
                            }
                        });
                        let unresolved_assertion_ids=assertions.iter().filter(|r|matches!(&r.payload,Payload::Assertion(a) if universe_rules::events::applies(&a.validity,&query_time,&accessible).is_none())).map(|r|r.identity.record_id.clone()).collect();
                        let derived = crate::powers::derive(
                            &accessible,
                            &ids,
                            &predicates,
                            &ctx.frame.context,
                            &query_time,
                            world_focus.as_ref(),
                        )?;
                        let epistemic = accessible
                            .iter()
                            .filter(|r| match &r.payload {
                                Payload::EpistemicAttitude(a) => {
                                    ids.contains(&a.holder.record)
                                        && accessible.iter().any(|p|p.identity.record_id==a.proposition.record&&matches!(&p.payload,Payload::Proposition(p) if p.context==ctx.frame.context))
                                        && universe_rules::events::applies(
                                            &a.validity,
                                            &query_time,
                                            &accessible,
                                        ) != Some(false)
                                }
                                Payload::Memory(m) => {
                                    ids.contains(&m.holder.record)
                                        && accessible.iter().any(|p|p.identity.record_id==m.content.record&&matches!(&p.payload,Payload::Proposition(p) if p.context==ctx.frame.context))
                                        && universe_rules::events::applies(
                                            &m.validity,
                                            &query_time,
                                            &accessible,
                                        ) != Some(false)
                                }
                                _ => false,
                            })
                            .cloned()
                            .collect();
                        serde_json::to_value(State{epistemic,derived,chronology,unresolved_assertion_ids,assertions,propositions:proposition_records,completeness,coverage:Coverage::Partial,unsupported_capabilities:vec!["Explicit evidence filtered by the authored time frame; unresolved validities remain visible. Exact event effects and explicit possession powers are evaluated; complex causality and temporal completeness inference remain unavailable; absent evidence remains undefined.".into()]})?
                    }
                    _ => {
                        let cache_key = hash(&(
                            args,
                            &ctx.frame,
                            &self.principal.id,
                            &self.scope,
                            self.permissions,
                            EVALUATOR,
                        ));
                        if let Some(brief) = cached_brief(&cache_key) {
                            complete = brief["complete"] == true;
                            if let Some(next) = brief["next"].as_u64() {
                                cursor = Some(self.cursor(args, &ctx.frame, next as usize)?);
                            }
                            return self.wrap(
                                args,
                                frame,
                                world_focus,
                                complete,
                                cursor,
                                brief["brief"].clone(),
                            );
                        }
                        let ids: Vec<RecordId> = field(args, "focus_ids")?;
                        let budget: usize = field(args, "byte_budget")?;
                        for id in &ids {
                            if !accessible.iter().any(|r| r.identity.record_id == *id) {
                                return Err(denied());
                            }
                        }
                        // Include every visible rule before focus records, then the transitive
                        // typed dependencies. Relevance and purpose text never remove constraints.
                        let rules = rule_ids;
                        let hidden_rule = rules
                            .iter()
                            .any(|id| !accessible.iter().any(|r| r.identity.record_id == *id));
                        let seeds: Vec<_> = rules
                            .iter()
                            .filter(|id| accessible.iter().any(|r| &r.identity.record_id == *id))
                            .cloned()
                            .chain(ids.iter().cloned())
                            .collect();
                        let appearance_records: Vec<_> = accessible
                            .iter()
                            .filter(|r| match &r.payload {
                                Payload::Appearance(a) => {
                                    universe_rules::time::applies(&a.validity, &ctx.frame.time)
                                        != Some(false)
                                }
                                _ => true,
                            })
                            .cloned()
                            .collect();
                        let (needed, closed) =
                            research_closure(&appearance_records, seeds.clone())?;
                        let mut required_dependencies = Vec::new();
                        let order: Vec<_> =
                            seeds.into_iter().chain(needed.iter().cloned()).collect();
                        let mut seen = BTreeSet::new();
                        let mut selected = Vec::new();
                        let hidden_appearance = appearance_targets.iter().any(|(id, target)| {
                            !visibility.contains(id)
                                && match target {
                                    AppearanceTarget::Universe => true,
                                    AppearanceTarget::Entry { entry } => {
                                        needed.contains(&entry.record)
                                    }
                                }
                        });
                        let coverage_complete = closed
                            && !hidden_rule
                            && !hidden_appearance
                            && self.scope.is_none()
                            && matches!(ctx.frame.perspective, Perspective::Author);
                        let by_id: std::collections::BTreeMap<_, _> = accessible
                            .iter()
                            .map(|r| (&r.identity.record_id, r))
                            .collect();
                        let ordered: Vec<_> = order
                            .into_iter()
                            .filter(|id| seen.insert(id.clone()))
                            .filter_map(|id| by_id.get(&id).copied())
                            .collect();
                        let start = self.offset(args, &ctx.frame)?;
                        if start > ordered.len() {
                            return Err(denied());
                        }
                        let mut end = start;
                        for r in &ordered[start..] {
                            selected.push((*r).clone());
                            let dependency = !ids.contains(&r.identity.record_id);
                            if dependency {
                                required_dependencies.push(r.identity.record_id.clone());
                            }
                            let trial = ContextBrief {
                                records: selected.clone(),
                                required_dependencies: required_dependencies.clone(),
                                coverage: Coverage::Partial,
                            };
                            if serde_json::to_vec(&trial)?.len() > budget {
                                selected.pop();
                                if dependency {
                                    required_dependencies.pop();
                                }
                                break;
                            }
                            end += 1;
                        }
                        if end == start && start < ordered.len() {
                            return Err(ProtocolError::EvaluationLimitReached { message: "context budget cannot fit the next mandatory record and dependency manifest; increase byte_budget".into() }.into());
                        }
                        complete = end == ordered.len();
                        if !complete {
                            cursor = Some(self.cursor(args, &ctx.frame, end)?);
                        }
                        let brief = ContextBrief {
                            records: selected,
                            required_dependencies,
                            coverage: if coverage_complete && complete && start == 0 {
                                Coverage::Complete
                            } else {
                                Coverage::Partial
                            },
                        };
                        if serde_json::to_vec(&brief)?.len() > budget {
                            return Err(ProtocolError::EvaluationLimitReached {
                                message:
                                    "mandatory dependency manifest exceeds the context byte budget"
                                        .into(),
                            }
                            .into());
                        }
                        let brief = serde_json::to_value(brief)?;
                        cache_brief(
                            cache_key,
                            json!({"brief":brief,"complete":complete,"next":if complete {None} else {Some(end)}}),
                        );
                        brief
                    }
                }
            }
            Request::Propose(
                action @ (Propose::AttachAssessment { .. } | Propose::SelectAssessment { .. }),
            ) => {
                let ctx = self.context(&field(args, "context_id")?)?;
                let r: ProposalRef = field(args, "proposal_reference")?;
                let p = self.proposal(&r).map_err(|_| denied())?;
                if ctx.frame != p.proposal.base_frame {
                    return Err(ProtocolError::ApprovalStale.into());
                }
                frame = Some(ctx.frame);
                world_focus = p.proposal.world_scope.clone();
                let selection = match action {
                    Propose::AttachAssessment {
                        expected_selection_generation,
                        body,
                        idempotency_key,
                        ..
                    } => self.attach_assessment(
                        &r,
                        expected_selection_generation,
                        *body,
                        &idempotency_key,
                    )?,
                    Propose::SelectAssessment {
                        expected_selection_generation,
                        assessment_reference,
                        idempotency_key,
                        ..
                    } => self.select_assessment(
                        &r,
                        expected_selection_generation,
                        assessment_reference,
                        &idempotency_key,
                    )?,
                    _ => unreachable!(),
                };
                serde_json::to_value(selection)?
            }
            Request::Propose(_) => {
                if !matches!(
                    self.context(&field(args, "context_id")?)?.frame.time,
                    FrameTime::Timeless
                ) {
                    return Err(unsupported(
                        "create or revise proposals from an all-validities author frame",
                    ));
                }
                let key: String = field(args, "idempotency_key")?;
                let receipt_key = self.operation_key("propose", &key);
                let digest = hash(args);
                if self.kernel.workflow_get(&receipt_key)?.is_some() {
                    let op = self.operation(&receipt_key)?;
                    if op.digest != digest {
                        return Err(ProtocolError::IdempotencyKeyReused {
                            message: "request differs".into(),
                        }
                        .into());
                    }
                    serde_json::to_value(op.status.proposal.ok_or_else(denied)?)?
                } else {
                    let ctx = self.context(&field(args, "context_id")?)?;
                    frame = Some(ctx.frame.clone());
                    if !matches!(ctx.frame.perspective, Perspective::Author) {
                        return Err(unsupported("proposals require an author perspective frame"));
                    }
                    let base = self
                        .kernel
                        .records(&ctx.frame.continuity, &ctx.frame.revision)?;
                    world_focus = self.focus(args, &base)?;
                    let action = args["action"].as_str().unwrap_or("");
                    let previous = if action == "create" {
                        None
                    } else {
                        let r: ProposalRef = field(args, "proposal_reference")?;
                        let p = self.proposal(&r)?;
                        if !self.latest(&p.proposal)? {
                            return Err(ProtocolError::ApprovalStale.into());
                        }
                        Some(p)
                    };
                    let mut p = if matches!(action, "create" | "revise") {
                        let operations: Vec<DomainOperation> = field(args, "operations")?;
                        let changes =
                            operations::compile(self.kernel.universe(), &base, &operations)?;
                        let footprint = operations::footprint(&base, &changes);
                        let id = previous
                            .as_ref()
                            .map(|p| p.proposal.proposal_id.clone())
                            .unwrap_or_else(|| ProposalId::generate(&mut rand::rng()));
                        StoredProposal {
                            owner: self.principal.id.clone(),
                            author_origin: self.principal.author,
                            changes,
                            footprint,
                            proposal: Proposal {
                                base_frame: ctx.frame.clone(),
                                world_scope: world_focus.clone(),
                                proposal_id: id,
                                version: previous.as_ref().map_or(1, |p| p.proposal.version + 1),
                                digest: String::new(),
                                submission: field(args, "submission")?,
                                operations,
                                compiled_changes: vec![],
                                rationale: field(args, "rationale")?,
                                canonical: false,
                                operation_id: OperationId::generate(&mut rand::rng()),
                                withdrawn: false,
                            },
                        }
                    } else {
                        let mut p = previous.ok_or_else(denied)?;
                        if p.proposal.base_frame != ctx.frame {
                            return Err(ProtocolError::ApprovalStale.into());
                        }
                        p.proposal.version += 1;
                        p.proposal.operation_id = OperationId::generate(&mut rand::rng());
                        p.proposal.digest.clear();
                        if action == "withdraw" {
                            p.proposal.withdrawn = true;
                        } else {
                            p.proposal.submission = Submission::Submitted;
                        }
                        p
                    };
                    self.authorize(&p.footprint, false)?;
                    if matches!(action, "create" | "revise") {
                        for change in &p.changes {
                            if change.expected.is_none() {
                                let reserved = self.kernel.workflow_get(&format!(
                                    "reserved-record:{}",
                                    change.record_id
                                ))?;
                                let adoption = p.proposal.operations.iter().find_map(|op| {
                                    if let DomainOperation::AdoptRecordVersion { source, .. } = op {
                                        (source.identity.record_id == change.record_id)
                                            .then_some(source)
                                    } else {
                                        None
                                    }
                                });
                                let historical = if let Some(source) = adoption {
                                    self.kernel.record_version(&source.record_version_id)?
                                        == **source
                                } else {
                                    false
                                };
                                if !historical
                                    && (self.kernel.identity_exists(&change.record_id)?
                                        || reserved.is_some_and(|v| {
                                            v["proposal_id"] != p.proposal.proposal_id.as_str()
                                        }))
                                {
                                    return Err(ProtocolError::invalid_argument("client_ref","record identity is already reserved by another proposal or canon").into());
                                }
                            }
                        }
                    }
                    if world_focus.as_ref().is_some_and(|w| {
                        p.footprint.shared || p.footprint.worlds.iter().any(|actual| actual != w)
                    }) {
                        return Err(ProtocolError::WorldScopeConflict{message:"full write footprint exceeds named world; omit focus for an explicit cross-world proposal".into()}.into());
                    }
                    self.write_boundaries(&p)?;
                    // Structural validation happens before a durable proposal is admitted.
                    p.proposal.digest = hash(&(&p.proposal, &p.changes, &p.footprint));
                    if matches!(action, "create" | "revise") {
                        self.kernel
                            .preview(&self.input(&p, "proposal-preview".into())?)?;
                    }
                    let op = StoredOperation {
                        owner: self.principal.id.clone(),
                        digest,
                        status: OperationStatus {
                            validation: None,
                            failure: None,
                            operation_id: p.proposal.operation_id.clone(),
                            kind: OperationKind::Propose,
                            state: OperationState::Succeeded,
                            proposal: Some(p.proposal.clone()),
                            receipt: None,
                            cancellation_requested: false,
                        },
                        input: None,
                        validation_capture: None,
                        footprint: p.footprint.clone(),
                    };
                    let mut entries = vec![
                        (
                            format!(
                                "proposal:{}:{:020}",
                                p.proposal.proposal_id, p.proposal.version
                            ),
                            serde_json::to_value(&p)?,
                        ),
                        (receipt_key, serde_json::to_value(&op)?),
                        (
                            format!("operation:{}", op.status.operation_id),
                            serde_json::to_value(&op)?,
                        ),
                    ];
                    for change in p.changes.iter().filter(|c| c.expected.is_none()) {
                        let key = format!("reserved-record:{}", change.record_id);
                        if self.kernel.workflow_get(&key)?.is_none() {
                            entries.push((key, json!({"proposal_id":p.proposal.proposal_id})));
                        }
                    }
                    self.persist(&entries)?;
                    serde_json::to_value(p.proposal)?
                }
            }
            Request::GetProposal(a) => {
                let p: StoredProposal =
                    self.load(&format!("proposal:{}:{:020}", a.proposal_id, a.version))?;
                let p = self.proposal(&ProposalRef {
                    proposal_id: a.proposal_id,
                    version: a.version,
                    digest: p.proposal.digest,
                })?;
                frame = Some(p.proposal.base_frame.clone());
                if matches!(a.view_group, Some(ProposalView::Assessment)) {
                    let (page, done, next) =
                        self.assessment_page(args, &p, a.assessment_reference.as_ref())?;
                    return self.wrap(
                        args,
                        frame,
                        world_focus,
                        done,
                        next,
                        serde_json::to_value(page)?,
                    );
                }
                let mut proposal = p.proposal;
                let start = self.offset(args, &proposal.base_frame)?;
                let total = proposal.operations.len().max(p.changes.len());
                if start > total {
                    return Err(denied());
                }
                let mut end = start;
                let mut bytes = 0;
                while end < total {
                    let size = serde_json::to_vec(&proposal.operations.get(end))?.len()
                        + serde_json::to_vec(&p.changes.get(end))?.len();
                    if end > start && (bytes + size > 65536 || end - start >= 20) {
                        break;
                    }
                    bytes += size;
                    end += 1;
                }
                complete = end == total;
                if !complete {
                    cursor = Some(self.cursor(args, &proposal.base_frame, end)?);
                }
                proposal.operations = proposal.operations
                    [start.min(proposal.operations.len())..end.min(proposal.operations.len())]
                    .to_vec();
                proposal.compiled_changes = p.changes
                    [start.min(p.changes.len())..end.min(p.changes.len())]
                    .iter()
                    .map(|c| CompiledChange {
                        record_id: c.record_id.clone(),
                        expected: c.expected.clone(),
                        next: c.next.clone(),
                    })
                    .collect();
                serde_json::to_value(proposal)?
            }
            Request::Validate(_) => {
                let ctx = self.context(&field(args, "context_id")?)?;
                frame = Some(ctx.frame.clone());
                if !matches!(ctx.frame.perspective, Perspective::Author) {
                    return Err(unsupported(
                        "validation requires an author perspective frame",
                    ));
                }
                // A restricted research check must not compile against hidden definitions:
                // even a compiler error could otherwise disclose their existence or shape.
                if args["mode"] == "inline" && self.scope.is_some() {
                    let base = self
                        .kernel
                        .records(&ctx.frame.continuity, &ctx.frame.revision)?;
                    world_focus = self.focus(args, &base)?;
                    return self.wrap(
                        args,
                        frame,
                        world_focus,
                        true,
                        None,
                        serde_json::to_value(ValidationV3::restricted())?,
                    );
                }
                let p = if args["mode"] == "proposal" || args["mode"] == "queued_proposal" {
                    self.proposal(&field(args, "proposal_reference")?)?
                } else {
                    let base = self
                        .kernel
                        .records(&ctx.frame.continuity, &ctx.frame.revision)?;
                    let operations: Vec<DomainOperation> = field(args, "operations")?;
                    let changes = operations::compile(self.kernel.universe(), &base, &operations)?;
                    let footprint = operations::footprint(&base, &changes);
                    world_focus = self.focus(args, &base)?;
                    if world_focus.as_ref().is_some_and(|w| {
                        footprint.shared || footprint.worlds.iter().any(|actual| actual != w)
                    }) {
                        return Err(ProtocolError::WorldScopeConflict {
                            message: "full write footprint exceeds named world".into(),
                        }
                        .into());
                    }
                    StoredProposal {
                        owner: self.principal.id.clone(),
                        author_origin: self.principal.author,
                        changes,
                        footprint,
                        proposal: Proposal {
                            base_frame: ctx.frame.clone(),
                            world_scope: world_focus.clone(),
                            proposal_id: ProposalId::generate(&mut rand::rng()),
                            version: 1,
                            digest: hash(args),
                            submission: Submission::Draft,
                            operations,
                            compiled_changes: vec![],
                            rationale: "inline validation".into(),
                            canonical: false,
                            operation_id: OperationId::generate(&mut rand::rng()),
                            withdrawn: false,
                        },
                    }
                };
                if p.proposal.base_frame != ctx.frame {
                    return Err(ProtocolError::ApprovalStale.into());
                }
                if args["mode"] != "inline" {
                    self.write_boundaries(&p)?;
                }
                if args["mode"] == "queued_proposal" {
                    let key =
                        self.operation_key("validate", &field::<String>(args, "idempotency_key")?);
                    let digest = hash(args);
                    let op = if self.kernel.workflow_get(&key)?.is_some() {
                        let saved = self.operation(&key)?;
                        let op =
                            self.operation(&format!("operation:{}", saved.status.operation_id))?;
                        if op.digest != digest {
                            return Err(ProtocolError::IdempotencyKeyReused {
                                message: "validation request differs".into(),
                            }
                            .into());
                        }
                        op
                    } else {
                        let id = OperationId::generate(&mut rand::rng());
                        let validation = Validation {
                            operation_id: Some(id.clone()),
                            run_id: ValidationRunId::generate(&mut rand::rng()),
                            coverage: Coverage::Partial,
                            findings: vec![],
                            opposing_evidence: vec![],
                            unsupported_capabilities: vec![
                                "Validation queued; poll this operation for completed evidence"
                                    .into(),
                            ],
                            input_digest: p.proposal.digest.clone(),
                            evaluator_version: EVALUATOR.into(),
                        };
                        let op = StoredOperation {
                            owner: self.principal.id.clone(),
                            digest,
                            status: OperationStatus {
                                validation: Some(Box::new(validation)),
                                failure: None,
                                operation_id: id,
                                kind: OperationKind::Validate,
                                state: OperationState::Queued,
                                proposal: Some(p.proposal.clone()),
                                receipt: None,
                                cancellation_requested: false,
                            },
                            input: None,
                            validation_capture: if self.scope.is_some() {
                                None
                            } else {
                                Some(self.capture_validation(&p)?)
                            },
                            footprint: p.footprint.clone(),
                        };
                        self.persist(&[
                            (key, serde_json::to_value(&op)?),
                            (
                                format!("operation:{}", op.status.operation_id),
                                serde_json::to_value(&op)?,
                            ),
                        ])?;
                        op
                    };
                    return self.wrap(
                        args,
                        frame,
                        None,
                        true,
                        None,
                        serde_json::to_value(
                            self.public_status(op.status)?
                                .validation
                                .ok_or_else(denied)?,
                        )?,
                    );
                }
                let capture = if args["mode"] == "inline" || self.scope.is_some() {
                    None
                } else {
                    Some(self.capture_validation(&p)?)
                };
                let mut checked = self.check(&p)?;
                checked.capture = capture.clone();
                checked.report = Some(if args["mode"] == "inline" {
                    Self::query_report(
                        checked.validation.clone(),
                        ctx.frame.clone(),
                        field(args, "check_scope")?,
                    )
                } else if let Some(capture) = &capture {
                    capture.report(&p, checked.validation.clone(), true)?
                } else {
                    ValidationV3::restricted()
                });
                self.persist_bound_validation(
                    &p,
                    capture.as_ref(),
                    &[(
                        format!("validation:{}", checked.validation.run_id),
                        serde_json::to_value(&checked)?,
                    )],
                )?;
                serde_json::to_value(checked.report)?
            }
            Request::Commit(a) => {
                let p = self.proposal(&a.proposal_reference)?;
                self.authorize(&p.footprint, true)?;
                self.write_boundaries(&p)?;
                frame = Some(p.proposal.base_frame.clone());
                let key = self.operation_key("commit", &a.idempotency_key);
                let digest = hash(args);
                if self.kernel.workflow_get(&key)?.is_some() {
                    let op = self.operation(&key)?;
                    if op.digest != digest {
                        return Err(ProtocolError::IdempotencyKeyReused {
                            message: "request differs".into(),
                        }
                        .into());
                    }
                    if let Some(receipt) = op.status.receipt {
                        return self.wrap(
                            args,
                            frame,
                            None,
                            true,
                            None,
                            serde_json::to_value(receipt)?,
                        );
                    }
                }
                if !self.latest(&p.proposal)?
                    || p.proposal.withdrawn
                    || !matches!(p.proposal.submission, Submission::Submitted)
                    || a.expected_base_revision != p.proposal.base_frame.revision
                {
                    return Err(ProtocolError::ApprovalStale.into());
                }
                let checked: Checked = self.load(&format!("validation:{}", a.validation_run))?;
                if checked.proposal_digest != p.proposal.digest
                    || !checked.admissible
                    || !self.has_final(&checked, &p)
                    || checked.validation.evaluator_version != EVALUATOR
                {
                    return Err(ProtocolError::ApprovalStale.into());
                }
                let limits = self.limits();
                let delegated = limits.delegated_commit
                    && !p.footprint.protected
                    && (!p.footprint.shared || limits.allow_shared)
                    && checked.validation.coverage == Coverage::Complete;
                if !delegated {
                    let approval = self
                        .kernel
                        .workflow_get(&format!(
                            "approval:{}:{}:{}",
                            self.approval_author, p.proposal.digest, a.validation_run
                        ))?
                        .ok_or_else(|| ProtocolError::ApprovalRequired {
                            message: "author must approve this exact proposal and validation"
                                .into(),
                        })?;
                    if approval["evaluator"] != EVALUATOR
                        || approval["author"] != self.approval_author.as_str()
                        || approval["validation_digest"] != hash(&checked)
                    {
                        return Err(ProtocolError::ApprovalStale.into());
                    }
                }
                let head = self.kernel.head(&p.proposal.base_frame.continuity)?;
                if head != a.expected_base_revision {
                    return Err(ProtocolError::BaseRevisionConflict {
                        expected: a.expected_base_revision.0,
                        actual: head.0,
                    }
                    .into());
                }
                // Exact author approval and an unchanged head authorize this private recheck.
                // Its evidence must not be disclosed to a scoped committing client.
                let scope = self.scope.take();
                let fresh = self.check(&p);
                self.scope = scope;
                let fresh = fresh?;
                if !fresh.admissible {
                    return Err(ProtocolError::ApprovalStale.into());
                }
                let input = self.input(&p, a.idempotency_key)?;
                let op = if self.kernel.workflow_get(&key)?.is_some() {
                    self.operation(&key)?
                } else {
                    let op = StoredOperation {
                        owner: self.principal.id.clone(),
                        digest,
                        status: OperationStatus {
                            validation: None,
                            failure: None,
                            operation_id: OperationId::generate(&mut rand::rng()),
                            kind: OperationKind::Commit,
                            state: OperationState::Committing,
                            proposal: Some(p.proposal.clone()),
                            receipt: None,
                            cancellation_requested: false,
                        },
                        validation_capture: None,
                        input: Some(input.clone()),
                        footprint: p.footprint.clone(),
                    };
                    self.persist(&[
                        (key, serde_json::to_value(&op)?),
                        (
                            format!("operation:{}", op.status.operation_id),
                            serde_json::to_value(&op)?,
                        ),
                    ])?;
                    op
                };
                if op.status.cancellation_requested {
                    return Err(ProtocolError::PolicyDenied {
                        message: "operation cancelled before commit".into(),
                    }
                    .into());
                }
                let authority = self.authority.clone();
                let _guard = authority.as_ref().map(|a| a.lock()).transpose()?;
                // The universe worker serializes candidates. SQLite rechecks the head
                // and publishes the revision and receipt under this current-authority gate.
                let revision = self.kernel.commit(&input)?;
                serde_json::to_value(CommitReceipt {
                    operation_id: op.status.operation_id,
                    proposal_id: p.proposal.proposal_id,
                    revision,
                })?
            }
            Request::GetOperation(_) => {
                let key = if let Some(id) = args.get("operation_id") {
                    format!("operation:{}", id.as_str().ok_or_else(denied)?)
                } else {
                    self.operation_key(
                        args["operation_kind"].as_str().ok_or_else(denied)?,
                        &field::<String>(args, "idempotency_key")?,
                    )
                };
                let mut status = self.operation(&key)?.status;
                if let Some(proposal) = &status.proposal {
                    frame = Some(proposal.base_frame.clone());
                }
                if self.scope.is_some() && status.validation.is_some() {
                    if args.get("cursor").is_some() {
                        return Err(denied());
                    }
                    // Do not page private findings or expose their cursor/count metadata.
                    return self.wrap(
                        args,
                        frame,
                        None,
                        true,
                        None,
                        serde_json::to_value(self.public_status(status)?)?,
                    );
                }
                if let Some(validation) = &mut status.validation {
                    let pinned = frame.as_ref().ok_or_else(denied)?;
                    let mut binding = args.clone();
                    binding["result_digest"] = json!(hash(&validation));
                    binding["resolved_operation"] = json!(status.operation_id);
                    let start = self.offset(&binding, pinned)?;
                    if start > validation.findings.len() {
                        return Err(denied());
                    }
                    let end = (start + 100).min(validation.findings.len());
                    if end < validation.findings.len() {
                        cursor = Some(self.cursor(&binding, pinned, end)?);
                        complete = false;
                    }
                    validation.findings = validation.findings[start..end].to_vec();
                } else if args.get("cursor").is_some() {
                    return Err(denied());
                }
                serde_json::to_value(self.public_status(status)?)?
            }
            Request::CancelOperation(a) => {
                let mut op = self.operation(&format!("operation:{}", a.operation_id))?;
                let key = self.operation_key("cancel", &a.idempotency_key);
                let digest = hash(args);
                if let Some(existing) = self.kernel.workflow_get(&key)? {
                    let saved: StoredOperation = serde_json::from_value(existing)?;
                    if saved.digest != digest {
                        return Err(ProtocolError::IdempotencyKeyReused {
                            message: "cancel key names another request".into(),
                        }
                        .into());
                    }
                    serde_json::to_value(self.public_status(self.operation(&key)?.status)?)?
                } else {
                    let mut entries = Vec::new();
                    if !matches!(
                        op.status.state,
                        OperationState::Succeeded | OperationState::Failed
                    ) {
                        entries.push((
                            format!("cancel:{}", a.operation_id),
                            json!({"owner":self.principal.id,"cancelled":true}),
                        ));
                        op.status.state = OperationState::Cancelled;
                        op.status.cancellation_requested = true;
                    }
                    op.digest = digest;
                    entries.push((key, serde_json::to_value(&op)?));
                    self.persist(&entries)?;
                    cancel_validation(self.kernel.universe(), &a.operation_id);
                    serde_json::to_value(self.public_status(op.status)?)?
                }
            }
            Request::GetImpact(_) => {
                let ctx = self.context(&field(args, "context_id")?)?;
                frame = Some(ctx.frame.clone());
                let mut all = self
                    .kernel
                    .records(&ctx.frame.continuity, &ctx.frame.revision)?;
                if !matches!(ctx.frame.perspective, Perspective::Author) {
                    return Err(unsupported("impact requires an author perspective frame"));
                }
                world_focus = self.focus(args, &all)?;
                let seeds: Vec<RecordId> = if args["mode"] == "proposal" {
                    let p = self.proposal(&field(args, "proposal_reference")?)?;
                    if p.proposal.base_frame != ctx.frame {
                        return Err(ProtocolError::ApprovalStale.into());
                    }
                    self.authorize(&p.footprint, false)?;
                    all.extend(p.changes.iter().filter_map(|c| c.next.clone()));
                    p.changes.iter().map(|c| c.record_id.clone()).collect()
                } else {
                    field(args, "changed_records")?
                };
                let visibility = self.visible_ids(&all)?;
                for id in &seeds {
                    if !all.iter().any(|r| {
                        r.identity.record_id == *id && visibility.contains(&r.identity.record_id)
                    }) {
                        return Err(denied());
                    }
                }
                // Conservative universe closure includes query-scope dependencies:
                // adding a fact may change a prior absence/cardinality conclusion.
                let restricted = all
                    .iter()
                    .any(|r| !visibility.contains(&r.identity.record_id));
                let records: BTreeSet<_> = all
                    .iter()
                    .filter(|r| visibility.contains(&r.identity.record_id))
                    .map(|r| r.identity.record_id.clone())
                    .collect();
                let world_ids: BTreeSet<_> = all
                    .iter()
                    .filter(|r| visibility.contains(&r.identity.record_id))
                    .flat_map(operations::worlds)
                    .collect();
                let impact = serde_json::to_value(Impact {
                    records: records.into_iter().collect(),
                    coverage: if restricted {
                        Coverage::Restricted
                    } else {
                        Coverage::Complete
                    },
                    world_ids: world_ids.into_iter().collect(),
                })?;
                if serde_json::to_vec(&impact)?.len() > field::<usize>(args, "byte_budget")? {
                    return Err(ProtocolError::EvaluationLimitReached {
                        message: "conservative impact closure exceeds the requested byte budget"
                            .into(),
                    }
                    .into());
                }
                impact
            }
        };
        self.wrap(args, frame, world_focus, complete, cursor, result)
    }
    fn wrap(
        &self,
        args: &Value,
        frame: Option<Frame>,
        world_focus: Option<WorldId>,
        complete: bool,
        cursor: Option<String>,
        result: Value,
    ) -> anyhow::Result<Value> {
        let value = json!({"contract_version":universe_protocol::PROTOCOL_VERSION,"request_id":0,"universe_id":self.kernel.universe(),"universe":self.name,"alias_matched":args["universe"]!=self.name,"frame":frame,"world_focus":world_focus,"authorization_scope":if self.scope.is_some(){"world-scoped grant"}else{"universe grant"},"delivery":{"complete":complete,"cursor":cursor},"result":result});
        if serde_json::to_vec(&value)?.len() > 900_000 {
            return Err(ProtocolError::EvaluationLimitReached {
                message: "response exceeds bounded transport; narrow the batch".into(),
            }
            .into());
        }
        Ok(value)
    }
    fn focus(&self, args: &Value, records: &[RecordVersion]) -> anyhow::Result<Option<WorldId>> {
        let Some(name) = args.get("world").and_then(Value::as_str) else {
            return Ok(None);
        };
        let key = universe_store::selector::selector_key(name)?;
        let visibility = self.visible_ids(records)?;
        let world = records
            .iter()
            .filter(|r| visibility.contains(&r.identity.record_id))
            .find(|r| {
                if let Payload::World(w) = &r.payload {
                    std::iter::once(&w.selector)
                        .chain(w.aliases.iter())
                        .any(|s| {
                            universe_store::selector::selector_key(s).ok().as_ref() == Some(&key)
                        })
                } else {
                    false
                }
            })
            .ok_or_else(denied)?;
        let id = universe_store::kernel::record_world(&world.identity.record_id);
        if args
            .get("world_id")
            .and_then(Value::as_str)
            .is_some_and(|guard| guard != id.as_str())
        {
            return Err(ProtocolError::WorldScopeConflict {
                message: "world guard differs".into(),
            }
            .into());
        }
        Ok(Some(id))
    }
    fn cursor_binding(&self, args: &Value, frame: &Frame) -> String {
        let mut args = args.clone();
        args.as_object_mut().expect("args object").remove("cursor");
        hash(&(args, frame, &self.principal.id, self.scope_hash()))
    }
    fn offset(&self, args: &Value, frame: &Frame) -> anyhow::Result<usize> {
        if let Some(id) = args.get("cursor").and_then(Value::as_str) {
            let c: Value = self.load(&format!("cursor:{id}"))?;
            if c["binding"] != self.cursor_binding(args, frame) {
                return Err(denied());
            }
            field(&c, "offset")
        } else {
            Ok(0)
        }
    }
    fn cursor(&mut self, args: &Value, frame: &Frame, offset: usize) -> anyhow::Result<String> {
        let id = OperationId::generate(&mut rand::rng()).0;
        self.save(
            format!("cursor:{id}"),
            &json!({"binding":self.cursor_binding(args,frame),"offset":offset}),
        )?;
        Ok(id)
    }
}
fn label(r: &RecordVersion) -> String {
    match &r.payload {
        Payload::Entity(e) => e
            .labels
            .values()
            .next()
            .cloned()
            .unwrap_or_else(|| r.identity.record_id.0.clone()),
        Payload::World(w) => w.selector.clone(),
        Payload::Work(w) => w.title.clone(),
        Payload::Saga(s) => s.title.clone(),
        Payload::Appearance(a) => a.label.clone(),
        Payload::ImageAsset(a) => a.original_name.clone(),
        Payload::Source(s) => s.label.clone(),
        Payload::EntityType(d) => d
            .labels
            .values()
            .next()
            .cloned()
            .unwrap_or_else(|| d.key.clone()),
        Payload::Property(d) => d
            .labels
            .values()
            .next()
            .cloned()
            .unwrap_or_else(|| d.key.clone()),
        Payload::Relation(d) => d
            .labels
            .values()
            .next()
            .cloned()
            .unwrap_or_else(|| d.key.clone()),
        Payload::Unit(d) => d
            .labels
            .values()
            .next()
            .cloned()
            .unwrap_or_else(|| d.key.clone()),
        Payload::Calendar(d) => d
            .labels
            .values()
            .next()
            .cloned()
            .unwrap_or_else(|| d.key.clone()),
        _ => r.identity.record_id.0.clone(),
    }
}

// The snapshot and authority filter bound traversal; cycles do not consume work twice.
fn dependency_closure(
    records: &[RecordVersion],
    seeds: Vec<RecordId>,
) -> anyhow::Result<(BTreeSet<RecordId>, bool)> {
    let map: std::collections::BTreeMap<_, _> =
        records.iter().map(|r| (&r.identity.record_id, r)).collect();
    let mut pending = seeds;
    let mut attachments = std::collections::BTreeMap::<RecordId, Vec<RecordId>>::new();
    for r in records {
        if let Payload::Appearance(a) = &r.payload {
            match &a.target {
                AppearanceTarget::Universe => pending.push(r.identity.record_id.clone()),
                AppearanceTarget::Entry { entry } => attachments
                    .entry(entry.record.clone())
                    .or_default()
                    .push(r.identity.record_id.clone()),
            }
        }
    }

    let mut visited = BTreeSet::new();
    let mut closed = true;
    let mut edges = 0;
    while let Some(id) = pending.pop() {
        if visited.contains(&id) {
            continue;
        }
        let Some(record) = map.get(&id) else {
            closed = false;
            continue;
        };
        pending.extend(attachments.get(&id).into_iter().flatten().cloned());
        visited.insert(id);
        let deps = universe_store::kernel::record_dependencies(record)?;
        edges += deps.len();
        if edges > 5_000_000 {
            return Err(ProtocolError::EvaluationLimitReached {
                message: "dependency traversal budget exceeded".into(),
            }
            .into());
        }
        pending.extend(deps);
    }
    Ok((visited, closed))
}
// Research follows authored evidence about a subject as well as references from it.
// Context/predicate references are not reverse edges: they would pull in unrelated facts.
fn research_closure(
    records: &[RecordVersion],
    seeds: Vec<RecordId>,
) -> anyhow::Result<(BTreeSet<RecordId>, bool)> {
    let mut edges = std::collections::BTreeMap::<RecordId, Vec<RecordId>>::new();
    let mut pending = seeds;
    let mut count = 0;
    for r in records {
        let id = &r.identity.record_id;
        let dependencies = universe_store::kernel::record_dependencies(r)?;
        let targets: Vec<_> = match &r.payload {
            Payload::Proposition(p) => dependencies
                .iter()
                .filter(|id| **id != p.context.record && **id != p.predicate.record)
                .cloned()
                .collect(),
            Payload::Assertion(a) => vec![a.proposition.record.clone()],
            Payload::Completeness(c) => vec![c.subject.record.clone()],
            Payload::EpistemicAttitude(a) => {
                vec![a.holder.record.clone(), a.proposition.record.clone()]
            }
            Payload::Observation(o) => {
                let mut targets = vec![o.observer.record.clone(), o.observed.record.clone()];
                targets.extend(o.interpretation.iter().map(|r| r.record.clone()));
                targets
            }
            Payload::PassageRef(p) => p.anchor.iter().map(|r| r.record.clone()).collect(),
            Payload::SceneRef(s) => s.depicted_events.iter().map(|r| r.record.clone()).collect(),
            Payload::Event(e) => e
                .participants
                .iter()
                .map(|p| p.record.record.clone())
                .collect(),
            Payload::Exception(e) => vec![e.rule.record.clone()],
            Payload::Appearance(a) => match &a.target {
                AppearanceTarget::Universe => {
                    pending.push(id.clone());
                    vec![]
                }
                AppearanceTarget::Entry { entry } => vec![entry.record.clone()],
            },
            Payload::Boundary(_) | Payload::IssueDecision(_) => {
                pending.push(id.clone());
                vec![]
            }
            _ => vec![],
        };
        count += dependencies.len() + targets.len();
        if count > 5_000_000 {
            return Err(ProtocolError::EvaluationLimitReached {
                message: "research dependency budget exceeded".into(),
            }
            .into());
        }
        edges.entry(id.clone()).or_default().extend(dependencies);
        for target in targets {
            edges.entry(target).or_default().push(id.clone());
        }
    }
    let existing: BTreeSet<_> = records
        .iter()
        .map(|r| r.identity.record_id.clone())
        .collect();
    let mut visited = BTreeSet::new();
    let mut closed = true;
    while let Some(id) = pending.pop() {
        if !existing.contains(&id) {
            closed = false;
            continue;
        }
        if visited.insert(id.clone()) {
            pending.extend(edges.get(&id).into_iter().flatten().cloned());
        }
    }
    Ok((visited, closed))
}

fn perspective_ids(records: &[RecordVersion], frame: &Frame) -> anyhow::Result<BTreeSet<RecordId>> {
    if matches!(frame.perspective, Perspective::Author) {
        if frame.reader_scene.is_some() {
            return Err(ProtocolError::invalid_argument(
                "reader_scene",
                "requires reader perspective",
            )
            .into());
        }
        return Ok(records
            .iter()
            .map(|r| r.identity.record_id.clone())
            .collect());
    }
    let mut roots = Vec::new();
    match &frame.perspective {
        Perspective::Character(holder) | Perspective::Narrator(holder) => {
            let character = matches!(frame.perspective, Perspective::Character(_));
            let matching = records.iter().any(|r| r.identity.record_id == frame.context.record && matches!(&r.payload,
                Payload::RepresentedContext(c) if match &c.kind {
                    RepresentedContextKind::Character { holder: h } => character && h.record == *holder,
                    RepresentedContextKind::Narrator { narrator } => !character && narrator.record == *holder,
                    _ => false,
                }));
            if !matching || frame.reader_scene.is_some() {
                return Err(denied());
            }
            roots.extend([holder.clone(), frame.context.record.clone()]);
            for r in records {
                let include = match &r.payload {
                    Payload::Assertion(a) => {
                        a.scope.context == frame.context
                            && universe_rules::events::applies(&a.validity, &frame.time, records)
                                != Some(false)
                    }
                    Payload::EpistemicAttitude(a) => {
                        a.holder.record == *holder
                            && universe_rules::events::applies(&a.validity, &frame.time, records)
                                != Some(false)
                    }
                    _ => false,
                };
                if include {
                    roots.push(r.identity.record_id.clone());
                }
            }
        }
        Perspective::Reader => {
            let id = frame.reader_scene.as_ref().ok_or_else(|| {
                ProtocolError::invalid_argument(
                    "reader_scene",
                    "reader perspective requires a pinned scene",
                )
            })?;
            let scene = records
                .iter()
                .find_map(|r| {
                    if r.identity.record_id == *id {
                        if let Payload::SceneRef(s) = &r.payload {
                            Some(s)
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                })
                .ok_or_else(denied)?;
            let position = scene.narrative_position.ok_or_else(denied)?;
            let work = records
                .iter()
                .find(|r| {
                    r.identity.record_id == scene.work_version.record
                        && r.record_version_id == scene.work_version.version
                })
                .ok_or_else(denied)?;
            if !matches!(&work.payload, Payload::WorkVersion(w) if matches!(&w.binding, WorkBinding::Bound {continuity, ..} if *continuity == frame.continuity))
            {
                return Err(denied());
            }
            for r in records {
                if let Payload::SceneRef(s) = &r.payload {
                    if s.work_version == scene.work_version
                        && s.narrative_position.is_some_and(|p| p <= position)
                    {
                        roots.extend(s.disclosed_records.iter().map(|r| r.record.clone()));
                    }
                }
            }
        }
        Perspective::Author => unreachable!(),
    }
    let by_id: std::collections::BTreeMap<_, _> = records
        .iter()
        .map(|r| (r.identity.record_id.clone(), r))
        .collect();
    let mut ids = BTreeSet::new();
    while let Some(id) = roots.pop() {
        if ids.insert(id.clone()) {
            let r = by_id.get(&id).ok_or_else(denied)?;
            roots.extend(universe_store::kernel::record_dependencies(r)?);
            if roots.len() + ids.len() > 5_000_000 {
                return Err(unsupported("perspective dependency budget exceeded"));
            }
        }
    }
    Ok(ids)
}

fn name_matches(r: &RecordVersion, query: &str) -> bool {
    let q = query.to_lowercase();
    if label(r).to_lowercase().contains(&q) {
        return true;
    }
    match &r.payload {
        Payload::Entity(e) => {
            e.names.iter().any(|n| n.text.to_lowercase().contains(&q))
                || e.labels.values().any(|s| s.to_lowercase().contains(&q))
        }
        Payload::World(w) => w.aliases.iter().any(|s| s.to_lowercase().contains(&q)),
        _ => false,
    }
}

// Bounded, process-local cache. Immutable payloads and the complete request/frame/
// principal/grant binding are hashed above; authorization is rechecked before disclosure.
type BriefCache = std::collections::VecDeque<(String, Value, usize)>;
static BRIEFS: std::sync::OnceLock<std::sync::Mutex<BriefCache>> = std::sync::OnceLock::new();
pub(crate) fn clear_briefs() {
    if let Some(cache) = BRIEFS.get() {
        cache.lock().unwrap().clear();
    }
}
fn cached_brief(key: &str) -> Option<Value> {
    let cache = BRIEFS.get_or_init(Default::default).lock().unwrap();
    cache
        .iter()
        .find(|(k, _, _)| k == key)
        .map(|(_, v, _)| v.clone())
}
fn cache_brief(key: String, value: Value) {
    let size = serde_json::to_vec(&value).map_or(usize::MAX, |v| v.len());
    if size > 900_000 {
        return;
    }
    let mut cache = BRIEFS.get_or_init(Default::default).lock().unwrap();
    while cache.len() >= 64
        || cache.iter().map(|(_, _, size)| size).sum::<usize>() + size > 8_000_000
    {
        cache.pop_front();
    }
    cache.push_back((key, value, size));
}

#[cfg(test)]
mod job_tests {
    use super::*;
    #[test]
    fn queued_cancel_and_interrupted_detection_are_durable_without_mutating_operation_receipts() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("jobs.db");
        let u = UniverseId::generate(&mut rand::rng());
        let cont = ContinuityId::generate(&mut rand::rng());
        let profile = ProfileId::generate(&mut rand::rng());
        let principal = PrincipalId::parse(&profile.as_str().replacen("prf_", "prn_", 1)).unwrap();
        let mut kernel = Kernel::create(&path, u, "Jobs", cont, &principal).unwrap();
        let id = OperationId::generate(&mut rand::rng());
        let key = format!("operation:{id}");
        let mut workflow = Workflow {
            kernel: &mut kernel,
            authority: None,
            principal: Principal {
                id: profile.clone(),
                author: true,
            },
            approval_author: profile.clone(),
            scope: None,
            permissions: (true, true, true),
            name: "Jobs".into(),
        };
        let mut op = StoredOperation {
            owner: profile.clone(),
            digest: "queued fixture".into(),
            status: OperationStatus {
                operation_id: id.clone(),
                kind: OperationKind::Validate,
                state: OperationState::Queued,
                proposal: None,
                receipt: None,
                cancellation_requested: false,
                validation: None,
                failure: None,
            },
            input: None,
            validation_capture: None,
            footprint: Footprint::default(),
        };
        workflow.save(key.clone(), &op).unwrap();
        op.status.state = OperationState::Running;
        workflow.save(format!("job:{id}:running"), &op).unwrap();
        assert_eq!(
            workflow.operation(&key).unwrap().status.state,
            OperationState::Interrupted
        );
        workflow
            .save(
                format!("cancel:{id}"),
                &json!({"owner":profile,"cancelled":true}),
            )
            .unwrap();
        workflow.run_validation(&id).unwrap(); // cancellation short-circuits even a missing proposal
        assert_eq!(
            workflow.operation(&key).unwrap().status.state,
            OperationState::Cancelled
        );
        assert!(workflow
            .kernel
            .workflow_get(&format!("job:{id}:terminal"))
            .unwrap()
            .is_none());
        drop(kernel);
        let mut kernel = Kernel::open(&path).unwrap();
        let workflow = Workflow {
            kernel: &mut kernel,
            authority: None,
            principal: Principal {
                id: profile.clone(),
                author: true,
            },
            approval_author: profile,
            scope: None,
            permissions: (true, true, true),
            name: "Jobs".into(),
        };
        assert_eq!(
            workflow.operation(&key).unwrap().status.state,
            OperationState::Cancelled
        );
        assert_eq!(
            workflow.load::<StoredOperation>(&key).unwrap().status.state,
            OperationState::Queued
        );
    }
}

#[path = "assessments.rs"]
mod assessments;

#[path = "validation_binding.rs"]
mod validation_binding;
