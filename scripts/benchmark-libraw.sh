#!/bin/sh
# Requires an explicitly supplied, already-built official LibRaw source tree.
# No download, image writes, runtime dependency or vendor source redistribution.
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -lt 3 ]; then
  echo 'Usage: sh scripts/benchmark-libraw.sh LIBRAW_SOURCE preview|full|cancel FILE...' >&2
  exit 2
fi
libraw_source=$1
probe_mode=$2
shift 2
case "$probe_mode" in preview|full|cancel) ;; *) exit 2 ;; esac
probe_work=$(mktemp -d "${TMPDIR:-/tmp}/photo-libraw-probe.XXXXXX")
trap 'rm -rf "$probe_work"' EXIT HUP INT TERM
c++ -std=c++17 -O3 -I "$libraw_source" Tools/LibRawProbe/main.cpp \
  "$libraw_source/lib/libraw_r.a" -lz -o "$probe_work/probe"
for probe_input in "$@"; do
  probe_before=$(shasum -a 256 < "$probe_input")
  probe_result=$("$probe_work/probe" "$probe_mode" "$probe_input")
  probe_after=$(shasum -a 256 < "$probe_input")
  if [ "$probe_before" != "$probe_after" ]; then
    echo 'Original image changed during the read-only probe.' >&2
    exit 1
  fi
  printf '%s\n' "$probe_result"
done
