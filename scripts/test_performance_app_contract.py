#!/usr/bin/env python3
"""Check that the App Designer archive calls the bounded viewer/UI helpers."""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class PerformanceAppContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with zipfile.ZipFile(ROOT / "visualize_light.mlapp") as archive:
            cls.xml = archive.read("matlab/document.xml")
            if archive.testzip() is not None:
                raise AssertionError("Invalid App Designer archive")
        root = ET.fromstring(cls.xml)
        cls.code = "".join(e.text or "" for e in root.iter() if e.tag.split("}")[-1] == "t")

    def method(self, name):
        pattern = re.compile(
            r"^        function\s+(?:\[[^\]]*\]\s*=\s*|\w+\s*=\s*)?"
            + re.escape(name) + r"\b.*?(?=^        function\b|^    end\n)", re.M | re.S)
        match = pattern.search(self.code)
        self.assertIsNotNone(match, name)
        return match.group()

    def test_main_render_routes(self):
        self.assertIn("Program.Routines.ID.render()", self.method("DrawImageData"))
        self.assertIn("Program.Routines.ID.get_slice(", self.method("DrawZSlice"))
        self.assertNotRegex(self.code, r"(?:max|size)\(app\.image_view")
        self.assertNotRegex(self.code, r"app\.image_view\s*\(")
        self.assertNotIn("createMask(roi,app.image_view)", self.code)

    def test_public_render_bridges(self):
        for name in ("DrawImageLabels", "ImageClicked", "NeuronClicked",
                     "visual_composer", "retrieveVideoRenderViews", "scaleVideoProjection", "setVideoImage"):
            method = self.method(name)
            before = self.code[:self.code.index(method)]
            blocks = re.findall(r"^    methods \(Access = (\w+)\)", before, re.M)
            self.assertEqual(blocks[-1], "public", name)
        self.assertIn("Program.Routines.Videos.render", self.method("visual_composer"))
        self.assertIn("Program.Helpers.video_render_views", self.method("retrieveVideoRenderViews"))

    def test_video_open_is_metadata_only(self):
        method = self.method("load_h5")
        self.assertIn("Program.Helpers.h5_video_info(path)", method)
        self.assertNotIn("h5read(", method)
        self.assertIn("arr = []", method)

    def test_export_and_legacy_routes(self):
        self.assertIn("main_display_export_source", self.method("SaveIDImageMenuSelected"))
        for name in ("DecimateButtonPushed", "AdjustHistogramMenuSelected", "AutoSegmentationMenuSelected"):
            self.assertIn("main_display_legacy_volume", self.method(name))

    def test_owned_callbacks_and_log(self):
        self.assertIn("main_drag_event_callbacks", self.method("startupFcn"))
        self.assertNotIn("addlistener(app.CELL_ID, 'WindowMousePress'", self.code)
        self.assertIn("Program.Helpers.log_event", self.method("logEvent"))
        self.assertIn("Program.Helpers.cleanup_ui_runtime", self.method("delete"))
        open_code = (ROOT / "+Program/+Routines/open.m").read_text()
        self.assertIn("Program.Helpers.drag_event_listeners(app)", open_code)
        self.assertNotIn("addlistener(app.CELL_ID, 'WindowMousePress'", open_code)

    def test_tracking_scalar_observations(self):
        for name, frame in (("load_annotations", "target_frame"), ("import_annotations", "frame")):
            method = self.method(name)
            self.assertIn("roi = Program.Helpers.tracking_roi(", method)
            self.assertIn(f".rois({frame}) = roi;", method)
            self.assertIn(f"rois({frame}) = roi;", method)
            self.assertIn("rois = roi([]);", method)
            self.assertNotIn(f"rois({frame}).x_slice", method)


if __name__ == "__main__":
    unittest.main()
