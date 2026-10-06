//! Authoring guidance advertised during MCP initialization, not an authority grant.
const AUTHORING: &str = concat!(
    "Authoring workflow: draft prose is provisional. Before considering prose usable, research the explicitly ",
    "named universe at a pinned continuity/revision and the appropriate story time and ",
    "author/character/narrator/reader perspective. Use universe_get_context and universe_get_state, follow ",
    "pagination, and preserve unknown or restricted evidence. A proposition is a claimable statement, not an ",
    "established fact: use assertions, polarity, scope and active validity as evidence. The state proposition ",
    "catalogue can include statements with inactive assertions. State objects separately return identity and ancestry, shared attributes, instance facts, initial-value candidates, behavioral requirements, rules, exact dependencies, conflicts and unknown applicability. An applicability of null is unresolved, never established. Action requirements enumerate possible owning roles and do not establish action eligibility. No candidate overrides another; initial-value candidates alone never establish current state. Initialization receipts report original admission history, separately from corrected or consumed stock. Retrieval never advances height or refills ammunition. Object coverage describes evidence assembly, not physical or prose completeness.\n\n",
    "Incremental factual authoring uses universe_propose operations introduce_definition, introduce_instance, add_named_attribute, refine_classification and initialize_instance. Introduce only the identity/name and explicit classification/world applicability you know; missing properties stay unknown. add_named_attribute creates or reuses a namespace/key property with the exact declared shape and semantics, then compiles its value and explicit scope/time/precision/basis into canonical proposition/assertion records. Shared definition attributes remain distinct from instance facts. refine_classification retains instance identity and accepts only resolved descendant classification; ambiguous or unrelated changes require explicit authored correction, and physical transformation uses occurred events. initialize_instance explicitly names an occurred instance start, approved initial-value assertion version, scope and interval beginning at that start. Applicable conflicting or unresolved candidates require resolution. Reviewed publication creates separate instance facts and a durable once-only receipt. A mention, scene, rename, classification refinement, holder transfer, definition edit or restart cannot refill stock; absent current stock requires authored evidence, not initialization again. The full batch is reviewed, validated and committed atomically through the usual exact approval path.\n\n",
    "For a proposed stock change with no declared event or coherent correction, inspect the complete validation finding and effective object evidence. If resources.accounting.v1 requires resolution, leave the question open and ask the author; do not infer a cause or turn an unknown into a fact. An explicit author decision may accept only the exact finding fingerprint and resource:<predicate record ID> scope, with the author's authority and rationale. A changed claim or predecessor needs a fresh decision. Acceptance records the unexplained count as canon while preserving its unexplained marker; it does not create an arrival event. Ordinary proposal approval alone cannot answer the factual question.\n\n",
    "Use the exact committed revision for continued research. If context or validation is stale, reopen at head and repeat retrieval and validation. Restricted or incomplete delivery is not evidence of absence: retain its coverage status and request authorized access or author clarification before relying on it. On an interrupted commit, query universe_get_operation with the original idempotency key and recover that receipt; do not submit a new mutation. Then reopen at the receipt's committed revision, retrieve the affected state again, and continue from fresh canon facts.\n\n",
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
    "semantic validation of prose. Protocol 3 separates execution.coverage, submitted_input and assessment. Complete execution means bounded engine checks completed, never manuscript continuity. Source-only and mixed records without a usable selected assessment remain record_candidate/includes_sources=true. Validation reports exact absent, stale or unavailable assessment state; a usable selection yields source_assessed_candidate with byte verification and its declared inventory/conclusion. A declared positive conclusion is assessor provenance, never engine-verified entailment. Historical evidence is unavailable_legacy and requires fresh validation and approval. Restricted validation discloses no input or assessment identifiers. Use universe_propose action attach_assessment to attach an authenticated immutable declaration to a frozen submitted proposal; select_assessment selects an existing attachment or explicitly null to withdraw selection. Supply expected_selection_generation and an exact idempotency_key; replacement never changes the proposal version or digest. Use universe_get_proposal view_group=assessment to review selection, state and the exact envelope, including declared inventory, exclusions, mappings and unresolved material. An exact assessment_reference retrieves authorized history. Follow every cursor: for fragmented delivery concatenate canonical_envelope_utf8 by UTF-8 byte offset and verify the reconstructed body digest. Selection changes invalidate old cursors and each page rechecks current permissions. Review reports assessor declarations separately from byte verification and engine coverage. Completed proposal validation binds the exact selected assessment or absence, selection generation, submitted scope, assessment state and execution digest. Changes to selection, proposal, head or authority during evaluation discard the binding; use a fresh run. Author approval and delegated commit require that exact final binding. Private revalidation compares the same assessment identity or absence and generation; canonical publication checks selection atomically. Replacement or withdrawal requires fresh validation and applicable approval. Assessor conclusions do not add universal admission blockers. Query, pending, interrupted and cancelled results have null final_binding_digest. ",
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
