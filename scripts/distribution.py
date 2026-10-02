#!/usr/bin/env python3
"""Build versioned release archives and a checksum-pinned Homebrew formula."""
import argparse
import hashlib
import json
import re
import subprocess
import tarfile
from pathlib import Path
from string import Template

ROOT = Path(__file__).resolve().parents[1]
ARCHITECTURES = {'arm64': 'aarch64-apple-darwin', 'x86_64': 'x86_64-apple-darwin'}


def version(value):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', value):
        raise ValueError('Expected a semantic version without the v prefix')
    return value


def asset_name(release_version, architecture):
    return f'multiverse-mcp-{version(release_version)}-{ARCHITECTURES[architecture]}.tar.gz'


def archive(bundle, output, tag, allow_dirty=False):
    manifest = json.loads((bundle / 'Contents/Resources/release-manifest.json').read_text())
    release_version = version(manifest['version'])
    if tag != f'v{release_version}':
        raise ValueError('Git tag must match the Cargo/bundle version exactly')
    if manifest['dirty_build'] and not allow_dirty:
        raise ValueError('Release archives require a clean source tree; --allow-dirty is for local checks only')
    if bundle.name != 'Multiverse MCP.app' or manifest['channel'] != 'preview':
        raise ValueError('Use xtask package-release to build the distribution bundle')
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
    output.mkdir(parents=True, exist_ok=True)
    destination = output / asset_name(release_version, manifest['architecture'])
    # One complete app at the archive root; no source checkout, profiles or installation data.
    with tarfile.open(destination, 'w:gz') as target:
        target.add(bundle, arcname=bundle.name)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix(destination.suffix + '.sha256').write_text(f'{digest}  {destination.name}\n')
    return destination


def formula(assets, release_version, repository=None, local=False):
    version(release_version)
    if not local and (not repository or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository)):
        raise ValueError('Expected GitHub owner/repository')
    values = {'version': release_version, 'homepage': f'https://github.com/{repository}' if repository else 'https://brew.sh'}
    downloads = []
    present = []
    for architecture, key in [('arm64', 'arm'), ('x86_64', 'intel')]:
        asset = assets / asset_name(release_version, architecture)
        if local and not asset.is_file():
            continue
        digest = hashlib.sha256(asset.read_bytes()).hexdigest()
        url = asset.resolve().as_uri() if local else f'https://github.com/{repository}/releases/download/v{release_version}/{asset.name}'
        downloads.append(f'  on_{key} do\n    url "{url}"\n    sha256 "{digest}"\n  end\n')
        present.append(architecture)
    if not present:
        raise FileNotFoundError('No local release archives found')
    values['downloads'] = '\n'.join(downloads)
    values['architecture_dependency'] = f'  depends_on arch: :{present[0]}\n' if len(present) == 1 else ''
    return Template((ROOT / 'packaging/multiverse-mcp.rb.in').read_text()).substitute(values)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    pack = commands.add_parser('archive')
    pack.add_argument('--bundle', type=Path, required=True)
    pack.add_argument('--output', type=Path, required=True)
    pack.add_argument('--tag', required=True)
    pack.add_argument('--allow-dirty', action='store_true')
    brew = commands.add_parser('formula')
    brew.add_argument('--assets', type=Path, required=True)
    brew.add_argument('--version', required=True)
    location = brew.add_mutually_exclusive_group(required=True)
    location.add_argument('--repository')
    location.add_argument('--local', action='store_true', help='file URLs for temporary local installation checks only')
    brew.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'archive':
        print(archive(args.bundle, args.output, args.tag, args.allow_dirty))
    else:
        content = formula(args.assets, args.version, args.repository, args.local)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content)
        print(args.output)


if __name__ == '__main__':
    main()
