import copy
import hashlib
import unittest
import numpy as np
from curate_local_excerpt import prepare_excerpt
from local_whisper_catalog import ASR_MODEL, ASR_REVISION

class ExcerptIdentityTests(unittest.TestCase):
    def setUp(self):
        self.audio = np.arange(160000, dtype=np.float32) / 160000
        self.identity = dict(videoId="abcdefghijk", sourceStartSec=30)
        self.original = dict(audioSha256=hashlib.sha256(self.audio.tobytes()).hexdigest(),
            asrModel=ASR_MODEL, asrRevision=ASR_REVISION, language="ja",
            segments=[dict(avgLogProbability=-.2, noSpeechProbability=.01)])
        self.selection = dict(videoId="abcdefghijk", lo=2, hi=7,
            segments=[[2.1,4,"こんにちは"],[5,6.8,"ありがとう"]], notes="Checked source")

    def test_actual_pcm_and_source_offsets_survive_without_collapsing_internal_silence(self):
        before = copy.deepcopy(self.original)
        excerpt, start, heard, digest = prepare_excerpt(self.audio,16000,self.identity,self.original,self.selection)
        np.testing.assert_array_equal(excerpt,self.audio[32000:112000])
        self.assertEqual(start,32)
        self.assertAlmostEqual(heard["segments"][1]["start"],3)
        self.assertEqual(heard["segments"][0]["avgLogProbability"],-.2)
        self.assertEqual(digest,self.original["audioSha256"])
        self.assertEqual(self.original,before)

    def test_different_audio_cannot_reuse_the_recognition_proof(self):
        changed = self.audio.copy();changed[100] += .01
        with self.assertRaisesRegex(ValueError,"identity mismatch"):
            prepare_excerpt(changed,16000,self.identity,self.original,self.selection)

    def test_different_video_or_model_cannot_reuse_the_source(self):
        for changed in [dict(self.identity,videoId="zyxwvutsrqp")]:
            with self.assertRaisesRegex(ValueError,"identity mismatch"):
                prepare_excerpt(self.audio,16000,changed,self.original,self.selection)
        with self.assertRaisesRegex(ValueError,"provenance required"):
            prepare_excerpt(self.audio,16000,self.identity,dict(self.original,asrRevision="other"),self.selection)

    def test_transcript_cannot_silently_clip_a_phrase_or_go_backward(self):
        for segments in [[[1,4,"こんにちは"]],[[6,8,"ありがとう"]],[[5,6,"一"],[4,5,"二"]]]:
            with self.assertRaisesRegex(ValueError,"ordered inside"):
                prepare_excerpt(self.audio,16000,self.identity,self.original,dict(self.selection,segments=segments))
