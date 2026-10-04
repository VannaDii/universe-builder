#!/usr/bin/env python3
"""Disposable relational writer and proof runner. Never accepts an author package path."""
import copy
import hashlib
import json
import re
import sqlite3
import subprocess
import tempfile
from pathlib import Path
from build_schema import HERE, ROOT, build, contracts, q

MISSING = object()

def canonical(v):return json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()

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


def sample(schema,defs):
    if '$ref' in schema:return sample(defs[schema['$ref'].split('/')[-1]],defs)
    variants=schema.get('oneOf',schema.get('anyOf'))
    if variants:
        # Optional data stays absent/unknown. Avoid recursive branches as defaults.
        s=next((s for s in variants if s.get('type')=='null'),variants[0])
        return sample(s,defs)
    if 'const' in schema:return schema['const']
    if 'enum' in schema:return schema['enum'][0]
    t=schema.get('type')
    if isinstance(t,list):return None if 'null' in t else sample({'type':t[0]},defs)
    if t=='object':return {k:sample(s,defs) for k,s in schema.get('properties',{}).items() if k in schema.get('required',[])}
    if t=='array':return [sample(s,defs) for s in schema['prefixItems']] if 'prefixItems' in schema else [sample(schema['items'],defs) for _ in range(schema.get('minItems',0))]
    if t=='null':return None
    if t=='boolean':return True
    if t in ('integer','number'):return max(1,schema.get('minimum',1))
    if t=='string':
        pat=schema.get('pattern','')
        if pat.startswith('^') and '_[' in pat:return pat[1:pat.index('[')]+'0'*23+'1'
        if '64' in pat:return 'a'*64
        return '1' if any(x in pat for x in ('0-9','\\d')) else 'é🌲 sample'
    raise ValueError(schema)


def fixtures(c):
    defs=contracts(); rows=[]
    for i,s in enumerate(defs['Payload']['oneOf']):
        v=sample(s,defs)
        # Exact numeric digit strings have domain syntax checks on deserialize.
        def digits(x):
            if isinstance(x,dict):
                for k,v in x.items():
                    if k in ('digits','numerator','denominator','factor','offset'):x[k]='1'
                    else:digits(v)
            elif isinstance(x,list):
                for v in x:digits(v)
        digits(v)
        rows.append({'name':'family:'+v['record_kind'],'value':v})
    template=next(x['value'] for x in rows if x['value']['record_kind']=='entity')
    # Exercise every Value variant and every expression variant inside real payloads.
    for i,s in enumerate(defs['Value']['oneOf']):
        v=sample(s,defs);digits(v)
        e=copy.deepcopy(template);e['metadata']={'specimen':v}
        rows.append({'name':'value:'+str(i),'value':e})
    rule=next(x['value'] for x in rows if x['value']['record_kind']=='rule')
    for i,s in enumerate(defs['Expr']['oneOf']):
        r=copy.deepcopy(rule);r['expression']=sample(s,defs);digits(r)
        rows.append({'name':'expression:'+str(i),'value':r})
    # Ambiguity is evidence in the same model, not a second classification format.
    ty=copy.deepcopy(next(x['value'] for x in rows if x['value']['record_kind']=='entity_type'))
    ty['parent']=None;ty['parentResolution']='ambiguous'
    rows.append({'name':'classification:ambiguous-parent','value':ty})
    e=copy.deepcopy(template);e['classification']=None;e['classificationResolution']='ambiguous';rows.append({'name':'classification:ambiguous-membership','value':e})
    e=copy.deepcopy(template)
    e['metadata']={'decimal':{'kind':'decimal','digits':'30.00'},'integer':{'kind':'integer','digits':'9007199254740993'},'rational':{'kind':'rational','numerator':'7','denominator':'3'},'sequence':{'kind':'sequence','items':[{'kind':'text','text':'b'},{'kind':'text','text':'a'}]}}
    rows.append({'name':'exact:digits-unicode-order','value':e})
    return rows


def run():
    c=build()
    with tempfile.TemporaryDirectory(prefix='universe-relational-decision-') as tmp:
        tmp=Path(tmp)
        raw=tmp/'raw.json';raw.write_text(json.dumps(fixtures(c),ensure_ascii=False))
        result=subprocess.run(['cargo','run','-q','-p','universe-domain','--example','relational_decision_probe','--',str(raw)],cwd=ROOT,capture_output=True,text=True)
        if result.returncode:raise RuntimeError(result.stderr)
        expected=json.loads(result.stdout)
        (HERE/'canonical-oracle.json').write_text(json.dumps(expected,ensure_ascii=False,indent=2)+'\n')
        dbpath=tmp/'prototype.sqlite'
        db=sqlite3.connect(dbpath);db.executescript((HERE/'typed.sql').read_text())
        db.executescript((HERE/'kernel.sql').read_text());db.executescript((HERE/'semantic.sql').read_text());db.executescript((HERE/'workflow.sql').read_text())
        # Proof-only addressing, not a production application fallback.
        db.execute('CREATE TABLE proof_roots(name TEXT PRIMARY KEY, model TEXT NOT NULL, row_id INTEGER NOT NULL, expected_digest TEXT NOT NULL) STRICT')
        writer=Writer(db,c.models)
        for row in expected:
            rid=writer.put('Payload',row['value'])
            db.execute('INSERT INTO proof_roots VALUES (?,?,?,?)',(row['name'],'Payload',rid,row['digest']))
        # Structurally round-trip every operation/workflow envelope and every union variant.
        extra=[]
        defs=contracts()
        for name in c.models:
            d=c.models[name]
            if d['kind']!='union':continue
            for i,variant in enumerate(d['variants']):
                # Derive a specimen from the compiled explicit catalog, independently checked below.
                value=sample_model(c.models,variant)
                extra.append({'name':'union:'+name+':'+str(i),'model':name,'value':value})
        for root in c.models:
            if root in defs and root in ['StoredContext','StoredProposal','Checked','StoredOperation','ApprovalEvidence','AssessmentEnvelope','AssessmentSelection','AssessmentReceipt','Cursor','Cancellation','ReservedRecord','SavedDraft','ImportOrigin','ImportAdmission','ImportPreview','ArchiveManifest']:
                extra.append({'name':'workflow:'+root,'model':root,'value':sample(defs[root],defs)})
        for row in extra:
            rid=writer.put(row['model'],row['value'])
            db.execute('INSERT INTO proof_roots VALUES (?,?,?,?)',(row['name'],row['model'],rid,hashlib.sha256(canonical(row['value'])).hexdigest()))
            if row['name'].startswith('workflow:') and row['model'] not in ['ImportPreview','ArchiveManifest']:
                db.execute('INSERT INTO workflow_entries (key,family,digest,digest_recipe,'+q(row['model'])+') VALUES (?,?,?,?,?)',(row['name'],row['model'],hashlib.sha256(canonical(row['value'])).hexdigest(),'workflow-canonical',rid))
        content='é🌲 source bytes, not application metadata'.encode()
        db.execute('INSERT INTO source_content VALUES (?,?,?,?)',(hashlib.sha256(content).hexdigest(),len(content),content,hashlib.sha256(canonical(content.decode())).hexdigest()))
        oracle=tmp/'extra.json';oracle.write_text(json.dumps(extra,ensure_ascii=False))
        # Fail-closed constraints: required value, invalid discriminator, missing FK.
        rejected=[]
        for label,sql in [('required','INSERT INTO r_payload_v0 (names__state) VALUES (0)'),('discriminator','INSERT INTO r_payload (variant) VALUES (9999)'),('foreign-key','INSERT INTO r_payload (variant,v0) VALUES (0,999999)'),('immutable-workflow',"DELETE FROM workflow_entries"),('immutable-body',"UPDATE r_value_v0 SET text='mutated'")]:
            try:db.execute(sql)
            except sqlite3.IntegrityError:rejected.append(label)
            else:raise AssertionError(label)
        db.commit();db.close()
        audit=subprocess.run(['python3',str(HERE/'independent_audit.py'),str(dbpath),str(HERE/'canonical-oracle.json'),str(oracle)],capture_output=True,text=True,check=True)
        proof=json.loads(audit.stdout);proof['constraint_rejections']=rejected
        # SQLite snapshot/restore includes every typed row; files are disposable.
        src=sqlite3.connect(dbpath);backup=sqlite3.connect(tmp/'backup.sqlite');src.backup(backup);backup.close();src.close()
        again=subprocess.run(['python3',str(HERE/'independent_audit.py'),str(tmp/'backup.sqlite'),str(HERE/'canonical-oracle.json'),str(oracle)],capture_output=True,text=True,check=True)
        assert json.loads(again.stdout)==json.loads(audit.stdout)
        proof['backup_reopen']='same independent result'
        changed=sqlite3.connect(tmp/'backup.sqlite');changed.execute('DROP TRIGGER r_value_v0_no_update');changed.execute("UPDATE r_value_v0 SET text='tampered' WHERE __row_id=(SELECT min(__row_id) FROM r_value_v0)");changed.commit();changed.close()
        tamper=subprocess.run(['python3',str(HERE/'independent_audit.py'),str(tmp/'backup.sqlite'),str(HERE/'canonical-oracle.json'),str(oracle)],capture_output=True,text=True)
        assert tamper.returncode!=0
        proof['tampered_value']='independent readback rejected'
        fault=sqlite3.connect(dbpath);before=fault.execute('SELECT count(*) FROM proof_roots').fetchone()[0]
        try:
            fault.execute("INSERT INTO proof_roots VALUES ('interrupted','Payload',1,'discard')")
            raise RuntimeError('injected before publication')
        except RuntimeError:fault.rollback()
        assert fault.execute('SELECT count(*) FROM proof_roots').fetchone()[0]==before
        fault.close();proof['interrupted_transaction']='no published rows'
        proof['semantic_examples']=semantic_examples(tmp)
        proof['installation']=installation_examples(tmp)
        proof['scope']='disposable decision prototypes; no production migration, MCP admission or evaluator qualification'
        (HERE/'proof-results.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2)+'\n')
        print(json.dumps(proof,ensure_ascii=False))


def sample_model(models,name,depth=0):
    d=models[name];k=d['kind']
    if k=='union':
        n=next((n for n in d['variants'] if models[n]['kind']=='null'),d['variants'][0])
        return sample_model(models,n,depth+1)
    if k=='object':return {key:sample_model(models,f['model'],depth+1) for key,f in d['fields'].items() if f['required']}
    if k=='tuple':return [sample_model(models,f['model'],depth+1) for f in d['fields'].values()]
    if k=='array':return []
    if k=='map':return {}
    if k=='null':return None
    if 'const' in d:return d['const']
    if 'enum' in d:return d['enum'][0]
    if k=='boolean':return True
    if k in ('integer','number'):return max(1,d.get('minimum',1))
    pat=d.get('pattern','')
    if pat.startswith('^') and '_[' in pat:return pat[1:pat.index('[')]+'0'*23+'1'
    if '64' in pat:return 'a'*64
    return '1' if any(x in pat for x in ('0-9','\\d')) else 'é🌲 sample'

# Implemented below: handwritten Cedar/Pistol storage/resolution oracle.


def semantic_examples(tmp):
    """Explicit authored states; does not call/extend any evaluator."""
    c=build();defs=contracts();path=tmp/'examples.sqlite'
    db=sqlite3.connect(path);db.executescript((HERE/'typed.sql').read_text());db.executescript((HERE/'kernel.sql').read_text());db.executescript((HERE/'semantic.sql').read_text())
    w=Writer(db,c.models)
    universe='unv_'+'0'*23+'1';cont='cont_'+'0'*23+'1'
    names=['Tree','Cedar','Western red cedar','Gun','Pistol','Revolver','Service pistol','Cedar One','Pistol A','Pistol B','Objective','World A','World B','grows','hazard','height','rounds','start A','shot A','refill A','holder','Person','Ambiguous','Conflicting Cedar','foot','Story clock','opposition policy']
    ids={name:'rec_'+format(i+1,'024x') for i,name in enumerate(names)}
    db.execute('INSERT INTO universes VALUES (?,1,?)',(universe,'Cedar and Pistol review'))
    db.execute('PRAGMA defer_foreign_keys=ON')
    for n in names:
        kind='entity_type' if n in names[:7] else 'represented_context' if n=='Objective' else 'world' if n.startswith('World ') else 'rule' if n=='opposition policy' else 'unit' if n=='foot' else 'calendar' if n=='Story clock' else 'property' if n in ['grows','hazard','height','rounds','holder'] else 'event' if n in ['start A','shot A','refill A'] else 'entity'
        db.execute('INSERT INTO record_identities VALUES (?,?,?)',(universe,ids[n],kind))
    revisions=['rev_'+format(i+1,'024x') for i in range(4)]
    db.execute('INSERT INTO continuities VALUES (?,?,?,NULL)',(universe,cont,revisions[-1]))
    for i,rev in enumerate(revisions):
        db.execute('INSERT INTO commits VALUES (?,?,?,?,?,?,?,?,?)',(universe,rev,cont,revisions[i-1] if i else None,i,'review-author','explicit authored example','storage proof',hashlib.sha256(('authored example '+str(i)).encode()).hexdigest()))
    seq=0;membership={};versions={};expected_versions=[];import_evidence=[]
    def record(name,kind,model,value,revision=0):
        nonlocal seq
        seq+=1;ver='ver_'+format(seq,'024x')
        body=value if 'record_kind' in value else {'record_kind':kind,**value}
        rid=w.put('Payload',body)
        digest=hashlib.sha256((kind+':').encode()+canonical(body)).hexdigest()
        db.execute('INSERT INTO record_versions VALUES (?,?,?,?,?,?)',(universe,ver,ids[name],kind,rid,digest))
        if name=='Ambiguous':
            original={k:v for k,v in body.items() if k not in ('classification','classificationResolution')}
            original['types']=[ids['Tree'],ids['Gun']]
            source_digest=hashlib.sha256((kind+':v1:v1:').encode()+canonical(original)).hexdigest()
            db.execute('INSERT INTO import_record_digest VALUES (?,?,?,?)',(universe,ver,source_digest,digest))
            import_evidence.append({'version':ver,'source_body':original,'source_digest':source_digest,'normalized_digest':digest})

        prior=membership.get(ids[name]);membership[ids[name]]=ver;versions[name]=ver
        db.execute('INSERT INTO commit_changes VALUES (?,?,?,?,?)',(universe,revisions[revision],ids[name],prior,ver))
        expected_versions.append({'version':ver,'identity':ids[name],'kind':kind,'value':body,'digest':digest})
        return ver
    for name,parent,scope in [('Tree',None,'universe'),('Cedar','Tree','universe'),('Western red cedar','Cedar','worlds'),('Gun',None,'universe'),('Pistol','Gun','universe'),('Revolver','Gun','universe'),('Service pistol','Pistol','universe')]:
        value={'namespace':'author','key':name,'labels':{'en':name},'classificationExecutable':True,'name':name,'parent':ids[parent] if parent else None,'parentResolution':'resolved' if parent else 'root','applicability':{'kind':'universe_wide' if scope=='universe' else scope,**({'world_ids':['wld_'+format(names.index('World A')+1,'024x')]} if scope=='worlds' else {})}}
        ver=record(name,'entity_type','Payload',value)
        db.execute('INSERT INTO type_definition VALUES (?,?,?,?,?,?,?)',(universe,ver,ids[name],name,ids[parent] if parent else None,'resolved' if parent else 'root',scope))
        if scope=='worlds':db.execute('INSERT INTO type_world VALUES (?,?,0,?)',(universe,ver,ids['World A']))
    def instance(name,classification,revision=0,label=None):
        value={'names':[{'text':label or name,'validity':{'kind':'unspecified'}}], 'worldAssociations':[], 'labels':{'en':label or name}, 'metadata':{},'classification':ids[classification] if classification else None,'classificationResolution':'resolved' if classification else 'unclassified'}
        ver=record(name,'entity','Payload',value,revision)
        db.execute('INSERT INTO instance_classification VALUES (?,?,?,?,?)',(universe,ver,ids[name],ids[classification] if classification else None,'resolved' if classification else 'unclassified'))
    instance('Cedar One','Tree');instance('Pistol A','Pistol');instance('Pistol B','Pistol');instance('Person',None)
    instance('Cedar One','Western red cedar',1);instance('Pistol A','Service pistol',2,'Renamed pistol')
    legacy=sample(defs['Entity'],defs);legacy.update(classification=None,classificationResolution='ambiguous',record_kind='entity')
    ver=record('Ambiguous','entity','Payload',legacy)
    db.execute('INSERT INTO instance_classification VALUES (?,?,?,NULL,?)',(universe,ver,ids['Ambiguous'],'ambiguous'))
    for i,t in enumerate(['Tree','Gun']):db.execute('INSERT INTO classification_evidence VALUES (?,?,?,?,?)',(universe,ver,'membership',i,ids[t]))
    # Facts are real typed proposition/assertion bodies, with separate identities and versions.
    fact_seq=100
    fact_index=[]
    def fact(subject,predicate,value,mode,at=0,until=None,world='World A',polarity='support',context='Objective',revision=0):
        nonlocal fact_seq
        fact_seq+=1;pname='prop-'+str(fact_seq);aname='assert-'+str(fact_seq)
        for n,k in [(pname,'proposition'),(aname,'assertion')]:
            ids[n]='rec_'+format(len(ids)+1,'024x');db.execute('INSERT INTO record_identities VALUES (?,?,?)',(universe,ids[n],k))
        rr=lambda n:{'universe':universe,'record':ids[n]}
        prop={'record_kind':'proposition','subject':rr(subject),'predicate':rr(predicate),'value':value,'quantification':'particular','context':rr(context)}
        pv=record(pname,'proposition','Payload',prop,revision)
        assertion={'proposition':rr(pname),'polarity':polarity,'scope':{'applicability':{'kind':'worlds','world_ids':['wld_'+format(names.index(world)+1,'024x')]} if world else {'kind':'unspecified'},'context':rr(context)},
            'validity':{'kind':'calendar_interval','calendar':'cal_'+ids['Story clock'].split('_')[1],'start':{'kind':'exact','value':str(at)},'end':{'kind':'exact','value':str(until)} if until is not None else {'kind':'unbounded'}},
            'persistence':'explicit_interval','precision':'exact','basis':{'kind':'author_decision','note':'Explicit example fact'},'attributeMode':mode}
        av=record(aname,'assertion','Payload',assertion,revision)
        if mode!='instance':db.execute('INSERT INTO definition_attribute VALUES (?,?,?,?,?)',(universe,av,ids[subject],ids[predicate],mode))
        fact_index.append({'subject':subject,'predicate':predicate,'assertion':av,'proposition':pv})
        return av
    fact('Tree','grows',{'kind':'boolean','value':True},'shared')
    fact('Cedar','grows',{'kind':'boolean','value':False},'shared',at=2,revision=2)
    fact('Tree','hazard',{'kind':'boolean','value':False},'shared',at=2,world=None,revision=2)
    fact('Cedar One','hazard',{'kind':'boolean','value':True},'instance')
    fact('Cedar One','height',{'kind':'quantity','value':{'kind':'decimal','digits':'30.00'},'unit':'unit_'+ids['foot'].split('_')[1]},'instance',at=1,revision=1)
    fact('Pistol A','rounds',{'kind':'integer','digits':'7'},'instance',until=1)
    fact('Pistol A','rounds',{'kind':'integer','digits':'6'},'instance',at=1,until=2,revision=1)
    fact('Pistol A','rounds',{'kind':'integer','digits':'0'},'instance',at=2,until=3,revision=2)
    fact('Pistol A','rounds',{'kind':'integer','digits':'2'},'instance',at=3,revision=3)
    fact('Pistol B','rounds',{'kind':'integer','digits':'3'},'instance')
    initial=fact('Gun','rounds',{'kind':'integer','digits':'7'},'initial_value')
    db.execute('INSERT INTO initialization_receipt VALUES (?,?,?,?,?,?,?)',(universe,ids['Pistol A'],ids['start A'],ids['rounds'],versions['Gun'],initial,revisions[0]))
    for label in ['World A','World B','Objective','grows','hazard','height','rounds','holder','start A','shot A','refill A','foot','Story clock','opposition policy']:
        # These references need real version bodies for an integrity/closure audit.
        kind=db.execute('SELECT kind FROM record_identities WHERE id=?',(ids[label],)).fetchone()[0]
        specimen=copy.deepcopy(next(x['value'] for x in fixtures(c) if x['name']=='family:'+kind))
        if kind=='property':
            specimen['key']=label
            specimen['value']={'kind':'boolean'} if label in ['grows','hazard'] else {'kind':'integer'} if label=='rounds' else {'kind':'quantity','unit':'unit_'+ids['foot'].split('_')[1]} if label=='height' else {'kind':'entity_ref','subject_types':[]}
        if kind=='unit':specimen.update(key='foot',symbol='ft',dimension='length')
        if kind=='calendar':specimen.update(key='Story clock',unitStructure={'tick':'authored integer tick'},epoch='0')
        if kind=='represented_context':specimen.update(universe=universe,chronology={'calendar':'cal_'+ids['Story clock'].split('_')[1],'system':{'kind':'fictional','tick_label':'tick','ticks_per_month':None},'first_interaction':'0','current':'3'})
        if kind=='event':specimen['time']={'kind':'exact','calendar':'cal_'+ids['Story clock'].split('_')[1],'value':'0' if label=='start A' else '1' if label=='shot A' else '3'}
        record(label,kind,'Payload',specimen)
    for record_id,version in membership.items():db.execute('INSERT INTO head_membership VALUES (?,?,?,?)',(universe,cont,record_id,version))
    db.execute('INSERT INTO snapshot_membership VALUES (?,?,?)',(universe,revisions[-1],hashlib.sha256(canonical(membership)).hexdigest()))
    for record_id,version in membership.items():db.execute('INSERT INTO snapshot_member VALUES (?,?,?,?)',(universe,revisions[-1],record_id,version))
    db.execute('INSERT INTO operation_receipts VALUES (?,?,?,?,?,?)',(universe,'review-author','commit','review-key','a'*64,revisions[3]))
    db.execute('INSERT INTO world_name_reservations VALUES (?,?,?,?)',(universe,'world a',ids['World A'],revisions[0]))
    db.commit();db.close()
    # Independent expected results authored without calling the resolver.
    oracle={'versions':expected_versions,'names':ids,'facts':fact_index,'membership':membership,'universe':universe,'continuity':cont,'revisions':revisions,
        'expected':{'cedar_ancestry':['Western red cedar','Cedar','Tree'],'cedar_grows':True,'cedar_hazard':True,'cedar_height_digits':'30.00',
            'pistol_a_rounds':['7','6','0','2'],'pistol_b_rounds':['3','3','3','3'],'pistol_a_ancestry':['Service pistol','Pistol','Gun'],
            'ambiguity_status':'ambiguous','world_b_definition':'inapplicable','unknown_before_height':True,'initial_value_is_current_state':False,'inherited_conflict_at_t2':True,'unspecified_applicability_at_t2':'unresolved'}}
    oracle['import_evidence']=import_evidence
    (HERE/'semantic-oracle.json').write_text(json.dumps(oracle,ensure_ascii=False,indent=2)+'\n')
    audited=subprocess.run(['python3',str(HERE/'verify_examples.py'),str(path),str(HERE/'semantic-oracle.json')],capture_output=True,text=True)
    if audited.returncode:raise RuntimeError(audited.stderr)
    result=json.loads(audited.stdout)
    result['logical_export']=logical_export(tmp,path,oracle,c)
    return result


def installation_examples(tmp):
    path=tmp/'installation.sqlite';db=sqlite3.connect(path);db.executescript((HERE/'installation.sql').read_text())
    db.execute('INSERT INTO profiles VALUES (?,?,1,0)',('review-author','a'*64));db.execute('INSERT INTO profiles VALUES (?,?,0,0)',('writer','b'*64))
    db.execute('INSERT INTO catalog VALUES (?,?,?,?,?)',('universe','Review','/disposable/review','device','inode'))
    db.execute('INSERT INTO grants VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',('writer','universe','listed',1,1,0,'listed','all','listed','1792000000',1,0))
    db.execute('INSERT INTO grant_worlds VALUES (?,?,?,?)',('writer','universe',0,'world-a'))
    db.execute('INSERT INTO grant_continuities VALUES (?,?,?,?)',('writer','universe',0,'main'))
    db.execute('INSERT INTO audit VALUES (?,?,?,?)',(17,'review-author','grant_scope','writer:universe'))
    db.commit();db.close()
    audit=subprocess.run(['python3',str(HERE/'verify_installation.py'),str(path)],capture_output=True,text=True,check=True)
    return json.loads(audit.stdout)

def logical_export(tmp,source_path,oracle,c):
    # New trusted schema, bounded known rows; never dump/execute input SQL.
    archive=tmp/'export.sqlite';source=sqlite3.connect(source_path);target=sqlite3.connect(archive)
    for file in ['typed.sql','kernel.sql','semantic.sql','workflow.sql','export.sql']:
        target.executescript((HERE/file).read_text())
    target.execute('DELETE FROM projection_state');target.execute('BEGIN') if not target.in_transaction else None
    target.execute('PRAGMA defer_foreign_keys=ON')
    allowed=[r[0] for r in source.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name") if not r[0].startswith(('sqlite_','search_index'))]
    for table in allowed:
        columns=[r[1] for r in source.execute('PRAGMA table_info('+q(table)+')')]
        rows=source.execute('SELECT '+','.join(map(q,columns))+' FROM '+q(table)).fetchall()
        if rows:target.executemany('INSERT INTO '+q(table)+' ('+','.join(map(q,columns))+') VALUES ('+','.join('?' for _ in columns)+')',rows)
    target.commit()
    # The writer's checksum calculation is intentionally separate from the verifier.
    entries=[]
    for table in sorted(r[0] for r in target.execute("SELECT name FROM sqlite_master WHERE type='table'") if not r[0].startswith(('sqlite_','search_index')) and r[0] not in ['archive_integrity','r_archive_manifest']):
        schema=target.execute('PRAGMA table_info('+q(table)+')').fetchall();columns=[r[1] for r in schema]
        primary=[r[1] for r in sorted(schema,key=lambda r:r[5]) if r[5]] or columns
        for record in target.execute('SELECT '+','.join(map(q,columns))+' FROM '+q(table)+' ORDER BY '+','.join(map(q,primary))):
            cells=[]
            for value in record:
                if value is None:cells.append(['null',None])
                elif isinstance(value,bytes):cells.append(['bytes',value.hex()])
                elif isinstance(value,int):cells.append(['integer',value])
                else:cells.append(['text',value])
            entries.append([table,columns,cells])
    digest=hashlib.sha256(json.dumps(entries,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
    manifest={'format':'universe-relational','universe':oracle['universe'],'name':'Cedar and Pistol review','complete':True,'omitted_records':0,'includes_history':True,'includes_workflow':True}
    row=Writer(target,c.models).put('ArchiveManifest',manifest)
    target.execute('INSERT INTO archive_integrity VALUES (1,?,?,?,?,?,?)',(row,'typed-row-stream',digest,len(entries),'historical_evidence_only',hashlib.sha256(canonical(manifest)).hexdigest()))
    target.commit();target.close();source.close()
    result=subprocess.run(['python3',str(HERE/'verify_export.py'),str(archive)],capture_output=True,text=True,check=True)
    readback=subprocess.run(['python3',str(HERE/'verify_examples.py'),str(archive),str(HERE/'semantic-oracle.json')],capture_output=True,text=True,check=True)
    assert json.loads(readback.stdout)['receipt']=='exact'
    return json.loads(result.stdout)

if __name__=='__main__':run()
