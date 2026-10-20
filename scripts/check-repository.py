#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check tracked project files; run checksum-pinned linters without a global install."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = (
    "LICENSE", "NOTICE", "README.md", "CONTRIBUTING.md", "SECURITY.md", "SUPPORT.md",
    "CODE_OF_CONDUCT.md", "CHANGELOG.md", ".github/CODEOWNERS",
    ".github/pull_request_template.md", ".github/ISSUE_TEMPLATE/bug_report.yml",
    ".github/ISSUE_TEMPLATE/feature_request.yml", ".github/ISSUE_TEMPLATE/config.yml",
    ".github/dependabot.yml", ".github/workflows/ci.yml", ".github/workflows/repository.yml",
)
MEDIA = {".jpg", ".jpeg", ".png", ".heic", ".arw", ".cr2", ".cr3", ".crw", ".orf", ".dng", ".nef", ".tif", ".tiff"}
LOCAL_SUFFIXES = {".sqlite", ".db", ".lrcat", ".lrdata", ".pem", ".key", ".p12", ".pfx", ".dmg", ".pkg", ".mobileprovision", ".provisionprofile"}
LOCAL_DIRS = {".build", "DerivedData", "local-data", "photos", "catalogs", "previews", "thumbnails", ".venv", "node_modules"}
ORIGINS = {"gitleaks": "gitleaks/gitleaks", "actionlint": "rhysd/actionlint"}


def tracked_files():
    output = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    return [Path(os.fsdecode(name)) for name in output.split(b"\0") if name]


def metadata_check(files):
    errors = []
    for name in REQUIRED:
        if not (ROOT / name).is_file():
            errors.append(f"Missing required repository file: {name}")
    license_path = ROOT / "LICENSE"
    if license_path.is_file() and "Apache License" not in license_path.read_text():
        errors.append("LICENSE must contain the selected Apache-2.0 terms.")
    for relative in files:
        path = ROOT / relative
        if path.is_symlink() or not path.is_file():
            errors.append(f"Tracked paths must be regular files: {relative}")
            continue
        name = relative.name.lower()
        if (relative.suffix.lower() in LOCAL_SUFFIXES
                or any(part in LOCAL_DIRS or part.endswith((".app", ".xcarchive", ".dSYM", ".lrdata")) for part in relative.parts)
                or name == ".ds_store" or name.startswith((".env", ".sqlite-", ".lrcat-")) and not name.endswith(".example")
                or any(marker in name for marker in (".sqlite-", ".db-", ".lrcat-"))):
            errors.append(f"Local data, generated output or signing material must not be tracked: {relative}")
        if relative.suffix.lower() in MEDIA:
            allowed = relative.parts[:3] == ("Sources", "PhotoUI", "Resources") or relative.parts[:2] == ("Tests", "Fixtures")
            if not allowed or not (path.parent / "PROVENANCE.md").is_file():
                errors.append(f"Image fixtures need an intentional fixture location and adjacent PROVENANCE.md: {relative}")
            continue
        if path.stat().st_size > 2 * 1024 * 1024:
            errors.append(f"Review large tracked files before adding them: {relative}")
            continue
        try:
            text = path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            errors.append(f"Unexpected binary file (review its provenance and allow it deliberately): {relative}")
            continue
        if "\r" in text or (text and not text.endswith("\n")):
            errors.append(f"Use UTF-8 text, LF endings and a final newline: {relative}")
        if relative.suffix == ".json":
            try:
                json.loads(text)
            except json.JSONDecodeError as error:
                errors.append(f"Invalid JSON in {relative}: {error.msg}")
        if relative.suffix != ".md":
            continue
        for match in re.finditer(r"\]\(([^)]+)\)", text):
            target = match.group(1).strip().strip("<>")
            if target.startswith("#") or urllib.parse.urlsplit(target).scheme:
                continue
            destination = urllib.parse.unquote(target.split("#", 1)[0])
            resolved = (path.parent / destination).resolve()
            if not resolved.is_relative_to(ROOT) or not resolved.exists():
                errors.append(f"Broken or nonportable local Markdown target in {relative}: {target}")
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return False
    print(f"Repository metadata, tracked-data policy, JSON and local Markdown targets pass ({len(files)} files).", flush=True)
    return True


def verified_tool(name, manifest, directory):
    spec = manifest[name]
    if spec["repository"] != ORIGINS[name] or not re.fullmatch(r"\d+\.\d+\.\d+", spec["version"]):
        raise ValueError(f"Invalid official tool pin for {name}")
    target = f"{platform.system()}-{platform.machine()}"
    artifact = spec["platforms"].get(target)
    if artifact is None:
        raise ValueError(f"Repository tools support macOS/Linux on arm64/x86_64; unsupported platform: {target}")
    archive = artifact["archive"]
    if Path(archive).name != archive or not re.fullmatch(r"[a-f0-9]{64}", artifact["sha256"]):
        raise ValueError(f"Invalid archive pin for {name}")
    url = f"https://github.com/{ORIGINS[name]}/releases/download/v{spec['version']}/{archive}"
    print(f"Verifying {name} {spec['version']} from its official release…", flush=True)
    with urllib.request.urlopen(url, timeout=45) as response:
        data = response.read(64 * 1024 * 1024 + 1)
    if len(data) > 64 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != artifact["sha256"]:
        raise ValueError(f"Checksum mismatch for {name}; nothing was executed")
    archive_path = directory / archive
    archive_path.write_bytes(data)
    with tarfile.open(archive_path) as package:
        entry = package.getmember(name)
        if not entry.isfile() or entry.size > 64 * 1024 * 1024:
            raise ValueError(f"Unexpected executable in {name} archive")
        # Extract only the named executable; never extract arbitrary archive paths.
        with package.extractfile(entry) as executable:
            binary = directory / name
            binary.write_bytes(executable.read())
    binary.chmod(0o755)
    return str(binary)


def run_tools(files):
    manifest = json.loads((ROOT / "scripts/repository-tools.json").read_text())
    with tempfile.TemporaryDirectory(prefix="photo-repository-") as temporary:
        directory = Path(temporary)
        gitleaks = verified_tool("gitleaks", manifest, directory)
        actionlint = verified_tool("actionlint", manifest, directory)
        subprocess.run([actionlint], cwd=ROOT, check=True)
        # Check both history and the tracked working tree. Untracked photo libraries,
        # build caches and user catalogs are neither copied nor scanned here.
        subprocess.run([gitleaks, "git", str(ROOT), "--redact=100", "--no-banner", "--log-opts=--all"], cwd=ROOT, check=True)
        snapshot = directory / "tracked"
        snapshot.mkdir()
        for relative in files:
            target = snapshot / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        subprocess.run([gitleaks, "dir", str(snapshot), "--redact=100", "--no-banner"], cwd=ROOT, check=True)
    print("Workflow lint and redacted history/working-tree secret scans pass.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata-only", action="store_true", help="Offline file/link checks only; does not claim workflow or secret scanning")
    args = parser.parse_args()
    files = tracked_files()
    if not metadata_check(files):
        return 1
    if not args.metadata_only:
        run_tools(files)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print(f"Repository checks failed: {error}", file=sys.stderr)
        sys.exit(1)
