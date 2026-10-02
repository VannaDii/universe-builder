"""Independent reviewer calculation. Does not import or invoke producer verifier."""
from pathlib import Path
import json, hashlib
P=Path(__file__).parent
x=json.loads((P/'examples.json').read_text())
def enc(v):
    if isinstance(v,str):
        rules={'"':'\\"','\\':'\\\\','\b':'\\b','\f':'\\f','\n':'\\n','\r':'\\r','\t':'\\t'}
        return ('"'+''.join(rules.get(c, f'\\u{ord(c):04x}' if ord(c)<32 else c) for c in v)+'"').encode()
    if v is None: return b'null'
    if v is True:return b'true'
    if v is False:return b'false'
    if type(v) is int:return str(v).encode()
    if isinstance(v,list):return b'['+b','.join(map(enc,v))+b']'
    if isinstance(v,dict):return b'{'+b','.join(enc(k)+b':'+enc(v[k]) for k in sorted(v))+b'}'
    raise ValueError('unsupported numeric/type')
def h(v,p=''):return hashlib.sha256(p.encode()+enc(v)).hexdigest()
body=x['assessment']['body']; binding=x['final_binding']
r={'kind':'independent_design_arithmetic_not_runtime_qualification','frozen_independent_oracle_sha256':hashlib.sha256((P/'independent-oracle.md').read_bytes()).hexdigest(),'bindings':{}}
for name,v,p in [('candidate_miniature',x['miniature_frozen_candidate'],''),('candidate_production_tuple',x['production_shaped_proposal_preimage'],''),('assessment',body,'source-assessment:v1:'),('execution',x['execution_core'],''),('inventory',body['declared_inventory'],''),('final_validation',binding,'source-validation:v1:')]:
    r['bindings'][name]={'sha256':h(v,p),'preimage_utf8':p+enc(v).decode()}
b=r['bindings']; assert b['candidate_miniature']['sha256']==body['proposal']['digest']; assert b['assessment']['sha256']==x['assessment']['digest']; assert b['execution']['sha256']==binding['execution_result_digest'];assert b['inventory']['sha256']==binding['submitted_input']['inventory_digest'];assert b['final_validation']['sha256']==x['validation_v3']['final_binding_digest']
r['production_candidate_equals_separate_miniature_chain']=b['candidate_production_tuple']['sha256']==body['proposal']['digest']
r['sources']={}
for suffix in ['a','b']:
    raw=x['source_'+suffix].encode(); words=[x['source_'+suffix], x['source_'+suffix][11:x['source_'+suffix].index(' Iven')], 'Iven waited.']; ranges=[]
    for text in words:
        start=raw.index(text.encode());end=start+len(text.encode()); raw[:start].decode();raw[start:end].decode();raw[end:].decode(); ranges.append([start,end])
    r['sources'][suffix]={'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'independent_ranges':ranges}
assert r['sources']['a']['independent_ranges']==[[0,47],[11,34],[35,47]]
r['wrapper_checks']={'evaluated_tag':x['validation_v3']['kind']=='evaluated','query_has_no_binding':x['query_result']['final_binding_digest'] is None,'restricted_exact_shape':x['restricted_result']=={'kind':'restricted','execution_coverage':'restricted','submitted_input':{'kind':'restricted'},'assessment':{'kind':'restricted'}}}
(P/'independent-recalculation-results.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v['sha256'] for k,v in b.items()}));print('Production C equals separate miniature C:',r['production_candidate_equals_separate_miniature_chain'])

# Corrections: independently bind the production-shaped tuple through the full DAG.
production=x['production_bound_example']
prod_c=h(x['production_shaped_proposal_preimage'])
prod_a=h(production['assessment']['body'],'source-assessment:v1:')
prod_e=h(production['execution_core'])
prod_v=h(production['final_binding'],'source-validation:v1:')
assert prod_c==production['proposal_digest']==production['assessment']['body']['proposal']['digest']==production['execution_core']['input_digest']
assert prod_a==production['assessment']['digest']==production['selection']['selected']['digest']
assert prod_e==production['final_binding']['execution_result_digest']
assert prod_v==production['validation_v3']['final_binding_digest']
assert production['final_binding']['assessment_state']==production['validation_v3']['assessment']
assert production['final_binding']['selection']==production['selection']
assert production['final_binding']['submitted_input']==production['validation_v3']['submitted_input']
assignment=x['production_shaped_proposal_preimage'][1][0]['next']
payload_digest=h(assignment['payload'],'anchor:v1:')
assert payload_digest==assignment['payload_digest']
assert not {'operation_id','opposing_evidence'} & production['execution_core'].keys()
wrong=dict(production['execution_core'],operation_id=None,opposing_evidence=[])
assert h(wrong)!=prod_e
fresh=x['fresh_record_only_result'];fresh_binding=x['fresh_record_only_binding']
assert h(fresh['execution'])==fresh_binding['execution_result_digest']
assert h(fresh_binding,'source-validation:v1:')==fresh['final_binding_digest']
assert fresh_binding['assessment_state']==fresh['assessment']
assert fresh_binding['submitted_input']==fresh['submitted_input']
assert fresh_binding['selection']==production['selection']
assert x['stale_result_fragment']['final_binding_digest'] is None
r['corrected_production_chain']={'candidate':prod_c,'assessment':prod_a,'execution':prod_e,'final_validation':prod_v,'anchor_payload':payload_digest}
r['fresh_record_only_final_validation']=fresh['final_binding_digest']
r['typed_execution_omission_changes_hash']=True
r['all_connected_production_fields_agree']=True
(P/'independent-recalculation-results.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(r['corrected_production_chain']))
