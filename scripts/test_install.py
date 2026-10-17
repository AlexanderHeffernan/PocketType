"""Exercise the public installer with a signed local app and offline release assets."""
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class InstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory()
        cls.release = Path(cls.fixture.name)
        app = cls.release / "PocketType.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        shutil.copyfile("/usr/bin/true", app / "Contents/MacOS/PocketType")
        (app / "Contents/MacOS/PocketType").chmod(0o755)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.local.drift.typing", "CFBundleExecutable": "PocketType",
            "CFBundleVersion": "1.2.3", "CFBundlePackageType": "APPL",
        }))
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        cls.archive = cls.release / "PocketType.zip"
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(cls.archive)], check=True)
        (cls.release / "SHA256SUMS").write_text(hashlib.sha256(cls.archive.read_bytes()).hexdigest() + "  PocketType.zip\n")
        (cls.release / "release.json").write_text(json.dumps({"tag_name": "v1.2.3"}))

    @classmethod
    def tearDownClass(cls):
        cls.fixture.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.dest = self.home / "Applications/PocketType.app"
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin", FIXTURE=str(self.release))
        self.command("pgrep", "exit 1")
        self.command("open", 'printf "%s\\n" "$@" > "$HOME/opened"')
        self.command("curl", '''
for arg in "$@"; do
    if [ "${next:-}" = output ]; then output="$arg"; next=""; fi
    if [ "$arg" = -o ]; then next=output; fi
    case "$arg" in https://*) url="$arg";; esac
done
case "$url" in
    https://api.github.com/repos/AlexanderHeffernan/PocketType/releases/latest) file=release.json;;
    https://github.com/AlexanderHeffernan/PocketType/releases/download/v1.2.3/PocketType.zip) file=PocketType.zip;;
    https://github.com/AlexanderHeffernan/PocketType/releases/download/v1.2.3/SHA256SUMS) file=SHA256SUMS;;
    *) exit 19;;
esac
cp "$FIXTURE/$file" "$output"
if [ "${TAMPER:-}" = yes ] && [ "$file" = PocketType.zip ]; then printf tampered >> "$output"; fi
''')

    def command(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -eu\n" + body + "\n")
        path.chmod(0o755)

    def install(self):
        return subprocess.run(["bash", str(Path(__file__).resolve().parent.parent / "install.sh")],
                              env=self.env, text=True, capture_output=True)

    def existing_app(self):
        shutil.copytree(self.release / "PocketType.app", self.dest)
        (self.dest / "keep-me").write_text("previous installation")

    def test_install_and_replace_only_after_validation(self):
        for attempt in range(2):
            if attempt:
                (self.dest / "previous-only").write_text("old installation")
            result = self.install()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(plistlib.loads((self.dest / "Contents/Info.plist").read_bytes())["CFBundleVersion"], "1.2.3")
            self.assertFalse((self.dest / "previous-only").exists())
            self.assertIn(str(self.dest), (self.home / "opened").read_text())
        self.assertEqual(list(self.dest.parent.glob(".pockettype-install.*")), [])

    def test_bad_download_does_not_replace_or_launch_existing_app(self):
        self.existing_app()
        self.env["TAMPER"] = "yes"
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.dest / "keep-me").read_text(), "previous installation")
        self.assertFalse((self.home / "opened").exists())

    def test_refuses_unrelated_app_and_dangling_symlink(self):
        self.existing_app()
        info = self.dest / "Contents/Info.plist"
        info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "another.app"}))
        self.assertNotEqual(self.install().returncode, 0)
        self.assertTrue((self.dest / "keep-me").exists())
        shutil.rmtree(self.dest)
        self.dest.symlink_to(self.home / "missing.app")
        self.assertNotEqual(self.install().returncode, 0)
        self.assertTrue(self.dest.is_symlink())

    def test_failed_move_restores_previous_app(self):
        self.existing_app()
        self.command("mv", 'case "$1" in */unpacked/PocketType.app) exit 23;; esac\nexec /bin/mv "$@"')
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual((self.dest / "keep-me").read_text(), "previous installation")
        self.assertFalse((self.home / "opened").exists())
