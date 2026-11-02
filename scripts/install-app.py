#!/usr/bin/env python3
"""Install a verified local package after Quit, retaining a complete previous app."""
import argparse
import sys
from macos_bundle import PackageError, install_bundle

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True)
    parser.add_argument("--destination", required=True)
    args = parser.parse_args()
    try:
        backup = install_bundle(args.app, args.destination)
        print(f"Installed: {args.destination}")
        if backup:
            print(f"Previous app retained: {backup}")
    except (PackageError, OSError) as error:
        print(f"Photo install: {error}", file=sys.stderr)
        sys.exit(1)
