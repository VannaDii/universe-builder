# ADR-0006: Declared actions and owning-entity attributes

Status: Accepted. Vanna approved the action-to-power binding on October 2, 2026,
and requested the same ownership discipline for attributes generally.

## Decision

Add an author-controlled `action_definition` record and `define_action` operation
inside the existing universe/proposal/validation/commit architecture. Each
definition declares mandatory `{role, predicate, value}` attribute requirements,
represented context, world applicability and validity. An empty requirement list
explicitly declares an ordinary action; labels and prose never supply physics.

New and revised events must reference a declared action. Each required role must
identify exactly one individual or object. The service resolves the required
value against that entity's exact pre-event evidence, in every affected world,
and within the action's context. Optional event prerequisites supplement these
requirements and cannot omit or substitute them. An event's own effects cannot
grant a prerequisite retroactively.

Direct and possession-derived attributes share the rules evaluator. A held item
grants only its explicitly defined recipient the declared value, while both
custody and grant validity apply. It does not empower the item, bystanders,
previous holders or another world implicitly. Complete positive evidence chains
remain attached to the exact owning entity. Conflicting or unresolved custody
cannot grant a power, even when a query requests only one competing holder.

Attributes retain their authored intervals/persistence and historical versions;
there is no default value or inheritance from another entity. Explicit active
refutation of a recipient's granted value suppresses an indirect grant; a
supported Boolean false also suppresses a granted Boolean true. An unknown
suppression interval cannot authorize use. The grant can become usable after an
explicit suppression interval ends, provided custody and the grant still apply.
Direct positive evidence must be explicitly ended or superseded when canon
changes; conflicting positive/negative evidence blocks an action. Missing or
expired evidence remains unresolved, not automatically false or "muted."

For action definitions only, unspecified validity means a revision-wide
declaration of action vocabulary. It does not make an entity's unspecified
attribute validity usable at a particular story time.

## Compatibility and authority

The optional event field is omitted when absent so historical payload bytes and
digests remain unchanged. Existing actionless events remain readable. Creating,
adopting or revising an event requires a declared action; untouched legacy events
are not retrospectively certified. Definitions use existing protected grants,
exact revision/validation bindings and author approval or bounded delegation.
Definition changes revalidate existing bound events and expose retcon impact.
No new public MCP tool, model role or manuscript editor is introduced.

Existing synthetic fixtures explicitly declare ordinary actions. The production
compiler never silently fills an omitted action. The author event form requires
an action selection and exposes a small typed action-definition form; multiple
or complex value requirements use the same typed contract.

## Limits and verification

The engine checks structured actions and attributes. Calling an extraordinary
action ordinary, or failing to extract an attribute from prose, is a semantic
interpretation error requiring prose review. It cannot be solved by inferring
physics from a display label. Unrestricted manuscript extraction and native UI
qualification remain separate evidence gates.

Regression coverage includes direct character/object powers, item grants,
wrong-owner and omitted-requirement bypasses, undeclared/expired/muted powers,
restoration, custody conflicts/unknowns/transfers, scalar attribute ownership,
exact pre-event boundaries, world/context scope, ambiguous roles, historical
decoding and self-grant rejection. See the dated execution evidence in
novel readiness.

The scoped G02 qualification adds
authored breathing/consciousness requirements, legal undead speech and body
movement, exact incapacity/restoration boundaries, unknown evidence and earlier
incapacity retcon proofs using this same decision.
