//! Small typed definition forms. No expression or JSON text is executable input.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{
    ids::{RecordId, UnitId},
    records::DomainOperation,
};
#[derive(Clone, Default)]
struct DefinitionForm {
    kind: String,
    namespace: String,
    key: String,
    label: String,
    shape: String,
    multiplicity: String,
    unit: String,
    roles: String,
    dimension: String,
    symbol: String,
    epoch: String,
}
impl DefinitionForm {
    fn operation(&self) -> Result<Value, String> {
        if self.namespace.trim().is_empty() || self.key.trim().is_empty() {
            return Err("Enter a namespace and definition key.".into());
        }
        let label = if self.label.trim().is_empty() {
            self.key.clone()
        } else {
            self.label.clone()
        };
        let mut record = json!({"namespace":self.namespace,"key":self.key,"labels":{"en":label}});
        let kind = match self.kind.as_str() {
            "type" => {
                record["parents"] = json!([]);
                record["classificationExecutable"] = json!(false);
                "define_type"
            }
            "property" => {
                if ![
                    "text",
                    "boolean",
                    "integer",
                    "decimal",
                    "rational",
                    "temporal",
                    "entity_ref",
                    "range",
                    "quantity",
                ]
                .contains(&self.shape.as_str())
                {
                    return Err("Choose a property value shape.".into());
                }
                if !["single", "multiple"].contains(&self.multiplicity.as_str()) {
                    return Err("Choose one or multiple values explicitly.".into());
                }
                record["subjectTypes"] = json!([]);
                record["value"] = if self.shape == "quantity" {
                    json!({"kind":"quantity","unit":UnitId::parse(self.unit.trim()).map_err(|e|e.to_string())?})
                } else if self.shape == "range" {
                    json!({"kind":"range","unit":null})
                } else if self.shape == "entity_ref" {
                    json!({"kind":"entity_ref","subject_types":[]})
                } else {
                    json!({"kind":self.shape})
                };
                record["multiplicity"] = json!(self.multiplicity);
                record["unitDimension"] = Value::Null;
                record["persistence"] = json!("unspecified");
                record["exclusive"] = json!(false);
                record["inverse"] = Value::Null;
                record["symmetric"] = json!(false);
                record["transitive"] = json!(false);
                "define_property"
            }
            "relation" => {
                let names: Vec<_> = self.roles.split(',').map(str::trim).collect();
                if names.iter().any(|s| s.is_empty())
                    || names
                        .iter()
                        .collect::<std::collections::BTreeSet<_>>()
                        .len()
                        != names.len()
                {
                    return Err("Enter distinct, nonempty relationship role names.".into());
                }
                record["roles"]=json!(names.iter().map(|name|json!({"name":name,"participantTypes":[],"multiplicity":"multiple","ordered":false})).collect::<Vec<_>>());
                "define_relation"
            }
            "unit" => {
                if self.dimension.trim().is_empty() || self.symbol.trim().is_empty() {
                    return Err("Enter a unit dimension and symbol.".into());
                }
                record["dimension"] = json!(self.dimension);
                record["symbol"] = json!(self.symbol);
                record["base"] = Value::Null;
                record["validity"] = json!({"kind":"unspecified"});
                "define_unit"
            }
            "calendar" => {
                if !self.epoch.trim().is_empty() {
                    record["epoch"] = json!(self.epoch);
                }
                record["unitStructure"] = json!({});
                record["conversions"] = json!([]);
                "define_calendar"
            }
            _ => return Err("Choose a definition kind.".into()),
        };
        let operation =
            json!({"kind":kind,"client_ref":RecordId::generate(&mut rand::rng()),"record":record});
        let checked: DomainOperation =
            serde_json::from_value(operation).map_err(|e| e.to_string())?;
        serde_json::to_value(checked).map_err(|e| e.to_string())
    }
}
#[component]
pub fn DefinitionEditor(
    namespaces: Vec<super::select::Choice>,
    disabled: bool,
    onadd: EventHandler<Value>,
) -> Element {
    let mut form = use_signal(DefinitionForm::default);
    let mut error = use_signal(String::new);
    rsx! {details{
        summary{"Define a type, property, relationship, unit or calendar"}
        p{"Definitions are reviewed as protected changes. This form adds no inheritance, persistence, unit conversion or inter-calendar conversion implicitly."}
        label{r#for:"definition-kind","Definition kind"}super::select::RichSelect {id:"definition-kind",disabled,value:form.read().kind.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().kind=e.value(),options:super::select::choices(&[("","Choose a kind"),("type","Entity type"),("property","Property"),("relation","Relationship"),("unit","Unit"),("calendar","Calendar")])}
        label{r#for:"definition-namespace","Namespace"}super::select::RichSelect{id:"definition-namespace",disabled,value:form.read().namespace.clone(),allow_new:true,options:namespaces,onchange:move|e:crate::select::SelectionEvent|form.write().namespace=e.value()}
        label{r#for:"definition-key","Definition key"}input{id:"definition-key",disabled,value:form.read().key.clone(),oninput:move|e|form.write().key=e.value()}
        label{r#for:"definition-label","Display name"}input{id:"definition-label",disabled,value:form.read().label.clone(),oninput:move|e|form.write().label=e.value()}
        if form.read().kind=="property"{
            label{r#for:"definition-shape","Value shape"}super::select::RichSelect {id:"definition-shape",disabled,value:form.read().shape.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().shape=e.value(),options:super::select::choices(&[("","Choose a shape"),("text","Text"),("boolean","Boolean"),("integer","Integer"),("decimal","Decimal"),("rational","Rational"),("temporal","Temporal"),("entity_ref","Entity Ref"),("range","Range"),("quantity","Quantity")])}
            if form.read().shape=="quantity"{label{r#for:"definition-unit","Unit ID"}input{id:"definition-unit",disabled,value:form.read().unit.clone(),oninput:move|e|form.write().unit=e.value()}}
            label{r#for:"definition-multiplicity","Number of values"}super::select::RichSelect {id:"definition-multiplicity",disabled,value:form.read().multiplicity.clone(),onchange:move|e: crate::select::SelectionEvent|form.write().multiplicity=e.value(),options:super::select::choices(&[("","Choose multiplicity"),("single","One value per subject"),("multiple","Multiple values")])}
        }
        if form.read().kind=="relation"{label{r#for:"definition-roles","Role names, separated by commas"}input{id:"definition-roles",disabled,value:form.read().roles.clone(),oninput:move|e|form.write().roles=e.value()}p{"Each named role permits multiple unordered participants. More restrictive role definitions can be introduced through reviewed proposals."}}
        if form.read().kind=="unit"{label{r#for:"definition-dimension","Dimension"}input{id:"definition-dimension",disabled,value:form.read().dimension.clone(),oninput:move|e|form.write().dimension=e.value()}label{r#for:"definition-symbol","Symbol"}input{id:"definition-symbol",disabled,value:form.read().symbol.clone(),oninput:move|e|form.write().symbol=e.value()}}
        if form.read().kind=="calendar"{label{r#for:"definition-epoch","Optional authored epoch"}input{id:"definition-epoch",disabled,value:form.read().epoch.clone(),oninput:move|e|form.write().epoch=e.value()}p{"A named calendar supports explicit values. Defining its name does not establish conversion to another clock."}}
        if !error().is_empty(){p{role:"alert","{error}"}}
        button{class:"secondary",disabled,onclick:move|_|match form.read().operation(){Ok(op)=>{onadd.call(op);error.set(String::new());},Err(e)=>error.set(e)},"Add definition to draft"}
    }}
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn definitions_require_typed_choices_and_distinct_roles() {
        let mut f = DefinitionForm {
            kind: "property".into(),
            namespace: "story".into(),
            key: "age".into(),
            ..Default::default()
        };
        assert!(f.operation().is_err());
        f.shape = "integer".into();
        assert!(f.operation().is_err());
        f.multiplicity = "single".into();
        assert!(f.operation().is_ok());
        for shape in ["range", "quantity"] {
            f.shape = shape.into();
            f.unit = "unit_000000000000000000000001".into();
            if shape == "range" {
                assert!(f.operation().is_ok());
            }
        }
        f.kind = "relation".into();
        f.roles = "sender,sender".into();
        assert!(f.operation().is_err());
        f.roles = "sender,receiver".into();
        assert!(f.operation().is_ok());
        for kind in ["type", "unit", "calendar"] {
            f.kind = kind.into();
            f.dimension = "length".into();
            f.symbol = "m".into();
            assert!(f.operation().is_ok(), "{kind}");
        }
    }
}
