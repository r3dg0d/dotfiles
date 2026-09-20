#!/usr/bin/env python3
"""Exercise the publication gate with synthetic data, never workstation secrets."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("privacy_scan", Path(__file__).with_name("privacy-scan.py"))
scanner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scanner)


class PrivacyTests(unittest.TestCase):
    def test_synthetic_token_is_redacted(self):
        sample = "sk-" + "x" * 32
        findings, _ = scanner.scan("config.txt", sample.encode())
        self.assertTrue(any(category == "provider-token" for _, category in findings))
        self.assertNotIn(sample, repr(findings))

    def test_inert_placeholder_and_loopback(self):
        line = 'env.' + 'OBSIDIAN_API_KEY = "build-time-placeholder-not-a-secret";'
        findings, _ = scanner.scan("package.nix", (line + "\n127.0.0.1").encode())
        self.assertEqual(findings, [])
        self.assertEqual(scanner.scan("module.nix", b'services.displayManager.defaultSession = "hyprland";')[0], [])

    def test_paths_binary_and_assignment(self):
        samples = [
            (".env", b"ordinary text"),
            ("file.bin", b"\0"),
            ("config", ("/home/" + "private-account/file").encode()),
            ("config", ('API_' + 'KEY = "synthetic-sensitive-value"').encode()),
        ]
        for name, data in samples:
            with self.subTest(name=name):
                self.assertTrue(scanner.scan(name, data)[0])

    def test_reviewed_screenshots_are_allowed_but_only_narrowly(self):
        png = b"\x89PNG\r\n\x1a\n" + b"\0" * 512
        self.assertEqual(scanner.scan("assets/screenshots/desktop.png", png)[0], [])
        # Oversized, mislabelled, or somewhere else: still reported.
        self.assertTrue(scanner.scan("assets/screenshots/huge.png", png + b"\0" * scanner.SCREENSHOT_LIMIT)[0])
        self.assertTrue(scanner.scan("assets/screenshots/notes.png", b"plain text pretending to be a screenshot")[0])
        self.assertTrue(scanner.scan("config/desktop.png", png)[0])

    def test_index_and_history_are_not_worktree(self):
        with tempfile.TemporaryDirectory() as directory:
            old_root = scanner.ROOT
            scanner.ROOT = Path(directory)
            try:
                def git(*args):
                    return subprocess.run(["git", "-C", directory, *args], check=True, capture_output=True)
                git("init", "-q")
                git("config", "user.name", "Synthetic Test")
                git("config", "user.email", "synthetic" + "@" + "example.invalid")
                path = Path(directory) / "config.txt"
                path.write_text("sk-" + "x" * 32)
                git("add", "config.txt")
                git("commit", "-qm", "synthetic fixture")
                path.write_text("safe replacement")
                git("add", "config.txt")
                git("commit", "-qm", "replace fixture")
                # Unstaged data must not be confused with staged content.
                path.write_text("sk-" + "y" * 32)
                args = type("Args", (), {"staged": True, "history": False})()
                staged = list(scanner.candidates(args))
                self.assertEqual(staged[0][1], b"safe replacement")
                args.staged, args.history = False, True
                self.assertTrue(any(scanner.scan(name, data)[0] for name, data in scanner.candidates(args)))
            finally:
                scanner.ROOT = old_root


if __name__ == "__main__":
    unittest.main()
