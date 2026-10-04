//! Resolution uses only the supplied factual snapshot, never a database head.
use std::collections::BTreeSet;
use universe_domain::{ids::*, records::*, scope::Applicability};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Ancestry {
    pub types: Vec<RecordId>,
    pub complete: bool,
}

pub fn ancestry(subject: &RecordId, records: &[RecordVersion]) -> Ancestry {
    let get = |id: &RecordId| records.iter().find(|r| &r.identity.record_id == id);
    let Some(record) = get(subject) else {
        return Ancestry {
            types: vec![],
            complete: false,
        };
    };
    let universe = &record.identity.universe_id;
    let mut next = match &record.payload {
        Payload::Entity(e) if e.classification_resolution == ClassificationResolution::Resolved => {
            e.classification.clone()
        }
        Payload::EntityType(_) => Some(subject.clone()),
        _ => {
            return Ancestry {
                types: vec![],
                complete: false,
            }
        }
    };
    let mut result = Ancestry {
        types: vec![],
        complete: true,
    };
    let mut seen = BTreeSet::new();
    while let Some(id) = next {
        if !seen.insert(id.clone()) {
            result.complete = false;
            break;
        }
        let Some(r) = get(&id).filter(|r| &r.identity.universe_id == universe) else {
            result.complete = false;
            break;
        };
        let Payload::EntityType(t) = &r.payload else {
            result.complete = false;
            break;
        };
        // A nonexecutable or ambiguous definition cannot establish ancestry.
        if !t.classification_executable || t.parent_resolution == ParentResolution::Ambiguous {
            result.complete = false;
            break;
        }
        result.types.push(id);
        match t.parent_resolution {
            ParentResolution::Root if t.parent.is_none() => next = None,
            ParentResolution::Resolved if t.parent.is_some() => next = t.parent.clone(),
            _ => {
                result.complete = false;
                break;
            }
        }
    }
    if result.types.is_empty() {
        result.complete = false;
    }
    result
}

/// Each ancestor has independent jurisdiction. A disjoint child does not hide
/// a known ancestor; an unresolved chain does not prove nonmembership.
pub fn world_applies(scope: &Applicability, worlds: &[RecordId]) -> Option<bool> {
    match scope {
        Applicability::UniverseWide => Some(true),
        Applicability::Worlds { world_ids } if world_ids.is_empty() => Some(false),
        Applicability::Worlds { .. } if worlds.is_empty() => None,
        Applicability::Worlds { world_ids } => Some(worlds.iter().all(|r| {
            world_ids
                .iter()
                .any(|w| r.as_str().strip_prefix("rec_") == w.as_str().strip_prefix("wld_"))
        })),
        _ => None,
    }
}

pub fn matches(
    subject: &RecordId,
    targets: &[RecordId],
    records: &[RecordVersion],
    worlds: Option<&[RecordId]>,
) -> Option<bool> {
    if targets.is_empty() {
        return Some(true);
    }
    if let Some(worlds) = worlds.filter(|w| w.len() > 1) {
        let mut unknown = false;
        for world in worlds {
            match matches(subject, targets, records, Some(std::slice::from_ref(world))) {
                Some(false) => return Some(false),
                None => unknown = true,
                Some(true) => {}
            }
        }
        return if unknown { None } else { Some(true) };
    }
    let chain = ancestry(subject, records);
    let mut unknown = !chain.complete;
    let mut matched = false;
    for id in chain.types.iter().filter(|id| targets.contains(id)) {
        let Some(Payload::EntityType(t)) = records
            .iter()
            .find(|r| &r.identity.record_id == id)
            .map(|r| &r.payload)
        else {
            return None;
        };
        match worlds.map_or(Some(true), |w| world_applies(&t.applicability, w)) {
            Some(true) if chain.complete => matched = true,
            Some(false) => {}
            _ => unknown = true,
        }
    }
    if unknown {
        None
    } else {
        Some(matched)
    }
}

/// Type hints enumerate relevant rules over the complete candidate. They do
/// not select, filter or bind an expression operand or quantifier collection.
/// A known matching instance establishes relevance; without one, unknown
/// classification/ancestry prevents a convenient nonapplicability verdict.
pub fn rule_applies(rule: &Rule, records: &[RecordVersion], worlds: &[RecordId]) -> Option<bool> {
    if rule.subject_types.is_empty() {
        return Some(true);
    }
    let mut unknown = false;
    let mut relevant = false;
    for r in records
        .iter()
        .filter(|r| matches!(r.payload, Payload::Entity(_)))
    {
        match matches(
            &r.identity.record_id,
            &rule.subject_types,
            records,
            Some(worlds),
        ) {
            Some(true) => relevant = true,
            Some(false) => {}
            None => unknown = true,
        }
    }
    if relevant {
        Some(true)
    } else if unknown {
        None
    } else {
        Some(false)
    }
}

/// Admission checks the whole authored fact scope, not a selected UI world.
/// Explicit universe-wide facts require explicit universe-wide type permission.
pub fn covers(
    subject: &RecordId,
    targets: &[RecordId],
    records: &[RecordVersion],
    scope: &Applicability,
) -> Option<bool> {
    if targets.is_empty() {
        return Some(true);
    }
    match scope {
        Applicability::Worlds { world_ids } if world_ids.is_empty() => Some(true),
        Applicability::Worlds { world_ids } => {
            let worlds: Vec<_> = world_ids
                .iter()
                .map(|w| {
                    RecordId::parse(&w.as_str().replacen("wld_", "rec_", 1)).expect("world id")
                })
                .collect();
            matches(subject, targets, records, Some(&worlds))
        }
        Applicability::UniverseWide => {
            if matches(subject, targets, records, None) != Some(true) {
                return matches(subject, targets, records, None);
            }
            let chain = ancestry(subject, records);
            let mut allowed = false;
            for id in chain.types.iter().filter(|id| targets.contains(id)) {
                let Payload::EntityType(t) = &records
                    .iter()
                    .find(|r| &r.identity.record_id == id)?
                    .payload
                else {
                    return None;
                };
                match t.applicability {
                    Applicability::UniverseWide => allowed = true,
                    Applicability::Worlds { .. } => {}
                    _ => return None,
                }
            }
            Some(allowed)
        }
        _ => None,
    }
}
