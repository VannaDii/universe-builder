//! An ephemeral index of one exact candidate. It is never reused across frames,
//! revisions or grants; the unindexed evaluator remains the reference path.
use std::collections::BTreeMap;
use universe_domain::{
    ids::RecordId,
    records::{Payload, RecordVersion},
    value::RecordRef,
};
pub struct EvaluationIndex<'a> {
    definitions: BTreeMap<String, Vec<&'a RecordVersion>>,
    propositions: BTreeMap<(RecordRef, RecordId, RecordRef), Vec<&'a RecordVersion>>,
    assertions: BTreeMap<RecordId, Vec<&'a RecordVersion>>,
    completeness: BTreeMap<(RecordRef, String), Vec<&'a RecordVersion>>,
    exceptions: BTreeMap<RecordId, Vec<&'a RecordVersion>>,
    has_powers: bool,
}
impl<'a> EvaluationIndex<'a> {
    pub fn new(records: &'a [RecordVersion]) -> Self {
        let mut index = Self {
            definitions: BTreeMap::new(),
            propositions: BTreeMap::new(),
            assertions: BTreeMap::new(),
            completeness: BTreeMap::new(),
            exceptions: BTreeMap::new(),
            has_powers: false,
        };
        for r in records {
            match &r.payload {
                Payload::ItemPower(_) => index.has_powers = true,
                Payload::Property(d) => index
                    .definitions
                    .entry(format!("{}:{}", d.namespace, d.key))
                    .or_default()
                    .push(r),
                Payload::Relation(d) => index
                    .definitions
                    .entry(format!("{}:{}", d.namespace, d.key))
                    .or_default()
                    .push(r),
                Payload::Proposition(p) => index
                    .propositions
                    .entry((
                        p.subject.clone(),
                        p.predicate.record.clone(),
                        p.context.clone(),
                    ))
                    .or_default()
                    .push(r),
                Payload::Assertion(a) => index
                    .assertions
                    .entry(a.proposition.record.clone())
                    .or_default()
                    .push(r),
                Payload::Completeness(c) => index
                    .completeness
                    .entry((c.subject.clone(), c.predicate.clone()))
                    .or_default()
                    .push(r),
                Payload::Exception(e) => index
                    .exceptions
                    .entry(e.rule.record.clone())
                    .or_default()
                    .push(r),
                _ => {}
            }
        }
        index
    }
    pub fn exceptions(&self, target: &RecordId) -> impl Iterator<Item = &'a RecordVersion> + '_ {
        self.exceptions.get(target).into_iter().flatten().copied()
    }
    pub fn has_powers(&self) -> bool {
        self.has_powers
    }
    pub fn claim(
        &self,
        subject: &RecordRef,
        predicate: &str,
        context: &RecordRef,
    ) -> Vec<&'a RecordVersion> {
        let mut found = Vec::new();
        for def in self.definitions.get(predicate).into_iter().flatten() {
            found.push(*def);
            for prop in self
                .propositions
                .get(&(
                    subject.clone(),
                    def.identity.record_id.clone(),
                    context.clone(),
                ))
                .into_iter()
                .flatten()
            {
                found.push(*prop);
                found.extend(
                    self.assertions
                        .get(&prop.identity.record_id)
                        .into_iter()
                        .flatten()
                        .copied(),
                );
            }
        }
        found.extend(
            self.completeness
                .get(&(subject.clone(), predicate.to_string()))
                .into_iter()
                .flatten()
                .copied(),
        );
        found
    }
}
