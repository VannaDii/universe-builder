//! Typed citation links. Exact excerpt verification remains in Workflow::verify_sources.
use std::collections::BTreeMap;
use universe_domain::{ids::RecordId, records::Payload, scope::EvidenceBasis};
use universe_protocol::ProtocolError;

pub(crate) fn validate_links(
    payload: &Payload,
    records: &BTreeMap<&RecordId, &Payload>,
) -> anyhow::Result<()> {
    let basis = match payload {
        Payload::Assertion(r) => Some(&r.basis),
        Payload::EpistemicAttitude(r) => Some(&r.basis),
        Payload::Observation(r) => Some(&r.basis),
        _ => None,
    };
    let citation = match basis {
        Some(EvidenceBasis::SourceAnchor { anchor, .. }) => Some(anchor),
        _ => match payload {
            Payload::PassageRef(r) => r.anchor.as_ref(),
            _ => None,
        },
    };
    if citation.is_some_and(|r| !matches!(records.get(&r.record), Some(Payload::Anchor(_)))) {
        return Err(ProtocolError::invalid_argument(
            "provenance.anchor",
            "source evidence and passage citations must reference an anchor record",
        )
        .into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use universe_domain::ids::UniverseId;
    use universe_domain::value::RecordRef;

    #[test]
    fn passage_cannot_use_an_entity_as_a_source_anchor() {
        let u = UniverseId::parse("unv_000000000000000000000001").unwrap();
        let id = RecordId::parse("rec_000000000000000000000001").unwrap();
        let entity: Payload = serde_json::from_value(json!({"record_kind":"entity","names":[],
            "classification":null,"classificationResolution":"unclassified","worldAssociations":[],"labels":{},"metadata":{}}))
        .unwrap();
        let map = BTreeMap::from([(&id, &entity)]);
        let passage: Payload = serde_json::from_value(json!({"record_kind":"passage_ref",
            "workVersion":{"universe":u,"record":id,"version":"ver_000000000000000000000001"},
            "passageId":"scene-1","anchor":RecordRef::new(u, id.clone())}))
        .unwrap();
        assert!(validate_links(&passage, &map).is_err());
    }

    #[test]
    fn source_anchor_flag_does_not_let_an_entity_become_evidence() {
        let u = "unv_000000000000000000000001";
        let id = RecordId::parse("rec_000000000000000000000001").unwrap();
        let entity: Payload = serde_json::from_value(json!({"record_kind":"entity","names":[],
            "classification":null,"classificationResolution":"unclassified","worldAssociations":[],"labels":{},"metadata":{}}))
        .unwrap();
        let map = BTreeMap::from([(&id, &entity)]);
        for verified in [true, false] {
            let observation: Payload = serde_json::from_value(json!({"record_kind":"observation",
                "observer":{"universe":u,"record":id},"observed":{"universe":u,"record":id},
                "sensoryAccess":true,"time":{"kind":"exact","calendar":"cal_000000000000000000000001","value":"12"},
                "basis":{"kind":"source_anchor","anchor":{"universe":u,"record":id},"verified":verified}})).unwrap();
            assert!(validate_links(&observation, &map).is_err());
        }
    }
}
