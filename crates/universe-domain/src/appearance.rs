//! Optional visual references attach to any entry, without kind-specific rules.
use crate::{scope::Validity, value::RecordRef};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum AppearanceTarget {
    Universe,
    Entry { entry: RecordRef },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ImagePurpose {
    Appearance,
    Detail,
    Inspiration,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AppearanceImage {
    pub asset: RecordRef,
    pub caption: String,
    pub purpose: ImagePurpose,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AppearanceRelationship {
    Matches,
    Complements,
    Contrasts,
    DetailOf,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AppearanceLink {
    pub entry: RecordRef,
    pub relationship: AppearanceRelationship,
    pub note: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Appearance {
    pub target: AppearanceTarget,
    pub label: String,
    pub physical_description: String,
    pub atmosphere: String,
    pub images: Vec<AppearanceImage>,
    pub links: Vec<AppearanceLink>,
    pub validity: Validity,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ImageAsset {
    pub digest: String,
    pub media_type: String,
    pub byte_size: u64,
    pub width: u32,
    pub height: u32,
    pub original_name: String,
}
