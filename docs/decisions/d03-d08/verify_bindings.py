#!/usr/bin/env python3
"""Decision arithmetic only. No runtime assessment implementation or admission oracle."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent
ORACLE_HASH = '3ead237bf50ef60413a9d62ef0505daf57961168b2bfbf5d74de02f711e77107'

def ordinary(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')

def reference(value):
    # Separate encoder for this fixture's restricted types; no serializer imports.
    def string(s):
        escapes = {'"': '\\"', '\\': '\\\\', '\n': '\\n', '\r': '\\r', '\t': '\\t', '\b': '\\b', '\f': '\\f'}
        return '"' + ''.join(escapes.get(c, ('\\u%04x' % ord(c)) if ord(c) < 32 else c) for c in s) + '"'
    if value is None: return b'null'
    if value is True: return b'true'
    if value is False: return b'false'
    if type(value) is int: return str(value).encode('ascii')
    if isinstance(value, str): return string(value).encode('utf-8')
    if isinstance(value, list): return b'[' + b','.join(reference(v) for v in value) + b']'
    if isinstance(value, dict): return b'{' + b','.join(reference(k)+b':'+reference(value[k]) for k in sorted(value)) + b'}'
    raise TypeError('Fixture permits no host float or unknown type')

def sha(data): return hashlib.sha256(data).hexdigest()
def openssl(data):
    return subprocess.run(['openssl', 'dgst', '-sha256'], input=data, check=True, capture_output=True).stdout.decode().strip().split()[-1]
def exact(value, prefix=b''):
    left, right = ordinary(value), reference(value)
    assert left == right
    digest = sha(prefix+left)
    assert digest == openssl(prefix+right)
    return {'canonical_utf8':left.decode(), 'prefix_utf8':prefix.decode(), 'sha256':digest, 'byte_length':len(prefix+left)}

def main():
    assert sha((ROOT/'oracle.md').read_bytes()) == ORACLE_HASH, 'Frozen gold oracle changed'
    e = json.loads((ROOT/'examples.json').read_text())
    body=e['assessment']['body']; candidate=e['miniature_frozen_candidate']; binding=e['final_binding']
    proofs={ 'production_shaped_candidate':exact(e['production_shaped_proposal_preimage']), 'candidate_miniature':exact(candidate), 'assessment':exact(body,b'source-assessment:v1:'), 'execution':exact(e['execution_core']), 'inventory':exact(body['declared_inventory']), 'final_validation':exact(binding,b'source-validation:v1:') }
    assert proofs['candidate_miniature']['sha256']==body['proposal']['digest']
    assert proofs['assessment']['sha256']==e['assessment']['digest']==binding['selection']['selected']['digest']
    assert proofs['execution']['sha256']==binding['execution_result_digest']
    assert proofs['inventory']['sha256']==binding['submitted_input']['inventory_digest']
    assert proofs['final_validation']['sha256']==e['validation_v3']['final_binding_digest']
    checks=[]
    def ok(name, condition):
        assert condition, name
        checks.append({'check':name,'result':'pass'})
    ok('three-stage example hashes match stored binding fields',True)
    pp=e['production_shaped_proposal_preimage']
    ok('production tuple empty digest and closed stored proposal shape',pp[0]['digest']=='' and len(pp)==3 and pp[1]==[] and pp[2]=={'worlds':[],'shared':False,'protected':False})
    raw=e['source_a'].encode(); braw=e['source_b'].encode()
    # Literal byte arithmetic derives gold locations without reading mapping offsets.
    expected=[(0,34),(11,34),(35,47)]
    actual=[(i['range']['start'],i['range']['end']) for i in body['declared_inventory']]
    ok('independent UTF-8 gold offsets',actual==expected and len(raw)==47)
    ok('all source bytes and lengths verified',sha(raw)==body['sources'][0]['blob_digest'] and len(raw)==body['sources'][0]['byte_size'])
    for start,end in expected:
        raw[:start].decode(); raw[start:end].decode(); raw[end:].decode()
    try: raw[12:32].decode()
    except UnicodeDecodeError: ok('anchor inside curly quote rejected by independent decoder',True)
    else: raise AssertionError('mid-character anchor unexpectedly valid')
    ok('stale source B differs from A',sha(raw)!=sha(braw))
    ok('object key reordering preserves binding',sha(reference(dict(reversed(list(body.items())))))==sha(reference(body)))
    mutations={
        'candidate_digest':lambda x:x['proposal'].__setitem__('digest','f'*64),
        'source_version':lambda x:x['sources'][0]['source_version'].__setitem__('version','ver_'+'f'*24),
        'source_bytes':lambda x:x['sources'][0].__setitem__('blob_digest',sha(braw)),
        'work_edition':lambda x:x['sources'][0]['work_edition'].__setitem__('version','ver_'+'e'*24),
        'mapping_context':lambda x:x['claim_mappings'][1].__setitem__('context',x['claim_mappings'][0]['context']),
        'inventory_omission':lambda x:x['declared_inventory'].pop(),
        'unresolved_item':lambda x:x['unresolved'].append({'unresolved_id':'u1','item_ids':['waiting'],'reason':'missing_evidence','detail':'Missing waiting evidence.'}),
        'assessor_identity':lambda x:x['assessor'].__setitem__('principal','prn_'+'e'*24),
        'ordered_inventory':lambda x:x['declared_inventory'].reverse(),
        'unchanged_dependency':lambda x:x['dependencies'][-1].__setitem__('version','ver_'+'d'*24),
    }
    mutated={}
    for name, mutate in mutations.items():
        changed=copy.deepcopy(body); mutate(changed); proof=exact(changed,b'source-assessment:v1:')
        ok(name+' changes attachment digest',proof['sha256']!=proofs['assessment']['sha256'])
        mutated[name]=proof['sha256']
    for name,modify in {
        'replacement':lambda x:x['selection']['selected'].__setitem__('assessment_id','asm_'+'e'*24),
        'withdrawal':lambda x:x['selection'].__setitem__('selected',None),
        'selection_generation':lambda x:x['selection'].__setitem__('generation',2),
        'evaluator':lambda x:x.__setitem__('evaluator_version','different-evaluator'),
        'submitted_scope':lambda x:x['submitted_input'].__setitem__('kind','record_candidate'),
    }.items():
        changed=copy.deepcopy(binding); modify(changed)
        ok(name+' invalidates final validation hash',exact(changed,b'source-validation:v1:')['sha256']!=proofs['final_validation']['sha256'])
    # Positive construction has no back edges; introducing a self-field changes preimage.
    ok('body excludes own identity/digest/final digest',not {'digest','assessment_id','final_binding_digest'} & body.keys())
    cycle=copy.deepcopy(body); cycle['digest']=proofs['assessment']['sha256']
    ok('inserting claimed self digest changes hash, cannot reuse original',sha(b'source-assessment:v1:'+reference(cycle))!=cycle['digest'])
    cyclic_candidate=copy.deepcopy(candidate); cyclic_candidate['assessment_candidate_digest']=body['proposal']['digest']
    ok('embedding candidate digest in candidate breaks original binding',sha(reference(cyclic_candidate))!=body['proposal']['digest'])
    # Closed response/fixture accounting checks, not implementation of proposed service.
    restricted=e['restricted_result']
    ok('restricted response exactly omits all fingerprints and identities',restricted=={'kind':'restricted','execution_coverage':'restricted','submitted_input':{'kind':'restricted'},'assessment':{'kind':'restricted'}})
    ok('query completion carries no final authority binding',e['query_result']['execution']['coverage']=='complete' and e['query_result']['submitted_input']['kind']=='query' and e['query_result']['assessment']=={'kind':'absent'} and e['query_result']['final_binding_digest'] is None)
    ok('stale response preserves record-only input scope',e['stale_result_fragment']['submitted_input']['kind']=='record_candidate' and e['stale_result_fragment']['final_binding_digest'] is None)
    source_by_key={v['key']:v for v in body['sources']}
    mappings={v['mapping_id']:v for v in body['claim_mappings']}
    items={v['item_id']:v for v in body['declared_inventory']}
    ok('all inventory ranges contained in declared source scope',all(any(r['start']<=v['range']['start']<v['range']['end']<=r['end'] for r in source_by_key[v['source_key']]['ranges']) for v in items.values()))
    ok('mapping and inventory identifiers reciprocally agree',all(v['item_id'] in mappings[mid]['item_ids'] for v in items.values() for mid in v['mapping_ids']) and all(v['mapping_id'] in items[iid]['mapping_ids'] for v in mappings.values() for iid in v['item_ids']))
    ok('all reference examples explicitly bind universe',all(v['universe']==body['base_frame']['universe'] for v in body['dependencies']) and all(v['source_version']['universe']==body['base_frame']['universe'] for v in body['sources']))
    for field,value in [('readerScene','rec_'+'b'*24),('personalSequence','sequence-b')]:
        changed=copy.deepcopy(pp);changed[0]['base_frame'][field]=value
        ok(field+' changes actual proposal tuple digest',exact(changed)['sha256']!=proofs['production_shaped_candidate']['sha256'])
    fragment=e['inconsistent_body_fragment']
    ok('inconsistent B fragment binds exact changed source bytes',fragment['sources'][0]['blob_digest']==sha(braw) and fragment['sources'][0]['byte_size']==49 and fragment['conclusion']=='inconsistent' and fragment['claim_mappings'][1]['judgment']=='contradicted')
    ok('inconsistent B offsets independently align',[(v['range']['start'],v['range']['end']) for v in fragment['declared_inventory']]==[(0,36),(11,36),(37,49)])
    rows=(ROOT/'oracle.md').read_text().splitlines()
    oracle_ids=[r.split('|')[1].strip() for r in rows if r.startswith('| O')]
    ok('38 independently frozen requirement fixtures present',oracle_ids==['O%02d'%i for i in range(1,39)])
    result={'proof_kind':'design_preparation_arithmetic_not_runtime_qualification','oracle_sha256':ORACLE_HASH,'independence':'Same-agent frozen requirement oracle; independent handwritten encoder and OpenSSL digest calculation versus Python JSON/hashlib. No separate reviewer implied.','passed_checks':len(checks),'checks':checks,'gold_utf8_ranges':expected,'source_a_sha256':sha(raw),'source_b_sha256':sha(braw),'bindings':proofs,'mutated_assessment_digests':mutated}
    (ROOT/'proof-results.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({'passed_checks':len(checks),'candidate':proofs['candidate_miniature']['sha256'],'assessment':proofs['assessment']['sha256'],'validation':proofs['final_validation']['sha256']}))
if __name__=='__main__': main()
