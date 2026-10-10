//! Ordinary authored dates normalize to existing exact coordinates; no clock defaults.
use super::*;
use universe_domain::{chronology::Chronology, temporal::TemporalExpression};

pub(super) fn normalize<T: Serialize + serde::de::DeserializeOwned>(
    input: T,
    frame: &Frame,
    rows: &[RecordVersion],
) -> anyhow::Result<T> {
    let clock = rows.iter().find(|r|r.identity.record_id==frame.context.record)
        .and_then(|r|if let Payload::RepresentedContext(c)=&r.payload{c.chronology.as_ref()}else{None})
        .filter(|clock|match &frame.time {
            FrameTime::At{time:TemporalExpression::Exact{calendar,..}}=>calendar==&clock.calendar,
            FrameTime::Timeless=>true,
            _=>false,
        });
    let mut value=serde_json::to_value(input)?;
    visit(&mut value,clock,rows,"writing")?;
    Ok(serde_json::from_value(value)?)
}
fn visit(value:&mut Value, clock:Option<&Chronology>, rows:&[RecordVersion], path:&str)->anyhow::Result<()> {
    match value {
        Value::Array(items)=>for (index,item) in items.iter_mut().enumerate(){visit(item,clock,rows,&format!("{path}[{index}]"))?;},
        Value::Object(fields)=>{
            let dated=fields.iter().any(|(key,value)|key.ends_with("_date") && !value.is_null()) || fields.get("lifetime").is_some_and(|v|!v["end_date"].is_null());
            if dated {
                let handle=fields.iter().filter(|(key,_)|key.ends_with("_handle")).find_map(|(_,v)|v.as_str())
                    .or_else(||fields.get("start").and_then(|v|v["event_handle"].as_str()));
                if let (Some(clock),Some(original))=(clock,handle.and_then(|handle|rows.iter().find(|r|r.identity.record_id.as_str()==handle || r.record_version_id.as_str()==handle))) {
                    let original=serde_json::to_value(&original.payload)?;
                    for field in ["validity","time","sent_at","received_at"] {
                        if let Some(calendar)=original[field]["calendar"].as_str() {
                            if calendar!=clock.calendar.as_str(){anyhow::bail!("{path}: the selected date calendar differs from the original authored calendar; no conversion was performed.");}
                        }
                    }
                }
            }

            for (tick,date) in [("at_tick","at_date"),("sent_tick","sent_date"),("received_tick","received_date"),("end_tick","end_date")] {
                if let Some(date_value)=fields.remove(date).filter(|v|!v.is_null()) {
                    let authored=date_value.as_str().ok_or_else(||anyhow::anyhow!("{path}.{date}: enter an authored date string."))?;
                    let clock=clock.ok_or_else(||anyhow::anyhow!("{path}.{date}: select an authored calendar with a readable chronology; no calendar or current date was inferred."))?;
                    let coordinate=clock.coordinate(authored).map_err(|e|anyhow::anyhow!("{path}.{date}: {e}"))?;
                    if let Some(supplied)=fields.get(tick).and_then(Value::as_str).filter(|v|!v.is_empty()) {
                        let same=supplied.parse::<i128>().ok().zip(coordinate.parse::<i128>().ok()).is_some_and(|(a,b)|a==b);
                        if !same {anyhow::bail!("{path}: {date} and {tick} disagree; explicitly correct the date or coordinate.");}
                    } else {fields.insert(tick.into(),json!(coordinate));}
                }
                if fields.get(tick).and_then(Value::as_str).is_some_and(str::is_empty) {
                    anyhow::bail!("{path}: supply {tick} or {date} explicitly.");
                }
            }
            // These are authored values, named role maps and source prose, not temporal DTOs.
            for (key,item) in fields.iter_mut().filter(|(key,_)|!matches!(key.as_str(),"value"|"participants"|"claim"|"content"|"metadata"|"labels"|"text")) {
                visit(item,clock,rows,&format!("{path}.{key}"))?;
            }
        },
        _=>(),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn selected_clock_conflicts_and_non_temporal_values_are_preserved() {
        let frame:Frame=serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000009"},"time":{"kind":"timeless"},"perspective":"author"})).unwrap();
        let calendar=universe_domain::ids::CalendarId::parse("cal_000000000000000000000001").unwrap();
        let clock=universe_domain::chronology::UniverseStart::Gregorian{timestamp:"1970-01-01T00:00:00+00:00".into()}.build(calendar.clone()).unwrap().0;
        let row=RecordVersion::build(universe_domain::ids::RecordVersionId::generate(&mut rand::rng()),RecordIdentity::new(frame.universe.clone(),frame.context.record.clone(),RecordKind::RepresentedContext),serde_json::from_value(json!({"record_kind":"represented_context","universe":frame.universe,"kind":{"kind":"objective"},"labels":{},"chronology":clock})).unwrap()).unwrap();
        let input=json!({"at_date":"1970-01-01T00:00:10+00:00","at_tick":"00010","participants":{"at_date":"Mara"},"value":{"end_date":"an authored phrase"},"lifetime":{"kind":"until","end_date":"1970-01-01T00:00:20+00:00"},"minimum_delay":"3"});
        let normalized=normalize(input.clone(),&frame,std::slice::from_ref(&row)).unwrap();
        assert_eq!(normalized["at_tick"],"00010");
        assert_eq!(normalized["lifetime"]["end_tick"],"20");
        assert_eq!(normalized["participants"],input["participants"]);
        assert_eq!(normalized["value"],input["value"]);
        assert_eq!(normalized["minimum_delay"],"3");
        assert!(normalize(input.clone(),&frame,&[]).unwrap_err().to_string().contains("readable chronology"));
        let mut conflict=input.clone();conflict["at_tick"]=json!("11");
        assert!(normalize(conflict,&frame,std::slice::from_ref(&row)).unwrap_err().to_string().contains("disagree"));
        let mut malformed=input.clone();malformed["at_date"]=json!("tomorrow");
        assert!(normalize(malformed,&frame,std::slice::from_ref(&row)).unwrap_err().to_string().contains("RFC3339"));
        let mut incompatible=frame.clone();incompatible.time=FrameTime::At{time:TemporalExpression::Exact{calendar:universe_domain::ids::CalendarId::parse("cal_000000000000000000000002").unwrap(),value:"10".into()}};
        assert!(normalize(input,&incompatible,&[row]).unwrap_err().to_string().contains("readable chronology"));
    }
}
