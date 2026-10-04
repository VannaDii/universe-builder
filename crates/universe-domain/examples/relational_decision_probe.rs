//! Decision-package probe only; does not open or migrate application storage.
use std::{env, fs};
use universe_domain::{
    canonical::Canonical,
    records::{DomainOperation, Payload},
};

fn main() {
    let args: Vec<_> = env::args().collect();
    if args.len() == 1 {
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
    let mut results = Vec::new();
    for row in rows {
        let payload: Payload = serde_json::from_value(row["value"].clone()).unwrap();
        let bytes = payload.to_canonical().to_bytes();
        let digest = universe_domain::canonical::payload_digest(&payload.kind(), &payload);
        results.push(serde_json::json!({"name": row["name"], "value": serde_json::to_value(&payload).unwrap(),
            "canonical": String::from_utf8(bytes).unwrap(), "digest": digest,
            "discriminator": format!("{}:{}", payload.kind().discriminator(), universe_domain::SCHEMA_VERSION)}));
    }
    println!("{}", serde_json::to_string(&results).unwrap());
}
