//! Authoring guidance advertised during MCP initialization, not an authority grant.
const AUTHORING: &str = concat!(
    "Authoring workflow: draft prose is provisional. Before considering prose usable, research the explicitly ",
    "named universe at a pinned continuity/revision and the appropriate story time and ",
    "author/character/narrator/reader perspective. Use universe_get_context and universe_get_state, follow ",
    "pagination, and preserve unknown or restricted evidence. A proposition is a claimable statement, not an ",
    "established fact: use assertions, polarity, scope and active validity as evidence. The state proposition ",
    "catalogue can include statements with inactive assertions.\n\n",
    "Translate the prose's material continuity claims and consequences into structured proposal operations: ",
    "facts, event effects, possession, timing, knowledge, and disclosures where applicable. Distinguish ",
    "objective narration from dialogue, beliefs, reports, hypotheticals, and metaphor; do not promote an ",
    "account into objective reality. New or revised events must name a declared action definition. Its ",
    "mandatory attributes are checked on the entity filling each required participant role, at pre-event ",
    "story time and within the declared context/world scope. Research each owning entity's active canon; ",
    "another individual's or object's attributes cannot satisfy its requirements. Direct and explicit ",
    "possession-granted powers share the same evidence checks. Muting/suppression must be canonically ",
    "established for that owner/time; missing or expired evidence is unresolved, not a default value or an ",
    "implicit transfer. An ordinary action declaration cannot be used to disguise a power-dependent action. ",
    "Before committing used prose's material changes, preserve its exact ",
    "immutable source version and supporting UTF-8 passage anchors. Link assertions and explicit knowledge ",
    "to those anchors with source_anchor evidence; link occurred events through legitimate sourced ",
    "observations and depicted-event scene references. ",
    "Check that supporting excerpts depict occurred events as performed, not merely planned, prepared or ",
    "anticipated. Character presence and dialogue alone do not establish explicit knowledge acquisition. ",
    "Bind passage references to exact work editions and the editions to the committed continuity/revision. ",
    "Do not invent a witness merely to attach evidence. Source ",
    "text alone is evidence and does not create executable facts. Source-byte staging requires the author ",
    "workspace.\n\n",
    "Use universe_propose, universe_validate, and universe_get_impact to check the exact candidate against ",
    "canon and affected dependencies. Use scene time for research and an author-perspective ",
    "timeless/all-validities context for proposal admission. Inspect findings as well as coverage: complete ",
    "evaluation can still contain blocking conflicts, and complete context delivery does not establish full ",
    "semantic validation of prose. Protocol 3 separates execution.coverage, submitted_input and assessment. Complete execution means bounded engine checks completed, never manuscript continuity. Source-only and mixed records remain record_candidate/includes_sources=true with assessment=absent. Historical evidence is unavailable_legacy and requires fresh validation and approval. Restricted validation discloses no input or assessment identifiers. Use universe_propose action attach_assessment to attach an authenticated immutable declaration to a frozen submitted proposal; select_assessment selects an existing attachment or explicitly null to withdraw selection. Supply expected_selection_generation and an exact idempotency_key; replacement never changes the proposal version or digest. Use universe_get_proposal view_group=assessment to review selection, state and the exact envelope, including declared inventory, exclusions, mappings and unresolved material. An exact assessment_reference retrieves authorized history. Follow every cursor: for fragmented delivery concatenate canonical_envelope_utf8 by UTF-8 byte offset and verify the reconstructed body digest. Selection changes invalidate old cursors and each page rechecks current permissions. Review reports assessor declarations separately from byte verification and engine coverage. Validation/approval/commit integration remains unavailable. Query and pending results have null final_binding_digest. ",
    " Resolve conflicts and material unknown, unsupported or restricted coverage,",
    " or obtain the author's explicit scoped decision where the engine supports it. Unsupported blocking ",
    "checks cannot be bypassed by claiming approval. Never label unchecked prose continuity-verified.\n\n",
    "Once the author chooses to use the verified prose, its material universe changes must be committed ",
    "through universe_commit with the exact proposal, base revision, validation run, and current authority. ",
    "Exact author approval is required unless a current explicit delegated-commit grant covers the complete ",
    "change. Never invent approval. A draft, proposal, validation result, or source import is not a canon ",
    "commit. Only a successful universe_commit makes changes canon.\n\n",
    "Confirm the commit receipt, recover uncertain outcomes with universe_get_operation and the original ",
    "idempotency key, then reopen a context at the committed revision and verify the resulting state before ",
    "continuing dependent prose. A canon or proposal change requires fresh research/validation and approval as",
    " applicable. Report draft, verified candidate, awaiting approval, and committed status accurately. The ",
    "engine validates supported structured claims. ",
    "For a retcon, trace the conservative impact closure through evidence anchors to affected passages, ",
    "resolve downstream state and knowledge times, create a new source/work edition, and preserve historical ",
    "revisions and original exact sources. Citation verification establishes byte identity, not truth. These ",
    "instructions do not guarantee that an external model extracts every implication or follows the workflow.",
);

pub fn instructions(fixture: bool) -> String {
    let mode = if fixture {
        "Explicit universe required on every tool call. This is a disposable read/propose fixture: state, validation, impact and canonical commit are unavailable. Prose cannot complete the verified authoring workflow in fixture mode."
    } else {
        "Explicit universe required on every tool call. Persistent mode authenticates a profile and enforces current grants, pinned context, validation and exact author approval or an explicit bounded delegated-commit grant."
    };
    format!("{mode}\n\n{AUTHORING}")
}
