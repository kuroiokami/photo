#!/usr/bin/env python3
"""Summarize macOS `sample Photo ...` without exporting paths or symbols.

Counts include waiting. They are neither CPU time nor presented-frame latency.
Categories overlap, but recursion/branches count each sample once per category.
"""
import argparse
import json
from pathlib import Path
import re

CATEGORIES = {
    "swiftUILayout": ("NSHostingView.layout",),
    "swiftUIViewGraph": ("ViewGraphRootValueUpdater.render",),
    "lazyGrid": ("LazyVGridLayout",),
    "lazyStack": ("LazyVStack",),
    "swiftUIFocus": ("focusResponder(for:",),
    "preferences": ("PreferenceCombiner",),
    "eventLoopWait": ("__CFRunLoopServiceMachPort",),
    "thumbnailView": ("PhotoImageView",),
}


def analyze(text):
    if not re.search(r"^Process:\s+Photo\s+\[\d+\]", text, re.MULTILINE):
        raise ValueError("Expected a Photo process sample")
    graph = text.partition("Call graph:")[2].splitlines()
    start = next((i for i, line in enumerate(graph)
                  if re.match(r"^    \d+ Thread_.*(?:com.apple.main-thread|: Main Thread(?:\s|$))", line)), None)
    if start is None:
        raise ValueError("Missing main-thread sample graph")
    totals = dict.fromkeys(CATEGORIES, 0)
    frames = []
    root_count = 0
    exclusive_total = 0

    def finish():
        nonlocal exclusive_total
        frame = frames.pop()
        if frame[2] < 0:
            raise ValueError("Inconsistent sample weights")
        exclusive_total += frame[2]
        for key in frame[3]:
            totals[key] += frame[2]

    for line in graph[start:]:
        if frames and re.match(r"^    \d+ Thread_", line):
            break
        match = re.match(r"^([ +!|:]*)(\d+) (.*)$", line)
        if match is None:
            continue
        depth, count, symbol = len(match[1]), int(match[2]), match[3]
        while frames and frames[-1][0] >= depth:
            finish()
        if not frames:
            if root_count:
                raise ValueError("Unexpected sample root")
            root_count = count
        inherited = set(frames[-1][3]) if frames else set()
        inherited.update(key for key, needles in CATEGORIES.items()
                         if any(needle in symbol for needle in needles))
        if frames:
            frames[-1][2] -= count
        frames.append([depth, count, count, inherited])
    while frames:
        finish()
    if root_count <= 0 or exclusive_total != root_count:
        raise ValueError("Empty or inconsistent main-thread sample")
    return {
        "schema": 1,
        "measurement": "stack sample counts including waiting; categories overlap",
        "mainThreadSampleCount": root_count,
        "inclusiveMainThreadSampleCounts": totals,
        "mainThreadSampleFractions": {key: value / root_count for key, value in totals.items()},
        "framePresentationMeasured": False,
        "cpuTimeMeasured": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sample", type=Path)
    args = parser.parse_args()
    try:
        result = analyze(args.sample.read_text())
    except (OSError, UnicodeError):
        parser.exit(2, "Could not read sample file\n")
    except ValueError as error:
        parser.exit(2, str(error) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
