//! Maintained public contract examples shared with Dart and host clients.
use serde_json::Value;
pub fn id(prefix: &str, n: u64) -> String {
    format!("{prefix}_{n:024x}")
}
pub fn valid() -> Vec<(String, Value)> {
    #[derive(serde::Deserialize)]
    struct Example {
        tool: String,
        args: Value,
    }
    serde_json::from_str::<Vec<Example>>(include_str!("../../../contracts/examples.json"))
        .expect("maintained public examples")
        .into_iter()
        .map(|example| (example.tool, example.args))
        .collect()
}
