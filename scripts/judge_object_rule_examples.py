"""Independent static scope/start/accounting judgments; imports no production logic.

This does not evaluate rule expressions, mutate canon, or simulate a world.
Expected labels are separately authored in the JSON fixture. Decisions here
are elementary set containment, established-start checks, and Fraction arithmetic.
"""
import json
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def matching(case):
    if case['explicit_set'] is not None:
        return case['entity_id'] in case['explicit_set']
    return case['requested_type'] in case['entity_types']


def scope(case):
    w = case['query_world']
    if case['rule_worlds'] is not None and w not in case['rule_worlds']:
        return 'outside_rule'
    if (case['assertion_worlds'] is not None and w not in case['assertion_worlds']) or case['context'] != case['assertion_context']:
        return 'missing_evidence'
    return 'applicable'


def initialization(case):
    if case['authorized_reload']:
        return 'reload_transition'
    if case['known_initial_record']:
        return 'do_not_initialize'
    if case['existing_stock'] is not None:
        return 'clarify_existing_stock'
    if case['established_start'] is None or case['requested_tick'] != case['established_start']:
        return 'clarify_start'
    return 'propose_initial_assertion'


def accounting(case):
    if case['stock'] is None:
        return 'missing_stock'
    values = set(map(Fraction, case['stock']))
    if len(values) != 1:
        return 'ambiguous_stock'
    before = values.pop()
    after = before + Fraction(case['delta'])
    if not (0 <= before <= Fraction(case['capacity']) and 0 <= after <= Fraction(case['capacity'])):
        return 'outside_bounds'
    if after != Fraction(case['proposed_after']):
        return 'forged_post'
    return 'allowed'


def judge(gold):
    results = []
    for family, calculator in [('matching_examples', matching), ('scope_examples', scope), ('initialization_examples', initialization), ('accounting_examples', accounting)]:
        for case in gold[family]:
            actual = calculator(case)
            if actual != case['expected']:
                raise AssertionError(f"{case['name']}: {actual} != {case['expected']}")
            results.append({'family': family, 'name': case['name'], 'judgment': actual})
    return {'status': 'passed', 'examples': len(results), 'results': results,
            'limitations': 'Independent program judgment, not human review; not a runtime once-only initializer proof.'}


if __name__ == '__main__':
    print(json.dumps(judge(json.loads((ROOT / 'fixtures/object-rules/independent-examples.json').read_text())), indent=2))
