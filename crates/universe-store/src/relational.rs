//! Codec for the normative fixed-column relational model.
//!
//! The embedded catalog is software metadata, never package authority. JSON
//! values here are transient boundary values; only typed scalar columns, branch
//! pointers and ordered/named child rows are written to SQLite.
use crate::{Connection, StoreError, StoreResult};
use rusqlite::{params, types::Value as SqlValue};
use serde::Deserialize;
use serde_json::{Map, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::OnceLock;

pub(crate) const SQL: &str = include_str!("../../../docs/decisions/relational-storage/typed.sql");
const CATALOG: &str = include_str!("../../../docs/decisions/relational-storage/catalog.json");
const MAX_DEPTH: usize = 128;

#[derive(Deserialize)]
struct Catalog {
    models: BTreeMap<String, Model>,
}
#[derive(Deserialize)]
struct Field {
    model: String,
    required: bool,
}
#[derive(Deserialize)]
struct Model {
    table: String,
    kind: String,
    #[serde(default)]
    fields: BTreeMap<String, Field>,
    #[serde(default)]
    variants: Vec<String>,
    item: Option<String>,
    #[serde(rename = "const")]
    constant: Option<Value>,
    #[serde(rename = "enum")]
    enumeration: Option<Vec<Value>>,
    pattern: Option<String>,
    minimum: Option<Value>,
    maximum: Option<Value>,
}
fn catalog() -> &'static Catalog {
    static MODELS: OnceLock<Catalog> = OnceLock::new();
    MODELS.get_or_init(|| serde_json::from_str(CATALOG).expect("checked-in relational catalog"))
}
fn invalid(message: &str) -> StoreError {
    StoreError::StorageFailure(format!("relational body: {message}"))
}
fn model(name: &str) -> StoreResult<&'static Model> {
    catalog()
        .models
        .get(name)
        .ok_or_else(|| invalid("unknown model"))
}
fn quote(name: &str) -> String {
    format!("\"{}\"", name.replace('"', "\"\""))
}
fn scalar(m: &Model) -> bool {
    matches!(
        m.kind.as_str(),
        "string" | "integer" | "number" | "boolean" | "null"
    )
}

// These are the complete pattern forms in the normative catalog. Reject an
// unrecognized software contract instead of quietly skipping its constraint.
fn pattern_matches(pattern: &str, text: &str) -> bool {
    if pattern == "^(0|-?[1-9][0-9]{0,38})$" {
        let digits = text.strip_prefix('-').unwrap_or(text);
        return text == "0"
            || (!digits.is_empty()
                && digits.len() <= 39
                && matches!(digits.as_bytes()[0], b'1'..=b'9')
                && digits.bytes().all(|b| b.is_ascii_digit()));
    }
    let (prefix, size) = if pattern == "^[0-9a-f]{64}$" {
        ("", 64)
    } else if let Some(prefix) = pattern
        .strip_prefix('^')
        .and_then(|p| p.strip_suffix("[0-9a-f]{24}$"))
    {
        (prefix, 24)
    } else {
        return false;
    };
    text.strip_prefix(prefix).is_some_and(|digits| {
        digits.len() == size
            && digits
                .bytes()
                .all(|b| b.is_ascii_digit() || matches!(b, b'a'..=b'f'))
    })
}

fn fits(name: &str, value: &Value, depth: usize) -> StoreResult<bool> {
    if depth > MAX_DEPTH {
        return Err(invalid("nesting limit"));
    }
    let m = model(name)?;
    let ok = match m.kind.as_str() {
        "union" => {
            let mut found = false;
            for variant in &m.variants {
                if fits(variant, value, depth + 1)? {
                    found = true;
                    break;
                }
            }
            found
        }
        "object" => {
            if let Some(object) = value.as_object() {
                if object.keys().any(|k| !m.fields.contains_key(k)) {
                    false
                } else {
                    let mut valid = true;
                    for (key, field) in &m.fields {
                        match object.get(key) {
                            Some(v) => valid &= fits(&field.model, v, depth + 1)?,
                            None => valid &= !field.required,
                        }
                        if !valid {
                            break;
                        }
                    }
                    valid
                }
            } else {
                false
            }
        }
        "tuple" => {
            if let Some(array) = value.as_array() {
                let mut valid = array.len() == m.fields.len();
                if valid {
                    for (key, field) in &m.fields {
                        let i: usize = key.parse().map_err(|_| invalid("tuple contract"))?;
                        valid &= fits(&field.model, &array[i], depth + 1)?;
                    }
                }
                valid
            } else {
                false
            }
        }
        "array" | "map" => {
            let entries: Option<Vec<&Value>> = if m.kind == "array" {
                value.as_array().map(|a| a.iter().collect())
            } else {
                value.as_object().map(|a| a.values().collect())
            };
            if let Some(entries) = entries {
                let item = m
                    .item
                    .as_deref()
                    .ok_or_else(|| invalid("collection contract"))?;
                let mut valid = true;
                for v in entries {
                    if !fits(item, v, depth + 1)? {
                        valid = false;
                        break;
                    }
                }
                valid
            } else {
                false
            }
        }
        "null" => value.is_null(),
        "boolean" => value.is_boolean(),
        "integer" => value.as_i64().is_some() || value.as_u64().is_some(),
        "number" => value.is_number(),
        "string" => value
            .as_str()
            .is_some_and(|s| m.pattern.as_deref().is_none_or(|p| pattern_matches(p, s))),
        _ => return Err(invalid("unknown model kind")),
    };
    if !ok
        || m.constant.as_ref().is_some_and(|c| c != value)
        || m.enumeration.as_ref().is_some_and(|e| !e.contains(value))
    {
        return Ok(false);
    }
    // Integral scalar limits are compared without a floating-point conversion.
    if m.kind == "integer" {
        let number = value
            .as_i64()
            .map(i128::from)
            .or_else(|| value.as_u64().map(i128::from))
            .unwrap();
        for (limit, lower) in [(&m.minimum, true), (&m.maximum, false)] {
            if let Some(limit) = limit {
                let bound = limit
                    .as_i64()
                    .map(i128::from)
                    .or_else(|| limit.as_u64().map(i128::from))
                    .ok_or_else(|| invalid("integer limit contract"))?;
                if (lower && number < bound) || (!lower && number > bound) {
                    return Ok(false);
                }
            }
        }
    }
    Ok(true)
}

fn scalar_sql(m: &Model, value: &Value) -> StoreResult<SqlValue> {
    Ok(match m.kind.as_str() {
        "null" => SqlValue::Null,
        "boolean" => SqlValue::Integer(i64::from(
            value.as_bool().ok_or_else(|| invalid("boolean"))?,
        )),
        "string" => SqlValue::Text(value.as_str().ok_or_else(|| invalid("string"))?.into()),
        "integer" | "number" => SqlValue::Text(value.to_string()),
        _ => return Err(invalid("scalar contract")),
    })
}

/// Caller owns the transaction. A failed body insert must roll back together
/// with its version, membership, head and receipt; this codec never commits.
pub(crate) fn put(
    c: &rusqlite::Transaction<'_>,
    name: &str,
    value: &Value,
) -> StoreResult<SqlValue> {
    if !fits(name, value, 0)? {
        return Err(invalid(&format!("value does not match {name} contract")));
    }
    write(c, name, value)
}
fn write(c: &Connection, name: &str, value: &Value) -> StoreResult<SqlValue> {
    let m = model(name)?;
    if scalar(m) {
        return scalar_sql(m, value);
    }
    let mut columns = Vec::new();
    let mut values = Vec::new();
    match m.kind.as_str() {
        "object" | "tuple" => {
            for (key, field) in &m.fields {
                let v = if m.kind == "object" {
                    value.get(key)
                } else {
                    value.get(
                        key.parse::<usize>()
                            .map_err(|_| invalid("tuple contract"))?,
                    )
                };
                let state = match v {
                    None => 0,
                    Some(Value::Null) => 1,
                    _ => 2,
                };
                columns.extend([quote(&format!("{key}__state")), quote(key)]);
                values.push(SqlValue::Integer(state));
                values.push(if state == 2 {
                    write(c, &field.model, v.unwrap())?
                } else {
                    SqlValue::Null
                });
            }
        }
        "union" => {
            let mut selected = None;
            for (i, variant) in m.variants.iter().enumerate() {
                if fits(variant, value, 0)? {
                    selected = Some((i, variant));
                    break;
                }
            }
            let (i, variant) = selected.ok_or_else(|| invalid("no branch"))?;
            columns.extend([quote("variant"), quote(&format!("v{i}"))]);
            values.extend([SqlValue::Integer(i as i64), write(c, variant, value)?]);
        }
        "array" | "map" => (),
        _ => return Err(invalid("row contract")),
    }
    let sql = if columns.is_empty() {
        format!("INSERT INTO {} DEFAULT VALUES", quote(&m.table))
    } else {
        format!(
            "INSERT INTO {} ({}) VALUES ({})",
            quote(&m.table),
            columns.join(","),
            vec!["?"; values.len()].join(",")
        )
    };
    c.prepare_cached(&sql)?
        .execute(rusqlite::params_from_iter(&values))?;
    let row = c.last_insert_rowid();
    if matches!(m.kind.as_str(), "array" | "map") {
        let item = m
            .item
            .as_deref()
            .ok_or_else(|| invalid("collection contract"))?;
        let sql = format!(
            "INSERT INTO {} VALUES (?,?,?)",
            quote(&format!("{}_items", m.table))
        );
        if m.kind == "array" {
            for (ordinal, v) in value.as_array().unwrap().iter().enumerate() {
                let child = write(c, item, v)?;
                c.prepare_cached(&sql)?
                    .execute(params![row, ordinal as i64, child])?;
            }
        } else {
            for (key, v) in value.as_object().unwrap() {
                let child = write(c, item, v)?;
                c.prepare_cached(&sql)?.execute(params![row, key, child])?;
            }
        }
    }
    Ok(SqlValue::Integer(row))
}

pub(crate) fn get(c: &Connection, name: &str, reference: SqlValue) -> StoreResult<Value> {
    let result = read(c, name, reference, &mut BTreeSet::new())?;
    if !fits(name, &result, 0)? {
        return Err(invalid("stored value violates closed contract"));
    }
    Ok(result)
}
fn read(
    c: &Connection,
    name: &str,
    reference: SqlValue,
    trail: &mut BTreeSet<(String, i64)>,
) -> StoreResult<Value> {
    let m = model(name)?;
    if scalar(m) {
        return match (m.kind.as_str(), reference) {
            ("null", SqlValue::Null) => Ok(Value::Null),
            ("boolean", SqlValue::Integer(n @ (0 | 1))) => Ok(Value::Bool(n == 1)),
            ("string", SqlValue::Text(text)) => Ok(Value::String(text)),
            ("integer" | "number", SqlValue::Text(text)) => {
                serde_json::from_str(&text).map_err(|_| invalid("stored number"))
            }
            _ => Err(invalid("stored scalar type")),
        };
    }
    let SqlValue::Integer(row_id) = reference else {
        return Err(invalid("stored row pointer"));
    };
    let marker = (name.to_owned(), row_id);
    if trail.len() >= MAX_DEPTH || !trail.insert(marker.clone()) {
        return Err(invalid("cyclic or excessive body nesting"));
    }
    let mut stmt = c.prepare_cached(&format!(
        "SELECT * FROM {} WHERE __row_id=?",
        quote(&m.table)
    ))?;
    let names: Vec<_> = stmt.column_names().into_iter().map(str::to_owned).collect();
    let row: BTreeMap<String, SqlValue> = stmt.query_row([row_id], |r| {
        names
            .iter()
            .enumerate()
            .map(|(i, name)| Ok((name.clone(), r.get(i)?)))
            .collect()
    })?;
    drop(stmt);
    let result = match m.kind.as_str() {
        "object" | "tuple" => {
            let mut fields = Map::new();
            for (key, field) in &m.fields {
                let state = row
                    .get(&format!("{key}__state"))
                    .ok_or_else(|| invalid("missing field state"))?;
                let v = row
                    .get(key)
                    .ok_or_else(|| invalid("missing field column"))?;
                match state {
                    SqlValue::Integer(0) if !field.required && *v == SqlValue::Null => (),
                    SqlValue::Integer(1)
                        if *v == SqlValue::Null && fits(&field.model, &Value::Null, 0)? =>
                    {
                        fields.insert(key.clone(), Value::Null);
                    }
                    SqlValue::Integer(2) if *v != SqlValue::Null => {
                        fields.insert(key.clone(), read(c, &field.model, v.clone(), trail)?);
                    }
                    _ => return Err(invalid("invalid field state")),
                }
            }
            if m.kind == "object" {
                Value::Object(fields)
            } else {
                Value::Array(
                    (0..m.fields.len())
                        .map(|i| {
                            fields
                                .remove(&i.to_string())
                                .ok_or_else(|| invalid("missing tuple element"))
                        })
                        .collect::<StoreResult<_>>()?,
                )
            }
        }
        "union" => {
            let Some(SqlValue::Integer(branch)) = row.get("variant") else {
                return Err(invalid("missing branch"));
            };
            let branch = usize::try_from(*branch).map_err(|_| invalid("invalid branch"))?;
            let variant = m
                .variants
                .get(branch)
                .ok_or_else(|| invalid("invalid branch"))?;
            for i in 0..m.variants.len() {
                if i != branch && row.get(&format!("v{i}")) != Some(&SqlValue::Null) {
                    return Err(invalid("multiple stored branches"));
                }
            }
            let value = row
                .get(&format!("v{branch}"))
                .ok_or_else(|| invalid("missing branch column"))?;
            read(c, variant, value.clone(), trail)?
        }
        "array" | "map" => {
            let key = if m.kind == "array" { "ordinal" } else { "name" };
            let sql = format!(
                "SELECT {key},item FROM {} WHERE owner=? ORDER BY {key}",
                quote(&format!("{}_items", m.table))
            );
            let entries: Vec<(SqlValue, SqlValue)> = c
                .prepare_cached(&sql)?
                .query_map([row_id], |r| Ok((r.get(0)?, r.get(1)?)))?
                .collect::<Result<_, _>>()?;
            let item = m
                .item
                .as_deref()
                .ok_or_else(|| invalid("collection contract"))?;
            let mut array = Vec::new();
            let mut map = Map::new();
            for (i, (key, v)) in entries.into_iter().enumerate() {
                let v = read(c, item, v, trail)?;
                if m.kind == "array" {
                    if key != SqlValue::Integer(i as i64) {
                        return Err(invalid("noncontiguous collection"));
                    }
                    array.push(v);
                } else {
                    let SqlValue::Text(key) = key else {
                        return Err(invalid("invalid map key"));
                    };
                    map.insert(key, v);
                }
            }
            if m.kind == "array" {
                Value::Array(array)
            } else {
                Value::Object(map)
            }
        }
        _ => return Err(invalid("row contract")),
    };
    trail.remove(&marker);
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};
    use universe_domain::canonical::canonical_serde;

    #[test]
    fn normative_bodies_reconstruct_after_restart_with_frozen_digests() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("typed.sqlite");
        let mut c = Connection::open(&path).unwrap();
        c.execute_batch(SQL).unwrap();
        c.execute_batch("CREATE TABLE proof_roots(name TEXT PRIMARY KEY, model TEXT NOT NULL, row_id INTEGER NOT NULL, expected_digest TEXT NOT NULL) STRICT;").unwrap();
        let mut oracle: Vec<Value> = serde_json::from_str(include_str!(
            "../../../docs/decisions/relational-storage/canonical-oracle.json"
        ))
        .unwrap();
        let semantics: Value = serde_json::from_str(include_str!(
            "../../../docs/decisions/relational-storage/semantic-oracle.json"
        ))
        .unwrap();
        for version in semantics["versions"].as_array().unwrap() {
            oracle.push(serde_json::json!({
                "name":format!("semantic:{}", version["version"].as_str().unwrap()),
                "value":version["value"], "digest":version["digest"],
                "canonical":String::from_utf8(canonical_serde(&version["value"]).to_bytes()).unwrap()
            }));
        }
        let tx = c.transaction().unwrap();
        for fixture in &oracle {
            let row = put(&tx, "Payload", &fixture["value"]).unwrap();
            tx.execute(
                "INSERT INTO proof_roots VALUES (?,'Payload',?,?)",
                params![fixture["name"].as_str(), row, fixture["digest"].as_str()],
            )
            .unwrap();
        }
        tx.commit().unwrap();
        drop(c);
        let c = Connection::open(&path).unwrap();
        for fixture in &oracle {
            let row = c
                .query_row(
                    "SELECT row_id FROM proof_roots WHERE name=?",
                    [fixture["name"].as_str().unwrap()],
                    |r| r.get(0),
                )
                .unwrap();
            let actual = get(&c, "Payload", row).unwrap();
            assert_eq!(actual, fixture["value"], "{}", fixture["name"]);
            let bytes = canonical_serde(&actual).to_bytes();
            assert_eq!(
                std::str::from_utf8(&bytes).unwrap(),
                fixture["canonical"].as_str().unwrap()
            );
            let mut digest = Sha256::new();
            digest.update(format!("{}:", actual["record_kind"].as_str().unwrap()));
            digest.update(bytes);
            assert_eq!(
                hex::encode(digest.finalize()),
                fixture["digest"].as_str().unwrap()
            );
        }
        assert_eq!(
            c.query_row("PRAGMA integrity_check", [], |r| r.get::<_, String>(0))
                .unwrap(),
            "ok"
        );
        assert_eq!(
            c.query_row("SELECT count(*) FROM pragma_foreign_key_check", [], |r| r
                .get::<_, i64>(
                0
            ))
            .unwrap(),
            0
        );
        // Independent Python decoder imports neither this codec nor its writer.
        let script = "import json,sqlite3,sys; from independent_audit import reader,encoded; from pathlib import Path; db=sqlite3.connect(sys.argv[1]);db.row_factory=sqlite3.Row; models=json.loads(Path('catalog.json').read_text())['models']; decode=reader(db,models); oracle=json.loads(Path('canonical-oracle.json').read_text()); expected={r['name']:r for r in oracle}; semantics=json.loads(Path('semantic-oracle.json').read_text()); expected.update({'semantic:'+r['version']:{**r,'canonical':encoded(r['value']).decode()} for r in semantics['versions']}); import hashlib; roots=list(db.execute('SELECT * FROM proof_roots')); assert len(roots)==len(expected);\nfor r in roots:\n v=decode(r['model'],r['row_id']);e=expected[r['name']];assert v==e['value'];assert encoded(v).decode()==e['canonical'];assert hashlib.sha256((v['record_kind']+':').encode()+encoded(v)).hexdigest()==r['expected_digest']==e['digest']\n";
        let output = std::process::Command::new("python3")
            .arg("-c")
            .arg(script)
            .arg(&path)
            .current_dir(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../docs/decisions/relational-storage"
            ))
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    #[test]
    fn closed_shapes_and_dropped_transactions_preserve_rows() {
        let mut c = Connection::open_in_memory().unwrap();
        c.execute_batch(SQL).unwrap();
        let before: i64 = c
            .query_row("SELECT count(*) FROM r_value", [], |r| r.get(0))
            .unwrap();
        {
            let tx = c.transaction().unwrap();
            put(
                &tx,
                "Value",
                &serde_json::json!({"kind":"integer","digits":"9007199254740993"}),
            )
            .unwrap();
            assert!(put(
                &tx,
                "Value",
                &serde_json::json!({"kind":"integer","digits":1})
            )
            .is_err());
            assert!(put(
                &tx,
                "RecordRef",
                &serde_json::json!({"record":"rec_000000000000000000000001","unexpected":true})
            )
            .is_err());
            assert!(put(
                &tx,
                "RecordRef",
                &serde_json::json!({"record":"rec_invalid"})
            )
            .is_err());
        }
        assert_eq!(
            c.query_row("SELECT count(*) FROM r_value", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            before
        );
        assert_eq!(
            c.query_row("SELECT count(*) FROM r_value_v2", [], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            0
        );
    }

    #[test]
    fn absence_null_exact_digits_and_collection_order_are_distinct() {
        let mut c = Connection::open_in_memory().unwrap();
        c.execute_batch(SQL).unwrap();
        let tx = c.transaction().unwrap();
        let absent = serde_json::json!({"record":"rec_000000000000000000000001"});
        let null = serde_json::json!({"record":"rec_000000000000000000000001", "universe":null});
        for input in [absent, null] {
            let row = put(&tx, "RecordRef", &input).unwrap();
            assert_eq!(get(&tx, "RecordRef", row).unwrap(), input);
        }
        for input in [
            serde_json::json!({"kind":"integer","digits":"+0007"}),
            serde_json::json!({"kind":"decimal","digits":"30.00"}),
            serde_json::json!({"kind":"rational","numerator":"0007","denominator":"03"}),
            serde_json::json!({"kind":"sequence","items":[{"kind":"text","text":"β"},{"kind":"text","text":"🌲"},{"kind":"text","text":"β"}]}),
            serde_json::json!({"kind":"structured","definition":"vdef_000000000000000000000001","fields":{"一":{"kind":"decimal","digits":"0.00"},"é":{"kind":"integer","digits":"9007199254740993"}}}),
        ] {
            let row = put(&tx, "Value", &input).unwrap();
            assert_eq!(get(&tx, "Value", row).unwrap(), input);
        }
        // Ordinary integer columns in the schema inventory also retain uint64
        // magnitudes as text rather than SQLite signed integers or REAL.
        for number in [serde_json::json!(u64::MAX), serde_json::json!(i64::MIN)] {
            let name = catalog()
                .models
                .iter()
                .find(|(_, m)| m.kind == "integer" && m.minimum.is_none() && m.maximum.is_none())
                .unwrap()
                .0;
            let stored = put(&tx, name, &number).unwrap();
            assert!(matches!(&stored, SqlValue::Text(_)));
            assert_eq!(get(&tx, name, stored).unwrap(), number);
        }
        tx.commit().unwrap();
        assert_eq!(
            c.query_row(
                "SELECT count(*) FROM r_record_ref WHERE universe__state=0",
                [],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
            1
        );
        assert_eq!(
            c.query_row(
                "SELECT count(*) FROM r_record_ref WHERE universe__state=1",
                [],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
            1
        );
    }

    #[test]
    fn typed_rows_are_immutable_and_corrupt_graphs_are_rejected() {
        let mut c = Connection::open_in_memory().unwrap();
        c.execute_batch(SQL).unwrap();
        let tx = c.transaction().unwrap();
        let input = serde_json::json!({"kind":"sequence","items":[]});
        let row = put(&tx, "Value", &input).unwrap();
        assert!(tx.execute("UPDATE r_value SET variant=0", []).is_err());
        assert!(tx.execute("DELETE FROM r_value", []).is_err());
        // Fixed pointers have physical foreign keys.
        assert!(tx
            .execute("INSERT INTO r_value(variant,v13) VALUES(13,999999)", [])
            .is_err());
        let owner: i64 = tx
            .query_row("SELECT items FROM r_value_v13", [], |r| r.get(0))
            .unwrap();
        let child = put(
            &tx,
            "Value",
            &serde_json::json!({"kind":"text","text":"one"}),
        )
        .unwrap();
        // An ordinal gap is not an alternative ordering convention.
        tx.execute(
            "INSERT INTO r_value_v13_items_items VALUES(?,1,?)",
            params![owner, child],
        )
        .unwrap();
        assert!(get(&tx, "Value", row.clone()).is_err());
        drop(tx);
        let tx = c.transaction().unwrap();
        let row = put(&tx, "Value", &input).unwrap();
        let owner: i64 = tx
            .query_row("SELECT items FROM r_value_v13", [], |r| r.get(0))
            .unwrap();
        // A recursive sequence pointing back at itself must never recurse
        // forever or reconstruct a body with fabricated replacement values.
        tx.execute(
            "INSERT INTO r_value_v13_items_items VALUES(?,0,?)",
            params![owner, row],
        )
        .unwrap();
        assert!(get(&tx, "Value", row).is_err());
    }
}
