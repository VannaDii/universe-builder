"""Actual MCP retrieval; the independent expected table lives outside this driver."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import time
import subprocess
from canonical_families_pilot import FamilySession, private, authority_counts
from pilot_support import NAME


def run(output, bin_dir):
    started = time.monotonic()
    report = {'mcp': [], 'views': {}}
    with tempfile.TemporaryDirectory(prefix='effective-object-', dir='/tmp') as directory:
        with output.with_suffix('.jsonl').open('w') as wire:
            s = FamilySession(directory, bin_dir, report, wire=wire)
            try:
                s.start()
                def typ(n, key, parent=None):
                    return {'kind':'define_type','client_ref':s.rid(n),'record':{'namespace':'object','key':key.lower(),'name':key,'labels':{},'parent':s.rid(parent) if parent else None,'parentResolution':'resolved' if parent else 'root','classificationExecutable':True,'applicability':{'kind':'universe_wide'}}}
                def prop(n, key, value='boolean'):
                    return {'kind':'define_property','client_ref':s.rid(n),'record':{'namespace':'object','key':key,'labels':{},'subjectTypes':[s.rid(1)],'value':{'kind':value},'multiplicity':'single','persistence':'explicit_interval','exclusive':False,'symmetric':False,'transitive':False}}
                def fact(n, owner, predicate, value, mode='shared', polarity='support', validity=None, scope=None):
                    return {'kind':'assert_proposition','client_ref':s.rid(n),'proposition':{'subject':s.rr(owner),'predicate':s.rr(predicate),'value':value,'context':s.scope['context'],'quantification':'particular'},'assertion':{'attributeMode':mode,'proposition':s.rr(n),'polarity':polarity,'scope':scope or s.scope,'validity':validity or s.interval(0,30),'persistence':'explicit_interval','precision':'exact','basis':{'kind':'author_decision','note':'Retrieval proof source'}}}
                boolean=lambda v:{'kind':'boolean','value':v}
                integer=lambda v:{'kind':'integer','digits':str(v)}
                ops=[{'kind':'create_world','client_ref':s.rid(n),'record':{'selector':key,'labels':{},'metadata':{}}} for n,key in [(60,'A'),(61,'B')]]
                ops += [typ(1,'Tree'),typ(2,'Cedar',1),{'kind':'create_entity','client_ref':s.rid(4),'record':{'names':[],'classification':s.rid(2),'classificationResolution':'resolved','worldAssociations':[],'labels':{},'metadata':{}}},{'kind':'create_entity','client_ref':s.rid(5),'record':{'names':[],'classification':None,'classificationResolution':'unclassified','worldAssociations':[],'labels':{},'metadata':{}}},prop(10,'grows'),prop(11,'height','integer'),prop(12,'ammunition','integer'),prop(13,'unknown'),prop(14,'private'),
                     fact(30,1,10,boolean(True)),fact(31,2,10,boolean(True),polarity='refutation'),
                     fact(32,4,11,integer(7),'instance'),fact(33,1,12,integer(6),'initial_value'),fact(34,4,12,integer(2),'instance'),
                     fact(35,1,13,boolean(True),validity={'kind':'unspecified'}),
                     fact(36,1,14,boolean(True),scope={'context':s.scope['context'],'applicability':{'kind':'worlds','world_ids':[s.rid(61).replace('rec_','wld_')]}}),
                     {'kind':'define_action','client_ref':s.rid(20),'record':{'namespace':'object','key':'grow','labels':{},'consequenceContract':{'kind':'action_consequences','slots':[]},'requirements':[{'role':'actor','predicate':s.rr(10),'value':boolean(True)}],'scope':s.scope,'validity':s.interval(0,30)}},
                     {'kind':'define_rule','client_ref':s.rid(21),'record':{'namespace':'object','key':'tree-rule','labels':{},'kind':'physical_constraint','commitPolicy':'advisory','applicability':{'kind':'universe_wide'},'subjectTypes':[s.rid(1)],'targetPredicates':['object:grows'],'expression':{'kind':'lit','value':True},'capabilities':['basic.v1'],'executable':True,'validity':s.interval(0,30)}}]
                original=s.publish(s.propose(ops,'seed'),'seed-commit')['revision']
                ids=[c['record_id'] for c in report['publications'][0]['review']['changes']]
                report['source_records']=[r for start in range(0,len(ids),5) for r in s.get(ids[start:start+5])]
                def view(label, revision=None, day=15, world=None, predicates=None, represented=None, perspective='author', entity=4):
                    before=authority_counts(s)
                    ctx=s.open(revision,day,represented,perspective)['context_id']
                    args={'universe':NAME,'context_id':ctx,'entity_ids':[s.rid(entity)],'predicate_filters':predicates or []}
                    if world:args.update(world_id=world,world='A' if world==s.rid(60).replace('rec_','wld_') else 'B')
                    response=s.call('universe_get_state',args)
                    after=authority_counts(s);assert before==after
                    report['views'][label]=response
                    report.setdefault('immutability',{})[label]={'before':before,'after':after}
                    return ctx
                view('unclassified',original,entity=5)
                ctx=view('original',original)
                brief=s.call('universe_get_context',{'universe':NAME,'context_id':ctx,'focus_ids':[s.rid(4)],'purpose':'effective object evidence','byte_budget':65536})
                report['context']=brief
                old=s.get([s.rid(20)])[0];body=deepcopy(old['payload']);body['requirements'][0]['value']=boolean(False)
                corrected=s.publish(s.propose([{'kind':'revise_definition','record':s.rr(20),'expected_version':old['record_version_id'],'replacement':body}],'edit-action'),'edit-action-commit')['revision']
                report['revisions']={'original':original,'current':corrected}
                report['current_action']=s.get([s.rid(20)])[0]
                view('historical',original);view('current',corrected);view('later',corrected,day=25);view('expired',corrected,day=31)
                view('predicate',corrected,predicates=[s.rid(12)])
                s.open()
                character={'kind':'record_narrative_reference','client_ref':s.rid(70),'record':'represented_context','payload':{'record_kind':'represented_context','universe':s.uid,'kind':{'kind':'character','holder':s.rr(4)},'parent':s.scope['context'],'labels':{}}}
                s.publish(s.propose([character],'character-context'),'character-context-commit')
                view('other_context',represented=s.rid(70))
                view('character',represented=s.rid(70),perspective={'character':s.rid(4)})
                s.restart();view('restart_historical',original);view('restart_current',corrected)
                # This inconsistent legacy specimen cannot pass public scalar admission.
                # Seed only a disposable history using the tightly constrained example.
                scalar=fact(37,2,10,boolean(False))
                payloads=[{'record_kind':'proposition',**scalar['proposition']},{'record_kind':'assertion',**scalar['assertion']}]
                seed=Path(directory)/'scalar.json';seed.write_text(json.dumps(payloads))
                s.client.close();s.client=None;s.cli('shutdown',profile=s.author)
                deadline=time.monotonic()+5
                while (s.root/'engine.sock').exists() and time.monotonic()<deadline:time.sleep(.02)
                assert not (s.root/'engine.sock').exists()
                seeded=subprocess.run([str(bin_dir/'examples/seed_effective_object_conflict'),str(s.root/'packages'/(s.uid+'.sqlite')),s.u['continuity_id'],s.author.replace('prf_','prn_',1),str(seed)],check=True,capture_output=True,text=True)
                report['scalar_seed_revision']=seeded.stdout.strip()
                s.admin('status');s.connect();s.open()
                report['source_records'].extend(s.get([s.rid(37),s.rid(38)]))
                view('scalar_current');s.restart();view('scalar_restart')
                # A world-only grant is checked against the existing context too.
                s.open();w=s.rid(60).replace('rec_','wld_')
                view('world_b',world=s.rid(61).replace('rec_','wld_'))
                oldctx=view('world',world=w)
                private(s,{'method':'grant','grant':{'profile_id':s.agent,'universe_id':s.uid,'worlds':[w],'propose':False,'edit':False,'protected':False,'limits':{}}})
                report['grant_changed_context']=s.client.request('tools/call',{'name':'universe_get_state','arguments':{'universe':NAME,'context_id':oldctx,'entity_ids':[s.rid(4)],'predicate_filters':[]}})
                assert report['grant_changed_context'].get('isError')
                restrictedctx=view('restricted',world=w)
                s.admin('revoke',s.agent)
                report['revoked']=s.client.request('tools/call',{'name':'universe_get_state','arguments':{'universe':NAME,'context_id':restrictedctx,'entity_ids':[s.rid(4)],'predicate_filters':[]}})
                assert report['revoked'].get('isError')
            finally:
                s.close()
                output.write_text(json.dumps(report,indent=2)+'\n')
    report['seconds']=time.monotonic()-started
    output.write_text(json.dumps(report,indent=2)+'\n')
    print(f'MCP retrieval captured in {report["seconds"]:.1f}s')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--bin-dir',type=Path,default=Path('target/debug'));a=p.parse_args();run(a.output,a.bin_dir.resolve())
