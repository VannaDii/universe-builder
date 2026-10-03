"""Actual stdio MCP assessment actions in an owned disposable installation.

Snapshots are read-only observations of raw SQLite workflow bytes and every
canonical table. No validation or commit call is used for the assessed candidate.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
from pilot_support import NAME, PilotSession


def snapshot(s):
    path = s.root / 'packages' / (s.uid + '.sqlite')
    with sqlite3.connect(f'file:{path}?mode=ro', uri=True) as db:
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        names = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
        tables = {}
        for name in names:
            rows = db.execute('SELECT * FROM "' + name + '"').fetchall()
            rows = [[{'hex':v.hex()} if isinstance(v, bytes) else v for v in row] for row in rows]
            tables[name] = sorted(rows, key=lambda r: json.dumps(r, sort_keys=True))
        workflow = [{'key':k, 'payload_utf8':raw.decode(), 'digest':digest}
                    for k,raw,digest in db.execute('SELECT key,payload,digest FROM workflow_entries ORDER BY key')]
        return {'workflow':workflow, 'canonical_tables':{k:v for k,v in tables.items() if k!='workflow_entries'}}


def assessment(s, p, viewed, text):
    source = next(c['next'] for c in viewed['compiled_changes']
                  if c['next'] and c['next']['payload']['record_kind']=='source_version')
    return {'kind':'source_assessment_v1','proposal':s.reference(p),'base_frame':p['base_frame'],
        'assessor':{'principal':s.agent.replace('prf_','prn_',1),'method':'human_review','tool':None,'assessed_at':'2026-10-03T00:00:00Z'},
        'sources':[{'key':'passage','source_version':{'universe':s.uid,'record':source['identity']['record_id'],'version':source['record_version_id']},
                    'blob_digest':hashlib.sha256(text.encode()).hexdigest(),'byte_size':len(text.encode()),'representation':'exact-utf8-v1',
                    'ranges':[{'start':0,'end':len(text.encode())}],'work_edition':None,'passage_id':None}],
        'dependencies':[],'declared_inventory':[],
        'inventory_declaration':{'kind':'no_material_claims','rationale':'Synthetic passage without declared material','exclusions':[]},
        'claim_mappings':[],'unresolved':[],'conclusion':'consistent_with_declared_inventory'}


def run(bin_dir, output):
    report = {'kind':'assessment-mcp-transcript-v1','cases':[], 'snapshots':{}, 'mcp':[]}
    with tempfile.TemporaryDirectory(prefix='asm-', dir='/tmp') as directory:
        s = PilotSession(directory, bin_dir, report)
        try:
            s.start()
            report['authenticated_profile'] = s.agent
            report['tools'] = s.client.request('tools/list', {})['tools']
            text = 'Exact café bytes.\n'
            path = Path(directory)/'source.txt';path.write_text(text)
            staged = s.admin('stage-source', NAME, 'Assessment pilot', path)
            p = s.propose(staged['operations'], 'proposal')
            viewed = s.call('universe_get_proposal', {'universe':NAME,'proposal_id':p['proposal_id'],'version':p['version']})['result']
            report['proposal'] = p
            body = assessment(s,p,viewed,text)
            attach = {'action':'attach_assessment','universe':NAME,'universe_id':s.uid,'context_id':s.ctx,
                'proposal_reference':s.reference(p),'expected_selection_generation':0,'body':body,'idempotency_key':'attach-a'}

            def case(label,args,error=False,validate=True):
                before=snapshot(s)
                if validate:s.client.schemas['universe_propose'][0].validate(args)
                raw=s.client.request('tools/call',{'name':'universe_propose','arguments':args})
                assert bool(raw.get('isError',False))==error,(label,raw)
                content=raw.get('structuredContent')
                assert json.loads(''.join(c['text'] for c in raw['content'] if c['type']=='text'))==content
                if not error:s.client.schemas['universe_propose'][1].validate(content)
                after=snapshot(s)
                report['snapshots'][label+'-before']=before
                report['snapshots'][label+'-after']=after
                report['cases'].append({'label':label,'authenticated_profile':s.agent,'arguments':copy.deepcopy(args),'response':raw,
                    'before':label+'-before','after':label+'-after'})
                assert before['canonical_tables']==after['canonical_tables'],label
                if error or 'retry' in label:assert before==after,label
                return content if error else content['result']

            a=case('attachment',attach)
            case('attachment-retry',attach)
            replace=copy.deepcopy(attach);replace['expected_selection_generation']=1;replace['idempotency_key']='attach-b'
            replace['body']['assessor']['assessed_at']='2026-10-03T00:00:01Z'
            b=case('replacement',replace)
            assert a['selected']!=b['selected']
            case('attachment-retry-after-replacement',attach)
            select={'action':'select_assessment','universe':NAME,'universe_id':s.uid,'context_id':s.ctx,
                    'proposal_reference':s.reference(p),'expected_selection_generation':2,'assessment_reference':a['selected'],'idempotency_key':'select-a'}
            case('reselection',select)
            clear=copy.deepcopy(select);clear.update(expected_selection_generation=3,assessment_reference=None,idempotency_key='withdraw')
            case('withdrawal',clear)
            case('selection-retry-after-withdrawal',select)
            case('withdrawal-retry',clear)
            invalid=copy.deepcopy(replace);invalid['expected_selection_generation']=4;invalid['idempotency_key']='impersonation'
            invalid['body']['assessor']['principal']=s.author.replace('prf_','prn_',1)
            case('impersonation',invalid,True)
            invalid=copy.deepcopy(attach);invalid['idempotency_key']='stale-attachment'
            case('stale-attachment',invalid,True)
            invalid=copy.deepcopy(select);invalid['idempotency_key']='stale-selection'
            case('stale-selection',invalid,True)
            invalid=copy.deepcopy(attach);invalid['body']['assessor']['assessed_at']='2026-10-03T00:00:02Z'
            case('mismatched-body-retry',invalid,True)
            invalid=copy.deepcopy(clear);invalid['expected_selection_generation']=4
            case('mismatched-generation-retry',invalid,True)
            invalid=copy.deepcopy(select);invalid['assessment_reference']=b['selected']
            case('mismatched-reference-retry',invalid,True)
            invalid=copy.deepcopy(clear);invalid['expected_selection_generation']=4;invalid['idempotency_key']='unchanged'
            case('no-change',invalid,True)
            invalid=copy.deepcopy(clear);del invalid['assessment_reference']
            case('missing-nullable-selection',invalid,True,False)
            invalid=copy.deepcopy(attach);invalid['body']['assessor']['extra']='forbidden'
            case('unknown-body-field',invalid,True,False)
            # Same installation, another authenticated agent with propose permission.
            original=s.agent
            s.client.close();s.agent=s.admin('enroll')['profile_id'];s.admin('grant',s.agent,s.uid,'--propose','--edit','--protected');s.connect();s.open()
            invalid=copy.deepcopy(replace);invalid['context_id']=s.ctx;invalid['expected_selection_generation']=4;invalid['idempotency_key']='wrong-owner'
            invalid['body']['assessor']['principal']=s.agent.replace('prf_','prn_',1)
            case('wrong-proposal-owner',invalid,True)
            s.client.close();s.agent=original;s.connect();s.open()
            # Grants are current authority even on an identical receipt retry.
            s.admin('grant',s.agent,s.uid)  # read access, no propose permission
            s.client.close();s.connect();s.open()
            retry=copy.deepcopy(attach);retry['context_id']=s.ctx
            case('permission-denied-retry',retry,True)
            invalid=copy.deepcopy(replace);invalid['context_id']=s.ctx;invalid['expected_selection_generation']=4;invalid['idempotency_key']='permission-denied'
            case('permission-denied-attachment',invalid,True)
            invalid=copy.deepcopy(select);invalid['context_id']=s.ctx;invalid['expected_selection_generation']=4;invalid['idempotency_key']='permission-denied-select'
            case('permission-denied-selection',invalid,True)
            s.admin('grant',s.agent,s.uid,'--propose','--edit','--protected');s.client.close();s.connect();s.open()
            # Restart recovers durable receipt IDs/generations without new entries.
            s.restart();retry=copy.deepcopy(attach);retry['context_id']=s.ctx
            assert case('attachment-retry-after-restart',retry)==a
            retry=copy.deepcopy(clear);retry['context_id']=s.ctx
            case('withdrawal-retry-after-restart',retry)
            # Separate record-only setup for source visibility: the new proposal's
            # world footprint is allowed while retained sources require full view.
            world_id='wld_'+s.rid(40)[4:]
            world={'kind':'create_world','client_ref':s.rid(40),'record':{'selector':'Visible','aliases':[],'labels':{'en':'Visible'}}}
            path=Path(directory)/'scope-source.txt';path.write_text(text)
            source_ops=s.admin('stage-source',NAME,'Scope source',path)['operations']
            setup=s.propose([world]+source_ops,'scope-setup')
            setup_view=s.call('universe_get_proposal',{'universe':NAME,'proposal_id':setup['proposal_id'],'version':setup['version']})['result']
            s.publish(setup,'scope-setup-commit')
            entity={'kind':'create_entity','client_ref':s.rid(41),'record':{'names':[],'types':[],
                'worldAssociations':[{'world':world_id,'role':'setting','validity':{'kind':'unspecified'},'qualifiers':{}}],
                'labels':{'en':'Scope subject'},'metadata':{}}}
            scoped=s.propose([entity],'scope-proposal')
            scope_body=assessment(s,scoped,setup_view,text)
            s.admin('grant',s.agent,s.uid,'--world',world_id,'--propose','--edit','--protected')
            s.client.close();s.connect();s.open()
            # Positive control: existing proposal is accessible with this grant.
            s.call('universe_get_proposal',{'universe':NAME,'proposal_id':scoped['proposal_id'],'version':scoped['version']})
            invalid={'action':'attach_assessment','universe':NAME,'context_id':s.ctx,'proposal_reference':s.reference(scoped),
                'expected_selection_generation':0,'body':scope_body,'idempotency_key':'source-scope-denied'}
            case('source-scope-denied',invalid,True)
            report['final_snapshot']=snapshot(s)
        finally:s.close()
    output.mkdir(parents=True,exist_ok=True)
    (output/'transcript.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(f'PASS: {len(report["cases"])} assessment MCP cases')

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--bin-dir',type=Path,default=Path('target/debug'));ap.add_argument('--output',type=Path,default=Path('docs/evidence/assessment-mcp'))
    args=ap.parse_args();run(args.bin_dir.resolve(),args.output)
