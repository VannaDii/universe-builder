#!/usr/bin/env python3
"""Design-proof ledger equations only. Imports no payload verifier or engine."""
import json
from fractions import Fraction
from pathlib import Path
root = Path(__file__).resolve().parent
ledger = json.loads((root / 'independent-ledger.json').read_text())
result = {}
for case in ledger['cases']:
    accounts = set(case['initial']) | set(case['credits']) | set(case['debits'])
    post = {k: Fraction(case['initial'][k]) + Fraction(case['credits'].get(k, '0'))
            - Fraction(case['debits'].get(k, '0')) for k in sorted(accounts)}
    assert all(v.denominator == 1 for v in post.values())
    assert {k: str(v.numerator) for k, v in post.items()} == case['expected']
    admitted = all(Fraction(ledger['bounds']['minimum']) <= v <= Fraction(ledger['bounds']['maximum']) for v in post.values())
    assert admitted == case.get('admissible', True)
    result[case['id']] = {'post': {k: str(v.numerator) for k, v in post.items()}, 'withinBounds': admitted}
grant = ledger['grant']
end = Fraction(grant['start']) + Fraction(grant['duration'])
assert str(end.numerator) == grant['expectedEnd']
result['grant'] = {'recipient': grant['recipientRecord'], 'end': str(end.numerator)}
stock = Fraction(ledger['sequential']['initial'])
after = []
for cost in ledger['sequential']['costs']:
    stock -= Fraction(cost)
    after.append(str(stock.numerator))
assert after == ledger['sequential']['expectedAfter']
result['sequential'] = after
assert ledger['missingBalance']['initial'] is None
result['missingBalance'] = 'unresolved'
overflow = Fraction(ledger['i128']['initial']) + Fraction(ledger['i128']['credit'])
assert overflow > 2**127-1
result['i128'] = 'overflow'
(root / 'independent-results.json').write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
print('Independent ledger: five balance equations, grant end/recipient, sequential use, missing balance, overflow passed.')
