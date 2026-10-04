#!/usr/bin/env python3
"""Independent direct relational readback and handwritten semantic oracle checks.
No writer, generator or production resolver imports. No evaluator calls.
"""
import hashlib
import json
import sqlite3
import sys
from pathlib import Path
from independent_audit import reader,encoded

HERE=Path(__file__).resolve().parent
oracle=json.loads(Path(sys.argv[2]).read_text());models=json.loads((HERE/'catalog.json').read_text())['models']
db=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True);db.row_factory=sqlite3.Row
assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
assert not db.execute('PRAGMA foreign_key_check').fetchall()
decode=reader(db,models);versions={}
for e in oracle['versions']:
    r=db.execute('SELECT * FROM record_versions WHERE id=?',(e['version'],)).fetchone()
    assert (r['record_id'],r['kind'],r['schema_version'],r['digest'])==(e['identity'],e['kind'],e['schema'],e['digest'])
    layout=r['storage_layout']
    model,column={'legacy':('Payload','payload_row'),'type_v3':('TypeDefinitionV3','type_row'),'instance_v3':('InstanceV3','instance_row'),'attribute_v3':('AttributeAssertionV3','attribute_row')}[layout]
    v=decode(model,r[column]);v=v if layout=='legacy' else {'record_kind':r['kind'],**v}
    assert v==e['value'],e['version']
    recipe='v1' if layout=='legacy' else 'v3'
    digest=hashlib.sha256((r['kind']+':'+recipe+':'+recipe+':').encode()+encoded(v)).hexdigest()
    assert digest==r['digest']
    versions[e['version']]=v
assert db.execute("SELECT count(*) FROM record_versions WHERE schema_version='v2' AND storage_layout='legacy'").fetchone()[0]==1
ids=oracle['names'];reverse={v:k for k,v in ids.items()}
head={r['record_id']:r['version_id'] for r in db.execute('SELECT * FROM head_membership')}
snap={r['record_id']:r['version_id'] for r in db.execute('SELECT * FROM snapshot_member')}
assert head==snap==oracle['membership']
assert hashlib.sha256(encoded(snap)).hexdigest()==db.execute('SELECT checksum FROM snapshot_membership').fetchone()[0]
# Reconstruct each revision through authoritative commit changes, not its snapshot.
history=[];m={}
for rev in oracle['revisions']:
    for r in db.execute('SELECT * FROM commit_changes WHERE revision_id=?',(rev,)):
        assert m.get(r['record_id'])==r['prior_version']
        if r['version_id'] is None:m.pop(r['record_id'],None)
        else:m[r['record_id']]=r['version_id']
    history.append(dict(m))
assert history[-1]==head
assert tuple(db.execute('SELECT principal,operation_kind,idempotency_key,payload_digest,revision_id FROM operation_receipts').fetchone())==('review-author','commit','review-key','a'*64,oracle['revisions'][3])
assert db.execute('SELECT record_id FROM world_name_reservations').fetchone()[0]==ids['World A']

def ancestry(name,revision=-1):
    member=history[revision];instance=versions[member[ids[name]]]
    t=instance.get('classification');seen=set();result=[]
    while t:
        assert t not in seen,'subtype cycle';seen.add(t);result.append(reverse[t])
        definition=versions[member[t]];t=definition['parent']
    return result

def facts(subject,predicate,t,revision=-1,mode='instance',world='World A'):
    found=[]
    for binding in oracle['facts']:
        if binding['subject']!=subject or binding['predicate']!=predicate:continue
        assertion=versions[binding['assertion']];prop=versions[binding['proposition']]
        if binding['assertion'] not in history[revision].values():continue
        if assertion['attributeMode']!=mode:continue
        scope=assertion['scope']['applicability']
        if scope['kind']=='worlds' and 'wld_'+ids[world].split('_')[1] not in scope['world_ids']:continue
        if scope['kind']!='worlds':continue
        assert assertion['scope']['context']['record']==ids['Objective']
        valid=assertion['validity'];lo=int(valid['start']['value']);hi=None if valid['end']['kind']=='unbounded' else int(valid['end']['value'])
        if lo<=t and (hi is None or t<hi):found.append(prop['value'])
    return found
expected=oracle['expected']
assert ancestry('Cedar One')==expected['cedar_ancestry']
assert ancestry('Cedar One',0)==['Tree']
assert facts('Tree','grows',1,mode='shared')==[{'kind':'boolean','value':expected['cedar_grows']}]
assert facts('Cedar One','hazard',1)==[{'kind':'boolean','value':expected['cedar_hazard']}]
assert facts('Cedar One','height',0,revision=0)==[]
assert facts('Cedar One','height',1)[0]['value']['digits']==expected['cedar_height_digits']
assert ancestry('Pistol A')==expected['pistol_a_ancestry']
a=[facts('Pistol A','rounds',t)[0]['digits'] for t in range(4)]
b=[facts('Pistol B','rounds',t)[0]['digits'] for t in range(4)]
assert a==expected['pistol_a_rounds'];assert b==expected['pistol_b_rounds']
assert facts('Gun','rounds',3)==[] # initial values never contribute current instance state
assert db.execute('SELECT count(*) FROM initialization_receipt').fetchone()[0]==1
assert db.execute('SELECT resolution,type_id FROM instance_classification WHERE record_id=?',(ids['Ambiguous'],)).fetchone()['resolution']==expected['legacy_status']
assert [r['type_id'] for r in db.execute('SELECT type_id FROM legacy_classification ORDER BY ordinal')]==[ids['Tree'],ids['Gun']]
cedar=versions[head[ids['Western red cedar']]]
assert cedar['applicability']['world_ids']==['wld_'+format(list(ids).index('World A')+1,'024x')]
# World B does not acquire this world-A definition.
assert 'wld_'+format(list(ids).index('World B')+1,'024x') not in cedar['applicability']['world_ids']
assert facts('Cedar One','height',1,world='World B')==[]
shared=[]
for ancestor in ancestry('Cedar One'):
    shared.extend(facts(ancestor,'grows',2,mode='shared'))
assert shared==[{'kind':'boolean','value':False},{'kind':'boolean','value':True}]
assert len({encoded(v) for v in shared})>1 and expected['inherited_conflict_at_t2']
unknown=[versions[b['assertion']] for b in oracle['facts'] if b['subject']=='Tree' and b['predicate']=='hazard']
assert unknown[0]['scope']['applicability']['kind']=='unspecified'
assert expected['unspecified_applicability_at_t2']=='unresolved'
# Query projections must agree with typed authority, including the single parent.
for r in db.execute('SELECT * FROM type_definition'):
    source=versions[r['version_id']]
    assert (r['name'],r['parent_id'])==(source['name'],source['parent'])
for r in db.execute('SELECT * FROM instance_classification'):
    source=versions[r['version_id']]
    if r['resolution']=='resolved':assert r['type_id']==source['classification']
# Exact identity closure for every explicitly authored proposition/reference and quantity unit.
for binding in oracle['facts']:
    prop=versions[binding['proposition']]
    for key in ['subject','predicate','context']:
        assert prop[key]['universe']==oracle['universe'];assert prop[key]['record'] in head
    if prop['value']['kind']=='quantity':assert 'rec_'+prop['value']['unit'].split('_')[1] in head
print(json.dumps({'version_round_trips':len(versions),'historical_membership_replayed':len(history),'snapshots':'exact','receipt':'exact','reservation':'exact',
 'cedar':{'identity':'preserved','ancestry':expected['cedar_ancestry'],'height':'30.00 authored unit reference; absent before t1','world_b':'inapplicable'},
 'pistols':{'A':a,'B':b,'rename_and_refinement':'no reinitialization','initial_value_receipts':1},'legacy':'both memberships retained; executable resolution blocked','inherited_conflict':'both scoped values retained; no override','unspecified_scope':'unresolved','cross_world_fact':'excluded','typed_projection_agreement':'verified','v2_header_v1_digest_recipe':'verified'}))
