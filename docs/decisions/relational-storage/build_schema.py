#!/usr/bin/env python3
"""Generate explicit, closed relational DDL for the normative unreleased model; no production writes.
JSON files here describe contracts/proofs, never prototype application storage.
"""
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

def obj(**fields):
    return {'type': 'object', 'properties': fields, 'required': list(fields), 'additionalProperties': False}

def ref(name): return {'$ref': '#/$defs/' + name}
def arr(name): return {'type': 'array', 'items': ref(name)}
def nullable(s): return {'anyOf': [s, {'type': 'null'}]}
S = {'type': 'string'}
I = {'type': 'integer', 'minimum': 0}
B = {'type': 'boolean'}

def contracts():
    defs = {}
    def collect(value):
        if isinstance(value, dict):
            for k, v in value.get('$defs', {}).items():
                if k in defs and defs[k] != v:
                    # Contracts contain narrower assessment-specific schema descriptions.
                    # Current domain schemas below own the canonical families.
                    pass
                defs[k] = v
            for child in value.values(): collect(child)
        elif isinstance(value, list):
            for child in value: collect(child)
    for file in sorted((ROOT / 'contracts').glob('*.json')):
        collect(json.loads(file.read_text()))
    live = json.loads((HERE / 'source-contracts.json').read_text())
    for name, schema in live.items():
        defs.update(schema.get('$defs', {}))
        defs[name] = {k:v for k,v in schema.items() if k not in ('$defs', '$schema')}
    # Private persisted structs do not have public schema derives. Exact source fields.
    defs.update({
        'Footprint': obj(worlds=arr('WorldId'), shared=B, protected=B),
        'Assignment': obj(record_id=ref('RecordId'), expected=nullable(ref('RecordVersionId')), next=nullable(ref('RecordVersion'))),
        'CommitInput': obj(universe=ref('UniverseId'), continuity=ref('ContinuityId'), expected_head=ref('RevisionId'), principal=ref('PrincipalId'), decision=S, reason=S, idempotency_key=S, changes=arr('Assignment')),
        'StoredContext': obj(owner=S, scope=S, expires=I, frame=ref('Frame')),
        'StoredProposal': obj(proposal=ref('Proposal'), owner=S, author_origin=B, changes=arr('Assignment'), footprint=ref('Footprint')),
        'ValidationCapture': obj(selection=ref('AssessmentSelection'), assessment=ref('AssessmentState'), submitted_input=ref('SubmittedInput'), head=ref('RevisionId'), latest_proposal_key=nullable(S), authority_digest=S, authority_sequence=nullable({'type':'integer'})),
        'Checked': obj(proposal_digest=S, validation=ref('Validation'), admissible=B, report=nullable(ref('ValidationV3')), capture=nullable(ref('ValidationCapture'))),
        'OperationStatusInternal': obj(validation=nullable(ref('Validation')), failure=nullable(S), operation_id=ref('OperationId'), kind=ref('OperationKind'), state=ref('OperationState'), proposal=nullable(ref('Proposal')), receipt=nullable(ref('CommitReceipt')), cancellation_requested=B),
        'StoredOperation': obj(owner=S, digest=S, status=ref('OperationStatusInternal'), input=nullable(ref('CommitInput')), footprint=ref('Footprint'), validation_capture=nullable(ref('ValidationCapture'))),
        'ApprovalEvidence': obj(author=S, proposal=ref('ProposalRef'), validation_digest=S, evaluator=S),
        'AssessmentReceipt': obj(request_digest=S, selection=ref('AssessmentSelection'), envelope=nullable(ref('AssessmentEnvelope'))),
        'Cursor': obj(binding=S, offset=I),
        'Cancellation': obj(owner=S, cancelled=B),
        'ReservedRecord': obj(proposal_id=ref('ProposalId')),
        'DraftContent': obj(base_revision=ref('RevisionId'), represented_context=ref('RecordId'), operations=arr('DomainOperation'), rationale=S, proposal=nullable(ref('ProposalRef'))),
        'SavedDraft': obj(version=I, content=ref('DraftContent')),
        'ImportOrigin': obj(digest=S, source_universe=ref('UniverseId'), target_universe=ref('UniverseId'), complete=B, omitted_records=I),
        'ImportAdmission': obj(preview_id=ref('OperationId'), digest=S, universe_id=ref('UniverseId'), name=S, complete=B, omitted_records=I, imported=B),
        'ImportPreview': obj(id=ref('OperationId'), owner=S, source_digest=S, target=ref('UniverseId'), source=ref('UniverseId'), name=S, complete=B, omitted_records=I, records=I, includes_workflow=B),
        'ArchiveManifest': obj(format=S, universe=ref('UniverseId'), name=S, complete=B, omitted_records=I, includes_history=B, includes_workflow=B),
    })
    # Unreleased decisions replace the canonical model in place.
    def replace_model(schema):
        if isinstance(schema, list): return [replace_model(x) for x in schema]
        if not isinstance(schema, dict): return schema
        schema = {k:replace_model(v) for k,v in schema.items()}
        fields = schema.get('properties', {})
        required = schema.get('required', [])
        if {'namespace','key','labels','classificationExecutable'} <= fields.keys():
            fields.pop('parents', None)
            fields.update(name=S, parent=nullable(ref('RecordId')), parentResolution={'type':'string','enum':['root','resolved','ambiguous']}, applicability=ref('Applicability'))
            schema['required'] = [k for k in required if k!='parents'] + ['name','parent','parentResolution','applicability']
        if {'names','types','worldAssociations','metadata'} <= fields.keys():
            fields.pop('types')
            fields.update(classification=nullable(ref('RecordId')), classificationResolution={'type':'string','enum':['unclassified','resolved','ambiguous']})
            schema['required'] = [k for k in required if k!='types'] + ['classification','classificationResolution']
        if {'proposition','polarity','scope','validity','basis'} <= fields.keys():
            fields['attributeMode']={'type':'string','enum':['instance','shared','initial_value']}
            schema['required'] = required + ['attributeMode']
        if 'payload_schema_version' in fields:
            fields.pop('payload_schema_version')
            schema['required'] = [k for k in required if k!='payload_schema_version']
        return schema
    defs = replace_model(defs)
    # Remove superseded pre-release suffixes from the normative contract names/tags.
    aliases={'ValidationV3':'ValidationReport','OperationStatusV3':'OperationStatusReport',
             'SourceAssessmentV1':'SourceAssessment','SourceValidationBinding':'SourceValidationBinding'}
    def rename(value):
        if isinstance(value,dict): return {aliases.get(k,k):rename(v) for k,v in value.items()}
        if isinstance(value,list): return [rename(v) for v in value]
        if isinstance(value,str):
            if value.startswith('#/$defs/'):return '#/$defs/'+aliases.get(value.rsplit('/',1)[1],value.rsplit('/',1)[1])
            return re.sub(r'_v[0-9]+$', '', value)
        return value
    defs=rename(defs)
    # Serde defaults/omissions of private structs: retention needs all three states.
    for name, keys in {'Checked':['report','capture'], 'StoredOperation':['validation_capture'],
                       'ValidationCapture':['authority_sequence'], 'DraftContent':['proposal'],
                       'Cancellation':['owner'], 'OperationStatusInternal':['validation','failure']}.items():
        defs[name]['required'] = [k for k in defs[name]['required'] if k not in keys]
    # Initialization provenance is an additional closed evidence branch. Existing
    # branch ordinals and canonical families retain their exact representation.
    defs['EvidenceBasis']['oneOf'].append(obj(
        kind={'type':'string','const':'instance_initialization'},
        start=ref('VersionRef'), definition=ref('VersionRef'), source_revision=ref('RevisionId')))
    defs['DomainOperation']['oneOf'].append(obj(
        kind={'type':'string','const':'initialize_instance'}, client_ref=S,
        instance=ref('RecordRef'), start=ref('RecordRef'), definition=ref('VersionRef'),
        scope=ref('Scope'), validity=ref('Validity')))
    # Append the new closed mutation without renumbering historical operation branches.
    defs['DomainOperation']['oneOf'].append(obj(
        kind={'type':'string','const':'revise_item_power'},record=ref('RecordRef'),
        expected_version=ref('RecordVersionId'),replacement=ref('ItemPower'),rationale=S))
    defs['DomainOperation']['oneOf'].append(obj(
        kind={'type':'string','const':'revise_attitude'},record=ref('RecordRef'),
        expected_version=ref('RecordVersionId'),replacement=ref('EpistemicAttitude'),rationale=S))
    defs['DomainOperation']['oneOf'].append(obj(kind={'type':'string','const':'revise_communication'},record=ref('RecordRef'),expected_version=ref('RecordVersionId'),replacement=ref('Communication'),rationale=S))
    defs['DomainOperation']['oneOf'].append(obj(kind={'type':'string','const':'revise_interpretation'},record=ref('RecordRef'),expected_version=ref('RecordVersionId'),interpretation={'anyOf':[ref('RecordRef'),{'type':'null'}]},rationale=S))
    defs['DomainOperation']['oneOf'].append(obj(kind={'type':'string','const':'withdraw_event'},record=ref('RecordRef'),expected_version=ref('RecordVersionId'),rationale=S))
    defs['DomainOperation']['oneOf'].append(obj(kind={'type':'string','const':'revise_scene'},record=ref('RecordRef'),expected_version=ref('RecordVersionId'),replacement=ref('SceneRef'),rationale=S))
    # Story secrecy retains the existing payload fields and appends operation
    # branches so every earlier stored operation keeps its ordinal.
    defs['Secret'] = obj(scope=arr('RecordRef'), fictionalKnowers=arr('RecordRef'),
        readerDisclosed=B, concealment=nullable(S), validity=ref('Validity'))
    defs['Secret']['required'].remove('concealment')
    defs['DomainOperation']['oneOf'].append(obj(kind={'type':'string','const':'create_secret'},client_ref=S,record=ref('Secret')))
    defs['DomainOperation']['oneOf'].append(obj(kind={'type':'string','const':'revise_secret'},record=ref('RecordRef'),expected_version=ref('RecordVersionId'),replacement=ref('Secret')))
    return defs


def ident(name): return re.sub(r'[^a-z0-9_]', '_', re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower())
def q(name): return '"' + name.replace('"', '""') + '"'

class Compiler:
    def __init__(self, definitions):
        self.defs = definitions
        self.models = {}
    def model(self, schema, name):
        while '$ref' in schema:
            name = schema['$ref'].rsplit('/', 1)[1]
            schema = self.defs[name]
        if name in self.models: return name
        self.models[name] = {'table': 'r_' + ident(name)}
        d = self.models[name]
        alternatives = schema.get('oneOf', schema.get('anyOf'))
        if alternatives:
            d.update(kind='union', variants=[self.model(s, name + '_v' + str(i)) for i,s in enumerate(alternatives)])
        elif schema.get('type') == 'object' and 'properties' in schema:
            d.update(kind='object', fields={})
            for key, s in schema['properties'].items():
                d['fields'][key] = {'model':self.model(s, name+'_'+key), 'required':key in schema.get('required', [])}
        elif schema.get('type') == 'object':
            additional = schema.get('additionalProperties')
            if not isinstance(additional, dict): raise ValueError(('unbounded object forbidden', name, schema))
            d.update(kind='map', item=self.model(additional, name+'_item'))
        elif schema.get('type') == 'array' and 'prefixItems' in schema:
            d.update(kind='tuple', fields={str(i): {'model':self.model(s, name+'_p'+str(i)), 'required':True} for i,s in enumerate(schema['prefixItems'])})
        elif schema.get('type') == 'array':
            if 'items' not in schema: raise ValueError(('untyped array', name))
            d.update(kind='array', item=self.model(schema['items'], name+'_item'))
        elif schema.get('type') in ('string','integer','number','boolean','null'):
            d.update(kind=schema['type'])
            for key in ('const','enum','pattern','minimum','maximum'):
                if key in schema: d[key] = schema[key]
        elif isinstance(schema.get('type'), list):
            d.update(kind='union', variants=[self.model({'type':t}, name+'_v'+str(i)) for i,t in enumerate(schema['type'])])
        else: raise ValueError(('unsupported closed contract', name, schema))
        return name
    def scalar(self, name): return self.models[name]['kind'] in ('string','integer','number','boolean','null')
    def ddl(self):
        statements = ['-- NORMATIVE UNRELEASED MODEL. One relational schema; not a production migration.','PRAGMA foreign_keys=ON;']
        for name,d in self.models.items():
            if self.scalar(name): continue
            table = d['table']; cols = ['__row_id INTEGER PRIMARY KEY']
            if d['kind'] in ('object','tuple'):
                for key, f in d['fields'].items():
                    m = self.models[f['model']]; st = q(key+'__state'); col=q(key)
                    nullable = m['kind']=='null' or (m['kind']=='union' and any(self.models[v]['kind']=='null' for v in m['variants']))
                    states = ([0] if not f['required'] else []) + ([1] if nullable else []) + [2]
                    cols.append(f"{st} INTEGER NOT NULL CHECK({st} IN ({','.join(map(str,states))}))")
                    typ = 'INTEGER' if m['kind']=='boolean' else 'TEXT' if self.scalar(f['model']) else 'INTEGER'
                    cols.append(f'{col} {typ}' + ('' if self.scalar(f['model']) else f' REFERENCES {q(m["table"])}(__row_id)'))
                    cols.append(f'CHECK(({st}=2 AND {col} IS NOT NULL) OR ({st} IN (0,1) AND {col} IS NULL))')
                    if m['kind']=='boolean': cols.append(f'CHECK({col} IN (0,1))')
                    if 'const' in m: cols.append(f'CHECK({col}={sql_literal(m["const"])})')
                    if 'enum' in m: cols.append(f'CHECK({col} IN ({",".join(sql_literal(v) for v in m["enum"])}))')
            elif d['kind'] == 'union':
                cols.append(f'variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND {len(d["variants"])-1})')
                for i,n in enumerate(d['variants']):
                    m=self.models[n]; typ='INTEGER' if m['kind']=='boolean' else 'TEXT' if self.scalar(n) else 'INTEGER'
                    cols.append(f'v{i} {typ}' + ('' if self.scalar(n) else f' REFERENCES {q(m["table"])}(__row_id)'))
                # One selected branch, including a branch representing explicit null.
                for i,n in enumerate(d['variants']):
                    cols.append(f'CHECK(variant={i} OR v{i} IS NULL)')
                    if self.models[n]['kind']!='null':cols.append(f'CHECK(variant!={i} OR v{i} IS NOT NULL)')
            cols = [s for s in cols if not s.startswith('CHECK(')] + [s for s in cols if s.startswith('CHECK(')]
            statements.append('CREATE TABLE '+q(table)+' (\n  '+',\n  '.join(cols)+'\n) STRICT;')
            if d['kind'] in ('array','map'):
                m=self.models[d['item']]; typ='INTEGER' if m['kind']=='boolean' else 'TEXT' if self.scalar(d['item']) else 'INTEGER'
                key='ordinal INTEGER NOT NULL CHECK(ordinal>=0)' if d['kind']=='array' else 'name TEXT NOT NULL'
                statements.append(f'CREATE TABLE {q(table+"_items")} (owner INTEGER NOT NULL REFERENCES {q(table)}(__row_id), {key}, item {typ}' + ('' if self.scalar(d['item']) else f' REFERENCES {q(m["table"])}(__row_id)') + f', PRIMARY KEY(owner,{"ordinal" if d["kind"]=="array" else "name"})) STRICT;')
        for name,d in self.models.items():
            if self.scalar(name):continue
            for table in [d['table']] + ([d['table']+'_items'] if d['kind'] in ('array','map') else []):
                for action in ['UPDATE','DELETE']:
                    statements.append(f"CREATE TRIGGER {q(table+'_no_'+action.lower())} BEFORE {action} ON {q(table)} BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;")
        return '\n\n'.join(statements)+'\n'

def sql_literal(v):
    if isinstance(v,bool): return str(int(v))
    if isinstance(v,(int,float)): return str(v)
    return "'"+str(v).replace("'","''")+"'"

ROOTS = ['Payload','DomainOperation','RecordVersion','StoredContext','StoredProposal','Checked','StoredOperation',
         'ApprovalEvidence','AssessmentEnvelope','AssessmentSelection','AssessmentReceipt','Cursor','Cancellation',
         'ReservedRecord','SavedDraft','ImportOrigin','ImportAdmission','ImportPreview','ArchiveManifest',
         'SourceValidationBinding']

def build():
    c=Compiler(contracts())
    # This contract is currently inline in assessment.rs, not a named public schema.
    c.defs['SourceValidationBinding'] = obj(kind=ref('ValidationBindingKind'), proposal=ref('ProposalRef'), base_frame=ref('Frame'), selection=ref('AssessmentSelection'), submitted_input=ref('SubmittedInput'), assessment_state=ref('AssessmentState'), execution_result_digest=S, evaluator_version=S)
    for root in ROOTS:c.model(ref(root),root)
    (HERE/'typed.sql').write_text(c.ddl())
    (HERE/'catalog.json').write_text(json.dumps({'roots':ROOTS,'models':c.models},ensure_ascii=False,indent=2)+'\n')
    lines=['# Exact field mapping','', 'Generated from current domain schemas and checked-in public contracts. The replacement model is normative before release. Private envelopes are explicitly specified in `build_schema.py`; DraftContent.operations uses typed operations. Superseded editor formats are one-time input concerns (see compatibility.md). `__state`: 0 absent, 1 explicit null, 2 value. Collections use child rows; an empty collection still has a header. Numeric wire tokens use decimal TEXT, never SQLite REAL.','', '| Contract | Table / scalar domain | Fields or links |','|---|---|---|']
    for name,d in c.models.items():
        desc=', '.join(f'{k} → {f["model"]}' for k,f in d.get('fields',{}).items()) or ', '.join(d.get('variants',[])) or d.get('item','') or d['kind']
        lines.append(f'| `{name}` | `{d["table"]}`' + (' (scalar column)' if c.scalar(name) else '') + f' | {desc} |')
    (HERE/'field-mapping.md').write_text('\n'.join(lines)+'\n')
    return c

if __name__=='__main__':
    c=build()
    print(f'{len(c.models)} closed models; {sum(not c.scalar(n) for n in c.models)} typed tables plus collection children')
