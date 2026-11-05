import unittest
from types import SimpleNamespace
from unittest.mock import patch
import numpy as np
from local_whisper_catalog import LocalWhisperAligner, LocalWhisperProcessor, align_phrase_context, restore_phrase_groups, verify_whisper_weights

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

class PhraseRecoveryTests(unittest.TestCase):
    def test_joint_context_preserves_every_word_and_original_draft(self):
        import copy
        clip={"lines":[{"start":0,"end":1,"tokens":[{"surface":"透明"}]},{"start":1,"end":2,"tokens":[{"surface":"モード"}]},{"start":2,"end":3,"tokens":[{"surface":"透明"}]}]}
        original=copy.deepcopy(clip);calls=[]
        def align(draft,audio):
            calls.append(copy.deepcopy(draft))
            if len(calls)==1:raise ValueError('line[1]: No speech in alignment phrase')
            return {"lines":draft["lines"]}
        result,merges=align_phrase_context(SimpleNamespace(align=align),clip,np.zeros(48000))
        self.assertEqual(clip,original)
        self.assertEqual([t["surface"] for t in result["lines"][0]["tokens"]],["透明","モード","透明"])
        self.assertEqual(len(merges),1)

    def test_joint_context_never_grows_beyond_the_bounded_search(self):
        clip={"lines":[{"start":0,"end":8,"tokens":[]},{"start":8,"end":20,"tokens":[]}]}
        def align(*args):raise ValueError('line[1]: original failure')
        with self.assertRaisesRegex(ValueError,'original failure'):align_phrase_context(SimpleNamespace(align=align),clip,np.zeros(320000))

    def test_excerpt_keeps_a_contiguous_region_without_stitching_gaps(self):
        processor=object.__new__(LocalWhisperProcessor)
        processor.dictionary={};processor.dictionary_module=SimpleNamespace(tokenize=lambda text,_:[{"surface":text}])
        def align(clip,audio):
            line=clip["lines"][0]
            if line["tokens"][0]["surface"]=="欠落":raise ValueError('missing word')
            return {"lines":[line]}
        processor.aligner=SimpleNamespace(align=align);seen={}
        def process(video,info,audio,offset,heard):
            seen.update(offset=offset,duration=len(audio)/16000,texts=[s['text'] for s in heard['segments']])
            return {"processing":{}},[]
        processor.process=process
        segments=[{"start":a,"end":b,"text":text,"avgLogProbability":-.1} for a,b,text in [(0,2,'一'),(2,4,'二'),(4,5,'欠落'),(5,7,'三'),(7,9,'四'),(9,11,'五')]]
        processor.salvage_excerpt({"video_id":"abcdefghijk"},{},np.zeros(176000),30,{"language":"ja","segments":segments})
        self.assertEqual(seen['texts'],['三','四','五'])
        self.assertAlmostEqual(seen['offset'],34.8)
        self.assertAlmostEqual(seen['duration'],6.2)

class NaturalCardBoundaryTests(unittest.TestCase):
    def test_joint_search_keeps_natural_phrases_without_reusing_rough_times(self):
        original=[{"start":0,"end":1,"tokens":[{"surface":"透明"}]},
                  {"start":1,"end":2,"tokens":[{"surface":"モード"}]}]
        tokens=[{"surface":"透明","start":.3,"end":1.7},
                {"surface":"モード","start":1.9,"end":2.8}]
        result=restore_phrase_groups(original,[{"tokens":tokens}])
        self.assertEqual([(l["start"],l["end"]) for l in result],[(.3,1.7),(1.9,2.8)])
        self.assertEqual([t for l in result for t in l["tokens"]],tokens)

    def test_changed_words_cannot_be_hidden_by_card_regrouping(self):
        with self.assertRaisesRegex(ValueError,"identity/order"):
            restore_phrase_groups([{"tokens":[{"surface":"透明"}]}],
                                  [{"tokens":[{"surface":"全然違う","start":0,"end":1}]}])
