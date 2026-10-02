#!/usr/bin/env python3
"""Distribution metadata tests; these do not open a desktop or contact GitHub."""
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import distribution


class FormulaTests(unittest.TestCase):
    def test_release_urls_and_checksums_come_from_each_architecture(self):
        with tempfile.TemporaryDirectory() as directory:
            assets = Path(directory)
            for arch in distribution.ARCHITECTURES:
                (assets / distribution.asset_name('0.1.0', arch)).write_bytes(arch.encode())
            formula = distribution.formula(assets, '0.1.0', 'example/universe')
            for arch in distribution.ARCHITECTURES:
                name = distribution.asset_name('0.1.0', arch)
                self.assertIn(f'https://github.com/example/universe/releases/download/v0.1.0/{name}', formula)
                self.assertIn(hashlib.sha256(arch.encode()).hexdigest(), formula)
            self.assertIn('bin.install_symlink', formula)
            local = distribution.formula(assets, '0.1.0', local=True)
            self.assertIn(assets.resolve().as_uri(), local)
            self.assertNotIn('releases/download', local)

    def test_missing_architecture_is_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                distribution.formula(Path(directory), '0.1.0', 'example/universe')

    def test_local_formula_can_restrict_to_the_built_architecture(self):
        with tempfile.TemporaryDirectory() as directory:
            assets = Path(directory)
            (assets / distribution.asset_name('0.1.0', 'arm64')).write_bytes(b'local build')
            formula = distribution.formula(assets, '0.1.0', local=True)
            self.assertIn('depends_on arch: :arm64', formula)
            self.assertNotIn('on_intel', formula)
            with self.assertRaises(FileNotFoundError):
                distribution.formula(assets, '0.1.0', 'example/universe')

    def test_archive_rejects_mismatched_tags_and_dirty_release_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / 'Multiverse MCP.app'
            resources = bundle / 'Contents/Resources'
            resources.mkdir(parents=True)
            (resources / 'release-manifest.json').write_text(json.dumps({'version': '0.1.0', 'dirty_build': True}))
            with self.assertRaisesRegex(ValueError, 'Git tag'):
                distribution.archive(bundle, Path(directory), 'v0.2.0')
            with self.assertRaisesRegex(ValueError, 'clean source'):
                distribution.archive(bundle, Path(directory), 'v0.1.0')

    def test_metadata_cannot_inject_ruby_or_paths(self):
        for candidate in ['../1', 'v0.1.0', '0.1.0"; system("id")', '0.1']:
            with self.assertRaises(ValueError):
                distribution.version(candidate)
        with self.assertRaises(ValueError):
            distribution.formula(Path('/tmp'), '0.1.0', 'owner/repo"')


if __name__ == '__main__':
    unittest.main()
