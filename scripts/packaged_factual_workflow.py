#!/usr/bin/env python3
"""Qualify a copied development app using disposable installations and real MCP.

Python readers/contracts remain qualification tooling, not packaged executables.
No desktop, author data, distribution installer, or remote service is used.
"""
import argparse
from contextlib import redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

import installation_smoke
import resource_resolution_pilot as resource
from audit_resource_resolution import audit
from continuity_gap_pilot import RecordedMCP
from verify_launcher import verify

ROOT = Path(__file__).resolve().parents[1]
PRODUCTS = {'universe', 'universe-engine', 'universe-mcp', 'multiverse-mcp', 'universe-builder'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(bundle, output):
    started = time.monotonic()
    output.mkdir(parents=True, exist_ok=False)
    report = {'status': 'running', 'executions': [], 'checks': []}
    original_cwd, original_path = Path.cwd(), os.environ['PATH']
    rustc = Path(shutil.which('rustc')).absolute()
    guard = {'active': False, 'bin': None}

    def execution_guard(event, args):
        if event != 'subprocess.Popen' or not guard['active']:
            return
        executable, argv, cwd, env = args
        executable = Path(os.fsdecode(executable))
        if executable.name in PRODUCTS:
            resolved = executable.resolve()
            assert resolved.parent == guard['bin'], f'product executable escaped installed bundle: {resolved}'
            assert resolved.name != 'universe-builder', 'native interaction is outside this proof'
            actual_cwd = Path(cwd or Path.cwd()).resolve()
            assert not actual_cwd.is_relative_to(ROOT), 'product launched from source checkout'
            actual_path = (env or os.environ)['PATH']
            assert all(not Path(p).resolve().is_relative_to(ROOT) for p in actual_path.split(os.pathsep))
            # Do not record command arguments: installation authentication can
            # contain credentials. Only path/provenance is retained here.
            report['executions'].append({'executable': str(resolved), 'cwd': str(actual_cwd), 'path': actual_path})

    sys.addaudithook(execution_guard)
    try:
        with tempfile.TemporaryDirectory(prefix='packaged-factual-', dir='/tmp') as directory:
            base = Path(directory).resolve()
            installed = base / 'Applications with spaces' / bundle.name
            shutil.copytree(bundle, installed)
            bin_dir = installed / 'Contents/MacOS'
            guard['bin'] = bin_dir.resolve()
            resources = installed / 'Contents/Resources'
            manifest = json.loads((resources / 'release-manifest.json').read_text())
            assert manifest['channel'] == 'local-development' and manifest['release_accepted'] is False
            assert manifest['components_sha256'] == digest(resources / 'components.json')
            assert len(json.loads((resources / 'components.json').read_text())['components']) > 0
            assert set(manifest['helpers']) == PRODUCTS - {'universe-builder'}
            files = {str(p.relative_to(installed)): digest(p) for p in sorted(installed.rglob('*')) if p.is_file()}
            assert all(files['Contents/MacOS/' + name] == sha for name, sha in manifest['helpers'].items())
            report.update(bundle_manifest=manifest, bundle_files_sha256=files, installed_bundle=str(installed))
            os.chdir(base)
            # Rust is available only to the existing proof's build-metadata
            # collector. All product processes are absolute installed paths;
            # MCP itself additionally forces /usr/bin:/bin.
            os.environ['PATH'] = os.pathsep.join(['/usr/bin', '/bin', str(rustc.parent)])
            guard['active'] = True
            public_bin = base / 'bin'
            public_bin.mkdir()
            launcher = public_bin / 'multiverse-mcp'
            launcher.symlink_to(bin_dir / 'multiverse-mcp')
            report['public_launcher'] = str(launcher)
            smoke_output = io.StringIO()
            with redirect_stdout(smoke_output):
                verify(bin_dir)
                installation_smoke.run(bin_dir)
            report['installation_smoke'] = smoke_output.getvalue()
            report['checks'] += ['public launcher and symlink forwarding', 'fresh enrollment and current grants',
                                 '13-tool discovery', 'forged authentication/protocol rejection', 'revocation',
                                 'concurrent bootstrap', 'forced restart and durable heads']

            class InstalledAuthorSession(resource.AuthorSession):
                def cli(self, *args, profile=None, check=True):
                    command = [str(launcher), 'admin', '--installation', str(self.root)]
                    if profile:
                        command += ['--profile', profile]
                    result = subprocess.run([*command, *map(str, args)], capture_output=True, text=True, timeout=30)
                    self.report.setdefault('author_cli', []).append({'arguments': list(map(str, args)),
                        'profile': profile, 'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
                    if check:
                        assert result.returncode == 0, result.stderr
                    return result

                def connect(self):
                    self.client = RecordedMCP(launcher, command_prefix=('serve',), installation=self.root,
                                              profile=self.author, wire=self.wire)
                    self.instructions = self.client.initialization['instructions']

                def admin(self, *args):
                    result = super().admin(*args)
                    if args[0] == 'status':
                        rows = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines()
                        needle = f'universe-engine --installation {self.root.resolve()}'
                        owned = [row.strip().split(None, 1)[1] for row in rows if needle in row]
                        assert len(owned) == 1 and owned[0].startswith(str(bin_dir / 'universe-engine') + ' '), owned
                        report.setdefault('engine_paths', []).append(str(bin_dir / 'universe-engine'))
                    return result

            original_session = resource.AuthorSession
            resource.AuthorSession = InstalledAuthorSession
            proof = output / 'resource-resolution.json'
            try:
                resource.run(proof, bin_dir)
            finally:
                resource.AuthorSession = original_session
            report['resource_audit'] = audit(proof)
            test = subprocess.run([sys.executable, str(ROOT / 'scripts/test_resource_resolution_audit.py'),
                                   '--evidence', str(proof), '-v'], capture_output=True, text=True, timeout=120)
            (output / 'audit-tests.txt').write_text(test.stdout + test.stderr)
            assert test.returncode == 0, test.stdout + test.stderr
            report['checks'] += ['public launcher factual publication and exact private review/approval',
                                 'independent expected facts and typed SQLite history reconstruction',
                                 'effective objects, unknowns, restricted evidence and reviewed initialization',
                                 'unresolved resource and changed-claim rejection', 'explicit exact resource acceptance',
                                 'stale approval and commit-key rejection', 'forged creative authority rejection',
                                 'receipt recovery and historical/current state after forced restart',
                                 'independent auditor falsification controls']
            actual = json.loads(proof.read_text())
            assert all(actual['build']['binaries'][name]['sha256'] == sha for name, sha in manifest['helpers'].items()
                       if name in actual['build']['binaries'])
            assert report['engine_paths'] and report['executions']
            assert files == {str(p.relative_to(installed)): digest(p) for p in sorted(installed.rglob('*')) if p.is_file()}
            report['bundle_unchanged'] = True
            report['proof_sha256'] = {p.name: digest(p) for p in sorted(output.iterdir()) if p.is_file()}
            guard['active'] = False
            os.chdir(original_cwd)
        report['copied_bundle_removed'] = not installed.exists()
        report['status'] = 'pass'
    finally:
        guard['active'] = False
        os.chdir(original_cwd)
        os.environ['PATH'] = original_path
        report['seconds'] = time.monotonic() - started
        (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'status': report['status'], 'seconds': report['seconds'], 'checks': report['checks']}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='new credential-free evidence directory')
    args = parser.parse_args()
    run(args.bundle.resolve(), args.output.resolve())
