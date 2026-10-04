//! Private author drafts use immutable revisions and optimistic concurrency.
//! They never enter the canonical snapshot or the proposal approval lifecycle.
use universe_domain::{ids::*, records::Payload};
use universe_protocol::{
    installation::{DraftContent, SavedDraft},
    ProtocolError,
};
use universe_store::kernel::Kernel;

fn prefix(owner: &ProfileId, continuity: &ContinuityId) -> String {
    format!("draft:{owner}:{continuity}:")
}
pub fn load(
    kernel: &Kernel,
    owner: &ProfileId,
    continuity: &ContinuityId,
) -> anyhow::Result<Option<SavedDraft>> {
    kernel.head(continuity)?;
    let keys = kernel.workflow_keys(&prefix(owner, continuity))?;
    if keys.len() > 10_000 {
        return Err(ProtocolError::EvaluationLimitReached {
            message: "draft history limit reached".into(),
        }
        .into());
    }
    keys.last()
        .map(|key| {
            Ok(serde_json::from_value(
                kernel
                    .workflow_get(key)?
                    .ok_or_else(|| ProtocolError::not_found("draft"))?,
            )?)
        })
        .transpose()
}
pub fn save(
    kernel: &mut Kernel,
    owner: &ProfileId,
    continuity: &ContinuityId,
    expected: u64,
    content: DraftContent,
) -> anyhow::Result<SavedDraft> {
    if serde_json::to_vec(&content.operations)?.len() > 128_000 || content.rationale.len() > 16_000
    {
        return Err(ProtocolError::invalid_argument(
            "draft",
            "draft content exceeds draft size limit",
        )
        .into());
    }
    let records = kernel.records(continuity, &content.base_revision)?;
    if !records.iter().any(|r| {
        r.identity.record_id == content.represented_context
            && matches!(r.payload, Payload::RepresentedContext(_))
    }) {
        return Err(ProtocolError::not_found("draft represented context").into());
    }
    let current = load(kernel, owner, continuity)?;
    let version = current.as_ref().map_or(0, |d| d.version);
    // Recover a lost save response, but never overwrite another window's draft.
    if version != expected {
        if version == expected.saturating_add(1)
            && current.as_ref().is_some_and(|d| d.content == content)
        {
            return Ok(current.unwrap());
        }
        return Err(ProtocolError::BaseRevisionConflict {
            expected: format!("draft:{expected}"),
            actual: format!("draft:{version}"),
        }
        .into());
    }
    if version >= 10_000 {
        return Err(ProtocolError::EvaluationLimitReached {
            message: "draft history limit reached; export the draft before further editing".into(),
        }
        .into());
    }
    let saved = SavedDraft {
        version: version + 1,
        content,
    };
    kernel.workflow_put(&[(
        format!("{}{:020}", prefix(owner, continuity), saved.version),
        serde_json::to_value(&saved)?,
    )])?;
    Ok(saved)
}
