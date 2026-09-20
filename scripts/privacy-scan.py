#!/usr/bin/env python3
"""Conservative publication checks; reports locations/categories, never values.

Run from any directory. --staged examines the index, --history every reachable
commit. Heuristics supplement human review and cannot establish data ownership.
"""
import argparse
import ipaddress
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    "private-key": r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY",
    "provider-token": r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16}|hf_[A-Za-z0-9]{20,})\b",
    "age-identity": r"\bAGE-SECRET-KEY-1[A-Z0-9]+",
    "uuid": r"\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b",
    "mac-address": r"(?<![\w:])(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}(?![\w:])",
    "email": r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b",
    "phone-like": r"(?<!\w)\+\d{1,3}[ -]\(?\d{2,4}\)?[ -]\d{3,4}[ -]\d{3,4}(?!\w)",
    "network-or-machine-identifier": r"(?i)\b(?:ssid|bssid|machine[_-]?id|serial[_-]?number)\s*[\"']?\s*[:=]\s*[\"'][^\"'\n]+[\"']",
    "phone-domestic": r"(?<!\w)\(\d{3}\)[ -]\d{3}[ -]\d{4}(?!\w)",
    "credential-in-url": r"https?://[^\s/\"']+:[^\s/\"']+@",
    "local-flake-input": r"(?:url|path)\s*=\s*\"(?:path:)?/(?:home|root|Users|etc)/",
    "credential-assignment": r"(?i)\b(?:[A-Z_]*(?:API_KEY|TOKEN|PASSWORD|PASSWD|PRIVATE_KEY|CLIENT_SECRET)|(?:[A-Z_]+_)?(?:COOKIE|SESSION)|token|secret)\s*[\"']?\s*[:=]\s*[\"']([^\"'\n]+)[\"']",
}
RX = {name: re.compile(pattern) for name, pattern in PATTERNS.items()}
KEYWORDS = re.compile(r"API_KEY|API_TOKEN|TOKEN|SECRET|PASSWORD|PASSWD|PRIVATE_KEY|AUTH|BEARER|COOKIE|SESSION|AWS_|OPENAI_|ANTHROPIC_|GITHUB_TOKEN|HF_TOKEN", re.I)
FORBIDDEN_PARTS = {".ssh", ".gnupg", ".claude", ".codex", "backups", "secrets", "private", "node_modules", ".cache", ".var"}
FORBIDDEN_NAMES = {".env", "machine-id", "shadow", "cookies", "cookies.sqlite", "login data", "key4.db", "logins.json", ".bash_history", ".zsh_history", "hosts.yml", "auth.json"}
FORBIDDEN_SUFFIXES = {".pem", ".key", ".asc", ".p12", ".pfx", ".db", ".sqlite", ".log", ".bak"}
# Screenshots are the one kind of binary this repository publishes. They are
# reviewed by eye before being added -- for visible credentials, window titles,
# private documents and personal identifiers -- which no regex can do. The
# exemption is deliberately narrow: only PNGs, only under this directory, only
# up to this size, and only if the bytes really are a PNG, so nothing else can
# be smuggled in under an image's name.
SCREENSHOT_DIRECTORY = "assets/screenshots"
SCREENSHOT_MAGIC = b"\x89PNG\r\n\x1a\n"
SCREENSHOT_LIMIT = 2 * 1024 * 1024


def is_reviewed_screenshot(path, data):
    return (path.parent.as_posix() == SCREENSHOT_DIRECTORY and path.suffix == ".png"
            and data.startswith(SCREENSHOT_MAGIC))


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def scan(name, data):
    findings = []
    path = Path(name.removesuffix(" (history)"))
    if (FORBIDDEN_PARTS.intersection(path.parts) or path.name.lower() in FORBIDDEN_NAMES
            or path.name.startswith(".env.") or path.suffix in FORBIDDEN_SUFFIXES):
        findings.append((0, "sensitive-or-state-filename"))
    if path.parent.as_posix() == SCREENSHOT_DIRECTORY:
        # Anything here must really be a PNG image: the exemption below is for
        # reviewed screenshots, not for a text file wearing a .png name.
        if not is_reviewed_screenshot(path, data):
            findings.append((0, "screenshot-directory-non-image"))
        elif len(data) > SCREENSHOT_LIMIT:
            findings.append((0, "screenshot-over-size-limit"))
        return findings, 0
    if len(data) > 262144:
        findings.append((0, "unexpected-large-file"))
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return findings + [(0, "binary-file")], 0
    if "\x00" in text:
        findings.append((0, "binary-file"))
    keyword_lines = 0
    for number, line in enumerate(text.splitlines(), 1):
        keyword_lines += bool(KEYWORDS.search(line))
        for category, regex in RX.items():
            for match in regex.finditer(line):
                if category == "email" and match.group() == "autovt@tty1.service":
                    # This exact systemd unit in the boot comment is not email.
                    continue
                if category == "credential-assignment":
                    value = match.group(1)
                    if value == "build-time-placeholder-not-a-secret" or value.startswith(("$", "<")):
                        continue
                findings.append((number, category))
        for match in re.finditer(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])", line):
            try:
                address = ipaddress.ip_address(match.group())
            except ValueError:
                continue
            if str(address) not in {"127.0.0.1", "0.0.0.0"}:
                findings.append((number, "ip-or-version-needs-review"))
        # Reject concrete personal home paths; dynamic interpolation and the
        # documented neutral account are allowed.
        for match in re.finditer(r"/(?:home|Users)/([A-Za-z_][A-Za-z0-9_.-]*)", line):
            if match.group(1) != "user":
                findings.append((number, "personal-home-path"))
    return findings, keyword_lines


def candidates(args):
    if args.staged:
        for record in git("ls-files", "--stage", "-z").split(b"\0"):
            if not record:
                continue
            meta, name = record.split(b"\t", 1)
            mode, oid, stage = meta.split()
            label = name.decode()
            if mode not in {b"100644", b"100755"} or stage != b"0":
                yield label, b"\x00unsupported git entry"
            else:
                yield label, git("cat-file", "blob", oid.decode())
    elif args.history:
        commits = git("rev-list", "--all").splitlines()
        seen = set()
        for commit in commits:
            for record in git("ls-tree", "-r", "-z", commit.decode()).split(b"\0"):
                if not record:
                    continue
                meta, name = record.split(b"\t", 1)
                mode, kind, oid = meta.split()
                key = (name, oid)
                if key in seen:
                    continue
                seen.add(key)
                label = name.decode() + " (history)"
                if kind != b"blob" or mode not in {b"100644", b"100755"}:
                    yield label, b"\x00unsupported git entry"
                else:
                    yield label, git("cat-file", "blob", oid.decode())
        if not commits:
            print("History: no commits")
    else:
        for path in sorted(ROOT.rglob("*")):
            if ".git" in path.relative_to(ROOT).parts:
                continue
            if path.is_symlink():
                yield str(path.relative_to(ROOT)), b"\x00symlink requires review"
            elif path.is_file():
                yield str(path.relative_to(ROOT)), path.read_bytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--staged", action="store_true")
    group.add_argument("--history", action="store_true")
    args = parser.parse_args()
    total = errors = keywords = 0
    for name, data in candidates(args):
        total += 1
        findings, count = scan(name, data)
        keywords += count
        for line, category in findings:
            print(f"REVIEW {name}:{line}: {category}")
        errors += len(findings)
    print(f"Checked {total} files/blobs; {errors} findings; {keywords} keyword-reference lines (manual review required).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
