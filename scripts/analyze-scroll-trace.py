#!/usr/bin/env python3
"""Export anonymous Photo main-thread diagnostics from a finalized Instruments trace."""
import argparse
import collections
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
import xml.etree.ElementTree as ET


def table(trace, schema, destination, xctrace):
    subprocess.run(
        [xctrace, "export", "--input", str(trace), "--xpath",
         f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]',
         "--output", str(destination)],
        check=True, stdout=subprocess.DEVNULL,
    )
    root = ET.parse(destination).getroot()
    definition = root.find(".//schema")
    if definition is None:
        raise ValueError(f"Trace has no {schema} table; capture is not usable for this report")
    columns = [column.findtext("mnemonic") for column in definition.findall("col")]
    references = {element.attrib["id"]: element for element in root.iter() if "id" in element.attrib}

    def resolve(element):
        return references[element.attrib["ref"]] if "ref" in element.attrib else element

    rows = [{name: resolve(cell) for name, cell in zip(columns, row)} for row in root.iter("row")]
    return rows, resolve


def analyze(trace, xctrace, process, cpu_only=False):
    with tempfile.TemporaryDirectory(prefix="photo-scroll-export-") as scratch:
        root = Path(scratch)
        rows = [] if cpu_only else table(trace, "potential-hangs", root / "hangs.xml", xctrace)[0]
        intervals = []
        types = collections.Counter()
        for row in rows:
            if not row["process"].attrib.get("fmt", "").startswith(process + " ("):
                continue
            start = int(row["start"].text)
            duration = int(row["duration"].text)
            intervals.append((start, start + duration))
            types[row["hang-type"].attrib.get("fmt", "Unknown")] += 1
        merged = []
        for start, end in sorted(intervals):
            if merged and start <= merged[-1][1]:
                merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
            else:
                merged.append((start, end))
        rows, resolve = table(trace, "time-profile", root / "cpu.xml", xctrace)
        main_weight = 0
        categories = collections.Counter()
        for row in rows:
            if not row["process"].attrib.get("fmt", "").startswith(process + " ("):
                continue
            if "Main Thread" not in row["thread"].attrib.get("fmt", ""):
                continue
            weight = int(row["weight"].text)
            main_weight += weight
            names = [resolve(frame).attrib.get("name", "") for frame in row["stack"]]
            matchers = {
                "swiftUIViewGraph": ("ViewGraphRootValueUpdater.render",),
                "swiftUIFocus": ("ViewRendererHost.focusResponder",),
                "swiftUILazyGrid": ("LazyVGridLayout",),
                "swiftUIPreferences": ("PreferenceCombiner", "GraphHost.updatePreferences"),
                "appKitBitmap": ("EditedBitmap", "ImageEditDrawing"),
                "imageDecoding": ("ImageDecoder.decode", "CGImageSourceCreateThumbnail"),
                "workspaceSelection": ("refreshSelectionPresentation", "WorkspaceSelectionState.replace", "WorkspaceState.rebuildVisible"),
                "workspacePublication": ("WorkspaceState.publishMetadata", "WorkspaceState.publishDecisions"),
            }
            for category, needles in matchers.items():
                if any(needle in name for needle in needles for name in names):
                    categories[category] += weight
        if main_weight == 0:
            raise ValueError("Trace has no sampled main-thread work for the selected process; do not interpret this as zero stalls")
        return {
            "schemaVersion": 2,
            "stallDiagnosticsMeasured": not cpu_only,
            "potentialMainThreadStalls": None if cpu_only else len(intervals),
            "potentialStallsByType": None if cpu_only else dict(sorted(types.items())),
            "potentialStallUnionMilliseconds": None if cpu_only else sum(end - start for start, end in merged) / 1e6,
            "maximumPotentialStallMilliseconds": None if cpu_only else max((end - start for start, end in intervals), default=0) / 1e6,
            "mainThreadSampleWeightMilliseconds": main_weight / 1e6,
            "inclusiveMainThreadSampleMilliseconds": {key: value / 1e6 for key, value in sorted(categories.items())},
            "framePresentationMeasured": False,
            "notes": [
                "Potential hangs are Instruments diagnostics, not confirmed dropped/presented frames.",
                "Inclusive CPU categories overlap; their values must not be added together.",
                "Compare identical inputs/window/cache/indexing conditions; scripted input can add accessibility/focus overhead.",
            ],
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--xctrace", default=shutil.which("xctrace"))
    parser.add_argument("--process", default="Photo")
    parser.add_argument("--cpu-only", action="store_true", help="Time Profiler capture without hang diagnostics; absent stall values remain null")
    args = parser.parse_args()
    if not args.xctrace:
        found = subprocess.run(["xcrun", "--find", "xctrace"], capture_output=True, text=True)
        if found.returncode:
            parser.error("Select a full Xcode developer directory or pass --xctrace /path/to/xctrace")
        args.xctrace = found.stdout.strip()
    print(json.dumps(analyze(args.trace, args.xctrace, args.process, args.cpu_only), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
