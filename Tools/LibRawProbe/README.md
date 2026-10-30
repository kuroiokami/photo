# Standalone LibRaw experiment

This read-only developer probe is outside SwiftPM and the app. It requires an explicitly supplied, already-built official LibRaw tree; normal Photo installation needs no LibRaw. No vendor source or binary is included here.

The recorded pilot uses [LibRaw 0.22.3, commit cf02d66](https://github.com/LibRaw/LibRaw/tree/cf02d66eb5c19d4e46df7aee0582e47a4918509a), built with its `Makefile.devel` and `make -f Makefile.devel -j2 lib/libraw_r.a`. That configuration is optimized, zlib-only and has no OpenMP, external JPEG, LCMS, DNG SDK or RawSpeed integration. It does not represent a tuned commercial RAW engine. Review vendor instructions and [COPYRIGHT](https://github.com/LibRaw/LibRaw/blob/cf02d66eb5c19d4e46df7aee0582e47a4918509a/COPYRIGHT) when obtaining/building it.

```sh
sh scripts/benchmark-libraw.sh /path/to/LibRaw preview /path/to/photo.ARW
sh scripts/benchmark-libraw.sh /path/to/LibRaw full /path/to/photo.ARW
sh scripts/benchmark-libraw.sh /path/to/LibRaw cancel /path/to/photo.ARW
sh scripts/benchmark.sh --raw-stages-detail /path/to/photo.ARW
```

The wrapper builds a temporary probe and checks each input's SHA-256 before/after. Each input gets a fresh process. Output contains numeric timings, dimensions, field-presence/error flags and peak RSS; no filenames, metadata values or pixels. `preview` stops after metadata/embedded extraction; unpack/render fields for unrequested stages are ignored. `full` also unpacks sensor data and processes it with camera WB, sRGB 8-bit and otherwise defaults. `cancel` requests the progress callback before unpack; it does not test every mid-decode cancellation point.

For an optional camera-JPEG decode experiment, compile the probe directly:

```sh
c++ -std=c++17 -O3 -I /path/to/LibRaw Tools/LibRawProbe/main.cpp \
  /path/to/LibRaw/lib/libraw_r.a -lz -o /tmp/photo-libraw-probe
/tmp/photo-libraw-probe preview /path/to/photo.ARW /tmp/new-camera-preview.jpg
sh scripts/benchmark.sh --raw-stages-detail /tmp/new-camera-preview.jpg
```

The optional last argument creates a **new** private scratch file only when the embedded payload is JPEG. Existing files/symlinks are never replaced. Remove derived test images when finished; keep originals and personal bytes outside Git. Extraction time excludes the separately reported scratch write. The extracted image contains camera-processed JPEG pixels; its dimensions may be smaller than the sensor, and its 100% is not rendered RAW.

Compare stage scopes carefully: LibRaw extraction returns compressed JPEG bytes; Photo's first preview includes decode/orientation/downsampling. Photo metadata is read after its first preview, sharing SDK initialization. Apple and LibRaw full-render settings/active areas differ. Hash checks warm OS caches; process RSS includes frameworks and transient allocations. See the [review and pilot](../../docs/RAW_BACKEND_REVIEW.md) for results and limits.
