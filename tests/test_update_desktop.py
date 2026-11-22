import importlib.util
import base64
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("updater", Path(__file__).resolve().parents[1] / "scripts/update-desktop.py")
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


def metadata(linux="0.1.100", mac="100", digest="a" * 64):
    return (
        f"pkgver={linux}\nsha256sums_x86_64=('{digest}')\nsha256sums_aarch64=('{digest}')\n",
        f'version "1.0,{mac}"\nsha256 "{digest}"\ndepends_on arch: :arm64\ndepends_on macos: :tahoe\n',
    )


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "desktop-versions.json"
        self.path.write_text(json.dumps(updater.releases(*metadata())))
        self.original = self.path.read_bytes()
        self.downloads = []

    def update(self, data, verify=None):
        return updater.update(self.path, fetch=lambda url: data[0 if url == updater.LINUX_METADATA else 1],
                              verify=verify or (lambda url, digest: self.downloads.append((url, digest))))

    def test_noop_downloads_metadata_only(self):
        self.assertFalse(self.update(metadata()))
        self.assertEqual(self.downloads, [])
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_linux_only(self):
        self.assertTrue(self.update(metadata(linux="0.1.101")))
        self.assertEqual(len(self.downloads), 2)
        self.assertTrue(all("/linux/" in url for url, _ in self.downloads))
        self.assertEqual(json.loads(self.path.read_text())["platforms"]["aarch64-darwin"]["version"], "1.0-100")

    def test_mac_only(self):
        self.assertTrue(self.update(metadata(mac="101")))
        self.assertEqual(len(self.downloads), 1)
        self.assertTrue(self.downloads[0][0].endswith("Amp-1.0-101.dmg"))

    def test_all_platforms(self):
        self.assertTrue(self.update(metadata(linux="0.1.101", mac="101")))
        self.assertEqual(len(self.downloads), 3)

    def test_failure_is_atomic(self):
        calls = []
        def fail_second(url, digest):
            calls.append(url)
            if len(calls) == 2:
                raise ValueError("Checksum mismatch")
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            self.update(metadata(linux="0.1.101", mac="101"), fail_second)
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_real_checksum_verification(self):
        content = b"release artifact fixture"
        expected = "sha256-" + base64.b64encode(hashlib.sha256(content).digest()).decode()
        def fake_curl(command, check):
            self.assertTrue(check)
            Path(command[command.index("--output") + 1]).write_bytes(content)
        with patch.object(updater.subprocess, "run", side_effect=fake_curl):
            updater.verify_download("https://static.ampcode.com/fixture", expected)
            with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
                updater.verify_download("https://static.ampcode.com/fixture", "sha256-wrong")

    def test_metadata_failure_preserves_pins(self):
        with self.assertRaisesRegex(RuntimeError, "Network unavailable"):
            updater.update(self.path, fetch=lambda url: (_ for _ in ()).throw(RuntimeError("Network unavailable")))
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_rejects_downgrade_or_mutated_release(self):
        for data in [metadata(mac="99"), metadata(digest="b" * 64)]:
            with self.assertRaises(ValueError):
                self.update(data)
        self.assertEqual(self.downloads, [])
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_rejects_invalid_or_ambiguous_metadata(self):
        linux, mac = metadata()
        for data in [(linux.replace("pkgver=0.1.100", "pkgver=$(touch /tmp/bad)"), mac),
                     (linux + "pkgver=0.1.101\n", mac),
                     (linux.replace("a" * 64, "SKIP"), mac),
                     (linux, mac.replace(":tahoe", ":future"))]:
            with self.assertRaises(ValueError):
                self.update(data)
        self.assertEqual(self.downloads, [])
        self.assertEqual(self.path.read_bytes(), self.original)


if __name__ == "__main__":
    unittest.main()
