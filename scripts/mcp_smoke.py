"""Independent stdio MCP client. Runs only the disposable fixture engine."""
import argparse
import copy
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time
from validate_contracts import ROOT, validators
from jsonschema import Draft202012Validator

class MCP:
    def __init__(self, binary, socket=None, protocol='2025-11-25', *, installation=None, profile=None, command_prefix=()):
        args = ['--installation', str(installation), '--profile', str(profile)] if installation else ['--fixture', '--socket', str(socket)]
        self.process = subprocess.Popen([str(binary), *command_prefix, *args], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={**os.environ, 'PATH': '/usr/bin:/bin'})
        self.responses = queue.Queue()
        self.seq = 0
        self.notifications = []
        self.schemas = validators()
        def read():
            for line in self.process.stdout:
                try:
                    self.responses.put(json.loads(line))
                except Exception as error:
                    self.responses.put(error)
            self.responses.put(EOFError('MCP stdout closed'))
        threading.Thread(target=read, daemon=True).start()
        self.initialization = self.request('initialize', {'protocolVersion': protocol, 'capabilities': {}, 'clientInfo': {'name': 'universe-independent-fixture-client', 'version': '1'}})
        self.write({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
    def write(self, message):
        # Default Python escaping is valid MCP JSON, including surrogate pairs.
        self.process.stdin.write(json.dumps(message, ensure_ascii=True) + '\n')
        self.process.stdin.flush()
    def request(self, method, params):
        self.seq += 1
        self.write({'jsonrpc': '2.0', 'id': self.seq, 'method': method, 'params': params})
        while True:
            response = self.responses.get(timeout=20)
            if isinstance(response, Exception):
                raise response
            if 'id' not in response:
                self.notifications.append(response)
                continue
            assert response['id'] == self.seq, response
            assert 'error' not in response, response
            return response['result']
    def call(self, name, args, error=False):
        result = self.request('tools/call', {'name': name, 'arguments': args})
        assert bool(result.get('isError', False)) == error, result
        structured = result.get('structuredContent')
        text = ''.join(c['text'] for c in result['content'] if c['type'] == 'text')
        if structured is not None:
            assert json.loads(text) == structured, 'text/structured mismatch'
        if not error:
            self.schemas[name][1].validate(structured)
        return structured
    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=5)


def check_server_contract(initialization, tools):
    """Check delivery and public contracts; functional scenarios check behavior."""
    guidance = initialization.get('instructions')
    assert isinstance(guidance, str) and guidance.strip(), 'missing serving guidance'
    expected = {t['name']: t for t in json.loads((ROOT / 'contracts/tools.json').read_text())}
    assert len(tools) == len(expected), 'missing or duplicate tools'
    assert {t['name'] for t in tools} == set(expected), 'unexpected tool catalog'
    for tool in tools:
        name = tool['name']
        assert isinstance(tool.get('description'), str) and tool['description'].strip(), name
        for delivered, owned in [('inputSchema', 'input_schema'), ('outputSchema', 'output_schema')]:
            Draft202012Validator.check_schema(tool[delivered])
            assert tool[delivered] == expected[name][owned], (name, delivered)


def run(bin_dir):
    examples = {e['tool']: e['args'] for e in json.loads((ROOT / 'contracts/examples.json').read_text())}
    with tempfile.TemporaryDirectory(prefix='universe-fixture-') as directory:
        socket = Path(directory) / 'fixture.sock'
        engine = subprocess.Popen([str(bin_dir / 'universe-engine'), '--fixture', '--socket', str(socket)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                if socket.exists(): break
                if engine.poll() is not None: raise RuntimeError(engine.stderr.read().decode())
                time.sleep(.05)
            assert socket.exists(), 'engine did not start'
            client = MCP(bin_dir / 'universe-mcp', socket)
            try:
                tools = client.request('tools/list', {})['tools']
                check_server_contract(client.initialization, tools)
                for tool in tools:
                    name = tool['name']
                    bad = copy.deepcopy(examples[name]); del bad['universe']
                    client.call(name, bad, error=True)
                    # Deterministic malformed-contract corpus through real MCP, not only JSON Schema.
                    for field, value in [('universe', None), ('universe', ''), ('universe', '*'), ('universe_id', 'bad'), ('approved', True), ('world', None)]:
                        malformed = copy.deepcopy(examples[name]); malformed[field] = value
                        client.call(name, malformed, error=True)
                client.call('universe_describe', examples['universe_describe'])
                context = client.call('universe_open_context', examples['universe_open_context'])['result']['context_id']
                args = copy.deepcopy(examples['universe_search']); args['context_id'] = context
                result = client.call('universe_search', args)
                assert any('Mara' in h['label'] for h in result['result']['hits'])
                args['world'] = 'Aster'; client.call('universe_search', args)
                del args['world']; assert client.call('universe_search', args)['world_focus'] is None
                args['universe'] = 'The Glass Archive'; client.call('universe_search', args, error=True)
                args = copy.deepcopy(examples['universe_propose']); args['context_id'] = context
                args['operations'][0]['record']['labels']['en'] = 'La lanterne — 日本語 🌙'
                proposal = client.call('universe_propose', args)['result']; assert proposal['canonical'] is False
                assert client.call('universe_propose', args)['result'] == proposal
                args['universe_id'] = proposal['base_frame']['universe']
                assert client.call('universe_propose', args)['result'] == proposal
                revised = copy.deepcopy(args)
                revised['action'] = 'revise'
                revised['proposal_reference'] = {k: proposal[k] for k in ('proposal_id', 'version', 'digest')}
                revised['idempotency_key'] = 'fixture-revision-2'
                revised['rationale'] = 'Revision two'
                version_two = client.call('universe_propose', revised)['result']
                revised['idempotency_key'] = 'stale-revision'
                assert client.call('universe_propose', revised, error=True)['code'] == 'INVALID_ARGUMENT'
                read_version = {'universe': args['universe'], 'proposal_id': proposal['proposal_id'], 'version': 2}
                assert client.call('universe_get_proposal', read_version)['result'] == version_two
                recovered = client.call('universe_get_operation', examples['universe_get_operation'])
                assert recovered['result']['proposal'] == proposal
                client.call('universe_commit', examples['universe_commit'], error=True)
                args['rationale'] = 'Changed content'; client.call('universe_propose', args, error=True)
                print(json.dumps({'status': 'pass', 'route': 'independent stdio', 'negotiated': client.initialization['protocolVersion'], 'tools': len(tools), 'checks': ['91 malformed contract mutations across all tools', 'known record', 'omitted world', 'isolation', 'Unicode proposal', 'idempotency', 'receipt recovery', 'canon denial', 'text/structured parity', 'output schemas']}, indent=2))
            finally: client.close()
            # Replace the adapter entirely. Recovery uses the engine receipt, not client memory.
            resumed = MCP(bin_dir / 'universe-mcp', socket)
            try:
                recovered = resumed.call('universe_get_operation', examples['universe_get_operation'])
                assert recovered['result']['proposal'] == proposal
                retry = copy.deepcopy(examples['universe_propose'])
                retry['context_id'] = resumed.call('universe_open_context', examples['universe_open_context'])['result']['context_id']
                retry['operations'][0]['record']['labels']['en'] = 'La lanterne — 日本語 🌙'
                assert resumed.call('universe_propose', retry)['result'] == proposal
                print(json.dumps({'adapter_restart_receipt_recovery': 'pass', 'equivalent_frame_retry': 'pass'}))
            finally: resumed.close()
            # An older lifecycle must negotiate explicitly; never imply its requested version worked.
            older = MCP(bin_dir / 'universe-mcp', socket, '2024-11-05')
            try:
                older.call('universe_describe', examples['universe_describe'])
                print(json.dumps({'older_requested': '2024-11-05', 'negotiated': older.initialization['protocolVersion'], 'read': 'pass'}))
            finally: older.close()
        finally:
            engine.terminate()
            engine.wait(timeout=5)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bin-dir', type=Path, default=ROOT / 'target/debug')
    run(parser.parse_args().bin_dir.resolve())
