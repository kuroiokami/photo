#!/usr/bin/env python3
"""Verify a local package's signatures, hashes and mounted read-only DMG payload."""
import argparse
import sys
from macos_bundle import PackageError
from release_package import verify_package

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", help="Folder containing manifest.json and SHA256SUMS")
    args = parser.parse_args()
    try:
        manifest = verify_package(args.package)
        print("Verified local package from " + manifest["app"]["info"]["sourceCommit"])
        print("Integrity checks pass; public signing/notarization acceptance remains outstanding.")
    except (PackageError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"Photo verification: {error}", file=sys.stderr)
        sys.exit(1)
