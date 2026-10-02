//! Private candidate diagnostics, not a wire contract or admission policy.
//! Input is the structurally checked, event-expanded active membership of ONE
//! resolved revision. Historical versions belong in the provenance archive only.
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{
    canonical::Canonical,
    expr::Comparator,
    ids::{RecordId, RecordVersionId, UniverseId},
    records::{Assertion, Payload, Proposition, RecordVersion},
    scope::{Applicability, PersistenceSemantics, Polarity, Precision, Validity},
    temporal::{TemporalBound, TemporalExpression},
    value::RecordRef,
};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum Gap {
    Equality,
    Context,
    Realm,
    Worlds,
    Time,
    Precision,
    Persistence,
    Provenance,
    Budget,
}
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub enum Intersection {
    Unqualified,
    Exact(Validity),
    /// Definite existential overlap; only `guaranteed` is an exact cell.
    Uncertain {
        left: Validity,
        right: Validity,
        guaranteed: Option<Validity>,
    },
    Unresolved,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Chain {
    pub assertion: RecordVersion,
    pub proposition: RecordVersion,
    pub dependencies: Vec<RecordVersion>,
    pub complete: bool,
}
#[derive(Debug, Clone, PartialEq)]
pub struct OpposingPair {
    /// Resolved coarse meaning; value equality is proved pairwise.
    pub comparison_key: Vec<u8>,
    pub support: Chain,
    pub refutation: Chain,
    pub context: RecordRef,
    pub applicability: Option<Applicability>,
    pub realm: Option<RecordRef>,
    pub intersection: Intersection,
    pub gaps: BTreeSet<Gap>,
}
impl OpposingPair {
    pub fn definite(&self) -> bool {
        self.gaps.iter().all(|g| *g == Gap::Provenance)
            && !matches!(self.intersection, Intersection::Unresolved)
    }
}
#[derive(Debug, Clone, PartialEq)]
pub struct Scan {
    pub pairs: Vec<OpposingPair>,
    pub complete: bool,
    pub comparisons: usize,
    pub gaps: BTreeSet<Gap>,
}

/// Bounded comparison with a coarse meaning index, then exact value equality.
/// No transitive equality grouping and no focus-world narrowing occur here.
/// Invalid/ambiguous active membership is rejected rather than selecting a version.
pub fn detect(
    universe: &UniverseId,
    records: &[RecordVersion],
    indexed: bool,
    budget: usize,
) -> Result<Scan, &'static str> {
    let budget = budget.min(10_000);
    if records.len() > 10_000 {
        return Err("active membership budget exhausted");
    }
    let mut membership = BTreeMap::<RecordId, &RecordVersion>::new();
    for r in records {
        if &r.identity.universe_id != universe {
            return Err("mixed universe membership");
        }
        if let Some(old) = membership.insert(r.identity.record_id.clone(), r) {
            if old != r {
                return Err("ambiguous active membership");
            }
        }
    }
    let resolve = |r: &RecordRef| -> Result<&RecordVersion, &'static str> {
        r.resolve_namespace(universe)
            .map_err(|_| "cross-universe reference")?;
        membership
            .get(&r.record)
            .copied()
            .ok_or("missing active reference")
    };
    let mut meaning_keys = BTreeMap::new();
    let mut chains = BTreeMap::new();
    let mut buckets =
        BTreeMap::<Vec<u8>, Vec<(&RecordVersion, &Assertion, &RecordVersion, &Proposition)>>::new();
    for r in membership.values() {
        let Payload::Assertion(a) = &r.payload else {
            continue;
        };
        let prop = resolve(&a.proposition)?;
        let Payload::Proposition(p) = &prop.payload else {
            return Err("assertion target is not a proposition");
        };
        let def = resolve(&p.predicate)?;
        resolve(&p.subject)?;
        let context = resolve(&p.context)?;
        if !matches!(context.payload, Payload::RepresentedContext(_)) {
            return Err("invalid represented context");
        }
        resolve(&a.scope.context)?;
        if let Some(realm) = &a.scope.realm {
            resolve(realm)?;
        }
        let mut roles = Vec::new();
        for role in &p.roles {
            resolve(&role.participant)?;
            roles.push((
                role.role.clone(),
                role.participant
                    .resolve_namespace(universe)
                    .map_err(|_| "cross-universe role")?,
            ));
        }
        roles.sort();
        match &def.payload {
            Payload::Property(_) if roles.is_empty() => {}
            Payload::Relation(d)
                if roles
                    .iter()
                    .all(|(name, _)| d.roles.iter().any(|role| &role.name == name)) => {}
            _ => return Err("invalid predicate or role declaration"),
        }
        let key = serde_json::to_vec(&(
            p.subject.resolve_namespace(universe).unwrap(),
            &def.record_version_id,
            &p.quantification,
            p.context.resolve_namespace(universe).unwrap(),
            roles,
        ))
        .map_err(|_| "invalid comparison key")?;
        meaning_keys.insert(prop.record_version_id.clone(), key.clone());
        buckets
            .entry(if indexed { key } else { vec![] })
            .or_default()
            .push((*r, a, prop, p));
    }
    let mut scan = Scan {
        pairs: vec![],
        complete: true,
        comparisons: 0,
        gaps: BTreeSet::new(),
    };
    for items in buckets.values() {
        for (s, sa, sp, ps) in items
            .iter()
            .filter(|(_, a, _, _)| a.polarity == Polarity::Support)
        {
            for (r, ra, rp, pr) in items
                .iter()
                .filter(|(_, a, _, _)| a.polarity == Polarity::Refutation)
            {
                if scan.comparisons == budget {
                    scan.complete = false;
                    scan.gaps.insert(Gap::Budget);
                    sort_pairs(&mut scan);
                    return Ok(scan);
                }
                scan.comparisons += 1;
                if !same_meaning(ps, pr, universe) {
                    continue;
                }
                let mut gaps = BTreeSet::new();
                let applicability = worlds(&sa.scope.applicability, &ra.scope.applicability);
                if matches!(&applicability, Some(Applicability::Worlds { world_ids }) if world_ids.is_empty())
                {
                    continue;
                }
                if let (Some(a), Some(b)) = (&sa.scope.realm, &ra.scope.realm) {
                    if a.resolve_namespace(universe).unwrap()
                        != b.resolve_namespace(universe).unwrap()
                    {
                        continue;
                    }
                }
                if crate::time::overlaps(&sa.validity, &ra.validity) == Some(false) {
                    continue;
                }
                let equal = match (&ps.value, &pr.value) {
                    (None, None) => Some(true),
                    (Some(_), None) | (None, Some(_)) => Some(false),
                    (Some(a), Some(b)) if a.to_canonical() == b.to_canonical() => Some(true),
                    (Some(a), Some(b)) => crate::basic::compare(a, Comparator::Eq, b),
                };
                if equal == Some(false) {
                    continue;
                }
                if equal.is_none() {
                    gaps.insert(Gap::Equality);
                }
                if applicability.is_none() {
                    gaps.insert(Gap::Worlds);
                }
                if sa.scope.realm.is_some() != ra.scope.realm.is_some() {
                    gaps.insert(Gap::Realm);
                }
                for (a, p) in [(sa, ps), (ra, pr)] {
                    if a.scope.context.resolve_namespace(universe).unwrap()
                        != p.context.resolve_namespace(universe).unwrap()
                    {
                        gaps.insert(Gap::Context);
                    }
                    if a.precision != Precision::Exact || !a.alternatives.is_empty() {
                        gaps.insert(Gap::Precision);
                    }
                    if matches!(
                        a.persistence,
                        PersistenceSemantics::PersistentUntilChanged
                            | PersistenceSemantics::ConditionDependent
                    ) {
                        gaps.insert(Gap::Persistence);
                    }
                }
                let intersection = intersection(&sa.validity, &ra.validity);
                if intersection == Intersection::Unresolved {
                    gaps.insert(Gap::Time);
                }
                let support = chains
                    .entry(s.record_version_id.clone())
                    .or_insert_with(|| chain(s, sp, universe, &membership))
                    .clone();
                let refutation = chains
                    .entry(r.record_version_id.clone())
                    .or_insert_with(|| chain(r, rp, universe, &membership))
                    .clone();
                if !support.complete || !refutation.complete {
                    gaps.insert(Gap::Provenance);
                }
                scan.complete &=
                    gaps.is_empty() && !matches!(intersection, Intersection::Uncertain { .. });
                scan.pairs.push(OpposingPair {
                    comparison_key: meaning_keys[&sp.record_version_id].clone(),
                    support,
                    refutation,
                    context: ps.context.resolve_namespace(universe).unwrap(),
                    applicability,
                    realm: sa
                        .scope
                        .realm
                        .as_ref()
                        .map(|r| r.resolve_namespace(universe).unwrap()),
                    intersection,
                    gaps,
                });
            }
        }
    }
    sort_pairs(&mut scan);
    Ok(scan)
}
fn sort_pairs(scan: &mut Scan) {
    scan.pairs.sort_by_key(|p| {
        (
            p.comparison_key.clone(),
            p.support.proposition.payload.to_canonical().to_bytes(),
            p.applicability
                .as_ref()
                .map(|a| a.to_canonical().to_bytes()),
            serde_json::to_vec(&p.realm).unwrap(),
            serde_json::to_vec(&p.intersection).unwrap(),
            p.support.assertion.record_version_id.clone(),
            p.refutation.assertion.record_version_id.clone(),
        )
    });
}
fn same_meaning(a: &Proposition, b: &Proposition, u: &UniverseId) -> bool {
    let norm = |r: &RecordRef| r.resolve_namespace(u).ok();
    let roles = |p: &Proposition| {
        let mut roles: Vec<_> = p
            .roles
            .iter()
            .map(|r| (r.role.clone(), norm(&r.participant)))
            .collect();
        roles.sort();
        roles
    };
    norm(&a.subject) == norm(&b.subject)
        && norm(&a.predicate) == norm(&b.predicate)
        && norm(&a.context) == norm(&b.context)
        && a.quantification == b.quantification
        && roles(a) == roles(b)
}
fn worlds(a: &Applicability, b: &Applicability) -> Option<Applicability> {
    use Applicability::*;
    let set = |ids: &Vec<_>| ids.iter().cloned().collect::<BTreeSet<_>>();
    match (a, b) {
        (Worlds { world_ids }, _) | (_, Worlds { world_ids }) if world_ids.is_empty() => {
            Some(Worlds { world_ids: vec![] })
        }
        (UniverseWide, UniverseWide) => Some(UniverseWide),
        (UniverseWide, Worlds { world_ids }) | (Worlds { world_ids }, UniverseWide) => {
            Some(Worlds {
                world_ids: set(world_ids).into_iter().collect(),
            })
        }
        (Worlds { world_ids: a }, Worlds { world_ids: b }) => Some(Worlds {
            world_ids: set(a).intersection(&set(b)).cloned().collect(),
        }),
        _ => None,
    }
}
fn exact_intersection(a: &Validity, b: &Validity, guaranteed: bool) -> Option<Validity> {
    fn bounds(
        v: &Validity,
        guaranteed: bool,
    ) -> Option<(universe_domain::ids::CalendarId, i128, i128, bool)> {
        let endpoint = |b: &TemporalBound, start| match b {
            TemporalBound::Exact { value } => value.parse().ok(),
            TemporalBound::Unbounded => Some(if start { i128::MIN } else { i128::MAX }),
            TemporalBound::BoundedUncertainty { lower, upper } if guaranteed => {
                (if start { upper } else { lower }).parse().ok()
            }
            _ => None,
        };
        match v {
            Validity::CalendarInterval {
                calendar,
                start,
                end,
            } => Some((
                calendar.clone(),
                endpoint(start, true)?,
                endpoint(end, false)?,
                false,
            )),
            Validity::Instant {
                at: TemporalExpression::Exact { calendar, value },
            } => {
                let n = value.parse().ok()?;
                Some((calendar.clone(), n, n, true))
            }
            _ => None,
        }
    }
    let (d, x, y, bp) = bounds(b, guaranteed)?;
    let (c, a, b, ap) = bounds(a, guaranteed)?;
    if c != d {
        return None;
    }
    if ap || bp {
        let n = if ap { a } else { x };
        if (ap && bp && a == x) || (ap && !bp && x <= n && n < y) || (!ap && bp && a <= n && n < b)
        {
            return Some(Validity::Instant {
                at: TemporalExpression::Exact {
                    calendar: c,
                    value: n.to_string(),
                },
            });
        }
        return None;
    }
    let (start, end) = (a.max(x), b.min(y));
    if start >= end {
        return None;
    }
    let bound = |n: i128| {
        if n == i128::MIN || n == i128::MAX {
            TemporalBound::Unbounded
        } else {
            TemporalBound::Exact {
                value: n.to_string(),
            }
        }
    };
    Some(Validity::CalendarInterval {
        calendar: c,
        start: bound(start),
        end: bound(end),
    })
}
fn intersection(a: &Validity, b: &Validity) -> Intersection {
    if matches!((a, b), (Validity::Unspecified, Validity::Unspecified)) {
        return Intersection::Unqualified;
    }
    if crate::time::overlaps(a, b) != Some(true) {
        return Intersection::Unresolved;
    }
    if let Some(v) = exact_intersection(a, b, false) {
        return Intersection::Exact(v);
    }
    Intersection::Uncertain {
        left: a.clone(),
        right: b.clone(),
        guaranteed: exact_intersection(a, b, true),
    }
}
fn chain(
    a: &RecordVersion,
    p: &RecordVersion,
    u: &UniverseId,
    m: &BTreeMap<RecordId, &RecordVersion>,
) -> Chain {
    // Traverse immutable payload links, including exact version links. Missing
    // archived versions never silently resolve to the active replacement.
    let mut found = BTreeMap::<RecordVersionId, RecordVersion>::new();
    let mut pending = vec![a.clone(), p.clone()];
    let mut complete = true;
    while let Some(r) = pending.pop() {
        if found.contains_key(&r.record_version_id) {
            continue;
        }
        if let Payload::Assertion(assertion) = &r.payload {
            if matches!(
                assertion.basis,
                universe_domain::scope::EvidenceBasis::ImportedClaim
            ) {
                complete = false;
            }
        }
        fn refs(v: &serde_json::Value, out: &mut Vec<(RecordRef, Option<RecordVersionId>)>) {
            match v {
                serde_json::Value::Object(o) => {
                    if o.contains_key("record") {
                        let mut reference = o.clone();
                        reference.remove("version");
                        if let Ok(r) = serde_json::from_value(serde_json::Value::Object(reference))
                        {
                            let version = o
                                .get("version")
                                .and_then(|v| serde_json::from_value(v.clone()).ok());
                            out.push((r, version));
                            return;
                        }
                    }
                    for v in o.values() {
                        refs(v, out);
                    }
                }
                serde_json::Value::Array(items) => {
                    for v in items {
                        refs(v, out);
                    }
                }
                _ => {}
            }
        }
        let mut links = vec![];
        refs(&serde_json::to_value(&r.payload).unwrap(), &mut links);
        for (link, version) in links {
            match link
                .resolve_namespace(u)
                .ok()
                .and_then(|_| m.get(&link.record))
            {
                Some(next)
                    if version
                        .as_ref()
                        .is_none_or(|v| v == &next.record_version_id) =>
                {
                    pending.push((*next).clone())
                }
                _ => complete = false,
            }
        }
        found.insert(r.record_version_id.clone(), r);
    }
    found.remove(&a.record_version_id);
    found.remove(&p.record_version_id);
    Chain {
        assertion: a.clone(),
        proposition: p.clone(),
        dependencies: found.into_values().collect(),
        complete,
    }
}
