"""Goal 40 actual MCP knowledge acquisition, correction, history and restart proof."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import tempfile
import time
from canonical_families_pilot import FamilySession, authority_counts, restart
from continuity_gap_pilot import build_identity, save, sha


def run(output, bin_dir):
    output.mkdir(parents=True, exist_ok=False)
    began=time.monotonic();report={'status':'running','cases':[],'build':build_identity(bin_dir,{})}
    with tempfile.TemporaryDirectory(prefix='ub-g40-',dir='/tmp') as root:
        with (output/'mcp-transcript.jsonl').open('w') as wire:
            s=FamilySession(root,bin_dir,report,wire=wire)
            try:
                s.start(); report['installation']=s.u
                context=s.rr(s.u['context_id'])
                def instance(n,label):
                    return {'kind':'introduce_instance','client_ref':s.rid(n),'name':{'text':label,'validity':s.interval(0)},'classification':None,'world_associations':[]}
                def rule(n,mode=None):
                    record={'namespace':'g40','key':str(n),'labels':{},'kind':'physical_constraint','commitPolicy':'always_block','applicability':{'kind':'universe_wide'},'targetPredicates':[],'expression':{'kind':'lit','value':True},'executable':True,'validity':{'kind':'unspecified'}}
                    if mode is None:record.update(capabilities=['communications.chronology.v1'],channelChronology={'channel':'letter','forwardOnly':True,'minimumDelay':'2','maximumDelay':'10'})
                    else:record.update(capabilities=['knowledge.acquisition.v1'],knowledgePolicy={'context':context,'mode':mode})
                    return {'kind':'define_rule','client_ref':s.rid(n),'record':record}
                def proposition(subject=1):
                    return {'predicate':s.rr(10),'subject':s.rr(subject),'value':{'kind':'boolean','value':True},'quantification':'particular','context':context}
                def assertion(n,polarity='support',subject=1):
                    return {'kind':'assert_proposition','client_ref':s.rid(n),'proposition':proposition(subject),'assertion':{'attributeMode':'instance','proposition':s.rr(n),'polarity':polarity,'scope':{'applicability':{'kind':'universe_wide'},'context':context},'validity':s.interval(0,20),'persistence':'explicit_interval','precision':'exact','basis':{'kind':'author_decision','note':'Explicit factual evidence'}}}
                def message(n=30,received=7,actual=(2,),content=20,distorted=False):
                    return {'kind':'record_communication','client_ref':s.rid(n),'record':{'sender':s.rr(1),'intendedRecipients':[s.rr(2)],'actualRecipients':[s.rr(x) for x in actual],'content':[s.rr(content)],'channel':'letter','sentAt':s.instant(5),'receivedAt':s.instant(received),'distorted':distorted}}
                def attitude(n,start=8,acquired=7,holder=2,prop=20,msg=30,interpret=True,direct=False,kind='knows'):
                    return {'kind':'add_belief','client_ref':s.rid(n),'record':{'holder':s.rr(holder),'proposition':s.rr(prop),'attitude':kind,'certainty':None,'validity':s.interval(start),'basis':{'kind':'author_decision','note':'Authored interpretation, not inferred understanding'},'acquisition':{'truthContext':context,'time':s.instant(acquired),'basis':{'kind':'author_established'} if direct else {'kind':'communication_receipt','communication':s.rr(msg),'interpretation':s.rr(prop) if interpret else None}}}}
                def tomb(n):
                    return {'kind':'tombstone_record','record':s.rr(n),'expected_version':s.get([s.rid(n)])[0]['record_version_id'],'rationale':'Exact authored correction'}
                def evaluate(label,ops,expected,publish=False):
                    s.open();row={'id':label,'expected':expected,'operations':deepcopy(ops),'before':authority_counts(s),'head_before':s.open()['frame']['revision']}
                    p=s.propose(ops,'g40-'+label);v=s.validate(p);row.update(proposal=p,validation=v)
                    observed='unresolved' if v['coverage']=='partial' else ('rejected' if any(f['outcome'] in ('refuted','conflicting') for f in v['findings']) else 'legal')
                    assert observed==expected,(label,v)
                    if publish:row['receipt']=s.publish(p,'g40-'+label+'-commit');row['admitted']=True
                    else:
                        row['approval_returncode']=s.approval(p,v,check=False).returncode
                        row['commit_response']=s.call('universe_commit',s.commit_args(p,v,'g40-'+label+'-commit'),error=True)
                        assert row['approval_returncode']!=0
                        row['admitted']=False
                    row['after']=authority_counts(s);row['head_after']=s.open()['frame']['revision']
                    if not publish:assert row['before']==row['after'] and row['head_before']==row['head_after']
                    report['cases'].append(row);return row
                seed=[{'kind':'define_calendar','client_ref':s.rid(50),'record':{'namespace':'g40','key':'other','labels':{},'unitStructure':{'tick':'days'},'conversions':[]}},instance(1,'Mara'),instance(2,'Iven'),instance(3,'Nera'),{'kind':'define_property','client_ref':s.rid(10),'record':{'namespace':'g40','key':'open','labels':{},'value':{'kind':'boolean'},'multiplicity':'single','persistence':'explicit_interval','exclusive':False,'symmetric':False,'transitive':False}},assertion(20),rule(11),rule(12,'justified'),message()]
                s.publish(s.propose(seed,'g40-seed'),'g40-seed-commit')
                valid=evaluate('valid-interpreted-receipt',[attitude(100)],'legal',True)
                report['original_revision']=valid['head_after'];report['original_reads']=s.get([s.rid(100),s.rid(30),s.rid(20)])
                evaluate('knowledge-before-receipt',[attitude(101,start=6,acquired=6)],'rejected')
                evaluate('validity-before-acquisition',[attitude(102,start=6)],'rejected')
                evaluate('wrong-actual-recipient',[attitude(103,holder=3)],'rejected')
                evaluate('receipt-without-interpretation',[attitude(104,interpret=False)],'unresolved')
                evaluate('wrong-interpreted-content',[{'kind':'define_proposition','client_ref':s.rid(21),'record':proposition(3)},attitude(105,prop=21)],'rejected')
                evaluate('distorted-content-unresolved',[message(31,distorted=True),attitude(106,msg=31)],'unresolved')
                evaluate('unknown-truth',[{'kind':'define_proposition','client_ref':s.rid(22),'record':proposition(3)},message(32,content=22),attitude(107,prop=22,msg=32)],'unresolved')
                evaluate('refuted-truth',[assertion(23,'refutation',3),message(33,content=23),attitude(108,prop=23,msg=33)],'rejected')
                evaluate('conflicting-truth',[assertion(24,'refutation'),attitude(109)],'rejected')
                evaluate('false-belief-preserved',[assertion(25,'refutation',3),attitude(110,prop=25,kind='believes')],'legal',True)
                evaluate('author-basis-under-justified-policy',[attitude(111,direct=True)],'rejected')
                unknown=attitude(112);unknown['record']['acquisition']['time']={'kind':'unspecified'}
                evaluate('unknown-acquisition-clock',[unknown],'unresolved')
                cross=attitude(119);cross['record']['acquisition']['time']['calendar']=s.rid(50).replace('rec_','cal_')
                evaluate('unmapped-acquisition-clock',[cross],'unresolved')
                timeless=attitude(120);timeless['record']['validity']={'kind':'unspecified'}
                evaluate('unspecified-knowledge-onset',[timeless],'unresolved')
                legacy=attitude(113);legacy['record'].pop('acquisition')
                evaluate('missing-acquisition-under-policy',[legacy],'unresolved')
                # Find assertion identity through SQL only as a lookup input; read body through MCP.
                dbpath=s.root/'packages'/(s.uid+'.sqlite')
                with sqlite3.connect(dbpath) as db:
                    ids=[r[0] for r in db.execute("SELECT h.record_id FROM head_membership h JOIN record_versions v ON v.id=h.version_id WHERE v.kind='assertion'")]
                truth=next(r for rid in ids for r in s.get([rid]) if r['payload']['proposition']==s.rr(20))
                replacement=deepcopy(truth['payload']);replacement.pop('record_kind');replacement['polarity']='refutation'
                correction={'kind':'supersede_assertion','record':s.rr(truth['identity']['record_id']),'expected_version':truth['record_version_id'],'replacement':replacement,'rationale':'Earlier truth was authored incorrectly'}
                evaluate('truth-correction-invalidates-dependent',[correction],'rejected')
                # Ending current truth must retain supported truth at acquisition.
                end={'kind':'end_assertion_at','record':s.rr(truth['identity']['record_id']),'expected_version':truth['record_version_id'],'at':s.instant(10),'basis':{'kind':'author_decision','note':'Door later closes'}}
                ended=evaluate('later-truth-end-retains-historical-knowledge',[end],'legal',True)
                report['truth_end_revision']=ended['head_after']
                evaluate('truth-ended-before-acquisition',[attitude(114,start=12,acquired=11)],'unresolved')
                # Correction to the beginning removes support at acquisition and is rejected.
                current=s.get([truth['identity']['record_id']])[0];repl=deepcopy(current['payload']);repl.pop('record_kind');repl['validity']=s.interval(8,10)
                early={'kind':'supersede_assertion','record':s.rr(truth['identity']['record_id']),'expected_version':current['record_version_id'],'replacement':repl,'rationale':'Correct truth onset'}
                evaluate('truth-onset-correction-invalidates-dependent',[early],'unresolved')
                # Correct the truth together with the dependent claim; preserve it as belief.
                repaired=evaluate('atomic-truth-and-dependent-correction',[early,tomb(100),attitude(115,kind='believes')],'legal',True)
                report['corrected_revision']=repaired['head_after']
                evaluate('historical-adoption-rechecks-acquisition',[{'kind':'adopt_record_version','source':report['original_reads'][0],'expected_version':None}],'unresolved')
                report['historical_before_restart']=s.get([s.rid(100),s.rid(30),s.rid(20)],s.open(report['original_revision'])['context_id'])
                assert report['historical_before_restart']==report['original_reads']
                s.open()
                # Direct knowledge has its own explicit policy; no acquisition chain/truth certificate.
                evaluate('author-policy-and-established-knowledge',[tomb(12),rule(13,'author_established'),attitude(116,direct=True)],'legal',True)
                evaluate('receipt-basis-under-author-policy',[attitude(117)],'rejected')
                report['head_before_restart']=s.open()['frame']['revision'];report['current_before_restart']=s.get([s.rid(115),s.rid(116),truth['identity']['record_id']])
                restart(s,report)
                report['head_after_restart']=s.open()['frame']['revision'];assert report['head_before_restart']==report['head_after_restart']
                report['current_after_restart']=s.get([s.rid(115),s.rid(116),truth['identity']['record_id']]);assert report['current_after_restart']==report['current_before_restart']
                report['historical_after_restart']=s.get([s.rid(100),s.rid(30),s.rid(20)],s.open(report['original_revision'])['context_id']);assert report['historical_after_restart']==report['original_reads']
                evaluate('restart-policy-still-enforced',[attitude(118)],'rejected')
                evaluate('restart-corrected-truth-still-unresolved',[tomb(13),rule(14,'justified'),tomb(116),attitude(121)],'unresolved')
                with sqlite3.connect(dbpath) as source,sqlite3.connect(output/'package.sqlite') as target:source.backup(target)
                report['package_sha256']=sha(output/'package.sqlite');report['status']='executed'
            finally:
                s.close();report['cleanup']={'engine_stopped':not (s.root/'engine.sock').exists()}
                save(output/'report.json',report)
    report['cleanup']['temporary_install_removed']=not Path(root).exists();report['seconds']=time.monotonic()-began
    save(output/'report.json',report);print(json.dumps({'status':report['status'],'cases':len(report['cases']),'seconds':report['seconds']}))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--bin-dir',type=Path,default=Path('target/debug'))
    a=p.parse_args();run(a.output.resolve(),a.bin_dir.resolve())
