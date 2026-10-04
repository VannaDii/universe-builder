"""Adversarial controls for the independent relational MCP oracle."""
import copy
import gzip
import json
from pathlib import Path
import unittest
from audit_relational_workflow import audit
from audit_assessment_publication import canonical, digest, rows


class RelationalOracleControls(unittest.TestCase):
    def test_rehashed_workflow_cannot_change_frozen_operations_or_assignments(self):
        original=json.loads(gzip.decompress(Path('docs/evidence/relational-workflow/race.json.gz').read_bytes()))
        snapshot=original['race_before']
        rows(snapshot)
        for mutation in ('operations','assignment','footprint'):
            changed=copy.deepcopy(snapshot)
            entry=next(row for row in changed['workflow'] if row['key'].startswith('proposal:'))
            stored=json.loads(entry['payload_utf8'])
            if mutation=='operations':stored['proposal']['operations']=[]
            elif mutation=='assignment':stored['changes'][0]['next']['payload']['label']='forged source title'
            else:stored['footprint']['shared']=not stored['footprint']['shared']
            # Defeat the shallow envelope-hash check; the independent frozen
            # candidate preimage must still reject this forged evidence.
            entry['payload_utf8']=canonical(stored).decode()
            entry['digest']=digest(stored)
            with self.subTest(mutation=mutation),self.assertRaises(AssertionError):rows(changed)

    def test_rejects_orphans_false_winner_changed_history_and_retry(self):
        original=json.loads(gzip.decompress(Path('docs/evidence/relational-workflow/race.json.gz').read_bytes()))
        audit(original)
        mutations=[]
        value=copy.deepcopy(original)
        table=next(iter(value['interruption']['typed_rows_after']))
        value['interruption']['typed_rows_after'][table]+=1
        mutations.append(value)
        value=copy.deepcopy(original)
        for contender in value['contenders']:contender['response']['isError']=False
        mutations.append(value)
        value=copy.deepcopy(original)
        value['restart']['workflow'][0]['digest']='0'*64
        mutations.append(value)
        value=copy.deepcopy(original)
        value['retry']['response']={'isError':True}
        mutations.append(value)
        for index, mutation in enumerate(mutations):
            with self.subTest(index=index),self.assertRaises(AssertionError):audit(mutation)


if __name__=='__main__':unittest.main()
