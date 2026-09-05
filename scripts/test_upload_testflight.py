import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("upload", Path(__file__).with_name("upload-testflight.py"))
upload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upload)


class ArchiveValidationTests(unittest.TestCase):
    def test_archive_rejects_each_invalid_release_field(self):
        good = {"CFBundleIdentifier": "dev.rallyroo.app", "CFBundleVersion": "101.1.0",
                "CFBundleShortVersionString": "1.0", "RALLYROO_DATA_MODE": "remote",
                "RALLYROO_REMOTE_BASE_URL": "https://api.rallyroo.dev",
                "ITSAppUsesNonExemptEncryption": False, "UIDeviceFamily": [1]}
        entitlements = {"application-identifier": "5LS29Z8553.dev.rallyroo.app",
                        "com.apple.developer.team-identifier": "5LS29Z8553",
                        "aps-environment": "production", "com.apple.developer.applesignin": ["Default"]}
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            (app / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps({}))
            with patch.object(upload, "run", return_value=plistlib.dumps(entitlements)):
                (app / "Info.plist").write_bytes(plistlib.dumps(good))
                self.assertEqual(upload.verify(app, "101.1.0"), "1.0")
                for key in good.keys() - {"CFBundleShortVersionString"}:
                    with self.subTest(key=key):
                        bad = {**good, key: "wrong"}
                        (app / "Info.plist").write_bytes(plistlib.dumps(bad))
                        with self.assertRaises(RuntimeError):
                            upload.verify(app, "101.1.0")
                (app / "Info.plist").write_bytes(plistlib.dumps(good))
                (app / "PrivacyInfo.xcprivacy").unlink()
                with self.assertRaises(FileNotFoundError):
                    upload.verify(app, "101.1.0")

    def test_security_password_uses_stdin_not_argv(self):
        with patch.object(upload, "run") as call:
            upload.security(["unlock-keychain", "-p", "fixture-password", "fixture.keychain"])
            self.assertEqual(call.call_args.args[0], ["security", "-i"])
            self.assertIn(b"fixture-password", call.call_args.kwargs["input"])
            self.assertNotIn(b"quit", call.call_args.kwargs["input"])

    @unittest.skipUnless(__import__('sys').platform == 'darwin', 'Requires macOS Security CLI')
    def test_security_interactive_keychain_lifecycle(self):
        with tempfile.TemporaryDirectory() as directory:
            keychain = str(Path(directory) / 'fixture.keychain-db')
            try:
                upload.security(['create-keychain', '-p', 'fixture password', keychain])
                self.assertTrue(Path(keychain).exists())
                upload.security(['unlock-keychain', '-p', 'fixture password', keychain])
            finally:
                __import__('subprocess').run(['security', 'delete-keychain', keychain], capture_output=True)
