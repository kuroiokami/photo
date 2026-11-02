#!/usr/bin/env python3
"""Create an ad-hoc local installation candidate from a pinned Git commit."""
import argparse
from pathlib import Path
import subprocess
import sys
from macos_bundle import DEVELOPMENT_ID, RELEASE_ID, PackageError, validate_version
from release_package import build_package


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local", action="store_true", required=True, help="Local acceptance only; no public beta or notarization")
    parser.add_argument("--revision", required=True, help="Pinned commit or ref to export")
    parser.add_argument("--version", required=True, help="Three numeric components, for example 0.1.0")
    parser.add_argument("--build", required=True, help="Increasing numeric build")
    parser.add_argument("--bundle-id", default=RELEASE_ID, help="Stable packaged identity; override only for isolated QA preferences")
    parser.add_argument("--output", required=True, help="New folder for the app, DMG, manifest and checksums")
    args = parser.parse_args()
    validate_version(args.version, args.build, args.bundle_id)
    if args.bundle_id == DEVELOPMENT_ID:
        raise PackageError("Use a packaged identity distinct from the development app.")
    root = Path(__file__).resolve().parents[1]
    output = build_package(root, args.revision, args.version, args.build, args.bundle_id, args.output)
    print(f"Verified local package: {output}")
    print("Ad-hoc signed; public release signing and notarization remain outstanding.")


if __name__ == "__main__":
    try:
        main()
    except (PackageError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Photo package: {error}", file=sys.stderr)
        sys.exit(1)
