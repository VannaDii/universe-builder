"""Typed row writer for disposable functional test fixtures."""
import re

def q(name):
    return '"' + name.replace('"', '""') + '"'

MISSING = object()


class Writer:
    def __init__(self, db, models):self.db,self.models=db,models
    def fits(self,name,value):
        d=self.models[name]; k=d['kind']
        if k=='union':return any(self.fits(n,value) for n in d['variants'])
        if k=='object':
            return isinstance(value,dict) and not (value.keys()-d['fields'].keys()) and all(
                (key in value or not f['required']) and (key not in value or self.fits(f['model'],value[key]))
                for key,f in d['fields'].items())
        if k=='tuple':return isinstance(value,list) and len(value)==len(d['fields']) and all(self.fits(f['model'],value[int(key)]) for key,f in d['fields'].items())
        if k in ('array','map'):
            return isinstance(value,list if k=='array' else dict) and all(self.fits(d['item'],x) for x in (value if k=='array' else value.values()))
        if k=='null':return value is None
        if k=='boolean':return isinstance(value,bool)
        if k=='integer':return isinstance(value,int) and not isinstance(value,bool)
        if k=='number':return isinstance(value,(int,float)) and not isinstance(value,bool)
        if not isinstance(value,str):return False
        return ('const' not in d or value==d['const']) and ('enum' not in d or value in d['enum']) and ('pattern' not in d or re.fullmatch(d['pattern'],value))
    def put(self,name,value):
        assert self.fits(name,value),(name,value)
        d=self.models[name]; k=d['kind']
        if k in ('string','integer','number','boolean','null'):
            return None if value is None else int(value) if k=='boolean' else str(value)
        cols={}
        if k in ('object','tuple'):
            for key,f in d['fields'].items():
                x=value.get(key,MISSING) if k=='object' else value[int(key)]
                cols[key+'__state']=0 if x is MISSING else 1 if x is None else 2
                cols[key]=None if x is MISSING or x is None else self.put(f['model'],x)
        elif k=='union':
            i=next(i for i,n in enumerate(d['variants']) if self.fits(n,value))
            cols={'variant':i,'v'+str(i):self.put(d['variants'][i],value)}
        row=self.db.execute('INSERT INTO '+q(d['table'])+(' ('+','.join(map(q,cols))+') VALUES ('+','.join('?' for _ in cols)+')' if cols else ' DEFAULT VALUES'),list(cols.values())).lastrowid
        if k in ('array','map'):
            for key,x in enumerate(value) if k=='array' else value.items():
                self.db.execute('INSERT INTO '+q(d['table']+'_items')+' VALUES (?,?,?)',(row,key,self.put(d['item'],x)))
        return row
