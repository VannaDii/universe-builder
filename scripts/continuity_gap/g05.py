"""G05 stimuli on real MCP; synthetic author approvals only."""
import json
from pathlib import Path
from mlx_authoring_smoke import require
from pilot_support import NAME


def exercise(s, report):
    report['cases'] = []
    def entity(n):
        return {'kind':'create_entity','client_ref':s.rid(n),'record':{'names':[],'types':[],'worldAssociations':[],'labels':{'en':f'G05 subject {n}'},'metadata':{}}}
    def prop(n):
        return {'kind':'define_property','client_ref':s.rid(n),'record':{'namespace':'g05','key':f'p{n}','labels':{},'value':{'kind':'boolean'},'multiplicity':'single','persistence':'explicit_interval','exclusive':False,'symmetric':False,'transitive':False}}
    def proposition(n,owner=1,predicate=10):
        return {'kind':'define_proposition','client_ref':s.rid(n),'record':{'subject':s.rr(owner),'predicate':s.rr(predicate),'value':{'kind':'boolean','value':True},'context':s.scope['context'],'quantification':'particular'}}
    meanings={20:(1,10),21:(1,10),22:(2,11),23:(2,11),24:(2,10),25:(3,11),26:(7,10),27:(8,10)}
    def assertion(n,prop,polarity,validity=None,scope=None,precision='exact'):
        owner,predicate=meanings[prop]
        return {'kind':'assert_proposition','client_ref':s.rid(n),'proposition':proposition(n,owner,predicate)['record'], 'assertion':{'proposition':s.rr(n),'polarity':polarity,'scope':scope or s.scope,'validity':validity or s.interval(0,10),'persistence':'explicit_interval','precision':precision,'alternatives':[],'basis':{'kind':'author_decision','note':'G05 synthetic evidence'}}}

    def rule(n,policy,owner=1,predicate=10,validity=None):
        return {'kind':'define_rule','client_ref':s.rid(n),'record':{'namespace':'g05','key':f'r{n}','labels':{},'kind':'physical_constraint','commitPolicy':policy,'applicability':{'kind':'universe_wide'},'targetPredicates':[], 'expression':{'kind':'no_opposing_evidence','subject':{'kind':'record','ref':s.rr(owner)},'predicate':f'g05:p{predicate}','context':{'kind':'record','ref':s.scope['context']}},'capabilities':['opposing_evidence.v1'],'executable':True,'validity':validity or {'kind':'unspecified'}}}
    def check(key,ops,kind=None,coverage='complete',blocked=False,publish=False,context=None):
        head=s.open()['frame']['revision']
        p=s.propose(ops,key,context=context); v=s.validate(p,context=context)
        diagnostics=v.get('opposing_evidence',[])
        require(v['coverage']==coverage,f'{key} coverage: {v}')
        if kind:
            require(any(d['kind']==kind for d in diagnostics),f'{key}: missing {kind}: {v}')
        else: require(not diagnostics,f'{key}: false opposing evidence: {v}')
        approval=s.approval(p,v,check=False)
        require((approval.returncode!=0)==blocked,f'{key} approval: {approval.stderr}')
        args=s.commit_args(p,v,key+'-commit')
        receipt=s.call('universe_commit',args,error=blocked) if publish or blocked else {'not_attempted':'diagnostic-only probe'}
        if publish:
            receipt=receipt['result'];s.open()
            require(s.call('universe_commit',args)['result']==receipt,'retry changed receipt')
        after=s.open()['frame']['revision']
        require((after!=head)==publish,f'{key}: head disposition differs')
        row={'key':key,'proposal':p,'validation':v,'approval':{'returncode':approval.returncode,'stdout':approval.stdout,'stderr':approval.stderr},'commit':receipt,'arguments':args,'blocked':blocked,'published':publish,'head_before':head,'head_after':after}
        report['cases'].append(row)
        return row
    seed=s.propose([entity(1),entity(2),prop(10),prop(11),proposition(20),proposition(21),assertion(30,20,'support'),assertion(29,20,'support')],'g05-seed')
    report['seed']=s.publish(seed,'g05-seed-commit')
    # Same proposition and equivalent distinct IDs must report without a rule.
    seed_review=s.admin('review',NAME,seed['proposal_id'],seed['version'],seed['digest'])
    spare=next(c['next'] for c in seed_review['changes'] if c.get('next',{}).get('payload',{}).get('record_kind')=='assertion' and c['next']['payload']['proposition']['record']==s.rid(29))
    replacement={**spare['payload'],'proposition':s.rr(30),'polarity':'refutation'};replacement.pop('record_kind')
    a=check('mechanism-a',[{'kind':'supersede_assertion','record':s.rr(spare['identity']['record_id']),'expected_version':spare['record_version_id'],'replacement':replacement,'rationale':'Explicit same-proposition opposite polarity'}],'definite',publish=True)
    report['mechanism_a_assertion']=spare['identity']['record_id']
    report['historical_revision']=a['head_after']
    check('mechanism-b',[assertion(32,21,'refutation')],'definite',publish=True)
    # Existing opposing evidence is scanned for an unrelated candidate.
    check('unrelated-continuation',[entity(3)],'definite',publish=True)
    for i,policy in enumerate(['record_finding','advisory','report_unsupported','always_block','scope_enforced','block_unless_exception']):
        check('policy-'+policy,[rule(50+i,policy)],'definite',blocked=policy in ['always_block','scope_enforced','block_unless_exception'])
    # Correct the active evidence and install a protected consistency policy.
    bp=report['cases'][1]['proposal']
    b_review=s.admin('review',NAME,bp['proposal_id'],bp['version'],bp['digest'])
    b_assertion=next(c['next']['identity']['record_id'] for c in b_review['changes'] if c.get('next',{}).get('payload',{}).get('record_kind')=='assertion')
    rows=s.get([report['mechanism_a_assertion'],b_assertion])
    retract=[{'kind':'retract_assertion','record':s.rr(r['identity']['record_id']),'expected_version':r['record_version_id'],'rationale':'Correct opposing evidence; preserve history'} for r in rows]
    corrected=check('correction',retract+[rule(60,'always_block')],publish=True)
    require(corrected['validation']['findings'][0]['outcome']=='supported','corrected policy not satisfied')
    check('blocked-under-installed-policy',[assertion(33,21,'refutation')],'definite',blocked=True)
    check('legal-adjacent',[assertion(34,21,'refutation',s.interval(10,20))],publish=True)
    worlds=[{'kind':'create_world','client_ref':s.rid(n),'record':{'selector':label,'aliases':[],'labels':{},'metadata':{}}} for n,label in [(100,'G05 A'),(101,'G05 B')]]
    scoped=lambda n:{'context':s.scope['context'],'applicability':{'kind':'worlds','world_ids':[s.rid(n).replace('rec_','wld_',1)]}}
    check('legal-worlds',worlds+[entity(7),assertion(92,26,'support',scope=scoped(100)),assertion(93,26,'refutation',scope=scoped(101))],publish=True)
    represented={'kind':'record_narrative_reference','client_ref':s.rid(120),'record':'represented_context','payload':{'record_kind':'represented_context','universe':s.uid,'kind':{'kind':'authored','label':'Dream'},'parent':s.scope['context'],'labels':{}}}
    check('context-setup',[represented,entity(8),assertion(94,27,'support')],publish=True)
    objective=s.scope
    s.scope={**s.scope,'context':s.rr(120)}
    dream=s.open(represented=s.rid(120))['context_id']
    check('legal-contexts',[assertion(95,27,'refutation')],publish=True,context=dream)
    s.scope=objective
    # Scoped delivery must disclose neither diagnostics nor hidden identities.
    local=s.admin('enroll')['profile_id']
    s.admin('grant',local,s.uid,'--world',s.rid(100).replace('rec_','wld_',1),'--propose','--edit')
    original=s.agent;s.client.close();s.agent=local;s.connect();s.open()
    report['restricted_validation']=s.call('universe_validate',{'mode':'inline','universe':NAME,'context_id':s.ctx,'operations':[entity(9)],'check_scope':'universe'})
    restricted=report['restricted_validation']['result']
    require(restricted=={'kind':'restricted','execution_coverage':'restricted','submitted_input':{'kind':'restricted'},'assessment':{'kind':'restricted'}},'restricted scan leaked diagnostics')
    s.client.close();s.agent=original;s.connect();s.open()
    check('exception-setup',[assertion(80,25,'support'),rule(70,'block_unless_exception',3,11)],publish=True)
    policy=s.get([s.rid(70)])[0]
    s.client.close();agent=s.agent;s.agent=s.author;s.connect();s.open()
    decision=lambda n:{'kind':'record_issue_decision','client_ref':s.rid(n),'record':{'fingerprints':[],'mode':'accept','scope':s.rid(70),'rationale':'Reviewed synthetic policy departure','principal':s.author.replace('prf_','prn_',1)}}
    def exception(n,start,end,decision_id):
        return {'kind':'add_exception','client_ref':s.rid(n),'record':{'rule':s.rr(70),'ruleVersion':policy['record_version_id'],'scope':s.scope,'validity':s.interval(start,end),'authorizingDecision':s.rr(decision_id),'rationale':'Only the explicitly reviewed interval'}}
    check('standalone-decision',[assertion(81,25,'refutation'),decision(74)],'definite',blocked=True)
    check('partial-exception',[assertion(82,25,'refutation'),decision(75),exception(72,2,8,75)],'definite',blocked=True)
    waived=check('full-exception',[assertion(83,25,'refutation'),decision(71),exception(73,0,10,71)],'definite',publish=True)
    require(any(f['outcome']=='refuted' for f in waived['validation']['findings']),'exception erased original finding')
    wreview=s.admin('review',NAME,waived['proposal']['proposal_id'],waived['proposal']['version'],waived['proposal']['digest'])
    refuted=next(c['next'] for c in wreview['changes'] if c.get('next',{}).get('payload',{}).get('record_kind')=='assertion')
    check('exception-correction',[{'kind':'retract_assertion','record':s.rr(refuted['identity']['record_id']),'expected_version':refuted['record_version_id'],'rationale':'Resume consistent evidence after exception proof'}],publish=True)
    s.client.close();s.agent=agent;s.connect();s.open()
    # Second subject has no blocking rule: unresolved report remains author-review eligible.
    check('unresolved-report',[proposition(22,2,11),proposition(23,2,11),assertion(35,22,'support'),assertion(36,23,'refutation',{'kind':'unknown'})],'unresolved',coverage='partial',publish=True)
    check('unresolved-blocking',[rule(61,'always_block',2,11)],'unresolved',coverage='partial',blocked=True)
    # A different complete key is legal even with exact opposition elsewhere.
    check('legal-different-subject',[proposition(24,2,10),assertion(37,24,'refutation')],'unresolved',coverage='partial',publish=True)
    pending=s.propose([entity(4)],'stale-head');old=s.validate(pending);require(s.approval(pending,old).returncode==0,'pending approval failed')
    continuation=check('corrected-continuation',[entity(5)],'unresolved',coverage='partial',publish=True)
    report['stale_head']=s.call('universe_commit',s.commit_args(pending,old,'stale-head-commit'),error=True)
    report['head_before_restart']=continuation['head_after']
    report['active_before_restart']=s.get([s.rid(30),s.rid(34),s.rid(60)])
    history=s.open(revision=report['historical_revision'])
    report['historical_records']=s.get([report['mechanism_a_assertion'],s.rid(30)],context=history['context_id'])
    # Exact prior validation still readable through public findings.
    report['historical_validation']=s.admin('review',NAME,a['proposal']['proposal_id'],a['proposal']['version'],a['proposal']['digest'])
    s.restart()
    report['head_after_restart']=s.open()['frame']['revision']
    report['active_after_restart']=s.get([s.rid(30),s.rid(34),s.rid(60)])
    require(report['active_before_restart']==report['active_after_restart'],'restart changed records')
    history=s.open(revision=report['historical_revision'])
    report['historical_after_restart']=s.get([report['mechanism_a_assertion'],s.rid(30)],context=history['context_id'])
    require(report['historical_after_restart']==report['historical_records'],'restart changed history')
    check('restart-continuation',[entity(6)],'unresolved',coverage='partial',publish=True)
