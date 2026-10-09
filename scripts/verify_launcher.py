#!/usr/bin/env python3
"""Headless public-command and Finder-shortcut checks in disposable directories."""
import argparse
import json
import plistlib
import shlex
import subprocess
import tempfile
from pathlib import Path


def verify(bin_dir):
    launcher = bin_dir.resolve() / 'multiverse-mcp'
    approved_icon = (Path(__file__).resolve().parent.parent / 'assets/branding/universe-builder.icns').read_bytes()
    assert approved_icon.startswith(b'icns'), 'Approved macOS icon must be present'
    bundle_contents = bin_dir.resolve().parent
    if bundle_contents.name == 'Contents':
        bundle_plist = plistlib.loads((bundle_contents / 'Info.plist').read_bytes())
        assert bundle_plist['CFBundleIconFile'] == 'universe-builder.icns'
        assert (bundle_contents / 'Resources/universe-builder.icns').read_bytes() == approved_icon

    def run(*args, ok=True):
        result = subprocess.run([str(launcher), *map(str, args)], text=True, capture_output=True, timeout=30)
        if ok:
            assert result.returncode == 0, result.stderr
        else:
            assert result.returncode != 0
        return result

    assert 'multiverse-mcp' in run('--version').stdout
    assert '--installation' in run('serve', '--help').stdout
    assert 'shutdown' in run('admin', '--help').stdout
    run('ux', '--installation', '/missing', ok=False)
    with tempfile.TemporaryDirectory(prefix='multiverse-launcher-', dir='/tmp') as directory:
        base = Path(directory)
        public_bin = base / 'bin'
        public_bin.mkdir()
        public_command = public_bin / 'multiverse-mcp'
        public_command.symlink_to(launcher)
        launcher = public_command
        assert '--installation' in run('serve', '--help').stdout
        installation = base / 'library with spaces'
        author = run('admin', '--installation', installation, 'init').stdout.strip()
        try:
            state = run('admin', '--installation', installation, '--profile', author, 'status')
            assert 'universes' in json.loads(state.stdout)
        finally:
            run('admin', '--installation', installation, '--profile', author, 'shutdown')
        # Execute the generated shortcut against a recording command, never a GUI.
        fake = base / "a 'quoted' $(id) command"
        capture = base / 'arguments.txt'
        fake.write_text('#!/bin/sh\nprintf \'%s\\n\' "$@" > ' + shlex.quote(str(capture)) + '\n')
        fake.chmod(0o755)
        destination = base / 'Desktop with spaces'
        arguments = ['shortcut', '--destination', destination, '--launcher', fake,
                     '--installation', installation, '--profile', author]
        run(*arguments)
        script = destination / 'Multiverse MCP.app/Contents/MacOS/launch'
        shortcut_contents = script.parent.parent
        shortcut_plist = plistlib.loads((shortcut_contents / 'Info.plist').read_bytes())
        assert shortcut_plist['CFBundleIconFile'] == 'universe-builder.icns'
        assert (shortcut_contents / 'Resources/universe-builder.icns').read_bytes() == approved_icon
        original = script.read_bytes()
        subprocess.run([str(script)], check=True, timeout=10)
        assert capture.read_text().splitlines() == ['ux', '--installation', str(installation), '--profile', author]
        run(*arguments, ok=False)
        assert script.read_bytes() == original, 'Existing shortcuts must not be overwritten'
    print('PASS: public launcher through symlinks, administration, literal shortcut arguments, approved app/shortcut icon, existing shortcut preserved; no GUI opened')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bin-dir', type=Path, required=True)
    verify(parser.parse_args().bin_dir)
