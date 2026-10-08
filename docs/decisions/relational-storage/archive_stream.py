"""Canonical table stream shared by archive regression fixtures."""
import json

def stream(db):
    rows=[]
    tables=[r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name") if not r[0].startswith(('sqlite_','search_index')) and r[0] not in ['archive_integrity','r_archive_manifest']]
    for table in tables:
        cols=[r[1] for r in db.execute('PRAGMA table_info("'+table+'")')]
        order=[r[1] for r in sorted(db.execute('PRAGMA table_info("'+table+'")'),key=lambda r:r[5]) if r[5]] or cols
        query='SELECT '+','.join('"'+k+'"' for k in cols)+' FROM "'+table+'" ORDER BY '+','.join('"'+k+'"' for k in order)
        for record in db.execute(query):
            cells=[['bytes',v.hex()] if isinstance(v,bytes) else ['null',None] if v is None else ['integer',v] if isinstance(v,int) else ['text',v] for v in record]
            rows.append([table,cols,cells])
    return json.dumps(rows,ensure_ascii=False,separators=(',',':')).encode(),len(rows)
