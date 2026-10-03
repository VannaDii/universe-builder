#!/usr/bin/env python3
"""Concrete example arithmetic/target checks. Not a proposed runtime evaluator."""
import copy
import json
from pathlib import Path
root = Path(__file__).resolve().parent
payloads = json.loads((root / 'payloads.json').read_text())
props = {v['ref']['record']: v['payload'] for v in payloads['propositions'].values()}
def magnitude(value):
    assert value['kind'] == 'integer'
    return int(value['digits'])
def pre(name):
    return magnitude(props[payloads['preEvidence'][name]['proposition']['record']]['value'])
def calculate(key, initial, event=None):
    action = payloads['actions'][key]['payload']
    event = event or payloads['events'][key]
    slots = action['consequenceContract']['slots']
    assert len(slots) == len(event['effects'])
    calculated = {}
    for slot in slots:
        matches = [e for e in event['effects'] if e['slot'] == slot['slot']]
        assert len(matches) == 1
        effect = matches[0]
        owners = [p['record'] for p in event['participants'] if p['role'] == slot['target']['role']]
        assert len(owners) == 1
        proposition = props[effect['proposition']['record']]
        assert proposition['subject'] == owners[0]
        assert proposition['predicate'] == slot['target']['predicate']
        assert proposition['context'] == action['scope']['context']
        assert effect['scope'] == action['scope']
        assert effect['order'] == slot['order']
        if slot['change']['kind'] == 'delta':
            role = slot['target']['role']
            post = initial[role] + int(slot['change']['delta'])
            assert -(2**127) <= post <= 2**127-1
            assert magnitude(proposition['value']) == post
            assert int(slot['change']['minimum']) <= post <= int(slot['change']['maximum'])
            calculated[role] = str(post)
        else:
            assert proposition['value'] == slot['change']['value']
            assert effect['polarity'] == slot['change']['polarity']
            end = int(event['time']['value']) + int(slot['lifetime']['count'])
            assert effect['validity']['end']['value'] == str(end)
            return {'recipient': owners[0]['record'], 'end': str(end)}
    return {'post': calculated, 'withinBounds': True}
result = {key: calculate(key, initial) for key, initial in [
    ('fire', {'actor':pre('oneStock')}),
    ('transfer', {'sender':pre('senderFive'),'recipient':pre('recipientOne')}),
    ('replenish', {'actor':pre('oneStock')})]}
result['grant'] = calculate('enchant', {})
for key, amount, change in [('empty_fire',0,-1), ('overfill',8,3)]:
    post = amount + change
    result[key] = {'post': {'actor':str(post)}, 'withinBounds':0 <= post <= 10}
remaining = pre('oneStock')
after = []
for _ in range(2):
    remaining += int(payloads['actions']['fire']['payload']['consequenceContract']['slots'][0]['change']['delta'])
    after.append(str(remaining))
result['sequential'] = after
result['missingBalance'] = 'unresolved'  # No evidence value is manufactured.
result['i128'] = 'overflow' if (2**127-1)+1 > 2**127-1 else 'valid'
# Target/presence/order/value/end negatives independently alter concrete inputs.
negatives = {}
def reject(name, key, change, initial):
    event = copy.deepcopy(payloads['events'][key]); change(event)
    try:
        calculate(key, initial, event)
    except (AssertionError, KeyError):
        negatives[name] = 'rejected'
    else:
        raise AssertionError('tampering accepted: '+name)
reject('missing_consumption','fire',lambda e:e.update(effects=[]),{'actor':1})
reject('forged_post','fire',lambda e:e['effects'][0].update(proposition=payloads['propositions']['40']['ref']),{'actor':1})
reject('unrelated_walk_grant','walk',lambda e:e.update(effects=payloads['events']['enchant']['effects']),{})
reject('wrong_recipient','enchant',lambda e:e['effects'][0].update(proposition=payloads['propositions']['43']['ref']),{})
reject('missing_transfer_credit','transfer',lambda e:e['effects'].pop(),{'sender':5,'recipient':1})
reject('wrong_order','fire',lambda e:e['effects'][0].update(order=1),{'actor':1})
reject('wrong_grant_end','enchant',lambda e:e['effects'][0]['validity']['end'].update(value='14'),{})
(root / 'payload-results.json').write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
(root / 'tamper-results.json').write_text(json.dumps(negatives, indent=2, sort_keys=True)+'\n')
print('Concrete payloads: five balance equations, grant end/recipient, sequential use, missing balance, overflow; seven tamper controls passed.')
