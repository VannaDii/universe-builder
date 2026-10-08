"""Typed relational decoding used by storage regression tests and archive inspection."""
import json

def quote(s):return '"'+s.replace('"','""')+'"'
def encoded(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()

def reader(db,models):
    def decode(model,reference,trail=()):
        spec=models[model];kind=spec['kind']
        if kind=='null':assert reference is None;return None
        if kind=='boolean':assert reference in (0,1);return bool(reference)
        if kind=='integer':return int(reference)
        if kind=='number':return float(reference)
        if kind=='string':return reference
        marker=(model,reference);assert marker not in trail,'cyclic value/expression'
        trail=trail+(marker,)
        rows=db.execute('SELECT * FROM '+quote(spec['table'])+' WHERE __row_id=?',(reference,)).fetchall()
        assert len(rows)==1,(model,reference)
        row=rows[0]
        if kind in ('object','tuple'):
            fields={}
            for key,field in spec['fields'].items():
                state=row[key+'__state'];value=row[key]
                assert state in (0,1,2)
                assert state!=0 or not field['required']
                if state==0:assert value is None;continue
                if state==1:assert value is None;fields[key]=None
                else:fields[key]=decode(field['model'],value,trail)
            return fields if kind=='object' else [fields[str(i)] for i in range(len(fields))]
        if kind=='union':
            branch=row['variant'];assert 0<=branch<len(spec['variants'])
            for i in range(len(spec['variants'])):
                assert i==branch or row['v'+str(i)] is None
            return decode(spec['variants'][branch],row['v'+str(branch)],trail)
        key='ordinal' if kind=='array' else 'name'
        entries=db.execute('SELECT '+key+',item FROM '+quote(spec['table']+'_items')+' WHERE owner=? ORDER BY '+key,(reference,)).fetchall()
        if kind=='array':
            assert [r[0] for r in entries]==list(range(len(entries))),'noncontiguous ordered collection'
            return [decode(spec['item'],r[1],trail) for r in entries]
        return {r[0]:decode(spec['item'],r[1],trail) for r in entries}
    return decode
