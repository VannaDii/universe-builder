//! Persistent authenticated service with durable, approved proposal admission.
use crate::registry::{Principal, Registry};
use futures::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    path::Path,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::{
    net::{UnixListener, UnixStream},
    sync::{OwnedSemaphorePermit, Semaphore},
};
use tokio_util::{
    codec::{Framed, LengthDelimitedCodec},
    sync::CancellationToken,
};
use universe_domain::{ids::*, records::Payload};
use universe_protocol::{
    installation::*, wire::decode, ProtocolError, MAX_FRAME_BYTES, PROTOCOL_VERSION,
};
use universe_store::{
    kernel::Kernel,
    ownership::{private_dir, FileLock},
};
struct Worker {
    _capacity: OwnedSemaphorePermit,
    tx: Option<std::sync::mpsc::SyncSender<Work>>,
    thread: Option<std::thread::JoinHandle<()>>,
}
type WorkerJob = Box<dyn FnOnce(&mut Kernel) -> anyhow::Result<Value> + Send>;
struct Work {
    result: std::sync::mpsc::Sender<anyhow::Result<Value>>,
    job: WorkerJob,
}
impl Worker {
    fn start(mut kernel: Kernel, capacity: OwnedSemaphorePermit) -> Self {
        let (tx, rx) = std::sync::mpsc::sync_channel::<Work>(16);
        let thread = std::thread::spawn(move || {
            while let Ok(work) = rx.recv() {
                let result = (work.job)(&mut kernel);
                let _ = work.result.send(result);
            }
        });
        Self {
            _capacity: capacity,
            tx: Some(tx),
            thread: Some(thread),
        }
    }
    fn run(
        &self,
        job: impl FnOnce(&mut Kernel) -> anyhow::Result<Value> + Send + 'static,
    ) -> anyhow::Result<Value> {
        let (tx, rx) = std::sync::mpsc::channel();
        self.tx
            .as_ref()
            .unwrap()
            .try_send(Work {
                result: tx,
                job: Box::new(job),
            })
            .map_err(|_| ProtocolError::EvaluationLimitReached {
                message: "universe queue full".into(),
            })?;
        // An admitted mutation must finish while its authority gate is held.
        rx.recv()?
    }
    fn typed<T: Send + 'static>(
        &self,
        job: impl FnOnce(&mut Kernel) -> anyhow::Result<T> + Send + 'static,
    ) -> anyhow::Result<T> {
        let (tx, rx) = std::sync::mpsc::channel();
        self.run(move |kernel| {
            let result = job(kernel)?;
            let _ = tx.send(result);
            Ok(Value::Null)
        })?;
        Ok(rx.recv()?)
    }
    fn describe(&self) -> anyhow::Result<Value> {
        self.run(|kernel| {
            let status = kernel.status()?;
            let mut worlds = Vec::new(); let mut contexts = Vec::new();
            for (cont, head) in &status.heads {
                for r in kernel.records(&ContinuityId::parse(cont)?, &RevisionId::parse(head)?)? {
                    match r.payload {
                        Payload::World(w) => worlds.push(json!({"id":universe_store::kernel::record_world(&r.identity.record_id),"name":w.selector,"continuity_id":cont})),
                        Payload::RepresentedContext(_) => contexts.push(r.identity.record_id),
                        _ => {},
                    }
                }
            }
            let continuities:Vec<_>=status.heads.iter().map(|(id,revision)|Ok(json!({"id":id,"revision":revision,"name":kernel.workflow_get(&format!("continuity-name:{id}"))?.unwrap_or_else(||json!("Original continuity"))}))).collect::<anyhow::Result<_>>()?;
            Ok(json!({"storage":status,"worlds":worlds,"contexts":contexts,"continuities":continuities}))
        })
    }
}
impl Drop for Worker {
    fn drop(&mut self) {
        drop(self.tx.take());
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}
type WorkerSlot = Arc<Mutex<Option<Arc<Worker>>>>;
struct PrincipalSlots {
    connections: Arc<Semaphore>,
    requests: Arc<Semaphore>,
}
struct Runtime {
    validation_jobs: Arc<Semaphore>,
    agent_connections: Arc<Semaphore>,
    agent_work: Arc<Semaphore>,
    author_work: Arc<Semaphore>,
    registry: Arc<Mutex<Registry>>,
    workers: Mutex<HashMap<UniverseId, WorkerSlot>>,
    worker_capacity: Arc<Semaphore>,
    instance: String,
    shutdown: CancellationToken,
}
#[derive(Clone)]
pub(crate) struct Authority {
    registry: Arc<Mutex<Registry>>,
    hello: EngineHello,
    universe: UniverseId,
    scope: Option<std::collections::BTreeSet<WorldId>>,
    permissions: (bool, bool, bool),
    pub(crate) limits: GrantLimits,
    author: ProfileId,
}
impl Authority {
    pub(crate) fn lock(&self) -> anyhow::Result<std::sync::MutexGuard<'_, Registry>> {
        let registry = self.registry.lock().unwrap();
        let current = registry.authenticate(&self.hello)?;
        if registry.scope(&current, &self.universe)? != self.scope
            || registry.write_permissions(&current, &self.universe)? != self.permissions
            || registry.limits(&current, &self.universe)? != self.limits
            || registry.current_author()? != self.author
        {
            return Err(ProtocolError::PolicyDenied {
                message: "authority changed during preparation; retry with current grants".into(),
            }
            .into());
        }
        Ok(registry)
    }
}
impl Runtime {
    fn authenticate(&self, h: &EngineHello) -> anyhow::Result<Principal> {
        self.registry.lock().unwrap().authenticate(h)
    }
    fn reserve_worker(&self) -> anyhow::Result<OwnedSemaphorePermit> {
        self.worker_capacity
            .clone()
            .try_acquire_owned()
            .map_err(|_| {
                ProtocolError::EvaluationLimitReached {
                    message: "open universe limit reached".into(),
                }
                .into()
            })
    }
    fn worker(&self, id: &UniverseId, path: &Path) -> anyhow::Result<Arc<Worker>> {
        let slot = self
            .workers
            .lock()
            .unwrap()
            .entry(id.clone())
            .or_insert_with(|| Arc::new(Mutex::new(None)))
            .clone();
        // Only this universe waits for recovery; other worker slots stay available.
        let mut entry = slot.lock().unwrap();
        if let Some(worker) = entry.as_ref() {
            return Ok(worker.clone());
        }
        let result = (|| {
            let capacity = self.reserve_worker()?;
            let kernel = Kernel::open(path)?;
            anyhow::ensure!(
                kernel.universe() == id,
                "package universe identity mismatch"
            );
            Ok(Arc::new(Worker::start(kernel, capacity)))
        })();
        match result {
            Ok(worker) => {
                *entry = Some(worker.clone());
                Ok(worker)
            }
            Err(error) => {
                // Keep a failed slot only while another opener is waiting on it.
                // The final waiter removes it; a successful retry cannot be evicted.
                let mut workers = self.workers.lock().unwrap();
                if Arc::strong_count(&slot) == 2
                    && workers
                        .get(id)
                        .is_some_and(|current| Arc::ptr_eq(current, &slot))
                {
                    workers.remove(id);
                }
                Err(error)
            }
        }
    }
    fn execute(&self, h: &EngineHello, request: EngineRequest) -> anyhow::Result<Value> {
        // Recheck current credentials/grants on every call, not only handshake.
        let p = self.authenticate(h)?;
        let mut disclosure = None;
        let value = match request {
            EngineRequest::Status => {
                let registry = self.registry.lock().unwrap();
                let catalog = registry.catalog(&p)?;
                json!({"service_instance":self.instance,"principal":p.id,"author":p.author,"universes":catalog.into_iter().map(|u|json!({"id":u.universe_id,"name":u.name})).collect::<Vec<_>>(),"canonical_commit":"exact_approval_or_explicit_delegation","max_requests_per_principal":8,"universe_queue_capacity":16})
            }
            EngineRequest::Profiles => self.registry.lock().unwrap().profiles(&p)?,
            EngineRequest::WithdrawGrant {
                profile_id,
                universe_id,
            } => {
                let mut registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                registry.withdraw_grant(&current, &profile_id, &universe_id)?;
                json!({"withdrawn":true})
            }
            EngineRequest::PreviewPurge { universe } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                self.worker(&u.universe_id, &u.path)?
                    .run(|kernel| Ok(kernel.purge_preview()?))?
            }
            EngineRequest::Purge {
                universe,
                digest,
                confirmation,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                anyhow::ensure!(
                    confirmation == format!("PURGE {}", u.name),
                    "type the exact purge confirmation shown in the preview"
                );
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                let id = u.universe_id.clone();
                let name = u.name.clone();
                let result = self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    let mut registry = gate.lock().unwrap();
                    let current = registry.authenticate(&hello)?;
                    Registry::require_author(&current)?;
                    registry.resolve(&current, &name)?;
                    kernel.prepare_purge(&digest)?;
                    crate::workflow::cancel_universe_jobs(&id);
                    crate::workflow::clear_briefs();
                    registry.begin_purge(&current, &id)?;
                    Ok(json!({"purged":id,"external_copies_removed":false}))
                })?;
                self.workers.lock().unwrap().remove(&u.universe_id);
                result
            }
            EngineRequest::Doctor => {
                Registry::require_author(&p)?;
                let catalog = self.registry.lock().unwrap().catalog(&p)?;
                let mut packages = Vec::new();
                for u in catalog {
                    let checked = self.registry.lock().unwrap().resolve(&p, &u.name);
                    match checked.and_then(|u|self.worker(&u.universe_id,&u.path)).and_then(|w|w.describe()){
                    Ok(details)=>packages.push(json!({"id":u.universe_id,"storage":details["storage"]})),
                    Err(_)=>packages.push(json!({"id":u.universe_id,"error":"package unavailable: check file ownership, writer lock, schema version, and integrity"})),
                }
                }
                json!({"service_instance":self.instance,"packages":packages,"profile_storage":"installation-only protected files","recovery":"immutable history replay; atomic projection rebuild","admission":{"connections":32,"requests_per_principal":8,"queue_per_universe":16}})
            }
            EngineRequest::Tool { request } => {
                request.validate()?;
                let registry = self.registry.lock().unwrap();
                let p = registry.authenticate(h)?;
                let u = registry.resolve(&p, &request.universe().0)?;
                let scope = registry.scope(&p, &u.universe_id)?;
                let raw = serde_json::to_value(&request)?;
                if raw["args"]
                    .get("universe_id")
                    .and_then(Value::as_str)
                    .is_some_and(|id| id != u.universe_id.as_str())
                {
                    return Err(ProtocolError::UniverseScopeMismatch {
                        message: "universe guard does not match".into(),
                    }
                    .into());
                }
                let permissions = registry.write_permissions(&p, &u.universe_id)?;
                let approval_author = registry.current_author()?;
                let authority = Authority {
                    registry: self.registry.clone(),
                    hello: h.clone(),
                    universe: u.universe_id.clone(),
                    scope: scope.clone(),
                    permissions,
                    limits: registry.limits(&p, &u.universe_id)?,
                    author: approval_author.clone(),
                };
                drop(registry);
                let worker = self.worker(&u.universe_id, &u.path)?;
                disclosure = Some(authority.clone());
                // Preparation and queue waits do not hold the installation authority gate.
                let queued = matches!(
                    &*request,
                    universe_protocol::Request::Validate(
                        universe_protocol::request::Validate::QueuedProposal { .. }
                    )
                );
                let (job_authority, job_principal, job_scope, job_name, job_author) = (
                    authority.clone(),
                    p.clone(),
                    scope.clone(),
                    u.name.clone(),
                    approval_author.clone(),
                );
                let result = worker.run(move |kernel| {
                    crate::workflow::Workflow {
                        kernel,
                        approval_author,
                        authority: Some(authority),
                        principal: p,
                        scope,
                        permissions,
                        name: u.name,
                    }
                    .execute(*request)
                })?;
                if queued {
                    if let Some(id) = result["result"]["execution"]["operation_id"].as_str() {
                        let id = OperationId::parse(id)?;
                        let universe = job_authority.universe.clone();
                        if let Some(cancel) = crate::workflow::start_validation(&universe, &id) {
                            let capacity = match self.validation_jobs.clone().try_acquire_owned() {
                                Ok(capacity) => capacity,
                                Err(_) => {
                                    crate::workflow::end_validation(&universe, &id);
                                    return Err(ProtocolError::EvaluationLimitReached {
                                        message: "validation busy; retry the same key".into(),
                                    }
                                    .into());
                                }
                            };
                            let shutdown = self.shutdown.clone();
                            std::thread::spawn(move || {
                                let _capacity = capacity;
                                let (authority, principal, scope, name, author, job_id) = (
                                    job_authority.clone(),
                                    job_principal.clone(),
                                    job_scope.clone(),
                                    job_name.clone(),
                                    job_author.clone(),
                                    id.clone(),
                                );
                                let prepared = worker.typed(move |kernel| {
                                    crate::workflow::Workflow {
                                        kernel,
                                        approval_author: author,
                                        authority: Some(authority),
                                        principal,
                                        scope,
                                        permissions,
                                        name,
                                    }
                                    .prepare_validation(&job_id)
                                });
                                let evaluated = match prepared {
                                    Ok(Some(task)) => Some(task.evaluate(&cancel)),
                                    Ok(None) => None,
                                    Err(e) => Some(Err(e)),
                                };
                                if let Some(evaluated) =
                                    evaluated.filter(|_| !shutdown.is_cancelled())
                                {
                                    let job_id = id.clone();
                                    let _ = worker.run(move |kernel| {
                                        crate::workflow::Workflow {
                                            kernel,
                                            approval_author: job_author,
                                            authority: Some(job_authority),
                                            principal: job_principal,
                                            scope: job_scope,
                                            permissions,
                                            name: job_name,
                                        }
                                        .finish_validation(&job_id, evaluated)?;
                                        Ok(Value::Null)
                                    });
                                }
                                crate::workflow::end_validation(&universe, &id);
                            });
                        }
                    }
                }
                result
            }
            EngineRequest::Library { universe } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let worker = self.worker(&u.universe_id, &u.path)?;
                let mut library = worker.describe()?;
                let author = current.id.clone();
                let writing = worker.run(move |kernel| {
                    let mut latest = std::collections::BTreeMap::new();
                    for key in kernel.workflow_keys("proposal:")? {
                        let stored: crate::workflow::StoredProposal = serde_json::from_value(kernel.workflow_get(&key)?.ok_or_else(|| ProtocolError::not_found("proposal"))?)?;
                        let mut rows = kernel.records(&stored.proposal.base_frame.continuity, &stored.proposal.base_frame.revision)?;
                        for changed in stored.changes.iter().filter_map(|c| c.next.as_ref()) {
                            rows.retain(|r| r.identity.record_id != changed.identity.record_id);
                            rows.push(changed.clone());
                        }
                        let name = |id: &RecordId| rows.iter().find(|r| &r.identity.record_id == id).and_then(|r| match &r.payload {
                            Payload::Entity(e) => e.labels.values().next().cloned().or_else(|| e.names.first().map(|n| n.text.clone())),
                            Payload::Property(p) => Some(p.key.clone()),
                            Payload::Relation(r) => Some(r.key.clone()),
                            Payload::ActionDefinition(a) => Some(a.key.clone()),
                            _ => None,
                        });
                        let names: Vec<String> = stored.changes.iter().filter_map(|c|c.next.as_ref()).filter_map(|r|match &r.payload {
                            Payload::Entity(e)=>e.names.first().map(|n|n.text.clone()),
                            Payload::Source(s)=>Some(s.label.clone()),
                            Payload::Property(p)=>Some(p.key.clone()),
                            Payload::Relation(r)=>Some(r.key.clone()),
                            Payload::EntityType(t)=>Some(t.name.clone()),
                            Payload::ActionDefinition(a)=>Some(a.key.clone()),
                            Payload::Event(e) => e.action.as_ref().and_then(|a| name(&a.record)).map(|action| format!("Occurred action: {action}")),
                            Payload::Assertion(a) => rows.iter().find(|r| r.identity.record_id == a.proposition.record).and_then(|r| if let Payload::Proposition(p) = &r.payload { Some(format!("{} — {}", name(&p.subject.record)?, name(&p.predicate.record)?)) } else { None }),
                            _=>None,
                        }).collect();
                        let p = stored.proposal;
                        let label = if names.is_empty(){p.rationale.clone()}else{names.join(" · ")};
                        let entry = latest.entry(p.proposal_id.clone()).or_insert((p.clone(), label.clone()));
                        if p.version > entry.0.version { *entry = (p,label); }
                    }
                    let mut published = std::collections::BTreeSet::new();
                    for key in kernel.workflow_keys("operation:")? {
                        if let Some(operation) = kernel.workflow_get(&key)? {
                            if !operation["input"].is_null() {
                                let input: universe_store::kernel::CommitInput = serde_json::from_value(operation["input"].clone())?;
                                if kernel.receipt(&input)?.is_some() {
                                    if let Some(digest) = operation["status"]["proposal"]["digest"].as_str() { published.insert(digest.to_owned()); }
                                }
                            }
                        }
                    }
                    let proposals: Vec<_> = latest.values().filter(|(p,_)| !p.withdrawn && !published.contains(&p.digest)).map(|(p,label)| json!({"candidate":{"proposal_id":p.proposal_id,"version":p.version,"digest":p.digest},"label":label,"submission":p.submission,"base_revision":p.base_frame.revision,"continuity":p.base_frame.continuity})).collect();
                    let mut approvals = vec![];
                    for key in kernel.workflow_keys(&format!("approval:{author}:"))? {
                        if let Some(value) = kernel.workflow_get(&key)? {
                            if value["author"] == author.as_str() {
                                approvals.push(json!({"candidate":value["proposal"],"validation_run":key.rsplit(':').next().unwrap_or_default(),"label":value["proposal"]["proposal_id"].as_str().and_then(|id|latest.iter().find(|(key,_)|key.as_str()==id).map(|(_,(_,label))|label.clone())).unwrap_or_else(||"Approved writing".into())}));
                            }
                        }
                    }
                    Ok(json!({"proposals":proposals,"approved":approvals}))
                })?;
                library["writing"] = writing;
                library
            }
            EngineRequest::ForkContinuity {
                universe,
                name,
                continuity_id,
                source,
                revision,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                if name.trim().is_empty() || name.len() > 128 {
                    return Err(ProtocolError::invalid_argument(
                        "name",
                        "enter a continuity name of 1..128 bytes",
                    )
                    .into());
                }
                let principal =
                    PrincipalId::parse(&current.id.as_str().replacen("prf_", "prn_", 1))?;
                let gate = self.registry.clone();
                let hello = h.clone();
                drop(registry);
                self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    let registry = gate.lock().unwrap();
                    let current = registry.authenticate(&hello)?;
                    Registry::require_author(&current)?;
                    let revision = kernel.branch(&continuity_id, &source, &revision, &principal)?;
                    kernel.workflow_put(&[(
                        format!("continuity-name:{continuity_id}"),
                        json!(name),
                    )])?;
                    Ok(json!({"continuity_id":continuity_id,"revision":revision}))
                })?
            }
            EngineRequest::CompareContinuities {
                universe,
                target,
                target_revision,
                source,
                source_revision,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                self.worker(&u.universe_id,&u.path)?.run(move|kernel|{
                    let from=kernel.records(&source,&source_revision)?;let to=kernel.records(&target,&target_revision)?;
                    let ids:std::collections::BTreeSet<_>=from.iter().chain(&to).map(|r|r.identity.record_id.clone()).collect();
                    let mut differences=Vec::new();for id in ids{let a=to.iter().find(|r|r.identity.record_id==id);let b=from.iter().find(|r|r.identity.record_id==id);if a.map(|r|&r.payload_digest)==b.map(|r|&r.payload_digest){continue;}
                        if a.into_iter().chain(b).any(|r|matches!(&r.payload,Payload::Assertion(a) if a.established_by.is_some())){continue;}
                        let record=b.or(a).unwrap();differences.push(json!({"record_id":id,"kind":record.identity.record_kind,"target_version":a.map(|r|&r.record_version_id),"source_version":b.map(|r|&r.record_version_id)}));
                    }
                    if differences.len()>1000{return Err(ProtocolError::EvaluationLimitReached{message:"continuity comparison exceeds 1,000 changed records".into()}.into());}
                    Ok(json!({"differences":differences,"source_revision":source_revision,"target_revision":target_revision}))
                })?
            }
            EngineRequest::PrepareAdoption {
                universe,
                target,
                target_revision,
                source,
                source_revision,
                record_ids,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                if record_ids.is_empty() || record_ids.len() > 100 {
                    return Err(ProtocolError::invalid_argument(
                        "record_ids",
                        "select 1..100 records",
                    )
                    .into());
                }
                self.worker(&u.universe_id,&u.path)?.run(move|kernel|{
                    let from=kernel.records(&source,&source_revision)?;let to=kernel.records(&target,&target_revision)?;let mut operations=Vec::new();
                    for id in record_ids{
                        let old=to.iter().find(|r|r.identity.record_id==id);
                        if let Some(record)=from.iter().find(|r|r.identity.record_id==id){if old.is_some_and(|r|r.payload_digest==record.payload_digest){continue;}
                            operations.push(universe_domain::records::DomainOperation::AdoptRecordVersion{source:Box::new(record.clone()),expected_version:old.map(|r|r.record_version_id.clone())});
                        }else if let Some(old)=old{operations.push(universe_domain::records::DomainOperation::TombstoneRecord{record:universe_domain::value::RecordRef::new(kernel.universe().clone(),id),expected_version:old.record_version_id.clone(),rationale:"Explicitly selected absence in source continuity".into()});}else{return Err(ProtocolError::not_found("adoption record").into());}
                    }
                    Ok(json!({"operations":operations,"target_revision":target_revision,"source_revision":source_revision}))
                })?
            }
            EngineRequest::LoadDraft {
                universe,
                continuity_id,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    let registry = gate.lock().unwrap();
                    Registry::require_author(&registry.authenticate(&hello)?)?;
                    Ok(serde_json::to_value(crate::drafts::load(
                        kernel,
                        &current.id,
                        &continuity_id,
                    )?)?)
                })?
            }
            EngineRequest::SaveDraft {
                universe,
                continuity_id,
                expected_version,
                content,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    let registry = gate.lock().unwrap();
                    Registry::require_author(&registry.authenticate(&hello)?)?;
                    Ok(serde_json::to_value(crate::drafts::save(
                        kernel,
                        &current.id,
                        &continuity_id,
                        expected_version,
                        content,
                    )?)?)
                })?
            }
            EngineRequest::StageImage { universe, source } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    let registry = gate.lock().unwrap();
                    Registry::require_author(&registry.authenticate(&hello)?)?;
                    crate::workflow::Workflow {
                        kernel,
                        authority: None,
                        approval_author: current.id.clone(),
                        principal: current,
                        scope: None,
                        permissions: (true, true, true),
                        name: u.name,
                    }
                    .stage_image(source)
                })?
            }
            EngineRequest::ImagePreview {
                universe,
                context_id,
                asset,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    let registry = gate.lock().unwrap();
                    Registry::require_author(&registry.authenticate(&hello)?)?;
                    crate::workflow::Workflow {
                        kernel,
                        authority: None,
                        approval_author: current.id.clone(),
                        principal: current,
                        scope: None,
                        permissions: (true, true, true),
                        name: u.name,
                    }
                    .image_preview(&context_id, &asset)
                })?
            }
            EngineRequest::AuthorWriting { universe, action } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    let registry = gate.lock().unwrap();
                    Registry::require_author(&registry.authenticate(&hello)?)?;
                    crate::workflow::Workflow {
                        kernel,
                        authority: None,
                        approval_author: current.id.clone(),
                        principal: current,
                        scope: None,
                        permissions: (true, true, true),
                        name: u.name,
                    }
                    .author_writing(universe, action)
                })?
            }
            EngineRequest::StageSource {
                universe,
                label,
                text,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    let registry = gate.lock().unwrap();
                    Registry::require_author(&registry.authenticate(&hello)?)?;
                    crate::workflow::Workflow {
                        kernel,
                        authority: None,
                        approval_author: current.id.clone(),
                        principal: current,
                        scope: None,
                        permissions: (true, true, true),
                        name: u.name,
                    }
                    .stage_source(label, text)
                })?
            }
            EngineRequest::Backup {
                universe,
                destination,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                self.worker(&u.universe_id,&u.path)?.run(move |kernel|{let registry=gate.lock().unwrap();Registry::require_author(&registry.authenticate(&hello)?)?;kernel.backup(&destination)?;Ok(json!({"backup":destination,"universe_id":kernel.universe(),"verified":true}))})?
            }
            EngineRequest::Maintain { universe, collect } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    {
                        let registry = gate.lock().unwrap();
                        Registry::require_author(&registry.authenticate(&hello)?)?;
                    }
                    Ok(kernel.maintain(collect)?)
                })?
            }
            EngineRequest::ConvertLegacy {
                source,
                destination,
            } => {
                Registry::require_author(&p)?;
                let root = self.registry.lock().unwrap().root.join("packages");
                universe_store::kernel::convert_legacy(&source, &destination, &root)?
            }
            EngineRequest::ExportLogical {
                universe,
                destination,
                record_ids,
                complete_history,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    let registry = gate.lock().unwrap();
                    Registry::require_author(&registry.authenticate(&hello)?)?;
                    Ok(serde_json::to_value(kernel.export_relational(
                        &destination,
                        &record_ids,
                        complete_history,
                    )?)?)
                })?
            }
            EngineRequest::PreviewImport { source, name, mode } => {
                Registry::require_author(&p)?;
                let root = self.registry.lock().unwrap().root.clone();
                let preview = crate::imports::prepare(&root, &p.id, &source, name, mode)?;
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let mut report = preview.report();
                report["conflicts"] = serde_json::to_value(
                    registry.import_conflicts(&preview.target, &preview.name)?,
                )?;
                report
            }
            EngineRequest::AcceptImport { preview_id, digest } => {
                let mut registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let preview =
                    crate::imports::load(&registry.root, &current.id, &preview_id, &digest)?;
                let receipt = json!({"preview_id":preview.id,"digest":digest,"universe_id":preview.target,"name":preview.name,"complete":preview.complete,"omitted_records":preview.omitted_records,"imported":true});
                if let Some(existing) = registry
                    .catalog(&current)?
                    .into_iter()
                    .find(|e| e.universe_id == preview.target)
                {
                    drop(registry);
                    let stored =
                        self.worker(&existing.universe_id, &existing.path)?
                            .run(move |k| {
                                Ok(k.workflow_get(&format!(
                                    "logical-import-admission:{}",
                                    preview.id
                                ))?
                                .unwrap_or(Value::Null))
                            })?;
                    if stored != receipt {
                        return Err(ProtocolError::PolicyDenied {
                            message: "existing universe belongs to another import; choose a clone"
                                .into(),
                        }
                        .into());
                    }
                    receipt
                } else {
                    if !registry
                        .import_conflicts(&preview.target, &preview.name)?
                        .is_empty()
                    {
                        return Err(ProtocolError::NameUnavailable {
                            message: "import identity or name is reserved".into(),
                        }
                        .into());
                    }
                    let capacity = self.reserve_worker()?;
                    let destination = registry
                        .root
                        .join("packages")
                        .join(format!("{}.sqlite", preview.target));
                    let created_package = !destination.exists();
                    if created_package {
                        let archive = universe_store::kernel::LogicalArchive::read(
                            &preview.archive_path(&registry.root),
                        )?;
                        if archive.digest != preview.source_digest {
                            return Err(ProtocolError::ApprovalStale.into());
                        }
                        let (mut staged, temporary) = archive.stage(
                            &registry.root.join("packages"),
                            preview.target.clone(),
                            &preview.name,
                        )?;
                        staged.workflow_put(&[(
                            format!("logical-import-admission:{}", preview.id),
                            receipt.clone(),
                        )])?;
                        staged.backup(&destination)?;
                        drop(staged);
                        drop(temporary);
                    }
                    let publication = (|| -> anyhow::Result<Kernel> {
                        let kernel = Kernel::open(&destination)?;
                        if kernel
                            .workflow_get(&format!("logical-import-admission:{}", preview.id))?
                            != Some(receipt.clone())
                        {
                            return Err(ProtocolError::ApprovalStale.into());
                        }
                        registry.register(
                            &current,
                            &preview.target,
                            &preview.name,
                            &destination,
                        )?;
                        Ok(kernel)
                    })();
                    let kernel = match publication {
                        Ok(kernel) => kernel,
                        Err(error) => {
                            if created_package {
                                remove_unregistered_package(&destination)?;
                            }
                            return Err(error);
                        }
                    };
                    let worker = Arc::new(Worker::start(kernel, capacity));
                    self.workers
                        .lock()
                        .unwrap()
                        .insert(preview.target.clone(), Arc::new(Mutex::new(Some(worker))));
                    receipt
                }
            }
            EngineRequest::Restore { source, name } => {
                Registry::require_author(&p)?;
                let capacity = self.reserve_worker()?;
                let scratch = self.registry.lock().unwrap().root.join("packages");
                let (source_kernel, staging) = Kernel::stage_restore(&source, &scratch)?;
                let id = source_kernel.universe().clone();
                let mut registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let destination = registry.root.join("packages").join(format!("{id}.sqlite"));
                if !registry.import_conflicts(&id, &name)?.is_empty() {
                    return Err(ProtocolError::NameUnavailable {
                        message: "restore identity or name is reserved".into(),
                    }
                    .into());
                }
                source_kernel.backup(&destination)?;
                drop(source_kernel);
                drop(staging);
                let publication = (|| -> anyhow::Result<Kernel> {
                    let kernel = Kernel::open(&destination)?;
                    registry.register(&current, &id, &name, &destination)?;
                    Ok(kernel)
                })();
                let kernel = match publication {
                    Ok(kernel) => kernel,
                    Err(error) => {
                        remove_unregistered_package(&destination)?;
                        return Err(error);
                    }
                };
                self.workers.lock().unwrap().insert(
                    id.clone(),
                    Arc::new(Mutex::new(Some(Arc::new(Worker::start(kernel, capacity))))),
                );
                json!({"universe_id":id,"name":name,"restored":true})
            }
            EngineRequest::Review {
                universe,
                proposal_reference,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    let registry = gate.lock().unwrap();
                    Registry::require_author(&registry.authenticate(&hello)?)?;
                    crate::workflow::Workflow {
                        kernel,
                        authority: None,
                        approval_author: current.id.clone(),
                        principal: current,
                        scope: None,
                        permissions: (true, true, true),
                        name: u.name,
                    }
                    .review(&proposal_reference)
                })?
            }
            EngineRequest::Approve {
                universe,
                proposal_reference,
                validation_run,
            } => {
                let registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                Registry::require_author(&current)?;
                let u = registry.resolve(&current, &universe.0)?;
                drop(registry);
                let gate = self.registry.clone();
                let hello = h.clone();
                self.worker(&u.universe_id, &u.path)?.run(move |kernel| {
                    let registry = gate.lock().unwrap();
                    Registry::require_author(&registry.authenticate(&hello)?)?;
                    crate::workflow::Workflow {
                        kernel,
                        authority: None,
                        approval_author: current.id.clone(),
                        principal: current,
                        scope: None,
                        permissions: (true, true, true),
                        name: u.name,
                    }
                    .approve(&proposal_reference, &validation_run)
                })?
            }
            EngineRequest::CreateUniverse { name, start } => {
                Registry::require_author(&p)?;
                let capacity = self.reserve_worker()?;
                universe_store::selector::selector_key(&name)?;
                let id = UniverseId::generate(&mut rand::rng());
                let continuity = ContinuityId::generate(&mut rand::rng());
                let calendar_id = CalendarId::generate(&mut rand::rng());
                let (chronology, calendar_definition) = start
                    .build(calendar_id.clone())
                    .map_err(anyhow::Error::msg)?;
                let path = self
                    .registry
                    .lock()
                    .unwrap()
                    .root
                    .join("packages")
                    .join(format!("{}.sqlite", id.as_str()));
                let principal = PrincipalId::parse(&p.id.as_str().replacen("prf_", "prn_", 1))?;
                let mut kernel =
                    Kernel::create(&path, id.clone(), &name, continuity.clone(), &principal)?;
                // Creating a universe explicitly establishes its objective context.
                let context_id = RecordId::generate(&mut rand::rng());
                let payload =
                    Payload::RepresentedContext(universe_domain::records::RepresentedContext {
                        universe: id.clone(),
                        kind: universe_domain::records::RepresentedContextKind::Objective,
                        parent: None,
                        chronology: Some(chronology),
                        labels: std::collections::BTreeMap::from([(
                            "en".into(),
                            "Objective reality".into(),
                        )]),
                    });
                let record = universe_domain::records::RecordVersion::build(
                    RecordVersionId::generate(&mut rand::rng()),
                    universe_domain::records::RecordIdentity::new(
                        id.clone(),
                        context_id.clone(),
                        payload.kind(),
                    ),
                    payload,
                )?;
                let calendar_record = universe_domain::records::RecordVersion::build(
                    RecordVersionId::generate(&mut rand::rng()),
                    universe_domain::records::RecordIdentity::new(
                        id.clone(),
                        calendar_id.to_record_id()?,
                        universe_domain::records::RecordKind::Calendar,
                    ),
                    Payload::Calendar(calendar_definition),
                )?;
                let revision = kernel.commit(&universe_store::kernel::CommitInput {
                    universe: id.clone(),
                    continuity: continuity.clone(),
                    expected_head: kernel.head(&continuity)?,
                    principal,
                    decision: "create-universe".into(),
                    reason: "Author created objective context".into(),
                    idempotency_key: "create-universe".into(),
                    changes: vec![
                        universe_store::kernel::Assignment {
                            record_id: context_id.clone(),
                            expected: None,
                            next: Some(record),
                        },
                        universe_store::kernel::Assignment {
                            record_id: calendar_id.to_record_id()?,
                            expected: None,
                            next: Some(calendar_record),
                        },
                    ],
                })?;
                // Recheck after disk work and before publishing the registration.
                let mut registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                registry.register(&current, &id, &name, &path)?;
                self.workers.lock().unwrap().insert(
                    id.clone(),
                    Arc::new(Mutex::new(Some(Arc::new(Worker::start(kernel, capacity))))),
                );
                drop(registry);
                json!({"universe_id":id,"continuity_id":continuity,"context_id":context_id,"revision":revision,"name":name})
            }
            EngineRequest::RegisterUniverse { path, name } => {
                Registry::require_author(&p)?;
                let capacity = self.reserve_worker()?;
                let kernel = Kernel::open(&path)?;
                let id = kernel.universe().clone();
                let mut registry = self.registry.lock().unwrap();
                let current = registry.authenticate(h)?;
                registry.register(&current, &id, &name, &path)?;
                self.workers.lock().unwrap().insert(
                    id.clone(),
                    Arc::new(Mutex::new(Some(Arc::new(Worker::start(kernel, capacity))))),
                );
                drop(registry);
                json!({"universe_id":id,"name":name})
            }
            EngineRequest::RenameUniverse { universe_id, name } => {
                self.registry
                    .lock()
                    .unwrap()
                    .rename(&p, &universe_id, &name)?;
                json!({"universe_id":universe_id,"name":name})
            }
            EngineRequest::Enroll => {
                let id = self.registry.lock().unwrap().enroll(&p)?;
                json!({"profile_id":id})
            }
            EngineRequest::Grant { grant } => {
                self.registry.lock().unwrap().grant(&p, &grant)?;
                json!({"granted":true})
            }
            EngineRequest::Revoke { profile_id } => {
                self.registry.lock().unwrap().revoke(&p, &profile_id)?;
                json!({"revoked":true})
            }
            EngineRequest::Shutdown => {
                Registry::require_author(&p)?;
                self.shutdown.cancel();
                json!({"shutdown":"requested"})
            }
        };
        // Avoid disclosing an already computed result after revocation.
        if let Some(authority) = disclosure {
            // Apply the same full authority gate used during preparation: world,
            // entity, predicate and continuity limits can all restrict review.
            let _guard = authority
                .lock()
                .map_err(|_| ProtocolError::not_found("resource"))?;
            return Ok(value);
        }
        let registry = self.registry.lock().unwrap();
        registry.authenticate(h)?;
        Ok(value)
    }
}
pub fn initialize(root: &Path) -> anyhow::Result<ProfileId> {
    let root = private_dir(root)?;
    let _bootstrap = FileLock::acquire(&root.join("bootstrap.lock"))?;
    let _service = FileLock::acquire(&root.join("service.lock"))?;
    Registry::open(&root)?.initialize_author()
}
pub async fn serve(root: &Path, shutdown: CancellationToken) -> anyhow::Result<()> {
    let root = private_dir(root)?;
    let _service = FileLock::acquire(&root.join("service.lock"))?;
    let socket = root.join("engine.sock");
    use std::os::unix::fs::{FileTypeExt, MetadataExt, PermissionsExt};
    if let Ok(meta) = std::fs::symlink_metadata(&socket) {
        anyhow::ensure!(
            meta.file_type().is_socket() && meta.uid() == std::fs::metadata(&root)?.uid(),
            "unsafe stale endpoint"
        );
        std::fs::remove_file(&socket)?;
    }
    let registry = Registry::open(&root)?;
    let listener = UnixListener::bind(&socket)?;
    std::fs::set_permissions(&socket, std::fs::Permissions::from_mode(0o600))?;
    let runtime = Arc::new(Runtime {
        validation_jobs: Arc::new(Semaphore::new(2)),
        agent_connections: Arc::new(Semaphore::new(24)),
        agent_work: Arc::new(Semaphore::new(8)),
        author_work: Arc::new(Semaphore::new(4)),
        registry: Arc::new(Mutex::new(registry)),
        workers: Mutex::new(HashMap::new()),
        worker_capacity: Arc::new(Semaphore::new(32)),
        instance: OperationId::generate(&mut rand::rng()).0,
        shutdown: shutdown.clone(),
    });
    let mut clients = tokio::task::JoinSet::new();
    let mut last_active = tokio::time::Instant::now();
    let mut idle = tokio::time::interval(Duration::from_secs(60));
    let connections = Arc::new(Semaphore::new(32));
    let principals: Arc<Mutex<HashMap<ProfileId, Arc<PrincipalSlots>>>> =
        Arc::new(Mutex::new(HashMap::new()));
    loop {
        tokio::select! {
            _=shutdown.cancelled()=>break,
        _=idle.tick()=>{if clients.is_empty()&&last_active.elapsed()>=Duration::from_secs(900){shutdown.cancel();break}},
            _=clients.join_next(),if !clients.is_empty()=>{last_active=tokio::time::Instant::now();},
            stream=listener.accept()=>{let(stream,_)=stream?;last_active=tokio::time::Instant::now();if stream.peer_cred()?.uid()!=std::fs::metadata(&root)?.uid(){continue}let Ok(permit)=connections.clone().try_acquire_owned()else{continue};let runtime=runtime.clone();let principals=principals.clone();clients.spawn(async move{let _permit=permit;let _=connection(stream,runtime,principals).await;});}
        }
    }
    // Requests already dispatched to blocking workers are allowed to finish.
    while clients.join_next().await.is_some() {}
    for universe in runtime.workers.lock().unwrap().keys() {
        crate::workflow::cancel_universe_jobs(universe);
    }
    let _jobs = runtime
        .validation_jobs
        .clone()
        .acquire_many_owned(2)
        .await?;
    drop(runtime);
    std::fs::remove_file(socket)?;
    Ok(())
}
async fn connection(
    stream: UnixStream,
    runtime: Arc<Runtime>,
    principals: Arc<Mutex<HashMap<ProfileId, Arc<PrincipalSlots>>>>,
) -> anyhow::Result<()> {
    let mut io = Framed::new(
        stream,
        LengthDelimitedCodec::builder()
            .max_frame_length(MAX_FRAME_BYTES)
            .new_codec(),
    );
    let hello: EngineHello = decode(
        &tokio::time::timeout(Duration::from_secs(5), io.next())
            .await?
            .ok_or_else(|| anyhow::anyhow!("handshake missing"))??,
    )
    .map_err(anyhow::Error::msg)?;
    anyhow::ensure!(
        hello.protocol_version == PROTOCOL_VERSION && hello.client_name.len() <= 128,
        "incompatible handshake"
    );
    let r = runtime.clone();
    let h = hello.clone();
    let principal = tokio::task::spawn_blocking(move || r.authenticate(&h)).await??;
    let slots = {
        let mut principals = principals.lock().unwrap();
        anyhow::ensure!(
            principals.len() < 1024 || principals.contains_key(&principal.id),
            "principal capacity"
        );
        principals
            .entry(principal.id.clone())
            .or_insert_with(|| {
                Arc::new(PrincipalSlots {
                    connections: Arc::new(Semaphore::new(8)),
                    requests: Arc::new(Semaphore::new(8)),
                })
            })
            .clone()
    };
    let _connection = slots.connections.clone().try_acquire_owned()?;
    let _agent_connection = if principal.author {
        None
    } else {
        Some(runtime.agent_connections.clone().try_acquire_owned()?)
    };
    let capacity = if principal.author {
        runtime.author_work.clone()
    } else {
        runtime.agent_work.clone()
    };
    let welcome = EngineWelcome {
        protocol_version: PROTOCOL_VERSION.into(),
        service_instance: runtime.instance.clone(),
        principal: principal.id,
        author: principal.author,
        max_frame_bytes: MAX_FRAME_BYTES,
        max_in_flight: 8,
    };
    tokio::time::timeout(
        Duration::from_secs(5),
        io.send(serde_json::to_vec(&welcome)?.into()),
    )
    .await??;
    let mut seen = std::collections::HashSet::new();
    loop {
        let incoming = tokio::select! {_ = runtime.shutdown.cancelled()=>break, msg=tokio::time::timeout(Duration::from_secs(60),io.next())=>msg?};
        let Some(bytes) = incoming else { break };
        let call: EngineCall = decode(&bytes?).map_err(anyhow::Error::msg)?;
        anyhow::ensure!(
            seen.len() < 8192 && seen.insert(call.id),
            "request ID limit or duplicate"
        );
        let result = match slots
            .requests
            .clone()
            .try_acquire_owned()
            .and_then(|principal| {
                capacity
                    .clone()
                    .try_acquire_owned()
                    .map(|cpu| (principal, cpu))
            }) {
            Ok(permit) => {
                let r = runtime.clone();
                let h = hello.clone();
                tokio::task::spawn_blocking(move || {
                    let _permit = permit;
                    r.execute(&h, call.request).map(|mut value| {
                        if value.get("contract_version").is_some() {value["request_id"]=json!(call.id);}
                        value
                    })
                })
                .await?
                .map_err(|e| {
                    e.downcast_ref::<ProtocolError>()
                        .cloned()
                        .or_else(|| e.downcast_ref::<universe_store::StoreError>().map(|_| ProtocolError::StorageFailure { message:"package operation failed structural, integrity, or storage checks".into() }))
                        .unwrap_or(ProtocolError::PolicyDenied {
                        message:
                            "operation unavailable; verify current profile, grant, or package state"
                                .into(),
                    })
                })
            }
            Err(_) => Err(ProtocolError::EvaluationLimitReached {
                message: "principal request limit".into(),
            }),
        };
        let mut encoded = serde_json::to_vec(&EngineReply {
            id: call.id,
            result,
        })?;
        if encoded.len() > MAX_FRAME_BYTES {
            encoded = serde_json::to_vec(&EngineReply {
                id: call.id,
                result: Err(ProtocolError::EvaluationLimitReached {
                    message: "response size limit".into(),
                }),
            })?;
        }
        tokio::time::timeout(Duration::from_secs(5), io.send(encoded.into())).await??;
    }
    Ok(())
}

// Only called under the installation lock for a file published by this attempt
// whose registration transaction failed. Existing packages are never removed.
fn remove_unregistered_package(path: &std::path::Path) -> anyhow::Result<()> {
    for owned in [
        path.to_path_buf(),
        std::path::PathBuf::from(format!("{}-wal", path.display())),
        std::path::PathBuf::from(format!("{}-shm", path.display())),
        path.with_extension("writer.lock"),
    ] {
        match std::fs::remove_file(owned) {
            Ok(()) => (),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => (),
            Err(error) => return Err(error.into()),
        }
    }
    if let Some(parent) = path.parent() {
        std::fs::File::open(parent)?.sync_all()?;
    }
    Ok(())
}

#[cfg(test)]
mod ownership_tests {
    use super::*;
    use sha2::Digest;
    fn runtime(root: &Path) -> Runtime {
        Runtime {
            validation_jobs: Arc::new(Semaphore::new(2)),
            agent_connections: Arc::new(Semaphore::new(24)),
            agent_work: Arc::new(Semaphore::new(8)),
            author_work: Arc::new(Semaphore::new(4)),
            registry: Arc::new(Mutex::new(Registry::open(root).unwrap())),
            workers: Mutex::new(HashMap::new()),
            worker_capacity: Arc::new(Semaphore::new(32)),
            instance: "test".into(),
            shutdown: CancellationToken::new(),
        }
    }
    #[test]
    fn queued_universe_work_does_not_hold_installation_authority() {
        let d = tempfile::tempdir().unwrap();
        let root = d.path().join("installation");
        let author = initialize(&root).unwrap();
        let runtime = Arc::new(runtime(&root));
        let profile = Credential::new(universe_store::credentials::read(&root, &author).unwrap());
        let hello = EngineHello {
            protocol_version: PROTOCOL_VERSION.into(),
            profile_id: author,
            credential: profile,
            client_name: "test".into(),
        };
        runtime
            .execute(
                &hello,
                EngineRequest::CreateUniverse {
                    start: universe_domain::chronology::UniverseStart::Fictional {
                        calendar_name: "Test clock".into(),
                        initial_tick: "0".into(),
                        tick_label: "ticks".into(),
                        ticks_per_month: None,
                    },
                    name: "Busy".into(),
                },
            )
            .unwrap();
        runtime
            .execute(
                &hello,
                EngineRequest::CreateUniverse {
                    start: universe_domain::chronology::UniverseStart::Fictional {
                        calendar_name: "Test clock".into(),
                        initial_tick: "0".into(),
                        tick_label: "ticks".into(),
                        ticks_per_month: None,
                    },
                    name: "Free".into(),
                },
            )
            .unwrap();
        let principal = runtime.authenticate(&hello).unwrap();
        let u = runtime
            .registry
            .lock()
            .unwrap()
            .resolve(&principal, "Busy")
            .unwrap();
        let worker = runtime.worker(&u.universe_id, &u.path).unwrap();
        let (entered_tx, entered_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let occupied = std::thread::spawn(move || {
            worker.run(move |_| {
                entered_tx.send(()).unwrap();
                release_rx.recv().unwrap();
                Ok(Value::Null)
            })
        });
        entered_rx.recv().unwrap();
        let queued = {
            let rt = runtime.clone();
            let h = hello.clone();
            std::thread::spawn(move || {
                rt.execute(
                    &h,
                    EngineRequest::Library {
                        universe: universe_protocol::request::Selector("Busy".into()),
                    },
                )
            })
        };
        let (tx, rx) = std::sync::mpsc::channel();
        let free = {
            let rt = runtime.clone();
            let h = hello.clone();
            std::thread::spawn(move || {
                tx.send(rt.execute(
                    &h,
                    EngineRequest::Library {
                        universe: universe_protocol::request::Selector("Free".into()),
                    },
                ))
                .unwrap()
            })
        };
        let responsive = rx.recv_timeout(Duration::from_secs(2));
        release_tx.send(()).unwrap();
        occupied.join().unwrap().unwrap();
        queued.join().unwrap().unwrap();
        free.join().unwrap();
        assert!(responsive.unwrap().is_ok());
    }
    #[test]
    fn detached_validation_allows_same_universe_reads_polling_and_cancellation() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("installation");
        let author = initialize(&root).unwrap();
        let runtime = Arc::new(runtime(&root));
        let profile = Credential::new(universe_store::credentials::read(&root, &author).unwrap());
        let hello = EngineHello {
            protocol_version: PROTOCOL_VERSION.into(),
            profile_id: author,
            credential: profile,
            client_name: "test".into(),
        };
        let u = runtime
            .execute(
                &hello,
                EngineRequest::CreateUniverse {
                    name: "Alpha".into(),
                    start: universe_domain::chronology::UniverseStart::Fictional {
                        calendar_name: "Days".into(),
                        initial_tick: "0".into(),
                        tick_label: "days".into(),
                        ticks_per_month: None,
                    },
                },
            )
            .unwrap();
        let tool = |name: &str, args: Value| EngineRequest::Tool {
            request: Box::new(universe_protocol::Request::from_tool(name, args).unwrap()),
        };
        let ctx=runtime.execute(&hello,tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).unwrap()["result"]["context_id"].clone();
        let p=runtime.execute(&hello,tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":ctx,"operations":[{"kind":"create_entity","client_ref":"new","record":{"names":[],"classification":null,"classificationResolution":"unclassified","worldAssociations":[],"labels":{"en":"New"},"metadata":{}}}],"submission":"submitted","rationale":"test","idempotency_key":"proposal"}))).unwrap()["result"].clone();
        let (entered, release) = crate::workflow::pause_evaluation(
            serde_json::from_value(u["universe_id"].clone()).unwrap(),
        );
        let queued=runtime.execute(&hello,tool("universe_validate",json!({"mode":"queued_proposal","universe":"Alpha","context_id":ctx,"proposal_reference":{"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]},"check_scope":"universe","idempotency_key":"queued"}))).unwrap();
        entered.recv_timeout(Duration::from_secs(5)).unwrap();
        let (tx, rx) = std::sync::mpsc::channel();
        let rt = runtime.clone();
        let h = hello.clone();
        let reader = std::thread::spawn(move || {
            let id = &queued["result"]["execution"]["operation_id"];
            let poll = rt
                .execute(
                    &h,
                    tool(
                        "universe_get_operation",
                        json!({"lookup":"id","universe":"Alpha","operation_id":id}),
                    ),
                )
                .unwrap();
            assert_eq!(poll["result"]["state"], "running");
            rt.execute(&h,tool("universe_search",json!({"universe":"Alpha","context_id":ctx,"query":"","typed_filters":{"record_kinds":[]},"limit":100}))).unwrap();
            let cancelled = rt
                .execute(
                    &h,
                    tool(
                        "universe_cancel_operation",
                        json!({"universe":"Alpha","operation_id":id,"idempotency_key":"cancel"}),
                    ),
                )
                .unwrap();
            assert_eq!(cancelled["result"]["state"], "cancelled");
            tx.send(()).unwrap();
        });
        let responsive = rx.recv_timeout(Duration::from_secs(2));
        let _ = release.send(());
        reader.join().unwrap();
        assert!(responsive.is_ok());
    }
    #[test]
    fn queued_selected_tool_requests_reject_replacement_withdrawal_and_live_grant_changes() {
        for mutation in ["replacement", "withdrawal", "grant", "restored-grant"] {
            let dir = tempfile::tempdir().unwrap();
            let root = dir.path().join("installation");
            let author = initialize(&root).unwrap();
            let runtime = Arc::new(runtime(&root));
            let hello = |id: ProfileId| {
                let profile =
                    Credential::new(universe_store::credentials::read(&root, &id).unwrap());
                EngineHello {
                    protocol_version: PROTOCOL_VERSION.into(),
                    profile_id: id,
                    credential: profile,
                    client_name: "binding-test".into(),
                }
            };
            let author_hello = hello(author.clone());
            let u = runtime
                .execute(
                    &author_hello,
                    EngineRequest::CreateUniverse {
                        name: "Bindings".into(),
                        start: universe_domain::chronology::UniverseStart::Fictional {
                            calendar_name: "Days".into(),
                            initial_tick: "0".into(),
                            tick_label: "days".into(),
                            ticks_per_month: None,
                        },
                    },
                )
                .unwrap();
            let uid: UniverseId = serde_json::from_value(u["universe_id"].clone()).unwrap();
            let agent: ProfileId = serde_json::from_value(
                runtime
                    .execute(&author_hello, EngineRequest::Enroll)
                    .unwrap()["profile_id"]
                    .clone(),
            )
            .unwrap();
            let grant = |propose| EngineRequest::Grant {
                grant: GrantSpec {
                    profile_id: agent.clone(),
                    universe_id: uid.clone(),
                    worlds: None,
                    propose,
                    edit: propose,
                    protected: propose,
                    limits: GrantLimits::default(),
                },
            };
            runtime.execute(&author_hello, grant(true)).unwrap();
            let h = hello(agent.clone());
            let tool = |name: &str, args: Value| EngineRequest::Tool {
                request: Box::new(universe_protocol::Request::from_tool(name, args).unwrap()),
            };
            let ctx = runtime.execute(&h,tool("universe_open_context",json!({"universe":"Bindings","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).unwrap()["result"]["context_id"].clone();
            let text = "Exact café bytes.\n";
            let staged = runtime
                .execute(
                    &author_hello,
                    EngineRequest::StageSource {
                        universe: universe_protocol::request::Selector("Bindings".into()),
                        label: "Binding proof".into(),
                        text: text.into(),
                    },
                )
                .unwrap();
            let p = runtime.execute(&h,tool("universe_propose",json!({"action":"create","universe":"Bindings","context_id":ctx,"operations":staged["operations"],"submission":"submitted","rationale":"Binding proof","idempotency_key":"proposal"}))).unwrap()["result"].clone();
            let reference =
                json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]});
            let viewed = runtime.execute(&h,tool("universe_get_proposal",json!({"universe":"Bindings","proposal_id":p["proposal_id"],"version":p["version"]}))).unwrap()["result"].clone();
            let source = viewed["compiled_changes"]
                .as_array()
                .unwrap()
                .iter()
                .map(|c| &c["next"])
                .find(|r| r["payload"]["record_kind"] == "source_version")
                .unwrap();
            let mut body = json!({"kind":"source_assessment","proposal":reference,"base_frame":p["base_frame"],"assessor":{"principal":agent.as_str().replacen("prf_","prn_",1),"method":"human_review","tool":null,"assessed_at":"2026-10-03T00:00:00Z"},"sources":[{"key":"passage","source_version":{"universe":uid,"record":source["identity"]["record_id"],"version":source["record_version_id"]},"blob_digest":source["payload"]["digest"],"byte_size":text.len(),"representation":"exact-utf8-v1","ranges":[{"start":0,"end":text.len()}],"work_edition":null,"passage_id":null}],"dependencies":[],"declared_inventory":[],"inventory_declaration":{"kind":"no_material_claims","exclusions":[],"rationale":"Synthetic material"},"claim_mappings":[],"unresolved":[],"conclusion":"consistent_with_declared_inventory"});
            let attach = |body: Value, generation, key| {
                tool(
                    "universe_propose",
                    json!({"action":"attach_assessment","universe":"Bindings","context_id":ctx,"proposal_reference":reference,"expected_selection_generation":generation,"body":body,"idempotency_key":key}),
                )
            };
            runtime
                .execute(&h, attach(body.clone(), 0, "first"))
                .unwrap();
            let (entered, release) = crate::workflow::pause_evaluation(uid.clone());
            let queued = runtime.execute(&h,tool("universe_validate",json!({"mode":"queued_proposal","universe":"Bindings","context_id":ctx,"proposal_reference":reference,"check_scope":"universe","idempotency_key":"queue"}))).unwrap();
            entered.recv_timeout(Duration::from_secs(5)).unwrap();
            let oid = queued["result"]["execution"]["operation_id"].clone();
            match mutation {
                "replacement" => {
                    body["assessor"]["assessed_at"] = json!("2026-10-03T00:00:01Z");
                    runtime.execute(&h, attach(body, 1, "second")).unwrap();
                }
                "withdrawal" => {
                    runtime.execute(&h,tool("universe_propose",json!({"action":"select_assessment","universe":"Bindings","context_id":ctx,"proposal_reference":reference,"expected_selection_generation":1,"assessment_reference":null,"idempotency_key":"withdraw"}))).unwrap();
                }
                "grant" => {
                    runtime.execute(&author_hello, grant(false)).unwrap();
                }
                "restored-grant" => {
                    runtime.execute(&author_hello, grant(false)).unwrap();
                    runtime.execute(&author_hello, grant(true)).unwrap();
                }
                _ => unreachable!(),
            }
            release.send(()).unwrap();
            let deadline = std::time::Instant::now() + Duration::from_secs(5);
            loop {
                let status = runtime
                    .execute(
                        &h,
                        tool(
                            "universe_get_operation",
                            json!({"lookup":"id","universe":"Bindings","operation_id":oid}),
                        ),
                    )
                    .unwrap()["result"]
                    .clone();
                if status["state"] != "running" {
                    assert!(
                        status["state"] == "failed" || status["state"] == "interrupted",
                        "{mutation}: {status}"
                    );
                    assert!(status["validation"]["final_binding_digest"].is_null());
                    assert_eq!(status["validation"]["assessment"]["kind"], "unavailable");
                    break;
                }
                assert!(std::time::Instant::now() < deadline);
                std::thread::sleep(Duration::from_millis(10));
            }
        }
    }
    #[test]
    fn assessment_publication_rejects_concurrent_selection_and_revoked_authority() {
        for mutation in [
            "replacement",
            "withdrawal",
            "grant",
            "restored-grant",
            "revoke",
        ] {
            let dir = tempfile::tempdir().unwrap();
            let root = dir.path().join("installation");
            let author = initialize(&root).unwrap();
            let runtime = Arc::new(runtime(&root));
            let hello = |id: ProfileId| {
                let profile =
                    Credential::new(universe_store::credentials::read(&root, &id).unwrap());
                EngineHello {
                    protocol_version: PROTOCOL_VERSION.into(),
                    profile_id: id,
                    credential: profile,
                    client_name: "binding-test".into(),
                }
            };
            let author_hello = hello(author.clone());
            let u = runtime
                .execute(
                    &author_hello,
                    EngineRequest::CreateUniverse {
                        name: "Bindings".into(),
                        start: universe_domain::chronology::UniverseStart::Fictional {
                            calendar_name: "Days".into(),
                            initial_tick: "0".into(),
                            tick_label: "days".into(),
                            ticks_per_month: None,
                        },
                    },
                )
                .unwrap();
            let uid: UniverseId = serde_json::from_value(u["universe_id"].clone()).unwrap();
            let agent: ProfileId = serde_json::from_value(
                runtime
                    .execute(&author_hello, EngineRequest::Enroll)
                    .unwrap()["profile_id"]
                    .clone(),
            )
            .unwrap();
            let grant = |propose| EngineRequest::Grant {
                grant: GrantSpec {
                    profile_id: agent.clone(),
                    universe_id: uid.clone(),
                    worlds: None,
                    propose,
                    edit: propose,
                    protected: propose,
                    limits: GrantLimits::default(),
                },
            };
            runtime.execute(&author_hello, grant(true)).unwrap();
            let h = hello(agent.clone());
            let tool = |name: &str, args: Value| EngineRequest::Tool {
                request: Box::new(universe_protocol::Request::from_tool(name, args).unwrap()),
            };
            let ctx = runtime.execute(&h,tool("universe_open_context",json!({"universe":"Bindings","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).unwrap()["result"]["context_id"].clone();
            let text = "Exact café bytes.\n";
            let staged = runtime
                .execute(
                    &author_hello,
                    EngineRequest::StageSource {
                        universe: universe_protocol::request::Selector("Bindings".into()),
                        label: "Binding proof".into(),
                        text: text.into(),
                    },
                )
                .unwrap();
            let p = runtime.execute(&h,tool("universe_propose",json!({"action":"create","universe":"Bindings","context_id":ctx,"operations":staged["operations"],"submission":"submitted","rationale":"Binding proof","idempotency_key":"proposal"}))).unwrap()["result"].clone();
            let reference =
                json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]});
            let viewed = runtime.execute(&h,tool("universe_get_proposal",json!({"universe":"Bindings","proposal_id":p["proposal_id"],"version":p["version"]}))).unwrap()["result"].clone();
            let source = viewed["compiled_changes"]
                .as_array()
                .unwrap()
                .iter()
                .map(|c| &c["next"])
                .find(|r| r["payload"]["record_kind"] == "source_version")
                .unwrap();
            let body = json!({"kind":"source_assessment","proposal":reference,"base_frame":p["base_frame"],"assessor":{"principal":agent.as_str().replacen("prf_","prn_",1),"method":"human_review","tool":null,"assessed_at":"2026-10-03T00:00:00Z"},"sources":[{"key":"passage","source_version":{"universe":uid,"record":source["identity"]["record_id"],"version":source["record_version_id"]},"blob_digest":source["payload"]["digest"],"byte_size":text.len(),"representation":"exact-utf8-v1","ranges":[{"start":0,"end":text.len()}],"work_edition":null,"passage_id":null}],"dependencies":[],"declared_inventory":[],"inventory_declaration":{"kind":"no_material_claims","exclusions":[],"rationale":"Synthetic material"},"claim_mappings":[],"unresolved":[],"conclusion":"consistent_with_declared_inventory"});
            let attach = |body: Value, generation, key| {
                tool(
                    "universe_propose",
                    json!({"action":"attach_assessment","universe":"Bindings","context_id":ctx,"proposal_reference":reference,"expected_selection_generation":generation,"body":body,"idempotency_key":key}),
                )
            };
            runtime
                .execute(&h, attach(body.clone(), 0, "first"))
                .unwrap();
            let validated = runtime.execute(&h,tool("universe_validate",json!({"mode":"proposal","universe":"Bindings","context_id":ctx,"proposal_reference":reference,"check_scope":"universe"}))).unwrap()["result"].clone();
            let run: ValidationRunId =
                serde_json::from_value(validated["execution"]["run_id"].clone()).unwrap();
            runtime
                .execute(
                    &author_hello,
                    EngineRequest::Approve {
                        universe: universe_protocol::request::Selector("Bindings".into()),
                        proposal_reference: serde_json::from_value(reference.clone()).unwrap(),
                        validation_run: run.clone(),
                    },
                )
                .unwrap();
            let package = root.join("packages").join(format!("{uid}.sqlite"));
            let db = rusqlite::Connection::open(&package).unwrap();
            let head: String = db
                .query_row("SELECT head_commit FROM continuities", [], |r| r.get(0))
                .unwrap();
            let receipts: i64 = db
                .query_row("SELECT count(*) FROM operation_receipts", [], |r| r.get(0))
                .unwrap();
            let (entered, release) = crate::workflow::pause_publication(uid.clone());
            let rt = runtime.clone();
            let commit_hello = h.clone();
            let request = tool(
                "universe_commit",
                json!({"universe":"Bindings","proposal_reference":reference,"expected_base_revision":p["base_frame"]["revision"],"validation_run":run,"idempotency_key":"commit"}),
            );
            let job = std::thread::spawn(move || rt.execute(&commit_hello, request));
            entered.recv_timeout(Duration::from_secs(5)).unwrap();
            match mutation {
                "grant" | "restored-grant" => {
                    runtime.execute(&author_hello, grant(false)).unwrap();
                    if mutation == "restored-grant" {
                        runtime.execute(&author_hello, grant(true)).unwrap();
                    }
                }
                "revoke" => {
                    runtime
                        .execute(&author_hello, EngineRequest::Revoke { profile_id: agent })
                        .unwrap();
                }
                "replacement" | "withdrawal" => {
                    // The worker serializes public selections. A separate fixture
                    // writer exercises the last SQLite comparison after private recheck.
                    let key: String = db.query_row("SELECT key FROM workflow_entries WHERE key LIKE 'assessment-selection:%' ORDER BY key DESC LIMIT 1", [], |r| r.get(0)).unwrap();
                    let (proposal_row, selected_row): (i64, Option<i64>) = db.query_row("SELECT s.proposal,s.selected FROM workflow_entries w JOIN r_assessment_selection s ON s.__row_id=w.AssessmentSelection WHERE w.key=?1",[&key],|r|Ok((r.get(0)?,r.get(1)?))).unwrap();
                    let (proposal_id, version, proposal_digest): (String,String,String) = db.query_row("SELECT proposal_id,version,digest FROM r_assessment_selection_proposal WHERE __row_id=?1",[proposal_row],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?))).unwrap();
                    let selected = if mutation == "withdrawal" {
                        Value::Null
                    } else {
                        let digest: String = db.query_row("SELECT a.digest FROM r_assessment_selection_selected s JOIN r_assessment_ref a ON a.__row_id=s.v0 WHERE s.__row_id=?1",[selected_row.unwrap()],|r|r.get(0)).unwrap();
                        json!({"assessment_id":"asm_000000000000000000000002","digest":digest})
                    };
                    let selection = json!({"proposal":{"proposal_id":proposal_id,"version":version.parse::<u64>().unwrap(),"digest":proposal_digest},"generation":2,"selected":selected});
                    db.execute_batch("BEGIN IMMEDIATE").unwrap();
                    let reference_row = if selected.is_null() {
                        None
                    } else {
                        db.execute("INSERT INTO r_assessment_ref(assessment_id__state,assessment_id,digest__state,digest) VALUES(2,?1,2,?2)",rusqlite::params![selected["assessment_id"].as_str().unwrap(),selected["digest"].as_str().unwrap()]).unwrap();
                        let row = db.last_insert_rowid();
                        db.execute(
                            "INSERT INTO r_assessment_selection_selected(variant,v0) VALUES(0,?1)",
                            [row],
                        )
                        .unwrap();
                        Some(db.last_insert_rowid())
                    };
                    db.execute("INSERT INTO r_assessment_selection(proposal__state,proposal,generation__state,generation,selected__state,selected) VALUES(2,?1,2,'2',?2,?3)",rusqlite::params![proposal_row,if selected.is_null(){1}else{2},reference_row]).unwrap();
                    let row = db.last_insert_rowid();
                    let next_key = format!("{}{:020}", &key[..key.len() - 20], 2);
                    let bytes = universe_domain::canonical::canonical_serde(&selection).to_bytes();
                    let digest = hex::encode(sha2::Sha256::digest(&bytes));
                    db.execute("INSERT INTO workflow_entries(key,family,digest,digest_recipe,AssessmentSelection) VALUES(?1,'AssessmentSelection',?2,'workflow-canonical',?3)",rusqlite::params![next_key,digest,row]).unwrap();
                    db.execute_batch("COMMIT").unwrap();
                }
                _ => unreachable!(),
            }
            release.send(()).unwrap();
            assert!(job.join().unwrap().is_err(), "{mutation}");
            assert_eq!(
                db.query_row("SELECT head_commit FROM continuities", [], |r| r
                    .get::<_, String>(0))
                    .unwrap(),
                head
            );
            assert_eq!(
                db.query_row("SELECT count(*) FROM operation_receipts", [], |r| r
                    .get::<_, i64>(0))
                    .unwrap(),
                receipts
            );
        }
    }
    #[test]
    fn assessment_publication_delegation_requires_exact_selection_and_current_bounds() {
        for mutation in ["valid", "withdrawal", "replacement", "revoked", "expired"] {
            let dir = tempfile::tempdir().unwrap();
            let root = dir.path().join("installation");
            let author = initialize(&root).unwrap();
            let runtime = Arc::new(runtime(&root));
            let hello = |id: ProfileId| {
                let profile =
                    Credential::new(universe_store::credentials::read(&root, &id).unwrap());
                EngineHello {
                    protocol_version: PROTOCOL_VERSION.into(),
                    profile_id: id,
                    credential: profile,
                    client_name: "binding-test".into(),
                }
            };
            let author_hello = hello(author.clone());
            let u = runtime
                .execute(
                    &author_hello,
                    EngineRequest::CreateUniverse {
                        name: "Bindings".into(),
                        start: universe_domain::chronology::UniverseStart::Fictional {
                            calendar_name: "Days".into(),
                            initial_tick: "0".into(),
                            tick_label: "days".into(),
                            ticks_per_month: None,
                        },
                    },
                )
                .unwrap();
            let uid: UniverseId = serde_json::from_value(u["universe_id"].clone()).unwrap();
            let agent: ProfileId = serde_json::from_value(
                runtime
                    .execute(&author_hello, EngineRequest::Enroll)
                    .unwrap()["profile_id"]
                    .clone(),
            )
            .unwrap();
            let grant = |propose| EngineRequest::Grant {
                grant: GrantSpec {
                    profile_id: agent.clone(),
                    universe_id: uid.clone(),
                    worlds: None,
                    propose,
                    edit: propose,
                    protected: propose,
                    limits: GrantLimits::default(),
                },
            };
            runtime.execute(&author_hello, grant(true)).unwrap();
            let h = hello(agent.clone());
            let tool = |name: &str, args: Value| EngineRequest::Tool {
                request: Box::new(universe_protocol::Request::from_tool(name, args).unwrap()),
            };
            let ctx = runtime.execute(&h,tool("universe_open_context",json!({"universe":"Bindings","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).unwrap()["result"]["context_id"].clone();
            let text = "Exact café bytes.\n";
            let staged = runtime
                .execute(
                    &author_hello,
                    EngineRequest::StageSource {
                        universe: universe_protocol::request::Selector("Bindings".into()),
                        label: "Binding proof".into(),
                        text: text.into(),
                    },
                )
                .unwrap();
            let entity = RecordId::generate(&mut rand::rng());
            let predicate = RecordId::generate(&mut rand::rng());
            let mut ops = staged["operations"].as_array().unwrap().clone();
            ops.push(json!({"kind":"create_entity","client_ref":entity,"record":{"names":[],"classification":null,"classificationResolution":"unclassified","worldAssociations":[],"labels":{"en":"Subject"},"metadata":{}}}));
            ops.push(json!({"kind":"define_property","client_ref":predicate,"record":{"namespace":"proof","key":"flag","labels":{},"subjectTypes":[],"value":{"kind":"boolean"},"multiplicity":"single","persistence":"explicit_interval","exclusive":true,"symmetric":false,"transitive":false}}));
            let setup = runtime.execute(&h,tool("universe_propose",json!({"action":"create","universe":"Bindings","context_id":ctx,"operations":ops,"submission":"submitted","rationale":"Retained source and delegation bounds","idempotency_key":"setup"}))).unwrap()["result"].clone();
            let setup_ref = json!({"proposal_id":setup["proposal_id"],"version":setup["version"],"digest":setup["digest"]});
            let viewed = runtime.execute(&h,tool("universe_get_proposal",json!({"universe":"Bindings","proposal_id":setup["proposal_id"],"version":setup["version"]}))).unwrap()["result"].clone();
            let source = viewed["compiled_changes"]
                .as_array()
                .unwrap()
                .iter()
                .map(|c| &c["next"])
                .find(|r| r["payload"]["record_kind"] == "source_version")
                .unwrap();
            let v = runtime.execute(&h,tool("universe_validate",json!({"mode":"proposal","universe":"Bindings","context_id":ctx,"proposal_reference":setup_ref,"check_scope":"universe"}))).unwrap()["result"].clone();
            runtime
                .execute(
                    &author_hello,
                    EngineRequest::Approve {
                        universe: universe_protocol::request::Selector("Bindings".into()),
                        proposal_reference: serde_json::from_value(setup_ref.clone()).unwrap(),
                        validation_run: serde_json::from_value(v["execution"]["run_id"].clone())
                            .unwrap(),
                    },
                )
                .unwrap();
            runtime.execute(&h,tool("universe_commit",json!({"universe":"Bindings","proposal_reference":setup_ref,"expected_base_revision":setup["base_frame"]["revision"],"validation_run":v["execution"]["run_id"],"idempotency_key":"setup-commit"}))).unwrap();
            let expiry = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs()
                + 3600;
            let limits = GrantLimits {
                entities: Some(vec![entity.clone()]),
                predicates: Some(vec![predicate.clone()]),
                continuities: Some(vec![
                    serde_json::from_value(u["continuity_id"].clone()).unwrap()
                ]),
                expires_at: Some(expiry),
                delegated_commit: true,
                allow_shared: true,
            };
            let delegated = GrantSpec {
                profile_id: agent.clone(),
                universe_id: uid.clone(),
                worlds: None,
                propose: true,
                edit: true,
                protected: false,
                limits,
            };
            runtime
                .execute(
                    &author_hello,
                    EngineRequest::Grant {
                        grant: delegated.clone(),
                    },
                )
                .unwrap();
            let ctx = runtime.execute(&h,tool("universe_open_context",json!({"universe":"Bindings","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).unwrap()["result"]["context_id"].clone();
            let proposition = json!({"kind":"define_proposition","client_ref":RecordId::generate(&mut rand::rng()),"record":{"subject":{"universe":uid,"record":entity},"predicate":{"universe":uid,"record":predicate},"value":{"kind":"boolean","value":true},"context":{"universe":uid,"record":u["context_id"]},"quantification":"particular"}});
            let p = runtime.execute(&h,tool("universe_propose",json!({"action":"create","universe":"Bindings","context_id":ctx,"operations":[proposition],"submission":"submitted","rationale":"Delegated candidate","idempotency_key":"candidate"}))).unwrap()["result"].clone();
            let reference =
                json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]});
            let author_ctx = runtime.execute(&author_hello,tool("universe_open_context",json!({"universe":"Bindings","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).unwrap()["result"]["context_id"].clone();
            let mut body = json!({"kind":"source_assessment","proposal":reference,"base_frame":p["base_frame"],"assessor":{"principal":author.as_str().replacen("prf_","prn_",1),"method":"human_review","tool":null,"assessed_at":"2026-10-03T00:00:00Z"},"sources":[{"key":"passage","source_version":{"universe":uid,"record":source["identity"]["record_id"],"version":source["record_version_id"]},"blob_digest":source["payload"]["digest"],"byte_size":text.len(),"representation":"exact-utf8-v1","ranges":[{"start":0,"end":text.len()}],"work_edition":null,"passage_id":null}],"dependencies":[],"declared_inventory":[],"inventory_declaration":{"kind":"no_material_claims","exclusions":[],"rationale":"Synthetic material"},"claim_mappings":[],"unresolved":[],"conclusion":"consistent_with_declared_inventory"});
            runtime.execute(&author_hello,tool("universe_propose",json!({"action":"attach_assessment","universe":"Bindings","context_id":author_ctx,"proposal_reference":reference,"expected_selection_generation":0,"body":body,"idempotency_key":"attach"}))).unwrap();
            // Delegation grants publication bounds, not source review access.
            assert!(runtime.execute(&h,tool("universe_get_proposal",json!({"universe":"Bindings","proposal_id":p["proposal_id"],"version":p["version"],"view_group":"assessment"}))).is_err());
            let v = runtime.execute(&author_hello,tool("universe_validate",json!({"mode":"proposal","universe":"Bindings","context_id":author_ctx,"proposal_reference":reference,"check_scope":"universe"}))).unwrap()["result"].clone();
            match mutation {
                "withdrawal" => {
                    runtime.execute(&author_hello,tool("universe_propose",json!({"action":"select_assessment","universe":"Bindings","context_id":author_ctx,"proposal_reference":reference,"expected_selection_generation":1,"assessment_reference":null,"idempotency_key":"withdraw"}))).unwrap();
                }
                "replacement" => {
                    body["assessor"]["assessed_at"] = json!("2026-10-03T00:00:01Z");
                    runtime.execute(&author_hello,tool("universe_propose",json!({"action":"attach_assessment","universe":"Bindings","context_id":author_ctx,"proposal_reference":reference,"expected_selection_generation":1,"body":body,"idempotency_key":"replace"}))).unwrap();
                }
                "revoked" => {
                    runtime.execute(&author_hello, grant(false)).unwrap();
                }
                "expired" => {
                    // Deterministic clock-independent expiry control in this owned fixture.
                    let db = rusqlite::Connection::open(root.join("installation.sqlite")).unwrap();
                    let mut expired = delegated.limits.clone();
                    expired.expires_at = Some(1);
                    db.execute(
                        "UPDATE grants SET expires_at=?1 WHERE profile=?2 AND universe=?3",
                        rusqlite::params![
                            expired.expires_at.unwrap().to_string(),
                            agent.as_str(),
                            uid.as_str()
                        ],
                    )
                    .unwrap();
                }
                "valid" => {}
                _ => unreachable!(),
            }
            let db =
                rusqlite::Connection::open(root.join("packages").join(format!("{uid}.sqlite")))
                    .unwrap();
            let head: String = db
                .query_row("SELECT head_commit FROM continuities", [], |r| r.get(0))
                .unwrap();
            let outcome = runtime.execute(&h,tool("universe_commit",json!({"universe":"Bindings","proposal_reference":reference,"expected_base_revision":p["base_frame"]["revision"],"validation_run":v["execution"]["run_id"],"idempotency_key":"delegated"})));
            assert_eq!(
                outcome.is_ok(),
                mutation == "valid",
                "{mutation}: {outcome:?}"
            );
            let after: String = db
                .query_row("SELECT head_commit FROM continuities", [], |r| r.get(0))
                .unwrap();
            if mutation == "valid" {
                assert_ne!(head, after);
            } else {
                assert_eq!(head, after);
            }
            let approvals: i64 = db
                .query_row(
                    "SELECT count(*) FROM workflow_entries WHERE key LIKE ?1",
                    [format!("approval:%:{}:%", p["digest"].as_str().unwrap())],
                    |r| r.get(0),
                )
                .unwrap();
            assert_eq!(approvals, 0);
        }
    }
    #[test]
    fn failed_recovery_does_not_exhaust_worker_capacity() {
        let d = tempfile::tempdir().unwrap();
        let root = d.path().join("installation");
        let runtime = runtime(&root);
        for n in 0..32 {
            assert!(runtime
                .worker(
                    &UniverseId::generate(&mut rand::rng()),
                    &root.join(format!("missing-{n}.sqlite"))
                )
                .is_err());
        }
        let u = UniverseId::generate(&mut rand::rng());
        let path = root.join("packages/healthy.sqlite");
        drop(
            Kernel::create(
                &path,
                u.clone(),
                "Healthy",
                ContinuityId::generate(&mut rand::rng()),
                &PrincipalId::generate(&mut rand::rng()),
            )
            .unwrap(),
        );
        assert!(
            runtime.worker(&u, &path).is_ok(),
            "failed recoveries retained all worker slots"
        );
    }
    #[test]
    fn concurrent_recovery_releases_failures_and_shares_one_writer() {
        let d = tempfile::tempdir().unwrap();
        let root = d.path().join("installation");
        let runtime = Arc::new(runtime(&root));
        let u = UniverseId::generate(&mut rand::rng());
        let path = root.join("packages/owned.sqlite");
        let kernel = Kernel::create(
            &path,
            u.clone(),
            "Owned",
            ContinuityId::generate(&mut rand::rng()),
            &PrincipalId::generate(&mut rand::rng()),
        )
        .unwrap();
        let attempt = || {
            let barrier = Arc::new(std::sync::Barrier::new(8));
            (0..8)
                .map(|_| {
                    let runtime = runtime.clone();
                    let u = u.clone();
                    let path = path.clone();
                    let barrier = barrier.clone();
                    std::thread::spawn(move || {
                        barrier.wait();
                        runtime.worker(&u, &path)
                    })
                })
                .collect::<Vec<_>>()
                .into_iter()
                .map(|t| t.join().unwrap())
                .collect::<Vec<_>>()
        };
        assert!(attempt().iter().all(Result::is_err));
        assert!(runtime.workers.lock().unwrap().is_empty());
        assert_eq!(runtime.worker_capacity.available_permits(), 32);
        drop(kernel);
        let workers: Vec<_> = attempt().into_iter().map(Result::unwrap).collect();
        assert!(workers.iter().all(|w| Arc::ptr_eq(w, &workers[0])));
        assert_eq!(runtime.worker_capacity.available_permits(), 31);
    }
    #[test]
    fn concurrent_creates_reserve_capacity_before_touching_packages() {
        let d = tempfile::tempdir().unwrap();
        let root = d.path().join("installation");
        let author = initialize(&root).unwrap();
        let runtime = Arc::new(runtime(&root));
        let profile = Credential::new(universe_store::credentials::read(&root, &author).unwrap());
        let hello = EngineHello {
            protocol_version: PROTOCOL_VERSION.into(),
            profile_id: author,
            credential: profile,
            client_name: "test".into(),
        };
        for n in 0..31 {
            runtime
                .execute(
                    &hello,
                    EngineRequest::CreateUniverse {
                        start: universe_domain::chronology::UniverseStart::Fictional {
                            calendar_name: "Test clock".into(),
                            initial_tick: "0".into(),
                            tick_label: "ticks".into(),
                            ticks_per_month: None,
                        },
                        name: format!("Universe {n}"),
                    },
                )
                .unwrap();
        }
        let barrier = Arc::new(std::sync::Barrier::new(4));
        let results = (0..4)
            .map(|n| {
                let runtime = runtime.clone();
                let hello = hello.clone();
                let barrier = barrier.clone();
                std::thread::spawn(move || {
                    barrier.wait();
                    runtime.execute(
                        &hello,
                        EngineRequest::CreateUniverse {
                            start: universe_domain::chronology::UniverseStart::Fictional {
                                calendar_name: "Test clock".into(),
                                initial_tick: "0".into(),
                                tick_label: "ticks".into(),
                                ticks_per_month: None,
                            },
                            name: format!("Contender {n}"),
                        },
                    )
                })
            })
            .collect::<Vec<_>>()
            .into_iter()
            .map(|t| t.join().unwrap())
            .collect::<Vec<_>>();
        assert_eq!(results.iter().filter(|r| r.is_ok()).count(), 1);
        for error in results.into_iter().filter_map(Result::err) {
            assert!(matches!(
                error.downcast_ref::<ProtocolError>(),
                Some(ProtocolError::EvaluationLimitReached { .. })
            ));
        }
        assert_eq!(runtime.workers.lock().unwrap().len(), 32);
        assert_eq!(runtime.worker_capacity.available_permits(), 0);
        let packages = std::fs::read_dir(root.join("packages"))
            .unwrap()
            .filter_map(Result::ok)
            .filter(|e| e.path().extension().is_some_and(|ext| ext == "sqlite"))
            .count();
        assert_eq!(packages, 32);
    }
}
