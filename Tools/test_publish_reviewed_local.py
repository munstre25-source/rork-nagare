import copy
import unittest
from publish_reviewed_local import reviewed_clip

class ReviewedPublicationTests(unittest.TestCase):
    def setUp(self):
        self.clip={"id":"local-example","video_id":"abcdefghijk","lines":[{"tokens":[
            {"surface":"手毬","start":.2,"end":.6,"definitions":["ball"]},
            {"surface":"寿司","start":.8,"end":1.1,"definitions":["sushi"]},
            {"surface":"食べた","start":1.2,"end":1.7,"baseForm":"食べる","baseReading":"たべる","baseRomaji":"taberu"}]}],"processing":{},"alignment":{}}
        self.review={"id":"local-example","videoId":"abcdefghijk","japanese":["手毬寿司食べた"],"english":["I ate round sushi balls."]}

    def test_changed_japanese_video_or_window_is_rejected(self):
        for key,value in [("japanese",["changed"]),("videoId","other"),("id","other-window")]:
            with self.subTest(key=key),self.assertRaises(ValueError):reviewed_clip(copy.deepcopy(self.clip),{**self.review,key:value})

    def test_every_line_needs_reviewed_english_before_mutation(self):
        for english in [[],[" "],[None]]:
            clip=copy.deepcopy(self.clip)
            with self.assertRaises(ValueError):reviewed_clip(clip,{**self.review,"english":english})
            self.assertEqual(clip,self.clip)

    def test_compound_keeps_existing_outer_audio_boundaries(self):
        review={**self.review,"dictionary":[{"surface":"手毬寿司","definitions":["round sushi balls"],"reading":"てまりずし"}]}
        out=reviewed_clip(copy.deepcopy(self.clip),review)
        token=out["lines"][0]["tokens"][0]
        self.assertEqual((token["start"],token["end"]),(.2,1.1))
        self.assertEqual(token["definitions"],["round sushi balls"])
        self.assertEqual(out["alignment"]["lines"],out["lines"])
        self.assertEqual(out["processing"]["operatorReview"],"english-checked")
        self.assertEqual(out["lines"][0]["translation"],self.review["english"][0])

    def test_context_definition_keeps_conjugation_base(self):
        out=reviewed_clip(copy.deepcopy(self.clip),{**self.review,"dictionary":[{"surface":"食べた","definitions":["ate"]}]})
        token=out["lines"][0]["tokens"][-1]
        self.assertEqual((token["baseForm"],token["baseReading"],token["baseRomaji"]),("食べる","たべる","taberu"))

    def test_cannot_split_word_to_invent_an_interval(self):
        with self.assertRaisesRegex(ValueError,"term missing"):
            reviewed_clip(copy.deepcopy(self.clip),{**self.review,"dictionary":[{"surface":"食べ","definitions":["eat"]}]})
