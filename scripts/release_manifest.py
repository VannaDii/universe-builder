#!/usr/bin/env python3
"""Record exact local bundle components. This never marks a release accepted."""
import argparse
import hashlib
import json
import platform
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--bundle', type=Path, required=True)
parser.add_argument('--channel', choices=['local-development', 'preview'], default='local-development')
args = parser.parse_args()
resources = args.bundle / 'Contents' / 'Resources'
resources.mkdir(parents=True, exist_ok=True)
host = next(line.split(': ', 1)[1] for line in subprocess.check_output(['rustc', '-vV'], text=True).splitlines() if line.startswith('host: '))
metadata = json.loads(subprocess.check_output(['cargo', 'metadata', '--locked', '--offline', '--filter-platform', host, '--format-version', '1'], text=True))
components = [{'name': p['name'], 'version': p['version'], 'license': p['license'], 'source': p['source']} for p in metadata['packages']]
components.sort(key=lambda p: (p['name'], p['version']))
(resources / 'components.json').write_text(json.dumps({'format': 1, 'components': components}, indent=2) + '\n')
files = {}
for name in ['universe-engine', 'universe-mcp', 'universe', 'multiverse-mcp']:
    binary = args.bundle / 'Contents' / 'MacOS' / name
    files[name] = hashlib.sha256(binary.read_bytes()).hexdigest()
manifest = {
    'format': 1, 'version': next(p['version'] for p in metadata['packages'] if p['name'] == 'universe-builder-desktop'), 'channel': args.channel,
    'minimum_macos': '15.0',
    'architecture': platform.machine(), 'target': host, 'verified_build_host': platform.mac_ver()[0],
    'source_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'dirty_build': bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip()),
    'supported_os': 'Not certified; this build host only',
    'rustc': subprocess.check_output(['rustc', '--version'], text=True).strip(),
    'helpers': files, 'desktop_integrity': 'Sealed by the bundle code signature',
    'components_sha256': hashlib.sha256((resources / 'components.json').read_bytes()).hexdigest(),
    'assets': 'Embedded in the desktop executable; no runtime asset server',
    'update_protocol': 'Stop the engine with authenticated shutdown, preserve installation data, replace the entire verified app bundle, restart explicitly. Never replace live helpers piecemeal.',
    'release_accepted': False,
    'pending_gates': ['Native/VoiceOver verification paused by author', 'LM Studio blocked while Bionic remains open', 'Clean-machine offline verification', 'Developer ID signing and notarization', 'Full release workload/security acceptance'],
}
(resources / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Recorded {len(components)} components and {len(files)} executable digests')
