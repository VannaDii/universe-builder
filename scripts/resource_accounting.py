"""Independent Fraction accounting for frozen single-event resource fixtures."""
from copy import deepcopy
from fractions import Fraction
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def materialize(gold, case):
    rows=deepcopy(gold['records'])
    for m in case['mutations']:
        node=rows[m['record']-1]; parts=m['path'].split('.')
        for key in parts[:-1]: node=node[int(key)] if isinstance(node,list) else node[key]
        if m['value'] is None: node.pop(parts[-1])
        else: node[parts[-1]]=deepcopy(m['value'])
    rows.extend(deepcopy(case.get('extraRecords',[])))
    return rows

def calculate(rows):
    event=rows[5]; slots=rows[4]['consequenceContract']['slots']; effects=event['effects']; calculations=[]
    def record(ref): return rows[int(ref['record'][4:],16)-1]
    def number(value,unit):
        if unit is not None:
            if value['kind']!='quantity' or value['unit']!=unit: raise ValueError('unit')
            value=value['value']
        if value['kind']!='integer': raise ValueError('integer')
        n=Fraction(value['digits'])
        if n.denominator!=1 or not -2**127<=n<2**127: raise ValueError('bounds')
        return n
    try:
        targets=[]
        for slot in slots:
            owners=[p['record'] for p in event['participants'] if p['role']==slot['target']['role']]
            if len(owners)!=1: raise ValueError('owner')
            key=(owners[0]['record'],slot['target']['predicate']['record'])
            if key in targets: raise ValueError('alias')
            targets.append(key)
            es=[e for e in effects if e['slot']==slot['slot']]
            if len(es)>1: raise ValueError('duplicate')
            if not es:
                if event['occurrence']=='occurred' and slot['presence']=='required': raise ValueError('missing')
                continue
            e=es[0]; p=record(e['proposition'])
            if p['subject']!=owners[0] or p['predicate']!=slot['target']['predicate'] or e['polarity']!='support': raise ValueError('effect')
            if event['occurrence']!='occurred': continue
            c=slot['change']; post=number(p['value'],c['unit']); tick=Fraction(event['time']['value'])
            for world in event.get('worlds',[]) or [None]:
                support=set();refute=set()
                for a in rows:
                    if a['record_kind']!='assertion': continue
                    q=record(a['proposition'])
                    if q['subject']!=owners[0] or q['predicate']!=slot['target']['predicate'] or q['context']!=rows[4]['scope']['context']: continue
                    scope=a['scope']['applicability']
                    if scope['kind']=='worlds' and world not in scope['world_ids']: continue
                    v=a['validity']
                    if v['kind']!='calendar_interval': raise ValueError('time')
                    start=v['start'];end=v['end']
                    if start['kind']!='unbounded' and Fraction(start['value'])>=tick:continue
                    if end['kind']!='unbounded' and Fraction(end['value'])<tick:continue
                    if a['precision']!='exact' or a.get('alternatives') or a['scope'].get('realm'):raise ValueError('uncertain')
                    n=number(q['value'],c['unit'])
                    (support if a['polarity']=='support' else refute).add(n)
                if len(support)!=1 or support & refute: raise ValueError('evidence')
                before=next(iter(support)); after=before+Fraction(c['delta']);lo=Fraction(c['minimum']);hi=Fraction(c['maximum'])
                calculations.append({'slot':slot['slot'],'world':world,'before':str(before),'delta':c['delta'],'expected_after':str(after),'proposed_after':str(post)})
                if not lo<=before<=hi or not lo<=after<=hi or not -2**127<=after<2**127 or post!=after: raise ValueError('arithmetic')
        return {'allowed':True,'calculations':calculations}
    except (ValueError,KeyError,IndexError) as e: return {'allowed':False,'calculations':calculations,'reason':str(e)}

if __name__=='__main__':
    gold=json.loads((ROOT/'fixtures/resource-transitions/expected.json').read_text()); results={}
    for case in gold['cases']:
        result=calculate(materialize(gold,case)); assert result['allowed']==case['allowed'],(case['id'],result);results[case['id']]=result
    print(json.dumps({'status':'passed','cases':results},indent=2))
