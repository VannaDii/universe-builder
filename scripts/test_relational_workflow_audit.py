"""Adversarial controls for the independent relational MCP oracle."""
import copy
import gzip
import json
from pathlib import Path
import unittest
from audit_relational_workflow import audit


class RelationalOracleControls(unittest.TestCase):
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
