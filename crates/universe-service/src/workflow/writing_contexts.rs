//! Explicit authored contexts; parentage is structure, never inherited truth.
use super::*;
use universe_protocol::writing::{CheckChanges, WritingCheck};

pub(super) fn named_context(rows: &[RecordVersion], name: &str) -> Option<RecordId> {
    let matches:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::RepresentedContext(c) if r.identity.record_id.as_str()==name || c.labels.values().any(|n|n==name) || matches!(&c.kind,RepresentedContextKind::Authored{label}if label==name))).collect();
    let [row] = matches.as_slice() else {
        return None;
    };
    Some(row.identity.record_id.clone())
}
impl Workflow<'_> {
    pub(super) fn writing_story_contexts(
        &self,
        input: &CheckChanges,
        ctx: &Context,
        rows: &[RecordVersion],
        operations: &mut Vec<Value>,
        result: &mut WritingCheck,
    ) -> anyhow::Result<()> {
        let mut introduced = BTreeSet::new();
        for context in &input.story_contexts {
            let built = (|| -> anyhow::Result<Option<Value>> {
                if context.name.trim().is_empty() {
                    anyhow::bail!("Name the authored context explicitly.");
                }
                if let Some(id)=named_context(rows,&context.name) {
                    if matches!(context.kind,universe_protocol::writing::StoryContextKind::Narrator) {
                        let holder=super::writing_connected::object(rows,context.narrator.as_deref().ok_or_else(||anyhow::anyhow!("Select the existing narrator explicitly."))?,&ctx.frame).ok_or_else(||anyhow::anyhow!("Select one existing narrator identity."))?;
                        if !rows.iter().any(|r|r.identity.record_id==id&&matches!(&r.payload,Payload::RepresentedContext(c)if matches!(&c.kind,RepresentedContextKind::Narrator{narrator}if narrator.record==holder))){anyhow::bail!("This context has another authored kind or narrator; declaration does not revise it.");}
                    }
                    return Ok(None);
                }
                if rows.iter().any(|r|matches!(&r.payload,Payload::RepresentedContext(c)if c.labels.values().any(|n|n==&context.name)||matches!(&c.kind,RepresentedContextKind::Authored{label}if label==&context.name))) {anyhow::bail!("Select one accessible authored context; this name is ambiguous.");}
                if !context.introduce || self.scope.is_some() {
                    anyhow::bail!("Select an accessible context or explicitly introduce it with universe-wide authoring access.");
                }
                if !introduced.insert(&context.name) {
                    anyhow::bail!("Declare each new context once per delta.");
                }
                let parent = named_context(rows, &context.parent).ok_or_else(|| {
                    anyhow::anyhow!("Select one accessible parent context explicitly.")
                })?;
                let calendars:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::Calendar(c)if c.key==context.calendar||c.labels.values().any(|n|n==&context.calendar))).collect();
                let [calendar] = calendars.as_slice() else {
                    anyhow::bail!("Select one accessible authored calendar explicitly.");
                };
                let calendar_id = CalendarId::parse(
                    &calendar
                        .identity
                        .record_id
                        .as_str()
                        .replacen("rec_", "cal_", 1),
                )?;
                let clocks: Vec<_> = rows
                    .iter()
                    .filter_map(|r| {
                        if let Payload::RepresentedContext(c) = &r.payload {
                            c.chronology.as_ref().filter(|c| c.calendar == calendar_id)
                        } else {
                            None
                        }
                    })
                    .collect();
                let Some(clock) = clocks.first() else {
                    anyhow::bail!("This calendar has no authored clock system; declare it before creating a timed context.");
                };
                if clocks.iter().any(|other| other.system != clock.system) {
                    anyhow::bail!("The selected calendar has conflicting authored clock systems.");
                }
                let mut chronology = (*clock).clone();
                let time = chronology
                    .coordinate(&context.story_time)
                    .map_err(|e| anyhow::anyhow!(e))?;
                chronology.first_interaction = time.clone();
                chronology.current = time;
                chronology.validate().map_err(|e| anyhow::anyhow!(e))?;
                let narrator = match context.kind { universe_protocol::writing::StoryContextKind::Narrator => Some(super::writing_connected::object(rows, context.narrator.as_deref().ok_or_else(||anyhow::anyhow!("Select an existing narrator entity explicitly."))?, &ctx.frame).ok_or_else(||anyhow::anyhow!("Select one accessible existing narrator entity."))?), _ if context.narrator.is_some()=>anyhow::bail!("Narrator identity applies only to narrator contexts."), _=>None };
                let kind = serde_json::to_value(context.kind)?
                    .as_str()
                    .unwrap()
                    .to_string();
                Ok(Some(
                    json!({"kind":"record_narrative_reference","client_ref":RecordId::generate(&mut rand::rng()),"record":"represented_context","payload":{"record_kind":"represented_context","universe":ctx.frame.universe,"kind":match narrator {Some(id)=>json!({"kind":"narrator","narrator":{"universe":ctx.frame.universe,"record":id}}),None=>json!({"kind":"authored","label":format!("{kind}: {}",context.name)})},"parent":{"universe":ctx.frame.universe,"record":parent},"chronology":chronology,"labels":{"en":context.name}}}),
                ))
            })();
            match built {
                Ok(Some(op)) => {
                    operations.push(op);
                    result.additions.push(format!("New authored context: {} (parent {}; explicit time {}). Publish and open it before adding local facts.",context.name,context.parent,context.story_time));
                }
                Ok(None) => result
                    .unchanged
                    .push(format!("Existing context: {}", context.name)),
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        Ok(())
    }
}

impl Workflow<'_> {
    pub(super) fn writing_narrative(&self,input:&CheckChanges,ctx:&Context,rows:&[RecordVersion],ops:&mut Vec<Value>,result:&mut WritingCheck)->anyhow::Result<()> {
        let u=&ctx.frame.universe;
        let unique_work=|name:&str|->anyhow::Result<&RecordVersion>{let found:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::Work(w)if w.title==name||w.labels.values().any(|n|n==name))).collect(); match found.as_slice(){[r]=>Ok(*r),_=>anyhow::bail!("Select one accessible existing work named '{name}'.")}};
        let mut declared=BTreeSet::new();
        for w in &input.narrative_works {
            let built=(||->anyhow::Result<Option<Value>>{
                if w.name.trim().is_empty(){anyhow::bail!("Name the work explicitly.");}
                if let Ok(r)=unique_work(&w.name){if matches!(&r.payload,Payload::Work(old)if old.kind==w.kind){return Ok(None)}anyhow::bail!("The existing work has another authored kind; this declaration does not revise it.");}
                if rows.iter().any(|r|matches!(&r.payload,Payload::Work(old)if old.title==w.name||old.labels.values().any(|n|n==&w.name))) || !w.introduce || self.scope.is_some() || !declared.insert(format!("work:{}",w.name)){anyhow::bail!("Select one work or explicitly introduce a unique new work with universe-wide access.");}
                Ok(Some(json!({"kind":"create_work","client_ref":RecordId::generate(&mut rand::rng()),"record":{"kind":w.kind,"title":w.name,"labels":{},"sourceRefs":[],"versions":[],"worldAssociations":[]}})))
            })();
            match built{Ok(Some(op))=>{ops.push(op);result.additions.push(format!("New work: {}. Publish before declaring its edition.",w.name));},Ok(None)=>result.unchanged.push(format!("Existing work: {}",w.name)),Err(e)=>result.clarifications.push(e.to_string())}
        }
        for edition in &input.work_editions {
            let built=(||->anyhow::Result<Option<Value>>{
                if edition.name.trim().is_empty(){anyhow::bail!("Name the edition explicitly.");}
                let work=unique_work(&edition.work)?;
                let found:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::WorkVersion(v)if v.work.record==work.identity.record_id&&v.version_label==edition.name)).collect();
                if found.len()==1{return Ok(None)}
                if !found.is_empty() || !edition.introduce || self.scope.is_some() || !declared.insert(format!("edition:{}:{}",edition.work,edition.name)){anyhow::bail!("Select one edition or explicitly introduce it with universe-wide access.");}
                let binding=match edition.binding{universe_protocol::writing::WritingEditionBinding::Current=>json!({"kind":"bound","continuity":ctx.frame.continuity,"revision":ctx.frame.revision}),universe_protocol::writing::WritingEditionBinding::Unbound=>json!({"kind":"unbound"})};
                Ok(Some(json!({"kind":"record_narrative_reference","client_ref":RecordId::generate(&mut rand::rng()),"record":"work_version","payload":{"record_kind":"work_version","work":RecordRef::new(u.clone(),work.identity.record_id.clone()),"versionLabel":edition.name,"binding":binding}})))
            })();
            match built{Ok(Some(op))=>{ops.push(op);result.additions.push(format!("New edition: {} / {}. Publish before referencing it from a scene.",edition.work,edition.name));},Ok(None)=>result.unchanged.push(format!("Existing edition: {} / {}",edition.work,edition.name)),Err(e)=>result.clarifications.push(e.to_string())}
        }
        for scene in &input.scenes {
            let built=(||->anyhow::Result<Option<Value>>{
                if scene.name.trim().is_empty(){anyhow::bail!("Name the scene explicitly.");}
                let work=unique_work(&scene.work)?;
                let editions:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::WorkVersion(v)if v.work.record==work.identity.record_id&&v.version_label==scene.edition)).collect();
                let [edition]=editions.as_slice()else{anyhow::bail!("Select one published accessible edition explicitly.");};
                let context=named_context(rows,&scene.narration_context).ok_or_else(||anyhow::anyhow!("Select one accessible narration context explicitly."))?;
                if !rows.iter().any(|r|r.identity.record_id==context&&matches!(&r.payload,Payload::RepresentedContext(c)if matches!(c.kind,RepresentedContextKind::Narrator{..})&&c.chronology.is_some())){anyhow::bail!("Select an actual narrator context with explicit authored narration time.");}
                let viewpoint=scene.viewpoint.as_ref().map(|name|super::writing_connected::object(rows,name,&ctx.frame).map(|id|RecordRef::new(u.clone(),id)).ok_or_else(||anyhow::anyhow!("Select one accessible viewpoint entity explicitly."))).transpose()?;
                let events:Vec<_>=scene.depicted_events.iter().map(|handle|rows.iter().find(|r|r.record_version_id.as_str()==handle&&matches!(&r.payload,Payload::Event(e)if e.occurrence==OccurrenceMode::Occurred)).map(|r|RecordRef::new(u.clone(),r.identity.record_id.clone())).ok_or_else(||anyhow::anyhow!("Retrieve the current occurred-event handle; absent/restricted/stale events cannot be linked."))).collect::<anyhow::Result<_>>()?;
                let version=universe_domain::value::VersionRef{universe:Some(u.clone()),record:edition.identity.record_id.clone(),version:edition.record_version_id.clone()};
                let payload=json!({"record_kind":"scene_ref","workVersion":version,"sceneId":scene.name,"disclosedRecords":[],"viewpoint":viewpoint,"narrativePosition":scene.reader_order,"depictedEvents":events,"narrationFrame":RecordRef::new(u.clone(),context),"worldAssociations":[]});
                let found:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::SceneRef(s)if s.work_version==version&&s.scene_id==scene.name)).collect();
                if found.len()==1 {if found[0].payload==serde_json::from_value::<Payload>(payload.clone())? {return Ok(None)}anyhow::bail!("This scene already exists with other authored settings; declaration does not revise it.");}
                if !found.is_empty() || !scene.introduce || self.scope.is_some() || !declared.insert(format!("scene:{}:{}:{}",scene.work,scene.edition,scene.name)){anyhow::bail!("Select one scene or explicitly introduce it with universe-wide access.");}
                Ok(Some(json!({"kind":"record_narrative_reference","client_ref":RecordId::generate(&mut rand::rng()),"record":"scene_ref","payload":payload})))
            })();
            match built{Ok(Some(op))=>{ops.push(op);result.additions.push(format!("Scene: {}. Narration context, depicted events and reader order are separate; no reader disclosure inferred.",scene.name));},Ok(None)=>result.unchanged.push(format!("Existing scene: {}",scene.name)),Err(e)=>result.clarifications.push(e.to_string())}
        }
        Ok(())
    }
}
