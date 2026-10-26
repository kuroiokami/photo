import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

SPEC = importlib.util.spec_from_file_location("scroll_trace", Path(__file__).parents[1] / "analyze-scroll-trace.py")
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


def cell(tag, text=None, fmt=None):
    value = ET.Element(tag, {} if fmt is None else {"fmt": fmt})
    value.text = None if text is None else str(text)
    return value


class ScrollTraceTests(unittest.TestCase):
    def test_filters_other_processes_merges_overlap_and_omits_raw_data(self):
        def hang(start, duration, process="Photo (123)"):
            return {"start": cell("start", start), "duration": cell("duration", duration),
                    "process": cell("process", fmt=process), "hang-type": cell("hang", fmt="Microhang")}

        stack = ET.Element("stack")
        ET.SubElement(stack, "frame", name="ViewGraphRootValueUpdater.render(interval:updateDisplayList:targetTimestamp:)")
        ET.SubElement(stack, "frame", name="ViewRendererHost.focusResponder(for:)")
        ET.SubElement(stack, "frame", name="private caption /private/user/photo.jpg")
        cpu = {"process": cell("process", fmt="Photo (123)"),
               "thread": cell("thread", fmt="Main Thread (123)"), "weight": cell("weight", 1_000_000), "stack": stack}
        exports = [([hang(0, 40_000_000), hang(20_000_000, 40_000_000), hang(0, 100_000_000, "Other (2)")], lambda x: x),
                   ([cpu, dict(cpu, process=cell("process", fmt="Other (2)"))], lambda x: x)]
        with patch.object(REPORT, "table", side_effect=exports):
            result = REPORT.analyze(Path("/private/source.trace"), "unused", "Photo")
        self.assertEqual(result["potentialMainThreadStalls"], 2)
        self.assertEqual(result["potentialStallUnionMilliseconds"], 60)
        self.assertEqual(result["mainThreadSampleWeightMilliseconds"], 1)
        self.assertEqual(result["inclusiveMainThreadSampleMilliseconds"]["swiftUIFocus"], 1)
        self.assertFalse(result["framePresentationMeasured"])
        self.assertNotIn("/private/", json.dumps(result))
        self.assertNotIn("caption", json.dumps(result))

    def test_empty_or_wrong_process_capture_is_not_reported_as_perfect_scrolling(self):
        with patch.object(REPORT, "table", side_effect=[([], lambda x: x), ([], lambda x: x)]):
            with self.assertRaises(ValueError):
                REPORT.analyze(Path("trace"), "unused", "Photo")

    def test_cpu_only_does_not_invent_zero_stalls_or_export_private_symbols(self):
        stack = ET.Element("stack")
        ET.SubElement(stack, "frame", name="WorkspaceState.publishMetadata private /user/image.jpg")
        cpu = {"process": cell("process", fmt="Photo (123)"),
               "thread": cell("thread", fmt="Main Thread (123)"), "weight": cell("weight", 2_000_000), "stack": stack}
        with patch.object(REPORT, "table", return_value=([cpu], lambda x: x)) as export:
            result = REPORT.analyze(Path("trace"), "unused", "Photo", cpu_only=True)
        self.assertEqual(export.call_count, 1)
        self.assertEqual(export.call_args.args[1], "time-profile")
        self.assertFalse(result["stallDiagnosticsMeasured"])
        self.assertIsNone(result["potentialMainThreadStalls"])
        self.assertIsNone(result["potentialStallUnionMilliseconds"])
        self.assertEqual(result["inclusiveMainThreadSampleMilliseconds"]["workspacePublication"], 2)
        self.assertNotIn("private", json.dumps(result))
        self.assertNotIn("image.jpg", json.dumps(result))

    def test_table_resolves_references_and_rejects_missing_schema(self):
        xml = '<result><schema><col><mnemonic>duration</mnemonic></col></schema><row><duration id="1">33</duration></row><row><duration ref="1"/></row></result>'
        with tempfile.TemporaryDirectory() as scratch:
            destination = Path(scratch) / "table.xml"
            def export(*args, **kwargs):
                destination.write_text(xml)
            with patch.object(REPORT.subprocess, "run", side_effect=export):
                rows, _ = REPORT.table(Path("trace"), "example", destination, "xctrace")
            self.assertEqual([row["duration"].text for row in rows], ["33", "33"])
            with patch.object(REPORT.subprocess, "run", side_effect=lambda *a, **k: destination.write_text('<result/>')):
                with self.assertRaises(ValueError):
                    REPORT.table(Path("trace"), "missing", destination, "xctrace")


if __name__ == "__main__":
    unittest.main()
