"""Actual MCP continuation, retcon and process-restart resource proof."""
import argparse
from contextlib import closing
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
from continuity_gap_pilot import ROOT, RecordedSession, save, sha, build_identity
from mlx_authoring_smoke import require

ORACLE=ROOT/'fixtures/resource-transitions/continuation.json'

def exercise(s,r,g):
    def entity(n,label): return {'kind':'create_entity','client_ref':s.rid(n),'record':{'names':[],'types':[],'worldAssociations':[],'labels':{'en':label},'metadata':{}}}
    def prop(n,owner,predicate,value):return {'kind':'define_proposition','client_ref':s.rid(n),'record':{'subject':s.rr(owner),'predicate':s.rr(predicate),'roles':[],'value':value,'quantification':'particular','context':s.scope['context']}}
    def integer(n):return {'kind':'integer','digits':str(n)}
    def premise(n,owner,predicate,value,end):
        return {'kind':'assert_proposition','client_ref':s.rid(n),'proposition':prop(n,owner,predicate,value)['record'],'assertion':{'proposition':s.rr(n),'polarity':'support','scope':s.scope,'validity':s.interval(0,end),'persistence':'explicit_interval','precision':'exact','basis':{'kind':'author_decision','note':'Established stock/holder'}}}
    def slot(name,order,role,predicate,change):return {'slot':name,'order':order,'presence':'required','target':{'role':role,'predicate':s.rr(predicate)},'condition':{'kind':'always'},'change':change,'lifetime':{'kind':'until_changed'}}
    def delta(n):return {'kind':'delta','delta':str(n),'minimum':'0','maximum':'12','unit':None}
    def action(n,key,slots):return {'kind':'define_action','client_ref':s.rid(n),'record':{'namespace':'continuation','key':key,'labels':{},'requirements':[],'consequenceContract':{'kind':'action_consequences_v1','slots':slots},'scope':s.scope,'validity':{'kind':'unspecified'}}}
    def event(n,t,a,effects,shooter=None):
        participants=[{'record':s.rr(1),'role':'gun'},{'record':s.rr(4),'role':'supply'}]
        pre=[]
        if shooter:
            participants.append({'record':s.rr(shooter),'role':'shooter'})
            pre=[{'kind':'claim','subject':{'kind':'record','ref':s.rr(1)},'predicate':'continuation:holder','roles':[],'value':{'kind':'value','value':{'kind':'entity_ref','ref':s.rr(shooter)}},'polarity':'support','context':None}]
        return {'kind':'record_event','client_ref':s.rid(n),'record':{'occurrence':'occurred','time':s.instant(t),'participants':participants,'action':s.rr(a),'effects':[{'slot':name,'order':order,'proposition':s.rr(p),'polarity':'support','scope':s.scope,'validity':s.interval(t)} for name,order,p in effects],'preconditions':pre,'labels':{},'expansionVersion':'events-v1'}}
    def publish(ops,key):return s.publish(s.propose(ops,key),key+'-commit')
    def reject(ops,key):
        before=s.open()['frame']['revision']
        if key in ('simultaneous_spend','retcon_simultaneous_successor'):
            args={'action':'create','universe':'The Cairn Archive Pilot','context_id':s.ctx,'operations':ops,'submission':'submitted','rationale':key,'idempotency_key':key}
            err=s.call('universe_propose',args,error=True);require(err['code']=='INVALID_ARGUMENT',str(err))
            result={'id':key,'operations':ops,'propose_arguments':args,'propose_error':err}
        else:
            p=s.propose(ops,key);err=s.validate(p,error=True)
            require(err['code']=='INVALID_ARGUMENT',str(err))
            denied=s.call('universe_commit',s.commit_args(p,r['publications'][-1]['validation'],key+'-denied'),error=True)
            result={'id':key,'proposal':p,'error':err,'commit_error':denied}
        after=s.open()['frame']['revision'];require(before==after,'rejection changed canon')
        r.setdefault('rejections',[]).append({**result,'before':before,'after':after})
    def query(key,t,revision=None):
        response=s.state([s.rid(n) for n in (1,2,3,4)],t,revision=revision)
        r.setdefault('states',[]).append({'id':key,'response':response});return response
    def narrative(n,kind,payload):return {'kind':'record_narrative_reference','client_ref':s.rid(n),'record':kind,'payload':{'record_kind':kind,**payload}}
    ops=[entity(n,label) for n,label in [(1,'Gun'),(2,'Holder A'),(3,'Holder B'),(4,'Constrained reserve')]]
    for n,key,shape in [(10,'rounds',{'kind':'integer'}),(11,'holder',{'kind':'entity_ref','subject_types':[]})]:
        ops.append({'kind':'define_property','client_ref':s.rid(n),'record':{'namespace':'continuation','key':key,'labels':{},'subjectTypes':[],'value':shape,'multiplicity':'single','persistence':'explicit_interval','exclusive':False,'symmetric':False,'transitive':False}})
    ops.append({'kind':'create_world','client_ref':s.rid(60),'record':{'selector':'Overlapping resource world','labels':{},'metadata':{}}})
    ops += [premise(20,1,10,integer(g['initial_gun']),11),premise(21,4,10,integer(g['initial_supply']),24),premise(22,1,11,{'kind':'entity_ref','ref':s.rr(2)},15),action(30,'shoot',[slot('shot',0,'gun',10,delta(-1))]),action(31,'handoff',[slot('holder',0,'gun',11,{'kind':'set','polarity':'support','value':{'kind':'entity_ref','ref':s.rr(3)}})]),action(32,'reload_three',[slot('load',0,'gun',10,delta(3)),slot('reserve',1,'supply',10,delta(-3))]),action(33,'reload_two',[slot('load',0,'gun',10,delta(2)),slot('reserve',1,'supply',10,delta(-2))]),{'kind':'create_work','client_ref':s.rid(40),'record':{'kind':'story','title':'Resource continuity proof','labels':{},'sourceRefs':[],'versions':[],'worldAssociations':[]}}]
    s.admin('status')
    publish(ops,'establish');query('initial',10)
    r['shots']=[];r['editions']=[]
    for i in range(1,13):
        t=10+i;n=100+2*i
        if i==5:
            publish([prop(50,1,11,{'kind':'entity_ref','ref':s.rr(3)}),event(51,15,31,[('holder',0,50)])],'handoff')
            reject([prop(900,1,10,integer(7)),event(901,15,30,[('shot',0,900)],3)],'dependent_holder_same_time')
        receipt=publish([prop(n,1,10,integer(g['initial_gun']-i)),event(n+1,t,30,[('shot',0,n)],2 if i<=5 else 3)],f'shot-{i}')
        r['shots'].append({'index':i,'receipt':receipt,'event':s.rid(n+1)})
        query(f'shot-{i}',t)
        if i==1:
            reject([prop(902,1,10,integer(11)),event(903,11,30,[('shot',0,902)],2)],'simultaneous_spend')
            overlapping=event(914,11,30,[('shot',0,915)])
            overlapping['record']['worlds']=[s.rid(60).replace('rec_','wld_',1)]
            overlapping['record']['effects'][0]['scope']={**s.scope,'applicability':{'kind':'worlds','world_ids':overlapping['record']['worlds']}}
            reject([prop(915,1,10,integer(11)),overlapping],'overlapping_world_spend')
        if i in (4,8,12):
            edition=200+i;scene=220+i;revision=receipt['revision']
            publish([narrative(edition,'work_version',{'work':s.rr(40),'versionLabel':f'scene-{i//4}','binding':{'kind':'bound','continuity':s.u['continuity_id'],'revision':revision}})],f'edition-{i}')
            version=s.get([s.rid(edition)])[0]
            publish([narrative(scene,'scene_ref',{'workVersion':{'universe':s.uid,'record':s.rid(edition),'version':version['record_version_id']},'sceneId':f'scene-{i//4}','viewpoint':s.rr(2 if i<=4 else 3),'narrativePosition':i//4,'depictedEvents':[s.rr(101+2*j) for j in range(i-3,i+1)],'narrationFrame':s.scope['context'],'worldAssociations':[]})],f'scene-{i}')
            r['editions'].append({'version':version,'scene':s.get([s.rid(scene)])[0],'revision':revision})
        if i==8:
            s.restart();query('mid_restart',18)
    reject([prop(904,1,10,integer(0)),event(905,23,30,[('shot',0,904)],3)],'thirteenth_shot')
    reject([prop(906,1,10,integer(4)),prop(907,4,10,integer(1)),event(908,24,32,[('load',0,906),('reserve',1,907)])],'forged_reload_amount')
    publish([prop(300,1,10,integer(3)),prop(301,4,10,integer(1)),event(302,24,32,[('load',0,300),('reserve',1,301)])],'reload_three');query('reload',24)
    publish([prop(303,1,10,integer(2)),event(304,25,30,[('shot',0,303)],3)],'continuation_shot');query('continuation',25)
    reject([prop(909,1,10,integer(4)),prop(910,4,10,integer(-1)),event(911,26,33,[('load',0,909),('reserve',1,910)])],'constrained_reload_underflow')
    first=s.get([s.rid(103)])[0]
    replacement=deepcopy(first['payload']);replacement.pop('record_kind');replacement['time']=s.instant(12);replacement['effects'][0]['validity']=s.interval(12)
    reject([{'kind':'revise_event','record':s.rr(103),'expected_version':first['record_version_id'],'replacement':replacement}],'retcon_simultaneous_successor')
    initial=s.state([s.rid(1)],10,revision=r['shots'][0]['receipt']['revision'])['result']['assertions']
    stock=next(a for a in initial if a['payload']['proposition']['record']==s.rid(20))
    replacement=deepcopy(first['payload']);replacement.pop('record_kind');replacement['effects'][0]['proposition']=s.rr(912)
    smaller=deepcopy(stock['payload']);smaller.pop('record_kind');smaller['proposition']=s.rr(913)
    reject([prop(913,1,10,integer(11)),{'kind':'supersede_assertion','record':s.rr(stock['identity']['record_id']),'expected_version':stock['record_version_id'],'replacement':smaller,'rationale':'Reduce initial load by one'},prop(912,1,10,integer(10)),{'kind':'revise_event','record':s.rr(103),'expected_version':first['record_version_id'],'replacement':replacement}],'retcon_stale_balances')
    # A valid earlier-time retcon also explicitly moves the established premise end.
    replacement=deepcopy(first['payload']);replacement.pop('record_kind');replacement['time']=s.instant(10);replacement['effects'][0]['validity']=s.interval(10)
    premise_replacement=deepcopy(stock['payload']);premise_replacement.pop('record_kind');premise_replacement['validity']=s.interval(0,10)
    publish([{'kind':'revise_event','record':s.rr(103),'expected_version':first['record_version_id'],'replacement':replacement},{'kind':'supersede_assertion','record':s.rr(stock['identity']['record_id']),'expected_version':stock['record_version_id'],'replacement':premise_replacement,'rationale':'Move first shot and explicit stock endpoint together'}],'valid_earlier_retcon')
    query('retcon_current',10);query('retcon_old',10,r['editions'][0]['revision'])
    r['old_event']=s.get([s.rid(103)],context=s.open(r['editions'][0]['revision'])['context_id'])[0];s.open()
    r['before_restart_head']=s.open()['frame']['revision'];s.restart();r['after_restart_head']=s.open()['frame']['revision'];query('final_restart',25)
    r['restart_editions']=s.get([e[k]['identity']['record_id'] for e in r['editions'] for k in ('version','scene')])
    r['restart_old_event']=s.get([s.rid(103)],context=s.open(r['editions'][0]['revision'])['context_id'])[0];s.open()
    r['retry_receipts']=[s.call('universe_commit',p['commit_arguments'])['result'] for p in r['publications']]
    query('restart_old',10,r['editions'][0]['revision'])

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);a=parser.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    start=time.monotonic();report={'status':'failed'}
    command=['cargo','build','--locked','-p','universe-cli','-p','universe-engine','-p','universe-mcp'];built=subprocess.run(command,cwd=ROOT,capture_output=True,text=True);save(out/'build.json',{'command':command,'returncode':built.returncode,'stdout':built.stdout,'stderr':built.stderr});require(built.returncode==0,'build failed')
    identity=build_identity(ROOT/'target/debug',{});identity['continuation_oracle_sha256']=sha(ORACLE);save(out/'build-identity.json',identity);(out/'oracle.json').write_bytes(ORACLE.read_bytes())
    with tempfile.TemporaryDirectory(prefix='resource-cont-',dir='/tmp') as d:
        with (out/'mcp-transcript.jsonl').open('w') as wire:
            s=RecordedSession(d,ROOT/'target/debug',report,wire=wire)
            try:s.start();report['installation']=s.u;exercise(s,report,json.loads(ORACLE.read_text()));report['status']='executed'
            finally:
                s.close();dbs=list((s.root/'packages').rglob('*.sqlite'))
                if len(dbs)==1:
                    with closing(sqlite3.connect(dbs[0])) as source,closing(sqlite3.connect(out/'package.sqlite')) as dest:source.backup(dest)
                    report['package_sha256']=sha(out/'package.sqlite')
                save(out/'report.json',report)
    result=subprocess.run([sys.executable,str(ROOT/'scripts/audit_cumulative_resources.py'),str(out)],capture_output=True,text=True);save(out/'audit-execution.json',{'returncode':result.returncode,'stdout':result.stdout,'stderr':result.stderr});require(result.returncode==0,result.stderr)
    negative=subprocess.run([sys.executable,str(ROOT/'scripts/test_cumulative_resources.py'),'--evidence',str(out),'-v'],capture_output=True,text=True);save(out/'audit-negative-tests.json',{'returncode':negative.returncode,'stdout':negative.stdout,'stderr':negative.stderr});require(negative.returncode==0 and 'skipped' not in negative.stderr,negative.stderr)
    final=build_identity(ROOT/'target/debug',{});require(final['source_sha256']==identity['source_sha256'] and final['binaries']==identity['binaries'] and sha(ORACLE)==identity['continuation_oracle_sha256'],'proof inputs changed')
    save(out/'result.json',{'status':'passed','seconds':time.monotonic()-start});save(out/'evidence-manifest.json',{p.name:sha(p) for p in sorted(out.iterdir()) if p.is_file() and p.name!='evidence-manifest.json'});print('PASS',out)
if __name__=='__main__':main()
