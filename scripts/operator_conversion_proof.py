#!/usr/bin/env python3
"""Disposable actual-CLI conversion with independent whole-data reconstruction.
No conversion implementation or Rust serializer is imported by this auditor.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
from relational_history import versions, workflows
from independent_audit import encoded

ROOT = Path(__file__).resolve().parents[1]
SCALARS = ('universes', 'record_identities', 'continuities', 'commits',
           'commit_changes', 'world_name_reservations', 'head_membership', 'operation_receipts')


def open_db(path):
    db = sqlite3.connect('file:' + str(path) + '?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    return db


def whole_table(db, name):
    return sorted([tuple(row) for row in db.execute('SELECT * FROM "' + name + '"')], key=repr)


def run(*args, env=None, succeeds=True):
    result = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True)
    assert (result.returncode == 0) == succeeds, result.stderr[-4000:]
    return result.stdout


def proof():
    with tempfile.TemporaryDirectory(prefix='universe-operator-proof-') as temp:
        root = Path(temp)
        os.chmod(root, 0o700)
        env = dict(os.environ, UNIVERSE_OPERATOR_PROOF_ROOT=str(root))
        run('cargo', 'test', '--locked', '-p', 'universe-store', '--lib',
            'kernel::operator_conversion::tests::generate_operator_fixture', '--', '--exact', env=env)
        run('cargo', 'test', '--locked', '-p', 'universe-service', '--lib',
            'conversion::tests::generate_operator_fixture', '--', '--exact', env=env)
        run('cargo', 'build', '--locked', '-p', 'universe-cli')
        installation = root / 'legacy-installation'
        before = {p: p.read_bytes() for p in root.rglob('*') if p.is_file()}
        cli = [str(ROOT / 'target/debug/universe'), '--installation', str(installation)]
        package = root / 'converted.sqlite'
        package_report = json.loads(run(*cli, 'convert-package', str(root / 'legacy.sqlite'), str(package)))
        converted_installation = root / 'converted-installation'
        installation_report = json.loads(run(*cli, 'convert-installation', str(installation), str(converted_installation)))
        profile_path = next((installation / 'profiles').glob('*.json'))
        converted_credential = root / 'credential.sqlite'
        credential_report = json.loads(run(*cli, 'convert-credential', str(profile_path), str(converted_credential)))
        source = open_db(root / 'legacy.sqlite')
        target = open_db(package)
        for table in SCALARS:
            assert whole_table(source, table) == whole_table(target, table), table
        actual = versions(target)
        legacy_records = list(source.execute('SELECT * FROM record_versions'))
        assert set(actual) == {r['id'] for r in legacy_records}
        classifications = []
        for row in legacy_records:
            body = json.loads(row['payload'])
            recipe = row['kind'] + ':v1:v1:'
            assert hashlib.sha256(recipe.encode() + encoded(body)).hexdigest() == row['digest']
            for vector, selected, status, zero, relationship in [
                ('types', 'classification', 'classificationResolution', 'unclassified', 'membership'),
                ('parents', 'parent', 'parentResolution', 'root', 'parent')]:
                if vector in body:
                    candidates = body.pop(vector)
                    body[selected] = candidates[0] if len(candidates) == 1 else None
                    body[status] = zero if not candidates else 'resolved' if len(candidates) == 1 else 'ambiguous'
                    if vector == 'parents':
                        body.setdefault('applicability', {'kind': 'unspecified'})
                    classifications += [(row['universe_id'], row['id'], relationship, i, ref)
                                        for i, ref in enumerate(candidates)]
            assert actual[row['id']]['payload'] == body, row['id']
            provenance = target.execute('SELECT source_digest,normalized_digest FROM import_record_digest WHERE version_id=?', (row['id'],)).fetchone()
            assert tuple(provenance) == (row['digest'], actual[row['id']]['payload_digest'])
        assert whole_table(target, 'classification_evidence') == sorted(classifications, key=repr)
        expected_provenance = [(r['universe_id'], r['id'], r['digest'], actual[r['id']]['payload_digest']) for r in legacy_records]
        assert whole_table(target, 'import_record_digest') == sorted(expected_provenance, key=repr)
        for record in actual.values():
            body = record['payload']
            if body['record_kind'] == 'entity_type':
                projection = target.execute('SELECT universe_id,version_id,record_id,name,parent_id,parent_resolution,applicability FROM type_definition WHERE version_id=?', (record['record_version_id'],)).fetchone()
                assert tuple(projection) == (record['identity']['universe_id'], record['record_version_id'], record['identity']['record_id'], body['name'], body['parent'], body['parentResolution'], body['applicability']['kind'])
            elif body['record_kind'] == 'entity':
                projection = target.execute('SELECT * FROM instance_classification WHERE version_id=?', (record['record_version_id'],)).fetchone()
                assert tuple(projection) == (record['identity']['universe_id'], record['record_version_id'], record['identity']['record_id'], body['classification'], body['classificationResolution'])
        actual_workflows = {r['key']: r for r in workflows(target)}
        source_workflows = list(source.execute('SELECT * FROM workflow_entries'))
        assert set(actual_workflows) == {r['key'] for r in source_workflows}
        for row in source_workflows:
            value = json.loads(row['payload'])
            assert hashlib.sha256(encoded(value)).hexdigest() == row['digest']
            if row['key'].startswith('draft:') and isinstance(value['content']['operations'], str):
                value['content']['operations'] = json.loads(value['content']['operations'])
            assert json.loads(actual_workflows[row['key']]['payload_utf8']) == value
            provenance = target.execute('SELECT source_digest,normalized_digest FROM import_workflow_digest WHERE key=?', (row['key'],)).fetchone()
            assert tuple(provenance) == (row['digest'], actual_workflows[row['key']]['digest'])
        expected_workflow_provenance = [(r['key'], r['digest'], actual_workflows[r['key']]['digest']) for r in source_workflows]
        assert whole_table(target, 'import_workflow_digest') == sorted(expected_workflow_provenance, key=repr)
        expected_snapshot_headers = []
        expected_snapshot_members = []
        snapshots = 0
        for row in source.execute('SELECT * FROM snapshot_membership'):
            expected = json.loads(row['membership'])
            retained = dict(target.execute('SELECT record_id,version_id FROM snapshot_member WHERE revision_id=?', (row['revision_id'],)))
            assert retained == expected
            expected_snapshot_headers.append((row['universe_id'], row['revision_id'], row['checksum']))
            expected_snapshot_members += [(row['universe_id'], row['revision_id'], r, v) for r, v in expected.items()]
            assert hashlib.sha256(encoded(expected)).hexdigest() == row['checksum']
            snapshots += 1
        assert whole_table(target, 'snapshot_membership') == sorted(expected_snapshot_headers, key=repr)
        assert whole_table(target, 'snapshot_member') == sorted(expected_snapshot_members, key=repr)
        source_install = open_db(installation / 'installation.sqlite')
        target_install = open_db(converted_installation / 'installation.sqlite')
        for table in ('settings', 'profiles', 'catalog', 'aliases', 'purge_pending', 'audit'):
            assert whole_table(source_install, table) == whole_table(target_install, table), table
        grants = 0
        for row in source_install.execute('SELECT * FROM grants'):
            restored = target_install.execute('SELECT * FROM grants WHERE profile=? AND universe=?', (row['profile'], row['universe'])).fetchone()
            for field in ('profile', 'universe', 'propose', 'edit', 'protected'):
                assert restored[field] == row[field]
            limits_row = source_install.execute('SELECT limits FROM grant_limits WHERE profile=? AND universe=?', (row['profile'], row['universe'])).fetchone()
            limits = json.loads(limits_row[0]) if limits_row else {}
            for field, table, column in [('worlds','grant_worlds','world'), ('entities','grant_entities','entity'), ('predicates','grant_predicates','predicate'), ('continuities','grant_continuities','continuity')]:
                expected = json.loads(row['worlds']) if field == 'worlds' and row['worlds'] is not None else limits.get(field) if field != 'worlds' else None
                assert restored[field + '_state'] == ('all' if expected is None else 'listed')
                values = [r[0] for r in target_install.execute(f'SELECT {column} FROM {table} WHERE profile=? AND universe=? ORDER BY ordinal', (row['profile'], row['universe']))]
                assert values == (expected or [])
            assert restored['expires_at'] == (str(limits['expires_at']) if limits.get('expires_at') is not None else None)
            assert bool(restored['delegated_commit']) == limits.get('delegated_commit', False)
            assert bool(restored['allow_shared']) == limits.get('allow_shared', False)
            grants += 1
        for profile in (installation / 'profiles').glob('*.json'):
            value = json.loads(profile.read_bytes())
            credential = open_db(converted_installation / 'profiles' / (value['profile_id'] + '.sqlite'))
            assert whole_table(credential, 'credential') == [(value['profile_id'], value['credential'])]
            credential.close()
        value = json.loads(profile_path.read_bytes())
        standalone = open_db(converted_credential)
        assert whole_table(standalone, 'credential') == [(value['profile_id'], value['credential'])]
        for command, original, destination in [('convert-package', root / 'legacy.sqlite', package), ('convert-installation', installation, converted_installation), ('convert-credential', profile_path, converted_credential)]:
            run(*cli, command, str(original), str(destination), succeeds=False)
            retry = destination.with_name('retry-' + destination.name)
            run(*cli, command, str(original), str(retry))
        assert all(p.read_bytes() == data for p, data in before.items())
        assert not (installation / 'engine.sock').exists()
        assert not target.execute('PRAGMA foreign_key_check').fetchall()
        assert not target_install.execute('PRAGMA foreign_key_check').fetchall()
        return {'package': package_report, 'installation': installation_report,
                'credential': credential_report, 'independent_versions': len(actual),
                'independent_workflows': len(actual_workflows), 'independent_snapshots': snapshots,
                'independent_grants': grants, 'original_files_compared': len(before),
                'retry_and_no_clobber': 'passed for all three CLI commands',
                'engine_started': False, 'live_author_data_converted': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = proof()
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
