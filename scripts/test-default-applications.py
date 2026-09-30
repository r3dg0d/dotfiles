"""Default applications must only update the selected user's configuration."""

import configparser
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "user/set-default-applications.py"


class DefaultApplicationsTests(unittest.TestCase):
    def check_configuration(self, use_xdg):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            home = root / "test home"
            home.mkdir()
            config_dir = root / "custom config" if use_xdg else home / ".config"
            config_dir.mkdir()
            associations = root / "defaults.json"
            associations.write_text(json.dumps({"image/png": "imv.desktop"}))
            target = config_dir / "mimeapps.list"
            target.write_text(
                "[Default Applications]\nimage/png=old.desktop;\ntext/plain=editor.desktop;\n"
                "[Added Associations]\nimage/png=old.desktop;imv.desktop;\n"
                "[Removed Associations]\nimage/png=imv.desktop;other.desktop;\n"
            )
            env = os.environ.copy()
            env["HOME"] = str(home)
            env["XDG_CONFIG_HOME"] = str(config_dir) if use_xdg else ""
            for _ in range(2):
                subprocess.run([sys.executable, str(SCRIPT), str(associations)], env=env, check=True)
            parsed = configparser.ConfigParser(interpolation=None)
            parsed.read(target)
            self.assertEqual(parsed["Default Applications"]["image/png"], "imv.desktop;")
            self.assertEqual(parsed["Default Applications"]["text/plain"], "editor.desktop;")
            self.assertEqual(parsed["Added Associations"]["image/png"], "imv.desktop;old.desktop;")
            self.assertEqual(parsed["Removed Associations"]["image/png"], "other.desktop;")
            self.assertFalse(target.with_name("mimeapps.list.tmp").exists())
            if use_xdg:
                self.assertFalse((home / ".config/mimeapps.list").exists())

    def test_custom_xdg_config(self):
        self.check_configuration(True)

    def test_home_fallback(self):
        self.check_configuration(False)


if __name__ == "__main__":
    unittest.main()
