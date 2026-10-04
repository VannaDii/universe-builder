#!/usr/bin/env python3
"""Independent source-to-mapping coverage and DDL-install audit; no author data."""
import hashlib
import json
import re
import sqlite3
from pathlib import Path

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
text=(HERE/'inventory.md').read_text()
models=json.loads((HERE/'catalog.json').read_text())['models']
source_files=list((ROOT/'crates/universe-store/src').glob('*.rs'))+list((ROOT/'crates/universe-service/src').glob('*.rs'))+list((ROOT/'crates/universe-store/src').glob('*.sql'))+[ROOT/'crates/universe-protocol/src/installation.rs',ROOT/'crates/universe-client/src/installation.rs',ROOT/'crates/universe-protocol/src/response.rs',ROOT/'crates/universe-protocol/src/assessment.rs',ROOT/'crates/universe-protocol/src/validation_scope.rs',ROOT/'crates/universe-domain/src/records.rs',ROOT/'crates/universe-domain/src/canonical.rs']+list((ROOT/'contracts').glob('*.json'))
source_files=sorted(set(source_files))
hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files}
tables=set()
for name in ['schema_v0.sql','schema_v1.sql','schema_v2.sql']:
    sql=(ROOT/'crates/universe-store/src'/name).read_text()
    tables.update(re.findall(r'CREATE (?:VIRTUAL )?TABLE (?:IF NOT EXISTS )?(\w+)',sql))
registry=(ROOT/'crates/universe-service/src/registry.rs').read_text()
tables.update(re.findall(r'CREATE TABLE IF NOT EXISTS (\w+)',registry))
missing=sorted(t for t in tables if not re.search(r'\b'+t+r'\b',text))
assert not missing,missing
payload=json.loads((HERE/'source-contracts.json').read_text())['Payload']['oneOf']
kinds=[s['properties']['record_kind']['const'] for s in payload]
assert all(re.search(r'\b'+k+r'\b',text) for k in kinds)
assert len(kinds)==38
assert len(json.loads((HERE/'source-contracts.json').read_text())['DomainOperation']['oneOf'])==50
# Install the entire proposed DDL, including historical headers and installation schema.
db=sqlite3.connect(':memory:')
for file in ['typed.sql','kernel.sql','workflow.sql','semantic.sql','export.sql']:
    sql=(HERE/file).read_text();assert not re.search(r'\b(?:payload|evidence|result|membership)\s+BLOB\b',sql,re.I),file
    db.executescript(sql)
assert not db.execute('PRAGMA foreign_key_check').fetchall()
assert not db.execute("SELECT 1 FROM sqlite_master WHERE name='schema_meta'").fetchone()
for table in [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")]:
    assert not {'schema_version','payload_schema_version','storage_layout','format_version'} & {r[1] for r in db.execute('PRAGMA table_info("'+table+'")')}, table
for name,model in models.items():
    assert not re.search(r'V[0-9]+$',name),name
    fields=model.get('fields',{})
    if {'namespace','key','classificationExecutable'} <= fields.keys():
        assert 'parents' not in fields and {'parent','parentResolution','applicability'} <= fields.keys(),name
    if {'names','metadata','worldAssociations'} <= fields.keys():
        assert 'types' not in fields and {'classification','classificationResolution'} <= fields.keys(),name
assert not (HERE/'legacy-v0.sql').exists()

install=sqlite3.connect(':memory:');install.executescript((HERE/'installation.sql').read_text())
for table in ['profiles','grants','catalog','audit']:
    assert not db.execute('SELECT 1 FROM sqlite_master WHERE name=?',(table,)).fetchone()
    assert install.execute('SELECT 1 FROM sqlite_master WHERE name=?',(table,)).fetchone()
# The profile format has concrete DDL as a separate protected database.
profile=sqlite3.connect(':memory:');profile.executescript((HERE/'credential.sql').read_text())
result={'source_baseline':'56f7b6b6e9a770c6c2dd1fc5f938f2b6e63f1b73','canonical_families':len(kinds),'operation_variants':50,'persisted_source_tables_mapped':sorted(tables),'source_table_omissions':missing,'package_ddl':'all five batches installed','installation_ddl':'installed separately','credential_ddl':'installed separately; no real credential','no_application_payload_blobs':True,'single_normative_model':'verified; no parallel routes or prerelease version fields','source_sha256':hashes}
(HERE/'inventory-results.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='source_sha256'}))
