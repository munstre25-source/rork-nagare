import unittest
from local_word_alignment import map_alignment, spoken_text, token_units, refine_items, invalid_items

class LocalAlignmentTests(unittest.TestCase):
    def setUp(self):
        self.line = {"start": 0, "end": 3, "translation": "Hello!",
            "tokens": [{"surface": "hello", "reading": "hello", "definitions": ["greeting"], "start": 0, "end": 3},
                       {"surface": "!", "start": 0, "end": 3},
                       {"surface": "world", "start": 0, "end": 3}]}
        self.items = [{"text": "hello", "start_time": .2, "end_time": .7},
                      {"text": "world", "start_time": 1.3, "end_time": 1.8}]

    def test_real_silence_and_metadata_preserved(self):
        out = map_alignment(self.line, self.items, .5, 3)
        self.assertEqual(out["tokens"][0]["start"], .7)
        self.assertEqual(out["tokens"][1]["start"], 1.2)
        self.assertEqual(out["tokens"][1]["end"], 1.2)
        self.assertEqual(out["tokens"][2]["start"], 1.8)
        self.assertEqual(out["tokens"][0]["definitions"], ["greeting"])
        self.assertEqual(self.line["tokens"][0]["start"], 0)
        self.assertEqual(out["timing"], "word")

    def test_no_interpolated_missing_words(self):
        with self.assertRaisesRegex(ValueError, "every requested word"):
            map_alignment(self.line, self.items[:1], 0, 3)

    def test_transcript_mutation_rejected(self):
        self.items[0]["text"] = "other"
        with self.assertRaisesRegex(ValueError, "changed"):
            map_alignment(self.line, self.items, 0, 3)

    def test_collapsed_overlap_out_of_bounds_and_nan_rejected(self):
        for start, end in [(0, 0), (-.1, .5), (.5, 4), (float("nan"), .5)]:
            with self.subTest(start=start, end=end), self.assertRaises(ValueError):
                map_alignment(self.line, [{**self.items[0], "start_time": start, "end_time": end}, self.items[1]], 0, 3)
        self.items[1]["start_time"] = .5
        with self.assertRaisesRegex(ValueError, "overlapping"):
            map_alignment(self.line, self.items, 0, 3)

    def test_tiny_float_slop_is_clamped_not_invented(self):
        items = [{"text": "hello", "start_time": -0.01, "end_time": .7},
                 {"text": "world", "start_time": 1.3, "end_time": 3.02}]
        out = map_alignment(self.line, items, 0, 3)
        self.assertEqual(out["tokens"][0]["start"], 0)
        self.assertEqual(out["tokens"][2]["end"], 3)

    def test_collapsed_word_is_repredicted_from_an_audio_crop(self):
        import numpy as np
        items=[{"text":str(i),"start_time":i*.2,"end_time":i*.2+.1} for i in range(9)]
        items[4]["end_time"]=items[4]["start_time"]
        seen=[]
        def infer(audio,units,factor):
            seen.append((len(audio),units,factor))
            return [{"text":u,"start_time":.1+n*.2,"end_time":.18+n*.2} for n,u in enumerate(units)]
        result,evidence=refine_items(items,np.zeros(32000),infer)
        self.assertFalse(invalid_items(result,2))
        self.assertEqual(result[4]["start_time"],.8)
        self.assertEqual(result[4]["end_time"],.88)
        self.assertEqual(seen[0][1],["2","3","4","5","6"])
        self.assertTrue(evidence)
        self.assertEqual(items[4]["start_time"],items[4]["end_time"])

    def test_unrecoverable_words_remain_invalid(self):
        import numpy as np
        items=[{"text":"missing","start_time":0.,"end_time":0.}]
        result,_=refine_items(items,np.zeros(16000),lambda *args:items)
        self.assertEqual(invalid_items(result,1),{0})

    def test_normalization_matches_exact_spoken_characters(self):
        self.assertEqual(spoken_text("\u30d3\u30fc\u30eb\u3001\uff15\u676f!"), "\u30d3\u30fc\u30eb5\u676f")
        line = {"tokens": [{"surface": "\u30fc"}, {"surface": "\u4e00\u676f"}]}
        self.assertEqual(token_units(line), [(1, "\u4e00\u676f")])

if __name__ == "__main__":
    unittest.main()
