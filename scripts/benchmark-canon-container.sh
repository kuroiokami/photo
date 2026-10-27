#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo 'Usage: sh scripts/benchmark-canon-container.sh /disposable/public-eos-r.CR3 [/tmp/canon-container.json]' >&2
  exit 2
fi
# The optional benchmark accepts only the documented CC0 reference fixture.
python3 - "$1" <<'PY'
import hashlib,json,sys
from pathlib import Path
reference=json.loads(Path('docs/fixtures/public-raw-provenance.json').read_text())['files'][0]
image=Path(sys.argv[1])
if not image.is_file() or hashlib.sha256(image.read_bytes()).hexdigest()!=reference['sha256']:
    raise SystemExit('Expected the unmodified CC0 Canon EOS R fixture documented in docs/fixtures/public-raw-provenance.json')
PY
PHOTO_CANON_BENCHMARK_FIXTURE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
PHOTO_CANON_BENCHMARK_REPORT="${2:-/tmp/photo-canon-container.json}"
export PHOTO_CANON_BENCHMARK_FIXTURE PHOTO_CANON_BENCHMARK_REPORT
plugin_dir="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
set --
if [ -f "$plugin_dir/libTestingMacros.dylib" ]; then
  set -- -Xswiftc -plugin-path -Xswiftc "$plugin_dir"
fi
swift test -c release --filter CanonEmbeddedPreviewTests "$@"
python3 - "$PHOTO_CANON_BENCHMARK_FIXTURE" "$PHOTO_CANON_BENCHMARK_REPORT" <<'PY'
import hashlib,json,math,statistics,sys
from pathlib import Path
reference=json.loads(Path('docs/fixtures/public-raw-provenance.json').read_text())['files'][0]
assert hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest()==reference['sha256'],'Original changed'
report=json.loads(Path(sys.argv[2]).read_text())
for buffered in (False,True):
    samples=[sample for sample in report['samples'] if sample['buffered']==buffered]
    times=sorted(sample['milliseconds'] for sample in samples)
    print(('buffered' if buffered else 'unbuffered control')+': median=%.3f ms p95=%.3f ms reads=%s bytes=%s' % (statistics.median(times),times[math.ceil(len(times)*.95)-1],sorted({s['reads'] for s in samples}),sorted({s['bytes_read'] for s in samples})))
print('Original SHA-256 unchanged. Report:',sys.argv[2])
PY
