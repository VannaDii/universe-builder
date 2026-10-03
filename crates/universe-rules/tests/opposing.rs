//! Typed translation of frozen G05 detector outcomes. Expectations below come
//! from docs/decisions/g05-independent-review.md, not from the implementation.
use std::collections::BTreeMap;
use universe_domain::{ids::*, records::*, scope::*, temporal::*, value::*};
use universe_rules::opposing::{detect, Gap, Intersection, Scan};
fn universe() -> UniverseId {
    UniverseId::parse("unv_000000000000000000000001").unwrap()
}
fn rr(n: u64) -> RecordRef {
    RecordRef::new(
        universe(),
        RecordId::parse(&format!("rec_{n:024x}")).unwrap(),
    )
}
fn cal(n: u64) -> CalendarId {
    CalendarId::parse(&format!("cal_{n:024x}")).unwrap()
}
fn world(n: u64) -> WorldId {
    WorldId::parse(&format!("wld_{n:024x}")).unwrap()
}
fn interval(a: i128, b: i128) -> Validity {
    Validity::CalendarInterval {
        calendar: cal(1),
        start: TemporalBound::Exact {
            value: a.to_string(),
        },
        end: TemporalBound::Exact {
            value: b.to_string(),
        },
    }
}
fn record(n: u64, payload: Payload) -> RecordVersion {
    RecordVersion::build(
        RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
        RecordIdentity::new(universe(), rr(n).record, payload.kind()),
        payload,
    )
    .unwrap()
}
fn base() -> Vec<RecordVersion> {
    let mut records = vec![];
    for n in [1, 2, 8, 9] {
        records.push(record(
            n,
            Payload::Entity(Entity {
                names: vec![],
                types: vec![],
                world_associations: vec![],
                labels: BTreeMap::from([("en".into(), "Door".into())]),
                metadata: BTreeMap::new(),
            }),
        ));
    }
    for n in [3, 4] {
        records.push(record(
            n,
            Payload::RepresentedContext(RepresentedContext {
                universe: universe(),
                kind: if n == 3 {
                    RepresentedContextKind::Objective
                } else {
                    RepresentedContextKind::Authored {
                        label: "belief".into(),
                    }
                },
                parent: if n == 4 { Some(rr(3)) } else { None },
                chronology: None,
                labels: BTreeMap::new(),
            }),
        ));
    }
    records.push(record(
        10,
        Payload::Property(PropertyDef {
            namespace: "test".into(),
            key: "open".into(),
            labels: BTreeMap::new(),
            subject_types: vec![],
            value: ValueShape::Boolean,
            multiplicity: Multiplicity::Multiple,
            unit_dimension: None,
            persistence: PersistenceSemantics::ExplicitInterval,
            exclusive: false,
            inverse: None,
            symmetric: false,
            transitive: false,
        }),
    ));
    for n in [20, 21, 22] {
        records.push(record(
            n,
            Payload::Proposition(Proposition {
                predicate: rr(10),
                subject: if n == 22 { rr(2) } else { rr(1) },
                roles: vec![],
                value: Some(Value::bool_(true)),
                quantification: Quantification::Particular,
                context: rr(3),
            }),
        ));
    }
    for (n, polarity) in [(30, Polarity::Support), (31, Polarity::Refutation)] {
        records.push(record(
            n,
            Payload::Assertion(Assertion {
                proposition: rr(20),
                polarity,
                scope: Scope {
                    applicability: Applicability::UniverseWide,
                    context: rr(3),
                    realm: None,
                },
                validity: interval(10, 20),
                persistence: PersistenceSemantics::ExplicitInterval,
                precision: Precision::Exact,
                alternatives: vec![],
                basis: EvidenceBasis::AuthorDecision {
                    note: format!("synthetic {polarity:?}"),
                },
                established_by: None,
            }),
        ));
    }
    records
}
fn modify(records: &mut [RecordVersion], n: u64, f: impl FnOnce(&mut Payload)) {
    let r = records
        .iter_mut()
        .find(|r| r.identity.record_id == rr(n).record)
        .unwrap();
    f(&mut r.payload);
    r.identity.record_kind = r.payload.kind();
    *r = RecordVersion::build(
        r.record_version_id.clone(),
        r.identity.clone(),
        r.payload.clone(),
    )
    .unwrap();
}
fn assertion(records: &mut [RecordVersion], n: u64, f: impl FnOnce(&mut Assertion)) {
    modify(records, n, |p| {
        let Payload::Assertion(a) = p else { panic!() };
        f(a);
    });
}
fn proposition(records: &mut [RecordVersion], n: u64, f: impl FnOnce(&mut Proposition)) {
    modify(records, n, |p| {
        let Payload::Proposition(a) = p else { panic!() };
        f(a);
    });
}
fn scan(records: &[RecordVersion]) -> Scan {
    let expected = detect(&universe(), records, false, 10000).unwrap();
    let indexed = detect(&universe(), records, true, 10000).unwrap();
    assert_eq!(expected.pairs, indexed.pairs);
    assert_eq!(expected.complete, indexed.complete);
    for shift in 0..records.len() {
        let mut changed = records.to_vec();
        changed.rotate_left(shift);
        changed.reverse();
        let actual = detect(&universe(), &changed, true, 10000).unwrap();
        assert_eq!(indexed, actual, "ordering variation {shift}");
    }
    indexed
}
#[test]
fn frozen_identity_context_and_value_oracles() {
    for f in [
        "F01", "F02", "F05", "F06", "F07", "F08", "F09", "F36", "F40", "F42", "F47", "F50",
    ] {
        let mut r = base();
        if ["F02", "F05", "F06", "F07", "F08", "F09", "F42", "F50"].contains(&f) {
            assertion(&mut r, 31, |a| a.proposition = rr(21));
        }
        match f {
            "F05" => proposition(&mut r, 21, |p| p.subject = rr(2)),
            "F06" => {
                modify(&mut r, 10, |p| {
                    let Payload::Property(d) = p else { panic!() };
                    d.value = ValueShape::Decimal;
                });
                for (n, digits) in [(20, "1.0"), (21, "1.00"), (22, "1.0")] {
                    proposition(&mut r, n, |p| {
                        p.value = Some(Value::Decimal {
                            digits: digits.into(),
                        })
                    });
                }
            }
            "F07" => proposition(&mut r, 21, |p| p.quantification = Quantification::Universal),
            "F08" => {
                proposition(&mut r, 21, |p| p.context = rr(4));
                assertion(&mut r, 31, |a| a.scope.context = rr(4));
            }
            "F09" => {
                for n in [20, 21] {
                    proposition(&mut r, n, |p| p.context = rr(4));
                }
                for n in [30, 31] {
                    assertion(&mut r, n, |a| a.scope.context = rr(4));
                }
            }
            "F40" => assertion(&mut r, 31, |a| a.scope.context = rr(4)),
            "F42" => {
                let mut d = r
                    .iter()
                    .find(|r| r.identity.record_id == rr(10).record)
                    .unwrap()
                    .clone();
                d = record(11, d.payload);
                r.push(d);
                proposition(&mut r, 21, |p| p.predicate = rr(11));
            }
            "F50" => proposition(&mut r, 21, |p| {
                p.subject.universe =
                    Some(UniverseId::parse("unv_000000000000000000000002").unwrap())
            }),
            _ => {}
        }
        if f == "F50" {
            assert!(detect(&universe(), &r, true, 1000).is_err());
            continue;
        }
        let result = scan(&r);
        if ["F05", "F07", "F08", "F42"].contains(&f) {
            assert!(result.pairs.is_empty(), "{f}");
        } else {
            assert_eq!(result.pairs.len(), 1, "{f}");
            assert_eq!(result.pairs[0].definite(), f != "F40", "{f}");
        }
        if f == "F02" {
            assert_ne!(
                result.pairs[0].support.proposition.identity.record_id,
                result.pairs[0].refutation.proposition.identity.record_id
            );
        }
    }
}
#[test]
fn frozen_world_and_realm_oracles() {
    let worlds = |ids: &[u64]| Applicability::Worlds {
        world_ids: ids.iter().map(|n| world(*n)).collect(),
    };
    for (f, a, b, expected) in [
        ("F10", worlds(&[1]), worlds(&[2]), Some(worlds(&[]))),
        (
            "F11",
            Applicability::UniverseWide,
            worlds(&[2, 1, 1]),
            Some(worlds(&[1, 2])),
        ),
        ("F12", worlds(&[1, 2]), worlds(&[2, 3]), Some(worlds(&[2]))),
        (
            "F22",
            Applicability::UniverseWide,
            Applicability::Unspecified,
            None,
        ),
        (
            "F23",
            Applicability::UniverseWide,
            Applicability::Conditional,
            None,
        ),
        (
            "F51",
            Applicability::UniverseWide,
            worlds(&[]),
            Some(worlds(&[])),
        ),
    ] {
        let mut r = base();
        assertion(&mut r, 30, |s| s.scope.applicability = a);
        assertion(&mut r, 31, |s| s.scope.applicability = b);
        let s = scan(&r);
        if matches!(&expected,Some(Applicability::Worlds { world_ids }) if world_ids.is_empty()) {
            assert!(s.pairs.is_empty(), "{f}");
        } else {
            assert_eq!(s.pairs[0].applicability, expected, "{f}");
            assert_eq!(s.pairs[0].definite(), expected.is_some());
        }
    }
    for f in ["F13", "F14", "F43", "F41"] {
        let mut r = base();
        if f == "F41" {
            assertion(&mut r, 30, |a| a.scope.applicability = worlds(&[1]));
            assertion(&mut r, 31, |a| {
                a.scope.applicability = worlds(&[2]);
                a.validity = Validity::Unknown;
            });
        } else {
            if f != "F43" {
                assertion(&mut r, 30, |a| a.scope.realm = Some(rr(8)));
            }
            assertion(&mut r, 31, |a| {
                a.scope.realm = Some(rr(if f == "F13" { 9 } else { 8 }))
            });
        }
        let s = scan(&r);
        if ["F13", "F41"].contains(&f) {
            assert!(s.pairs.is_empty());
        } else {
            assert_eq!(s.pairs[0].definite(), f == "F14");
            if f == "F43" {
                assert!(s.pairs[0].gaps.contains(&Gap::Realm));
            }
        }
    }
}
#[test]
fn frozen_temporal_oracles_and_boundary_variations() {
    let instant = |n| Validity::Instant {
        at: TemporalExpression::Exact {
            calendar: cal(1),
            value: format!("{n}"),
        },
    };
    let uncertain = |a, b, end| Validity::CalendarInterval {
        calendar: cal(1),
        start: TemporalBound::BoundedUncertainty {
            lower: format!("{a}"),
            upper: format!("{b}"),
        },
        end: TemporalBound::Exact {
            value: format!("{end}"),
        },
    };
    for (f, v, expected) in [
        ("F15", interval(20, 30), None),
        (
            "F16",
            interval(15, 25),
            Some(Intersection::Exact(interval(15, 20))),
        ),
        ("F17", instant(20), None),
        ("F18", instant(19), Some(Intersection::Exact(instant(19)))),
        (
            "F19",
            Validity::CalendarInterval {
                calendar: cal(2),
                start: TemporalBound::Exact { value: "10".into() },
                end: TemporalBound::Exact { value: "20".into() },
            },
            Some(Intersection::Unresolved),
        ),
        ("F20", uncertain(18, 22, 30), Some(Intersection::Unresolved)),
        ("F21", Validity::Unknown, Some(Intersection::Unresolved)),
        ("F37", interval(10, 10), None),
        ("F39", uncertain(21, 22, 30), None),
        (
            "F48",
            Validity::CalendarInterval {
                calendar: cal(1),
                start: TemporalBound::Unbounded,
                end: TemporalBound::Unbounded,
            },
            Some(Intersection::Exact(interval(10, 20))),
        ),
        (
            "F52a",
            Validity::Interval {
                start: TemporalBound::Exact { value: "10".into() },
                end: TemporalBound::Exact { value: "20".into() },
            },
            Some(Intersection::Unresolved),
        ),
        (
            "F52b",
            Validity::PersistentUntilChanged {
                from: TemporalBound::Exact { value: "10".into() },
            },
            Some(Intersection::Unresolved),
        ),
    ] {
        let mut r = base();
        assertion(&mut r, 31, |a| a.validity = v);
        let s = scan(&r);
        assert_eq!(
            s.pairs.first().map(|p| p.intersection.clone()),
            expected,
            "{f}"
        );
    }
    let mut r = base();
    assertion(&mut r, 31, |a| a.validity = uncertain(12, 14, 18));
    let s = scan(&r);
    assert!(s.pairs[0].definite());
    assert!(!s.complete);
    assert!(
        matches!(&s.pairs[0].intersection,Intersection::Uncertain { guaranteed:Some(v),.. } if v.as_ref()==&interval(14,18))
    );
    for f in ["F25", "F26"] {
        let mut r = base();
        assertion(&mut r, 30, |a| a.validity = Validity::Unspecified);
        if f == "F25" {
            assertion(&mut r, 31, |a| a.validity = Validity::Unspecified);
        }
        assert_eq!(
            scan(&r).pairs[0].intersection,
            if f == "F25" {
                Intersection::Unqualified
            } else {
                Intersection::Unresolved
            }
        );
    }
    // Independent half-open set intersection oracle over 231 interval pairs.
    for start in -10..11 {
        for end in start..11 {
            let mut r = base();
            assertion(&mut r, 30, |a| a.validity = interval(-3, 4));
            assertion(&mut r, 31, |a| a.validity = interval(start, end));
            let s = detect(&universe(), &r, true, 1000).unwrap();
            let ticks: Vec<_> = (start..end).filter(|n| (-3..4).contains(n)).collect();
            assert_eq!(s.pairs.is_empty(), ticks.is_empty());
            if let (Some(first), Some(last)) = (ticks.first(), ticks.last()) {
                assert_eq!(
                    s.pairs[0].intersection,
                    Intersection::Exact(interval(*first, *last + 1))
                );
            }
        }
    }
}
#[test]
fn chains_uncertainty_duplicates_and_snapshot_isolation() {
    let mut r = base();
    let third = record(
        32,
        r.iter()
            .find(|r| r.identity.record_id == rr(31).record)
            .unwrap()
            .payload
            .clone(),
    );
    r.push(third);
    assertion(&mut r, 32, |a| a.validity = Validity::Unknown);
    let s = scan(&r);
    assert_eq!(s.pairs.len(), 2);
    assert_eq!(s.pairs.iter().filter(|p| p.definite()).count(), 1);
    assert_eq!(s.pairs.iter().filter(|p| !p.definite()).count(), 1);
    assert!(!s.complete); // F27
    for f in ["F24", "F53"] {
        let mut r = base();
        assertion(&mut r, 31, |a| {
            a.precision = if f == "F24" {
                Precision::Approximate
            } else {
                Precision::OneOf
            };
            if f == "F53" {
                a.alternatives = vec![Value::bool_(true), Value::bool_(false)];
            }
        });
        let s = scan(&r);
        assert!(!s.pairs[0].definite());
        assert!(s.pairs[0].gaps.contains(&Gap::Precision));
    }
    let r = base();
    let expected = scan(&r);
    let mut duplicate = r.clone();
    duplicate.extend(r.clone());
    assert_eq!(scan(&duplicate), expected); // F30
    for removed in [vec![30], vec![31], vec![30, 31]] {
        let mut candidate = r.clone();
        candidate.retain(|r| {
            !removed
                .iter()
                .any(|n| r.identity.record_id == rr(*n).record)
        });
        assert!(scan(&candidate).pairs.is_empty());
    } // F28/F49
    let old = r.clone();
    let mut corrected = r.clone();
    assertion(&mut corrected, 31, |a| a.validity = interval(20, 25));
    assert!(scan(&corrected).pairs.is_empty());
    assert_eq!(scan(&old), expected); // F29 kernel snapshot boundary
    let pair = &expected.pairs[0];
    assert_eq!(
        pair.support.assertion.record_version_id,
        RecordVersionId::parse(&format!("ver_{:024x}", 30)).unwrap()
    );
    assert_eq!(
        pair.refutation.assertion.record_version_id,
        RecordVersionId::parse(&format!("ver_{:024x}", 31)).unwrap()
    );
    assert!(pair
        .support
        .dependencies
        .iter()
        .any(|r| r.identity.record_id == rr(10).record));
    let mut r = base();
    assertion(&mut r, 31, |a| {
        a.basis = EvidenceBasis::Derivation {
            chain: vec![VersionRef {
                universe: Some(universe()),
                record: rr(1).record,
                version: RecordVersionId::parse(&format!("ver_{:024x}", 999)).unwrap(),
            }],
            evaluator: Some("fixture".into()),
        }
    });
    let s = scan(&r);
    assert!(s.pairs[0].definite());
    assert!(!s.pairs[0].refutation.complete);
    assert!(!s.complete); // direct evidence survives unresolved history
    assert!(!detect(&universe(), &base(), true, 0).unwrap().complete);
}
#[test]
fn role_multisets_are_named_and_preserve_multiplicity() {
    let mut r = base();
    modify(&mut r, 10, |p| {
        *p = Payload::Relation(RelationDef {
            namespace: "test".into(),
            key: "transfer".into(),
            labels: BTreeMap::new(),
            roles: ["donor", "recipient"]
                .iter()
                .map(|name| RoleDef {
                    name: (*name).into(),
                    participant_types: vec![],
                    multiplicity: Multiplicity::Multiple,
                    ordered: false,
                })
                .collect(),
        })
    });
    assertion(&mut r, 31, |a| a.proposition = rr(21));
    for n in [20, 21, 22] {
        proposition(&mut r, n, |p| {
            p.value = None;
            p.roles = vec![
                PropositionRole {
                    role: "donor".into(),
                    participant: rr(1),
                },
                PropositionRole {
                    role: "recipient".into(),
                    participant: rr(2),
                },
            ];
        });
    }
    proposition(&mut r, 21, |p| p.roles.reverse());
    assert!(scan(&r).pairs[0].definite()); // F03
    proposition(&mut r, 21, |p| {
        for role in &mut p.roles {
            role.participant = rr(if role.role == "donor" { 2 } else { 1 });
        }
    });
    assert!(scan(&r).pairs.is_empty()); // F04
    proposition(&mut r, 21, |p| {
        p.roles[0].participant = rr(2);
        p.roles[1].participant = rr(1);
        p.roles.push(p.roles[0].clone());
    });
    assert!(scan(&r).pairs.is_empty());
}

#[test]
fn source_anchor_and_derivation_chains_remain_separate() {
    let mut r = base();
    for offset in [0, 10] {
        r.push(record(
            40 + offset,
            Payload::Source(Source {
                label: format!("source {offset}"),
                external_id: None,
                origin: OriginMetadata::default(),
                versions: vec![rr(41 + offset).record],
            }),
        ));
        r.push(record(
            41 + offset,
            Payload::SourceVersion(SourceVersion {
                source: rr(40 + offset),
                digest: "a".repeat(64),
                media_type: "text/plain".into(),
                byte_size: 1,
                import_actor: PrincipalId::parse("prn_000000000000000000000001").unwrap(),
                import_time: "2026-10-02T19:00:00Z".into(),
                decoding: DecodingDescriptor {
                    encoding: "utf-8".into(),
                    representation: "fixture".into(),
                    byte_length: 1,
                },
                origin: OriginMetadata::default(),
            }),
        ));
        r.push(record(
            42 + offset,
            Payload::Anchor(Anchor {
                source_version: VersionRef {
                    universe: Some(universe()),
                    record: rr(41 + offset).record,
                    version: RecordVersionId::parse(&format!("ver_{:024x}", 41 + offset)).unwrap(),
                },
                locator: AnchorLocator::ByteRange { start: 0, end: 1 },
                excerpt_digest: "b".repeat(64),
                excerpt: "x".into(),
                context: Some(rr(3)),
            }),
        ));
    }
    assertion(&mut r, 30, |a| {
        a.basis = EvidenceBasis::SourceAnchor {
            anchor: rr(42),
            verified: false,
        }
    });
    assertion(&mut r, 31, |a| {
        a.basis = EvidenceBasis::Derivation {
            chain: vec![VersionRef {
                universe: None,
                record: rr(52).record,
                version: RecordVersionId::parse(&format!("ver_{:024x}", 52)).unwrap(),
            }],
            evaluator: Some("fixture.v1".into()),
        }
    });
    let s = scan(&r);
    assert!(s.complete);
    for (chain, present, absent) in [
        (&s.pairs[0].support, [40, 41, 42], [50, 51, 52]),
        (&s.pairs[0].refutation, [50, 51, 52], [40, 41, 42]),
    ] {
        for n in present {
            assert!(chain
                .dependencies
                .iter()
                .any(|r| r.identity.record_id == rr(n).record));
        }
        for n in absent {
            assert!(!chain
                .dependencies
                .iter()
                .any(|r| r.identity.record_id == rr(n).record));
        }
    }
    // Source verification is retained metadata and does not alter opposition.
    assertion(&mut r, 30, |a| {
        a.basis = EvidenceBasis::SourceAnchor {
            anchor: rr(42),
            verified: true,
        }
    });
    assert!(scan(&r).pairs[0].definite());
}
#[test]
fn identity_normalization_value_inequality_and_unresolved_equality() {
    let baseline = scan(&base());
    let mut r = base();
    for n in [20, 21] {
        proposition(&mut r, n, |p| {
            p.subject.universe = None;
            p.context.universe = None;
            p.predicate.universe = None;
        });
    }
    for n in [30, 31] {
        assertion(&mut r, n, |a| {
            a.proposition.universe = None;
            a.scope.context.universe = None;
        });
    }
    let normalized = scan(&r);
    assert!(normalized.pairs[0].definite());
    assert_eq!(normalized.pairs[0].context, baseline.pairs[0].context);
    for (value, gap) in [
        (Some(Value::bool_(false)), false),
        (None, false),
        (
            Some(Value::Decimal {
                digits: "99999999999999999999999999999999999999999999999999999".into(),
            }),
            true,
        ),
    ] {
        let mut r = base();
        assertion(&mut r, 31, |a| a.proposition = rr(21));
        proposition(&mut r, 21, |p| p.value = value);
        let s = scan(&r);
        if gap {
            assert!(s.pairs[0].gaps.contains(&Gap::Equality));
            assert!(!s.pairs[0].definite());
        } else {
            assert!(s.pairs.is_empty());
        }
    }
    let mut r = base();
    assertion(&mut r, 31, |a| a.proposition = rr(21));
    for n in [20, 21] {
        proposition(&mut r, n, |p| {
            p.value = Some(Value::Quantity {
                value: Box::new(Value::Decimal {
                    digits: if n == 20 { "1.0" } else { "1.00" }.into(),
                }),
                unit: UnitId::parse("unit_000000000000000000000001").unwrap(),
            })
        });
    }
    assert!(scan(&r).pairs[0].definite());
    let budget = detect(&universe(), &base(), true, 0).unwrap();
    assert_eq!(budget.gaps, std::collections::BTreeSet::from([Gap::Budget]));
    assert!(!budget.complete);
    let mut ambiguous = base();
    let mut revised = ambiguous[0].clone();
    revised.record_version_id = RecordVersionId::parse("ver_000000000000000000000099").unwrap();
    ambiguous.push(revised);
    assert!(detect(&universe(), &ambiguous, true, 100).is_err());
    let mut mixed = base();
    mixed[0].identity.universe_id = UniverseId::parse("unv_000000000000000000000002").unwrap();
    assert!(detect(&universe(), &mixed, true, 100).is_err());
}

#[test]
fn four_truth_states_and_unrelated_absence_survive_detection() {
    use universe_domain::{frame::*, Expr, Operand};
    use universe_rules::{basic, EvaluationContext, EvaluationIndex, EvidenceOutcome as Outcome};
    let frame = Frame {
        universe: universe(),
        continuity: ContinuityId::parse("cont_000000000000000000000001").unwrap(),
        revision: RevisionId::parse("rev_000000000000000000000001").unwrap(),
        context: rr(3),
        time: FrameTime::At {
            time: TemporalExpression::Exact {
                calendar: cal(1),
                value: "15".into(),
            },
        },
        perspective: Perspective::Author,
        reader_scene: None,
        personal_sequence: None,
    };
    let claim = |subject| Expr::Claim {
        subject: Operand::Record {
            record: rr(subject),
        },
        predicate: "test:open".into(),
        roles: vec![],
        value: Some(Operand::Value {
            value: Value::bool_(true),
        }),
        polarity: Polarity::Support,
        context: Some(Operand::Record { record: rr(3) }),
    };
    for (removed, outcome) in [
        (vec![], Outcome::Conflicting),
        (vec![31], Outcome::Supported),
        (vec![30], Outcome::Refuted),
        (vec![30, 31], Outcome::NotEstablished),
    ] {
        let mut records = base();
        records.retain(|r| {
            !removed
                .iter()
                .any(|n| r.identity.record_id == rr(*n).record)
        });
        let before = records.clone();
        let detected = scan(&records);
        assert_eq!(detected.pairs.len(), usize::from(removed.is_empty()));
        assert_eq!(records, before);
        let index = EvaluationIndex::new(&records);
        for indexed in [false, true] {
            let ctx = EvaluationContext {
                index: if indexed { Some(&index) } else { None },
                frame: Some(&frame),
                base_snapshot: &records,
                candidate_changes: vec![],
                world_scope: None,
            };
            let (e, complete) = basic::evaluate(&claim(1), &ctx);
            assert!(complete);
            assert_eq!(e.outcome(), outcome);
            let (q, complete) = basic::evaluate(&claim(2), &ctx);
            assert!(complete);
            assert_eq!(q.outcome(), Outcome::NotEstablished);
        }
    }
}

#[test]
fn scoped_metacondition_uses_exact_kernel_with_index_candidate_corrections_and_uncertainty() {
    use universe_domain::{
        expr::{Expr, Operand},
        frame::FrameTime,
        Frame,
    };
    let mut records = base();
    let frame: Frame = serde_json::from_value(serde_json::json!({
        "universe":universe(), "continuity":"cont_000000000000000000000001",
        "revision":"rev_000000000000000000000001", "context":rr(3),
        "time":{"kind":"at","time":{"kind":"exact","calendar":cal(1),"value":"12"}}, "perspective":"author"
    })).unwrap();
    let expression = Expr::NoOpposingEvidence {
        subject: Operand::Record { record: rr(1) },
        predicate: "test:open".into(),
        context: Operand::Record { record: rr(3) },
    };
    let run = |records: &[RecordVersion],
               frame: &Frame,
               corrections: Vec<(&RecordId, Option<&RecordVersion>)>,
               indexed| {
        let index = universe_rules::EvaluationIndex::new(records);
        universe_rules::basic::evaluate(
            &expression,
            &universe_rules::EvaluationContext {
                frame: Some(frame),
                base_snapshot: records,
                candidate_changes: corrections,
                index: if indexed { Some(&index) } else { None },
                world_scope: Some(vec![]),
            },
        )
    };
    for indexed in [false, true] {
        let (e, c) = run(&records, &frame, vec![], indexed);
        assert!(c);
        assert_eq!(e.outcome(), universe_rules::EvidenceOutcome::Refuted);
        assert!(e
            .all_sources()
            .contains(&records.last().unwrap().record_version_id));
        let (e, c) = run(&records, &frame, vec![(&rr(31).record, None)], indexed);
        assert!(c);
        assert_eq!(e.outcome(), universe_rules::EvidenceOutcome::Supported);
        let mut later = frame.clone();
        later.time = FrameTime::At {
            time: TemporalExpression::Exact {
                calendar: cal(1),
                value: "20".into(),
            },
        };
        let (e, c) = run(&records, &later, vec![], indexed);
        assert!(c);
        assert_eq!(e.outcome(), universe_rules::EvidenceOutcome::Supported);
    }
    if let Payload::Assertion(a) = &mut records.last_mut().unwrap().payload {
        a.validity = Validity::Unknown;
    }
    let (e, c) = run(&records, &frame, vec![], true);
    assert!(!c);
    assert_eq!(e.outcome(), universe_rules::EvidenceOutcome::NotEstablished);
    // Definition ambiguity must not select whichever record was indexed first.
    let Payload::Property(def) = records
        .iter()
        .find(|r| matches!(r.payload, Payload::Property(_)))
        .unwrap()
        .payload
        .clone()
    else {
        unreachable!()
    };
    records.push(record(90, Payload::Property(def)));
    assert!(!run(&records, &frame, vec![], true).1);
}
