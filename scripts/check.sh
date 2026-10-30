#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift format lint --strict --recursive Package.swift Sources Tests
set -- -Xswiftc -warnings-as-errors
# Some Command Line Tools releases omit this installed plugin from discovery.
# Use the selected toolchain path, never a machine-specific absolute path.
plugin_dir="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [ -f "$plugin_dir/libTestingMacros.dylib" ]; then
  set -- "$@" -Xswiftc -plugin-path -Xswiftc "$plugin_dir"
fi
swift build "$@"
swift build --product PhotoPreviewWorker "$@"
PHOTO_PREVIEW_WORKER_TEST_EXECUTABLE="$(swift build --show-bin-path)/PhotoPreviewWorker" swift test "$@"
