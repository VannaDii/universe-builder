//! Opt-in authored transmission chronology. No receipt or clock mapping inference.
use universe_domain::{
    expr::Expr, ids::FindingFingerprint, records::*, scope::*, temporal::TemporalExpression,
};
use universe_protocol::{
    response::{Coverage, EvidenceOutcome, Finding},
    ProtocolError,
};

pub(crate) const CAPABILITY: &str = "communications.chronology.v1";
fn invalid(message: &str) -> anyhow::Error {
    ProtocolError::invalid_argument("channelChronology", message).into()
}
pub(crate) fn validate_rule(rule: &Rule) -> anyhow::Result<()> {
    let declared = rule.capabilities.iter().any(|c| c == CAPABILITY);
    let Some(contract) = &rule.channel_chronology else {
        if declared {
            return Err(invalid(
                "chronology capability requires an authored channel contract",
            ));
        }
        return Ok(());
    };
    if !rule.executable
        || rule.kind != RuleKind::PhysicalConstraint
        || rule.commit_policy != CommitPolicy::AlwaysBlock
        || rule.applicability != Applicability::UniverseWide
        || rule.validity != Validity::Unspecified
        || !rule.subject_types.is_empty()
        || !rule.target_predicates.is_empty()
        || rule.expression != (Expr::Lit { value: true })
        || rule.capabilities != [CAPABILITY]
        || contract.channel.trim().is_empty()
        || contract.channel.len() > 256
    {
        return Err(invalid("chronology needs an executable universe-wide physical constraint with always_block, unspecified validity, literal true and only its capability"));
    }
    let parse = |s: &Option<String>| -> anyhow::Result<Option<i128>> {
        s.as_ref()
            .map(|s| {
                s.parse::<i128>()
                    .map_err(|_| invalid("delay must be signed i128 clock ticks"))
            })
            .transpose()
    };
    let (minimum, maximum) = (
        parse(&contract.minimum_delay)?,
        parse(&contract.maximum_delay)?,
    );
    if minimum.zip(maximum).is_some_and(|(a, b)| a > b)
        || contract.forward_only && maximum.is_some_and(|b| b < 0)
    {
        return Err(invalid("authored delay bounds are inconsistent"));
    }
    Ok(())
}
fn delay(c: &Communication) -> Option<i128> {
    if c.actual_recipients.is_empty() {
        return None;
    }
    match (&c.sent_at, c.received_at.as_ref()?) {
        (
            TemporalExpression::Exact {
                calendar: a,
                value: sent,
            },
            TemporalExpression::Exact {
                calendar: b,
                value: received,
            },
        ) if a == b => received
            .parse::<i128>()
            .ok()?
            .checked_sub(sent.parse::<i128>().ok()?),
        _ => None,
    }
}
/// Reassess every communication, including unchanged records when rules change.
/// Without authored contracts this lane is inactive, preserving legacy admission.
/// Once active, uncovered channels stay unresolved rather than assumed forward.
pub(crate) fn assess(records: &[RecordVersion]) -> Vec<Finding> {
    let policies: Vec<_> = records
        .iter()
        .filter_map(|r| match &r.payload {
            Payload::Rule(rule) => rule.channel_chronology.as_ref().map(|c| (r, c)),
            _ => None,
        })
        .collect();
    if policies.is_empty() {
        return vec![];
    }
    let mut findings = Vec::new();
    for row in records {
        let Payload::Communication(c) = &row.payload else {
            continue;
        };
        let matching: Vec<_> = policies
            .iter()
            .filter(|(_, p)| c.channel.as_ref() == Some(&p.channel))
            .collect();
        if matching.is_empty() {
            findings.push(Finding {
                fingerprint: FindingFingerprint(String::new()),
                rule_id: row.identity.record_id.clone(),
                outcome: EvidenceOutcome::NotEstablished,
                evidence: vec![row.record_version_id.clone()],
                coverage: Coverage::Unsupported,
            });
        }
        for (rule_row, contract) in matching {
            let d = delay(c);
            let pass = d.map(|d| {
                (!contract.forward_only || d >= 0)
                    && contract
                        .minimum_delay
                        .as_ref()
                        .is_none_or(|m| m.parse::<i128>().is_ok_and(|m| d >= m))
                    && contract
                        .maximum_delay
                        .as_ref()
                        .is_none_or(|m| m.parse::<i128>().is_ok_and(|m| d <= m))
            });
            findings.push(Finding {
                fingerprint: FindingFingerprint(String::new()),
                rule_id: rule_row.identity.record_id.clone(),
                outcome: match pass {
                    Some(true) => EvidenceOutcome::Supported,
                    Some(false) => EvidenceOutcome::Refuted,
                    None => EvidenceOutcome::NotEstablished,
                },
                evidence: vec![
                    rule_row.record_version_id.clone(),
                    row.record_version_id.clone(),
                ],
                coverage: if pass.is_some() {
                    Coverage::Complete
                } else {
                    Coverage::Unsupported
                },
            });
        }
    }
    findings
}
