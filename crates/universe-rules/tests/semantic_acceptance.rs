//! Authored evidence scenarios; expected outcomes are stated independently of the evaluator.
use serde_json::{json, Value};
use universe_domain::{frame::*, ids::*, records::*, scope::*, Expr};
use universe_rules::{basic, EvaluationContext, EvidenceOutcome as Outcome};
fn id(n: usize) -> String {
    format!("rec_{n:024x}")
}
fn rr(n: usize) -> Value {
    json!({"universe":"unv_000000000000000000000001","record":id(n)})
}
fn exact(t: i32) -> Value {
    json!({"kind":"exact","calendar":"cal_000000000000000000000001","value":t.to_string()})
}
fn interval(a: i32, b: i32) -> Value {
    json!({"kind":"calendar_interval","calendar":"cal_000000000000000000000001","start":{"kind":"exact","value":a.to_string()},"end":{"kind":"exact","value":b.to_string()}})
}
fn scope(context: usize) -> Value {
    json!({"applicability":{"kind":"universe_wide"},"context":rr(context)})
}
struct Fixture {
    records: Vec<RecordVersion>,
    frame: Frame,
}
impl Fixture {
    fn new() -> Self {
        let mut h = Self { records: vec![], frame: serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":rr(99),"time":{"kind":"timeless"},"perspective":"author"})).unwrap() };
        h.add(1,json!({"record_kind":"property","namespace":"story","key":"siblings","labels":{},"value":{"kind":"entity_ref","subject_types":[]},"multiplicity":"multiple","persistence":"unspecified","exclusive":false,"symmetric":false,"transitive":false}));
        h
    }
    fn add(&mut self, n: usize, p: Value) {
        let p: Payload = serde_json::from_value(p).unwrap();
        let v = RecordVersion::build(
            RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
            RecordIdentity::new(
                self.frame.universe.clone(),
                RecordId::parse(&id(n)).unwrap(),
                p.kind(),
            ),
            p,
        )
        .unwrap();
        let roundtrip: RecordVersion =
            serde_json::from_slice(&serde_json::to_vec(&v).unwrap()).unwrap();
        assert_eq!(roundtrip, v);
        self.records.push(v);
    }
    fn query(&self, q: Value) -> (Outcome, bool) {
        let expr: Expr = serde_json::from_value(q).unwrap();
        let (e, c) = basic::evaluate(
            &expr,
            &EvaluationContext {
                frame: Some(&self.frame),
                base_snapshot: &self.records,
                candidate_changes: vec![],
                index: None,
                world_scope: None,
            },
        );
        (e.outcome(), c)
    }
    fn at(&mut self, t: i32) {
        self.frame.time = serde_json::from_value(json!({"kind":"at","time":exact(t)})).unwrap();
    }
    fn proposition(&mut self, n: usize, context: usize, target: usize) {
        self.add(n,json!({"record_kind":"proposition","subject":rr(80),"predicate":rr(1),"roles":[],"value":{"kind":"entity_ref","ref":rr(target)},"quantification":"particular","context":rr(context)}));
    }
    fn assertion(&mut self, n: usize, p: usize, context: usize, polarity: &str, validity: Value) {
        self.add(n,json!({"record_kind":"assertion","attributeMode":"instance","proposition":rr(p),"polarity":polarity,"scope":scope(context),"validity":validity,"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Explicit authored evidence"}}));
    }
    fn closed(&mut self, n: usize, validity: Value) {
        self.add(n,json!({"record_kind":"completeness","subject":rr(80),"predicate":"story:siblings","members":[],"completeness":"objective_reality","validity":validity,"scope":scope(99)}));
    }
}
fn claim(context: Option<usize>) -> Value {
    let mut q = json!({"kind":"claim","subject":{"kind":"record","ref":rr(80)},"predicate":"story:siblings","roles":[],"value":{"kind":"value","value":{"kind":"entity_ref","ref":rr(81)}},"polarity":"support"});
    if let Some(c) = context {
        q["context"] = json!({"kind":"record","ref":rr(c)});
    }
    q
}
#[test]
fn s11_s12_s13_missing_is_not_empty_and_completeness_expires() {
    let mut h = Fixture::new();
    assert_eq!(h.query(claim(None)), (Outcome::NotEstablished, true));
    h.closed(10, json!({"kind":"unspecified"}));
    assert_eq!(h.query(claim(None)), (Outcome::Refuted, true));
    h.records.pop();
    h.closed(11, interval(1, 2));
    h.at(1);
    assert_eq!(h.query(claim(None)), (Outcome::Refuted, true));
    h.at(2);
    assert_eq!(h.query(claim(None)), (Outcome::NotEstablished, true));
    if let Payload::Completeness(c) = &mut h.records[1].payload {
        c.completeness = CompletenessKind::ObserverKnown {
            observer: EntityIdAlias(RecordId::parse(&id(90)).unwrap()),
        };
    }
    h.at(1);
    assert_eq!(h.query(claim(None)), (Outcome::NotEstablished, true));
}
#[test]
fn s14_s15_accounts_conflict_locally_without_explosion_or_objective_promotion() {
    let mut h = Fixture::new();
    h.proposition(2, 97, 81);
    h.proposition(3, 98, 81);
    h.assertion(4, 2, 97, "support", json!({"kind":"unspecified"}));
    h.assertion(5, 3, 98, "refutation", json!({"kind":"unspecified"}));
    assert_eq!(h.query(claim(None)), (Outcome::NotEstablished, true));
    assert_eq!(h.query(claim(Some(97))), (Outcome::Supported, true));
    assert_eq!(h.query(claim(Some(98))), (Outcome::Refuted, true));
    h.proposition(6, 99, 81);
    h.assertion(7, 6, 99, "support", json!({"kind":"unspecified"}));
    h.assertion(8, 6, 99, "refutation", json!({"kind":"unspecified"}));
    assert_eq!(h.query(claim(None)), (Outcome::Conflicting, true));
    let mut unrelated = claim(None);
    unrelated["value"]["value"]["ref"] = rr(82);
    assert_eq!(h.query(unrelated), (Outcome::NotEstablished, true));
}
#[test]
fn s16_s33_s34_false_belief_presence_and_transmission_do_not_produce_knowledge() {
    let mut h = Fixture::new();
    h.proposition(2, 99, 81);
    h.assertion(3, 2, 99, "refutation", interval(0, 10));
    h.at(5);
    h.add(4,json!({"record_kind":"epistemic_attitude","holder":rr(90),"proposition":rr(2),"attitude":"believes","certainty":null,"validity":interval(0,10),"basis":{"kind":"author_decision","note":"Mistaken belief"}}));
    h.add(5,json!({"record_kind":"observation","observer":rr(90),"observed":rr(80),"sensoryAccess":false,"time":exact(2),"interpretation":null,"basis":{"kind":"author_decision","note":"Presence only"}}));
    h.add(6,json!({"record_kind":"communication","sender":rr(80),"intendedRecipients":[rr(90)],"actualRecipients":[],"content":[rr(2)],"channel":"letter","sentAt":exact(3),"receivedAt":null,"distorted":false}));
    let q = |a| json!({"kind":"attitude","holder":rr(90),"proposition":rr(2),"attitude":a});
    assert_eq!(h.query(q("believes")), (Outcome::Supported, true));
    assert_eq!(h.query(q("knows")), (Outcome::NotEstablished, true));
    assert_eq!(h.query(claim(None)), (Outcome::Refuted, true));
}
#[test]
fn s21_treaty_has_multiple_signatories_guarantor_and_beneficiary() {
    let mut h = Fixture::new();
    h.records.clear();
    h.add(1,json!({"record_kind":"relation","namespace":"story","key":"treaty","labels":{},"roles":[{"name":"signatory","participantTypes":[],"multiplicity":"multiple","ordered":false},{"name":"guarantor","participantTypes":[],"multiplicity":"single","ordered":false},{"name":"beneficiary","participantTypes":[],"multiplicity":"multiple","ordered":false}]}));
    h.add(2,json!({"record_kind":"proposition","subject":rr(80),"predicate":rr(1),"roles":[{"role":"signatory","participant":rr(81)},{"role":"signatory","participant":rr(82)},{"role":"guarantor","participant":rr(83)},{"role":"beneficiary","participant":rr(84)}],"value":null,"quantification":"particular","context":rr(99)}));
    h.assertion(3, 2, 99, "support", json!({"kind":"unspecified"}));
    for (role, n) in [
        ("signatory", 81),
        ("signatory", 82),
        ("guarantor", 83),
        ("beneficiary", 84),
    ] {
        assert_eq!(h.query(json!({"kind":"role_holds","subject":{"kind":"record","ref":rr(80)},"predicate":"story:treaty","role":role,"participant":{"kind":"record","ref":rr(n)}})),(Outcome::Supported,true));
    }
    assert_eq!(h.query(json!({"kind":"role_holds","subject":{"kind":"record","ref":rr(80)},"predicate":"story:treaty","role":"guarantor","participant":{"kind":"record","ref":rr(81)}})),(Outcome::NotEstablished,true));
}
#[test]
fn s25_s26_s27_s30_uncertainty_half_open_and_independent_calendars() {
    let mut h = Fixture::new();
    h.proposition(2, 99, 81);
    h.assertion(3, 2, 99, "support", interval(10, 20));
    h.at(19);
    assert_eq!(h.query(claim(None)), (Outcome::Supported, true));
    h.at(20);
    assert_eq!(h.query(claim(None)), (Outcome::NotEstablished, true));
    if let Payload::Assertion(a) = &mut h.records[2].payload {
        a.validity=serde_json::from_value(json!({"kind":"calendar_interval","calendar":"cal_000000000000000000000001","start":{"kind":"bounded_uncertainty","lower":"9","upper":"11"},"end":{"kind":"exact","value":"20"}})).unwrap();
    }
    h.at(10);
    assert_eq!(h.query(claim(None)), (Outcome::NotEstablished, false));
    if let Payload::Assertion(a) = &mut h.records[2].payload {
        a.validity = Validity::Unknown;
    }
    assert_eq!(h.query(claim(None)), (Outcome::NotEstablished, false));
    if let Payload::Assertion(a) = &mut h.records[2].payload {
        let mut t = interval(0, 20);
        t["calendar"] = json!("cal_000000000000000000000002");
        a.validity = serde_json::from_value(t).unwrap();
    }
    assert_eq!(h.query(claim(None)), (Outcome::NotEstablished, false));
}
#[test]
fn e06_finite_quantification_requires_completeness_for_absence() {
    let h = Fixture::new();
    for (quantifier, complete, expected) in [
        ("exists", false, Outcome::NotEstablished),
        ("exists", true, Outcome::Refuted),
        ("for_all", false, Outcome::NotEstablished),
        ("for_all", true, Outcome::Supported),
    ] {
        assert_eq!(h.query(json!({"kind":"quantify","variable":"x","over":{"kind":"value","value":{"kind":"set","items":[]}},"complete":complete,"quantifier":quantifier,"body":{"kind":"lit","value":true}})),(expected,true));
    }
}

#[test]
fn numeric_ranges_require_agreement_and_respect_open_endpoints_and_units() {
    use universe_domain::{expr::Comparator, value::Value as V};
    let n = |i| V::Integer {
        digits: format!("{i}"),
    };
    let range = |a, b, closed| V::Range {
        lower: Box::new(n(a)),
        upper: Box::new(n(b)),
        lower_inclusive: true,
        upper_inclusive: closed,
        unit: None,
    };
    assert_eq!(
        basic::compare(&range(1, 5, true), Comparator::Lt, &n(5)),
        None
    );
    assert_eq!(
        basic::compare(&range(1, 5, false), Comparator::Lt, &n(5)),
        Some(true)
    );
    assert_eq!(
        basic::compare(&range(1, 5, true), Comparator::Neq, &n(3)),
        None
    );
    assert_eq!(
        basic::compare(&range(1, 5, true), Comparator::Eq, &n(9)),
        Some(false)
    );
    for a in -3..3 {
        for b in a..4 {
            for c in -3..4 {
                let actual = basic::compare(&range(a, b, true), Comparator::Lt, &n(c));
                let answers: Vec<_> = (a..=b).map(|n| n < c).collect();
                let expected = if answers.iter().all(|x| *x) {
                    Some(true)
                } else if answers.iter().all(|x| !*x) {
                    Some(false)
                } else {
                    None
                };
                assert_eq!(actual, expected, "seed a={a} b={b} c={c}");
            }
        }
    }
    let mut measured = range(1, 5, true);
    if let V::Range { unit, .. } = &mut measured {
        *unit = Some(UnitId::parse("unit_000000000000000000000001").unwrap());
    }
    assert_eq!(basic::compare(&measured, Comparator::Lt, &n(10)), None);
}
