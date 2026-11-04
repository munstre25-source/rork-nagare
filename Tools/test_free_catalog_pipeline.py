import unittest
from free_catalog_pipeline import natural_windows, display_groups

class FreeCatalogTests(unittest.TestCase):
    def test_long_audio_recognition_chunks_retain_every_sample(self):
        import numpy as np
        audio = np.ones(75*16000,dtype=np.float32)*.1
        audio[18*16000:19*16000]=0
        windows=natural_windows(audio)
        self.assertEqual(windows[0][0],0)
        self.assertEqual(windows[-1][1],len(audio))
        self.assertTrue(all(a[1]==b[0] for a,b in zip(windows,windows[1:])))
        self.assertTrue(18 <= windows[0][1]/16000 <= 19)

    def test_display_groups_preserve_words_and_do_not_create_silent_cards(self):
        words=[{"surface":"longword", "start":0.,"end":1.},
               {"surface":"!", "start":1.,"end":1.},
               {"surface":"next", "start":2.,"end":3.}]
        groups=display_groups(words,max_chars=8)
        self.assertEqual([t for group in groups for t in group],words)
        self.assertEqual(len(groups),2)
        self.assertEqual(groups[0][-1]["surface"],"!")

if __name__ == "__main__": unittest.main()
