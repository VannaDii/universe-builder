//! Internal assessment persistence. No public route or validation authority.
// These methods are staged for the subsequent public/native routing goal.
#![allow(dead_code)]
use super::*;
use universe_protocol::assessment::*;

#[derive(Clone, Serialize, Deserialize)]
struct AssessmentReceipt {
    request_digest: String,
    selection: AssessmentSelection,
    envelope: Option<AssessmentEnvelope>,
}
fn selection_prefix(r: &ProposalRef) -> String {
    format!("assessment-selection:{}:{:020}:", r.proposal_id, r.version)
}
fn envelope_key(r: &AssessmentRef) -> String {
    format!(
        "assessment:{}",
        serde_json::to_value(&r.assessment_id)
            .unwrap()
            .as_str()
            .unwrap()
    )
}
fn invalid_assessment(message: impl Into<String>) -> anyhow::Error {
    ProtocolError::invalid_argument("assessment", message.into()).into()
}
impl Workflow<'_> {
    fn assessment_candidate(&self, p: &StoredProposal) -> anyhow::Result<Vec<RecordVersion>> {
        let mut records = self.kernel.records(
            &p.proposal.base_frame.continuity,
            &p.proposal.base_frame.revision,
        )?;
        for change in &p.changes {
            records.retain(|r| r.identity.record_id != change.record_id);
            records.extend(change.next.clone());
        }
        Ok(records)
    }
    fn assessment_access(
        &self,
        p: &StoredProposal,
        body: Option<&SourceAssessmentV1>,
    ) -> anyhow::Result<Vec<RecordVersion>> {
        self.write_boundaries(p).map_err(|_| denied())?;
        let mut records = self.assessment_candidate(p)?;
        // Include historical evidence in the same dependency visibility walk.
        if let Some(body) = body {
            for dep in &body.dependencies {
                if !records.iter().any(|r| r.record_version_id == dep.version) {
                    if let Ok(r) = self.kernel.record_version(&dep.version) {
                        records.push(r);
                    }
                }
            }
        }
        let visible = self.visible_ids(&records)?;
        if records
            .iter()
            .any(|r| !visible.contains(&r.identity.record_id))
        {
            return Err(denied());
        }
        // Entity/predicate limits must cover unchanged dependencies too.
        let mut full = p.clone();
        full.changes = records
            .iter()
            .map(|r| Assignment {
                record_id: r.identity.record_id.clone(),
                expected: None,
                next: Some(r.clone()),
            })
            .collect();
        self.write_boundaries(&full).map_err(|_| denied())?;
        Ok(records)
    }
    fn assessment_latest(&self, p: &Proposal) -> anyhow::Result<bool> {
        Ok(self
            .kernel
            .workflow_latest_key(&format!("proposal:{}:", p.proposal_id))?
            == Some(format!("proposal:{}:{:020}", p.proposal_id, p.version)))
    }
    fn assessment_stale_reasons(
        &self,
        p: &StoredProposal,
        body: &SourceAssessmentV1,
    ) -> anyhow::Result<Vec<StaleReason>> {
        let latest: StoredProposal = self.load(
            &self
                .kernel
                .workflow_latest_key(&format!("proposal:{}:", p.proposal.proposal_id))?
                .ok_or_else(denied)?,
        )?;
        if latest.proposal.digest == p.proposal.digest
            && !latest.proposal.withdrawn
            && self.kernel.head(&p.proposal.base_frame.continuity)?
                == p.proposal.base_frame.revision
        {
            return Ok(vec![]);
        }
        let records = if self.kernel.head(&latest.proposal.base_frame.continuity)?
            == latest.proposal.base_frame.revision
        {
            self.assessment_candidate(&latest)?
        } else {
            self.kernel.records(
                &latest.proposal.base_frame.continuity,
                &self.kernel.head(&latest.proposal.base_frame.continuity)?,
            )?
        };
        let active = |reference: &AssessmentVersionRef| {
            records.iter().any(|r| {
                r.identity.record_id == reference.record && r.record_version_id == reference.version
            })
        };
        let mut reasons = vec![StaleReason::CandidateChanged];
        if body.sources.iter().any(|s| !active(&s.source_version)) {
            reasons.push(StaleReason::SourceChanged);
        }
        if body
            .sources
            .iter()
            .any(|s| s.work_edition.as_ref().is_some_and(|r| !active(r)))
        {
            reasons.push(StaleReason::EditionChanged);
        }
        if body.dependencies.iter().any(|dep| {
            !active(dep)
                && !body
                    .claim_mappings
                    .iter()
                    .flat_map(|m| &m.candidate_links)
                    .any(|l| {
                        matches!(l.kind, CandidateLinkKind::HistoricalEvidence)
                            && hash(&l.version) == hash(dep)
                    })
        }) {
            reasons.push(StaleReason::DependencyChanged);
        }
        Ok(reasons)
    }
    fn assessment_writable(&self, p: &StoredProposal) -> anyhow::Result<()> {
        self.authorize(&p.footprint, false).map_err(|_| denied())?;
        if !self.assessment_latest(&p.proposal)?
            || p.proposal.withdrawn
            || !matches!(p.proposal.submission, Submission::Submitted)
            || self.kernel.head(&p.proposal.base_frame.continuity)?
                != p.proposal.base_frame.revision
        {
            return Err(ProtocolError::ApprovalStale.into());
        }
        Ok(())
    }
    fn assessment_selection_raw(&self, r: &ProposalRef) -> anyhow::Result<AssessmentSelection> {
        match self.kernel.workflow_latest_key(&selection_prefix(r))? {
            Some(key) => self.load(&key),
            None => Ok(AssessmentSelection {
                proposal: r.clone(),
                generation: 0,
                selected: None,
            }),
        }
    }
    fn assessment_envelope_raw(&self, r: &AssessmentRef) -> anyhow::Result<AssessmentEnvelope> {
        let envelope: AssessmentEnvelope = self.load(&envelope_key(r))?;
        envelope.verify().map_err(invalid_assessment)?;
        if hash(&envelope.digest) != hash(&r.digest) {
            return Err(denied());
        }
        Ok(envelope)
    }
    /// Resolve active dependencies exactly; only explicit historical evidence may
    /// use retained versions. Verify staged metadata, anchors and actual bytes.
    fn verify_assessment(
        &self,
        p: &StoredProposal,
        body: &SourceAssessmentV1,
    ) -> anyhow::Result<()> {
        let reference = ProposalRef {
            proposal_id: p.proposal.proposal_id.clone(),
            version: p.proposal.version,
            digest: p.proposal.digest.clone(),
        };
        body.bind_frozen_proposal(&reference, &p.proposal.base_frame)
            .map_err(invalid_assessment)?;
        let candidate = self.assessment_candidate(p)?;
        let mut records = candidate.clone();
        for dep in &body.dependencies {
            if dep.universe != *self.kernel.universe() {
                return Err(invalid_assessment("cross-universe dependency"));
            }
            let active = candidate
                .iter()
                .find(|r| r.identity.record_id == dep.record && r.record_version_id == dep.version);
            let historical = body
                .claim_mappings
                .iter()
                .flat_map(|m| &m.candidate_links)
                .any(|l| {
                    matches!(l.kind, CandidateLinkKind::HistoricalEvidence)
                        && hash(&l.version) == hash(dep)
                });
            let r = match active {
                Some(r) => r.clone(),
                None if historical => self
                    .kernel
                    .record_version(&dep.version)
                    .map_err(|_| invalid_assessment("missing historical version"))?,
                None => {
                    return Err(invalid_assessment(
                        "dependency is not active in frozen candidate",
                    ));
                }
            };
            if r.identity.record_id != dep.record {
                return Err(invalid_assessment("record/version mismatch"));
            }
            if !records
                .iter()
                .any(|v| v.record_version_id == r.record_version_id)
            {
                records.push(r);
            }
        }
        // Historical evidence labels cannot make semantic prerequisites historical.
        fn active_references(value: &Value, candidate: &[RecordVersion]) -> anyhow::Result<()> {
            match value {
                Value::Object(fields) => {
                    if fields.contains_key("record") && fields.contains_key("version") {
                        let reference: AssessmentVersionRef =
                            serde_json::from_value(value.clone())?;
                        if !candidate.iter().any(|r| {
                            r.identity.record_id == reference.record
                                && r.record_version_id == reference.version
                        }) {
                            return Err(invalid_assessment(
                                "semantic reference is not active in frozen candidate",
                            ));
                        }
                    }
                    for value in fields.values() {
                        active_references(value, candidate)?;
                    }
                }
                Value::Array(values) => {
                    for value in values {
                        active_references(value, candidate)?;
                    }
                }
                _ => {}
            }
            Ok(())
        }
        for mapping in &body.claim_mappings {
            let mut semantics = serde_json::to_value(mapping)?;
            semantics.as_object_mut().unwrap().remove("candidate_links");
            active_references(&semantics, &candidate)?;
            for link in &mapping.candidate_links {
                if matches!(link.kind, CandidateLinkKind::HistoricalEvidence) {
                    let retained =
                        self.kernel
                            .record_version(&link.version.version)
                            .map_err(|_| {
                                invalid_assessment("historical evidence must be a retained version")
                            })?;
                    if retained.identity.record_id != link.version.record {
                        return Err(invalid_assessment("historical record/version mismatch"));
                    }
                }
                let changed = p.changes.iter().any(|c| {
                    c.next
                        .as_ref()
                        .is_some_and(|r| r.record_version_id == link.version.version)
                });
                let active = candidate.iter().any(|r| {
                    r.identity.record_id == link.version.record
                        && r.record_version_id == link.version.version
                });
                if matches!(link.kind, CandidateLinkKind::ProposedRecord) && (!changed || !active)
                    || matches!(link.kind, CandidateLinkKind::UnchangedRecord)
                        && (changed || !active)
                {
                    return Err(invalid_assessment("candidate link kind mismatch"));
                }
            }
        }
        for source in &body.sources {
            let r = candidate
                .iter()
                .find(|r| {
                    r.identity.record_id == source.source_version.record
                        && r.record_version_id == source.source_version.version
                })
                .ok_or_else(|| {
                    invalid_assessment("source version is not active in frozen candidate")
                })?;
            let Payload::SourceVersion(v) = &r.payload else {
                return Err(invalid_assessment(
                    "source reference is not a source version",
                ));
            };
            if serde_json::to_value(&source.blob_digest)? != json!(v.digest)
                || source.byte_size != v.byte_size
            {
                return Err(invalid_assessment("source metadata mismatch"));
            }
            if let Some(edition) = &source.work_edition {
                if !candidate.iter().any(|r| {
                    r.identity.record_id == edition.record
                        && r.record_version_id == edition.version
                        && matches!(r.payload, Payload::WorkVersion(_))
                }) {
                    return Err(invalid_assessment(
                        "edition version is not active in frozen candidate",
                    ));
                }
                if let Some(passage) = &source.passage_id {
                    let valid = candidate.iter().any(|r| match &r.payload {
                        Payload::PassageRef(passage_ref) if &passage_ref.passage_id == passage && passage_ref.work_version.record == edition.record && passage_ref.work_version.version == edition.version => {
                            passage_ref.anchor.as_ref().is_some_and(|a| candidate.iter().any(|r| r.identity.record_id == a.record && matches!(&r.payload, Payload::Anchor(anchor) if anchor.source_version.record == source.source_version.record && anchor.source_version.version == source.source_version.version && matches!(anchor.locator, AnchorLocator::ByteRange {start, end} if source.ranges.iter().any(|range| range.start <= start && end <= range.end)))))
                        }, _ => false,
                    });
                    if !valid {
                        return Err(invalid_assessment("passage/edition/source anchor mismatch"));
                    }
                }
            }
        }
        for dep in &body.dependencies {
            if let Some(RecordVersion {
                payload: Payload::Anchor(anchor),
                ..
            }) = records.iter().find(|r| r.record_version_id == dep.version)
            {
                let valid = body.sources.iter().any(|source| {
                    anchor.source_version.universe.as_ref() == Some(&source.source_version.universe)
                        && anchor.source_version.record == source.source_version.record
                        && anchor.source_version.version == source.source_version.version
                        && matches!(anchor.locator, AnchorLocator::ByteRange { start, end } if source.ranges.iter().any(|r| r.start <= start && end <= r.end))
                });
                if !valid {
                    return Err(invalid_assessment(
                        "anchor is outside declared source binding",
                    ));
                }
            }
        }
        self.verify_sources(&records)?;
        body.verify_source_bytes(|source| {
            body.sources
                .iter()
                .find(|s| hash(&s.source_version) == hash(source))
                .and_then(|s| {
                    let digest: String =
                        serde_json::from_value(serde_json::to_value(&s.blob_digest).ok()?).ok()?;
                    self.load::<String>(&format!("source:{digest}"))
                        .ok()
                        .map(String::into_bytes)
                })
        })
        .map_err(invalid_assessment)?;
        Ok(())
    }
    pub(crate) fn attach_assessment(
        &mut self,
        r: &ProposalRef,
        expected: u64,
        body: SourceAssessmentV1,
        key: &str,
    ) -> anyhow::Result<AssessmentSelection> {
        self.change_assessment(r, expected, Some(body), None, key)
    }
    pub(crate) fn select_assessment(
        &mut self,
        r: &ProposalRef,
        expected: u64,
        selected: Option<AssessmentRef>,
        key: &str,
    ) -> anyhow::Result<AssessmentSelection> {
        self.change_assessment(r, expected, None, selected, key)
    }
    fn change_assessment(
        &mut self,
        r: &ProposalRef,
        expected: u64,
        body: Option<SourceAssessmentV1>,
        selected: Option<AssessmentRef>,
        key: &str,
    ) -> anyhow::Result<AssessmentSelection> {
        let authority = self.authority.clone();
        let _guard = authority.as_ref().map(|a| a.lock()).transpose()?;
        let p = self.proposal(r).map_err(|_| denied())?;
        self.authorize(&p.footprint, false).map_err(|_| denied())?;
        self.assessment_access(&p, body.as_ref())?;
        if key.is_empty() || key.len() > 16384 {
            return Err(invalid_assessment("invalid idempotency key"));
        }
        if let Some(body) = &body {
            let principal = self.principal.id.as_str().replacen("prf_", "prn_", 1);
            if body.assessor.principal.as_str() != principal {
                return Err(denied());
            }
            self.verify_assessment(&p, body)?;
        }
        let request_digest = hash(&(r, expected, &body, &selected));
        let receipt_key = format!("assessment-receipt:{}:{}", self.principal.id, hash(&key));
        if let Some(value) = self.kernel.workflow_get(&receipt_key)? {
            let receipt: AssessmentReceipt = serde_json::from_value(value)?;
            if let Some(envelope) = &receipt.envelope {
                self.assessment_access(&p, Some(&envelope.body))?;
            }
            if receipt.request_digest != request_digest {
                return Err(ProtocolError::IdempotencyKeyReused {
                    message: "request differs".into(),
                }
                .into());
            }
            return Ok(receipt.selection);
        }
        self.assessment_writable(&p)?;
        let current = self.assessment_selection_raw(r)?;
        if current.generation != expected {
            return Err(ProtocolError::ApprovalStale.into());
        }
        let envelope = if let Some(body) = body {
            let assessment_id: AssessmentId = serde_json::from_value(json!(format!(
                "asm_{}",
                hex::encode(rand::random::<[u8; 12]>())
            )))?;
            Some(AssessmentEnvelope {
                assessment_id,
                digest: body.digest().map_err(invalid_assessment)?,
                body,
            })
        } else if let Some(reference) = &selected {
            let envelope = self.assessment_envelope_raw(reference)?;
            self.assessment_access(&p, Some(&envelope.body))?;
            self.verify_assessment(&p, &envelope.body)?;
            Some(envelope)
        } else {
            None
        };
        let selected = envelope.as_ref().map(|e| AssessmentRef {
            assessment_id: e.assessment_id.clone(),
            digest: e.digest.clone(),
        });
        if hash(&selected) == hash(&current.selected) {
            return Err(invalid_assessment("selection is unchanged"));
        }
        let generation = expected
            .checked_add(1)
            .ok_or_else(|| invalid_assessment("selection generation exhausted"))?;
        let selection = AssessmentSelection {
            proposal: r.clone(),
            generation,
            selected,
        };
        let prefix = selection_prefix(r);
        let mut entries = vec![
            (
                format!("{prefix}{generation:020}"),
                serde_json::to_value(&selection)?,
            ),
            (
                receipt_key,
                serde_json::to_value(AssessmentReceipt {
                    request_digest,
                    selection: selection.clone(),
                    envelope: envelope.clone(),
                })?,
            ),
        ];
        if let Some(e) = envelope {
            entries.push((
                envelope_key(selection.selected.as_ref().unwrap()),
                serde_json::to_value(e)?,
            ));
        }
        self.kernel.workflow_compare_append(
            &[
                (
                    prefix.clone(),
                    (expected > 0).then(|| format!("{prefix}{expected:020}")),
                ),
                (
                    format!("proposal:{}:", r.proposal_id),
                    Some(format!("proposal:{}:{:020}", r.proposal_id, r.version)),
                ),
            ],
            &entries,
        )?;
        Ok(selection)
    }
    /// Current usability is recomputed; exact historical envelopes never change.
    pub(crate) fn get_assessment(
        &self,
        r: &ProposalRef,
        exact: Option<&AssessmentRef>,
    ) -> anyhow::Result<(
        AssessmentSelection,
        AssessmentState,
        Option<AssessmentEnvelope>,
    )> {
        let authority = self.authority.clone();
        let _guard = authority.as_ref().map(|a| a.lock()).transpose()?;
        let p = self.proposal(r).map_err(|_| denied())?;
        self.assessment_access(&p, None)?;
        let selection = self.assessment_selection_raw(r)?;
        if let Some(reference) = &selection.selected {
            if self
                .kernel
                .workflow_get(&envelope_key(reference))?
                .is_none()
            {
                // Without its body, dependency scope cannot be established for
                // a partial viewer. Only the unrestricted author can read loss.
                if !self.principal.author || self.scope.is_some() {
                    return Err(denied());
                }
                if exact.is_some_and(|requested| hash(requested) != hash(reference)) {
                    return Err(denied());
                }
                return Ok((
                    selection,
                    AssessmentState::Unavailable {
                        reason: UnavailableReason::MissingRetainedMaterial,
                    },
                    None,
                ));
            }
        }
        let envelope = match exact.or(selection.selected.as_ref()) {
            Some(reference) => {
                let e = self.assessment_envelope_raw(reference)?;
                if e.body.proposal != *r {
                    return Err(denied());
                }
                self.assessment_access(&p, Some(&e.body))?;
                Some(e)
            }
            None => None,
        };
        let state = match &selection.selected {
            None => AssessmentState::Absent {},
            Some(reference) => {
                let e = self.assessment_envelope_raw(reference)?;
                self.assessment_access(&p, Some(&e.body))?;
                let reasons = self.assessment_stale_reasons(&p, &e.body)?;
                if !reasons.is_empty() {
                    AssessmentState::Stale {
                        assessment_reference: reference.clone(),
                        reasons,
                    }
                } else {
                    if e.body.sources.iter().any(|s| {
                        let digest: String =
                            serde_json::from_value(serde_json::to_value(&s.blob_digest).unwrap())
                                .unwrap();
                        self.kernel
                            .workflow_get(&format!("source:{digest}"))
                            .is_ok_and(|v| v.is_none())
                    }) {
                        return Ok((
                            selection,
                            AssessmentState::Unavailable {
                                reason: UnavailableReason::MissingRetainedMaterial,
                            },
                            envelope,
                        ));
                    }
                    self.verify_assessment(&p, &e.body)?;
                    AssessmentState::Bound {
                        assessment_reference: reference.clone(),
                        selection_generation: selection.generation,
                        byte_verification: ByteVerification::Verified,
                        declared_conclusion: e.body.conclusion.clone(),
                        inventory_count: e.body.declared_inventory.len() as u64,
                        mapping_count: e.body.claim_mappings.len() as u64,
                        unresolved_count: e.body.unresolved.len() as u64,
                        inventory_digest: e.body.inventory_digest().map_err(invalid_assessment)?,
                    }
                }
            }
        };
        Ok((selection, state, envelope))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    fn workflow<'a>(kernel: &'a mut Kernel, profile: &ProfileId) -> Workflow<'a> {
        Workflow {
            kernel,
            authority: None,
            principal: Principal {
                id: profile.clone(),
                author: true,
            },
            approval_author: profile.clone(),
            scope: None,
            permissions: (true, true, true),
            name: "Assessment proofs".into(),
        }
    }
    fn reference(p: &StoredProposal) -> ProposalRef {
        ProposalRef {
            proposal_id: p.proposal.proposal_id.clone(),
            version: p.proposal.version,
            digest: p.proposal.digest.clone(),
        }
    }
    fn freeze(
        w: &mut Workflow<'_>,
        frame: Frame,
        ops: Vec<DomainOperation>,
        previous: Option<&StoredProposal>,
    ) -> StoredProposal {
        let changes = operations::compile(w.kernel.universe(), &[], &ops).unwrap();
        let footprint = operations::footprint(&[], &changes);
        let mut p = StoredProposal {
            owner: w.principal.id.clone(),
            author_origin: true,
            changes,
            footprint,
            proposal: Proposal {
                base_frame: frame,
                world_scope: None,
                proposal_id: previous
                    .map(|p| p.proposal.proposal_id.clone())
                    .unwrap_or_else(|| ProposalId::generate(&mut rand::rng())),
                version: previous.map_or(1, |p| p.proposal.version + 1),
                digest: String::new(),
                submission: Submission::Submitted,
                operations: ops,
                compiled_changes: vec![],
                rationale: "Synthetic storage proof".into(),
                canonical: false,
                operation_id: OperationId::generate(&mut rand::rng()),
                withdrawn: false,
            },
        };
        p.proposal.digest = hash(&(&p.proposal, &p.changes, &p.footprint));
        w.kernel
            .preview(&w.input(&p, "proof-preview".into()).unwrap())
            .unwrap();
        w.save(
            format!(
                "proposal:{}:{:020}",
                p.proposal.proposal_id, p.proposal.version
            ),
            &p,
        )
        .unwrap();
        p
    }
    fn body(p: &StoredProposal, profile: &ProfileId, text: &str) -> SourceAssessmentV1 {
        let source = p
            .changes
            .iter()
            .filter_map(|c| c.next.as_ref())
            .find(|r| matches!(r.payload, Payload::SourceVersion(_)))
            .unwrap();
        serde_json::from_value(json!({
            "kind":"source_assessment_v1","proposal":reference(p),"base_frame":p.proposal.base_frame,
            "assessor":{"principal":profile.as_str().replacen("prf_","prn_",1),"method":"human_review","tool":null,"assessed_at":"2026-10-03T00:00:00Z"},
            "sources":[{"key":"passage","source_version":{"universe":p.proposal.base_frame.universe,"record":source.identity.record_id,"version":source.record_version_id},"blob_digest":hex::encode(Sha256::digest(text.as_bytes())),"byte_size":text.len(),"representation":"exact-utf8-v1","ranges":[{"start":0,"end":text.len()}],"work_edition":null,"passage_id":null}],
            "dependencies":[],"declared_inventory":[],"inventory_declaration":{"kind":"no_material_claims","exclusions":[],"rationale":"Synthetic source without declared material"},"claim_mappings":[],"unresolved":[],"conclusion":"consistent_with_declared_inventory"
        })).unwrap()
    }
    fn snapshot(w: &Workflow<'_>) -> Vec<(String, Value)> {
        w.kernel
            .workflow_keys("")
            .unwrap()
            .into_iter()
            .map(|k| {
                let v = w.kernel.workflow_get(&k).unwrap().unwrap();
                (k, v)
            })
            .collect()
    }
    fn audit(path: &Path, phase: &str, expected: &Value) {
        let output = std::process::Command::new("python3")
            .arg(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../scripts/audit_assessment_storage.py"
            ))
            .arg(path)
            .arg(phase)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let report: Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(&report["rows"], expected);
        if let Ok(dir) = std::env::var("ASSESSMENT_PROOF_DIR") {
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(Path::new(&dir).join(format!("{phase}.json")), output.stdout).unwrap();
        }
    }
    #[test]
    fn durable_bindings_atomic_retries_access_replacement_and_restart() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("assessments.sqlite");
        let u = UniverseId::generate(&mut rand::rng());
        let cont = ContinuityId::generate(&mut rand::rng());
        let profile = ProfileId::generate(&mut rand::rng());
        let principal = PrincipalId::parse(&profile.as_str().replacen("prf_", "prn_", 1)).unwrap();
        let mut kernel = Kernel::create(
            &path,
            u.clone(),
            "Assessment proofs",
            cont.clone(),
            &principal,
        )
        .unwrap();
        let frame = Frame {
            universe: u.clone(),
            continuity: cont.clone(),
            revision: kernel.head(&cont).unwrap(),
            context: RecordRef::new(u, RecordId::generate(&mut rand::rng())),
            time: FrameTime::Timeless,
            perspective: Perspective::Author,
            reader_scene: None,
            personal_sequence: None,
        };
        let mut w = workflow(&mut kernel, &profile);
        let text = "Exact café bytes.\n";
        let staged = w.stage_source("Proof source".into(), text.into()).unwrap();
        let ops: Vec<DomainOperation> =
            serde_json::from_value(staged["operations"].clone()).unwrap();
        let p = freeze(&mut w, frame.clone(), ops.clone(), None);
        let r = reference(&p);
        let b = body(&p, &profile, text);
        assert!(matches!(
            w.get_assessment(&r, None).unwrap().1,
            AssessmentState::Absent {}
        ));
        let s1 = w.attach_assessment(&r, 0, b.clone(), "attach-a").unwrap();
        let original = w.get_assessment(&r, None).unwrap().2.unwrap();
        assert_eq!(
            hash(&s1),
            hash(&w.attach_assessment(&r, 0, b.clone(), "attach-a").unwrap())
        );
        let before = snapshot(&w);
        let mut bad = b.clone();
        bad.proposal.digest = "a".repeat(64);
        assert!(w.attach_assessment(&r, 1, bad, "bad-candidate").is_err());
        let mut bad = b.clone();
        bad.base_frame.time = FrameTime::AtEvent {
            event: frame.context.clone(),
            side: EventTimeSide::After,
        };
        assert!(w.attach_assessment(&r, 1, bad, "bad-frame").is_err());
        let mut bad = b.clone();
        bad.sources[0].source_version.version = RecordVersionId::generate(&mut rand::rng());
        assert!(w.attach_assessment(&r, 1, bad, "bad-version").is_err());
        let mut bad = b.clone();
        bad.sources[0].source_version.record = RecordId::generate(&mut rand::rng());
        assert!(w.attach_assessment(&r, 1, bad, "bad-record").is_err());
        let mut bad = b.clone();
        bad.sources[0].blob_digest = Sha256Hex::parse("0".repeat(64)).unwrap();
        assert!(w.attach_assessment(&r, 1, bad, "bad-bytes").is_err());
        let mut bad = b.clone();
        bad.sources[0].ranges[0].end = 10; // splits é
        assert!(w.attach_assessment(&r, 1, bad, "bad-utf8").is_err());
        let mut bad = b.clone();
        bad.assessor.principal = PrincipalId::generate(&mut rand::rng());
        assert!(w.attach_assessment(&r, 1, bad, "impersonate").is_err());
        assert!(
            w.attach_assessment(&r, 0, b.clone(), "stale-generation")
                .is_err()
        );
        let mut changed = b.clone();
        changed.assessor.assessed_at = "2026-10-03T00:00:01Z".into();
        assert!(w.attach_assessment(&r, 1, changed, "attach-a").is_err());
        assert!(
            w.select_assessment(&r, 1, s1.selected.clone(), "no-change")
                .is_err()
        );
        let mut wrong = s1.selected.clone().unwrap();
        wrong.digest = Sha256Hex::parse("f".repeat(64)).unwrap();
        assert!(
            w.select_assessment(&r, 1, Some(wrong), "wrong-digest")
                .is_err()
        );
        w.permissions.0 = false;
        assert!(w.attach_assessment(&r, 0, b.clone(), "attach-a").is_err());
        assert!(
            w.attach_assessment(&r, 1, b.clone(), "no-permission")
                .is_err()
        );
        w.permissions.0 = true;
        w.principal = Principal {
            id: ProfileId::generate(&mut rand::rng()),
            author: false,
        };
        let access_error = w.get_assessment(&r, None).unwrap_err().to_string();
        let mut unknown = r.clone();
        unknown.proposal_id = ProposalId::generate(&mut rand::rng());
        assert_eq!(
            access_error,
            w.get_assessment(&unknown, None).unwrap_err().to_string()
        );
        assert!(
            w.attach_assessment(&r, 1, b.clone(), "wrong-owner")
                .is_err()
        );
        w.principal = Principal {
            id: profile.clone(),
            author: true,
        };
        w.scope = Some(BTreeSet::new());
        assert!(w.get_assessment(&r, None).is_err());
        w.scope = None;
        assert_eq!(snapshot(&w), before);
        // A changed second entry must roll back the first inserted entry.
        assert!(
            w.kernel
                .workflow_compare_append(
                    &[],
                    &[
                        ("assessment:rollback".into(), json!("must not survive")),
                        (
                            envelope_key(s1.selected.as_ref().unwrap()),
                            json!("collision")
                        )
                    ]
                )
                .is_err()
        );
        assert_eq!(snapshot(&w), before);
        let prefix = selection_prefix(&r);
        assert!(
            w.kernel
                .workflow_compare_append(
                    &[(prefix, None)],
                    &[("assessment:cas-failed".into(), json!(1))]
                )
                .is_err()
        );
        assert_eq!(snapshot(&w), before);
        // Unresolved is applicable, never absent or a positive declaration.
        let mut unresolved = serde_json::to_value(&b).unwrap();
        unresolved["declared_inventory"] = json!([{"item_id":"i1","source_key":"passage","range":{"start":0,"end":5},"material_kind":"description","statement":"Undetermined meaning","mapping_ids":[],"unresolved_ids":["u1"]}]);
        unresolved["inventory_declaration"]["kind"] = json!("material_inventory_declared");
        unresolved["unresolved"] = json!([{"unresolved_id":"u1","item_ids":["i1"],"reason":"interpretation_disagreement","detail":"Review pending"}]);
        unresolved["conclusion"] = json!("unresolved");
        let ub: SourceAssessmentV1 = serde_json::from_value(unresolved).unwrap();
        let s2 = w.attach_assessment(&r, 1, ub, "attach-unresolved").unwrap();
        assert!(matches!(
            w.get_assessment(&r, None).unwrap().1,
            AssessmentState::Bound {
                declared_conclusion: DeclaredConclusion::Unresolved,
                unresolved_count: 1,
                ..
            }
        ));
        assert_eq!(
            hash(
                &w.get_assessment(&r, s1.selected.as_ref())
                    .unwrap()
                    .2
                    .unwrap()
            ),
            hash(&original)
        );
        let s3 = w.select_assessment(&r, 2, None, "clear").unwrap();
        assert_eq!(s3.generation, 3);
        assert!(matches!(
            w.get_assessment(&r, None).unwrap().1,
            AssessmentState::Absent {}
        ));
        w.select_assessment(&r, 3, s2.selected.clone(), "reselect")
            .unwrap();
        // Source revision and proposal replacement keep historical envelopes exact.
        let stage2 = w
            .stage_source("Revised source".into(), "Revised bytes.\n".into())
            .unwrap();
        let ops2 = serde_json::from_value(stage2["operations"].clone()).unwrap();
        let p2 = freeze(&mut w, frame, ops2, Some(&p));
        let r2 = reference(&p2);
        assert!(matches!(
            w.get_assessment(&r, None).unwrap().1,
            AssessmentState::Stale { .. }
        ));
        assert!(matches!(
            w.get_assessment(&r2, None).unwrap().1,
            AssessmentState::Absent {}
        ));
        assert!(
            matches!(w.get_assessment(&r,None).unwrap().1, AssessmentState::Stale { reasons, .. } if reasons.iter().any(|r| matches!(r,StaleReason::SourceChanged)))
        );
        let stable = snapshot(&w);
        assert!(w.attach_assessment(&r, 4, b.clone(), "replaced").is_err());
        assert!(
            w.select_assessment(&r2, 0, s1.selected.clone(), "cross-proposal")
                .is_err()
        );
        assert_eq!(snapshot(&w), stable);
        let b2 = body(&p2, &profile, "Revised bytes.\n");
        w.attach_assessment(&r2, 0, b2, "source-revision").unwrap();
        let expected = json!(snapshot(&w));
        audit(&path, "before-restart", &expected);
        drop(w);
        drop(kernel);
        let mut kernel = Kernel::open(&path).unwrap();
        let mut w = workflow(&mut kernel, &profile);
        assert_eq!(json!(snapshot(&w)), expected);
        assert_eq!(
            hash(
                &w.get_assessment(&r, s1.selected.as_ref())
                    .unwrap()
                    .2
                    .unwrap()
            ),
            hash(&original)
        );
        assert!(matches!(
            w.get_assessment(&r, None).unwrap().1,
            AssessmentState::Stale { .. }
        ));
        assert!(matches!(
            w.get_assessment(&r2, None).unwrap().1,
            AssessmentState::Bound { .. }
        ));
        assert_eq!(
            hash(&s1),
            hash(&w.attach_assessment(&r, 0, b, "attach-a").unwrap())
        );
        audit(&path, "after-restart", &expected);
    }
    #[test]
    fn exact_anchor_dependency_and_missing_material_admission() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("anchors.sqlite");
        let profile = ProfileId::generate(&mut rand::rng());
        let principal = PrincipalId::parse(&profile.as_str().replacen("prf_", "prn_", 1)).unwrap();
        let u = UniverseId::generate(&mut rand::rng());
        let cont = ContinuityId::generate(&mut rand::rng());
        let mut kernel =
            Kernel::create(&path, u.clone(), "Anchors", cont.clone(), &principal).unwrap();
        let frame = Frame {
            universe: u.clone(),
            continuity: cont.clone(),
            revision: kernel.head(&cont).unwrap(),
            context: RecordRef::new(u.clone(), RecordId::generate(&mut rand::rng())),
            time: FrameTime::Timeless,
            perspective: Perspective::Author,
            reader_scene: None,
            personal_sequence: None,
        };
        let mut w = workflow(&mut kernel, &profile);
        let text = "Exact café bytes.\n";
        let staged = w.stage_source("Anchor source".into(), text.into()).unwrap();
        let ops = serde_json::from_value(staged["operations"].clone()).unwrap();
        let p = freeze(&mut w, frame, ops, None);
        // Preserve the compiled source identity/version while adding an exact anchor.
        let source = body(&p, &profile, text).sources[0].source_version.clone();
        let anchor_id = RecordId::generate(&mut rand::rng());
        let anchor = Anchor {
            source_version: universe_domain::value::VersionRef {
                universe: Some(u.clone()),
                record: source.record.clone(),
                version: source.version.clone(),
            },
            locator: AnchorLocator::ByteRange { start: 0, end: 5 },
            excerpt: "Exact".into(),
            excerpt_digest: hex::encode(Sha256::digest(b"Exact")),
            context: None,
        };
        let version = RecordVersion::build(
            RecordVersionId::generate(&mut rand::rng()),
            RecordIdentity::new(u.clone(), anchor_id.clone(), RecordKind::Anchor),
            Payload::Anchor(anchor.clone()),
        )
        .unwrap();
        let mut next = p.clone();
        next.proposal.version += 1;
        next.proposal
            .operations
            .push(DomainOperation::RecordNarrativeReference {
                client_ref: anchor_id.to_string(),
                record: RecordKind::Anchor,
                payload: Payload::Anchor(anchor),
            });
        next.changes.push(Assignment {
            record_id: anchor_id.clone(),
            expected: None,
            next: Some(version.clone()),
        });
        next.proposal.digest.clear();
        next.proposal.digest = hash(&(&next.proposal, &next.changes, &next.footprint));
        w.kernel
            .preview(&w.input(&next, "anchor-preview".into()).unwrap())
            .unwrap();
        w.save(
            format!(
                "proposal:{}:{:020}",
                next.proposal.proposal_id, next.proposal.version
            ),
            &next,
        )
        .unwrap();
        let r = reference(&next);
        let mut b = body(&next, &profile, text);
        b.dependencies.push(AssessmentVersionRef {
            universe: u.clone(),
            record: anchor_id,
            version: version.record_version_id,
        });
        let baseline = snapshot(&w);
        let mut wrong = b.clone();
        wrong.sources[0].ranges[0].start = 1;
        assert!(
            w.attach_assessment(&r, 0, wrong, "anchor-outside-range")
                .is_err()
        );
        let mut wrong = b.clone();
        wrong.dependencies[0].record = RecordId::generate(&mut rand::rng());
        assert!(
            w.attach_assessment(&r, 0, wrong, "dependency-identity")
                .is_err()
        );
        let mut wrong = b.clone();
        wrong.dependencies[0].universe = UniverseId::generate(&mut rand::rng());
        assert!(
            w.attach_assessment(&r, 0, wrong, "dependency-universe")
                .is_err()
        );
        assert_eq!(snapshot(&w), baseline);
        // Invalid immutable anchor excerpts and source versions reject attachment
        // admission even when the assessment claims matching candidate bindings.
        for (index, mismatch) in ["excerpt", "excerpt_digest", "source_version"]
            .iter()
            .enumerate()
        {
            let mut invalid = next.clone();
            invalid.proposal.proposal_id = ProposalId::generate(&mut rand::rng());
            invalid.proposal.version = 1;
            let record = invalid.changes.last_mut().unwrap().next.as_mut().unwrap();
            if let Payload::Anchor(anchor) = &mut record.payload {
                match *mismatch {
                    "excerpt" => anchor.excerpt = "Wrong".into(),
                    "excerpt_digest" => anchor.excerpt_digest = "0".repeat(64),
                    _ => {
                        anchor.source_version.version = RecordVersionId::generate(&mut rand::rng())
                    }
                }
            }
            record.payload_digest =
                universe_domain::canonical::payload_digest(&RecordKind::Anchor, &record.payload);
            invalid.proposal.digest.clear();
            invalid.proposal.digest =
                hash(&(&invalid.proposal, &invalid.changes, &invalid.footprint));
            w.save(
                format!(
                    "proposal:{}:{:020}",
                    invalid.proposal.proposal_id, invalid.proposal.version
                ),
                &invalid,
            )
            .unwrap();
            let ir = reference(&invalid);
            let mut invalid_body = body(&invalid, &profile, text);
            invalid_body.dependencies = b.dependencies.clone();
            let unchanged = snapshot(&w);
            assert!(
                w.attach_assessment(&ir, 0, invalid_body, &format!("bad-anchor-{index}"))
                    .is_err()
            );
            assert_eq!(snapshot(&w), unchanged);
        }
        let mut wrong = b.clone();
        wrong.sources[0].work_edition = Some(wrong.sources[0].source_version.clone());
        let unchanged = snapshot(&w);
        assert!(
            w.attach_assessment(&r, 0, wrong, "wrong-edition-type")
                .is_err()
        );
        assert_eq!(snapshot(&w), unchanged);
        w.attach_assessment(&r, 0, b.clone(), "exact-anchor")
            .unwrap();
        assert!(matches!(
            w.get_assessment(&r, None).unwrap().1,
            AssessmentState::Bound { .. }
        ));
        let expected = json!(snapshot(&w));
        audit(&path, "anchor-before-restart", &expected);
        drop(w);
        drop(kernel);
        let mut kernel = Kernel::open(&path).unwrap();
        let w = workflow(&mut kernel, &profile);
        assert!(matches!(
            w.get_assessment(&r, None).unwrap().1,
            AssessmentState::Bound { .. }
        ));
        audit(&path, "anchor-after-restart", &expected);
        // Missing retention is unavailable, not absence and never latest-text recovery.
        let digest: String =
            serde_json::from_value(serde_json::to_value(&b.sources[0].blob_digest).unwrap())
                .unwrap();
        drop(w);
        drop(kernel);
        let db = rusqlite::Connection::open(&path).unwrap();
        assert!(
            db.execute(
                "DELETE FROM workflow_entries WHERE key=?1",
                [format!("source:{digest}")]
            )
            .is_err()
        );
        // Deliberate corruption of this disposable fixture; production deletion
        // remains forbidden by both storage API and SQL trigger.
        db.execute_batch("DROP TRIGGER workflow_entries_no_delete")
            .unwrap();
        db.execute(
            "DELETE FROM workflow_entries WHERE key=?1",
            [format!("source:{digest}")],
        )
        .unwrap();
        db.execute_batch("CREATE TRIGGER workflow_entries_no_delete BEFORE DELETE ON workflow_entries BEGIN SELECT RAISE(ABORT, 'immutable workflow entry'); END;").unwrap();
        drop(db);
        let mut kernel = Kernel::open(&path).unwrap();
        let mut w = workflow(&mut kernel, &profile);
        assert!(matches!(
            w.get_assessment(&r, None).unwrap().1,
            AssessmentState::Unavailable {
                reason: UnavailableReason::MissingRetainedMaterial
            }
        ));
        let missing = snapshot(&w);
        assert!(
            w.attach_assessment(&r, 1, b, "cannot-write-missing")
                .is_err()
        );
        assert_eq!(snapshot(&w), missing);
        let selected = w.assessment_selection_raw(&r).unwrap().selected.unwrap();
        drop(w);
        drop(kernel);
        let db = rusqlite::Connection::open(&path).unwrap();
        db.execute_batch("DROP TRIGGER workflow_entries_no_delete")
            .unwrap();
        db.execute(
            "DELETE FROM workflow_entries WHERE key=?1",
            [envelope_key(&selected)],
        )
        .unwrap();
        db.execute_batch("CREATE TRIGGER workflow_entries_no_delete BEFORE DELETE ON workflow_entries BEGIN SELECT RAISE(ABORT, 'immutable workflow entry'); END;").unwrap();
        drop(db);
        let mut kernel = Kernel::open(&path).unwrap();
        let mut w = workflow(&mut kernel, &profile);
        let missing_envelope = w.get_assessment(&r, None).unwrap();
        assert!(matches!(
            missing_envelope.1,
            AssessmentState::Unavailable {
                reason: UnavailableReason::MissingRetainedMaterial
            }
        ));
        assert!(missing_envelope.2.is_none());
        w.principal.author = false;
        assert!(w.get_assessment(&r, None).is_err());
    }
}
