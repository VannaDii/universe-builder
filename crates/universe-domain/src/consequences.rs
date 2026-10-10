//! Definition contracts only. These declarations do not execute event effects.
use crate::{Canonical, CanonicalValue, Polarity, RecordRef, UnitId, Value};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

/// Exact bounded decimal string; never converted through a host float.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, schemars::JsonSchema)]
#[serde(transparent)]
pub struct ConsequenceInteger(
    #[schemars(length(max = 40), regex(pattern = r"^(0|-?[1-9][0-9]{0,38})$"))] String,
);
impl ConsequenceInteger {
    pub fn get(&self) -> i128 {
        self.0.parse().expect("validated integer")
    }
}
impl<'de> Deserialize<'de> for ConsequenceInteger {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let text = String::deserialize(d)?;
        let number = text.parse::<i128>().map_err(serde::de::Error::custom)?;
        if number.to_string() != text {
            return Err(serde::de::Error::custom("noncanonical consequence integer"));
        }
        Ok(Self(text))
    }
}
/// Exact finite decimal amount, bounded by checked i128 coefficient/scale arithmetic.
/// The authored digits stay intact; normalized pairs are only calculation keys.
pub type ExactAmount = (i128, u32);
pub fn exact_amount(text: &str) -> Option<ExactAmount> {
    if text.len() > 80
        || !crate::value::is_exact_decimal_digits(text, true)
        || text.starts_with('+')
    {
        return None;
    }
    let (whole, fraction) = text.split_once('.').unwrap_or((text, ""));
    if whole.is_empty() || whole == "-" || (text.contains('.') && fraction.is_empty()) {
        return None;
    }
    let fraction = fraction.trim_end_matches('0');
    let scale = u32::try_from(fraction.len()).ok()?;
    10_i128.checked_pow(scale)?;
    Some((format!("{whole}{fraction}").parse().ok()?, scale))
}
pub fn add_amount((a, s): ExactAmount, (b, t): ExactAmount) -> Option<ExactAmount> {
    let scale = s.max(t);
    let mut coefficient = a
        .checked_mul(10_i128.checked_pow(scale - s)?)?
        .checked_add(b.checked_mul(10_i128.checked_pow(scale - t)?)?)?;
    let mut scale = scale;
    while scale > 0 && coefficient % 10 == 0 {
        coefficient /= 10;
        scale -= 1;
    }
    Some((coefficient, scale))
}
pub fn compare_amount((a, s): ExactAmount, (b, t): ExactAmount) -> Option<std::cmp::Ordering> {
    let scale = s.max(t);
    Some(
        a.checked_mul(10_i128.checked_pow(scale - s)?)?
            .cmp(&b.checked_mul(10_i128.checked_pow(scale - t)?)?),
    )
}
pub fn amount_digits((coefficient, scale): ExactAmount) -> String {
    if scale == 0 {
        return coefficient.to_string();
    }
    let sign = if coefficient < 0 { "-" } else { "" };
    let mut digits = coefficient.unsigned_abs().to_string();
    while digits.len() <= scale as usize {
        digits.insert(0, '0');
    }
    digits.insert(digits.len() - scale as usize, '.');
    format!("{sign}{digits}")
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, schemars::JsonSchema)]
#[serde(transparent)]
pub struct ConsequenceDecimal(
    #[schemars(
        length(max = 80),
        regex(pattern = r"^(0|-?[1-9][0-9]{0,38}|-?(0|[1-9][0-9]*)\.[0-9]+)$")
    )]
    String,
);
impl ConsequenceDecimal {
    pub fn number(&self) -> serde_json::Number {
        self.0.parse().expect("validated JSON number digits")
    }
    pub fn get(&self) -> ExactAmount {
        exact_amount(&self.0).expect("validated finite amount")
    }
}
impl<'de> Deserialize<'de> for ConsequenceDecimal {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let text = String::deserialize(d)?;
        if !text.contains('.')
            && text
                .parse::<i128>()
                .map_err(serde::de::Error::custom)?
                .to_string()
                != text
        {
            return Err(serde::de::Error::custom("noncanonical consequence integer"));
        }
        if let Some((whole, _)) = text.split_once('.') {
            let digits = whole.trim_start_matches('-');
            if digits.len() > 1 && digits.starts_with('0') {
                return Err(serde::de::Error::custom("noncanonical decimal whole part"));
            }
        }
        exact_amount(&text).ok_or_else(|| {
            serde::de::Error::custom("amount exceeds exact finite decimal bounds")
        })?;
        Ok(Self(text))
    }
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ConsequenceKind {
    ActionConsequences,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum EffectPresence {
    Required,
    Optional,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct EffectTarget {
    #[schemars(length(min = 1, max = 120))]
    pub role: String,
    pub predicate: RecordRef,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum EffectCondition {
    Always {},
    AttributeEquals {
        #[schemars(length(min = 1, max = 120))]
        role: String,
        predicate: RecordRef,
        value: Value,
    },
}
fn nullable_unit_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
    generator.subschema_for::<Option<UnitId>>()
}
fn required_nullable<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Option<UnitId>, D::Error> {
    Option::<UnitId>::deserialize(d)
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum EffectChange {
    Set {
        polarity: Polarity,
        value: Value,
    },
    Delta {
        delta: ConsequenceDecimal,
        minimum: ConsequenceDecimal,
        maximum: ConsequenceDecimal,
        #[serde(deserialize_with = "required_nullable")]
        #[schemars(required, schema_with = "nullable_unit_schema")]
        unit: Option<UnitId>,
    },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum EffectLifetime {
    UntilChanged {},
    Ticks { count: ConsequenceInteger },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct EffectSlot {
    #[schemars(length(min = 1, max = 120))]
    pub slot: String,
    #[schemars(range(max = 63))]
    pub order: u8,
    pub presence: EffectPresence,
    pub target: EffectTarget,
    pub condition: EffectCondition,
    pub change: EffectChange,
    pub lifetime: EffectLifetime,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(try_from = "RawContract")]
pub struct ConsequenceContract {
    pub kind: ConsequenceKind,
    #[schemars(length(max = 64))]
    pub slots: Vec<EffectSlot>,
}
#[derive(Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
struct RawContract {
    kind: ConsequenceKind,
    #[schemars(length(max = 64))]
    slots: Vec<EffectSlot>,
}
impl TryFrom<RawContract> for ConsequenceContract {
    type Error = String;
    fn try_from(raw: RawContract) -> Result<Self, Self::Error> {
        let contract = Self {
            kind: raw.kind,
            slots: raw.slots,
        };
        contract.validate()?;
        Ok(contract)
    }
}
impl ConsequenceContract {
    /// Validate declarations even when constructed directly in Rust.
    pub fn validate(&self) -> Result<(), String> {
        fn name(s: &str) -> bool {
            !s.trim().is_empty() && s.len() <= 120
        }
        if self.slots.len() > 64 {
            return Err("at most 64 consequence slots".into());
        }
        let mut names = BTreeSet::new();
        let mut orders = BTreeSet::new();
        let mut targets = BTreeSet::new();
        for slot in &self.slots {
            if !name(&slot.slot)
                || !name(&slot.target.role)
                || slot.order > 63
                || !names.insert(&slot.slot)
                || !orders.insert(slot.order)
                || !targets.insert((&slot.target.role, &slot.target.predicate))
            {
                return Err(
                    "consequence slots need bounded unique names, orders and targets".into(),
                );
            }
            if let EffectCondition::AttributeEquals { role, value, .. } = &slot.condition {
                if !name(role) {
                    return Err("condition role must be bounded and nonempty".into());
                }
                crate::value::validate_value(value).map_err(|e| e.to_string())?;
            }
            match &slot.change {
                EffectChange::Set { value, .. } => {
                    crate::value::validate_value(value).map_err(|e| e.to_string())?;
                }
                EffectChange::Delta {
                    delta,
                    minimum,
                    maximum,
                    ..
                } => {
                    if delta.get().0 == 0
                        || compare_amount(minimum.get(), maximum.get())
                            .ok_or("decimal bounds exceed supported exact arithmetic")?
                            == std::cmp::Ordering::Greater
                        || !matches!(slot.lifetime, EffectLifetime::UntilChanged { .. })
                    {
                        return Err("delta needs a nonzero amount, increasing bounds and until_changed lifetime".into());
                    }
                }
            }
            if let EffectLifetime::Ticks { count } = &slot.lifetime {
                if count.get() <= 0 {
                    return Err("ticks must be positive".into());
                }
            }
        }
        Ok(())
    }
}
/// Missing contract is historical; explicit null is never an empty contract.
pub(crate) fn present_contract<'de, D: serde::Deserializer<'de>>(
    d: D,
) -> Result<Option<ConsequenceContract>, D::Error> {
    ConsequenceContract::deserialize(d).map(Some)
}
macro_rules! canonical {
    ($($ty:ty),+) => { $(impl Canonical for $ty {
        fn to_canonical(&self) -> CanonicalValue { crate::canonical::canonical_serde(self) }
    })+ };
}
canonical!(
    ConsequenceInteger,
    ConsequenceDecimal,
    ConsequenceKind,
    EffectPresence,
    EffectTarget,
    EffectCondition,
    EffectChange,
    EffectLifetime,
    EffectSlot,
    ConsequenceContract
);
