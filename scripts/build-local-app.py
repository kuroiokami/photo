#!/usr/bin/env python3
"""Build the working tree and replace only a stopped development app."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
from macos_bundle import DEVELOPMENT_ID, PackageError, assemble, install_bundle, require_stopped, run


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    app = root / ".build/Photo.app"
    require_stopped(app)
    configuration = "release" if args.release else "debug"
    for product in ("Photo", "PhotoPreviewWorker"):
        subprocess.run(["swift", "build", "-c", configuration, "--product", product], cwd=root, check=True)
    binaries = Path(run(["swift", "build", "-c", configuration, "--show-bin-path"], cwd=root).decode().strip())
    revision = run(["git", "rev-parse", "HEAD"], cwd=root).decode().strip()
    app.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="photo-local-") as folder:
        staged = Path(folder) / "Photo.app"
        assemble(staged, binaries, root, "0.1.0", "1", DEVELOPMENT_ID, revision,
                 source_kind="working-tree", source_dirty=bool(run(["git", "status", "--porcelain"], cwd=root).strip()))
        backup = install_bundle(staged, app)
    print(f"Development app: {app}")
    if backup:
        print(f"Previous app retained: {backup}")


if __name__ == "__main__":
    try:
        main()
    except (PackageError, OSError, subprocess.CalledProcessError) as error:
        print(f"Photo build: {error}", file=sys.stderr)
        sys.exit(1)
