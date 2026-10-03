"""Mutation controls for the independent page/permission oracle."""
import copy
import gzip
import json
from pathlib import Path
import tempfile
import unittest

from audit_assessment_review import run


class ReviewOracleControls(unittest.TestCase):
    def test_rejects_missing_pages_changed_offsets_content_and_private_denials(self):
        path = Path('docs/evidence/assessment-review/transcript.json.gz')
        original = json.loads(gzip.decompress(path.read_bytes()))
        mutations = []
        v = copy.deepcopy(original)
        v['cases'] = [c for c in v['cases'] if c['label'] != 'selected-8']
        mutations.append(('missing final page', v))
        v = copy.deepcopy(original)
        c = next(c for c in v['cases'] if c['label'] == 'selected-1')
        c['response']['structuredContent']['result']['fragment']['offset'] += 1
        c['response']['content'][0]['text'] = json.dumps(c['response']['structuredContent'])
        mutations.append(('changed byte offset', v))
        v = copy.deepcopy(original)
        c = next(c for c in v['cases'] if c['label'] == 'selected-0')
        chunk = c['response']['structuredContent']['result']['fragment']
        chunk['canonical_envelope_utf8'] = chunk['canonical_envelope_utf8'].replace('Synthetic', 'SynthetiX', 1)
        c['response']['content'][0]['text'] = json.dumps(c['response']['structuredContent'])
        mutations.append(('changed envelope bytes', v))
        v = copy.deepcopy(original)
        c = next(c for c in v['cases'] if c['label'] == 'source-restricted')
        c['response']['structuredContent']['inventory_count'] = 61
        c['response']['content'][0]['text'] = json.dumps(c['response']['structuredContent'])
        mutations.append(('private count in denial', v))
        with tempfile.TemporaryDirectory() as directory:
            for label, v in mutations:
                with self.subTest(label=label):
                    target = Path(directory) / 'mutated.json.gz'
                    target.write_bytes(gzip.compress(json.dumps(v, ensure_ascii=False).encode(), mtime=0))
                    with self.assertRaises(AssertionError):
                        run(target)


if __name__ == '__main__':
    unittest.main()
