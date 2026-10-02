use universe_domain::ids::RecordVersionId;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EvidenceBit {
    pub present: bool,
    pub sources: Vec<RecordVersionId>,
}

impl EvidenceBit {
    pub fn absent() -> Self {
        Self {
            present: false,
            sources: Vec::new(),
        }
    }
    pub fn with_source(source: RecordVersionId) -> Self {
        Self {
            present: true,
            sources: vec![source],
        }
    }
    pub fn with_sources(sources: Vec<RecordVersionId>) -> Self {
        Self {
            present: true,
            sources,
        }
    }
    pub fn or(self, other: Self) -> Self {
        if !self.present && !other.present {
            return Self::absent();
        }
        let mut s = self.sources;
        s.extend(other.sources);
        s.sort();
        s.dedup();
        Self {
            present: true,
            sources: s,
        }
    }
    pub fn and(self, other: Self) -> Self {
        if !self.present || !other.present {
            return Self::absent();
        }
        // Conjunction needs both derivations, not their source intersection.
        let mut sources = self.sources;
        sources.extend(other.sources);
        sources.sort();
        sources.dedup();
        Self {
            present: true,
            sources,
        }
    }
    pub fn negate(self) -> Self {
        Self {
            present: !self.present,
            sources: self.sources,
        }
    }
    pub fn is_definite(&self) -> bool {
        self.present
    }
    pub fn is_absent(&self) -> bool {
        !self.present && self.sources.is_empty()
    }
    pub fn is_indeterminate(&self) -> bool {
        self.present && self.sources.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Evidence {
    pub support: EvidenceBit,
    pub refutation: EvidenceBit,
}

impl Evidence {
    pub fn not_established() -> Self {
        Self {
            support: EvidenceBit::absent(),
            refutation: EvidenceBit::absent(),
        }
    }
    pub fn supported(sources: Vec<RecordVersionId>) -> Self {
        Self {
            support: EvidenceBit::with_sources(sources),
            refutation: EvidenceBit::absent(),
        }
    }
    pub fn refuted(sources: Vec<RecordVersionId>) -> Self {
        Self {
            support: EvidenceBit::absent(),
            refutation: EvidenceBit::with_sources(sources),
        }
    }
    pub fn conflicting(a: Vec<RecordVersionId>, b: Vec<RecordVersionId>) -> Self {
        Self {
            support: EvidenceBit::with_sources(a),
            refutation: EvidenceBit::with_sources(b),
        }
    }
    pub fn outcome(&self) -> EvidenceOutcome {
        match (self.support.present, self.refutation.present) {
            (true, false) => EvidenceOutcome::Supported,
            (false, true) => EvidenceOutcome::Refuted,
            (true, true) => EvidenceOutcome::Conflicting,
            _ => EvidenceOutcome::NotEstablished,
        }
    }
    pub fn negate(self) -> Self {
        Self {
            support: self.refutation,
            refutation: self.support,
        }
    }
    /// Spec 31.2: support AND, refutation OR (truth order).
    pub fn all(self, other: Self) -> Self {
        Self {
            support: self.support.and(other.support),
            refutation: self.refutation.or(other.refutation),
        }
    }
    /// Spec 31.2: support OR, refutation AND (truth order).
    pub fn any(self, other: Self) -> Self {
        Self {
            support: self.support.or(other.support),
            refutation: self.refutation.and(other.refutation),
        }
    }
    pub fn all_sources(&self) -> Vec<RecordVersionId> {
        let mut s = self.support.sources.clone();
        s.extend(self.refutation.sources.clone());
        s.sort();
        s.dedup();
        s
    }
    pub fn is_definite(&self) -> bool {
        self.support.is_definite() || self.refutation.is_definite()
    }
    pub fn is_truly_absent(&self) -> bool {
        self.support.is_absent() && self.refutation.is_absent()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvidenceOutcome {
    Supported,
    Refuted,
    Conflicting,
    NotEstablished,
}

impl std::fmt::Display for EvidenceOutcome {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EvidenceOutcome::Supported => write!(f, "supported"),
            EvidenceOutcome::Refuted => write!(f, "refuted"),
            EvidenceOutcome::Conflicting => write!(f, "conflicting"),
            EvidenceOutcome::NotEstablished => write!(f, "not_established"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn vid(n: u8) -> RecordVersionId {
        RecordVersionId::parse(&format!("ver_{:024x}", n)).unwrap()
    }
    #[test]
    fn not_established_has_no_sources() {
        let e = Evidence::not_established();
        assert!(e.is_truly_absent());
        assert_eq!(e.outcome(), EvidenceOutcome::NotEstablished);
        assert!(e.all_sources().is_empty());
    }
    #[test]
    fn supported_evidence() {
        assert_eq!(
            Evidence::supported(vec![vid(1)]).outcome(),
            EvidenceOutcome::Supported
        );
    }
    #[test]
    fn refuted_evidence() {
        assert_eq!(
            Evidence::refuted(vec![vid(3)]).outcome(),
            EvidenceOutcome::Refuted
        );
    }
    #[test]
    fn conflicting_evidence() {
        assert_eq!(
            Evidence::conflicting(vec![vid(1)], vec![vid(2)]).outcome(),
            EvidenceOutcome::Conflicting
        );
    }
    #[test]
    fn not_swaps() {
        assert_eq!(
            Evidence::supported(vec![vid(1)]).negate().outcome(),
            EvidenceOutcome::Refuted
        );
    }
    #[test]
    fn double_negation() {
        let e = Evidence::conflicting(vec![vid(1)], vec![vid(2)]);
        assert!(e.clone().negate().negate().is_definite());
    }
    #[test]
    fn all_conjunction() {
        assert_eq!(
            Evidence::supported(vec![vid(1)])
                .all(Evidence::refuted(vec![vid(2)]))
                .outcome(),
            EvidenceOutcome::Refuted
        );
    }
    #[test]
    fn any_disjunction() {
        assert_eq!(
            Evidence::supported(vec![vid(1)])
                .any(Evidence::refuted(vec![vid(2)]))
                .outcome(),
            EvidenceOutcome::Supported
        );
    }
    #[test]
    fn evidence_bit_or() {
        assert_eq!(
            EvidenceBit::with_source(vid(1))
                .or(EvidenceBit::with_source(vid(2)))
                .sources,
            vec![vid(1), vid(2)]
        );
    }
    #[test]
    fn evidence_bit_and() {
        assert_eq!(
            EvidenceBit::with_sources(vec![vid(1), vid(3)])
                .and(EvidenceBit::with_sources(vec![vid(2), vid(3)]))
                .sources,
            vec![vid(1), vid(2), vid(3)]
        );
    }
    #[test]
    fn idempotence() {
        let a = Evidence::supported(vec![vid(1)]);
        assert!(a.clone().all(a).is_definite());
    }
    #[test]
    fn no_explosion() {
        let c = Evidence::conflicting(vec![vid(1)], vec![vid(2)]);
        assert_eq!(
            c.clone().all(Evidence::not_established()).outcome(),
            EvidenceOutcome::Refuted
        );
        assert_eq!(
            c.clone().any(Evidence::not_established()).outcome(),
            EvidenceOutcome::Supported
        );
    }
    #[test]
    fn deduplicates() {
        let e = Evidence::conflicting(vec![vid(1), vid(1), vid(2)], vec![vid(2), vid(3)]);
        assert_eq!(e.all_sources(), vec![vid(1), vid(2), vid(3)]);
    }
    #[test]
    fn indeterminate_bit() {
        let mut e = EvidenceBit::with_source(vid(1));
        e.sources.clear();
        assert!(e.is_indeterminate());
    }
    #[test]
    fn outcome_display() {
        assert_eq!(format!("{}", EvidenceOutcome::Supported), "supported");
    }
}

#[cfg(test)]
mod truth_table {
    use super::*;
    #[test]
    fn every_pair_matches_spec_31_2() {
        for a in 0..4 {
            for b in 0..4 {
                let evidence = |bits| Evidence {
                    support: EvidenceBit {
                        present: bits & 1 != 0,
                        sources: vec![],
                    },
                    refutation: EvidenceBit {
                        present: bits & 2 != 0,
                        sources: vec![],
                    },
                };
                let (x, y) = (evidence(a), evidence(b));
                let and = x.clone().all(y.clone());
                let or = x.clone().any(y.clone());
                assert_eq!(
                    (and.support.present, and.refutation.present),
                    (
                        x.support.present && y.support.present,
                        x.refutation.present || y.refutation.present
                    )
                );
                assert_eq!(
                    (or.support.present, or.refutation.present),
                    (
                        x.support.present || y.support.present,
                        x.refutation.present && y.refutation.present
                    )
                );
                assert_eq!(x.clone().negate().negate(), x);
            }
        }
    }
}
