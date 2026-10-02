//! Versioned selector normalization. Changing either Unicode table is a format change.
use crate::{StoreError, StoreResult};
use unicode_casefold::UnicodeCaseFold;
use unicode_normalization::UnicodeNormalization;
pub const NORMALIZATION_VERSION: &str = "nfc-0.1.22-casefold-0.2.0-v1";
pub fn selector_key(name: &str) -> StoreResult<String> {
    if name.len()>640 || name.chars().count()>160 || name.chars().any(|c| c.is_control() || matches!(c,'\u{061c}'|'\u{200e}'|'\u{200f}'|'\u{202a}'..='\u{202e}'|'\u{2066}'..='\u{2069}')) {
        return Err(StoreError::StorageFailure("invalid selector".into()));
    }
    let key: String = name.trim().nfc().case_fold().nfc().collect();
    if key.is_empty() || matches!(key.as_str(), "*" | "all" | ".") {
        return Err(StoreError::StorageFailure("invalid selector".into()));
    }
    Ok(key)
}
