"""Goal 32: complete Cedar qualification through actual stdio MCP calls.

Only an owned disposable installation receives synthetic author approvals.
The independent expected table is never used to construct operations.
"""
import argparse
from contextlib import closing
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import time
from canonical_families_pilot import FamilySession, authority_counts, records, restart
from audit_incremental_authoring import canonical_snapshot
from continuity_gap_pilot import build_identity
from pilot_support import NAME


def run(output, bin_dir):
    started = time.monotonic()
    output.parent.mkdir(parents=True, exist_ok=True)
    oracle=Path(__file__).resolve().parents[1]/'fixtures/cedar-workflow/expected.json'
    report = {'build': build_identity(bin_dir, {}), 'expected_sha256':hashlib.sha256(oracle.read_bytes()).hexdigest(), 'status': 'running', 'mcp': [], 'snapshots': {}, 'states': {}, 'cases': {}}
    with tempfile.TemporaryDirectory(prefix='cedar-workflow-', dir='/tmp') as directory:
        with output.with_suffix('.jsonl').open('w') as wire:
            s = FamilySession(directory, bin_dir, report, wire=wire)
            try:
                s.start()
                report['installation'] = s.u
                package = s.root/'packages'/(s.uid+'.sqlite')
                world = s.rid(60).replace('rec_', 'wld_')
                scope = {'context': s.scope['context'], 'applicability': {'kind': 'worlds', 'world_ids': [world]}}
                boolean = lambda value: {'kind': 'boolean', 'value': value}
                quantity = lambda value: {'kind': 'quantity', 'value': {'kind': 'integer', 'digits': str(value)}, 'unit': s.rid(40).replace('rec_', 'unit_')}
                def definition(n, name, parent=None):
                    return {'kind': 'introduce_definition', 'client_ref': s.rid(n), 'namespace': 'cedar_workflow', 'key': name.lower(), 'name': name, 'parent': s.rid(parent) if parent else None, 'applicability': {'kind': 'universe_wide'}, 'classification_executable': True}
                def attribute(n, owner, key, value, mode='instance', end=None):
                    shape = {'kind': value['kind']}
                    if value['kind'] == 'quantity': shape['unit'] = value['unit']
                    return {'kind': 'add_named_attribute', 'client_ref': s.rid(n), 'subject': s.rr(owner), 'namespace': 'cedar_workflow', 'key': key, 'subject_types': [s.rid(1)], 'value_shape': shape, 'multiplicity': 'single', 'value': value, 'evidence': {'attributeMode': mode, 'scope': scope, 'validity': s.interval(0,end), 'persistence': 'explicit_interval', 'polarity': 'support', 'precision': 'exact', 'basis': {'kind': 'author_decision', 'note': 'Cedar author: '+key}}}
                def publish(ops, key):
                    return s.publish(s.propose(ops,key),key+'-commit')
                def snapshot(label, revision=None):
                    frame=s.open(revision)
                    canon=canonical_snapshot(package,frame['frame']['revision'])
                    report['snapshots'][label]={'canonical':canon,'mcp_records':records(s,list(canon['records']),frame['context_id'])}
                    return canon
                def state(label, day, revision=None):
                    frame=s.open(revision,day)
                    args={'universe':NAME,'context_id':frame['context_id'],'world':'Grove','world_id':world,'entity_ids':[s.rid(4)],'predicate_filters':[]}
                    before=authority_counts(s)
                    response=s.call('universe_get_state',args)
                    assert before==authority_counts(s)
                    report['states'][label]=response
                    report.setdefault('read_counts',{})[label]={'before':before,'after':authority_counts(s)}
                    s.open()
                    return frame['context_id']
                def assertion(n):
                    rows=canonical_snapshot(package,s.open()['frame']['revision'])['records']
                    return next(r for r in rows.values() if r['payload']['record_kind']=='assertion' and r['payload']['proposition']['record']==s.rid(n))
                def revise(row, body):
                    body=deepcopy(body);body.pop('record_kind',None)
                    return {'kind':'supersede_assertion','record':s.rr(row['identity']['record_id']),'expected_version':row['record_version_id'],'replacement':body,'rationale':'Explicit earlier measurement correction'}
                def proposition(n, value):
                    return {'kind':'define_proposition','client_ref':s.rid(n),'record':{'subject':s.rr(4),'predicate':s.rr(report['properties']['height']),'value':quantity(value),'quantification':'particular','context':scope['context']}}
                def event(n, action=50, post=52):
                    effects=[] if action==55 else [{'slot':'height','order':0,'proposition':s.rr(post),'polarity':'support','scope':scope,'validity':s.interval(10)}]
                    return {'kind':'record_event','client_ref':s.rid(n),'record':{'occurrence':'occurred','worlds':[world],'time':s.instant(10),'participants':[{'record':s.rr(4),'role':'tree'}],'action':s.rr(action),'effects':effects,'preconditions':[],'labels':{}}}
                def rejected(key, ops):
                    before=authority_counts(s);head=s.open()['frame']['revision']
                    p=s.propose(ops,key)
                    validation_args={'mode':'proposal','universe':NAME,'context_id':s.ctx,'proposal_reference':s.reference(p),'check_scope':'universe'}
                    raw=s.client.request('tools/call',{'name':'universe_validate','arguments':validation_args})
                    result=raw['structuredContent']
                    s.report['mcp'].append({'tool':'universe_validate','arguments':validation_args,'expected_error':bool(raw.get('isError')),'result':result})
                    v=result.get('result',{}).get('execution')
                    if v:
                        assert any(f['outcome']!='supported' for f in v['findings']) or v['coverage']=='partial',v
                        assert s.approval(p,v,check=False).returncode!=0
                    else: assert result.get('code')=='INVALID_ARGUMENT',result
                    denied=s.call('universe_commit',s.commit_args(p,v or report['publications'][-1]['validation'],key+'-denied'),error=True)
                    assert authority_counts(s)==before and s.open()['frame']['revision']==head
                    report['cases'][key]={'proposal':p,'rejection':result,'denied':denied,'before':before,'after':authority_counts(s)}
                    return p
                publish([definition(1,'Tree')],'minimal-tree')
                snapshot('definition')
                publish([{'kind':'create_world','client_ref':s.rid(60),'record':{'selector':'Grove','labels':{},'metadata':{}}},
                         {'kind':'introduce_instance','client_ref':s.rid(4),'name':{'text':'North tree','validity':s.interval(0)},'classification':s.rid(1),'world_associations':[{'world':world,'role':'setting','validity':s.interval(0),'qualifiers':{}}]},
                         attribute(10,4,'exists',boolean(True)),attribute(11,4,'physical_location',{'kind':'text','text':'North bank of the grove'})],'existence-location')
                snapshot('minimal');state('minimal',5)
                publish([attribute(12,1,'grows',boolean(True),'shared'),attribute(13,4,'climbing_hazard',{'kind':'text','text':'Broken upper branch'})],'capability-hazard')
                row=s.get([s.rid(4)])[0]
                publish([definition(2,'Cedar',1),{'kind':'refine_classification','record':s.rr(4),'expected_version':row['record_version_id'],'entity_type':s.rid(2)}],'refine-cedar')
                snapshot('cedar');ctx=state('cedar',5);state('before_existence',-1)
                report['context']=s.call('universe_get_context',{'universe':NAME,'context_id':ctx,'focus_ids':[s.rid(4)],'purpose':'Cedar identity, capabilities, hazard and missing height','byte_budget':65536})
                unit=s.rid(40).replace('rec_','unit_')
                publish([{'kind':'define_unit','client_ref':s.rid(40),'record':{'namespace':'cedar_workflow','key':'foot','dimension':'length','symbol':'ft','labels':{},'base':None,'validity':{'kind':'unspecified'}}},attribute(14,4,'height',quantity(30),end=10),
                         {'kind':'define_property','client_ref':s.rid(41),'record':{'namespace':'cedar_workflow','key':'adequate_water','labels':{},'subjectTypes':[s.rid(1)],'value':{'kind':'boolean'},'multiplicity':'single','persistence':'explicit_interval','exclusive':False,'symmetric':False,'transitive':False}},
                         {'kind':'define_property','client_ref':s.rid(42),'record':{'namespace':'cedar_workflow','key':'growing_season','labels':{},'subjectTypes':[s.rid(1)],'value':{'kind':'boolean'},'multiplicity':'single','persistence':'explicit_interval','exclusive':False,'symmetric':False,'transitive':False}}],'height-and-conditions')
                canon=snapshot('height')['records']
                report['properties']={r['payload']['key']:r['identity']['record_id'] for r in canon.values() if r['payload']['record_kind']=='property'}
                action={'namespace':'cedar_workflow','key':'measured_height_change','labels':{},'requirements':[],'scope':scope,'validity':s.interval(0),'consequenceContract':{'kind':'action_consequences','slots':[{'slot':'height','order':0,'presence':'required','target':{'role':'tree','predicate':s.rr(report['properties']['height'])},'condition':{'kind':'always'},'change':{'kind':'delta','delta':'1','minimum':'0','maximum':'1000','unit':unit},'lifetime':{'kind':'until_changed'}}]}}
                growth={**action,'key':'conditional_growth','requirements':[{'role':'tree','predicate':s.rr(report['properties'][key]),'value':boolean(True)} for key in ['grows','adequate_water','growing_season']],'consequenceContract':{'kind':'action_consequences','slots':[]}}
                publish([{'kind':'define_action','client_ref':s.rid(50),'record':action},{'kind':'define_action','client_ref':s.rid(55),'record':growth}],'authored-behavior')
                rejected('missing_water',[event(70,55)])
                rejected('conflicting_shared_growth',[attribute(71,2,'grows',boolean(False),'shared')])
                rejected('conflicting_height',[attribute(72,4,'height',quantity(99),end=10)])
                publish([proposition(52,31),event(51)],'authored-height-change')
                original=snapshot('changed')['revision']
                retained=state('before_change',5);state('after_change',15);state('far_future',1000)
                publish([attribute(15,4,'adequate_water',boolean(True))],'author-water-answer')
                rejected('missing_season',[event(73,55)])
                # A coherent correction must also correct the downstream +1 post-value.
                old=assertion(14);body=deepcopy(old['payload']);body['proposition']=s.rr(80);body['basis']={'kind':'author_decision','note':'Earlier height was 29 feet, not 30'}
                partial=[proposition(80,29),revise(old,body)]
                p=rejected('partial_height_correction',partial)
                report['correction_impact']=s.impact(p)
                report['affected_before']=s.get([s.rid(51),s.rid(52),old['identity']['record_id']])
                downstream=s.get([s.rid(51)])[0];event_body=deepcopy(downstream['payload']);event_body.pop('record_kind');event_body['effects'][0]['proposition']=s.rr(81)
                body['proposition']=s.rr(83)
                correction=[proposition(83,29),revise(old,body),proposition(81,30),{'kind':'revise_event','record':s.rr(51),'expected_version':downstream['record_version_id'],'replacement':event_body}]
                p=s.propose(correction,'complete-height-correction');v=s.validate(p)
                assert v['coverage']=='complete' and all(f['outcome']=='supported' for f in v['findings']),v
                review=s.admin('review',NAME,p['proposal_id'],p['version'],p['digest']);approval=json.loads(s.approval(p,v).stdout)
                args=s.commit_args(p,v,'complete-height-correction-commit')
                restart(s,report)
                receipt=s.call('universe_commit',args)['result'];assert s.call('universe_commit',args)['result']==receipt
                report['publications'].append({'key':'complete-height-correction-commit','review':review,'author_selection':{'approval':approval},'validation':v,'receipt':receipt,'commit_arguments':args})
                snapshot('corrected');state('corrected_before',5);state('corrected_after',15)
                # The retained context remains pinned after a head update and restart.
                report['retained_state']=s.call('universe_get_state',{'universe':NAME,'context_id':retained,'world':'Grove','world_id':world,'entity_ids':[s.rid(4)],'predicate_filters':[]})
                snapshot('historical',original);state('historical_before',5,original);state('historical_after',15,original)
                s.open();report['affected_after']=s.get([s.rid(51),s.rid(81),old['identity']['record_id']])
                restart(s,report);snapshot('restart');state('restart_before',5);state('restart_after',15);state('restart_historical',15,original)
                assert s.call('universe_commit',args)['result']==receipt
                # Unknown water remains authored evidence, never permission to grow.
                water=assertion(15);wb=deepcopy(water['payload']);wb['precision']='unresolved';wb['validity']={'kind':'unknown'}
                publish([revise(water,wb)],'unresolved-water')
                snapshot('unresolved');state('unresolved',15);rejected('unresolved_water',[event(74,55)])
                report['status']='passed';report['seconds']=time.monotonic()-started
            finally:
                s.close()
                report['cleanup']={'owned_root':str(s.root),'engine_stopped':not (s.root/'engine.sock').exists()}
                output.write_text(json.dumps(report,indent=2)+'\n')
                if report['status']=='passed':
                    with closing(sqlite3.connect('file:'+str(package)+'?mode=ro',uri=True)) as source:
                        with closing(sqlite3.connect(output.with_suffix('.sqlite'))) as target:
                            source.backup(target)
    report['cleanup']['installation_removed']=not Path(directory).exists()
    report['seconds']=time.monotonic()-started
    output.write_text(json.dumps(report,indent=2)+'\n')
    print(f'Actual Cedar MCP workflow {report["status"]} in {report["seconds"]:.1f}s')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--bin-dir',type=Path,default=Path('target/debug'));a=p.parse_args();run(a.output,a.bin_dir.resolve())
