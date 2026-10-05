"""Goal 33: sustained Pistol MCP admission qualification on an owned installation.
The driver never reads the independent accounting oracle.
"""
import argparse
from contextlib import closing
from copy import deepcopy
import json
import hashlib
from pathlib import Path
import sqlite3
import tempfile
import time
from canonical_families_pilot import FamilySession, authority_counts, records, restart
from audit_incremental_authoring import canonical_snapshot
from continuity_gap_pilot import build_identity
from pilot_support import NAME


def run(output, bin_dir):
    started=time.monotonic();output.parent.mkdir(parents=True,exist_ok=True)
    oracle=Path(__file__).resolve().parents[1]/'fixtures/pistol-workflow/expected.json'
    r={'expected_sha256':hashlib.sha256(oracle.read_bytes()).hexdigest(),'status':'running','build':build_identity(bin_dir,{}),'mcp':[],'snapshots':{},'states':{},'cases':{}}
    with tempfile.TemporaryDirectory(prefix='pistol-workflow-',dir='/tmp') as directory:
        with output.with_suffix('.jsonl').open('w') as wire:
            s=FamilySession(directory,bin_dir,r,wire=wire)
            try:
                s.start();r['installation']=s.u;package=s.root/'packages'/(s.uid+'.sqlite')
                world=s.rid(60).replace('rec_','wld_');other=s.rid(61).replace('rec_','wld_')
                scope={'context':s.scope['context'],'applicability':{'kind':'worlds','world_ids':[world]}}
                integer=lambda n:{'kind':'integer','digits':str(n)}
                ref=lambda n:{'kind':'entity_ref','ref':s.rr(n)}
                def definition(n,name,parent=None):
                    return {'kind':'introduce_definition','client_ref':s.rid(n),'namespace':'pistol_workflow','key':name.lower(),'name':name,'parent':s.rid(parent) if parent else None,'applicability':{'kind':'universe_wide'},'classification_executable':True}
                def instance(n,name,kind=None,w=world):
                    return {'kind':'introduce_instance','client_ref':s.rid(n),'name':{'text':name,'validity':s.interval(0)},'classification':s.rid(kind) if kind else None,'world_associations':[{'world':w,'role':'setting','validity':s.interval(0),'qualifiers':{}}]}
                def prop(n,owner,predicate,value):
                    return {'kind':'define_proposition','client_ref':s.rid(n),'record':{'subject':s.rr(owner),'predicate':s.rr(predicate),'value':value,'quantification':'particular','context':scope['context']}}
                def claim(n,owner,predicate,value,mode='instance',start=0,end=None,sc=None,note='Explicit author evidence'):
                    return {'kind':'assert_proposition','client_ref':s.rid(n),'proposition':prop(n,owner,predicate,value)['record'],'assertion':{'attributeMode':mode,'proposition':s.rr(n),'polarity':'support','scope':sc or scope,'validity':s.interval(start,end),'persistence':'explicit_interval','precision':'exact','basis':{'kind':'author_decision','note':note}}}
                def slot(name,role,predicate,change,order=0):
                    return {'slot':name,'order':order,'presence':'required','target':{'role':role,'predicate':s.rr(predicate)},'condition':{'kind':'always'},'change':change,'lifetime':{'kind':'until_changed'}}
                delta=lambda n:{'kind':'delta','delta':str(n),'minimum':'0','maximum':'3','unit':None}
                def action(n,key,slots,requirements=[]):
                    return {'kind':'define_action','client_ref':s.rid(n),'record':{'namespace':'pistol_workflow','key':key,'labels':{},'requirements':requirements,'scope':s.scope,'validity':s.interval(0),'consequenceContract':{'kind':'action_consequences','slots':slots}}}
                def event(n,owner,t,a,effects=[],shooter=None,w=world):
                    ps=[{'record':s.rr(owner),'role':'gun'}]
                    if a==33:ps.append({'record':s.rr(9),'role':'reserve'})
                    pre=[]
                    if shooter:
                        ps.append({'record':s.rr(shooter),'role':'shooter'})
                        pre=[{'kind':'claim','subject':{'kind':'record','ref':s.rr(owner)},'predicate':'pistol_workflow:holder','roles':[],'value':{'kind':'value','value':ref(shooter)},'polarity':'support','context':None}]
                    sc={**scope,'applicability':{'kind':'worlds','world_ids':[w]}}
                    return {'kind':'record_event','client_ref':s.rid(n),'record':{'occurrence':'occurred','worlds':[w],'time':s.instant(t),'participants':ps,'action':s.rr(a),'effects':[{'slot':key,'order':i,'proposition':s.rr(p),'polarity':'support','scope':sc,'validity':s.interval(t)} for key,i,p in effects],'preconditions':pre,'labels':{}}}
                def publish(ops,key):return s.publish(s.propose(ops,key),key+'-commit')
                def snapshot(key,revision=None):
                    frame=s.open(revision);canon=canonical_snapshot(package,frame['frame']['revision']);r['snapshots'][key]={'canonical':canon,'mcp_records':records(s,list(canon['records']),frame['context_id'])};s.open();return canon
                def state(key,t,revision=None,w=world):
                    frame=s.open(revision,t);before=authority_counts(s)
                    args={'universe':NAME,'context_id':frame['context_id'],'world':'Range' if w==world else 'Other','world_id':w,'entity_ids':[s.rid(n) for n in (4,5,8,9,18,19)],'predicate_filters':[]}
                    r['states'][key]=s.call('universe_get_state',args);assert before==authority_counts(s);s.open()
                def assertion(n):
                    return next(row for row in canonical_snapshot(package,s.open()['frame']['revision'])['records'].values() if row['payload']['record_kind']=='assertion' and row['payload']['proposition']['record']==s.rid(n))
                def initial(n,owner,e,source,t,end,w=world):
                    return {'kind':'initialize_instance','client_ref':s.rid(n),'instance':s.rr(owner),'start':s.rr(e),'definition':{'universe':s.uid,'record':source['identity']['record_id'],'version':source['record_version_id']},'scope':{**scope,'applicability':{'kind':'worlds','world_ids':[w]}},'validity':s.interval(t,end)}
                def attempt(ops,key):
                    before=authority_counts(s);head=s.open()['frame']['revision']
                    args={'action':'create','universe':NAME,'context_id':s.ctx,'operations':ops,'submission':'submitted','rationale':key,'idempotency_key':key}
                    raw=s.client.request('tools/call',{'name':'universe_propose','arguments':args});env=raw['structuredContent'];s.report['mcp'].append({'tool':'universe_propose','arguments':args,'expected_error':bool(raw.get('isError')),'result':env})
                    c={'propose':env,'before':before,'head_before':head}
                    if not raw.get('isError'):
                        p=env['result'];va={'mode':'proposal','universe':NAME,'context_id':s.ctx,'proposal_reference':s.reference(p),'check_scope':'universe'}
                        raw=s.client.request('tools/call',{'name':'universe_validate','arguments':va});v=raw['structuredContent'];s.report['mcp'].append({'tool':'universe_validate','arguments':va,'expected_error':bool(raw.get('isError')),'result':v});c['validation']=v
                        execution=v.get('result',{}).get('execution')
                        if execution and execution['coverage']=='complete' and all(f['outcome']=='supported' for f in execution['findings']):
                            c['publication']=publish_existing(p,key);c['admitted']=True
                        else:
                            if execution:c['approval_returncode']=s.approval(p,execution,check=False).returncode;assert c['approval_returncode']!=0
                            c['denied']=s.call('universe_commit',s.commit_args(p,execution or r['publications'][-1]['validation'],key+'-denied'),error=True)
                    c['after']=authority_counts(s);c['head_after']=s.open()['frame']['revision'];r['cases'][key]=c
                    if not c.get('admitted'):assert before==c['after'] and head==c['head_after']
                    return c
                def publish_existing(p,key):return s.publish(p,key+'-commit')
                ops=[{'kind':'create_world','client_ref':s.rid(n),'record':{'selector':name,'labels':{},'metadata':{}}} for n,name in [(60,'Range'),(61,'Other')]]
                ops += [definition(1,'Gun'),definition(2,'Pistol',1),definition(3,'Service pistol',2),definition(17,'Revolver',1)]
                for n,key,shape in [(10,'rounds',{'kind':'integer'}),(14,'holder',{'kind':'entity_ref','subject_types':[]}),(15,'can_fire',{'kind':'boolean'})]:
                    ops.append({'kind':'define_property','client_ref':s.rid(n),'record':{'namespace':'pistol_workflow','key':key,'labels':{},'subjectTypes':[s.rid(1)] if n==15 else [],'value':shape,'multiplicity':'single','persistence':'explicit_interval','exclusive':False,'symmetric':False,'transitive':False}})
                ops += [claim(11,1,10,integer(3),'initial_value',sc=s.scope),claim(12,2,15,{'kind':'boolean','value':True},'shared'),claim(16,17,15,{'kind':'boolean','value':False},'shared'),instance(6,'Holder A'),instance(7,'Holder B'),instance(9,'Reserve'),instance(4,'Pistol A',3),instance(5,'Pistol B',2),instance(8,'Pistol C',3),instance(18,'Revolver',17),instance(19,'Other-world pistol',3,w=other),claim(20,9,10,integer(2),end=20),action(30,'start',[]),action(31,'shoot',[slot('shot','gun',10,delta(-1))],[{'role':'gun','predicate':s.rr(15),'value':{'kind':'boolean','value':True}}]),action(32,'handoff',[slot('holder','gun',14,{'kind':'set','polarity':'support','value':ref(7)})]),action(33,'reload_two',[slot('load','gun',10,delta(2)),slot('reserve','reserve',10,delta(-2),1)])]
                publish(ops,'definitions');snapshot('definitions');source=assertion(11)
                ops=[]
                for n,owner,end,w in [(100,4,11,world),(110,5,11,world),(120,8,50,world),(130,18,50,world),(140,19,50,other)]:
                    ops += [event(n+1,owner,9,30,w=w),initial(n,owner,n+1,source,9,end,w)]
                ops += [claim(21,4,14,ref(6),start=9,end=12),claim(22,5,14,ref(6),start=9)]
                publish(ops,'reviewed-starts');snapshot('started');state('started',9)
                first=None
                for i in range(1,4):
                    t=9+2*i
                    for owner,base in [(4,200),(5,220)]:
                        publish([prop(base+2*i,owner,10,integer(3-i)),event(base+2*i+1,owner,t,31,[('shot',0,base+2*i)],6 if owner==5 or i==1 else 7)],f'shot-{owner}-{i}')
                    if i==1:
                        first=s.get([s.rid(203)])[0]
                        publish([prop(240,4,14,ref(7)),event(241,4,12,32,[('holder',0,240)])],'holder-transfer')
                        attempt([prop(800,4,10,integer(1)),event(801,4,13,31,[('shot',0,800)],6)],'former-holder')
                    snapshot('shots-'+str(i));state('shots-'+str(i),t)
                for owner,base in [(4,810),(5,820)]:attempt([prop(base,owner,10,integer(-1)),event(base+1,owner,16,31,[('shot',0,base)],7 if owner==4 else 6)],'exhausted-'+str(owner))
                attempt([prop(830,18,10,integer(2)),event(831,18,14,31,[('shot',0,830)])],'subtype-rejected')
                attempt([prop(840,19,10,integer(2)),event(841,19,14,31,[('shot',0,840)],w=other)],'world-rejected')
                state('other-world',14,w=other)
                publish([prop(250,4,10,integer(2)),prop(251,9,10,integer(0)),event(252,4,20,33,[('load',0,250),('reserve',1,251)])],'constrained-reload');snapshot('reload');state('reload',20)
                attempt([prop(850,4,10,integer(1)),prop(851,9,10,integer(0)),event(852,4,19,33,[('load',0,850),('reserve',1,851)])],'forged-reload')
                attempt([prop(860,4,10,integer(4)),prop(861,9,10,integer(-2)),event(862,4,21,33,[('load',0,860),('reserve',1,861)])],'empty-reserve')
                for i in (1,2):publish([prop(260+2*i,4,10,integer(2-i)),event(261+2*i,4,20+i,31,[('shot',0,260+2*i)],7)],'reload-shot-'+str(i))
                publish([prop(280,8,10,integer(2)),event(281,8,50,31,[('shot',0,280)])],'matching-instance-shot');snapshot('continued');state('continued',50)
                attempt([event(870,4,60,30),initial(871,4,870,source,60,61)],'repeat-initialization')
                old_revision=r['snapshots']['continued']['canonical']['revision']
                a=assertion(100);body=deepcopy(a['payload']);body.pop('record_kind');body['validity']=s.interval(9,10)
                e=deepcopy(first['payload']);e.pop('record_kind');e['time']=s.instant(10);e['effects'][0]['validity']=s.interval(10)
                attempt([{'kind':'revise_event','record':s.rr(203),'expected_version':first['record_version_id'],'replacement':e}],'partial-historical-correction')
                publish([{'kind':'supersede_assertion','record':s.rr(a['identity']['record_id']),'expected_version':a['record_version_id'],'replacement':body,'rationale':'Correct first firing coordinate and original stock endpoint together'},{'kind':'revise_event','record':s.rr(203),'expected_version':first['record_version_id'],'replacement':e}],'historical-correction')
                snapshot('corrected');state('corrected-at-10',10);snapshot('historical',old_revision);state('historical-at-10',10,old_revision)
                # Run plain factual stock through complete admission, including private approval if eligible.
                attempt([claim(900,4,10,integer(0),start=60,note='Author observation: empty after the last shot')],'direct-observation')
                attempt([claim(910,4,10,integer(3),start=60,note='Unsupported replenishment: no reserve debit or loading event')],'direct-unsupported-refill')
                snapshot('direct');state('direct',60)
                # A direct replacement of the reserve premise is not an event transition.
                reserve=assertion(20);rb=deepcopy(reserve['payload']);rb.pop('record_kind');rb['validity']=s.interval(0,5);rb['proposition']=s.rr(921)
                attempt([prop(921,9,10,integer(1)),{'kind':'supersede_assertion','record':s.rr(reserve['identity']['record_id']),'expected_version':reserve['record_version_id'],'replacement':rb,'rationale':'Unsupported earlier replenishment, no supplying event'},claim(920,9,10,integer(2),start=5,end=20,note='Stock asserted directly outside a replenishment event')],'direct-stock-transition')
                snapshot('final');state('reserve-before-transition',4);state('reserve-after-transition',6);state('final',60)
                restart(s,r);snapshot('restart');state('restart',60);state('restart-historical',10,old_revision)
                r['retry_receipts']=[s.call('universe_commit',p['commit_arguments'])['result'] for p in r['publications']]
                with closing(sqlite3.connect(package)) as db:
                    db.row_factory=sqlite3.Row;r['initialization_receipts']=[dict(row) for row in db.execute('SELECT * FROM initialization_receipt ORDER BY instance_id')]
                final=build_identity(bin_dir,{})
                assert final['source_sha256']==r['build']['source_sha256'] and final['binaries']==r['build']['binaries']
                assert hashlib.sha256(oracle.read_bytes()).hexdigest()==r['expected_sha256']
                r['status']='passed'
            finally:
                s.close();r['cleanup']={'owned_root':str(s.root),'engine_stopped':not (s.root/'engine.sock').exists()}
                with closing(sqlite3.connect(package)) as src,closing(sqlite3.connect(output.with_suffix('.sqlite'))) as dst:src.backup(dst)
                r['seconds']=time.monotonic()-started;output.write_text(json.dumps(r,indent=2)+'\n')
    r['cleanup']['installation_removed']=not Path(directory).exists();r['seconds']=time.monotonic()-started;output.write_text(json.dumps(r,indent=2)+'\n');print('Pistol MCP',r['status'],r['seconds'])

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--bin-dir',type=Path,default=Path('target/debug'));a=p.parse_args();run(a.output,a.bin_dir.resolve())
