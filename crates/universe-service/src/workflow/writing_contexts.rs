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
                let payload=json!({"record_kind":"scene_ref","workVersion":version,"sceneId":scene.name,"disclosedRecords":self.writing_disclosures(&scene.disclosures,&version,ctx,rows)?,"viewpoint":viewpoint,"narrativePosition":scene.reader_order,"depictedEvents":events,"narrationFrame":RecordRef::new(u.clone(),context),"worldAssociations":[]});
                let found:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::SceneRef(s)if s.work_version==version&&s.scene_id==scene.name)).collect();
                if found.len()==1 {if found[0].payload==serde_json::from_value::<Payload>(payload.clone())? {return Ok(None)}anyhow::bail!("This scene already exists with other authored settings; declaration does not revise it.");}
                if !found.is_empty() || !scene.introduce || self.scope.is_some() || !declared.insert(format!("scene:{}:{}:{}",scene.work,scene.edition,scene.name)){anyhow::bail!("Select one scene or explicitly introduce it with universe-wide access.");}
                Ok(Some(json!({"kind":"record_narrative_reference","client_ref":RecordId::generate(&mut rand::rng()),"record":"scene_ref","payload":payload})))
            })();
            match built{Ok(Some(op))=>{ops.push(op);result.additions.push(format!("Scene: {}. Narration context, depicted events and reader order are separate; no reader disclosure inferred.",scene.name));},Ok(None)=>result.unchanged.push(format!("Existing scene: {}",scene.name)),Err(e)=>result.clarifications.push(e.to_string())}
        }
        let mut corrected=BTreeSet::new();
        for correction in &input.scene_corrections {
            let built=(||->anyhow::Result<Option<Value>>{
                let row=rows.iter().find(|r|r.record_version_id.as_str()==correction.scene_handle && matches!(r.payload,Payload::SceneRef(_))).ok_or_else(||anyhow::anyhow!("Retrieve one current accessible scene handle; stale or missing scenes cannot be corrected."))?;
                if correction.reason.trim().is_empty() || !corrected.insert(row.identity.record_id.clone()){anyhow::bail!("Explain each scene correction and edit a scene only once per delta.");}
                let Payload::SceneRef(old)=&row.payload else{unreachable!()};let mut new=old.clone();
                if let Some(name)=&correction.narration_context {let id=named_context(rows,name).ok_or_else(||anyhow::anyhow!("Select one accessible narration context."))?;if !rows.iter().any(|r|r.identity.record_id==id && matches!(&r.payload,Payload::RepresentedContext(c)if matches!(c.kind,RepresentedContextKind::Narrator{..})&&c.chronology.is_some())){anyhow::bail!("Select an actual narrator context with explicit narration time.");}new.narration_frame=Some(RecordRef::new(u.clone(),id));}
                if correction.clear_viewpoint && correction.viewpoint.is_some() || correction.clear_reader_order && correction.reader_order.is_some(){anyhow::bail!("Choose replacement or explicit clearing, not both.");}
                if correction.clear_viewpoint {new.viewpoint=None;}else if let Some(name)=&correction.viewpoint {new.viewpoint=Some(RecordRef::new(u.clone(),super::writing_connected::object(rows,name,&ctx.frame).ok_or_else(||anyhow::anyhow!("Select one accessible viewpoint."))?));}
                if correction.clear_reader_order {new.narrative_position=None;}else if let Some(order)=correction.reader_order{new.narrative_position=Some(order);}
                if let Some(events)=&correction.depicted_events {new.depicted_events=events.iter().map(|handle|rows.iter().find(|r|r.record_version_id.as_str()==handle && matches!(&r.payload,Payload::Event(e)if e.occurrence==OccurrenceMode::Occurred)).map(|r|RecordRef::new(u.clone(),r.identity.record_id.clone())).ok_or_else(||anyhow::anyhow!("Retrieve current occurred-event handles before linking them."))).collect::<anyhow::Result<_>>()?;}
                if let Some(disclosures)=&correction.disclosures {new.disclosed_records=self.writing_disclosures(disclosures,&old.work_version,ctx,rows)?;}
                self.check_scene_disclosures(&new.work_version,&new.disclosed_records,rows)?;
                if &new==old{return Ok(None)}
                Ok(Some(json!({"kind":"revise_scene","record":RecordRef::new(u.clone(),row.identity.record_id.clone()),"expected_version":row.record_version_id,"replacement":new,"rationale":correction.reason})))
            })();
            match built{Ok(Some(op))=>{ops.push(op);result.additions.push(format!("Historical scene correction; unchanged edition, explicitly selected fields only. Reason: {}",correction.reason));},Ok(None)=>result.unchanged.push("Scene settings unchanged".into()),Err(e)=>result.clarifications.push(e.to_string())}
        }
        Ok(())
    }
}

impl Workflow<'_> {
    fn writing_disclosures(&self,disclosures:&[universe_protocol::writing::WritingDisclosure],edition:&universe_domain::value::VersionRef,ctx:&Context,rows:&[RecordVersion])->anyhow::Result<Vec<RecordRef>> {
        if disclosures.is_empty(){return Ok(vec![])}
        let version=rows.iter().find(|r|r.identity.record_id==edition.record && r.record_version_id==edition.version).ok_or_else(||anyhow::anyhow!("Select the exact published edition."))?;
        let Payload::WorkVersion(work)=&version.payload else{anyhow::bail!("Expected edition");};
        let WorkBinding::Bound{continuity,..}=&work.binding else{anyhow::bail!("Reader disclosures require an edition bound to one canon revision.");};
        if continuity!=&ctx.frame.continuity {anyhow::bail!("Open the edition's authored continuity before selecting disclosures.");}

        let mut result=vec![];let mut seen=BTreeSet::new();
        for disclosure in disclosures {
            use universe_protocol::writing::WritingDisclosure::*;
            let id=match disclosure {
                Object{name}=>super::writing_connected::object(rows,name,&ctx.frame).ok_or_else(||anyhow::anyhow!("Select one accessible existing disclosure object."))?,
                Fact{fact_handle}=>super::writing_connected::authored_fact(rows,fact_handle)?.0.identity.record_id.clone(),
                Event{event_handle}=>rows.iter().find(|r|r.record_version_id.as_str()==event_handle && matches!(&r.payload,Payload::Event(e)if e.occurrence==OccurrenceMode::Occurred)).ok_or_else(||anyhow::anyhow!("Retrieve a current occurred-event disclosure handle."))?.identity.record_id.clone(),
            };
            if seen.insert(id.clone()){result.push(RecordRef::new(ctx.frame.universe.clone(),id));}
        }
        self.check_scene_disclosures(edition,&result,rows)?;
        Ok(result)
    }

    pub(super) fn check_scene_disclosures(&self,edition:&universe_domain::value::VersionRef,disclosures:&[RecordRef],rows:&[RecordVersion])->anyhow::Result<()> {
        if disclosures.is_empty(){return Ok(())}
        let version=rows.iter().find(|r|r.identity.record_id==edition.record && r.record_version_id==edition.version).ok_or_else(||anyhow::anyhow!("Select the exact published edition."))?;
        let Payload::WorkVersion(work)=&version.payload else{anyhow::bail!("Expected edition");};
        let WorkBinding::Bound{continuity,revision}=&work.binding else{anyhow::bail!("Reader disclosures require an edition bound to one canon revision.");};
        let canon=self.kernel.records(continuity,revision)?;
        let mut pending:Vec<_>=disclosures.iter().map(|r|r.record.clone()).collect();let mut dependencies=BTreeSet::new();
        while let Some(target)=pending.pop(){if dependencies.insert(target.clone()){let row=rows.iter().find(|r|r.identity.record_id==target).ok_or_else(||anyhow::anyhow!("Disclosure dependencies are unavailable."))?;if !canon.iter().any(|old|old.identity.record_id==target && old.record_version_id==row.record_version_id){anyhow::bail!("Disclosure and its dependencies must match the edition's pinned canon; research that revision or explicitly create a newly bound edition.");}pending.extend(universe_store::kernel::record_dependencies(row)?);if dependencies.len()+pending.len()>5_000_000{anyhow::bail!("Disclosure dependency budget exceeded");}}}
        Ok(())
    }
}
