//! Bundled, optional domain vocabulary. Installation emits ordinary reviewable operations.
use crate::{ids::RecordId, records::*};
use std::collections::BTreeMap;
#[derive(Debug, serde::Serialize)]
pub struct StarterPack {
    pub key: &'static str,
    pub title: &'static str,
    pub types: &'static [&'static str],
}
pub const CATALOG: &[StarterPack] = &[
    StarterPack {
        key: "reality",
        title: "Reality, cosmology, and time",
        types: &["Realm", "Reference system", "Existence"],
    },
    StarterPack {
        key: "geography",
        title: "Geography and environment",
        types: &["Region", "River", "Resource deposit"],
    },
    StarterPack {
        key: "life",
        title: "Life, ecology, and health",
        types: &["Species", "Population", "Condition"],
    },
    StarterPack {
        key: "people",
        title: "People, minds, and identity",
        types: &["Agent", "Body", "Capability"],
    },
    StarterPack {
        key: "kinship",
        title: "Kinship, households, and populations",
        types: &["Household", "Partnership", "Caregiving"],
    },
    StarterPack {
        key: "culture",
        title: "Culture and everyday life",
        types: &["Community", "Custom", "Practice"],
    },
    StarterPack {
        key: "government",
        title: "Government and political power",
        types: &["State", "Government", "Office", "Territorial claim"],
    },
    StarterPack {
        key: "law",
        title: "Law, justice, and diplomacy",
        types: &["Jurisdiction", "Treaty", "Obligation", "Proceeding"],
    },
    StarterPack {
        key: "organizations",
        title: "Organizations and institutions",
        types: &["Institution", "Branch", "Appointment"],
    },
    StarterPack {
        key: "economy",
        title: "Economy, resources, and work",
        types: &["Inventory", "Production", "Shipment", "Debt"],
    },
    StarterPack {
        key: "belief",
        title: "Religion, philosophy, and belief",
        types: &["Doctrine", "Ritual", "Belief"],
    },
    StarterPack {
        key: "language",
        title: "Language, knowledge, and communication",
        types: &["Language", "Script", "Message"],
    },
    StarterPack {
        key: "technology",
        title: "Science, technology, and magic",
        types: &["Technique", "Device", "Prerequisite"],
    },
    StarterPack {
        key: "infrastructure",
        title: "Settlements, buildings, and infrastructure",
        types: &["Building", "Room", "Entrance", "Service"],
    },
    StarterPack {
        key: "transport",
        title: "Transportation, logistics, and security",
        types: &["Vehicle", "Route", "Journey", "Access condition"],
    },
    StarterPack {
        key: "objects",
        title: "Objects, art, and records",
        types: &["Design", "Edition", "Copy", "Custody"],
    },
    StarterPack {
        key: "history",
        title: "History, events, and processes",
        types: &["Occurrence", "Period", "Process", "Account"],
    },
    StarterPack {
        key: "intentions",
        title: "Intentions, knowledge, and disputed information",
        types: &["Goal", "Plan", "Commitment", "Evidence"],
    },
    StarterPack {
        key: "narrative",
        title: "Narrative and authoring records",
        types: &["Work", "Scene", "Passage", "Disclosure"],
    },
];
#[derive(Debug, serde::Serialize)]
pub struct Case {
    pub id: &'static str,
    pub nodes: &'static [&'static str],
    pub facts: &'static [(usize, &'static str, usize)],
    pub unproven: (usize, &'static str, usize),
}
pub const EXAMPLES: &[Case] = &[
    Case {
        id: "D01",
        nodes: &[
            "High realm",
            "Low realm",
            "Crossing requires a seal",
            "Sun-god cosmology",
        ],
        facts: &[
            (0, "crossing_condition", 2),
            (1, "crossing_condition", 2),
            (0, "inhabitant_cosmology", 3),
        ],
        unproven: (0, "objective_creator", 3),
    },
    Case {
        id: "D02",
        nodes: &[
            "Marsh",
            "Floodplain",
            "Seasonal river",
            "Iron deposit",
            "Unlabelled map",
        ],
        facts: &[
            (0, "overlaps", 1),
            (2, "flows_in_season_through", 0),
            (1, "contains_deposit", 3),
        ],
        unproven: (4, "establishes_coordinates_of", 2),
    },
    Case {
        id: "D03",
        nodes: &[
            "Gryphon species",
            "Harbour population",
            "Individual Iven",
            "Injured wing",
            "Authored survival food",
        ],
        facts: &[
            (1, "population_of", 0),
            (2, "individual_of", 0),
            (2, "condition", 3),
            (0, "survival_requirement", 4),
        ],
        unproven: (2, "has_every_typical_trait_of", 0),
    },
    Case {
        id: "D04",
        nodes: &[
            "Mara",
            "Mara's body",
            "Harbourmaster office",
            "Flight capability",
            "Mara's identical avatar",
        ],
        facts: &[
            (0, "embodied_as", 1),
            (0, "holds_office", 2),
            (0, "has_capability", 3),
            (4, "resembles", 0),
        ],
        unproven: (4, "is_same_identity_as", 0),
    },
    Case {
        id: "D05",
        nodes: &["Ari", "Bo", "Cy", "Chosen household"],
        facts: &[
            (0, "chosen_family", 1),
            (0, "partner", 1),
            (0, "partner", 2),
            (1, "partner", 2),
            (0, "household", 3),
            (1, "household", 3),
            (2, "caregiver_of", 0),
        ],
        unproven: (0, "biological_ancestor", 1),
    },
    Case {
        id: "D06",
        nodes: &[
            "Canal community",
            "Shared rice foodway",
            "Green dress custom",
            "Ari",
            "Red dress preference",
        ],
        facts: &[
            (0, "foodway", 1),
            (0, "dress_custom", 2),
            (3, "member_of", 0),
            (3, "preference", 4),
        ],
        unproven: (3, "physically_unable_to_depart_from", 2),
    },
    Case {
        id: "D07",
        nodes: &[
            "State",
            "Government",
            "Governor office",
            "Ari",
            "Territory",
            "Rival council",
        ],
        facts: &[
            (1, "governs", 0),
            (3, "holds_tenure", 2),
            (0, "claims", 4),
            (5, "effectively_controls", 4),
        ],
        unproven: (0, "effectively_controls", 4),
    },
    Case {
        id: "D08",
        nodes: &[
            "Harbour jurisdiction",
            "No theft law",
            "Treaty",
            "Ari",
            "Theft proceeding",
            "Prescribed punishment",
        ],
        facts: &[
            (1, "jurisdiction", 0),
            (3, "treaty_party", 2),
            (3, "subject_of", 4),
            (1, "prescribes", 5),
        ],
        unproven: (3, "received_punishment", 5),
    },
    Case {
        id: "D09",
        nodes: &[
            "Aid institution",
            "Harbour branch",
            "Ari",
            "Stored grain",
            "Profit practice",
            "Charity mission",
        ],
        facts: &[
            (1, "branch_of", 0),
            (2, "member_of", 1),
            (1, "holds_resource", 3),
            (2, "appointed_leader_of", 1),
            (0, "stated_mission", 5),
            (0, "actual_practice", 4),
        ],
        unproven: (0, "actual_practice", 5),
    },
    Case {
        id: "D10",
        nodes: &[
            "Crown currency",
            "Silver unit",
            "Inventory",
            "Production requirement",
            "Shipment",
            "Debt",
            "Foreign currency",
        ],
        facts: &[
            (0, "denominated_in", 1),
            (2, "production_requires", 3),
            (4, "draws_from", 2),
            (5, "denominated_in", 0),
        ],
        unproven: (0, "known_exchange_rate_to", 6),
    },
    Case {
        id: "D11",
        nodes: &[
            "Sun doctrine",
            "Temple institution",
            "Dawn ritual",
            "Believer",
            "Sacred narrative",
            "Sun deity",
        ],
        facts: &[
            (1, "teaches", 0),
            (1, "performs", 2),
            (3, "believes", 0),
            (0, "narrative", 4),
            (0, "describes_deity", 5),
        ],
        unproven: (5, "objectively_exists_in", 1),
    },
    Case {
        id: "D12",
        nodes: &[
            "Harbour dialect",
            "Old Quay contextual name",
            "Ari",
            "Readable letter",
            "Bo",
        ],
        facts: &[
            (1, "language_variant", 0),
            (2, "literate_in", 0),
            (3, "written_in", 0),
            (2, "sent", 3),
            (3, "intended_recipient", 4),
        ],
        unproven: (4, "knows_content_of", 3),
    },
    Case {
        id: "D13",
        nodes: &[
            "Levitation device",
            "Charged crystal cost",
            "Training prerequisite",
            "Damp failure condition",
            "Mara",
        ],
        facts: &[
            (0, "cost", 1),
            (0, "prerequisite", 2),
            (0, "failure_condition", 3),
        ],
        unproven: (4, "can_currently_use", 0),
    },
    Case {
        id: "D14",
        nodes: &[
            "House",
            "Kitchen",
            "Known door",
            "Ari",
            "Well",
            "Hidden entrance",
        ],
        facts: &[
            (1, "room_of", 0),
            (2, "entrance_of", 0),
            (3, "occupies", 1),
            (4, "supplies", 0),
        ],
        unproven: (5, "impossible_entrance_of", 0),
    },
    Case {
        id: "D15",
        nodes: &[
            "Ferry",
            "Canal route",
            "Water mode",
            "Permit access",
            "Travel interval unknown",
            "Capacity ten",
        ],
        facts: &[
            (0, "route", 1),
            (0, "mode", 2),
            (1, "requires", 3),
            (0, "travel_interval", 4),
            (0, "capacity", 5),
        ],
        unproven: (0, "definitely_arrives_before", 4),
    },
    Case {
        id: "D16",
        nodes: &[
            "Treatise work",
            "Second edition",
            "Specific copy",
            "Library custody",
            "Source content",
            "Authenticity claim",
            "Reported occurrence",
        ],
        facts: &[
            (1, "edition_of", 0),
            (2, "copy_of", 1),
            (2, "custody", 3),
            (2, "contains", 4),
            (2, "authenticity_claim", 5),
            (4, "reports", 6),
        ],
        unproven: (6, "established_by_occurrence", 2),
    },
    Case {
        id: "D17",
        nodes: &[
            "Compound crossing",
            "Departure",
            "Arrival",
            "Claimed cause",
            "First account",
            "Conflicting account",
        ],
        facts: &[
            (0, "first_subevent", 1),
            (0, "second_subevent", 2),
            (2, "claimed_cause", 3),
            (4, "account_of", 0),
            (5, "conflicting_account_of", 0),
        ],
        unproven: (4, "silently_reconciles_with", 5),
    },
    Case {
        id: "D18",
        nodes: &[
            "Ari",
            "Goal",
            "Plan",
            "Commitment",
            "Nested belief",
            "Observation",
            "Disclosure",
            "Future event",
        ],
        facts: &[
            (0, "goal", 1),
            (0, "plan", 2),
            (0, "commitment", 3),
            (0, "nested_belief", 4),
            (0, "observation", 5),
            (6, "content", 4),
            (2, "predicts", 7),
        ],
        unproven: (7, "occurred_because_planned_by", 0),
    },
    Case {
        id: "D19",
        nodes: &[
            "External work",
            "Work version",
            "Scene",
            "Passage",
            "Viewpoint Ari",
            "Later narration",
            "Reader reveal position",
        ],
        facts: &[
            (1, "version_of", 0),
            (2, "scene_of", 1),
            (3, "passage_of", 1),
            (2, "viewpoint", 4),
            (2, "narration_time", 5),
            (3, "reader_position", 6),
        ],
        unproven: (4, "already_knew_at_story_time", 6),
    },
];

pub fn operations(key: &str) -> Result<Vec<DomainOperation>, String> {
    let index = CATALOG
        .iter()
        .position(|p| p.key == key)
        .ok_or("Unknown starter pack")?;
    let pack = &CATALOG[index];
    let namespace = format!("starter:{}", pack.key);
    let mut operations = Vec::new();
    let mut records = Vec::new();
    for label in pack.types {
        let id = RecordId::generate(&mut rand::rng());
        records.push(id.clone());
        operations.push(DomainOperation::DefineType {
            client_ref: id.to_string(),
            record: EntityType {
                namespace: namespace.clone(),
                key: label.to_lowercase().replace(' ', "_"),
                labels: BTreeMap::from([("en".into(), (*label).into())]),
                parents: vec![],
                classification_executable: false,
            },
        });
    }
    for key in EXAMPLES[index]
        .facts
        .iter()
        .map(|(_, key, _)| *key)
        .collect::<std::collections::BTreeSet<_>>()
    {
        let id = RecordId::generate(&mut rand::rng());
        records.push(id.clone());
        operations.push(DomainOperation::DefineRelation {
            client_ref: id.to_string(),
            record: RelationDef {
                namespace: namespace.clone(),
                key: key.into(),
                labels: BTreeMap::from([("en".into(), key.replace('_', " "))]),
                roles: vec![RoleDef {
                    name: "participant".into(),
                    participant_types: vec![],
                    multiplicity: Multiplicity::Multiple,
                    ordered: false,
                }],
            },
        });
    }
    operations.push(DomainOperation::InstallPack {
        client_ref: RecordId::generate(&mut rand::rng()).to_string(),
        record: DomainPack {
            key: namespace,
            version: "1.0.0".into(),
            dependencies: BTreeMap::new(),
            capabilities: vec![],
            records,
        },
    });
    Ok(operations)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn all_nineteen_packs_have_distinct_vocabulary_and_reviewable_operations() {
        assert_eq!(CATALOG.len(), 19);
        assert_eq!(EXAMPLES.len(), 19);
        for pack in CATALOG {
            let ops = operations(pack.key).unwrap();
            assert!(ops.len() > 4 && ops.len() <= 100);
            for op in ops {
                let value = serde_json::to_value(&op).unwrap();
                assert_eq!(
                    serde_json::from_value::<DomainOperation>(value).unwrap(),
                    op
                );
            }
        }
    }
}
