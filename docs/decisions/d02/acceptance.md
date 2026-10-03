# Frozen D02 acceptance fixtures

October 3, 2026. Candidate test cases from the earlier proposal, not observed engine outcomes. Only the behavior in [approved D02](../d02-action-consequences.md) is authoritative. Technical restrictions in these cases are suggestions, not additional approved requirements. Adapt implementation-specific cases to the approved behavior; failed qualification does not authorize changing that behavior.

## Setup and concrete inputs

`payloads.json` provides complete proposed action/event/proposition bodies. Create same-universe entity records 1 (actor/sender), 5 (recipient), 6 (bystander); context 10; world record corresponding to world 20; exact integer-tick calendar 9. Property 2 is `d02.stock`, single, Integer, explicit_interval; property 3 is `d02.invulnerable`, single Boolean; property 4 is `d02.charged`, single Boolean. No implicit powers, assertions, conversions or world membership supply stock. Each fixture starts independently; install only the indicated pre-evidence and action. For a transfer, senderFive and recipientOne replace oneStock. Pre-evidence ends at 10 explicitly; at the pre-event boundary it is usable, and ordinary queries at 10 see only the new generated value. Generated resource balances have unbounded authored end, then are shortened only by later generated effects. Assertions for conditions can remain active or use the shown interval. OneStock ends at 10 in accepted occurred-event examples; missing/rejected events publish neither that ending nor any post-state changes.

Existing `define_action`, `define_proposition`, `record_event` operation records wrap the shown bodies. Assigned event/proposition IDs are frozen by existing proposal compilation. The shown action/proposition refs stand for those assignments; no production identity is asserted. Existing refs on preEvidence must be installed via existing author assertion operations; exact payloads are the normalized candidate. `expansion_version` is shown on the canonical event, assigned by the compiler. No manual generated-assertion operation is sent.

For resources, expected post evidence is exactly one generated support assertion per slot at `events::effect_id(eventID,slot)`, with event/slot provenance, precision exact, no alternatives and explicit_interval persistence. Scope and validity exactly match the admitted effect after compiler interval reconciliation. Transfer debit+credit either both publish or neither does. Grant valid at 10 and 12, expired at 13; no automatic Boolean false assertion on expiry. Fire pre(10)=1, post(10)=0; second at 11 must read zero. A proposed second legitimate fire needs a replenishment or a separately established stock change.

## Required results

| ID | Frozen stimulus | Expected admission and reason |
|---|---|---|
| F01 | fire, oneStock, consume post 0 | Admit; 1−1=0, correct actor/property/unit/scope/slot. |
| F02 | F01 with effects empty | Reject missing required consume; never auto-insert decrement. |
| F03 | F01 with consume proposition 40 (post 1) | Reject exact post mismatch; 1−1 is 0. |
| F04 | fire with exact pre stock 0, post 0 | Reject underflow; calculated −1 lies below 0. |
| F05 | fire with proposition 40 but no supporting pre assertion | Unresolved and deny; proposition is not stock evidence. |
| F06 | fire with expired/unknown-time/range/alternatives or conflicting pre balance | Unresolved and deny; cannot choose favorable balance or zero. |
| F07 | walk plus grant effect targeting proposition 42 | Reject unlisted effect, even with supported charged=true. |
| F08 | enchant with charged, recipient=5, proposition 42, end 13 | Admit; declared recipient alone receives true for [10,13). |
| F09 | F08 grant targets proposition 43 (bystander=6) | Reject wrong recipient; presence of bystander as another participant changes nothing. |
| F10 | F08 actor and recipient bindings swapped, retaining proposition 42 | Reject wrong target; cannot borrow original actor's condition evidence. |
| F11 | F08 with actor.charged=false uniquely supported, grant omitted | Admit conditional absence; no power asserted. |
| F12 | F11 with grant present | Reject disabled effect. |
| F13 | enchant, no usable charged evidence, grant omitted | Unresolved and deny; absence cannot skip conditional requirement. |
| F14 | F08 changed to optional, condition true, grant omitted | Admit; optional effect choice is explicit in protected definition. |
| F15 | F14 unknown condition, grant omitted | Unresolved and deny; optional does not conceal ambiguous activation. |
| F16 | F08 grant unbounded/end 14/order 1/refutation | Reject each mutation separately against declared end 13/order 0/support. |
| F17 | transfer sender 5 units, recipient 1 unit, debit/credit post 3/3 | Admit atomically; 5−2=3, 1+2=3, total 6 unchanged. |
| F18 | F17 missing credit or credit to bystander; sender=recipient alias | Reject each separately; required paired slots and distinct resolved state keys. |
| F19 | replenish actor pre 1, post 4 | Admit; explicitly authorized source action, 1+3=4. |
| F20 | replenish pre 8, submitted post 10 | Reject; calculated 11 exceeds maximum, clipping forbidden. |
| F21 | balance/delta max signed i128 plus 1 under wide authored bounds | Reject checked overflow; no wraparound. |
| F22 | Integer/Quantity, wrong unit, decimal/rational magnitude, unresolved conversion | Reject unsupported shape/unit or unresolved evidence; no float conversion. Same exact-unit integer Quantity control admits. |
| F23 | two fires at 10, same actor stock=1, each proposes 0 | Reject simultaneous shared-resource use, including identical post-values. Changing record IDs/array order/sequence cannot admit. |
| F24 | fires at 10 and 11 from stock=1, second proposes 0 | Reject second: 0−1=−1. From stock=2, posts 1 then 0 admit. |
| F25 | same-time fire actors 1 and 5 each own one unit in disjoint keys | Admit if no shared condition/requirement dependency. |
| F26 | same-time grant writes the charged condition another action reads | Reject read/write dependency; distinct times required, regardless of list order. |
| F27 | another world/context/realm effect; consume in only one of two event worlds | Reject scope mismatch. Two worlds pre=1/2 but shared submitted post=0 also reject. |
| F28 | same resource across universe-wide and world-local simultaneous events | Reject scope overlap; world-local effects in disjoint worlds may commute. |
| F29 | event's own charged effect is its enchant condition/prerequisite | Reject self-bootstrap; pre-event evidence only. |
| F30 | duplicate role/slot/order, nonentity owner, nonparticular proposition, relation roles | Reject each separately; closed v1 target contract. |
| F31 | planned/predicted/reported/hypothetical fire with effects | Validate contract structure/bindings and reject unlisted effects; no stock debit or objective assertions. Do not require actual pre-balance/condition truth or present required effects until occurrence is changed to occurred; revalidate then. |
| F32 | independent edit/delete/adopt of generated consume assertion | Reject through existing event-only mutation guard; revise/tombstone its event instead. |
| F33 | untouched legacy action/event during unrelated proposal | Readable, historical bytes/digest unchanged; consequence coverage exclusion visible. Existing structural constraints still apply. |
| F34 | new/adopted/revised action lacking contract or event referencing contractless action | Reject; no ordinary-action silent fallback. Empty explicit contract with no effects admits. |
| F35 | add contract to old definition; unchanged fire omits consumption | Reject migrated candidate; corrected event admits only with exact new approval. |
| F36 | revise contracted definition to remove contract; adopt old definition over it | Reject downgrade. Empty-contract retcon with existing effects rejects bound events. |
| F37 | retcon earlier stock 2→1 with unchanged fires at 10/11 (posts 1/0) | Reject both mismatched dependent transitions; separately remove each fire to demonstrate the other remains invalid. Old edition unchanged. |
| F38 | revise delta −1→−2, predicate/unit/scope/expiry or condition evidence | Revalidate unchanged bound events; prior approval/validation cannot authorize changed candidate. |
| F39 | ordinary delegate tries changing contract; credit outside entity/predicate/world grant | Deny authority regardless of correct arithmetic; protected definition still needs installation-author exact approval. |
| F40 | stale proposal/base head/evaluator/assessment selection/authority after validation | Deny commit with existing stale/current-grant gates; revalidate exact new bindings. |
| F41 | adversarial unended non-event balance conflicts with new post | Deny inconsistent candidate; compiler may not end external evidence silently. |
| F42 | effect expires; later action lacks current resource or power evidence | Unresolved and deny; expiry never restores prior stock/power. |
| F43 | fire contract changed to optional consume, always condition, absent effect and absent stock | Admit no-effect occurrence under this explicit protected contract; no inferred consumption. The author/prose classification must explain why consumption is optional. Present consume still needs exact pre-stock. |

F31 makes the occurrence boundary explicit: drafting intent does not execute accounting. Consequence coverage claims always identify occurred events, legacy exclusions and unresolved checks separately. Restricted or partial validation must not be presented as full consequence proof.

## Qualification protocol after approval

Each rejection/unresolved row needs actual persisted candidate bytes, validation result and denied commit attempt. Each legal control needs exact author-approved/delegated proposal publication, generated assertions, queried pre/post state and kernel receipt. F17/F23/F37 need independent per-owner accounting from immutable saved package history; F35/F38/F40 need exact binding/authority records and restart recovery. Tamper missing debit, post-value, recipient, world, oracle expected value, generated assertion, authority and approval independently; the auditor must fail each. Prose P3 gold separately freezes missing implicit consumption, unrelated walking power grant, wrong enchantment recipient, legitimate enchantment/transfer and ambiguous remaining ammunition, including held-out paraphrases. No such extraction/runtime/native-UI qualification is claimed here.

## Frozen prose examples for later extraction qualification

These source texts and gold mappings are authored decision fixtures; no model extraction is tested here. Each held-out wording retains the same structured expected result.

| Case | Literal / held-out wording | Frozen material mapping and judgment |
|---|---|---|
| Missing consumption | “With one round left, Mara fired. She still had one round.” / “Her final cartridge cracked; afterward the count remained one.” | actor Mara, occurred fire, pre stock 1, required post 0; submitted unchanged stock 1 is F03. Extract implicit consumption even if no verb ‘consume’ appears. |
| Unrelated grant | “Mara walked across the room and became invulnerable.” / “After crossing the floor on foot, nothing could hurt her.” | walking action with empty contract; invulnerability effect unlisted, F07. No implicit enchantment inferred. |
| Wrong recipient | “Mara enchanted Ivo, but the spell made watching Neri invulnerable.” / “Ivo was the named beneficiary; the protection instead appeared on Neri.” | actor Mara, recipient Ivo, bystander Neri, charged=true; grant subject Neri fails F09. |
| Legitimate effect | “Charged Mara enchanted Ivo, protecting him for three ticks.” / “Mara’s charge was established before she gave Ivo three ticks of protection.” | enchant actor Mara, recipient Ivo, supported charged=true before 10; true grant [10,13), F08. The sentence alone is not a separate pre-evidence assertion. |
| Unresolved balance | “Mara fired from the old gun; nobody knew how many rounds remained.” / “The weapon discharged, but its prior ammunition count was unrecorded.” | occurred constrained fire, owner Mara, absent exact pre stock; unresolved F05/F06. Do not guess initial 1 or remaining 0. |

Extraction must keep the event, condition, pre-stock and claimed post-stock distinct. Literal and held-out wording are separate inputs, not concatenated passages. A successful structured example does not establish that an external model will extract these mappings.

## Added world-rule and clarification fixtures — October 3, 2026

These extend the frozen preparation requirements following Vanna's direction; their runtime support is not yet established.

| ID | Author facts and use | Required result |
|---|---|---|
| F44 | Author declares each gun holds at most twelve rounds between reloads; gun A is explicitly loaded with twelve, then fires twelve one-round shots across scenes. | Gun A has zero remaining. A thirteenth fails without an established reload. Count belongs to gun A, not the holder or current scene. |
| F45 | The same cap exists, but gun A's starting load or earlier use is unknown. | Ask the author for the missing starting/history evidence; do not assume twelve remaining. The cap still rules out thirteen shots in one unreloaded period. |
| F46 | Author declares every gun starts fully loaded with twelve; A and B have established individual starts. | Each receives its own initial stock once. Firing A does not spend B's ammunition, and mentioning A again does not initialize it again. |
| F47 | Gun A has fired ten shots, then changes holder and is used in a later scene after restart. | Its remaining two rounds carry forward; changing owner, scene or process never reloads it. |
| F48 | Empty gun A has an established reload of twelve, followed by one shot. | Eleven remain. A supposed reload with unknown amount/supply where supply is constrained asks for clarification instead of manufacturing rounds. |
| F49 | Twelve-round rule belongs to world W1; a gun is used in W2, or an object-specific claim conflicts with the applicable rule. | Do not import W1's rule into W2. Ask for relevant W2 facts. A conflicting local claim cannot bypass W1's rule without an explicit authorized exception/change. |
| F50 | Author changes the world rule or initial-load statement after dependent shots were validated. | Show affected guns/events and revalidate them; previous approval cannot publish the changed result. Preserve old editions and the author's original wording. |
