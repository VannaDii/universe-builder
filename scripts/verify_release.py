#!/usr/bin/env python3
"""Headless bundle integrity and helper rejection checks; no desktop is launched."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


def verify(bundle):
    resources = bundle / 'Contents/Resources'
    manifest = json.loads((resources / 'release-manifest.json').read_text())
    assert manifest['release_accepted'] is False
    assert hashlib.sha256((resources / 'components.json').read_bytes()).hexdigest() == manifest['components_sha256']
    components = json.loads((resources / 'components.json').read_text())['components']
    assert components and all(p['name'] and p['version'] for p in components)
    for name, digest in manifest['helpers'].items():
        assert hashlib.sha256((bundle / 'Contents/MacOS' / name).read_bytes()).hexdigest() == digest
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle)], check=True, capture_output=True)
    with tempfile.TemporaryDirectory(prefix='ub-integrity-', dir='/tmp') as directory:
        copy = Path(directory) / 'Fixture.app'
        shutil.copytree(bundle, copy)
        root = Path(directory) / 'installation'
        cli = copy / 'Contents/MacOS/universe'
        author = subprocess.check_output([str(cli), '--installation', str(root), 'init'], text=True).strip()
        # Alter a signed helper without opening it or ever executing its contents.
        with (copy / 'Contents/MacOS/universe-engine').open('ab') as target:
            target.write(b'\ninvalid-bundle-test\n')
        result = subprocess.run([str(cli), '--installation', str(root), '--profile', author, 'status'], text=True, capture_output=True, timeout=20)
        assert result.returncode != 0 and 'integrity verification failed' in result.stderr, result.stderr
        public = Path(directory) / 'multiverse-mcp'
        public.symlink_to(copy / 'Contents/MacOS/multiverse-mcp')
        result = subprocess.run([str(public), 'admin', '--installation', str(root), '--profile', author, 'status'], text=True, capture_output=True, timeout=20)
        assert result.returncode != 0 and 'integrity verification failed' in result.stderr, result.stderr
        assert not (root / 'engine.sock').exists()
    return {'status': 'pass', 'component_count': len(components), 'helper_count': len(manifest['helpers']), 'checks': ['sealed bundle', 'component and helper SHA256', 'modified helper rejected before engine start, including through the public symlink'], 'release_accepted': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, required=True)
    print(json.dumps(verify(parser.parse_args().bundle.resolve()), indent=2))
