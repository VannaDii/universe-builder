#!/usr/bin/env python3
"""Build the local Flutter app with its native Dart engine. No publishing."""
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--mode', choices=('debug', 'release'), default='debug')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
app = root / 'apps/ub_app'
engine = root / 'apps/ub_engine'

def run(*command, cwd=root):
    subprocess.run(command, cwd=cwd, check=True)

run('dart', 'build', 'cli', '--target', 'bin/universe-engine.dart',
    '--output', 'build/native', '--verbosity=error', cwd=engine)
run('flutter', 'build', 'macos', f'--{args.mode}', '--no-pub', cwd=app)
bundle = app / f'build/macos/Build/Products/{args.mode.capitalize()}/Universe Builder.app'
contents = bundle / 'Contents'
native = engine / 'build/native/bundle'
shutil.copy2(native / 'bin/universe-engine', contents / 'MacOS/universe-engine')
shutil.copytree(native / 'lib', contents / 'lib', dirs_exist_ok=True)
shutil.copy2(root / 'assets/branding/universe-builder.icns', contents / 'Resources/AppIcon.icns')

# Keep the helper inside the app's sandbox, with the parent's access rights.
with tempfile.TemporaryDirectory(prefix='ub-sign-') as temporary:
    entitlements = Path(temporary) / 'helper.plist'
    entitlements.write_bytes(plistlib.dumps({
        'com.apple.security.app-sandbox': True,
        'com.apple.security.inherit': True,
    }))
    for library in (contents / 'lib').glob('*.dylib'):
        run('/usr/bin/codesign', '--force', '--sign', '-', str(library))
    run('/usr/bin/codesign', '--force', '--sign', '-', '--entitlements',
        str(entitlements), str(contents / 'MacOS/universe-engine'))

manifest = {
    'format': 1, 'version': plistlib.loads((contents / 'Info.plist').read_bytes())['CFBundleShortVersionString'],
    'channel': 'local-development',
    'helpers': {'universe-engine': hashlib.sha256(
        (contents / 'MacOS/universe-engine').read_bytes()).hexdigest()},
    'desktop_integrity': 'Sealed by the bundle code signature',
    'release_accepted': False,
}
(contents / 'Resources/release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
runner_entitlements = 'DebugProfile.entitlements' if args.mode == 'debug' else 'Release.entitlements'
run('/usr/bin/codesign', '--force', '--sign', '-', '--entitlements',
    str(app / 'macos/Runner' / runner_entitlements), str(bundle))
run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle))
print(bundle)
