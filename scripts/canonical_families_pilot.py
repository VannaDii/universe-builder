"""Actual MCP family qualification on one owned, disposable installation.

Private author staging/approval uses the existing authenticated engine protocol.
Only Realm and Secret are bootstrapped offline; their public route is adoption.
"""
import argparse
import base64
from contextlib import closing
from copy import deepcopy
import hashlib
import json
import random
import re
from pathlib import Path
import socket
import sqlite3
import struct
import subprocess
import tempfile
import time
import traceback
import zlib
from continuity_gap_pilot import RecordedSession, ROOT, build_identity, save, sha
from pilot_support import NAME, source_anchor

FIXTURE = ROOT / 'fixtures/canonical-families/records.json'
OPERATIONS = dict(entity='create_entity',world='create_world',property='define_property',
    relation='define_relation',value_definition='define_value',domain_pack='install_pack',
    work='create_work',saga='create_saga',appearance='create_appearance',
    proposition='define_proposition',epistemic_attitude='add_belief',observation='record_observation',
    communication='record_communication',memory='record_memory',goal='record_plan',
    commitment='record_commitment',completeness='set_completeness',boundary='set_creative_boundary',
    rule='define_rule',issue_decision='record_issue_decision',exception='add_exception',item_power='define_item_power')


class FamilySession(RecordedSession):
    def publish(self, p, key):
        v=self.validate(p)
        assert v['coverage']=='complete' and all(f['outcome']=='supported' for f in v['findings']),v
        impact=self.impact(p)
        assert impact['delivery']['complete'] and impact['result']['coverage']=='complete'
        args=self.commit_args(p,v,key)
        self.call('universe_commit',args,error=True)
        review=self.admin('review',NAME,p['proposal_id'],p['version'],p['digest'])
        approval=json.loads(self.approval(p,v).stdout)
        assert approval=={'approved':self.reference(p),'validation_run':v['run_id']}
        receipt=self.call('universe_commit',args)['result']
        assert self.call('universe_commit',args)['result']==receipt
        self.open()
        self.report.setdefault('publications',[]).append({'key':key,'review':review,
            'author_selection':{'author_profile':self.author,'rationale':p['rationale'],'approval':approval},
            'validation':v,'impact':impact,'receipt':receipt,'commit_arguments':args})
        return receipt


def replace(value, bindings):
    if isinstance(value, dict): return {k:replace(v,bindings) for k,v in value.items()}
    if isinstance(value, list): return [replace(v,bindings) for v in value]
    return bindings[value[1:]] if isinstance(value,str) and value.startswith('$') else value


def private(s, request, profile=None):
    """No credential or handshake is recorded, even in failed evidence."""
    profile = profile or s.author
    with closing(sqlite3.connect('file:'+str(s.root/'profiles'/(profile+'.sqlite'))+'?mode=ro',uri=True)) as db:
        credential = db.execute('SELECT credential FROM credential WHERE profile_id=?',(profile,)).fetchone()[0]
    def send(sock, body):
        data=json.dumps(body).encode();sock.sendall(struct.pack('>I',len(data))+data)
    def recv(sock):
        def exact(n):
            data=b''
            while len(data)<n:
                chunk=sock.recv(n-len(data));assert chunk,'engine closed';data+=chunk
            return data
        return json.loads(exact(struct.unpack('>I',exact(4))[0]))
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(30);sock.connect(str(s.root/'engine.sock'))
        send(sock,{'protocol_version':re.search(r'PROTOCOL_VERSION: &str = "([^"]+)"',(ROOT/'crates/universe-protocol/src/lib.rs').read_text())[1],'profile_id':profile,'credential':credential,'client_name':'family-qualification'})
        del credential
        recv(sock)
        send(sock,{'id':1,'request':request});reply=recv(sock)
    s.report.setdefault('private',[]).append({'request':request,'profile':profile,'reply':reply})
    return reply['result']


def png_bytes():
    # Exact original PNG, several content chunks. No media editing or generation.
    width=height=384
    rng=random.Random(25)
    raw=b''.join(b'\0'+rng.randbytes(width*3) for _ in range(height))
    def chunk(kind, data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')


def operation(name, body, bindings):
    family=body['record_kind'];body={k:v for k,v in body.items() if k!='record_kind'}
    if family in ('work_version','scene_ref','passage_ref'):
        return {'kind':'record_narrative_reference','client_ref':bindings[name],'record':family,'payload':{'record_kind':family,**body}}
    return {'kind':OPERATIONS[family],'client_ref':bindings[name],'record':body}


def records(s, ids, context=None):
    return [r for start in range(0,len(ids),5) for r in s.get(ids[start:start+5],context)]


def snapshot(s, label, report, revision=None):
    frame=s.open(revision)
    with closing(sqlite3.connect('file:'+str(s.root/'packages'/(s.uid+'.sqlite'))+'?mode=ro',uri=True)) as db:
        # IDs are lookup inputs only; all payload/version authority comes from MCP.
        ids=[r[0] for r in db.execute('SELECT record_id FROM head_membership')]
        ids=sorted(set(ids)|set(report['ids']))
    row={'label':label,'revision':frame['frame']['revision'],'records':records(s,ids,frame['context_id'])}
    report['snapshots'].append(row)
    return row


def authority_counts(s):
    with closing(sqlite3.connect('file:'+str(s.root/'packages'/(s.uid+'.sqlite'))+'?mode=ro',uri=True)) as db:
        tables=['record_versions','commits','commit_changes','head_membership','operation_receipts']
        return {t:db.execute('SELECT count(*) FROM "'+t+'"').fetchone()[0] for t in tables}


def reject(s, report, key, op, profile=None):
    before=authority_counts(s);head=s.open()['frame']['revision']
    args={'action':'create','universe':NAME,'context_id':s.ctx,'operations':[op],
          'submission':'submitted','rationale':key,'idempotency_key':key}
    raw=s.client.request('tools/call',{'name':'universe_propose','arguments':args})
    report['controls'].append({'key':key,'arguments':args,'proposal_response':raw,'before':before,'head_before':head})
    c=report['controls'][-1]
    if not raw.get('isError'):
        p=raw['structuredContent']['result'];v=s.validate(p,error=True);c['validation_rejection']=v
        assert v['code'] in ('INVALID_ARGUMENT','POLICY_DENIED'),v
        c['commit_rejection']=s.call('universe_commit',s.commit_args(p,report['publications'][-1]['validation'],key+'-commit'),error=True)
    assert authority_counts(s)==before
    assert s.open()['frame']['revision']==head
    c['after']=authority_counts(s);c['head_after']=head


def restart(s, report):
    before=s.admin('status')
    s.restart()
    after=s.admin('status')
    assert before['service_instance']!=after['service_instance']
    report.setdefault('restart_instances',[]).append({'before':before['service_instance'],'after':after['service_instance']})


def run(output, bin_dir):
    output.mkdir(parents=True,exist_ok=False);started=time.monotonic()
    f=json.loads(FIXTURE.read_text());report={'status':'failed','snapshots':[],'controls':[],'ids':[]}
    save(output/'fixture.json',f)
    save(output/'build-identity.json',build_identity(bin_dir,{}))
    with tempfile.TemporaryDirectory(prefix='universe-families-',dir='/tmp') as directory:
        with (output/'mcp-transcript.jsonl').open('w') as wire:
            s=FamilySession(directory,bin_dir,report,wire=wire)
            try:
                s.start();agent=s.agent;report['installation']=s.u
                b={n:s.rid(i+1) for i,n in enumerate(f['records'])}
                b.update(universe=s.uid,context=s.u['context_id'],calendar=s.calendar,
                    continuity=s.u['continuity_id'],principal=s.author.replace('prf_','prn_',1))
                b['world_id']=b['world'].replace('rec_','wld_',1)
                # No public creation operation exists for these two immutable families.
                seed=[]
                for i,n in enumerate(('realm','secret')):
                    body=replace(f['records'][n],b)
                    from relational_history import encoded
                    seed.append({'record_version_id':f'ver_{900001+i:024x}',
                        'identity':{'universe_id':s.uid,'record_id':b[n],'record_kind':body['record_kind']},
                        'payload':body,'payload_digest':hashlib.sha256((body['record_kind']+':').encode()+encoded(body)).hexdigest()})
                report['seed']=seed;s.client.close();s.client=None;s.cli('shutdown',profile=s.author)
                deadline=time.monotonic()+5
                while (s.root/'engine.sock').exists() and time.monotonic()<deadline:time.sleep(.02)
                assert not (s.root/'engine.sock').exists()
                seed_path=Path(directory)/'seed.json';save(seed_path,seed)
                dbpath=s.root/'packages'/(s.uid+'.sqlite')
                subprocess.run([str(bin_dir/'examples/seed_family_history'),str(dbpath),s.u['continuity_id'],b['principal'],str(seed_path)],check=True,capture_output=True,text=True)
                s.admin('status');s.connect();s.open()
                source,source_receipt=s.stage(f['source_text'],'Exact source α','exact-source')
                b['source']=source['payload']['source']['record'];b['source_version']=source['identity']['record_id']
                b['source_revision']=source_receipt['revision'];report['source']=source
                report['ids'] += [b['source'],b['source_version']]
                anchor=source_anchor(s.uid,source,f['source_text'],f['excerpt'],s.rr(s.u['context_id']))
                b['anchor']=s.rid(101)
                s.publish(s.propose([{'kind':'add_source_anchor','client_ref':b['anchor'],'record':anchor}],'anchor'),'anchor-commit')
                data=png_bytes();assert len(data)>256*1024 and hashlib.sha256(data).hexdigest()==f['media']['sha256']
                image=Path(directory)/'Original α.png';image.write_bytes(data)
                staged=private(s,{'method':'stage_image','universe':NAME,'source':str(image)})['Ok']
                b['image']=staged['asset_id'];report['image']={'metadata':staged['metadata'],'base64':base64.b64encode(data).decode()}
                s.publish(s.propose(staged['operations'],'image'),'image-commit');image.unlink()
                # Propose as author where the existing issue-decision policy requires it.
                s.client.close();s.agent=s.author;s.connect();s.open()
                phase=[n for n in f['records'] if n not in ('realm','secret','scene','passage','appearance','exception')]
                bodies={n:replace(f['records'][n],b) for n in phase}
                s.publish(s.propose([operation(n,bodies[n],b) for n in phase],'families'),'families-commit')
                w=s.get([b['work_version']])[0];b['work_version_version']=w['record_version_id']
                b['rule_version']=s.get([b['rule']])[0]['record_version_id']
                phase=['scene','passage','appearance','exception'];bodies.update({n:replace(f['records'][n],b) for n in phase})
                s.publish(s.propose([operation(n,bodies[n],b) for n in phase],'pinned-editorial'),'pinned-editorial-commit')
                report['bindings']=b;report['expected_bodies']=bodies
                report['ids'] += list(b[n] for n in f['records'])+[b['anchor'],b['image']]
                original=snapshot(s,'original',report)
                report['epistemic_state']=s.state([b['actor']],13)
                assert report['epistemic_state']['result']['assertions']==[]
                old={r['identity']['record_id']:r for r in original['records']}
                appearance=deepcopy(old[b['appearance']]['payload']);appearance.pop('record_kind');appearance['physical_description']=f['corrected_description']
                corrections=[{'kind':'revise_appearance','record':s.rr(b['appearance']),'expected_version':old[b['appearance']]['record_version_id'],'replacement':appearance},
                    {'kind':'set_work_binding','record':s.rr(b['work_version']),'expected_version':old[b['work_version']]['record_version_id'],'binding':{'kind':'segments','segments':[{'segment':'opening α','continuity':b['continuity'],'revision':original['revision']},{'segment':'ending α','continuity':b['continuity'],'revision':b['source_revision']}]}},
                    {'kind':'set_saga_membership','record':s.rr(b['saga']),'expected_version':old[b['saga']]['record_version_id'],'membership':{'work':s.rr(b['work']),'role':'opening','order':2}}]
                s.publish(s.propose(corrections,'corrections'),'corrections-commit')
                corrected=snapshot(s,'corrected',report);snapshot(s,'original-after-correction',report,original['revision'])
                # Re-admit every original body through the existing public historical route.
                current={r['identity']['record_id']:r for r in corrected['records']}
                adoption=[{'kind':'adopt_record_version','source':r,'expected_version':current[r['identity']['record_id']]['record_version_id']} for r in original['records'] if r['identity']['record_id'] in report['ids'] and r['identity']['record_id']!=b['rule']]
                s.publish(s.propose(adoption,'historical-adoption'),'historical-adoption-commit')
                adopted=snapshot(s,'adopted',report)
                restart(s,report);report['restarts']=1;snapshot(s,'adopted-restart',report);snapshot(s,'corrected-restart',report,corrected['revision']);snapshot(s,'original-restart',report,original['revision'])
                pub=report['publications'][-1]
                assert s.call('universe_commit',pub['commit_arguments'])['result']==pub['receipt']
                # Exercise references, exact provenance, kind checks and import receipts.
                cases=[]
                def case(key,name,path,value):
                    body=deepcopy(bodies[name]);node=body
                    for k in path[:-1]:node=node[k]
                    node[path[-1]]=value
                    op=operation(name,body,{**b,name:s.rid(500+len(cases))});cases.append((key,op))
                case('dangling-goal','goal',['desired'],s.rr(9999))
                case('dangling-commitment','commitment',['obligated'],s.rr(9999))
                case('dangling-observation','observation',['observed'],s.rr(9999))
                case('dangling-saga','saga',['memberships',0,'work'],s.rr(9999))
                case('dangling-scene','scene',['viewpoint'],s.rr(9999))
                case('dangling-work-source','work',['sourceRefs',0],s.rr(9999))
                case('dangling-pack-member','pack',['records'],[s.rid(9999)])
                case('wrong-power-property','power',['powerPredicate'],s.rr(b['actor']))
                case('dangling-exception','exception',['authorizingDecision'],s.rr(9999))
                case('dangling-completeness','completeness',['subject'],s.rr(9999))
                case('dangling-boundary','boundary',['area','record'],s.rid(9999))
                case('dangling-memory','memory',['content'],s.rr(9999))
                case('cross-universe-communication','communication',['sender'],{'universe':'unv_'+format(9999,'024x'),'record':b['actor']})
                case('wrong-attitude-holder','belief',['holder'],s.rr(b['property']))
                case('dangling-work-revision','work_version',['binding','revision'],'rev_'+format(9999,'024x'))
                case('wrong-work-kind','work_version',['work'],s.rr(b['actor']))
                case('wrong-passage-anchor','passage',['anchor'],s.rr(b['actor']))
                case('wrong-work-continuity','work_version',['binding','continuity'],'cont_'+format(9999,'024x'))
                actor_version=next(r for r in adopted['records'] if r['identity']['record_id']==b['actor'])['record_version_id']
                case('wrong-scene-edition-kind','scene',['workVersion'],{'universe':s.uid,'record':b['actor'],'version':actor_version})
                case('wrong-passage-edition-kind','passage',['workVersion'],{'universe':s.uid,'record':b['actor'],'version':actor_version})
                case('wrong-source-pin','passage',['workVersion','version'],source['record_version_id'])
                case('missing-receipt-time','communication',['receivedAt'],None)
                case('wrong-appearance-image-kind','appearance',['images',0,'asset'],s.rr(b['actor']))
                bad=deepcopy(anchor);bad['excerptDigest']='a'*64
                cases.append(('forged-excerpt',{'kind':'add_source_anchor','client_ref':s.rid(600),'record':bad}))
                bad=deepcopy(anchor);bad['locator']['start']+=1
                cases.append(('split-utf8',{'kind':'add_source_anchor','client_ref':s.rid(601),'record':bad}))
                bad=deepcopy(staged['metadata']);bad['digest']='a'*64
                cases.append(('forged-media-receipt',{'kind':'add_image_asset','client_ref':s.rid(602),'record':bad}))
                for key,op in cases:reject(s,report,key,op)
                # Agent origin cannot author issue decisions, even with broad grants.
                s.client.close();s.agent=agent;s.connect();s.open()
                reject(s,report,'agent-issue-decision',operation('decision',bodies['decision'],{**b,'decision':s.rid(603)}))
                # No grant: exact historical metadata/media/source cannot bypass access.
                outsider=s.admin('enroll')['profile_id'];s.client.close();s.agent=outsider;s.connect()
                denied={'universe':NAME,'mode':'summary'}
                report['no_grant']=s.call('universe_describe',denied,error=True)
                s.client.close();s.agent=agent;s.connect();s.open()
                # World-only grant must not expose shared records; current context is rechecked.
                private(s,{'method':'grant','grant':{'profile_id':agent,'universe_id':s.uid,'worlds':[b['world_id']],'propose':True,'edit':True,'protected':True,'limits':{}}})
                report['restricted_read']=s.call('universe_get',{'universe':NAME,'context_id':s.ctx,'record_ids':[b['appearance'],b['source_version'],b['secret'],b['communication']],'field_groups':['payload']},error=True)
                report['restricted_reads']={}
                for name in ('appearance','source_version','image','secret','communication','realm','memory','goal'):
                    report['restricted_reads'][name]=s.call('universe_get',{'universe':NAME,'context_id':s.ctx,'record_ids':[b[name]],'field_groups':['payload']},error=True)
                s.admin('grant',agent,s.uid,'--propose','--edit','--protected');s.open()
                s.admin('revoke',agent)
                report['revoked_read']=s.client.request('tools/call',{'name':'universe_get','arguments':{'universe':NAME,'context_id':s.ctx,'record_ids':[b['source']],'field_groups':['payload']}})
                assert report['revoked_read'].get('isError')
                s.client.close();s.agent=s.author;s.connect();s.open();restart(s,report);report['restarts']+=1
                snapshot(s,'final-restart',report)
                preview=private(s,{'method':'image_preview','universe':NAME,'context_id':s.ctx,'asset':b['image']})
                assert preview.get('Ok'),preview
                report['status']='executed'
            except Exception:
                report['error']=traceback.format_exc();raise
            finally:
                s.close()
                dbs=list((s.root/'packages').glob('*.sqlite'))
                if len(dbs)==1:
                    with closing(sqlite3.connect(dbs[0])) as src, closing(sqlite3.connect(output/'package.sqlite')) as dest:src.backup(dest)
                report['seconds']=time.monotonic()-started;save(output/'report.json',report)
    save(output/'manifest.json',{str(p.relative_to(output)):sha(p) for p in output.iterdir() if p.is_file() and p.name!='manifest.json'})
    print('PASS: canonical-family MCP publication/history/restart/denial controls')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--bin-dir',type=Path,default=ROOT/'target/debug')
    a=p.parse_args();run(a.output.resolve(),a.bin_dir.resolve())
