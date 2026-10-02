use crate::{ProtocolError, Request, Response};
use serde::{Deserialize, Serialize};
#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Hello {
    pub protocol_version: String,
    pub fixture: bool,
}
#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HelloReply {
    pub protocol_version: String,
    pub fixture: bool,
    pub max_frame_bytes: usize,
    pub max_in_flight: usize,
}
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum ClientMessage {
    Request { id: u64, request: Box<Request> },
    Cancel { id: u64 },
}
#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ServerMessage {
    pub id: u64,
    pub result: Result<Response, ProtocolError>,
}
/// Reject duplicate keys and invalid encoding before typed deserialization.
pub fn decode<T: serde::de::DeserializeOwned>(bytes: &[u8]) -> Result<T, String> {
    if bytes.len() > crate::MAX_FRAME_BYTES {
        return Err("frame too large".into());
    }
    // Wire JSON is not canonical JSON. Valid Unicode escapes and numeric JSON
    // tokens must be accepted, while duplicates must survive until checked.
    let _: StrictJson = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
    serde_json::from_slice(bytes).map_err(|e| e.to_string())
}

struct StrictJson;
impl<'de> Deserialize<'de> for StrictJson {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct Visitor;
        impl<'de> serde::de::Visitor<'de> for Visitor {
            type Value = StrictJson;
            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("JSON without duplicate keys")
            }
            fn visit_unit<E: serde::de::Error>(self) -> Result<StrictJson, E> {
                Ok(StrictJson)
            }
            fn visit_bool<E: serde::de::Error>(self, _: bool) -> Result<StrictJson, E> {
                Ok(StrictJson)
            }
            fn visit_i64<E: serde::de::Error>(self, _: i64) -> Result<StrictJson, E> {
                Ok(StrictJson)
            }
            fn visit_u64<E: serde::de::Error>(self, _: u64) -> Result<StrictJson, E> {
                Ok(StrictJson)
            }
            fn visit_f64<E: serde::de::Error>(self, _: f64) -> Result<StrictJson, E> {
                Ok(StrictJson)
            }
            fn visit_str<E: serde::de::Error>(self, _: &str) -> Result<StrictJson, E> {
                Ok(StrictJson)
            }
            fn visit_seq<A: serde::de::SeqAccess<'de>>(
                self,
                mut a: A,
            ) -> Result<StrictJson, A::Error> {
                while a.next_element::<StrictJson>()?.is_some() {}
                Ok(StrictJson)
            }
            fn visit_map<A: serde::de::MapAccess<'de>>(
                self,
                mut a: A,
            ) -> Result<StrictJson, A::Error> {
                let mut keys = std::collections::HashSet::new();
                while let Some(key) = a.next_key::<String>()? {
                    if !keys.insert(key) {
                        return Err(serde::de::Error::custom("duplicate JSON key"));
                    }
                    a.next_value::<StrictJson>()?;
                }
                Ok(StrictJson)
            }
        }
        d.deserialize_any(Visitor)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn standard_json_escapes_are_accepted_without_changing_unicode() {
        let value: serde_json::Value =
            decode(br#"{"text":"caf\u00e9 \ud83c\udf19 \u0000","number":1e3}"#).unwrap();
        assert_eq!(value["text"], "café 🌙 \0");
        let request: Request = decode(br#"{"tool":"universe_describe","args":{"universe":"The \u0041shen Cycle","mode":"summary"}}"#).unwrap();
        assert_eq!(request.universe().0, "The Ashen Cycle");
    }
    #[test]
    fn escaped_duplicate_keys_and_invalid_json_are_rejected() {
        for bytes in [
            br#"{"a":1,"\u0061":2}"#.as_slice(),
            br#"{"nested":[{"x":1,"x":2}]}"#,
            br#"{"x":"\ud800"}"#,
            br#"{"x":1.2.3}"#,
        ] {
            assert!(decode::<serde_json::Value>(bytes).is_err());
        }
    }
}
