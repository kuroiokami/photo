from contextlib import redirect_stderr
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("scroll_sample", Path(__file__).parents[1] / "analyze-scroll-sample.py")
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


def sample(graph):
    return "Process: Photo [123]\nCall graph:\n" + graph


class ScrollSampleTests(unittest.TestCase):
    def test_unions_recursion_and_branches_without_leaking_symbols(self):
        result = REPORT.analyze(sample(
            "    10 Thread_1 DispatchQueue_1: com.apple.main-thread\n"
            "    + 6 NSHostingView.layout\n"
            "    + ! 4 NSHostingView.layout /private/person/image.jpg\n"
            "    + ! : 4 PreferenceCombiner private caption\n"
            "    + ! 2 unknown private caption\n"
            "    + 3 NSHostingView.layout\n"
            "    + 1 __CFRunLoopServiceMachPort\n"
            "    99 Thread_2 other\n"
            "    + 99 NSHostingView.layout\n"))
        self.assertEqual(result["mainThreadSampleCount"], 10)
        self.assertEqual(result["inclusiveMainThreadSampleCounts"]["swiftUILayout"], 9)
        self.assertEqual(result["inclusiveMainThreadSampleCounts"]["preferences"], 4)
        self.assertEqual(result["mainThreadSampleFractions"]["eventLoopWait"], 0.1)
        self.assertFalse(result["cpuTimeMeasured"])
        self.assertFalse(result["framePresentationMeasured"])
        self.assertNotIn("private", json.dumps(result))
        self.assertNotIn("image.jpg", json.dumps(result))

    def test_rejects_wrong_process_missing_graph_and_zero_samples(self):
        for text in ["", sample(""), sample("    0 Thread_1 com.apple.main-thread\n"),
                     sample("    1 Thread_1 other\n"),
                     sample("    1 Thread_1 com.apple.main-thread\n").replace("Photo [", "Other [")]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                REPORT.analyze(text)

    def test_accepts_named_main_thread_with_multiple_dispatch_queues(self):
        result = REPORT.analyze(sample("    2 Thread_1: Main Thread   DispatchQueue_<multiple>\n"
                                       "    + 2 NSHostingView.layout\n"))
        self.assertEqual(result["inclusiveMainThreadSampleCounts"]["swiftUILayout"], 2)

    def test_cli_read_failure_does_not_expose_input_path(self):
        errors = io.StringIO()
        with patch("sys.argv", ["sample", "/private/person/photo.sample"]), \
                patch.object(Path, "read_text", side_effect=OSError("private path")), \
                redirect_stderr(errors), self.assertRaises(SystemExit) as exit_status:
            REPORT.main()
        self.assertEqual(exit_status.exception.code, 2)
        self.assertEqual(errors.getvalue(), "Could not read sample file\n")

    def test_rejects_inconsistent_child_weights(self):
        with self.assertRaises(ValueError):
            REPORT.analyze(sample("    2 Thread_1 com.apple.main-thread\n"
                                  "    + 3 NSHostingView.layout\n"))


if __name__ == "__main__":
    unittest.main()
