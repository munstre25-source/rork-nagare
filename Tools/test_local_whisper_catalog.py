import unittest
from types import SimpleNamespace
from unittest.mock import patch
import numpy as np
from local_whisper_catalog import LocalWhisperAligner, verify_whisper_weights

class RawAttentionTests(unittest.TestCase):
    def setUp(self):
        self.aligner=object.__new__(LocalWhisperAligner)
        self.aligner.tokenizer=SimpleNamespace(encode=lambda word:[len(word),7],sot_sequence=[1,2],eot=99)
        self.seen={}
        def alignment(proxy,targets,encoded,frames):
            self.seen.update(targets=targets,groups=proxy.split_to_word_tokens(targets[0]),frames=frames)
            return [[{"word":"毎回","start":.1,"end":.3,"probability":.91},{"word":"楽しい","start":.5,"end":.7,"probability":.82}]]
        self.aligner.model=SimpleNamespace(feature_extractor=lambda audio:audio,encode=lambda features:features,find_alignment=alignment)

    def test_exact_dictionary_words_raw_times_and_vad_offset(self):
        with patch('faster_whisper.vad.get_speech_timestamps',return_value=[{"start":1600,"end":14400}]),patch('faster_whisper.audio.pad_or_trim',side_effect=lambda x:x):
            words=self.aligner._infer(np.zeros(16000,dtype=np.float32),["毎回","楽しい"],1)
        self.assertEqual(self.seen["targets"],[[2,7,3,7]])
        self.assertEqual(self.seen["groups"],(["毎回","楽しい","<|endoftext|>"],[[2,7],[3,7],[99]]))
        self.assertEqual([(w["start_time"],w["end_time"]) for w in words],[(.2,.4),(.6,.8)])
        self.assertEqual(words[0]["probability"],.91)

    def test_silence_cannot_generate_word_timings(self):
        with patch('faster_whisper.vad.get_speech_timestamps',return_value=[]),self.assertRaisesRegex(ValueError,"No speech"):
            self.aligner._infer(np.zeros(16000,dtype=np.float32),["毎回"],1)

class WeightIdentityTests(unittest.TestCase):
    def test_changed_weight_file_cannot_claim_pinned_provenance(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder)/"model.bin").write_bytes(b"different model")
            with self.assertRaisesRegex(ValueError,"checksum mismatch"):verify_whisper_weights(folder)
