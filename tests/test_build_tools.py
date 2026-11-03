"""Offline checks for build safety and reproducibility; no browser data access."""
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest import mock

PROJECT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, PROJECT / f"scripts/{name}.py")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


cef = module("build")
chromium = module("build_chromium")


class BuildSafetyTests(unittest.TestCase):
    def test_checkout_cannot_be_home_repository_root_or_spaced_path(self):
        for path in (Path.home(), PROJECT, Path("/"), Path("/tmp/unsafe path")):
            with self.subTest(path=path), self.assertRaises(ValueError):
                chromium.ChromiumBuild(path)

    def test_build_identity_pins_full_browser_and_separate_data(self):
        lock = json.loads((PROJECT / "chromium.lock.json").read_text())
        for key in ("revision", "depot_tools_revision"):
            self.assertRegex(lock[key], r"^[0-9a-f]{40}$")
        self.assertEqual(lock["target"], "chrome")
        patch = (PROJECT / "chromium/patches/0001-aelo-branding-and-data-root.patch").read_text()
        self.assertIn('+MAC_BUNDLE_ID=dev.aelo.chromium', patch)
        self.assertIn('+      product_dir_name = "Aelo/Chromium";', patch)
        self.assertIn('+const char kDefaultServiceName[] = "Aelo Safe Storage";', patch)
        self.assertIn('/Library/Application Support/Aelo/Chromium/NativeMessagingHosts', patch)
        overrides = json.loads((PROJECT / 'chromium/dependency-overrides.json').read_text())['overrides']
        self.assertEqual(set(lock['custom_deps']), {entry['path'] for entry in overrides})
        self.assertEqual(lock['custom_deps']['src/third_party/clang-format/script'],
                         lock['custom_deps']['src/third_party/webpagereplay/third_party/clang-format/script'])
        for entry in overrides:
            self.assertRegex(entry['replacement_revision'], r'^[0-9a-f]{40}$')
            if entry.get('transport_only'):
                self.assertEqual(entry['original_revision'], entry['replacement_revision'])
                self.assertEqual(entry['repository'], 'https://github.com/google-ai-edge/LiteRT.git')
            else:
                self.assertTrue(entry['repository'].startswith('https://chromium.googlesource.com/'))
            self.assertEqual(lock['custom_deps'][entry['path']], entry['repository'] + '@' + entry['replacement_revision'])
        args = (PROJECT / "chromium/args.gn").read_text()
        for flag in ("no_sandbox", "disable_web_security", "ignore_certificate_errors"):
            self.assertNotIn(flag, args)

    def test_existing_repository_is_not_repointed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            subprocess.run(["git", "init", "-q", str(source)], check=True)
            subprocess.run(["git", "remote", "add", "origin", "file:///original"], cwd=source, check=True)
            builder = chromium.ChromiumBuild(root / "build")
            with self.assertRaisesRegex(RuntimeError, "Unexpected source origin"):
                builder.ensure_git(source, "file:///different", "a" * 40)
            actual = subprocess.check_output(["git", "remote", "get-url", "origin"], cwd=source, text=True).strip()
            self.assertEqual(actual, "file:///original")

    def test_nonempty_nonrepository_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            sentinel = source / "keep.txt"
            sentinel.write_text("unrelated source")
            builder = chromium.ChromiumBuild(root / "build")
            with self.assertRaisesRegex(RuntimeError, "nonempty"):
                builder.ensure_git(source, "file:///unused", "a" * 40)
            self.assertEqual(sentinel.read_text(), "unrelated source")
            self.assertFalse((source / ".git").exists())

    def test_source_guard_accepts_only_clean_declared_gitlink_overrides(self):
        with tempfile.TemporaryDirectory() as directory:
            builder = chromium.ChromiumBuild(Path(directory) / 'build')
            source = builder.src
            source.mkdir(parents=True)
            dependency = source / 'dependency'
            dependency.mkdir()

            def git(path, *args):
                return subprocess.check_output([
                    'git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                    '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', *args
                ], cwd=path, text=True).strip()

            git(source, 'init', '-q')
            git(dependency, 'init', '-q')
            tracked = dependency / 'input.txt'
            tracked.write_text('original\n')
            git(dependency, 'add', 'input.txt')
            git(dependency, 'commit', '-qm', 'original')
            original = git(dependency, 'rev-parse', 'HEAD')
            owned = source / 'owned.txt'
            owned.write_text('keep\n')
            git(source, 'add', 'owned.txt')
            git(source, 'update-index', '--add', '--cacheinfo', '160000,' + original + ',dependency')
            git(source, 'commit', '-qm', 'source baseline')
            tracked.write_text('updated\n')
            git(dependency, 'commit', '-qam', 'public override')
            replacement = git(dependency, 'rev-parse', 'HEAD')
            with mock.patch.dict(chromium.LOCK, {'custom_deps': {
                    'src/dependency': 'https://chromium.googlesource.com/fixture.git@' + replacement}}):
                builder.check_source_changes()
                tracked.write_text('uncommitted edit\n')
                with self.assertRaisesRegex(RuntimeError, 'unexpected local source changes'):
                    builder.check_source_changes()
                tracked.write_text('updated\n')
                owned.write_text('local source edit\n')
                with self.assertRaisesRegex(RuntimeError, 'unexpected local source changes'):
                    builder.check_source_changes()
                owned.write_text('keep\n')
                git(source, 'add', 'dependency')
                with self.assertRaisesRegex(RuntimeError, 'unexpected local source changes'):
                    builder.check_source_changes()

    def test_dependency_validation_rejects_partial_and_wrong_checkouts(self):
        with tempfile.TemporaryDirectory() as directory:
            builder = chromium.ChromiumBuild(Path(directory) / 'build')
            dependency = builder.src / 'dependency'
            dependency.mkdir(parents=True)

            def git(path, *args):
                return subprocess.check_output([
                    'git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                    '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', *args
                ], cwd=path, text=True).strip()

            git(dependency, 'init', '-q')
            tracked = dependency / 'schema.fbs'
            tracked.write_text('committed fixture\n')
            git(dependency, 'add', 'schema.fbs')
            git(dependency, 'commit', '-qm', 'complete dependency')
            revision = git(dependency, 'rev-parse', 'HEAD')
            manifest = builder.checkout / '.gclient_entries'

            def entries(path, rev):
                manifest.write_text('entries = ' + repr({path: 'https://example.invalid/source.git@' + rev}))

            entries('src/dependency', revision)
            builder.validate_dependencies()
            tracked.unlink()
            with self.assertRaisesRegex(RuntimeError, 'Missing tracked files'):
                builder.validate_dependencies()
            tracked.write_text('committed fixture\n')
            entries('src/dependency', '0' * 40)
            with self.assertRaisesRegex(RuntimeError, 'Unexpected dependency revision'):
                builder.validate_dependencies()
            empty = builder.src / 'unfinished'
            empty.mkdir()
            git(empty, 'init', '-q')
            entries('src/unfinished', revision)
            with self.assertRaisesRegex(RuntimeError, 'has no HEAD'):
                builder.validate_dependencies()
            entries('../outside-source', revision)
            with self.assertRaisesRegex(RuntimeError, 'escapes source checkout'):
                builder.validate_dependencies()
            self.assertEqual(tracked.read_text(), 'committed fixture\n')

    def test_previous_live_command_prevents_duplicate_build(self):
        with tempfile.TemporaryDirectory() as directory:
            builder = chromium.ChromiumBuild(Path(directory) / "build")
            builder.write_state({"status": "running", "pid": os.getpid()})
            with self.assertRaises(RuntimeError):
                builder.check_previous_process()
            builder.write_state({"status": "completed", "returncode": 0})
            builder.check_previous_process()
            self.assertFalse(list(builder.root.glob('.state-*')))

    def test_preflight_keeps_download_and_lfs_configuration_local(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate = root / 'bundled-lfs'
            candidate.write_text('#!/bin/sh\nexit 0\n')
            candidate.chmod(0o700)
            builder = chromium.ChromiumBuild(root / 'build')
            with mock.patch.dict(os.environ, {'AELO_GIT_LFS': str(candidate)}), \
                    mock.patch.object(chromium.sys, 'platform', 'darwin'), \
                    mock.patch.object(chromium.platform, 'machine', return_value='arm64'), \
                    mock.patch.object(chromium.shutil, 'disk_usage', return_value=mock.Mock(free=200 * 1024**3)), \
                    mock.patch.object(chromium.shutil, 'which', return_value=None), \
                    mock.patch.object(builder, 'run') as run:
                builder.preflight(require_xcode=False)
            self.assertEqual((builder.root / 'bin/git-lfs').resolve(), candidate.resolve())
            self.assertEqual(Path(builder.env['BOTO_CONFIG']).parent, builder.root)
            self.assertEqual(builder.env['BOTO_CONFIG'], builder.env['BOTO_PATH'])
            self.assertIn(str(builder.root / 'gsutil-state'), Path(builder.env['BOTO_CONFIG']).read_text())
            self.assertEqual(builder.env['SWARMING_HEADLESS'], '1')
            run.assert_called_once_with('git-lfs', 'version')

    def test_icon_container_has_all_resolution_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sizes = {"16x16": 16, "16x16@2x": 32, "32x32": 32, "32x32@2x": 64,
                     "128x128": 128, "128x128@2x": 256, "256x256": 256,
                     "256x256@2x": 512, "512x512": 512, "512x512@2x": 1024}
            # Only the PNG header is needed to inspect container assembly.
            for name, size in sizes.items():
                data = b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR'
                data += struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0) + b'\0' * 4
                (root / f"icon_{name}.png").write_bytes(data)
            destination = root / "Aelo.icns"
            cef.write_icns(root, destination)
            data = destination.read_bytes()
            self.assertEqual(data[:4], b"icns")
            self.assertEqual(struct.unpack('>I', data[4:8])[0], len(data))
            offset, kinds = 8, []
            while offset < len(data):
                kinds.append(data[offset:offset+4])
                length = struct.unpack('>I', data[offset+4:offset+8])[0]
                self.assertGreater(length, 8)
                self.assertEqual(data[offset+8:offset+16], b'\x89PNG\r\n\x1a\n')
                offset += length
            self.assertEqual(offset, len(data))
            self.assertEqual(len(set(kinds)), 10)
            (root / "icon_16x16.png").write_bytes(b"not a PNG")
            with self.assertRaisesRegex(RuntimeError, "Invalid icon"):
                cef.write_icns(root, destination)


if __name__ == "__main__":
    unittest.main()
