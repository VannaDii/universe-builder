"""Actual MCP admission and historical correction proof on a disposable installation.
Expected statuses are authored in fixtures/ancestor-applicability/oracle.json.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import time
from canonical_families_pilot import FamilySession
from pilot_support import NAME


def run(bin_dir, output):
    started=time.monotonic()
    report={'kind':'ancestor-applicability-mcp','cases':{},'mcp':[]}
    with tempfile.TemporaryDirectory(prefix='ancestor-',dir='/tmp') as directory:
        output.parent.mkdir(parents=True,exist_ok=True)
        wire=output.with_suffix('.jsonl').open('w')
        s=FamilySession(directory,bin_dir,report,wire=wire)
        try:
            s.start()
            def typedef(n,key,parent=None,scope=None,resolution=None):
                return {'kind':'define_type','client_ref':s.rid(n),'record':{'namespace':'ancestor','key':key,'name':key.title(),'labels':{},'parent':s.rid(parent) if parent else None,'parentResolution':resolution or ('resolved' if parent else 'root'),'classificationExecutable':True,'applicability':scope or {'kind':'universe_wide'}}}
            def entity(n,type_id=None,resolution=None):
                return {'kind':'create_entity','client_ref':s.rid(n),'record':{'names':[],'classification':s.rid(type_id) if type_id else None,'classificationResolution':resolution or ('resolved' if type_id else 'unclassified'),'worldAssociations':[],'labels':{},'metadata':{}}}
            def property(n,key,targets):
                return {'kind':'define_property','client_ref':s.rid(n),'record':{'namespace':'ancestor','key':key,'labels':{},'subjectTypes':[s.rid(t) for t in targets],'value':{'kind':'boolean'},'multiplicity':'single','persistence':'explicit_interval','exclusive':False,'symmetric':False,'transitive':False}}
            def fact(n,owner,predicate,value=True,mode='instance',scope=None,validity=None,context=None):
                return {'kind':'assert_proposition','client_ref':s.rid(n),'proposition':{'subject':s.rr(owner),'predicate':s.rr(predicate),'value':{'kind':'boolean','value':value},'context':context or s.scope['context'],'quantification':'particular'},'assertion':{'attributeMode':mode,'proposition':s.rr(n),'polarity':'support','scope':scope or s.scope,'validity':validity or s.interval(0,30),'persistence':'explicit_interval','precision':'exact','basis':{'kind':'author_decision','note':'Independent authored ancestry proof'}}}
            def event(n,owner=4,day=15):
                return {'kind':'record_event','client_ref':s.rid(n),'record':{'occurrence':'occurred','action':s.rr(20),'time':s.instant(day),'participants':[{'record':s.rr(owner),'role':'actor'}],'preconditions':[],'effects':[],'labels':{}}}
            def revise(n,changes):
                old=s.get([s.rid(n)])[0]; body=deepcopy(old['payload']);body.update(changes)
                return {'kind':'revise_definition','record':s.rr(n),'expected_version':old['record_version_id'],'replacement':body}
            def check(key,ops,status):
                p=s.propose(ops,key)
                if status=='legal':
                    v=s.validate(p);assert v['coverage']=='complete' and all(f['outcome']=='supported' for f in v['findings']),v
                    row={'status':'legal','validation':v}
                elif status=='illegal':
                    # Structural/event invalidity or a complete blocking finding.
                    raw=s.client.request('tools/call',{'name':'universe_validate','arguments':{'mode':'proposal','universe':NAME,'context_id':s.ctx,'proposal_reference':s.reference(p),'check_scope':'universe'}})
                    if raw.get('isError'):
                        row={'status':'illegal','rejection':raw}
                    else:
                        v=raw['structuredContent']['result']['execution'];assert v['coverage']=='complete' and any(f['outcome']!='supported' for f in v['findings']),v
                        assert s.approval(p,v,check=False).returncode!=0
                        row={'status':'illegal','validation':v}
                else:
                    v=s.validate(p);assert v['coverage']=='partial' and v['unsupported_capabilities'],v
                    assert s.approval(p,v,check=False).returncode!=0
                    row={'status':'unresolved','validation':v}
                row['proposal']=p
                v=row.get('validation',report['publications'][0]['validation'])
                row['commit_denial']=s.call('universe_commit',s.commit_args(p,v,key+'-denied'),error=True)
                report['cases'][key]=row
                return p
            ops=[typedef(1,'tree'),typedef(2,'cedar',1),typedef(3,'stone'),entity(4,2),entity(5,3),entity(6),entity(7,None,'ambiguous'),property(10,'grows',[1]),property(11,'hazard',[1]),property(12,'plain',[]),
                 fact(30,1,10,mode='shared'),
                 {'kind':'define_action','client_ref':s.rid(20),'record':{'namespace':'ancestor','key':'grow','labels':{},'requirements':[{'role':'actor','predicate':s.rr(10),'value':{'kind':'boolean','value':True}}],'scope':s.scope,'validity':{'kind':'unspecified'},'consequenceContract':{'kind':'action_consequences','slots':[]}}},
                 {'kind':'define_relation','client_ref':s.rid(13),'record':{'namespace':'ancestor','key':'climb','labels':{},'roles':[{'name':'tree','participantTypes':[s.rid(1)],'multiplicity':'single','ordered':False}]}}]
            s.publish(s.propose(ops,'seed'),'seed-commit')
            p=check('cedar_property',[fact(40,4,11)],'legal');s.publish(p,'cedar-property-commit')
            check('unrelated_property',[fact(41,5,11)],'illegal')
            check('unclassified_property',[fact(42,6,11)],'unresolved')
            check('ambiguous_classification',[fact(43,7,11)],'unresolved')
            check('ambiguous_parent',[revise(2,{'parent':None,'parentResolution':'ambiguous'}),fact(44,4,11)],'unresolved')
            def relation(n,participant):
                op=fact(n,4,13);op['proposition'].pop('value');op['proposition']['roles']=[{'role':'tree','participant':s.rr(participant)}];return op
            p=check('cedar_relation',[relation(45,4)],'legal');s.publish(p,'cedar-relation-commit')
            check('unrelated_relation',[relation(46,5)],'illegal')
            check('conflicting_definitions',[fact(47,2,10,False,'shared')],'illegal')
            check('initial_not_capability',[property(14,'initial',[1]),fact(48,1,14,mode='initial_value')],'legal')
            world_a={'kind':'create_world','client_ref':s.rid(60),'record':{'selector':'A','labels':{'en':'A'},'metadata':{}}}
            world_b={'kind':'create_world','client_ref':s.rid(61),'record':{'selector':'B','labels':{'en':'B'},'metadata':{}}}
            s.publish(s.propose([world_a,world_b],'worlds'),'worlds-commit')
            a={'kind':'worlds','world_ids':[s.rid(60).replace('rec_','wld_')]};b={'kind':'worlds','world_ids':[s.rid(61).replace('rec_','wld_')]}
            for offset,(key,scope,status) in enumerate([('world_allowed',a,'legal'),('world_denied',b,'illegal')]):
                n=160+offset*10
                check(key,[typedef(n,key,scope=a),entity(n+1,n),property(n+2,key,[n]),fact(n+3,n+1,n+2,scope={'context':s.scope['context'],'applicability':scope})],status)
            parent=typedef(220,'world_parent',scope=a);child=typedef(221,'world_child',220,scope=b)
            check('ancestor_world_independent',[parent,child,entity(222,221),property(223,'world_ancestor',[220]),fact(224,220,223,mode='shared',scope={'context':s.scope['context'],'applicability':a}),fact(225,222,223,scope={'context':s.scope['context'],'applicability':a})],'legal')
            check('property_definition_revalidates_fact',[revise(11,{'subjectTypes':[s.rid(3)]})],'illegal')
            relation_body=s.get([s.rid(13)])[0]['payload']['roles'];relation_body=deepcopy(relation_body);relation_body[0]['participantTypes']=[s.rid(3)]
            check('relation_definition_revalidates_participant',[revise(13,{'roles':relation_body})],'illegal')
            check('universe_wide_cannot_widen_type',[typedef(230,'bounded',scope=a),entity(231,230),property(232,'bounded',[230]),fact(233,231,232)],'illegal')
            check('world_unknown',[typedef(66,'unknown',scope={'kind':'unspecified'}),entity(67,66),property(68,'unknown',[66]),fact(69,67,68)],'unresolved')
            def rule(n,targets,subject):
                return {'kind':'define_rule','client_ref':s.rid(n),'record':{'namespace':'ancestor','key':str(n),'labels':{},'kind':'physical_constraint','commitPolicy':'always_block','applicability':{'kind':'universe_wide'},'subjectTypes':[s.rid(t) for t in targets],'targetPredicates':['ancestor:grows'],'expression':{'kind':'claim','subject':{'kind':'record','ref':s.rr(subject)},'predicate':'ancestor:grows','value':{'kind':'value','value':{'kind':'boolean','value':True}},'polarity':'support'},'capabilities':['basic.v1'],'executable':True,'validity':s.interval(10,20)}}
            check('ancestor_rule',[rule(70,[1],4)],'legal')
            check('explicit_unrelated_rule_operand',[rule(71,[1],5)],'illegal')
            check('unknown_rule',[rule(72,[1],6)],'unresolved')
            check('event_expired',[event(73,day=31)],'illegal')
            check('unrelated_event',[event(74,owner=5)],'illegal')
            check('conflicting_event',[fact(75,2,10,False,'shared'),event(76)],'illegal')
            initial_action={'kind':'define_action','client_ref':s.rid(205),'record':{'namespace':'ancestor','key':'initial-use','labels':{},'requirements':[{'role':'actor','predicate':s.rr(204),'value':{'kind':'boolean','value':True}}],'scope':s.scope,'validity':{'kind':'unspecified'},'consequenceContract':{'kind':'action_consequences','slots':[]}}}
            initial_event=event(206);initial_event['record']['action']=s.rr(205)
            check('initial_event_missing',[property(204,'initial_only',[1]),fact(207,1,204,mode='initial_value'),initial_action,initial_event],'illegal')
            dream={'kind':'record_narrative_reference','client_ref':s.rid(201),'record':'represented_context','payload':{'record_kind':'represented_context','universe':s.uid,'kind':{'kind':'authored','label':'Dream'},'parent':s.scope['context'],'labels':{}}}
            dream_action=deepcopy(initial_action);dream_action['client_ref']=s.rid(202);dream_action['record']['key']='dream-use';dream_action['record']['requirements'][0]['predicate']=s.rr(10);dream_action['record']['scope']['context']=s.rr(201)
            dream_event=event(203);dream_event['record']['action']=s.rr(202)
            check('context_does_not_borrow_definition',[dream,dream_action,dream_event],'illegal')
            holder=property(242,'holder',[]);holder['record']['value']={'kind':'entity_ref','subject_types':[]}
            custody=fact(245,241,242);custody['proposition']['value']={'kind':'entity_ref','ref':s.rr(4)}
            power={'kind':'define_item_power','client_ref':s.rid(240),'record':{'item':s.rr(241),'holderPredicate':s.rr(242),'powerPredicate':s.rr(10),'value':{'kind':'boolean','value':False},'scope':s.scope,'validity':s.interval(0,30)}}
            check('indirect_shared_conflict',[entity(241,3),holder,custody,power,event(244)],'illegal')
            p=check('inherited_event',[event(80)],'legal');original=s.publish(p,'event-commit')['revision']
            old=s.get([s.rid(80)])[0]
            remove_facts=[]
            for pub in report['publications']:
                if pub['key'] in ('cedar-property-commit','cedar-relation-commit'):
                    for change in pub['review']['changes']:
                        fact_record=s.get([change['record_id']])[0]
                        remove_facts.append({'kind':'tombstone_record','record':s.rr(change['record_id']),'expected_version':fact_record['record_version_id'],'rationale':'Remove fact invalidated by corrected ancestry'})
            check('definition_retcon_revalidates_event',[revise(2,{'parent':s.rid(3)}),*remove_facts],'illegal')
            correction=[revise(2,{'parent':s.rid(3)}),*remove_facts,{'kind':'tombstone_record','record':s.rr(80),'expected_version':old['record_version_id'],'rationale':'Remove event invalidated by corrected classification ancestry'}]
            corrected=s.publish(s.propose(correction,'corrected'),'corrected-commit')['revision']
            report['history']={'original':original,'corrected':corrected}
            def history():
                prior=s.open(original)['context_id']; current=s.open(corrected)['context_id']
                a=s.get([s.rid(2),s.rid(4),s.rid(80)],prior);b=s.get([s.rid(2),s.rid(4)],current)
                assert a[0]['payload']['parent']==s.rid(1) and b[0]['payload']['parent']==s.rid(3)
                assert a[1]['identity']==b[1]['identity'] and a[1]['record_version_id']==b[1]['record_version_id']
                assert a[2]==old
                s.open();return {'before':a,'after':b}
            report['history']['before_restart']=history()
            s.restart();report['history']['after_restart']=history()
            check('corrected_event_after_restart',[event(81)],'illegal')
            assert report['history']['before_restart']==report['history']['after_restart']
        finally:
            s.close();wire.close()
            output.write_text(json.dumps(report,ensure_ascii=False,separators=(',',':'))+'\n')
    report['seconds']=time.monotonic()-started
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,ensure_ascii=False,separators=(',',':'))+'\n')
    oracle=json.loads((Path(__file__).resolve().parents[1]/'fixtures/ancestor-applicability/oracle.json').read_text())
    assert {k:v['status'] for k,v in report['cases'].items()}==oracle['admission']
    print(f"PASS: {len(report['cases'])} MCP cases; correction and restart; {report['seconds']:.1f}s")

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--bin-dir',type=Path,default=Path('target/debug'));p.add_argument('--output',type=Path,required=True);a=p.parse_args();run(a.bin_dir.resolve(),a.output)
