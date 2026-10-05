"""Goal 31: actual reviewed MCP initialization and resource lifecycle.

The owned installation is disposable. Captured canonical readback is independently
reconstructed from typed rows, separate from received MCP results.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import tempfile
import time
from canonical_families_pilot import FamilySession, authority_counts, private, records
from audit_incremental_authoring import canonical_snapshot
from pilot_support import NAME
from continuity_gap_pilot import build_identity


def run(output, bin_dir):
    started = time.monotonic()
    output.parent.mkdir(parents=True, exist_ok=True)
    report = {'build': build_identity(bin_dir, {}), 'status': 'running', 'mcp': [], 'snapshots': {}, 'states': {}, 'controls': []}
    with tempfile.TemporaryDirectory(prefix='instance-initialization-', dir='/tmp') as directory:
        with output.with_suffix('.jsonl').open('w') as wire:
            s = FamilySession(directory, bin_dir, report, wire=wire)
            try:
                s.start()
                report['installation'] = s.u
                package = s.root/'packages'/(s.uid+'.sqlite')
                world = s.rid(60).replace('rec_', 'wld_')
                scope = {'context': s.scope['context'], 'applicability': {'kind': 'worlds', 'world_ids': [world]}}
                integer = lambda n: {'kind': 'integer', 'digits': str(n)}
                def definition(n, name, parent=None):
                    return {'kind': 'introduce_definition', 'client_ref': s.rid(n), 'namespace': 'initialization', 'key': name.lower(), 'name': name, 'parent': s.rid(parent) if parent else None, 'applicability': {'kind': 'universe_wide'}, 'classification_executable': True}
                def instance(n, name, classification=None):
                    return {'kind': 'introduce_instance', 'client_ref': s.rid(n), 'name': {'text': name, 'validity': {'kind': 'unknown'}}, 'classification': s.rid(classification) if classification else None, 'world_associations': [{'world': world, 'role': 'setting', 'validity': {'kind': 'unknown'}, 'qualifiers': {}}]}
                def prop(n, subject, predicate, value):
                    return {'kind': 'define_proposition', 'client_ref': s.rid(n), 'record': {'subject': s.rr(subject), 'predicate': s.rr(predicate), 'value': value, 'quantification': 'particular', 'context': scope['context']}}
                def claim(n, subject, predicate, value, mode, validity, claim_scope=None):
                    return {'kind': 'assert_proposition', 'client_ref': s.rid(n), 'proposition': prop(n,subject,predicate,value)['record'], 'assertion': {'attributeMode': mode, 'proposition': s.rr(n), 'polarity': 'support', 'scope': claim_scope or scope, 'validity': validity, 'persistence': 'explicit_interval', 'precision': 'exact', 'basis': {'kind': 'author_decision', 'note': 'Explicit fixture evidence'}}}
                def action(n, key, slots):
                    return {'kind': 'define_action', 'client_ref': s.rid(n), 'record': {'namespace': 'initialization', 'key': key, 'labels': {}, 'requirements': [], 'consequenceContract': {'kind': 'action_consequences', 'slots': slots}, 'scope': scope, 'validity': {'kind': 'unspecified'}}}
                def event(n, subject, t, action_id, effect=None):
                    effects = [] if effect is None else [{'slot': effect[0], 'order': 0, 'proposition': s.rr(effect[1]), 'polarity': 'support', 'scope': scope, 'validity': s.interval(t)}]
                    return {'kind': 'record_event', 'client_ref': s.rid(n), 'record': {'occurrence': 'occurred', 'worlds': [world], 'time': s.instant(t), 'participants': [{'record': s.rr(subject), 'role': 'gun'}], 'action': s.rr(action_id), 'effects': effects, 'preconditions': [], 'labels': {}}}
                def slot(name, predicate, change):
                    return {'slot': name, 'order': 0, 'presence': 'required', 'target': {'role': 'gun', 'predicate': s.rr(predicate)}, 'condition': {'kind': 'always'}, 'change': change, 'lifetime': {'kind': 'until_changed'}}
                def counts():
                    result = authority_counts(s)
                    with sqlite3.connect(package) as db:
                        result['initialization_receipt'] = db.execute('SELECT count(*) FROM initialization_receipt').fetchone()[0]
                        result['record_identities'] = db.execute('SELECT count(*) FROM record_identities').fetchone()[0]
                    return result
                def receipts():
                    with sqlite3.connect(package) as db:
                        db.row_factory = sqlite3.Row
                        return [dict(row) for row in db.execute('SELECT * FROM initialization_receipt ORDER BY instance_id,predicate_id')]
                def snapshot(label, revision=None):
                    frame = s.open(revision)
                    canonical = canonical_snapshot(package, frame['frame']['revision'])
                    report['snapshots'][label] = {'canonical': canonical, 'mcp_records': records(s, list(canonical['records']), frame['context_id']), 'all_receipts': receipts()}
                    return canonical
                def assertion_for(proposition):
                    rows = canonical_snapshot(package,s.open()['frame']['revision'])['records']
                    return next(r for r in rows.values() if r['payload']['record_kind']=='assertion' and r['payload']['proposition']['record']==s.rid(proposition))
                def initial(n, who, start, source, t, end):
                    return {'kind': 'initialize_instance', 'client_ref': s.rid(n), 'instance': s.rr(who), 'start': s.rr(start), 'definition': {'universe': s.uid, 'record': source['identity']['record_id'], 'version': source['record_version_id']}, 'scope': scope, 'validity': s.interval(t,end)}
                def publish(ops, key):
                    return s.publish(s.propose(ops,key),key+'-commit')
                def state(label,t,revision=None,ids=(4,5)):
                    frame = s.open(revision,t)
                    response = s.call('universe_get_state',{'universe':NAME,'world':'Range','world_id':world,'context_id':frame['context_id'],'entity_ids':[s.rid(n) for n in ids],'predicate_filters':[]})
                    report['states'][label] = response
                    s.open()
                    return response['result']
                def rejection(key, ops):
                    before = counts()
                    with sqlite3.connect(package) as db:
                        workflow = db.execute('SELECT count(*) FROM workflow_entries').fetchone()[0]
                    response = s.call('universe_propose',{'action':'create','universe':NAME,'context_id':s.ctx,'operations':ops,'submission':'submitted','rationale':key,'idempotency_key':key},error=True)
                    assert counts()==before
                    with sqlite3.connect(package) as db:
                        assert db.execute('SELECT count(*) FROM workflow_entries').fetchone()[0]==workflow
                    report['controls'].append({'key':key,'before':before,'after':counts(),'response':response})
                def revise_assertion(row,replacement):
                    replacement = deepcopy(replacement);replacement.pop('record_kind',None)
                    return {'kind':'supersede_assertion','record':s.rr(row['identity']['record_id']),'expected_version':row['record_version_id'],'replacement':replacement,'rationale':'Explicit reviewed correction'}
                def edit_source(n,value,key):
                    nonlocal source
                    old = s.get([source['identity']['record_id']])[0]
                    replacement = deepcopy(old['payload']);replacement['proposition']=s.rr(n)
                    publish([prop(n,1,10,integer(value)),revise_assertion(old,replacement)],key)
                    source=s.get([source['identity']['record_id']])[0]
                # Approved initial values are definition facts, never pre-stock.
                ops = [{'kind':'create_world','client_ref':s.rid(60),'record':{'selector':'Range','labels':{},'metadata':{}}},definition(1,'Gun'),definition(2,'Pistol',1)]
                for n,key,shape in [(10,'rounds',{'kind':'integer'}),(14,'holder',{'kind':'entity_ref','subject_types':[]})]:
                    ops.append({'kind':'define_property','client_ref':s.rid(n),'record':{'namespace':'initialization','key':key,'labels':{},'subjectTypes':[s.rid(1)],'value':shape,'multiplicity':'single','persistence':'explicit_interval','exclusive':False,'symmetric':False,'transitive':False}})
                ops += [claim(11,1,10,integer(7),'initial_value',s.interval(0,100),s.scope),instance(6,'Holder A'),instance(7,'Holder B'),action(30,'start',[]),action(31,'mention',[]),action(32,'shoot',[slot('shot',10,{'kind':'delta','delta':'-1','minimum':'0','maximum':'12','unit':None})]),action(33,'handoff',[slot('holder',14,{'kind':'set','polarity':'support','value':{'kind':'entity_ref','ref':s.rr(7)}})])]
                publish(ops,'definitions');snapshot('definitions')
                source=assertion_for(11)
                a_ops=[instance(4,'Pistol A',2),event(101,4,10,30),initial(100,4,101,source,10,11),claim(80,4,14,{'kind':'entity_ref','ref':s.rr(6)},'instance',s.interval(10,28))]
                p=s.propose(a_ops,'start-a');assert s.propose(a_ops,'start-a')==p
                original_args=next(r['arguments'] for r in report['mcp'] if r['tool']=='universe_propose' and r['arguments'].get('idempotency_key')=='start-a')
                s.restart();assert s.call('universe_propose',original_args)['result']==p
                s.publish(p,'start-a-commit');snapshot('a-start');state('a-start',10,ids=(4,))
                initial_a=assertion_for(100)
                publish([prop(102,4,10,integer(6)),event(103,4,11,32,('shot',102))],'shot-a-one');snapshot('shot-a-one');state('shot-a-one',12,ids=(4,))
                edit_source(12,3,'source-three');snapshot('source-three');state('source-edit-before-b',12,ids=(4,))
                source_three=deepcopy(source)
                publish([instance(5,'Pistol B',2),event(111,5,20,30),initial(110,5,111,source,20,100)],'start-b');snapshot('b-start');state('b-start',20)
                initial_b=assertion_for(110)
                edit_source(13,9,'source-nine');snapshot('source-nine');state('definition-edit',24)
                publish([prop(120,4,10,integer(5)),event(121,4,25,32,('shot',120))],'shot-a-two');snapshot('consumed');state('consumed',26)
                original_receipts=receipts()
                row=s.get([s.rid(4)])[0]
                publish([{'kind':'add_name','record':s.rr(4),'expected_version':row['record_version_id'],'name':{'text':'North pistol','validity':{'kind':'unknown'}}}],'rename');state('rename',30);assert receipts()==original_receipts
                row=s.get([s.rid(4)])[0]
                publish([definition(3,'ServicePistol',2),{'kind':'refine_classification','record':s.rr(4),'expected_version':row['record_version_id'],'entity_type':s.rid(3)}],'refinement');state('refinement',30);assert receipts()==original_receipts
                publish([prop(81,4,14,{'kind':'entity_ref','ref':s.rr(7)}),event(82,4,28,33,('holder',81))],'holder-transfer');state('holder-transfer',30);assert receipts()==original_receipts
                publish([prop(43,4,10,integer(7)),event(44,4,29,31)],'another-mention');state('another-mention',30);assert receipts()==original_receipts
                publish([{'kind':'create_work','client_ref':s.rid(40),'record':{'kind':'story','title':'Initialization proof','labels':{},'sourceRefs':[],'versions':[],'worldAssociations':[]}}, {'kind':'record_narrative_reference','client_ref':s.rid(41),'record':'work_version','payload':{'record_kind':'work_version','work':s.rr(40),'versionLabel':'Another scene edition','binding':{'kind':'bound','continuity':s.u['continuity_id'],'revision':s.open()['frame']['revision']}}}],'edition')
                edition=s.get([s.rid(41)])[0]
                scene={'record_kind':'scene_ref','workVersion':{'universe':s.uid,'record':s.rid(41),'version':edition['record_version_id']},'sceneId':'Another scene','disclosedRecords':[s.rr(4),s.rr(5),s.rr(43)],'viewpoint':s.rr(6),'narrativePosition':0,'depictedEvents':[],'narrationFrame':scope['context'],'worldAssociations':[]}
                publish([{'kind':'record_narrative_reference','client_ref':s.rid(42),'record':'scene_ref','payload':scene}],'another-scene');state('another-scene',30);snapshot('mutations');assert receipts()==original_receipts
                # Neither repeated mention/start nor stale source versions can refill A.
                rejection('later-start-no-refill',[event(150,4,35,30),initial(151,4,150,source,35,40)])
                rejection('same-start-no-refill',[initial(152,4,101,source,10,11)])
                rejection('stale-source',[event(153,5,35,30),initial(154,5,153,source_three,35,40)])
                s.restart();state('restart',30);assert receipts()==original_receipts
                # Correct initial history and both dependent declared post-values together.
                corrected=deepcopy(initial_a['payload']);corrected['proposition']=s.rr(160);corrected['basis']={'kind':'author_decision','note':'Correct original load to eight and both downstream shot consequences'}
                correction=[prop(160,4,10,integer(8)),prop(161,4,10,integer(7)),prop(162,4,10,integer(6)),revise_assertion(s.get([initial_a['identity']['record_id']])[0],corrected)]
                for event_id,post in [(103,161),(121,162)]:
                    row=s.get([s.rid(event_id)])[0];body=deepcopy(row['payload']);body.pop('record_kind');body['effects'][0]['proposition']=s.rr(post)
                    correction.append({'kind':'revise_event','record':s.rr(event_id),'expected_version':row['record_version_id'],'replacement':body})
                old_revision=report['snapshots']['mutations']['canonical']['revision']
                publish(correction,'historical-correction');snapshot('corrected');state('corrected-start',10);state('corrected',30);snapshot('historical-after-correction',old_revision);state('historical',30,old_revision);assert receipts()==original_receipts
                # A third identity has no stock; inherited conflicting evidence stays visible.
                publish([instance(8,'Conflict pistol',2),claim(16,2,10,integer(4),'initial_value',s.interval(0,100),s.scope)],'conflicting-candidates');snapshot('conflict');state('conflict',40,ids=(8,))
                conflict=assertion_for(16)
                c_ops=[event(130,8,40,30),initial(132,8,130,source,40,50)]
                rejection('conflicting-start-no-partial',c_ops)
                replacement=deepcopy(conflict['payload']);replacement['precision']='unresolved'
                publish([revise_assertion(conflict,replacement)],'unresolved-candidate');snapshot('unresolved');state('unresolved',40,ids=(8,));rejection('unresolved-start-no-partial',c_ops)
                row=s.get([conflict['identity']['record_id']])[0]
                publish([{'kind':'retract_assertion','record':s.rr(row['identity']['record_id']),'expected_version':row['record_version_id'],'rationale':'Author withdraws the conflicting unresolved candidate'}],'resolve-candidate')
                snapshot('resolved-candidate')
                p=s.propose(c_ops,'start-c');v=s.validate(p);assert v['coverage']=='complete' and all(f['outcome']=='supported' for f in v['findings'])
                review=s.admin('review',NAME,p['proposal_id'],p['version'],p['digest']);approval=json.loads(s.approval(p,v).stdout);args=s.commit_args(p,v,'start-c-commit')
                before=counts();canon_before=canonical_snapshot(package,s.open()['frame']['revision']);receipt_before=receipts()
                with sqlite3.connect(package) as db:db.execute("CREATE TRIGGER initialization_failure BEFORE INSERT ON commit_changes BEGIN SELECT RAISE(ABORT,'Goal 31 fault'); END")
                failed=s.call('universe_commit',args,error=True);assert counts()==before;assert receipts()==receipt_before;assert canonical_snapshot(package,s.open()['frame']['revision'])==canon_before
                report['publication_failure']={'response':failed,'before':before,'after':counts(),'receipts_before':receipt_before,'receipts_after':receipts(),'canonical_before':canon_before,'canonical_after':canonical_snapshot(package,s.open()['frame']['revision'])}
                with sqlite3.connect(package) as db:db.execute('DROP TRIGGER initialization_failure')
                s.restart();receipt=s.call('universe_commit',args)['result'];assert s.call('universe_commit',args)['result']==receipt
                report['publications'].append({'key':'start-c-commit','review':review,'author_selection':{'approval':approval},'validation':v,'receipt':receipt,'commit_arguments':args})
                snapshot('c-start');state('c-start',45,ids=(4,5,8));state('missing-current-stock',55,ids=(8,));rejection('expired-stock-no-bootstrap',[event(170,8,55,30),initial(171,8,170,source,55,60)])
                s.restart();snapshot('final');state('final',45,ids=(4,5,8));state('historical-c-before-init',40,report['snapshots']['conflict']['canonical']['revision'],ids=(8,));assert len(receipts())==3
                report['bindings']={'initial_a':initial_a,'initial_b':initial_b,'original_receipts':original_receipts}
                report['status']='passed';report['seconds']=time.monotonic()-started
            finally:
                s.close()
                output.write_text(json.dumps(report,indent=2)+'\n')
    from audit_instance_initialization import audit
    print(json.dumps(audit(output),sort_keys=True))
    print(f'MCP initialization proof {report["status"]} in {report["seconds"]:.1f}s')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--bin-dir',type=Path,default=Path('target/debug'));a=p.parse_args();run(a.output,a.bin_dir.resolve())
