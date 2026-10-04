"""Goal 30: real MCP lifecycle, private exact approval, and owned restart proof."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import tempfile
import time
from canonical_families_pilot import FamilySession, authority_counts, private, records
from pilot_support import NAME
from audit_incremental_authoring import canonical_snapshot, audit


def run(output, bin_dir):
    started = time.monotonic()
    output.parent.mkdir(parents=True, exist_ok=True)
    report = {'mcp': [], 'controls': [], 'snapshots': {}}
    with tempfile.TemporaryDirectory(prefix='incremental-authoring-', dir='/tmp') as directory:
        with output.with_suffix('.jsonl').open('w') as wire:
            s = FamilySession(directory, bin_dir, report, wire=wire)
            try:
                s.start()
                package = s.root/'packages'/(s.uid+'.sqlite')
                world = s.rid(60).replace('rec_', 'wld_')
                scope = {'context': s.scope['context'], 'applicability': {'kind': 'worlds', 'world_ids': [world]}}
                def definition(n, name, parent=None):
                    return {'kind': 'introduce_definition', 'client_ref': s.rid(n), 'namespace': 'incremental', 'key': name.lower(), 'name': name, 'parent': s.rid(parent) if parent else None, 'applicability': {'kind': 'universe_wide'}, 'classification_executable': True}
                def instance(n, name, classification=None):
                    return {'kind': 'introduce_instance', 'client_ref': s.rid(n), 'name': {'text': name, 'validity': {'kind': 'unknown'}}, 'classification': s.rid(classification) if classification else None, 'world_associations': [{'world': world, 'role': 'setting', 'validity': {'kind': 'unknown'}, 'qualifiers': {}}]}
                def attribute(n, subject, key, shape, value, mode='instance', validity=None):
                    return {'kind': 'add_named_attribute', 'client_ref': s.rid(n), 'subject': s.rr(subject), 'namespace': 'incremental', 'key': key, 'value_shape': {'kind': shape}, 'subject_types': [s.rid(1)], 'multiplicity': 'single', 'value': value, 'evidence': {'attributeMode': mode, 'scope': scope, 'validity': validity or s.interval(0,30), 'persistence': 'explicit_interval', 'polarity': 'support', 'precision': 'exact', 'basis': {'kind': 'author_decision', 'note': 'Author: '+key}}}
                def snapshot(label, revision=None):
                    frame=s.open(revision)
                    canon = canonical_snapshot(package, frame['frame']['revision'])
                    delivered = records(s, list(canon['records']), context=frame['context_id'])
                    report['snapshots'][label] = {'canonical': canon, 'mcp_records': delivered}
                def rejection(key, ops, check_schema=True):
                    before = authority_counts(s)
                    # Propose failures must not even leave a durable workflow fragment.
                    with sqlite3.connect('file:'+str(package)+'?mode=ro',uri=True) as db:
                        entries = db.execute('SELECT count(*) FROM workflow_entries').fetchone()[0]
                    args = {'action': 'create', 'universe': NAME, 'context_id': s.ctx, 'operations': ops, 'submission': 'submitted', 'rationale': key, 'idempotency_key': key}
                    response = s.call('universe_propose', args, error=True) if check_schema else s.client.call('universe_propose', args, error=True)
                    assert authority_counts(s) == before
                    with sqlite3.connect('file:'+str(package)+'?mode=ro',uri=True) as db:
                        assert db.execute('SELECT count(*) FROM workflow_entries').fetchone()[0] == entries
                    report['controls'].append({'key': key, 'before': before, 'after': authority_counts(s), 'response': response})
                # Minimal Tree, an unclassified named instance, and explicit world.
                ops = [{'kind': 'create_world', 'client_ref': s.rid(60), 'record': {'selector': 'Grove', 'labels': {}, 'metadata': {}}}, definition(1,'Tree'), instance(4,'North tree')]
                p = s.propose(ops, 'minimal')
                frozen = deepcopy(p)
                assert s.propose(ops, 'minimal') == p
                s.restart()
                # Exact request replay uses its original durable context ID.
                original_args = next(r['arguments'] for r in report['mcp'] if r['tool']=='universe_propose' and r['arguments']['idempotency_key']=='minimal')
                assert s.call('universe_propose', original_args)['result'] == frozen
                s.publish(p,'minimal-commit')
                snapshot('minimal')
                old = s.get([s.rid(4)])[0]
                s.publish(s.propose([{'kind':'refine_classification','record':s.rr(4),'expected_version':old['record_version_id'],'entity_type':s.rid(1)}],'classify'),'classify-commit')
                snapshot('tree')
                attrs = [attribute(10,1,'climbable','boolean',{'kind':'boolean','value':True},'shared'), attribute(11,4,'climbing_hazard','text',{'kind':'text','text':'Broken upper branch'}), attribute(12,4,'inspection_note','text',{'kind':'text','text':'Growth inspection pending'},validity={'kind':'unknown'})]
                attrs[2]['evidence']['precision']='unresolved'
                s.publish(s.propose(attrs,'attributes'),'attributes-commit')
                snapshot('attributes')
                old = s.get([s.rid(4)])[0]
                refine = {'kind':'refine_classification','record':s.rr(4),'expected_version':old['record_version_id'],'entity_type':s.rid(2)}
                s.publish(s.propose([definition(2,'Cedar',1), refine],'cedar'),'cedar-commit')
                snapshot('cedar')
                report['state'] = s.state([s.rid(4)], 15)['result']
                s.open()
                current = s.get([s.rid(4)])[0]
                unrelated = {'kind':'refine_classification','record':s.rr(4),'expected_version':current['record_version_id'],'entity_type':s.rid(3)}
                rejection('unrelated-no-partial', [definition(3,'Stone'), unrelated])
                rejection('stale-refinement', [refine])
                mismatch = attribute(20,4,'climbing_hazard','boolean',{'kind':'boolean','value':True})
                rejection('named-shape-conflict', [instance(21,'Must not exist',1),mismatch])
                event_attr = attribute(22,4,'fake_transform','text',{'kind':'text','text':'transformed'})
                event_attr['evidence']['basis'] = {'kind':'event_effect','event':s.rr(23),'slot':'transform'}
                rejection('physical-transformation', [event_attr], check_schema=False)
                duplicate=attribute(24,4,'duplicate','boolean',{'kind':'boolean','value':True})
                duplicate['client_ref']='same'
                other=instance(25,'duplicate',1);other['client_ref']='same'
                rejection('duplicate-friendly-ref', [duplicate,other])
                # A typed value mismatch passes the wire union but fails validation.
                bad = attribute(26,4,'bad_value','integer',{'kind':'text','text':'seven'})
                before = authority_counts(s)
                bp=s.propose([instance(27,'Invalid batch instance',1),bad],'invalid-value')
                bv=s.validate(bp,error=True)
                unrelated_run=report['publications'][-1]['validation']
                approval=s.approval(bp,unrelated_run,check=False)
                assert approval.returncode != 0
                s.call('universe_commit',s.commit_args(bp,unrelated_run,'invalid-value-commit'),error=True)
                assert authority_counts(s)==before
                report['invalid_value']={'validation':bv,'approval_exit':approval.returncode,'before':before,'after':authority_counts(s)}
                # Reusing the same named property creates no extra definition.
                s.open()
                pending=s.propose([instance(5,'South tree',1),attribute(28,5,'climbing_hazard','text',{'kind':'text','text':'Loose bark'})],'reuse')
                validation=s.validate(pending)
                assert validation['coverage']=='complete' and all(f['outcome']=='supported' for f in validation['findings']),validation
                review=s.admin('review',NAME,pending['proposal_id'],pending['version'],pending['digest'])
                approval=json.loads(s.approval(pending,validation).stdout)
                commit_args=s.commit_args(pending,validation,'reuse-commit')
                before=authority_counts(s)
                private(s,{'method':'grant','grant':{'profile_id':s.agent,'universe_id':s.uid,'worlds':None,'propose':True,'edit':False,'protected':False,'limits':{}}})
                denied=s.call('universe_commit',commit_args,error=True)
                assert authority_counts(s)==before
                report['authority']={'denied':denied,'before':before,'after':authority_counts(s)}
                private(s,{'method':'grant','grant':{'profile_id':s.agent,'universe_id':s.uid,'worlds':None,'propose':True,'edit':True,'protected':True,'limits':{}}})
                s.restart()
                before=authority_counts(s)
                canonical_before=canonical_snapshot(package,s.open()['frame']['revision'])
                with sqlite3.connect(package) as db:
                    db.execute("CREATE TRIGGER incremental_failure BEFORE INSERT ON commit_changes BEGIN SELECT RAISE(ABORT,'Goal 30 fault'); END")
                failed=s.call('universe_commit',commit_args,error=True)
                assert authority_counts(s)==before
                canonical_after=canonical_snapshot(package,s.open()['frame']['revision'])
                assert canonical_after==canonical_before
                report['publication_failure']={'response':failed,'before':before,'after':authority_counts(s),'canonical_before':canonical_before,'canonical_after':canonical_after}
                with sqlite3.connect(package) as db:db.execute('DROP TRIGGER incremental_failure')
                s.restart()
                receipt=s.call('universe_commit',commit_args)['result']
                assert s.call('universe_commit',commit_args)['result']==receipt
                report['publications'].append({'key':'reuse-commit','review':review,'author_selection':{'approval':approval},'validation':validation,'receipt':receipt,'commit_arguments':commit_args})
                snapshot('reuse')
                report['second_state']=s.state([s.rid(5)],15)['result']
                s.open()
                s.restart()
                assert s.call('universe_commit',commit_args)['result']==receipt
                snapshot('restart')
                snapshot('historical',report['publications'][0]['receipt']['revision'])
                s.open()
                # A world-only grant cannot introduce a shared type.
                private(s,{'method':'grant','grant':{'profile_id':s.agent,'universe_id':s.uid,'worlds':[world],'propose':True,'edit':True,'protected':True,'limits':{}}})
                rejection('shared-outside-grant',[definition(30,'Forbidden')])
                report['seconds']=time.monotonic()-started
            finally:
                s.close()
                output.write_text(json.dumps(report,indent=2)+'\n')
    audit(output)
    print(f'Actual MCP lifecycle completed in {report["seconds"]:.1f}s')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--bin-dir',type=Path,default=Path('target/debug'));a=p.parse_args();run(a.output,a.bin_dir.resolve())
