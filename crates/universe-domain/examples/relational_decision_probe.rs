//! Normative-model canonical byte probe only; no application storage access.
use std::{env, fs};
use universe_domain::{
    canonical::{canonical_serde, PayloadDigest},
    records::{DomainOperation, Payload},
};

fn main() {
    let args: Vec<_> = env::args().collect();
    if args.len() == 1 {
        // Source inventory only. The decision compiler replaces superseded shapes.
        println!(
            "{}",
            serde_json::json!({
                "Payload": schemars::schema_for!(Payload),
                "DomainOperation": schemars::schema_for!(DomainOperation)
            })
        );
        return;
    }
    let rows: Vec<serde_json::Value> =
        serde_json::from_slice(&fs::read(&args[1]).unwrap()).unwrap();
    let results: Vec<_> = rows
        .into_iter()
        .map(|row| {
            let value = &row["value"];
            let kind = value["record_kind"].as_str().unwrap();
            let canonical = canonical_serde(value);
            let digest = PayloadDigest::compute(kind, &canonical);
            serde_json::json!({"name":row["name"], "value":value,
            "canonical":String::from_utf8(canonical.to_bytes()).unwrap(), "digest":digest})
        })
        .collect();
    println!("{}", serde_json::to_string(&results).unwrap());
}
