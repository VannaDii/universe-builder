//! Immutable initialization evidence admitted in the same transaction as state.
use super::*;
use universe_domain::{scope::*, temporal::*, value::VersionRef};

pub(super) fn pending(
    c: &Connection,
    input: &CommitInput,
    base: &Membership,
    candidate: &Membership,
) -> StoreResult<Vec<InitializationReceipt>> {
    let u = input.universe.as_str();
    let get = |map: &Membership, id: &RecordId| {
        map.get(id.as_str())
            .ok_or_else(|| invalid("initialization reference absent"))
            .and_then(|v| load(c, u, v))
    };
    let mut receipts = Vec::new();
    let mut keys = BTreeSet::new();
    for change in &input.changes {
        let Some(record) = &change.next else { continue };
        let Payload::Assertion(a) = &record.payload else {
            continue;
        };
        let EvidenceBasis::InstanceInitialization {
            start,
            definition,
            source_revision,
        } = &a.basis
        else {
            continue;
        };
        // Explicit correction/adoption of this same assertion identity retains
        // its original receipt. A fresh assertion can never reuse that provenance.
        let prior_receipt = c.query_row(
            "SELECT r.assertion_version FROM initialization_receipt r JOIN record_versions v ON v.universe_id=r.universe_id AND v.id=r.assertion_version WHERE r.universe_id=?1 AND v.record_id=?2",
            params![u, change.record_id.as_str()], |r| r.get::<_, String>(0),
        ).optional()?;
        if let Some(original) = prior_receipt {
            if matches!(load(c,u,&original)?.payload, Payload::Assertion(ref prior) if prior.basis == a.basis)
            {
                continue;
            }
            return Err(invalid(
                "initialization provenance cannot change on historical restoration",
            ));
        }
        if let Some(old) = &change.expected {
            let old = load(c, u, old.as_str())?;
            if !matches!(old.payload, Payload::Assertion(ref prior) if prior.basis == a.basis) {
                return Err(invalid(
                    "initialization provenance cannot be added or changed by correction",
                ));
            }
            // Authored correction preserves the original immutable receipt.
            continue;
        }
        if source_revision != &input.expected_head {
            return Err(invalid(
                "initialization source revision differs from review base",
            ));
        }
        let pinned = |reference: &VersionRef, map: &Membership| -> StoreResult<RecordVersion> {
            if reference.universe.as_ref() != Some(&input.universe) {
                return Err(invalid("initialization needs explicit local provenance"));
            }
            let r = get(map, &reference.record)?;
            if r.record_version_id != reference.version {
                return Err(invalid("initialization provenance version differs"));
            }
            Ok(r)
        };
        let source = pinned(definition, base)?;
        if get(candidate, &definition.record)? != source {
            return Err(invalid(
                "initial definition changed in initialization proposal",
            ));
        }
        let Payload::Assertion(initial) = &source.payload else {
            return Err(invalid("initial definition must pin an assertion"));
        };
        let Payload::Proposition(source_p) = get(base, &initial.proposition.record)?.payload else {
            return Err(invalid("initial definition proposition absent"));
        };
        if get(candidate, &initial.proposition.record)? != get(base, &initial.proposition.record)? {
            return Err(invalid("initial definition proposition changed"));
        }
        let Payload::Proposition(p) = get(candidate, &a.proposition.record)?.payload else {
            return Err(invalid("initial instance proposition absent"));
        };
        let Payload::Event(event) = pinned(start, candidate)?.payload else {
            return Err(invalid("initialization start must be an event"));
        };
        let TemporalExpression::Exact { calendar, value } = &event.time else {
            return Err(invalid("initialization needs an exact authored start"));
        };
        if event.occurrence != OccurrenceMode::Occurred
            || !event.participants.iter().any(|r| r.record == p.subject)
            || a.attribute_mode != AttributeMode::Instance
            || initial.attribute_mode != AttributeMode::InitialValue
            || a.polarity != Polarity::Support
            || initial.polarity != Polarity::Support
            || a.precision != Precision::Exact
            || initial.precision != Precision::Exact
            || !a.alternatives.is_empty()
            || !initial.alternatives.is_empty()
            || a.established_by.is_some()
            || !scope_contains(&initial.scope, &a.scope)
            || p.context != source_p.context
            || p.context != a.scope.context
            || p.predicate != source_p.predicate
            || p.value != source_p.value
            || p.value.is_none()
            || p.quantification != Quantification::Particular
            || !matches!(&a.validity, Validity::CalendarInterval {calendar: clock, start: TemporalBound::Exact {value: at}, ..} if clock == calendar && at == value)
        {
            return Err(invalid(
                "initialization evidence disagrees with authored start or definition",
            ));
        }
        if !matches!(
            get(candidate, &p.predicate.record)?.payload,
            Payload::Property(_)
        ) {
            return Err(invalid("initialization predicate must be a property"));
        }
        if !matches!(
            get(candidate, &p.subject.record)?.payload,
            Payload::Entity(_)
        ) {
            return Err(invalid("initialization subject must be an instance"));
        }
        // Classification is knowledge, not a reset. The source must be an
        // explicit ancestor; no labels, names or holder associations select it.
        let Payload::Entity(entity) = get(candidate, &p.subject.record)?.payload else {
            unreachable!()
        };
        if entity.classification_resolution != ClassificationResolution::Resolved {
            return Err(invalid("initialization classification unresolved"));
        }
        let mut next = entity.classification;
        let mut ancestry = BTreeSet::new();
        while let Some(id) = next {
            if !ancestry.insert(id.clone()) {
                return Err(invalid("initialization ancestry cyclic"));
            }
            let Payload::EntityType(t) = get(candidate, &id)?.payload else {
                return Err(invalid("initialization ancestry absent"));
            };
            if !t.classification_executable || t.parent_resolution == ParentResolution::Ambiguous {
                return Err(invalid("initialization ancestry unresolved"));
            }
            next = t.parent;
        }
        if !ancestry.contains(&source_p.subject.record) {
            return Err(invalid("initial definition is not an instance ancestor"));
        }
        for version in base.values() {
            let prior = load(c, u, version)?;
            if let Payload::Assertion(prior) = prior.payload {
                if prior.attribute_mode == AttributeMode::Instance {
                    if let Payload::Proposition(prior) =
                        get(base, &prior.proposition.record)?.payload
                    {
                        if prior.subject == p.subject && prior.predicate == p.predicate {
                            return Err(invalid("existing instance evidence requires resolution, not initialization"));
                        }
                    }
                }
            }
        }
        let key = (p.subject.record.clone(), p.predicate.record.clone());
        if !keys.insert(key) || c.query_row(
            "SELECT EXISTS(SELECT 1 FROM initialization_receipt WHERE universe_id=?1 AND instance_id=?2 AND predicate_id=?3)",
            params![u, p.subject.record.as_str(), p.predicate.record.as_str()], |r| r.get::<_, bool>(0),
        )? {
            return Err(invalid("instance property has already been initialized"));
        }
        receipts.push(InitializationReceipt {
            instance: p.subject.record,
            start: start.record.clone(),
            property: p.predicate.record,
            definition: definition.version.clone(),
            assertion: record.record_version_id.clone(),
            revision: input.expected_head.clone(),
            source_revision: source_revision.clone(),
        });
    }
    Ok(receipts)
}

pub(super) fn insert(c: &Connection, u: &str, receipt: &InitializationReceipt) -> StoreResult<()> {
    c.execute(
        "INSERT INTO initialization_receipt VALUES(?1,?2,?3,?4,?5,?6,?7,?8)",
        params![
            u,
            receipt.instance.as_str(),
            receipt.start.as_str(),
            receipt.property.as_str(),
            receipt.definition.as_str(),
            receipt.assertion.as_str(),
            receipt.revision.as_str(),
            receipt.source_revision.as_str()
        ],
    )?;
    Ok(())
}

fn scope_contains(source: &Scope, target: &Scope) -> bool {
    source.context == target.context
        && source.realm == target.realm
        && match (&source.applicability, &target.applicability) {
            (Applicability::UniverseWide, Applicability::UniverseWide) => true,
            (Applicability::UniverseWide, Applicability::Worlds { world_ids }) => {
                !world_ids.is_empty()
            }
            (
                Applicability::Worlds { world_ids: source },
                Applicability::Worlds { world_ids: target },
            ) => !target.is_empty() && target.iter().all(|w| source.contains(w)),
            _ => false,
        }
}

pub(super) fn read(c: &Connection, u: &str) -> StoreResult<Vec<InitializationReceipt>> {
    let rows = c.prepare("SELECT instance_id,start_event_id,predicate_id,initial_definition_version,assertion_version,revision_id,source_revision FROM initialization_receipt WHERE universe_id=?1 ORDER BY instance_id,predicate_id,start_event_id")?
        .query_map([u], |r| Ok((r.get::<_, String>(0)?,r.get::<_, String>(1)?,r.get::<_, String>(2)?,r.get::<_, String>(3)?,r.get::<_, String>(4)?,r.get::<_, String>(5)?,r.get::<_, String>(6)?)))?
        .collect::<Result<Vec<_>, _>>()?;
    rows.into_iter()
        .map(
            |(instance, start, property, definition, assertion, revision, source_revision)| {
                Ok(InitializationReceipt {
                    instance: RecordId::parse(&instance)
                        .map_err(|_| invalid("receipt instance"))?,
                    start: RecordId::parse(&start).map_err(|_| invalid("receipt start"))?,
                    property: RecordId::parse(&property)
                        .map_err(|_| invalid("receipt property"))?,
                    definition: RecordVersionId::parse(&definition)
                        .map_err(|_| invalid("receipt definition"))?,
                    assertion: RecordVersionId::parse(&assertion)
                        .map_err(|_| invalid("receipt assertion"))?,
                    revision: RevisionId::parse(&revision)
                        .map_err(|_| invalid("receipt revision"))?,
                    source_revision: RevisionId::parse(&source_revision)
                        .map_err(|_| invalid("receipt source revision"))?,
                })
            },
        )
        .collect()
}

pub(super) fn verify(c: &Connection, u: &str) -> StoreResult<()> {
    let actual = read(c, u)?;
    let mut expected = Vec::new();
    let changes = c.prepare("SELECT ch.version_id,ch.revision_id,co.continuity_id,co.parent_id FROM commit_changes ch JOIN commits co ON co.universe_id=ch.universe_id AND co.id=ch.revision_id JOIN record_versions v ON v.universe_id=ch.universe_id AND v.id=ch.version_id WHERE v.kind='assertion' AND ch.universe_id=?1 AND ch.prior_version IS NULL AND ch.version_id IS NOT NULL ORDER BY ch.revision_id,ch.record_id")?
        .query_map([u], |r| Ok((r.get::<_,String>(0)?, r.get::<_,String>(1)?, r.get::<_,String>(2)?, r.get::<_,Option<String>>(3)?)))?
        .collect::<Result<Vec<_>,_>>()?;
    for (version, revision, continuity, parent) in changes {
        let record = load(c, u, &version)?;
        let Payload::Assertion(a) = &record.payload else {
            continue;
        };
        let EvidenceBasis::InstanceInitialization {
            start,
            definition,
            source_revision,
        } = &a.basis
        else {
            continue;
        };
        if actual.iter().any(|r|r.assertion != record.record_version_id && load(c,u,r.assertion.as_str()).is_ok_and(|original|original.identity.record_id == record.identity.record_id && matches!(original.payload, Payload::Assertion(ref prior) if prior.basis == a.basis))) {
            // A reviewed restoration is another version of the original fact,
            // not another original admission or initialization.
            continue;
        }
        if parent.as_deref() != Some(source_revision.as_str()) {
            return Err(invalid(
                "initialization source revision differs from admitting parent",
            ));
        }
        let membership = resolve(c, u, &continuity, &revision, &mut BTreeSet::new())?;
        let p = membership
            .get(a.proposition.record.as_str())
            .ok_or_else(|| invalid("initial receipt proposition absent"))?;
        let Payload::Proposition(p) = load(c, u, p)?.payload else {
            return Err(invalid("receipt proposition kind"));
        };
        expected.push(InitializationReceipt {
            instance: p.subject.record,
            start: start.record.clone(),
            property: p.predicate.record,
            definition: definition.version.clone(),
            assertion: record.record_version_id,
            revision: RevisionId::parse(&revision).map_err(|_| invalid("receipt revision"))?,
            source_revision: source_revision.clone(),
        });
    }
    let order =
        |r: &InitializationReceipt| (r.instance.clone(), r.property.clone(), r.start.clone());
    expected.sort_by_key(order);
    if expected != actual {
        return Err(invalid("initialization receipt history mismatch"));
    }
    Ok(())
}

impl Kernel {
    /// Receipts admitted in this pinned revision's history, including fork ancestry.
    pub fn initialization_receipts_at(
        &self,
        continuity: &ContinuityId,
        revision: &RevisionId,
    ) -> StoreResult<Vec<InitializationReceipt>> {
        self.snapshot(continuity, revision)?;
        let mut reachable = BTreeSet::new();
        let mut next = Some(revision.to_string());
        while let Some(id) = next {
            if !reachable.insert(id.clone()) || reachable.len() > MAX_CHAIN {
                return Err(invalid("initialization history budget exceeded"));
            }
            let (parent, branch): (Option<String>, String) = self.conn.query_row(
                "SELECT parent_id,continuity_id FROM commits WHERE universe_id=?1 AND id=?2",
                params![self.universe.as_str(), id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )?;
            next = if parent.is_some() {
                parent
            } else {
                self.conn.query_row(
                    "SELECT baseline_commit FROM continuities WHERE universe_id=?1 AND id=?2",
                    params![self.universe.as_str(), branch],
                    |r| r.get(0),
                )?
            };
        }
        Ok(self
            .initialization_receipts()?
            .into_iter()
            .filter(|r| reachable.contains(r.revision.as_str()))
            .collect())
    }
    /// Durable initialization evidence survives correction and tombstones.
    pub fn initialization_receipts(&self) -> StoreResult<Vec<InitializationReceipt>> {
        read(&self.conn, self.universe.as_str())
    }
}
