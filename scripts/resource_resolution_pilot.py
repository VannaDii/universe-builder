"""Actual MCP publication-gate proof; owned synthetic author installation only."""
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
from continuity_gap_pilot import RecordedMCP, build_identity
from audit_incremental_authoring import canonical_snapshot
from pilot_support import NAME

class AuthorSession(FamilySession):
    def connect(self):
        self.client=RecordedMCP(self.bin_dir/'universe-mcp',installation=self.root,profile=self.author,wire=self.wire)
        self.instructions=self.client.initialization['instructions']
    def publish(self,p,key):
        v=self.validate(p);assert v['coverage']=='complete'
        review=self.admin('review',NAME,p['proposal_id'],p['version'],p['digest'])
        args=self.commit_args(p,v,key)
        denied=self.call('universe_commit',args,error=True)
        approval=json.loads(self.approval(p,v).stdout)
        receipt=self.call('universe_commit',args)['result'];assert self.call('universe_commit',args)['result']==receipt
        self.report.setdefault('publications',[]).append({'key':key,'review':review,'validation':v,'approval':approval,'receipt':receipt,'commit_arguments':args,'without_approval':denied})
        self.open();return receipt

def run(output,bin_dir):
    start=time.monotonic();output.parent.mkdir(parents=True,exist_ok=True)
    oracle=Path(__file__).resolve().parents[1]/'fixtures/resource-resolution/expected.json'
    r={'expected_sha256':hashlib.sha256(oracle.read_bytes()).hexdigest(),'status':'running','mcp':[],'snapshots':{},'states':{},'cases':{},'build':build_identity(bin_dir,{})}
    with tempfile.TemporaryDirectory(prefix='resource-resolution-',dir='/tmp') as directory:
        with output.with_suffix('.jsonl').open('w') as wire:
            s=AuthorSession(directory,bin_dir,r,wire=wire)
            try:
                s.start();r['author_profile']=s.author;r['installation']=s.u;r['initialization_instructions']=s.instructions;package=s.root/'packages'/(s.uid+'.sqlite')
                val=lambda n:{'kind':'integer','digits':str(n)}
                def prop(n,owner,value):return {'kind':'define_proposition','client_ref':s.rid(n),'record':{'subject':s.rr(owner),'predicate':s.rr(10),'value':val(value),'quantification':'particular','context':s.scope['context']}}
                def claim(n,owner,value,t,end):return {'kind':'assert_proposition','client_ref':s.rid(n),'proposition':prop(n,owner,value)['record'],'assertion':{'attributeMode':'instance','proposition':s.rr(n),'polarity':'support','scope':s.scope,'validity':s.interval(t,end),'persistence':'explicit_interval','precision':'exact','basis':{'kind':'author_decision','note':'Exact factual stock claim; arrival is not supplied'}}}
                def assertion(n):return next(row for row in canonical_snapshot(package,s.open()['frame']['revision'])['records'].values() if row['payload']['record_kind']=='assertion' and row['payload']['proposition']['record']==s.rid(n))
                def revise(p,ops,key):return s.call('universe_propose',{'action':'revise','universe':NAME,'context_id':s.ctx,'proposal_reference':s.reference(p),'operations':ops,'submission':'submitted','rationale':key,'idempotency_key':key})['result']
                def decision(n,predicate,fp):return {'kind':'record_issue_decision','client_ref':s.rid(n),'record':{'fingerprints':[fp],'mode':'accept','scope':'resource:'+s.rid(predicate),'rationale':'Creative authority explicitly accepts this exact unexplained arrival, without inventing its cause','principal':s.author.replace('prf_','prn_',1)}}
                def snapshot(key,revision=None):
                    frame=s.open(revision);c=canonical_snapshot(package,frame['frame']['revision']);r['snapshots'][key]={'canonical':c,'mcp_records':records(s,list(c['records']),frame['context_id'])};s.open();return c
                def state(key,t,revision=None):
                    frame=s.open(revision,t);r['states'][key]=s.call('universe_get_state',{'universe':NAME,'context_id':frame['context_id'],'entity_ids':[s.rid(n) for n in (4,6,7,8,9)],'predicate_filters':[]});s.open()
                def blocked(p,key):
                    before=authority_counts(s);head=s.open()['frame']['revision'];v=s.validate(p)
                    accepted={fp for row in canonical_snapshot(package,head)['records'].values() if row['payload']['record_kind']=='issue_decision' and row['payload']['mode']=='accept' for fp in row['payload']['fingerprints']}
                    f=[f for f in v['findings'] if f['rule_id']==s.rid(20) and f['outcome']=='not_established' and f['fingerprint'] not in accepted];assert len(f)==1,v
                    assert s.approval(p,v,check=False).returncode!=0
                    args=s.commit_args(p,v,key+'-denied');first=s.call('universe_commit',args,error=True);retry=s.call('universe_commit',args,error=True)
                    assert before==authority_counts(s) and head==s.open()['frame']['revision']
                    r['cases'][key]={'proposal':p,'validation':v,'denied':first,'retry':retry,'commit_arguments':args,'before':before,'after':authority_counts(s),'head':head}
                    return f[0]['fingerprint']
                def delta(n):return {'kind':'delta','delta':str(n),'minimum':'0','maximum':'5','unit':None}
                def action(n,key,changes):return {'kind':'define_action','client_ref':s.rid(n),'record':{'namespace':'resolution','key':key,'labels':{},'requirements':[],'scope':s.scope,'validity':s.interval(0),'consequenceContract':{'kind':'action_consequences','slots':[{'slot':name,'order':i,'presence':'required','target':{'role':role,'predicate':s.rr(10)},'condition':{'kind':'always'},'change':delta(d),'lifetime':{'kind':'until_changed'}} for i,(name,role,d) in enumerate(changes)]}}}
                def event(n,t,a,participants,effects):return {'kind':'record_event','client_ref':s.rid(n),'record':{'occurrence':'occurred','time':s.instant(t),'participants':[{'record':s.rr(owner),'role':role} for role,owner in participants],'action':s.rr(a),'effects':[{'slot':name,'order':i,'proposition':s.rr(p),'polarity':'support','scope':s.scope,'validity':s.interval(t)} for i,(name,p) in enumerate(effects)],'preconditions':[],'labels':{}}}
                def publish(ops,key):return s.publish(s.propose(ops,key),key+'-commit')
                ops=[{'kind':'introduce_instance','client_ref':s.rid(n),'name':{'text':name,'validity':s.interval(0)},'classification':None,'world_associations':[]} for n,name in [(4,'Pistol'),(6,'Supply'),(7,'Accounted reserve'),(8,'Correction reserve'),(9,'Unexplained reserve')]]
                ops += [{'kind':'define_property','client_ref':s.rid(10),'record':{'namespace':'resolution','key':'rounds','labels':{},'subjectTypes':[],'value':{'kind':'integer'},'multiplicity':'single','persistence':'explicit_interval','exclusive':False,'symmetric':False,'transitive':False}}, {'kind':'define_rule','client_ref':s.rid(20),'record':{'namespace':'resolution','key':'require_accounted_stock','labels':{},'kind':'physical_constraint','commitPolicy':'block_unless_exception','applicability':{'kind':'universe_wide'},'targetPredicates':['resolution:rounds'],'expression':{'kind':'lit','value':True},'capabilities':['resources.accounting.v1'],'executable':True,'validity':{'kind':'unspecified'}}},claim(40,4,0,0,10),claim(60,6,3,0,5),claim(70,7,1,0,5),claim(80,8,1,0,5),claim(90,9,2,0,10),action(30,'replenish',[('arrive','reserve',1),('supply','supply',-1)]),action(31,'reload_two',[('load','gun',2),('reserve','reserve',-2)]),action(32,'shoot',[('shot','gun',-1)])]
                publish(ops,'baseline');snapshot('baseline');state('baseline',4)
                earlier=assertion(90);earlier_body=deepcopy(earlier['payload']);earlier_body.pop('record_kind');earlier_body['proposition']=s.rr(95);earlier_body['validity']=s.interval(0,5)
                stock=[prop(95,9,1),{'kind':'supersede_assertion','record':s.rr(earlier['identity']['record_id']),'expected_version':earlier['record_version_id'],'replacement':earlier_body,'rationale':'Correct earlier stock to one and split its interval at five'},claim(91,9,2,5,10)];p=s.propose(stock,'unexplained-increase');fp=blocked(p,'unresolved')
                # An enrolled client cannot mint creative authority, even when it
                # copies the real author's principal and a real finding fingerprint.
                agent=RecordedMCP(bin_dir/'universe-mcp',installation=s.root,profile=s.agent,wire=wire)
                def agent_call(tool,args,error=False):
                    result=agent.call(tool,args,error=error);r['mcp'].append({'tool':tool,'arguments':args,'expected_error':error,'result':result,'profile':s.agent});return result
                try:
                    before=authority_counts(s)
                    ctx=agent_call('universe_open_context',{'universe':NAME,'continuity_id':s.u['continuity_id'],'revision':{'kind':'head'},'represented_context':s.u['context_id'],'temporal_query':{'kind':'timeless'},'temporal_systems':[],'perspective':'author'})['result']['context_id']
                    fake=agent_call('universe_propose',{'action':'create','universe':NAME,'context_id':ctx,'operations':[claim(150,9,2,5,10),decision(151,150,fp)],'submission':'submitted','rationale':'An enrolled client tries to impersonate creative acceptance','idempotency_key':'forged-acceptance'})['result']
                    rejected=agent_call('universe_validate',{'mode':'proposal','universe':NAME,'context_id':ctx,'proposal_reference':s.reference(fake),'check_scope':'universe'},error=True)
                    denied=agent_call('universe_commit',s.commit_args(fake,r['publications'][0]['validation'],'forged-acceptance-denied'),error=True)
                    assert rejected['code']=='POLICY_DENIED' and before==authority_counts(s)
                    r['forged_acceptance']={'proposal':fake,'validation':rejected,'denied':denied,'before':before,'after':authority_counts(s)}
                finally:agent.close()
                restart(s,r);r['restart_denied']=s.call('universe_commit',r['cases']['unresolved']['commit_arguments'],error=True)
                r['restart_ordinary_approval_returncode']=s.approval(p,r['cases']['unresolved']['validation'],check=False).returncode;assert r['restart_ordinary_approval_returncode']!=0
                accepted_ops=stock+[decision(100,91,fp)];p=revise(p,accepted_ops,'explicit-acceptance');s.publish(p,'accepted-two-commit');old=snapshot('accepted-two')['revision'];state('accepted-two',6)
                row=assertion(91);body=deepcopy(row['payload']);body.pop('record_kind');body['proposition']=s.rr(92)
                changed=[prop(92,9,3),{'kind':'supersede_assertion','record':s.rr(row['identity']['record_id']),'expected_version':row['record_version_id'],'replacement':body,'rationale':'Change the exact unexplained amount from two to three'}]
                p=s.propose(changed,'changed-claim');newfp=blocked(p,'changed-claim');assert newfp!=fp
                before=authority_counts(s)
                r['old_approval_reuse']=s.call('universe_commit',s.commit_args(p,r['publications'][1]['validation'],'old-approval-reuse'),error=True)
                r['old_commit_key_reuse']=s.call('universe_commit',s.commit_args(p,r['publications'][1]['validation'],'accepted-two-commit'),error=True)
                assert before==authority_counts(s)
                p=revise(p,changed+[decision(101,92,newfp)],'fresh-acceptance');s.publish(p,'accepted-three-commit');snapshot('accepted-three');state('accepted-three',6)
                publish([prop(71,7,2),prop(61,6,2),event(72,5,30,[('reserve',7),('supply',6)],[('arrive',71),('supply',61)])],'accounted-replenishment');snapshot('accounted');state('accounted',6)
                correction=[claim(81,8,2,5,20)];p=s.propose(correction,'unexplained-correction-reserve');blocked(p,'uncorrected-evidence')
                row=assertion(80);body=deepcopy(row['payload']);body.pop('record_kind');body['proposition']=s.rr(82)
                correction += [prop(82,8,2),{'kind':'supersede_assertion','record':s.rr(row['identity']['record_id']),'expected_version':row['record_version_id'],'replacement':body,'rationale':'Correct the earlier observed stock to two; no arrival is asserted'}]
                p=revise(p,correction,'valid-earlier-correction');s.publish(p,'valid-correction-commit');snapshot('corrected');state('corrected-before',4);state('corrected-after',6)
                publish([prop(41,4,2),prop(93,9,1),event(42,10,31,[('gun',4),('reserve',9)],[('load',41),('reserve',93)])],'reload-accepted-stock');snapshot('reloaded');state('reloaded',10)
                for n,t,value in [(43,11,1),(45,12,0)]:publish([prop(n,4,value),event(n+1,t,32,[('gun',4)],[('shot',n)])],'shot-'+str(t))
                p=s.propose([prop(47,4,-1),event(48,13,32,[('gun',4)],[('shot',47)])],'exhausted');before=authority_counts(s);error=s.validate(p,error=True);assert 'underflow' in error['message'];r['event_rejection']={'response':error,'denied':s.call('universe_commit',s.commit_args(p,r['publications'][-1]['validation'],'exhausted-denied'),error=True),'before':before,'after':authority_counts(s)};assert before==authority_counts(s)
                p=s.propose([prop(50,4,2),prop(51,9,-1),event(52,13,31,[('gun',4),('reserve',9)],[('load',50),('reserve',51)])],'reserve-exhausted');before=authority_counts(s);error=s.validate(p,error=True);assert 'underflow' in error['message'];r['reload_rejection']={'response':error,'denied':s.call('universe_commit',s.commit_args(p,r['publications'][-1]['validation'],'reserve-exhausted-denied'),error=True),'before':before,'after':authority_counts(s)};assert before==authority_counts(s)
                snapshot('final');state('final',13);snapshot('historical',old);state('historical',6,old)
                restart(s,r);snapshot('restart');state('restart',13);state('restart-historical',6,old)
                # Recover every committed operation from the durable operation
                # index after restart, using the original commit idempotency key.
                r['recovered_operations'] = []
                for publication in r['publications']:
                    commit_key = publication['commit_arguments']['idempotency_key']
                    recovered = s.call('universe_get_operation', {'lookup':'key','universe':NAME,'operation_kind':'commit','idempotency_key':commit_key})['result']
                    assert recovered['state'] == 'succeeded', recovered
                    assert recovered['receipt'] == publication['receipt'], recovered
                    r['recovered_operations'].append({'idempotency_key':commit_key,'result':recovered})
                r['retry_receipts']=[s.call('universe_commit',x['commit_arguments'])['result'] for x in r['publications']]
                final=build_identity(bin_dir,{})
                assert final['source_sha256']==r['build']['source_sha256'] and final['binaries']==r['build']['binaries']
                assert hashlib.sha256(oracle.read_bytes()).hexdigest()==r['expected_sha256']
                r['status']='executed';r['seconds']=time.monotonic()-start
            finally:
                s.close();r['cleanup']={'engine_stopped':not (s.root/'engine.sock').exists(),'owned_root':str(s.root)}
                with closing(sqlite3.connect(package)) as src,closing(sqlite3.connect(output.with_suffix('.sqlite'))) as dst:src.backup(dst)
                output.write_text(json.dumps(r,indent=2)+'\n')
    r['cleanup']['installation_removed']=not Path(directory).exists();r['seconds']=time.monotonic()-start;output.write_text(json.dumps(r,indent=2)+'\n');print('Resource resolution MCP',r['status'],r['seconds'])
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--bin-dir',type=Path,default=Path('target/debug'));a=p.parse_args();run(a.output,a.bin_dir.resolve())
