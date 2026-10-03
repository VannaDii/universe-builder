//! Selection snapshots and exact validation bindings. No assessment publication path.
use super::*;
use universe_protocol::assessment::{
    execution_result_digest, AssessmentSelection, SourceValidationBindingV1, ValidationBindingKind,
};

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct ValidationCapture {
    selection: AssessmentSelection,
    assessment: AssessmentState,
    submitted_input: SubmittedInput,
    head: RevisionId,
    latest_proposal_key: Option<String>,
    authority_digest: String,
    #[serde(default)]
    authority_sequence: Option<i64>,
}
pub(super) fn proposal_reference(p: &StoredProposal) -> ProposalRef {
    ProposalRef {
        proposal_id: p.proposal.proposal_id.clone(),
        version: p.proposal.version,
        digest: p.proposal.digest.clone(),
    }
}
pub(super) fn record_input(p: &StoredProposal) -> SubmittedInput {
    SubmittedInput::RecordCandidate {
        proposal: proposal_reference(p),
        includes_sources: p.changes.iter().any(|a| {
            a.next.as_ref().is_some_and(|r| {
                matches!(
                    r.payload,
                    Payload::Source(_)
                        | Payload::SourceVersion(_)
                        | Payload::Anchor(_)
                        | Payload::WorkVersion(_)
                )
            })
        }),
    }
}
impl ValidationCapture {
    pub(super) fn report(
        &self,
        p: &StoredProposal,
        execution: Validation,
        finished: bool,
    ) -> anyhow::Result<ValidationV3> {
        let final_binding_digest = if finished {
            Some(
                SourceValidationBindingV1 {
                    kind: ValidationBindingKind::SourceValidationBindingV1,
                    proposal: proposal_reference(p),
                    base_frame: p.proposal.base_frame.clone(),
                    selection: self.selection.clone(),
                    submitted_input: self.submitted_input.clone(),
                    assessment_state: self.assessment.clone(),
                    execution_result_digest: execution_result_digest(&execution),
                    evaluator_version: execution.evaluator_version.clone(),
                }
                .digest()
                .map_err(|e| ProtocolError::invalid_argument("validation_binding", e))?,
            )
        } else {
            None
        };
        Ok(ValidationV3::Evaluated {
            execution: Box::new(execution),
            submitted_input: Box::new(self.submitted_input.clone()),
            assessment: self.assessment.clone(),
            final_binding_digest,
        })
    }
    fn comparisons(&self) -> Vec<(String, Option<String>)> {
        let r = &self.selection.proposal;
        let prefix = format!("assessment-selection:{}:{:020}:", r.proposal_id, r.version);
        vec![
            (
                prefix.clone(),
                (self.selection.generation > 0)
                    .then(|| format!("{prefix}{:020}", self.selection.generation)),
            ),
            (
                format!("proposal:{}:", r.proposal_id),
                self.latest_proposal_key.clone(),
            ),
        ]
    }
}
impl Workflow<'_> {
    fn validation_authority_digest(&self) -> String {
        hash(&(
            &self.principal.id,
            self.principal.author,
            &self.approval_author,
            self.scope_hash(),
        ))
    }
    pub(super) fn capture_validation(
        &self,
        p: &StoredProposal,
    ) -> anyhow::Result<ValidationCapture> {
        let authority = self.authority.clone();
        let _guard = authority.as_ref().map(|a| a.lock()).transpose()?;
        let r = proposal_reference(p);
        let selection = self.assessment_selection_raw(&r)?;
        // Unassessed records retain their existing write-boundary admission.
        // Full source/dependency visibility is required only for an attachment.
        let (selection, assessment, envelope) = if selection.selected.is_some() {
            self.resolve_assessment(&r, None)?
        } else {
            (selection, AssessmentState::Absent {}, None)
        };
        let submitted_input = match (&assessment, envelope) {
            (
                AssessmentState::Bound {
                    inventory_digest, ..
                },
                Some(e),
            ) => SubmittedInput::SourceAssessedCandidate {
                proposal: r.clone(),
                sources: e.body.sources,
                inventory_digest: inventory_digest.clone(),
            },
            _ => record_input(p),
        };
        Ok(ValidationCapture {
            selection,
            assessment,
            submitted_input,
            head: self.kernel.head(&p.proposal.base_frame.continuity)?,
            latest_proposal_key: self
                .kernel
                .workflow_latest_key(&format!("proposal:{}:", r.proposal_id))?,
            authority_digest: self.validation_authority_digest(),
            authority_sequence: _guard
                .as_ref()
                .map(|r| {
                    r.validation_authority_sequence(&self.principal.id, self.kernel.universe())
                })
                .transpose()?,
        })
    }
    pub(super) fn verify_validation_capture(
        &self,
        p: &StoredProposal,
        capture: &ValidationCapture,
    ) -> anyhow::Result<()> {
        let r = proposal_reference(p);
        if capture.selection.proposal != r
            || capture.authority_digest != self.validation_authority_digest()
            || self.kernel.head(&p.proposal.base_frame.continuity)? != capture.head
            || self
                .kernel
                .workflow_latest_key(&format!("proposal:{}:", r.proposal_id))?
                != capture.latest_proposal_key
        {
            return Err(ProtocolError::ApprovalStale.into());
        }
        let selection = self.assessment_selection_raw(&r)?;
        if hash(&selection) != hash(&capture.selection) {
            return Err(ProtocolError::ApprovalStale.into());
        }
        let state = if selection.selected.is_some() {
            self.resolve_assessment(&r, None)?.1
        } else {
            AssessmentState::Absent {}
        };
        if hash(&state) != hash(&capture.assessment) {
            return Err(ProtocolError::ApprovalStale.into());
        }
        Ok(())
    }
    pub(super) fn verify_validation_authority(
        &self,
        capture: &ValidationCapture,
        registry: Option<&crate::registry::Registry>,
    ) -> anyhow::Result<()> {
        let current = registry
            .map(|r| r.validation_authority_sequence(&self.principal.id, self.kernel.universe()))
            .transpose()?;
        if capture.authority_sequence != current {
            return Err(ProtocolError::ApprovalStale.into());
        }
        Ok(())
    }
    pub(super) fn persist_bound_validation(
        &mut self,
        p: &StoredProposal,
        capture: Option<&ValidationCapture>,
        entries: &[(String, Value)],
    ) -> anyhow::Result<()> {
        let authority = self.authority.clone();
        let _guard = authority.as_ref().map(|a| a.lock()).transpose()?;
        if let Some(capture) = capture {
            self.verify_validation_authority(capture, _guard.as_deref())?;
            self.verify_validation_capture(p, capture)?;
            // The owning universe worker and package writer lock serialize head
            // changes. Selection/proposal comparisons and all evidence append
            // atomically while current installation authority remains locked.
            self.kernel
                .workflow_compare_append(&capture.comparisons(), entries)?;
        } else {
            self.kernel.workflow_put(entries)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::super::assessments::tests::{body, freeze, reference, workflow};
    use super::*;
    use universe_protocol::assessment::*;

    fn setup(kernel: &mut Kernel, profile: &ProfileId) -> (StoredProposal, SourceAssessmentV1) {
        let mut w = workflow(kernel, profile);
        let text = "Exact café bytes.\n";
        let staged = w.stage_source("Binding proof".into(), text.into()).unwrap();
        let frame = Frame {
            universe: w.kernel.universe().clone(),
            continuity: ContinuityId::parse(&w.kernel.status().unwrap().heads[0].0).unwrap(),
            revision: w
                .kernel
                .head(&ContinuityId::parse(&w.kernel.status().unwrap().heads[0].0).unwrap())
                .unwrap(),
            context: RecordRef::new(
                w.kernel.universe().clone(),
                RecordId::generate(&mut rand::rng()),
            ),
            perspective: Perspective::Author,
            time: FrameTime::Timeless,
            reader_scene: None,
            personal_sequence: None,
        };
        let p = freeze(
            &mut w,
            frame,
            serde_json::from_value(staged["operations"].clone()).unwrap(),
            None,
        );
        let b = body(&p, profile, text);
        (p, b)
    }
    fn synchronous(w: &mut Workflow<'_>, p: &StoredProposal) -> Checked {
        let capture = w.capture_validation(p).unwrap();
        let mut checked = w.check(p).unwrap();
        checked.report = Some(capture.report(p, checked.validation.clone(), true).unwrap());
        checked.capture = Some(capture.clone());
        w.persist_bound_validation(
            p,
            Some(&capture),
            &[(
                format!("validation:{}", checked.validation.run_id),
                serde_json::to_value(&checked).unwrap(),
            )],
        )
        .unwrap();
        checked
    }
    fn queued(w: &mut Workflow<'_>, p: &StoredProposal, key: &str) -> OperationId {
        let id = OperationId::generate(&mut rand::rng());
        let op = StoredOperation {
            owner: w.principal.id.clone(),
            digest: key.into(),
            status: OperationStatus {
                operation_id: id.clone(),
                kind: OperationKind::Validate,
                state: OperationState::Queued,
                proposal: Some(p.proposal.clone()),
                validation: None,
                receipt: None,
                cancellation_requested: false,
                failure: None,
            },
            input: None,
            footprint: p.footprint.clone(),
            validation_capture: Some(w.capture_validation(p).unwrap()),
        };
        w.save(format!("operation:{id}"), &op).unwrap();
        id
    }
    fn case(w: &Workflow<'_>, label: &str, p: &StoredProposal, checked: &Checked) -> Value {
        let (selection, _, envelope) = w.get_assessment(&reference(p), None).unwrap();
        let mut bytes = serde_json::Map::new();
        if let Some(e) = &envelope {
            for source in &e.body.sources {
                let digest: String =
                    serde_json::from_value(serde_json::to_value(&source.blob_digest).unwrap())
                        .unwrap();
                bytes.insert(
                    source.key.clone(),
                    json!(w.load::<String>(&format!("source:{digest}")).unwrap()),
                );
            }
        }
        json!({"label":label,"proposal":p.proposal,"validation":checked.report,"selection":selection,"envelope":envelope,"source_bytes_utf8":bytes})
    }
    fn independent(name: &str, bindings: Vec<Value>) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("evidence.json");
        let evidence = json!({"bindings":bindings});
        std::fs::write(&path, serde_json::to_vec_pretty(&evidence).unwrap()).unwrap();
        let output = std::process::Command::new("python3")
            .arg(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../scripts/audit_validation_binding.py"
            ))
            .arg(&path)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        if let Ok(dir) = std::env::var("VALIDATION_BINDING_PROOF_DIR") {
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(
                std::path::Path::new(&dir).join(format!("service-{name}-bindings.json")),
                serde_json::to_vec_pretty(&evidence).unwrap(),
            )
            .unwrap();
            std::fs::write(
                std::path::Path::new(&dir).join(format!("service-{name}-independent.json")),
                output.stdout,
            )
            .unwrap();
        }
    }
    fn kernel(path: &std::path::Path) -> Kernel {
        Kernel::create(
            path,
            UniverseId::generate(&mut rand::rng()),
            "Binding proof",
            ContinuityId::generate(&mut rand::rng()),
            &PrincipalId::generate(&mut rand::rng()),
        )
        .unwrap()
    }
    #[test]
    fn synchronous_and_queued_exact_bindings_replacement_withdrawal_unresolved_and_restart() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("package.sqlite");
        let profile = ProfileId::generate(&mut rand::rng());
        let mut kernel = kernel(&path);
        let (p, mut b) = setup(&mut kernel, &profile);
        let mut w = workflow(&mut kernel, &profile);
        let r = reference(&p);
        let absent = synchronous(&mut w, &p);
        assert!(w.has_final(&absent, &p));
        w.approve(&r, &absent.validation.run_id).unwrap();
        let mut proofs = vec![case(&w, "absent", &p, &absent)];
        w.attach_assessment(&r, 0, b.clone(), "first").unwrap();
        assert!(!w.has_final(&absent, &p));
        assert!(w.approve(&r, &absent.validation.run_id).is_err());
        let first = synchronous(&mut w, &p);
        proofs.push(case(&w, "selected", &p, &first));
        assert!(!w.has_final(&first, &p)); // No assessment-aware publication integration.
        let id = queued(&mut w, &p, "queue");
        w.run_validation(&id).unwrap();
        let op = w.operation(&format!("operation:{id}")).unwrap();
        assert_eq!(op.status.state, OperationState::Succeeded);
        let checked: Checked = w
            .load(&format!(
                "validation:{}",
                op.status.validation.unwrap().run_id
            ))
            .unwrap();
        proofs.push(case(&w, "queued-selected", &p, &checked));
        b.assessor.assessed_at = "2026-10-03T00:00:01Z".into();
        w.attach_assessment(&r, 1, b.clone(), "replacement")
            .unwrap();
        let replacement = synchronous(&mut w, &p);
        proofs.push(case(&w, "replacement", &p, &replacement));
        assert_ne!(hash(&first.report), hash(&replacement.report));
        w.select_assessment(&r, 2, None, "withdrawal").unwrap();
        let withdrawn = synchronous(&mut w, &p);
        proofs.push(case(&w, "withdrawn", &p, &withdrawn));
        b.declared_inventory = serde_json::from_value(json!([{"item_id":"uncertain","source_key":"passage","range":{"start":0,"end":5},"material_kind":"description","statement":"Uncertain description","mapping_ids":[],"unresolved_ids":["u"]}])).unwrap();
        b.inventory_declaration.kind = InventoryKind::MaterialInventoryDeclared;
        b.unresolved = serde_json::from_value(json!([{"unresolved_id":"u","item_ids":["uncertain"],"reason":"unrepresented_material","detail":"Explicit unresolved material"}])).unwrap();
        b.conclusion = DeclaredConclusion::Unresolved;
        w.attach_assessment(&r, 3, b.clone(), "unresolved").unwrap();
        let unresolved = synchronous(&mut w, &p);
        proofs.push(case(&w, "unresolved", &p, &unresolved));
        // Accounting is reverified: an unresolved body cannot be relabeled clean.
        b.conclusion = DeclaredConclusion::ConsistentWithDeclaredInventory;
        assert!(w.attach_assessment(&r, 4, b, "false-clean").is_err());
        independent("selection", proofs);
        drop(w);
        drop(kernel);
        let mut kernel = Kernel::open(&path).unwrap();
        let w = workflow(&mut kernel, &profile);
        let recovered: Checked = w
            .load(&format!("validation:{}", checked.validation.run_id))
            .unwrap();
        assert_eq!(hash(&recovered.report), hash(&checked.report));
    }
    #[test]
    fn queued_selection_proposal_head_and_authority_changes_discard_final_bindings() {
        for mutation in [
            "replacement",
            "withdrawal",
            "proposal",
            "head",
            "authority",
            "cancel",
            "before-prepare",
        ] {
            let dir = tempfile::tempdir().unwrap();
            let profile = ProfileId::generate(&mut rand::rng());
            let mut kernel = kernel(&dir.path().join("package.sqlite"));
            let (p, mut b) = setup(&mut kernel, &profile);
            let mut w = workflow(&mut kernel, &profile);
            let r = reference(&p);
            w.attach_assessment(&r, 0, b.clone(), "first").unwrap();
            let id = queued(&mut w, &p, mutation);
            if mutation == "before-prepare" {
                w.select_assessment(&r, 1, None, "withdraw").unwrap();
                assert!(w.prepare_validation(&id).is_err());
                continue;
            }
            let task = w.prepare_validation(&id).unwrap().unwrap();
            match mutation {
                "replacement" => {
                    b.assessor.assessed_at = "2026-10-03T00:00:01Z".into();
                    w.attach_assessment(&r, 1, b, "second").unwrap();
                }
                "withdrawal" => {
                    w.select_assessment(&r, 1, None, "withdraw").unwrap();
                }
                "proposal" => {
                    freeze(
                        &mut w,
                        p.proposal.base_frame.clone(),
                        p.proposal.operations.clone(),
                        Some(&p),
                    );
                }
                "head" => {
                    w.kernel
                        .commit(&w.input(&p, "advance".into()).unwrap())
                        .unwrap();
                }
                "authority" => {
                    w.permissions = (false, true, true);
                }
                "cancel" => {
                    w.save(format!("cancel:{id}"), &json!({"cancelled":true}))
                        .unwrap();
                }
                _ => unreachable!(),
            }
            let result = task
                .evaluate(&std::sync::atomic::AtomicBool::new(false))
                .unwrap();
            let run = result.validation.run_id.clone();
            w.finish_validation(&id, Ok(result)).unwrap();
            assert!(
                w.kernel
                    .workflow_get(&format!("validation:{run}"))
                    .unwrap()
                    .is_none(),
                "{mutation}"
            );
            let op = w.operation(&format!("operation:{id}")).unwrap();
            assert!(
                matches!(
                    op.status.state,
                    OperationState::Failed | OperationState::Cancelled
                ),
                "{mutation}"
            );
        }
    }
    #[test]
    fn changed_dependencies_are_stale_record_only_and_retention_loss_never_bypasses_integrity() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("package.sqlite");
        let profile = ProfileId::generate(&mut rand::rng());
        let mut kernel = kernel(&path);
        let (initial, _) = setup(&mut kernel, &profile);
        let mut w = workflow(&mut kernel, &profile);
        let mut ops = initial.proposal.operations.clone();
        ops.push(serde_json::from_value(json!({"kind":"create_entity","client_ref":"dependency","record":{"names":[],"types":[],"worldAssociations":[],"labels":{"en":"Dependency"},"metadata":{}}})).unwrap());
        let p = freeze(
            &mut w,
            initial.proposal.base_frame.clone(),
            ops.clone(),
            Some(&initial),
        );
        let mut b = body(&p, &profile, "Exact café bytes.\n");
        let dep = p
            .changes
            .iter()
            .filter_map(|c| c.next.as_ref())
            .find(|r| matches!(r.payload, Payload::Entity(_)))
            .unwrap();
        b.dependencies.push(AssessmentVersionRef {
            universe: p.proposal.base_frame.universe.clone(),
            record: dep.identity.record_id.clone(),
            version: dep.record_version_id.clone(),
        });
        let selection = w
            .attach_assessment(&reference(&p), 0, b.clone(), "with-dependency")
            .unwrap();
        let fresh = synchronous(&mut w, &p);
        let mut proofs = vec![case(&w, "active-dependency", &p, &fresh)];
        let mut changed = serde_json::to_value(&ops).unwrap();
        changed[2]["record"]["labels"]["en"] = json!("Changed dependency");
        freeze(
            &mut w,
            p.proposal.base_frame.clone(),
            serde_json::from_value(changed).unwrap(),
            Some(&p),
        );
        let stale = synchronous(&mut w, &p);
        let result = serde_json::to_value(&stale.report).unwrap();
        assert_eq!(result["assessment"]["kind"], "stale");
        assert!(result["assessment"]["reasons"]
            .as_array()
            .unwrap()
            .contains(&json!("dependency_changed")));
        assert_eq!(result["submitted_input"]["kind"], "record_candidate");
        proofs.push(case(&w, "changed-dependency", &p, &stale));
        assert!(w.approve(&reference(&p), &stale.validation.run_id).is_err());
        drop(w);
        drop(kernel);
        // Explicit corruption of an owned disposable package, never production.
        let db = rusqlite::Connection::open(&path).unwrap();
        db.execute_batch("DROP TRIGGER workflow_entries_no_delete")
            .unwrap();
        let assessment_id =
            serde_json::to_value(selection.selected.unwrap().assessment_id).unwrap();
        db.execute(
            "DELETE FROM workflow_entries WHERE key=?1",
            [format!("assessment:{}", assessment_id.as_str().unwrap())],
        )
        .unwrap();
        drop(db);
        let mut kernel = Kernel::open(&path).unwrap();
        let mut w = workflow(&mut kernel, &profile);
        let unavailable = synchronous(&mut w, &p);
        let result = serde_json::to_value(&unavailable.report).unwrap();
        assert_eq!(result["assessment"]["kind"], "unavailable");
        assert_eq!(result["submitted_input"]["kind"], "record_candidate");
        proofs.push(case(&w, "missing-assessment-record-only", &p, &unavailable));
        independent("dependency-retention", proofs);
        let blob = serde_json::to_value(&b.sources[0].blob_digest).unwrap();
        drop(w);
        drop(kernel);
        let db = rusqlite::Connection::open(&path).unwrap();
        db.execute(
            "DELETE FROM workflow_entries WHERE key=?1",
            [format!("source:{}", blob.as_str().unwrap())],
        )
        .unwrap();
        drop(db);
        let mut kernel = Kernel::open(&path).unwrap();
        let mut w = workflow(&mut kernel, &profile);
        assert!(w.capture_validation(&p).is_ok()); // Missing body permits only record scope.
        assert!(w.check(&p).is_err()); // Source integrity still blocks completed evidence.
    }
}
