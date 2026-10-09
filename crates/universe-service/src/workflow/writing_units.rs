//! Exact named unit binding; conversions remain separately authored advanced definitions.
use super::*;
use universe_protocol::writing::*;
pub(super) fn unit(rows: &[RecordVersion], name: &str) -> anyhow::Result<UnitId> {
    let ids: Vec<_> = rows
        .iter()
        .filter_map(|r| {
            if let Payload::Unit(u) = &r.payload {
                (u.key == name || u.symbol == name || u.labels.values().any(|v| v == name))
                    .then(|| r.identity.record_id.clone())
            } else {
                None
            }
        })
        .collect();
    match ids.as_slice(){[id]=>Ok(UnitId::from_id(id.clone())?),_=>anyhow::bail!("Which exact authored unit is '{name}'? Research the visible unit names; ambiguity or absence cannot imply conversion.")}
}
impl Workflow<'_> {
    pub(super) fn writing_units(
        &self,
        input: &CheckChanges,
        base: &[RecordVersion],
        ops: &mut Vec<Value>,
        result: &mut WritingCheck,
    ) -> anyhow::Result<()> {
        let mut names = BTreeSet::new();
        for declaration in &input.units {
            if declaration.name.trim().is_empty()
                || declaration.dimension.trim().is_empty()
                || declaration.symbol.trim().is_empty()
                || !names.insert(declaration.name.clone())
            {
                result.clarifications.push("Unit name, explicit dimension and symbol must be nonempty and unique in this delta.".into());
                continue;
            }
            let existing: Vec<_> = base
                .iter()
                .filter_map(|r| {
                    if let Payload::Unit(u) = &r.payload {
                        (u.key == declaration.name
                            || u.labels.values().any(|v| v == &declaration.name))
                        .then_some(u)
                    } else {
                        None
                    }
                })
                .collect();
            if declaration.introduce && existing.is_empty() {
                ops.push(json!({"kind":"define_unit","client_ref":RecordId::generate(&mut rand::rng()),"record":{"namespace":"authoring","key":declaration.name,"dimension":declaration.dimension,"symbol":declaration.symbol,"labels":{},"base":null,"validity":{"kind":"unspecified"}}}));
                result.additions.push(format!("Explicit unit: {}; dimension {}; symbol {}; no conversion declared. Use private contract review.",declaration.name,declaration.dimension,declaration.symbol));
            } else if !declaration.introduce
                && existing.len() == 1
                && existing[0].dimension == declaration.dimension
                && existing[0].symbol == declaration.symbol
            {
                result
                    .unchanged
                    .push(format!("Authored unit: {}", declaration.name));
            } else {
                result.clarifications.push(format!("Resolve existing unit '{}' or revise it explicitly; no duplicate or conversion is inferred.",declaration.name));
            }
        }
        Ok(())
    }
}
