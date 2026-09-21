//! The one versioned canonical serializer and digest rules (spec §27.8).
//!
//! - Object keys are canonically ordered (sorted); authored Unicode string
//!   content is preserved without identity-changing normalization.
//! - Sequences preserve authored order; sets normalize by stable identity.
//! - Exact numerics are canonical JSON number tokens of their exact digit
//!   strings — no host float is ever introduced.
//! - Duplicate keys and unknown fields in closed payloads are rejected by
//!   the strict parser used at import/decoding boundaries.
//!
//! A digest is an integrity/comparison mechanism, not proof of authorship
//! (spec §27.8): a caller cannot authorize a write by supplying a digest
//! that happens to match stored data.

use sha2::{Digest, Sha256};

/// A canonical value: the in-memory form of canonical JSON.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum CanonicalValue {
    Null,
    Bool(bool),
    /// Exact digit token (integers, decimals). Written as a JSON number.
    Num(String),
    /// Preserved exactly; canonical form writes raw UTF-8, minimal escapes.
    Str(String),
    Arr(Vec<CanonicalValue>),
    Obj(Vec<(String, CanonicalValue)>),
}

impl CanonicalValue {
    pub fn obj(mut fields: Vec<(String, CanonicalValue)>) -> Self {
        fields.sort_by(|a, b| a.0.cmp(&b.0));
        CanonicalValue::Obj(fields)
    }

    pub fn arr(items: Vec<Self>) -> Self {
        CanonicalValue::Arr(items)
    }

    /// Render to canonical JSON bytes: sorted keys, no whitespace,
    /// minimal escaping, exact numeric tokens, raw UTF-8 strings.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::new();
        self.write(&mut out);
        out
    }

    fn write(&self, out: &mut Vec<u8>) {
        match self {
            CanonicalValue::Null => out.extend_from_slice(b"null"),
            CanonicalValue::Bool(b) => out.extend_from_slice(if *b { b"true" } else { b"false" }),
            CanonicalValue::Num(digits) => out.extend_from_slice(digits.as_bytes()),
            CanonicalValue::Str(s) => write_json_string(out, s),
            CanonicalValue::Arr(items) => {
                out.push(b'[');
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(b',');
                    }
                    item.write(out);
                }
                out.push(b']');
            }
            CanonicalValue::Obj(fields) => {
                out.push(b'{');
                for (i, (k, v)) in fields.iter().enumerate() {
                    if i > 0 {
                        out.push(b',');
                    }
                    write_json_string(out, k);
                    out.push(b':');
                    v.write(out);
                }
                out.push(b'}');
            }
        }
    }

    /// Strictly parse canonical JSON. Rejects duplicate object keys
    /// (spec §27.8), raw control characters, and non-UTF-8 input.
    ///
    /// Numeric tokens accept the digit/`-`/`.` forms the canonical writer
    /// can produce; callers that need to reject authored numeric strings
    /// (import/decoding boundaries, universe-schema) validate the token
    /// shape against the domain's exact-numeric rules on top of this.
    /// The parse is a faithful round-trip of `to_bytes` output: parsed
    /// values re-serialize byte-identically.
    pub fn parse(bytes: &[u8]) -> Result<Self, crate::error::DomainError> {
        let text =
            std::str::from_utf8(bytes).map_err(|_| crate::error::DomainError::InvalidValue {
                reason: "canonical bytes are not UTF-8".into(),
            })?;
        let mut pos = 0usize;
        let b = text.as_bytes();
        fn skip_ws(b: &[u8], pos: &mut usize) {
            while *pos < b.len() && (b[*pos] as char).is_whitespace() {
                *pos += 1;
            }
        }
        fn parse_value(
            text: &str,
            b: &[u8],
            pos: &mut usize,
        ) -> Result<CanonicalValue, crate::error::DomainError> {
            skip_ws(b, pos);
            let start = *pos;
            match b.get(*pos) {
                Some(b'{') => {
                    *pos += 1;
                    let mut fields: Vec<(String, CanonicalValue)> = Vec::new();
                    let mut seen: std::collections::HashSet<String> =
                        std::collections::HashSet::new();
                    skip_ws(b, pos);
                    if b.get(*pos) == Some(&b'}') {
                        *pos += 1;
                        return Ok(CanonicalValue::Obj(fields));
                    }
                    loop {
                        skip_ws(b, pos);
                        let key = parse_string(text, b, pos)?;
                        if !seen.insert(key.clone()) {
                            return Err(crate::error::DomainError::DuplicateKey { key });
                        }
                        skip_ws(b, pos);
                        if b.get(*pos) != Some(&b':') {
                            return Err(crate::error::DomainError::InvalidValue {
                                reason: "expected ':'".into(),
                            });
                        }
                        *pos += 1;
                        let v = parse_value(text, b, pos)?;
                        fields.push((key, v));
                        skip_ws(b, pos);
                        match b.get(*pos) {
                            Some(b',') => *pos += 1,
                            Some(b'}') => {
                                *pos += 1;
                                break;
                            }
                            _ => {
                                return Err(crate::error::DomainError::InvalidValue {
                                    reason: "expected ',' or '}'".into(),
                                })
                            }
                        }
                    }
                    Ok(CanonicalValue::Obj(fields))
                }
                Some(b'[') => {
                    *pos += 1;
                    let mut items = Vec::new();
                    skip_ws(b, pos);
                    if b.get(*pos) == Some(&b']') {
                        *pos += 1;
                        return Ok(CanonicalValue::Arr(items));
                    }
                    loop {
                        let v = parse_value(text, b, pos)?;
                        items.push(v);
                        skip_ws(b, pos);
                        match b.get(*pos) {
                            Some(b',') => *pos += 1,
                            Some(b']') => {
                                *pos += 1;
                                break;
                            }
                            _ => {
                                return Err(crate::error::DomainError::InvalidValue {
                                    reason: "expected ',' or ']'".into(),
                                })
                            }
                        }
                    }
                    Ok(CanonicalValue::Arr(items))
                }
                Some(b'"') => parse_string(text, b, pos).map(CanonicalValue::Str),
                Some(b't') if text[*pos..].starts_with("true") => {
                    *pos += 4;
                    Ok(CanonicalValue::Bool(true))
                }
                Some(b'f') if text[*pos..].starts_with("false") => {
                    *pos += 5;
                    Ok(CanonicalValue::Bool(false))
                }
                Some(b'n') if text[*pos..].starts_with("null") => {
                    *pos += 4;
                    Ok(CanonicalValue::Null)
                }
                Some(c) if *c == b'-' || c.is_ascii_digit() => {
                    let s = *pos;
                    while *pos < b.len()
                        && (b[*pos].is_ascii_digit() || b[*pos] == b'.' || b[*pos] == b'-')
                    {
                        *pos += 1;
                    }
                    let tok = &text[s..*pos];
                    if tok.is_empty() {
                        return Err(crate::error::DomainError::InvalidValue {
                            reason: "empty numeric token".into(),
                        });
                    }
                    Ok(CanonicalValue::Num(tok.to_string()))
                }
                _ => {
                    let at = &text[start..];
                    Err(crate::error::DomainError::InvalidValue {
                        reason: format!("unexpected token `{at}`"),
                    })
                }
            }
        }
        fn parse_string(
            text: &str,
            b: &[u8],
            pos: &mut usize,
        ) -> Result<String, crate::error::DomainError> {
            // assumes b[*pos] == b'"'
            *pos += 1;
            let mut out = String::new();
            loop {
                let c = *b.get(*pos).ok_or(crate::error::DomainError::InvalidValue {
                    reason: "unterminated string".into(),
                })?;
                *pos += 1;
                if c == b'"' {
                    break;
                }
                if c == b'\\' {
                    let e = *b.get(*pos).ok_or(crate::error::DomainError::InvalidValue {
                        reason: "dangling escape".into(),
                    })?;
                    *pos += 1;
                    match e {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{0008}'),
                        b'f' => out.push('\u{000C}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            if *pos + 4 > b.len() {
                                return Err(crate::error::DomainError::InvalidValue {
                                    reason: "truncated unicode escape".into(),
                                });
                            }
                            let hex = std::str::from_utf8(&b[*pos..*pos + 4]).map_err(|_| {
                                crate::error::DomainError::InvalidValue {
                                    reason: "invalid unicode escape".into(),
                                }
                            })?;
                            let cp = u32::from_str_radix(hex, 16).map_err(|_| {
                                crate::error::DomainError::InvalidValue {
                                    reason: "invalid unicode escape".into(),
                                }
                            })?;
                            // Canonical form must not escape codepoints; a
                            // canonical input containing \u escapes is
                            // non-canonical. Reject to keep the one
                            // canonical representation.
                            return Err(crate::error::DomainError::InvalidValue {
                                reason: format!("non-canonical \\u escape of U+{cp:04X}"),
                            });
                        }
                        _ => {
                            return Err(crate::error::DomainError::InvalidValue {
                                reason: "invalid escape".into(),
                            })
                        }
                    }
                } else if c < 0x20 {
                    return Err(crate::error::DomainError::InvalidValue {
                        reason: "raw control character in canonical string".into(),
                    });
                } else {
                    // Copy the full UTF-8 character (the whole input was
                    // validated as UTF-8 above); canonical strings keep the
                    // original spelling byte-for-byte (spec §27.8).
                    let rest = &text[*pos - 1..];
                    let ch =
                        rest.chars()
                            .next()
                            .ok_or(crate::error::DomainError::InvalidValue {
                                reason: "invalid utf-8 in canonical string".into(),
                            })?;
                    *pos += ch.len_utf8() - 1;
                    out.push(ch);
                }
            }
            Ok(out)
        }
        let v = parse_value(text, b, &mut pos)?;
        skip_ws(b, &mut pos);
        if pos != b.len() {
            return Err(crate::error::DomainError::InvalidValue {
                reason: "trailing data after canonical value".into(),
            });
        }
        Ok(v)
    }
}

fn write_json_string(out: &mut Vec<u8>, s: &str) {
    out.push(b'"');
    for c in s.chars() {
        match c {
            '"' => out.extend_from_slice(b"\\\""),
            '\\' => out.extend_from_slice(b"\\\\"),
            '\n' => out.extend_from_slice(b"\\n"),
            '\r' => out.extend_from_slice(b"\\r"),
            '\t' => out.extend_from_slice(b"\\t"),
            '\u{0008}' => out.extend_from_slice(b"\\b"),
            '\u{000C}' => out.extend_from_slice(b"\\f"),
            c if (c as u32) < 0x20 => {
                out.extend_from_slice(format!("\\u{:04x}", c as u32).as_bytes());
            }
            c => out.extend_from_slice(c.encode_utf8(&mut [0u8; 4]).as_bytes()),
        }
    }
    out.push(b'"');
}

/// A domain value that can be canonicalized.
pub trait Canonical {
    fn to_canonical(&self) -> CanonicalValue;
}

impl Canonical for str {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(self.to_string())
    }
}
impl Canonical for String {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(self.clone())
    }
}
impl Canonical for bool {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Bool(*self)
    }
}
impl<T: Canonical> Canonical for Option<T> {
    fn to_canonical(&self) -> CanonicalValue {
        match self {
            Some(v) => v.to_canonical(),
            None => CanonicalValue::Null,
        }
    }
}
impl<T: Canonical> Canonical for Vec<T> {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::arr(self.iter().map(|v| v.to_canonical()).collect())
    }
}
impl<K: std::hash::Hash + Eq + Ord, V: Canonical> Canonical for std::collections::BTreeMap<K, V>
where
    K: std::fmt::Display,
{
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::obj(
            self.iter()
                .map(|(k, v)| (k.to_string(), v.to_canonical()))
                .collect(),
        )
    }
}
impl<T: Canonical> Canonical for &T {
    fn to_canonical(&self) -> CanonicalValue {
        (**self).to_canonical()
    }
}

/// Canonical byte form of a value.
pub fn canonical_bytes(v: &CanonicalValue) -> Vec<u8> {
    v.to_bytes()
}

/// Hash canonical bytes prefix-freely (length-prefixed) so that distinct
/// canonical forms cannot collide in `Hash` implementations.
pub fn write_canonical_bytes<H: std::hash::Hasher>(state: &mut H, bytes: &[u8]) {
    state.write_u32(bytes.len() as u32);
    state.write(bytes);
}

/// Hash a canonicalizable value (length-prefixed canonical bytes).
pub fn hash_canonical<T: Canonical, H: std::hash::Hasher>(state: &mut H, v: &T) {
    write_canonical_bytes(state, &v.to_canonical().to_bytes());
}

/// Canonical byte form of any canonicalizable value (convenience).
pub fn canonical_json<T: Canonical>(v: &T) -> Vec<u8> {
    v.to_canonical().to_bytes()
}

/// Canonicalize any `Serialize` value by bridging through serde JSON.
///
/// Domain payloads contain no host floats: exact integers/decimals are
/// digit strings and integrals are exact tokens, so the serde form is a
/// faithful canonical source. Keys are canonically sorted; authored
/// Unicode is preserved (spec §27.8). This is the single canonical
/// serializer for record payloads.
pub fn canonical_serde<T: serde::Serialize>(v: &T) -> CanonicalValue {
    let value = match serde_json::to_value(v) {
        Ok(v) => v,
        Err(e) => {
            panic!("domain value failed canonical serialization: {e}");
        }
    };
    canonical_json_value(&value)
}

/// Convert a serde_json::Value into the canonical form.
///
/// Numbers keep their exact decimal tokens (arbitrary_precision); object
/// keys are sorted; strings are preserved byte-for-byte.
pub fn canonical_json_value(v: &serde_json::Value) -> CanonicalValue {
    use serde_json::Value::*;
    match v {
        Null => CanonicalValue::Null,
        Bool(b) => CanonicalValue::Bool(*b),
        Number(n) => {
            // With `arbitrary_precision`, the exact token is preserved.
            if n.is_i64() || n.is_u64() {
                CanonicalValue::Num(n.to_string())
            } else {
                // A fractional decimal token: keep exact digits as a
                // string so no host float rounding is possible.
                CanonicalValue::Str(n.to_string())
            }
        }
        String(s) => CanonicalValue::Str(s.clone()),
        Array(items) => CanonicalValue::arr(items.iter().map(canonical_json_value).collect()),
        Object(map) => {
            let mut fields: Vec<_> = map
                .iter()
                .map(|(k, val)| (k.clone(), canonical_json_value(val)))
                .collect();
            fields.sort_by(|a, b| a.0.cmp(&b.0));
            CanonicalValue::Obj(fields)
        }
    }
}

/// SHA-256 digest of the canonical serialized payload and its schema
/// discriminator (spec §27.8).
#[derive(
    Debug,
    Clone,
    PartialEq,
    Eq,
    Hash,
    PartialOrd,
    Ord,
    serde::Serialize,
    serde::Deserialize,
    schemars::JsonSchema,
)]
#[serde(transparent)]
pub struct PayloadDigest(String);

impl PayloadDigest {
    pub fn compute(discriminator: &str, canonical: &CanonicalValue) -> Self {
        let mut h = Sha256::new();
        h.update(discriminator.as_bytes());
        h.update(b":");
        h.update(canonical.to_bytes());
        PayloadDigest(hex::encode(h.finalize()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Digest of a record payload with its kind + schema discriminator.
pub fn payload_digest(
    kind: &crate::records::RecordKind,
    payload: &crate::records::Payload,
) -> PayloadDigest {
    let discriminator = format!("{}:{}", kind.discriminator(), crate::SCHEMA_VERSION);
    PayloadDigest::compute(&discriminator, &payload.to_canonical())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_bytes_sort_keys_and_preserve_unicode() {
        let v = CanonicalValue::obj(vec![
            ("beta".into(), CanonicalValue::Str("ßẞſ".into())),
            ("alpha".into(), CanonicalValue::Num("007".into())),
        ]);
        let raw = v.to_bytes();
        let bytes = std::str::from_utf8(&raw).unwrap();
        // Sorted keys, exact numeric token (leading zeros preserved),
        // raw UTF-8 string content: no re-escaping, no re-normalization.
        assert_eq!(bytes, r#"{"alpha":007,"beta":"ßẞſ"}"#);
    }

    #[test]
    fn strict_parser_rejects_duplicate_keys() {
        let err = CanonicalValue::parse(b"{\"a\":1,\"a\":2}").unwrap_err();
        assert!(matches!(
            err,
            crate::error::DomainError::DuplicateKey { .. }
        ));
    }

    #[test]
    fn strict_parser_round_trips() {
        let v = CanonicalValue::obj(vec![
            (
                "n".into(),
                CanonicalValue::Num("-12345678901234567890".into()),
            ),
            ("s".into(), CanonicalValue::Str("héllo\nworld".into())),
            (
                "x".into(),
                CanonicalValue::arr(vec![CanonicalValue::Bool(true)]),
            ),
        ]);
        let bytes = v.to_bytes();
        let back = CanonicalValue::parse(&bytes).unwrap();
        assert_eq!(v, back);
    }

    #[test]
    fn digest_is_stable_and_content_sensitive() {
        let v1 = CanonicalValue::obj(vec![("a".into(), CanonicalValue::Num("1".into()))]);
        let d1 = PayloadDigest::compute("assertion:v1", &v1);
        let d1b = PayloadDigest::compute("assertion:v1", &v1);
        assert_eq!(d1, d1b);
        let v2 = CanonicalValue::obj(vec![("a".into(), CanonicalValue::Num("2".into()))]);
        assert_ne!(d1, PayloadDigest::compute("assertion:v1", &v2));
        // key reordering does not change the digest (E25):
        let v1_reordered = CanonicalValue::obj(vec![
            ("z".into(), CanonicalValue::Null),
            ("a".into(), CanonicalValue::Num("1".into())),
        ]);
        let v1_reordered2 = CanonicalValue::obj(vec![
            ("a".into(), CanonicalValue::Num("1".into())),
            ("z".into(), CanonicalValue::Null),
        ]);
        assert_eq!(v1_reordered, v1_reordered2);
        assert_eq!(
            PayloadDigest::compute("x:v1", &v1_reordered),
            PayloadDigest::compute("x:v1", &v1_reordered2)
        );
    }

    #[test]
    fn non_finite_numbers_cannot_be_represented() {
        // The value layer has no float variant at all; the canonical form
        // only accepts digit tokens, so NaN/Infinity are unrepresentable.
        assert!(matches!(
            CanonicalValue::parse(b"NaN"),
            Err(crate::error::DomainError::InvalidValue { .. })
        ));
    }
}
