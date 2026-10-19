"""Exercise release source inclusion and model/archive integrity with small kits."""
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import build_package as build
import setup_models as setup


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.repo = self.folder / 'repo'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Package fixture')
        self.git('config', 'user.email', 'package-fixture@example.invalid')
        for name in build.REQUIRED_APP_FILES:
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture ' + name)
        (self.repo / 'distribution/macos').mkdir(parents=True)
        for name in build.KIT_FILES:
            shutil.copy2(build.HERE / name, self.repo / 'distribution/macos' / name)
        (self.repo / 'cluster').mkdir()
        (self.repo / 'cluster/tool.py').write_text('separate delivery')
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        self.repo_patch = patch.object(build, 'REPO', self.repo)
        self.repo_patch.start()
        self.addCleanup(self.repo_patch.stop)
        self.models = self.folder / 'models'
        self.models.mkdir()
        packs = {}
        for key in ['moe', 'gat']:
            path = self.models / (key + '.zip')
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('fixture', key)
            packs[key] = dict(file=path.name, bytes=path.stat().st_size,
                              sha256=build.digest(path), version='fixture-v1')
        (self.models / 'catalog.json').write_text(json.dumps(dict(packs=packs)))
        self.output = self.folder / 'output'

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo, stderr=subprocess.PIPE, text=True).strip()

    def test_untracked_required_source_is_not_silently_omitted(self):
        (self.repo / '+Program/+GUI/NewController.m').write_text('new required code')
        with self.assertRaisesRegex(ValueError, 'NewController.m'):
            build.build(self.models, self.output, 'test-release')
        self.assertFalse(self.output.exists())

    def test_modified_and_staged_source_are_rejected(self):
        path = self.repo / build.REQUIRED_APP_FILES[0]
        path.write_text('modified')
        with self.assertRaisesRegex(ValueError, 'Commit the app'):
            build.assert_release_source()
        self.git('add', '.')
        with self.assertRaisesRegex(ValueError, 'Commit the app'):
            build.assert_release_source()

    def test_missing_committed_annotation_asset_is_rejected(self):
        self.git('rm', '+Annotations/catalog_v1.json')
        self.git('commit', '-qm', 'missing catalog')
        with self.assertRaisesRegex(ValueError, 'Required application files'):
            build.assert_release_source()

    def test_full_build_preserves_annotations_and_excludes_cluster(self):
        (self.repo / 'cluster/local-only.py').write_text('not part of this release')
        release = build.build(self.models, self.output, '20261019-fixture')
        kit = release.with_suffix('')
        catalog = json.loads((kit / 'catalog.json').read_text())
        self.assertEqual(catalog['app_commit'], self.git('rev-parse', 'HEAD'))
        self.assertEqual(catalog['package_version'], '20261019-fixture')
        self.assertEqual((kit / 'PACKAGE_VERSION').read_text(), '20261019-fixture\n')
        self.assertEqual(catalog['app_archive']['sha256'], build.digest(kit / catalog['app_archive']['file']))
        with zipfile.ZipFile(kit / catalog['app_archive']['file']) as archive:
            names = archive.namelist()
            self.assertIn('NeuroPAL_ID/+Annotations/catalog_v1.json', names)
            self.assertFalse(any(name.startswith('NeuroPAL_ID/cluster/') for name in names))
            target = self.folder / 'extracted'
            archive.extractall(target)
        setup.verify(target / 'NeuroPAL_ID')
        setup.verify(kit)
        with zipfile.ZipFile(release) as archive:
            self.assertIsNone(archive.testzip())
            self.assertIn(kit.name + '/PACKAGE_VERSION', archive.namelist())
        self.assertEqual(release.with_suffix('.zip.sha256').read_text().split()[0], build.digest(release))
        (kit / 'ACCEPTANCE.md').write_text('This fixture is not biological acceptance.')
        build.seal(kit, release)
        setup.verify(kit)
        with zipfile.ZipFile(release) as archive:
            self.assertIn(kit.name + '/ACCEPTANCE.md', archive.namelist())
        with self.assertRaises(FileExistsError):
            build.build(self.models, self.output, '20261019-fixture')

    def test_model_hash_failure_creates_no_kit(self):
        (self.models / 'moe.zip').write_bytes(b'corrupted')
        with self.assertRaisesRegex(ValueError, 'Invalid source model pack'):
            build.build(self.models, self.output, 'test-release')
        self.assertFalse(self.output.exists())

    def test_failed_build_does_not_leave_partial_kit(self):
        with patch.object(build.shutil, 'copy2', side_effect=OSError('disk full')):
            with self.assertRaisesRegex(OSError, 'disk full'):
                build.build(self.models, self.output, 'test-release')
        self.assertFalse((self.output / 'NeuroPAL-Methods-macOS-test-release').exists())

    def test_existing_archive_is_not_overwritten(self):
        self.output.mkdir()
        existing = self.output / 'NeuroPAL-Methods-macOS-test-release.zip'
        existing.write_bytes(b'previous release')
        with self.assertRaises(FileExistsError):
            build.build(self.models, self.output, 'test-release')
        self.assertEqual(existing.read_bytes(), b'previous release')

    def test_failed_reseal_preserves_previous_archive(self):
        kit = self.folder / 'kit'
        kit.mkdir()
        (kit / 'fixture.txt').write_text('fixture')
        release = self.folder / 'release.zip'
        release.write_bytes(b'previous release')
        with patch.object(build.zipfile.ZipFile, 'write', side_effect=OSError('disk full')):
            with self.assertRaisesRegex(OSError, 'disk full'):
                build.seal(kit, release)
        self.assertEqual(release.read_bytes(), b'previous release')
        self.assertFalse(list(self.folder.glob('.seal-*')))

    def test_versions_are_safe_and_source_specific(self):
        self.assertTrue(build.package_version(None, 'a' * 40).endswith('-' + 'a' * 12))
        for value in ['../elsewhere', '/absolute', 'bad version', 'x' * 81, '-unsafe']:
            with self.assertRaises(ValueError):
                build.package_version(value, 'a' * 40)

    def test_missing_or_unsafe_pack_is_rejected(self):
        catalog = json.loads((self.models / 'catalog.json').read_text())
        (self.models / 'catalog.json').write_text(json.dumps(dict(packs={})))
        with self.assertRaisesRegex(ValueError, 'both MoE and GAT'):
            build.source_packs(self.models)
        catalog['packs']['gat']['file'] = '../outside'
        (self.models / 'catalog.json').write_text(json.dumps(catalog))
        with self.assertRaisesRegex(ValueError, 'Unsafe source model pack'):
            build.source_packs(self.models)


if __name__ == '__main__':
    unittest.main()
