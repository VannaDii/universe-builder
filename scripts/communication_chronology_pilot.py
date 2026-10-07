"""Actual stdio MCP chronology admission/correction/history/restart proof.

Author review/approval uses the authenticated author CLI. No live author data.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import tempfile
import time
from canonical_families_pilot import FamilySession, authority_counts, restart
from continuity_gap_pilot import build_identity, save, sha
from pilot_support import NAME


def run(output, bin_dir):
    output.mkdir(parents=True, exist_ok=False)
    began = time.monotonic()
    report = {'status': 'running', 'cases': [], 'build': build_identity(bin_dir,{})}
    with tempfile.TemporaryDirectory(prefix='ub-g39-', dir='/tmp') as root:
        with (output/'mcp-transcript.jsonl').open('w') as wire:
            s = FamilySession(root,bin_dir,report,wire=wire)
            try:
                s.start()
                report['installation'] = s.u
                def instance(n,label):
                    return {'kind':'introduce_instance','client_ref':s.rid(n),'name':{'text':label,'validity':s.interval(0)},'classification':None,'world_associations':[]}
                def contract(channel,forward=True,minimum=None,maximum=None):
                    c={'channel':channel,'forwardOnly':forward}
                    if minimum is not None:c['minimumDelay']=str(minimum)
                    if maximum is not None:c['maximumDelay']=str(maximum)
                    return c
                def rule(n,c):
                    return {'kind':'define_rule','client_ref':s.rid(n),'record':{
                        'namespace':'g39','key':str(n),'labels':{},'kind':'physical_constraint',
                        'commitPolicy':'always_block','applicability':{'kind':'universe_wide'},
                        'targetPredicates':[],'expression':{'kind':'lit','value':True},
                        'capabilities':['communications.chronology.v1'],'executable':True,
                        'validity':{'kind':'unspecified'},'channelChronology':c}}
                def communication(n,sent,received,channel='letter',actual=(2,),intended=(2,)):
                    return {'kind':'record_communication','client_ref':s.rid(n),'record':{
                        'sender':s.rr(1),'intendedRecipients':[s.rr(x) for x in intended],
                        'actualRecipients':[s.rr(x) for x in actual],'content':[],
                        'channel':channel,'sentAt':s.instant(sent),
                        'receivedAt':None if received is None else s.instant(received),'distorted':False}}
                def tomb(n):
                    return {'kind':'tombstone_record','record':s.rr(n),
                        'expected_version':s.get([s.rid(n)])[0]['record_version_id'],
                        'rationale':'Authored chronology correction'}
                def evaluate(case_id,operations,expected,publish=False):
                    s.open()
                    row={'id':case_id,'expected':expected,'operations':deepcopy(operations),
                         'before':authority_counts(s),'head_before':s.open()['frame']['revision']}
                    p=s.propose(operations,'g39-'+case_id);v=s.validate(p)
                    row.update(proposal=p,validation=v)
                    observed='unresolved' if v['coverage']=='partial' else ('rejected' if any(f['outcome']=='refuted' for f in v['findings']) else 'legal')
                    assert observed==expected,(case_id,v)
                    if publish:
                        row['receipt']=s.publish(p,'g39-'+case_id+'-commit');row['admitted']=True
                    else:
                        approval=s.approval(p,v,check=False);row['approval_returncode']=approval.returncode
                        row['commit_response']=s.call('universe_commit',s.commit_args(p,v,'g39-'+case_id+'-commit'),error=True)
                        assert approval.returncode != 0,(case_id,'approval unexpectedly allowed')
                        row['admitted']=False
                    row['after']=authority_counts(s);row['head_after']=s.open()['frame']['revision']
                    if not publish:
                        assert row['before']==row['after'] and row['head_before']==row['head_after']
                    report['cases'].append(row)
                    return row
                seed=s.propose([instance(1,'Mara'),instance(2,'Iven'),instance(3,'Nera'),
                    {'kind':'define_calendar','client_ref':s.rid(50),'record':{'namespace':'g39','key':'other','labels':{},'unitStructure':{'tick':'days'},'conversions':[]}}], 'g39-seed')
                s.publish(seed,'g39-seed-commit')
                # This reversal is admitted only while chronology is not activated.
                legacy=evaluate('legacy-opt-out',[communication(90,15,5)],'legal',True)
                report['legacy_revision']=legacy['head_after']
                report['historical_before_activation']=s.get([s.rid(90)])
                letter=contract('letter',True,2,10)
                evaluate('activation-rechecks-legacy',[rule(9,letter)],'rejected')
                corrected=evaluate('activate-and-correct',[rule(10,letter),tomb(90),communication(91,5,15)],'legal',True)
                report['corrected_revision']=corrected['head_after']
                s.publish(s.propose([rule(11,contract('reverse',False,-10,-2)),rule(12,contract('instant',True,0,0))],'g39-more-channels'),'g39-more-channels-commit')
                evaluate('forward-min-boundary',[communication(100,5,7)],'legal',True)
                evaluate('forward-max-boundary',[communication(101,5,15)],'legal',True)
                evaluate('reversed-forward',[communication(102,15,5)],'rejected')
                evaluate('too-fast',[communication(103,5,6)],'rejected')
                evaluate('too-slow',[communication(104,5,16)],'rejected')
                evaluate('reverse-permitted',[communication(105,15,5,'reverse')],'legal',True)
                evaluate('reverse-too-far',[communication(106,16,5,'reverse')],'rejected')
                evaluate('reverse-too-near',[communication(107,6,5,'reverse')],'rejected')
                evaluate('simultaneous',[communication(108,5,5,'instant')],'legal',True)
                evaluate('different-recipient',[communication(109,5,7,actual=(3,))],'legal',True)
                evaluate('sender-is-recipient',[communication(110,5,7,actual=(1,))],'legal',True)
                evaluate('multiple-actual',[communication(111,5,7,actual=(2,3))],'legal',True)
                evaluate('unreceived',[communication(112,5,None,actual=())],'unresolved')
                evaluate('intended-only',[communication(113,15,5,actual=())],'unresolved')
                evaluate('missing-channel-rule',[communication(114,5,7,'unruled')],'unresolved')
                evaluate('missing-channel-identity',[communication(115,5,7,None)],'unresolved')
                cross=communication(116,5,7);cross['record']['receivedAt']['calendar']=s.rid(50).replace('rec_','cal_')
                evaluate('unmapped-clocks',[cross],'unresolved')
                unknown=communication(117,5,7);unknown['record']['sentAt']={'kind':'unspecified'}
                evaluate('unknown-send',[unknown],'unresolved')
                overflow=communication(118,-(1<<127),(1<<127)-1)
                evaluate('delay-overflow',[overflow],'unresolved')
                # A second rule for a channel is conjunctive, never chosen by order.
                evaluate('conjunctive-rules',[rule(13,contract('letter',True,3,10))],'rejected')
                report['head_before_restart']=s.open()['frame']['revision']
                report['historical_before_restart']=s.get([s.rid(90)],s.open(report['legacy_revision'])['context_id'])
                restart(s,report)
                report['head_after_restart']=s.open()['frame']['revision']
                assert report['head_after_restart']==report['head_before_restart']
                report['historical_after_restart']=s.get([s.rid(90)],s.open(report['legacy_revision'])['context_id'])
                assert report['historical_before_restart']==report['historical_after_restart']==report['historical_before_activation']
                s.open();report['current_after_restart']=s.get([s.rid(91),s.rid(10),s.rid(11),s.rid(109)])
                evaluate('restart-reversal-rejected',[communication(119,15,5)],'rejected')
                # Invalid contract authoring is refused during actual validation.
                report['invalid_contracts']=[]
                for index,(label,c) in enumerate([('inverted',contract('bad',True,10,2)),('negative-forward-maximum',contract('bad',True,None,-1)),('not-integer',contract('bad',True,'one',None))]):
                    p=s.propose([rule(30+index,c)],'g39-invalid-'+label)
                    response=s.validate(p,error=True)
                    assert response.get('code')=='INVALID_ARGUMENT' and response.get('field')=='channelChronology',response
                    report['invalid_contracts'].append({'id':label,'proposal':p,'response':response})
                package=s.root/'packages'/(s.uid+'.sqlite')
                with sqlite3.connect(package) as source,sqlite3.connect(output/'package.sqlite') as target:source.backup(target)
                report['package_sha256']=sha(output/'package.sqlite')
                report['status']='executed'
            finally:
                s.close();report['cleanup']={'engine_stopped':not (s.root/'engine.sock').exists()}
    report['cleanup']['temporary_install_removed']=not Path(root).exists()
    report['seconds']=time.monotonic()-began
    save(output/'report.json',report)
    print(json.dumps({'status':report['status'],'cases':len(report['cases']),'seconds':report['seconds']}))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--bin-dir',type=Path,default=Path('target/debug'))
    a=p.parse_args();run(a.output.resolve(),a.bin_dir.resolve())
