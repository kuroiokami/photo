#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product PhotoBench >&2
swift build -c release --product PhotoPreviewWorker >&2
bin_path="$(swift build -c release --show-bin-path)"
exec "$bin_path/PhotoBench" "$@"
