"""Independent CLI/MCP persistent-engine checks. Never prints profile credentials."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import signal
import sqlite3
import socket
import struct
import subprocess
import tempfile
import time
from mcp_smoke import MCP, check_server_contract


def run(bin_dir):
    with tempfile.TemporaryDirectory(prefix='ub-install-', dir='/tmp') as temp:
        root = Path(temp) / 'installation'
        binary = bin_dir / 'universe'
        def cli(*args, profile=None, check=True):
            command = [str(binary), '--installation', str(root)]
            if profile:
                command += ['--profile', profile]
            result = subprocess.run([*command, *args], text=True, capture_output=True, timeout=20)
            if check and result.returncode:
                raise RuntimeError(f'CLI {args[0]} failed: {result.stderr}')
            return result
        author = cli('init').stdout.strip()
        def admin(*args):
            return json.loads(cli(*args, profile=author).stdout)
        client = None
        try:
            # Six independent cold-starting processes must converge on one service.
            with ThreadPoolExecutor(max_workers=6) as pool:
                statuses = list(pool.map(lambda _: admin('status'), range(6)))
            instance = statuses[0]['service_instance']
            assert all(s['service_instance'] == instance for s in statuses)
            universe = admin('create',"--scratch-policy", 'The Ashen Cycle', '--first-time', '0', '--calendar', 'Ashen days', '--tick-label', 'days')
            agent = admin('enroll')['profile_id']
            uid = universe['universe_id']
            client = MCP(bin_dir / 'universe-mcp', installation=root, profile=agent)
            check_server_contract(client.initialization, client.request('tools/list', {})['tools'])
            client.call('universe_describe', {'universe': 'The Ashen Cycle', 'mode': 'summary'}, error=True)
            admin('grant', agent, uid, '--propose')
            result = client.call('universe_describe', {'universe': 'The Ashen Cycle', 'mode': 'summary'})
            assert result['universe_id'] == uid and result['result']['fixture'] is False
            # Same closed public contracts as native authoring, independent client.
            admin('grant', agent, uid, '--propose', '--edit')
            context_args = {'universe': 'The Ashen Cycle', 'continuity_id': universe['continuity_id'], 'revision': {'kind': 'head'}, 'represented_context': universe['context_id'], 'temporal_query': {'kind': 'timeless'}, 'temporal_systems': [], 'perspective': 'author'}
            context = client.call('universe_open_context', context_args)['result']['context_id']
            proposal_args = {'action': 'create', 'universe': 'The Ashen Cycle', 'context_id': context, 'operations': [{'kind': 'create_entity', 'client_ref': 'mara', 'record': {'names': [], 'classification': None, 'classificationResolution': 'unclassified', 'worldAssociations': [], 'labels': {'en': 'Mara'}, 'metadata': {}}}], 'submission': 'submitted', 'rationale': 'Independent author and agent loop', 'idempotency_key': 'propose-mara'}
            proposal = client.call('universe_propose', proposal_args)['result']
            assert client.call('universe_propose', proposal_args)['result'] == proposal
            reference = {key: proposal[key] for key in ('proposal_id', 'version', 'digest')}
            validation = client.call('universe_validate', {'mode': 'proposal', 'universe': 'The Ashen Cycle', 'context_id': context, 'proposal_reference': reference, 'check_scope': 'universe'})['result']['execution']
            commit = {'universe': 'The Ashen Cycle', 'proposal_reference': reference, 'expected_base_revision': proposal['base_frame']['revision'], 'validation_run': validation['run_id'], 'idempotency_key': 'commit-mara'}
            client.call('universe_commit', commit, error=True)
            review = admin('review', 'The Ashen Cycle', proposal['proposal_id'], str(proposal['version']), proposal['digest'])
            assert len(review['changes']) == 1 and review['footprint']['shared']
            admin('approve', 'The Ashen Cycle', proposal['proposal_id'], str(proposal['version']), proposal['digest'], validation['run_id'])
            receipt = client.call('universe_commit', commit)['result']
            assert client.call('universe_commit', commit)['result'] == receipt
            current = client.call('universe_open_context', context_args)['result']['context_id']
            result = client.call('universe_search', {'universe': 'The Ashen Cycle', 'context_id': current, 'query': 'Mara', 'typed_filters': {'record_kinds': ['entity']}, 'limit': 100})
            assert len(result['result']['hits']) == 1 and result['frame']['revision'] == receipt['revision']
            entity_id = result['result']['hits'][0]['record_id']
            state = client.call('universe_get_state', {'universe': 'The Ashen Cycle', 'context_id': current, 'entity_ids': [entity_id], 'predicate_filters': []})['result']
            assert state['assertions'] == [] and state['propositions'] == [] and state['completeness'] == []
            assert state['coverage'] == 'partial' and state['unsupported_capabilities']
            brief_args = {'universe': 'The Ashen Cycle', 'context_id': current, 'focus_ids': [entity_id], 'purpose': 'Read explicit canon', 'byte_budget': 65536}
            brief = client.call('universe_get_context', brief_args)['result']
            assert client.call('universe_get_context', brief_args)['result'] == brief
            operation = client.call('universe_get_operation', {'lookup': 'key', 'universe': 'The Ashen Cycle', 'operation_kind': 'commit', 'idempotency_key': 'commit-mara'})
            assert operation['result']['receipt'] == receipt
            admin('rename', uid, 'The Renamed Cycle')
            result = client.call('universe_describe', {'universe': 'The Ashen Cycle', 'mode': 'summary'})
            assert result['alias_matched'] is True and result['universe'] == 'The Renamed Cycle'
            # Malformed context input remains rejected.
            client.call('universe_open_context', {'universe': 'The Renamed Cycle', 'revision': 'head', 'continuity': 'main'}, error=True)
            client.close(); client = None
            assert admin('status')['service_instance'] == instance
            doctor = admin('doctor')
            storage = doctor['packages'][0]['storage']
            assert storage['foreign_keys'] is True and storage['journal_mode'] == 'wal' and storage['synchronous'] == 2
            # Incompatible and forged hello metadata fail before request dispatch.
            with sqlite3.connect(f"file:{root / 'profiles' / f'{agent}.sqlite'}?mode=ro", uri=True) as credentials:
                profile = {'credential': credentials.execute('SELECT credential FROM credential WHERE profile_id=?', (agent,)).fetchone()[0]}
            for extra in [{'protocol_version': '999'}, {'author': True}]:
                hello = {'protocol_version': '1', 'profile_id': agent, 'credential': profile['credential'], 'client_name': 'author', **extra}
                payload = json.dumps(hello).encode()
                with socket.socket(socket.AF_UNIX) as sock:
                    sock.settimeout(5); sock.connect(str(root / 'engine.sock'))
                    sock.sendall(struct.pack('>I', len(payload)) + payload)
                    assert sock.recv(4) == b''
            del profile
            admin('revoke', agent)
            assert cli('status', profile=agent, check=False).returncode != 0
            # Terminate only the engine started for this exact disposable installation.
            rows = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines()
            pids = [int(line.strip().split(None, 1)[0]) for line in rows if f'universe-engine --installation {root.resolve()}' in line]
            assert len(pids) == 1, 'expected one owned engine'
            os.kill(pids[0], signal.SIGKILL)
            time.sleep(.2)
            restarted = admin('status')
            assert restarted['service_instance'] != instance and restarted['universes'][0]['id'] == uid
            assert admin('doctor')['packages'][0]['storage']['heads'] == storage['heads']
            print(json.dumps({'status': 'pass', 'sqlite': storage['sqlite_version'], 'checks': ['six concurrent cold starts', 'independent MCP schema validation', 'agent proposal and exact author approval', 'idempotent canon commit', 'pinned query and operation receipt', 'current grants', 'rename aliases', 'adapter disconnect survival', 'incompatible/forged handshake rejection', 'revocation', 'SIGKILL stale-socket recovery', 'durable heads', 'WAL/FULL/FK diagnostics']}, indent=2))
        finally:
            if client:
                client.close()
            cli('shutdown', profile=author, check=False)
            for _ in range(100):
                if not (root / 'engine.sock').exists():
                    break
                time.sleep(.02)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bin-dir', type=Path, default=Path('target/headless/local/bin'))
    run(parser.parse_args().bin_dir.resolve())
