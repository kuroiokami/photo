import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import macos_bundle as bundle
import release_package as release


class PackagingPolicyTests(unittest.TestCase):
    def test_invalid_version_build_identity_and_paths_are_rejected(self):
        for version, build, identity in [('../1', '1', 'org.photo.qa'), ('1.0', '1', 'org.photo.qa'),
                                         ('01.0.0', '1', 'org.photo.qa'), ('1.0.0', '0', 'org.photo.qa'),
                                         ('1.0.0', '-1', 'org.photo.qa'), ('1.0.0', '1', '../../bad')]:
            with self.subTest(version=version, build=build, identity=identity):
                with self.assertRaises(bundle.PackageError):
                    bundle.validate_version(version, build, identity)
        bundle.validate_version('0.1.0', '123', 'com.kuroiokami.photo')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'file').write_text('original')
            (root / 'linked').symlink_to(root / 'file')
            with self.assertRaises(bundle.PackageError):
                bundle.inventory(root)

    def test_process_matching_handles_spaces_aliases_and_helper_without_prefix_collisions(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / 'Photo QA.app'
            listing = f'123 {app}/Contents/MacOS/PhotoPreviewWorker\n'
            self.assertTrue(bundle.running_inside(app, listing))
            self.assertFalse(bundle.running_inside(app, f'124 {app}.other/Contents/MacOS/Photo\n'))
            alias = Path(folder) / 'alias'
            app.mkdir()
            alias.symlink_to(app, target_is_directory=True)
            self.assertTrue(bundle.running_inside(alias, listing))

    def test_committed_export_excludes_working_edits_and_rejects_tracked_links(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            repo = root / 'repo'
            repo.mkdir()
            subprocess.run(['git', 'init', '-q', str(repo)], check=True)
            (repo / 'original.txt').write_text('committed')
            subprocess.run(['git', 'add', 'original.txt'], cwd=repo, check=True)
            subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                            'commit', '-qm', 'Fixture'], cwd=repo, check=True)
            head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo).decode().strip()
            (repo / 'original.txt').write_text('working edit')
            (repo / 'private-untracked.txt').write_text('never exported')
            self.assertEqual(release.export_commit(repo, 'HEAD', root / 'exported'), head)
            self.assertEqual((root / 'exported/original.txt').read_text(), 'committed')
            self.assertFalse((root / 'exported/private-untracked.txt').exists())
            (repo / 'linked').symlink_to('../outside')
            subprocess.run(['git', 'add', 'linked'], cwd=repo, check=True)
            subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                            'commit', '-qm', 'Link fixture'], cwd=repo, check=True)
            with self.assertRaises(bundle.PackageError):
                release.export_commit(repo, 'HEAD', root / 'rejected')
            self.assertEqual((repo / 'original.txt').read_text(), 'working edit')

    def test_checksum_mismatch_never_mounts_an_image(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'candidate.dmg').write_bytes(b'disposable fake container')
            manifest = dict(schemaVersion=1, publicReleaseReady=False,
                            diskImage=dict(filename='candidate.dmg', sha256='0' * 64))
            (root / 'manifest.json').write_text(json.dumps(manifest))
            (root / 'SHA256SUMS').write_text('mismatched checksum')
            with patch.object(release, 'mounted_image') as mount:
                with self.assertRaises(bundle.PackageError):
                    release.verify_package(root)
                mount.assert_not_called()


@unittest.skipUnless(sys.platform == 'darwin', 'Native bundle/signature/atomic install tests require macOS')
class NativePackagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory(prefix='photo-package-fixture-')
        root = Path(cls.fixture.name)
        cls.binaries = root / 'Binaries'
        cls.binaries.mkdir()
        code = root / 'fixture.c'
        code.write_text('#include <unistd.h>\nint main(int argc, char **argv) { if (argc > 1) sleep(30); return 0; }\n')
        subprocess.run(['xcrun', 'clang', '-mmacosx-version-min=14.0', str(code), '-o',
                        str(cls.binaries / 'Photo')], check=True, capture_output=True)
        shutil.copy2(cls.binaries / 'Photo', cls.binaries / 'PhotoPreviewWorker')
        resources = cls.binaries / bundle.RESOURCE_BUNDLE
        resources.mkdir()
        source_resources = Path(__file__).resolve().parents[2] / 'Sources/PhotoUI/Resources'
        for name in ('coast.png', 'dawn.png', 'dusk.png', 'PROVENANCE.md'):
            shutil.copy2(source_resources / name, resources / name)
        cls.source = Path(__file__).resolve().parents[2]

    @classmethod
    def tearDownClass(cls):
        cls.fixture.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='photo-package-test-')
        self.root = Path(self.temp.name).resolve()
        self.addCleanup(self.temp.cleanup)

    def app(self, name='Source.app', build='1', identity='org.photo.packaging-fixture'):
        app = self.root / name
        bundle.assemble(app, self.binaries, self.source, '0.1.0', build, identity, 'a' * 40)
        return app

    def test_atomic_upgrade_keeps_previous_bytes_and_drops_obsolete_resources(self):
        previous = self.app('Installed.app')
        obsolete = previous / 'Contents/Resources/obsolete.txt'
        obsolete.write_text('old build only')
        bundle.run(['/usr/bin/codesign', '--force', '--sign', '-', previous])
        old_inode = (previous / 'Contents/MacOS/Photo').stat().st_ino
        old_files = bundle.inventory(previous)
        source = self.app(build='2')
        backup = bundle.install_bundle(source, previous)
        self.assertEqual(bundle.read_info(previous)['CFBundleVersion'], '2')
        self.assertFalse((previous / 'Contents/Resources/obsolete.txt').exists())
        self.assertEqual(bundle.inventory(backup), old_files)
        self.assertEqual((backup / 'Contents/MacOS/Photo').stat().st_ino, old_inode)
        self.assertEqual(bundle.inventory(previous), bundle.inventory(source))

    def test_running_main_and_helper_refuse_install_without_changing_any_bytes(self):
        installed = self.app('Installed.app')
        source = self.app(build='2')
        original = bundle.inventory(installed)
        for name in ('Photo', 'PhotoPreviewWorker'):
            with self.subTest(executable=name):
                process = subprocess.Popen([str(installed / 'Contents/MacOS' / name), 'wait'])
                try:
                    # Query actual executable publication rather than assuming
                    # scheduler timing immediately after Popen returns.
                    deadline = time.monotonic() + 5
                    while True:
                        listing = bundle.run(['/bin/ps', '-A', '-o', 'pid=,comm=']).decode()
                        if bundle.running_inside(installed, listing):
                            break
                        if time.monotonic() >= deadline or process.poll() is not None:
                            self.fail('Fixture executable was not observed running')
                        time.sleep(0.01)
                    with self.assertRaisesRegex(bundle.PackageError, 'Quit Photo'):
                        bundle.install_bundle(source, installed)
                    self.assertEqual(bundle.inventory(installed), original)
                finally:
                    process.terminate()
                    process.wait(timeout=5)

    def test_bad_identity_links_overlap_missing_helper_and_tamper_fail_closed(self):
        installed = self.app('Installed.app')
        other = self.app('Other.app', identity='org.photo.other')
        original = bundle.inventory(installed)
        with self.assertRaises(bundle.PackageError):
            bundle.install_bundle(other, installed)
        alias = self.root / 'Alias.app'
        alias.symlink_to(installed, target_is_directory=True)
        with self.assertRaises(bundle.PackageError):
            bundle.install_bundle(other, alias)
        with self.assertRaises(bundle.PackageError):
            bundle.install_bundle(installed, installed / 'Nested.app')
        self.assertEqual(bundle.inventory(installed), original)
        (other / 'Contents/MacOS/PhotoPreviewWorker').unlink()
        with self.assertRaises(bundle.PackageError):
            bundle.verify_app(other)
        (installed / 'Contents/Resources/Legal/NOTICE').write_text('tampered')
        with self.assertRaises(bundle.PackageError):
            bundle.verify_app(installed)

    def test_backup_rename_failure_retains_the_old_app_in_its_staging_container(self):
        installed = self.app('Installed.app')
        source = self.app(build='2')
        original = bundle.inventory(installed)
        real_rename = bundle.rename_directory
        def injected(old, new, swap=False):
            if not swap:
                raise OSError('simulated backup naming failure')
            return real_rename(old, new, swap=True)
        with patch.object(bundle, 'rename_directory', side_effect=injected):
            with self.assertRaisesRegex(bundle.PackageError, 'previous app retained'):
                bundle.install_bundle(source, installed)
        retained = list(self.root.glob('.photo-install-*/Photo.app'))
        self.assertEqual(len(retained), 1)
        self.assertEqual(bundle.inventory(retained[0]), original)
        self.assertEqual(bundle.read_info(installed)['CFBundleVersion'], '2')


if __name__ == '__main__':
    unittest.main()
