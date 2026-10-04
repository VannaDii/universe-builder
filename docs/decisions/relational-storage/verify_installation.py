#!/usr/bin/env python3
"""Independent installation readback; uses synthetic identities/hashes only."""
import json
import sqlite3
import sys

db=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True)
assert db.execute('PRAGMA integrity_check').fetchone()==('ok',)
assert not db.execute('PRAGMA foreign_key_check').fetchall()
assert db.execute('SELECT * FROM grants').fetchone()==('writer','universe','listed',1,1,0,'listed','all','listed','1792000000',1,0)
assert db.execute('SELECT world FROM grant_worlds').fetchall()==[('world-a',)]
# listed + zero rows denies all entity writes; all + zero rows permits all predicates.
assert db.execute('SELECT count(*) FROM grant_entities').fetchone()==(0,)
assert db.execute('SELECT continuity FROM grant_continuities').fetchall()==[('main',)]
assert db.execute('SELECT sequence,actor,action,target FROM audit').fetchone()==(17,'review-author','grant_scope','writer:universe')
assert db.execute('SELECT id,author,revoked FROM profiles ORDER BY id').fetchall()==[('review-author',1,0),('writer',0,0)]
print(json.dumps({'grant_round_trip':'exact','null_vs_empty_limits':'distinguished','authority_sequence':17,'synthetic_profiles':'preserved','production_credentials_used':False}))
