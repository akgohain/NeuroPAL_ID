"""Check package integrity and failure recovery without loading real weights."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import setup_models as setup


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.here = self.folder / 'kit'; self.here.mkdir()
        self.target = self.folder / 'installed'
        self.here_patch = patch.object(setup, 'HERE', self.here)
        self.here_patch.start(); self.addCleanup(self.here_patch.stop)

    def pack(self, filename='test.zip', prefix=''):
        path = self.here / filename
        data = b'fixture'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(prefix + 'models/one.pt', data)
            archive.writestr(prefix + 'SHA256SUMS', hashlib.sha256(data).hexdigest() + '  models/one.pt\n')
        return dict(file=filename, sha256=setup.digest(path), bytes=path.stat().st_size, version='v1')

    def test_install_reuse_and_changed_file(self):
        info = self.pack()
        root = setup.unpack(info, self.target)
        self.assertEqual((root / 'models/one.pt').read_bytes(), b'fixture')
        self.assertEqual(setup.unpack(info, self.target), root)
        (root / 'models/one.pt').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Checksum failed'):
            setup.unpack(info, self.target)

    def test_changed_archive(self):
        info = self.pack(); info['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'Archive checksum'):
            setup.unpack(info, self.target)
        self.assertFalse(self.target.exists())

    def test_changed_installed_app(self):
        info = self.pack(prefix='NeuroPAL_ID/')
        app = setup.unpack(info, self.target, 'NeuroPAL_ID')
        (app / 'models/one.pt').unlink()
        with self.assertRaises(ValueError):
            setup.unpack(info, self.target, 'NeuroPAL_ID')

    def test_unsafe_archive_cleanup(self):
        for name in ['../escape', '/escape', 'C:/escape', 'x\\escape']:
            path = self.here / 'bad.zip'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr(name, b'bad')
            info = dict(file=path.name, sha256=setup.digest(path), bytes=path.stat().st_size)
            with self.assertRaises(ValueError):
                setup.unpack(info, self.target)
            self.assertFalse(self.target.exists())
            self.assertFalse(list(self.folder.glob('.install-*')))

    def test_symlink_and_empty_manifest(self):
        path = self.here / 'bad.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            member = zipfile.ZipInfo('linked')
            member.external_attr = 0o120777 << 16
            archive.writestr(member, '/elsewhere')
        with self.assertRaises(ValueError):
            setup.extract(path, self.target)
        self.target.mkdir()
        (self.target / 'SHA256SUMS').write_text('')
        with self.assertRaises(ValueError):
            setup.verify(self.target)

    def test_concurrent_install(self):
        self.target.mkdir()
        with setup.install_lock(self.target):
            with self.assertRaisesRegex(RuntimeError, 'Another setup'):
                with setup.install_lock(self.target):
                    self.fail('Concurrent setup entered the lock')
        self.assertFalse((self.target / '.setup-lock').exists())

    def test_failed_validation_keeps_previous_launcher(self):
        catalog = dict(app_commit='a' * 40, app_archive=self.pack('app.zip', 'NeuroPAL_ID/'),
                       packs={'moe': self.pack('moe.zip')})
        (self.here / 'catalog.json').write_text(json.dumps(catalog))
        files = list(self.here.iterdir())
        (self.here / 'SHA256SUMS').write_text(''.join(f'{setup.digest(p)}  {p.name}\n' for p in files))
        self.target.mkdir()
        launcher = self.target / 'start_neuropal.m'; launcher.write_text('working launcher')
        pointer = self.here / 'installed_launcher.m'; pointer.write_text('working pointer')
        args = type('Args', (), dict(root=self.target, with_gat=False))()
        with patch.object(setup.sys, 'platform', 'darwin'), \
                patch.object(setup.platform, 'machine', return_value='arm64'), \
                patch.object(setup.platform, 'mac_ver', return_value=('14.0', (), '')), \
                patch.object(setup, 'environment', return_value=Path('/fake/python')), \
                patch.object(setup, 'run', side_effect=RuntimeError('model cannot load')):
            with self.assertRaisesRegex(RuntimeError, 'model cannot load'):
                setup.install(args)
        self.assertEqual(launcher.read_text(), 'working launcher')
        self.assertEqual(pointer.read_text(), 'working pointer')
        self.assertFalse((self.target / 'installation.json').exists())


if __name__ == '__main__':
    unittest.main()
