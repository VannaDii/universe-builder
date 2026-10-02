"""Independent wire, SQLite, approval and receipt audit. No detector/runner imports."""
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
from audit_continuity_gap import canonical, digest, check, normalize

EXPECTED={
 'mechanism-a':('definite','complete',False,True),
 'mechanism-b':('definite','complete',False,True),
 'unrelated-continuation':('definite','complete',False,True),
 **{'policy-'+p:('definite','complete',p in ('always_block','scope_enforced','block_unless_exception'),False) for p in ('record_finding','advisory','report_unsupported','always_block','scope_enforced','block_unless_exception')},
 'correction':(None,'complete',False,True),
 'blocked-under-installed-policy':('definite','complete',True,False),
 'legal-adjacent':(None,'complete',False,True),
 'legal-worlds':(None,'complete',False,True),
 'context-setup':(None,'complete',False,True),
 'legal-contexts':(None,'complete',False,True),
 'exception-setup':(None,'complete',False,True),
 'standalone-decision':('definite','complete',True,False),
 'partial-exception':('definite','complete',True,False),
 'full-exception':('definite','complete',False,True),
 'exception-correction':(None,'complete',False,True),
 'unresolved-report':('unresolved','partial',False,True),
 'unresolved-blocking':('unresolved','partial',True,False),
 'legal-different-subject':('unresolved','partial',False,True),
 'corrected-continuation':('unresolved','partial',False,True),
 'restart-continuation':('unresolved','partial',False,True),
}

def diagnostic_equivalence(d):
 result={k:normalize(v) for k,v in d.items() if k!='fingerprint'}
 for side in ('support','refutation'):
  result[side]['dependencies']=sorted(result[side]['dependencies'],key=canonical)
 return result

def audit(directory):
 report=json.loads((directory/'report.json').read_text());check(report['status']=='executed','unfinished run')
 check(hashlib.sha256((directory/'package.sqlite').read_bytes()).hexdigest()==report['package_sha256'],'snapshot hash differs')
 calls=[];pending={};sessions=0
 for line in (directory/'mcp-transcript.jsonl').read_text().splitlines():
  entry=json.loads(line);f=entry['frame']
  if entry['direction']=='sent':
   if f.get('method')=='initialize':sessions+=1
   if 'id' in f:check(f['id'] not in pending,'duplicate request');pending[f['id']]=f
  elif 'id' in f:
   q=pending.pop(f['id']);check('error' not in f,'wire error')
   if q['method']=='tools/call':
    wire=f['result'];v=wire['structuredContent'];check(json.loads(''.join(c['text'] for c in wire['content'] if c['type']=='text'))==v,'wire representations differ')
    calls.append((q['params']['name'],q['params']['arguments'],v))
 check(not pending,'unanswered request')
 check(len(calls)==len(report['mcp']),'report omits calls')
 for c,r in zip(calls,report['mcp']):check(c==(r['tool'],r['arguments'],r['result']),'report differs from wire')
 with closing(sqlite3.connect(f'file:{directory / "package.sqlite"}?mode=ro',uri=True)) as db:
  db.row_factory=sqlite3.Row
  workflow={}
  for r in db.execute('SELECT * FROM workflow_entries'):
   v=json.loads(r['payload']);check(digest(v)==r['digest'],'workflow hash differs');workflow[r['key']]=v
  versions={r['id']:json.loads(r['payload']) for r in db.execute('SELECT id,payload FROM record_versions')}
  membership={r['record_id']:r['version_id'] for r in db.execute('SELECT record_id,version_id FROM head_membership')}
  def snapshot(rev):
   path=[]
   while rev:
    path.append(rev);rev=db.execute('SELECT parent_id FROM commits WHERE id=?',(rev,)).fetchone()[0]
   result={}
   for rev in reversed(path):
    for r in db.execute('SELECT record_id,version_id FROM commit_changes WHERE revision_id=?',(rev,)):
     if r['version_id']:result[r['record_id']]=versions[r['version_id']]
     else:result.pop(r['record_id'],None)
   return result
  def persisted(p,v):
   stored=workflow[f"proposal:{p['proposal_id']}:{p['version']:020}"]
   check(stored['proposal']==p,'proposal binding differs')
   checked=workflow['validation:'+v['run_id']]
   check(checked['validation']==v and checked['proposal_digest']==p['digest'],'validation binding differs')
   candidate=snapshot(p['base_frame']['revision'])
   for c in stored['changes']:
    if c['next']:candidate[c['record_id']]=c['next']
    else:candidate.pop(c['record_id'],None)
   by_version={r['record_version_id']:r for r in candidate.values()}
   for d in v.get('opposing_evidence',[]):
    chains=[]
    for side,polarity in [('support','support'),('refutation','refutation')]:
     chain=d[side];a=by_version[chain['assertion']]['payload'];p0=by_version[chain['proposition']]['payload']
     check(a['polarity']==polarity and a['proposition']['record']==by_version[chain['proposition']]['identity']['record_id'],'chain polarity/target differs')
     check(all(x['version'] in by_version and by_version[x['version']]['identity']['record_id']==x['record'] for x in chain['dependencies']),'chain dependency absent')
     check(d['context']==p0['context'],'diagnostic context differs');chains.append((a,p0))
    a,b=chains;check(a[1]==b[1],'propositions are not equivalent in these stimuli')
    if d['kind']=='definite':
     check(a[0]['precision']==b[0]['precision']=='exact','inexact definite conflict')
     check(a[0]['scope']==b[0]['scope'],'unexpected scope merge')
     def bounds(x):
      v=x['validity'];check(v['kind']=='calendar_interval','noninterval definite fixture')
      return v['calendar'],int(v['start']['value']),int(v['end']['value'])
     ca,sa,ea=bounds(a[0]);cb,sb,eb=bounds(b[0]);check(ca==cb and max(sa,sb)<min(ea,eb),'no independent half-open overlap')
     i=d['intersection'];check(i['kind']=='exact' and i['validity']['start']['value']==str(max(sa,sb)) and i['validity']['end']['value']==str(min(ea,eb)),'intersection differs')
    else:check(d['coverage']=='partial' and d['unresolved_reasons'],'unresolved reported as clean')
   return stored,checked
  def receipt(p,v,args,r):
   stored,checked=persisted(p,v);check(checked['admissible'],'inadmissible publication')
   approvals=[a for k,a in workflow.items() if k.startswith('approval:') and k.endswith(':'+p['digest']+':'+v['run_id'])]
   check(len(approvals)==1 and approvals[0]['validation_digest']==digest(checked) and approvals[0]['evaluator']==v['evaluator_version'],'exact approval missing')
   op=workflow['operation:'+r['operation_id']];check(op['input']['changes']==stored['changes'],'commit input differs')
   rows=db.execute('SELECT * FROM operation_receipts WHERE idempotency_key=?',(args['idempotency_key'],)).fetchall()
   check(len(rows)==1 and rows[0]['revision_id']==r['revision'] and rows[0]['payload_digest']==digest(op['input']),'kernel receipt mismatch')
   commit=db.execute('SELECT * FROM commits WHERE id=?',(r['revision'],)).fetchone()
   check(commit['parent_id']==args['expected_base_revision'] and commit['decision']==p['digest'],'commit binding differs')
   changes={c['record_id']:c for c in db.execute('SELECT * FROM commit_changes WHERE revision_id=?',(r['revision'],))}
   check(set(changes)=={c['record_id'] for c in stored['changes']},'commit assignments differ')
   for c in stored['changes']:
    check(changes[c['record_id']]['prior_version']==c['expected'],'prior version differs')
    if c['next']:check(versions[changes[c['record_id']]['version_id']]==c['next'],'committed payload differs')
    else:check(changes[c['record_id']]['version_id'] is None,'retraction did not remove active membership')
  if 'cases' in report:
   check({r['key'] for r in report['cases']}==set(EXPECTED),'case set differs')
   for r in report['cases']:
    kind,coverage,blocked,published=EXPECTED[r['key']];p,v=r['proposal'],r['validation'];stored,checked=persisted(p,v)
    check(v['coverage']==coverage and r['blocked']==blocked and r['published']==published,'policy oracle differs')
    check(checked['admissible']==(not blocked),'admission differs')
    ds=v.get('opposing_evidence',[])
    check(any(d['kind']==kind for d in ds) if kind else not ds,'diagnostic oracle differs')
    if blocked:
     check(r['head_before']==r['head_after'] and r['approval']['returncode']!=0,'blocked head or approval differs')
     check(db.execute('SELECT count(*) FROM operation_receipts WHERE idempotency_key=?',(r['arguments']['idempotency_key'],)).fetchone()[0]==0,'blocked receipt exists')
    if published:receipt(p,v,r['arguments'],r['commit']);check(r['head_after']==r['commit']['revision'],'published head differs')
   a=report['cases'][0]['validation']['opposing_evidence'][0]
   check(a['support']['proposition']==a['refutation']['proposition'],'mechanism A not same ID')
   b=report['cases'][1]['validation']['opposing_evidence']
   check(any(d['support']['proposition']!=d['refutation']['proposition'] for d in b),'mechanism B not distinct IDs')
   check(report['restricted_validation']['result']['coverage']=='restricted' and not report['restricted_validation']['result'].get('opposing_evidence') and not report['restricted_validation']['result']['findings'],'restricted diagnostics leaked')
   check(report['head_before_restart']==report['head_after_restart'],'restart changed head')
   for r in report['active_after_restart']:check(versions[membership[r['identity']['record_id']]]==r,'restart active record differs')
   history=snapshot(report['historical_revision'])
   for r in report['historical_after_restart']:check(history[r['identity']['record_id']]==r,'history differs')
   check(report['mechanism_a_assertion'] not in membership,'correction left refutation active')
   check(any(c[0]=='universe_commit' and c[2]==report['stale_head'] for c in calls),'stale head failure absent from wire')
  else:
   check(report['head_before']==report['head_after_denial'],'upgrade denial changed head')
   check(report['old_validation']['evaluator_version']!=report['fresh_validation']['evaluator_version'],'evaluator did not change')
   check(report['old_status']==report['historical_status'],'historical operation differs')
   check(report['stale_approval']['returncode']!=0,'stale approval accepted')
   check(db.execute("SELECT count(*) FROM operation_receipts WHERE idempotency_key='stale-evaluator'").fetchone()[0]==0,'stale receipt exists')
   receipt(report['old_proposal'],report['fresh_validation'],report['fresh_arguments'],report['fresh_commit'])
  head=db.execute('SELECT head_commit FROM continuities').fetchone()[0]
  check(snapshot(head)=={k:versions[v] for k,v in membership.items()},'head membership differs from history')
  equivalence={r['key']:{'operations':normalize(r['proposal']['operations']),'coverage':r['validation']['coverage'],'diagnostics':sorted([diagnostic_equivalence(d) for d in r['validation'].get('opposing_evidence',[])],key=canonical),'rule_outcomes':[f['outcome'] for f in r['validation']['findings']],'blocked':r['blocked'],'published':r['published']} for r in report.get('cases',[])}
  result={'equivalence':equivalence,'status':'passed','cases':len(report.get('cases',[])),'mcp_calls':len(calls),'sessions':sessions,'kernel_receipts':db.execute('SELECT count(*) FROM operation_receipts').fetchone()[0],'limits':'Independent program audit, not external human review or prose/story qualification.'}
 (directory/'audit.json').write_text(json.dumps(result,indent=2)+'\n');return result

if __name__=='__main__':print(json.dumps(audit(Path(sys.argv[1]).resolve())))
