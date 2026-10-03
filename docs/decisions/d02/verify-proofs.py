#!/usr/bin/env python3
"""Run independent design calculations; compare outputs and freeze source hashes."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path
root=Path(__file__).resolve().parent
for name in ['independent-calculation.py','payload-calculation.py']:
    subprocess.run([sys.executable,str(root/name)],check=True)
a=json.loads((root/'independent-results.json').read_text())
b=json.loads((root/'payload-results.json').read_text())
assert a == b, 'Independent ledger and concrete payload calculations disagree'
tamper=json.loads((root/'tamper-results.json').read_text())
assert len(tamper)==7 and set(tamper.values())=={'rejected'}
files=[root.parent/'d02-action-consequences.md']+[root/name for name in [
 'payloads.json','independent-ledger.json','acceptance.md','review.md','implementation-notes.md',
 'independent-calculation.py','payload-calculation.py','verify-proofs.py',
 'independent-results.json','payload-results.json','tamper-results.json','current-code-test-results.json']]
source_root=root.parents[2]
source_names=['crates/universe-domain/src/records.rs','crates/universe-domain/src/value.rs','crates/universe-service/src/actions.rs','crates/universe-rules/src/events.rs','crates/universe-service/src/events.rs','crates/universe-service/src/validation.rs','crates/universe-service/src/operations.rs','crates/universe-service/src/workflow.rs','crates/universe-service/src/validation_binding.rs','crates/universe-store/src/kernel.rs']
report={'currentCodeRegressionTests':json.loads((root/'current-code-test-results.json').read_text()),'owningSourceSha256':{name:hashlib.sha256((source_root/name).read_bytes()).hexdigest() for name in source_names},'status':'passed_design_preparation_only','baseline':'eb7ac8c4ff95842f21b1427828182dd79483bf6e',
 'independentCalculationGroups':len(a),'tamperControls':len(tamper),'runtimeQualification':False,
 'externalIndependentReviewer':False,'approval':'D02 approved as discussed; implementation notes are nonauthoritative suggestions',
 'method':'Independent Fraction ledger equations vs integer calculations from concrete proposed payloads; separate algorithms, same preparing agent. Not engine integration.',
 'sha256':{str(p.relative_to(root.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(root/'proof-results.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(f'PASS: {len(a)} independent groups agree; {len(tamper)} tamper controls reject.')
