"""Derive current contract fixtures without rewriting frozen historical evidence.

Independent Python JSON, handwritten encoder and OpenSSL hashing; no Rust
serializer/codec is imported or run.
"""
import importlib.util
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'docs/decisions/d03-d08'
out=ROOT/'fixtures/source-assessments'
spec=importlib.util.spec_from_file_location('frozen_arithmetic',source/'verify_bindings.py')
oracle=importlib.util.module_from_spec(spec);spec.loader.exec_module(oracle)
examples=json.loads((source/'examples.json').read_text())
oldproofs=json.loads((source/'proof-results.json').read_text())['bindings']
replacements={'source_assessment_v1':'source_assessment'}
def replace(value):
    if isinstance(value,dict):return {k:replace(v) for k,v in value.items()}
    if isinstance(value,list):return [replace(v) for v in value]
    if isinstance(value,str):return replacements.get(value,value)
    return value
# Reconstruct the acyclic dependency chain in its original order.
bindings={}
for name in ['assessment','production_assessment'] + [n for n in oldproofs if n not in ['assessment','production_assessment']]:
    prior=oldproofs[name]
    body=replace(json.loads(prior['canonical_utf8']))
    proof=oracle.exact(body,prior['prefix_utf8'].encode())
    bindings[name]=proof
    replacements[prior['sha256']]=proof['sha256']
current=replace(examples)
(out/'relational-examples.json').write_text(json.dumps(current,ensure_ascii=False,indent=2)+'\n')
(out/'relational-proofs.json').write_text(json.dumps({'note':'Current unversioned assessment discriminator; derived from retained historical scenarios using independent encoders and OpenSSL. Historical files unchanged.','bindings':bindings},ensure_ascii=False,indent=2)+'\n')
edge=json.loads((out/'edge.json').read_text())
edge['body']=replace(edge['body'])
proof=oracle.exact(edge['body'],b'source-assessment:v1:')
edge['canonical_utf8']=proof['canonical_utf8'];edge['digest']=proof['sha256']
(out/'edge.json').write_text(json.dumps(edge,ensure_ascii=False,indent=2)+'\n')
print('PASS: current fixtures use independently reconstructed assessment and binding hashes')
