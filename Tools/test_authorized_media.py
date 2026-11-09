import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from authorized_media import AuthorizedMedia

VIDEO = "abcdefghijk"


class AuthorizedMediaTests(unittest.TestCase):
    def test_real_local_audio_window_is_bound_to_file_checksum_and_origin(self):
        import numpy as np
        import soundfile as sf

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audio = np.concatenate((np.full(16000, 0.1), np.full(16000, 0.3))).astype(
                "float32"
            )
            sf.write(root / "source.wav", audio, 16000, subtype="FLOAT")
            item = dict(
                file="source.wav",
                permission="Original provided by creator",
                sourceStartSec=10,
                durationSec=2,
                sha256=hashlib.sha256((root / "source.wav").read_bytes()).hexdigest(),
            )
            manifest = root / "authorized-media.json"
            manifest.write_text(json.dumps({VIDEO: item}))
            reader = AuthorizedMedia(manifest)
            excerpt = reader.window(VIDEO, 11, 1)
            self.assertEqual(len(excerpt), 16000)
            self.assertAlmostEqual(float(excerpt.mean()), 0.3, places=5)
            with self.assertRaisesRegex(ValueError, "complete source window"):
                reader.window(VIDEO, 9.5, 1)
            item["sha256"] = "0" * 64
            manifest.write_text(json.dumps({VIDEO: item}))
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                AuthorizedMedia(manifest).window(VIDEO, 11, 1)
