import copy
import hashlib
import json
import unittest
from additional_voices import merge_calibration


class AdditionalVoicesTests(unittest.TestCase):
    def setUp(self):
        self.base = {"hidden": 2, "channels": 2, "audioVocab": 8, "sample": "A fixed original prompt", "voices": [
            {"anchor": [1.0, 0.0], "referenceCodes": [[1, 2]]},
            {"anchor": [0.0, 1.0], "referenceCodes": []}]}
        self.raw = json.dumps(self.base).encode()
        self.extra = {"voices": [
            {"anchor": [-1.0, 0.0], "referenceCodes": []},
            {"anchor": [0.0, -1.0], "referenceCodes": []}]}

    def test_original_voices_and_old_cached_speech_are_preserved(self):
        merged = merge_calibration(self.raw, self.extra)
        self.assertEqual(len(merged["voices"]), 4)
        for index in range(2):
            original = dict(merged["voices"][index])
            self.assertEqual(original.pop("identity"), hashlib.sha256(self.raw).hexdigest())
            self.assertEqual(original, self.base["voices"][index])
        self.assertEqual(merged["sample"], self.base["sample"])
        self.assertNotEqual(merged["voices"][2]["identity"], merged["voices"][3]["identity"])
        changed = copy.deepcopy(self.extra)
        changed["voices"][0]["anchor"][0] = -2.0
        again = merge_calibration(self.raw, changed)
        self.assertEqual(again["voices"][3]["identity"], merged["voices"][3]["identity"])
        self.assertNotEqual(again["voices"][2]["identity"], merged["voices"][2]["identity"])

    def test_invalid_shapes_nonfinite_and_reference_codes_are_rejected(self):
        for values in [[1.0], [0.0, 0.0], [float("nan"), 1.0], [float("inf"), 1.0]]:
            bad = copy.deepcopy(self.extra); bad["voices"][0]["anchor"] = values
            with self.assertRaises(ValueError): merge_calibration(self.raw, bad)
        for codes in [None, [[1]], [[1, 8]], [[-1, 2]], [[True, 2]], [[1.5, 2]], [[1, 2]] * 101]:
            bad = copy.deepcopy(self.extra); bad["voices"][0]["referenceCodes"] = codes
            with self.assertRaises(ValueError): merge_calibration(self.raw, bad)
        with self.assertRaises(ValueError): merge_calibration(self.raw, {"voices": []})


    def test_reference_frames_are_preserved_and_change_only_their_voice_cache(self):
        original = merge_calibration(self.raw, self.extra)
        changed = copy.deepcopy(self.extra)
        changed["voices"][0]["referenceCodes"] = [[1, 2], [3, 4]]
        revised = merge_calibration(self.raw, changed)
        self.assertEqual(revised["voices"][2]["referenceCodes"], [[1, 2], [3, 4]])
        self.assertNotEqual(original["voices"][2]["identity"], revised["voices"][2]["identity"])
        for index in [0, 1, 3]:
            self.assertEqual(original["voices"][index]["identity"], revised["voices"][index]["identity"])
