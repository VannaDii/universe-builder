"""Thirteen unchanged synthetic stimuli, using the existing persistent pilot helpers."""
import json
from pilot_support import NAME, source_anchor
from mlx_authoring_smoke import require

CASE_IDS = {
    'extraordinary_action_classified_ordinary':'G01',
    'correct_phase_action_blocks':'C01',
    'dead_character_takes_ordinary_action':'G02',
    'shooting_without_ammunition_or_consumption':'G03',
    'ordinary_action_grants_unrelated_power':'G04',
    'opposing_assertions_same_objective_proposition':'G05',
    'different_single_property_values_block':'C02',
    'knows_objectively_refuted_proposition':'G06',
    'communication_received_before_sent':'G07',
    'single_relation_role_has_two_simultaneous_counterparts':'G08',
    'appearance_conflicts_with_structured_hair':'G09',
    'verified_quote_does_not_entail_linked_assertion':'G10',
    'source_only_contradicts_canon':'G11',
}

def cli_result(result):
    try:
        value=json.loads(result.stdout)
    except ValueError:
        value=None
    return {'attempted':True,'returncode':result.returncode,'stdout':result.stdout,
            'stderr':result.stderr,'result':value}

def exercise(s, report):
    def entity(n, label):
        return {'kind':'create_entity','client_ref':s.rid(n),'record':{'names':[],'types':[],'worldAssociations':[],'labels':{'en':label},'metadata':{}}}
    def prop(n,key,shape):
        return {'kind':'define_property','client_ref':s.rid(n),'record':{'namespace':'gap','key':key,'labels':{},'subjectTypes':[],'value':shape,'multiplicity':'single','persistence':'explicit_interval','exclusive':True,'symmetric':False,'transitive':False}}
    def claim(n,owner,predicate,value,polarity='support',basis=None):
        return {'kind':'assert_proposition','client_ref':s.rid(n),'proposition':{'subject':s.rr(owner),'predicate':s.rr(predicate),'value':value,'context':s.scope['context'],'quantification':'particular'},'assertion':{'proposition':s.rr(n),'polarity':polarity,'scope':s.scope,'validity':s.interval(10),'persistence':'explicit_interval','precision':'exact','basis':basis or {'kind':'author_decision','note':'Synthetic probe'}}}
    def event(n,label,action=20,effects=None):
        return {'kind':'record_event','client_ref':s.rid(n),'record':{'occurrence':'occurred','action':s.rr(action),'time':s.instant(12),'participants':[{'record':s.rr(1),'role':'actor'}],'preconditions':[],'effects':effects or [],'labels':{'en':label}}}
    false={'kind':'boolean','value':False}
    true={'kind':'boolean','value':True}
    ops=[entity(1,'Mara'),entity(2,'Iven'),entity(3,'Nera')]
    ops += [prop(10,'alive',{'kind':'boolean'}),prop(11,'wall_phase',{'kind':'boolean'}),prop(12,'hair',{'kind':'text'}),prop(13,'bullets',{'kind':'integer'}),prop(14,'password_is_ember',{'kind':'boolean'}),prop(15,'invulnerable',{'kind':'boolean'})]
    ops += [{'kind':'define_action','client_ref':s.rid(20),'record':{'namespace':'gap','key':'ordinary','labels':{},'requirements':[],'scope':s.scope,'validity':{'kind':'unspecified'}}},{'kind':'define_action','client_ref':s.rid(21),'record':{'namespace':'gap','key':'phase','labels':{},'requirements':[{'role':'actor','predicate':s.rr(11),'value':true}],'scope':s.scope,'validity':{'kind':'unspecified'}}}]
    ops += [claim(30,1,10,false),claim(31,1,11,false),claim(32,1,12,{'kind':'text','text':'black'}),claim(33,1,13,{'kind':'integer','digits':'0'}),claim(34,1,14,true,'refutation')]
    ops += [{'kind':'define_relation','client_ref':s.rid(40),'record':{'namespace':'gap','key':'one_counterpart','labels':{},'roles':[{'name':'counterpart','participantTypes':[],'multiplicity':'single','ordered':False}]}}]
    s.publish(s.propose(ops,'gap-seed'),'gap-seed-commit')
    rows=report['probes']
    def probe(key,operations,blocked=False):
        p=s.propose(operations,key)
        v=s.validate(p,error=blocked and key != 'different_single_property_values_block')
        if blocked and key == 'different_single_property_values_block':
            denied=s.approval(p,v,check=False)
            require(denied.returncode != 0, 'multiplicity control approval unexpectedly passed')
        if not blocked:
            require(v['coverage'] == 'complete' and not v['findings'], 'baseline gap behavior drifted')
            approved=s.approval(p,v,check=False)
            require(approved.returncode == 0, 'baseline gap approval behavior drifted')
        row={'id':CASE_IDS[key], 'case':key,'validation':v, 'proposal':p, 'operations':operations,
             'approval': {'attempted':False, 'reason':'validation failed; no validation run'}
             if key == 'correct_phase_action_blocks' else cli_result(denied if blocked else approved)}
        rows.append(row)
        print(json.dumps({'case':key,'coverage':v.get('coverage'),'findings':len(v.get('findings',[])),'error':v.get('error')}),flush=True)
        return p
    probe('extraordinary_action_classified_ordinary',[event(100,'Mara walks through a solid wall')])
    probe('correct_phase_action_blocks',[event(101,'Mara walks through a solid wall',21)],True)
    probe('dead_character_takes_ordinary_action',[event(102,'Mara chats over breakfast')])
    probe('shooting_without_ammunition_or_consumption',[event(103,'Mara fires her empty pistol twice')])
    probe('opposing_assertions_same_objective_proposition',[claim(104,1,10,false,'refutation')])
    probe('different_single_property_values_block',[claim(105,1,10,true)],True)
    probe('knows_objectively_refuted_proposition',[{'kind':'add_belief','client_ref':s.rid(106),'record':{'holder':s.rr(2),'proposition':s.rr(34),'attitude':'knows','certainty':None,'validity':s.interval(10),'basis':{'kind':'author_decision','note':'No acquisition chain'}}}])
    probe('communication_received_before_sent',[{'kind':'record_communication','client_ref':s.rid(107),'record':{'sender':s.rr(1),'intendedRecipients':[s.rr(2)],'actualRecipients':[s.rr(2)],'content':[s.rr(34)],'channel':'ordinary letter','sentAt':s.instant(15),'receivedAt':s.instant(5),'distorted':False}}])
    relation_ops=[]
    for n,target in [(108,2),(109,3)]:
        c=claim(n,1,40,None)
        c['kind']='record_relation'
        c['proposition']['roles']=[{'role':'counterpart','participant':s.rr(target)}]
        relation_ops.append(c)
    probe('single_relation_role_has_two_simultaneous_counterparts',relation_ops)
    probe('appearance_conflicts_with_structured_hair',[{'kind':'create_appearance','client_ref':s.rid(110),'record':{'target':{'kind':'entry','entry':s.rr(1)},'label':'Mara appearance','physical_description':'Mara has white hair.','atmosphere':'','images':[],'links':[],'validity':s.interval(10)}}])
    invented={'kind':'define_proposition','client_ref':s.rid(111),'record':{'subject':s.rr(1),'predicate':s.rr(15),'value':true,'context':s.scope['context'],'quantification':'particular'}}
    effect={'slot':'grant','proposition':s.rr(111),'polarity':'support','scope':s.scope,'validity':s.interval(12),'order':0}
    probe('ordinary_action_grants_unrelated_power',[invented,event(112,'Mara becomes invulnerable while walking',effects=[effect])])
    text='Mara is alive. Iven has black hair.'
    path=s.directory/'contradictory.txt'
    path.write_text(text, encoding='utf-8')
    staged=s.admin('stage-source',NAME,'Contradictory source',path)
    source_proposal=probe('source_only_contradicts_canon',staged['operations'])
    source_receipt=s.publish(source_proposal,'source-for-anchor-commit')
    rows[-1]['receipt']=source_receipt
    source=s.get([staged['operations'][1]['client_ref']])[0]
    anchor={'kind':'add_source_anchor','client_ref':s.rid(113),'record':source_anchor(s.uid,source,text,'Iven has black hair.',s.scope['context'])}
    white=claim(114,2,12,{'kind':'text','text':'white'},basis={'kind':'source_anchor','anchor':s.rr(113),'verified':True})
    probe('verified_quote_does_not_entail_linked_assertion',[anchor,white])
    report['probes']=rows
    report['baseline_mcp_calls']=len(report['mcp'])
    # All baseline observations above precede these additional canonical writes.
    for row in rows:
        if row['id'].startswith('G') and row['id'] != 'G11':
            candidate=s.call('universe_propose', {'action':'revise', 'universe':NAME,
                            'context_id':s.ctx, 'proposal_reference':s.reference(row['proposal']),
                            'operations':row['operations'], 'submission':'submitted',
                            'rationale':row['id']+' persistence proof',
                            'idempotency_key':row['id']+'-persistence'})['result']
            row['receipt']=s.publish(candidate,row['id']+'-commit')
            row['persistence_proposal']=candidate
    for row in rows:
        if row['id'].startswith('C'):
            row['receipt']=None
            row['commit_disposition']='not committed: control rejected'
    s.restart()
    report['restarted_records']=s.get([s.rid(n) for n in (1,100,102,103,104,106,107,108,109,110,111,112,113,114)])
