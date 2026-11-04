import io
import unittest
from unittest.mock import patch
from source_audio import RangeReader, select_audio_format

class Response(io.BytesIO):
    status = 206

class RangeAudioTests(unittest.TestCase):
    def setUp(self):
        self.data = bytes(range(256)) * 3000
        self.calls = []

    def request(self, request, timeout):
        span = request.headers["Range"].removeprefix("bytes=")
        lo, hi = map(int, span.split("-"))
        self.calls.append((lo, hi))
        return Response(self.data[lo:hi+1])

    def test_seek_and_read_fetch_only_needed_blocks(self):
        reader = RangeReader("https://example.invalid/audio", len(self.data))
        with patch("urllib.request.urlopen", self.request):
            reader.seek(500000)
            self.assertEqual(reader.read(40000), self.data[500000:540000])
            reader.seek(500010)
            self.assertEqual(reader.read(10), self.data[500010:500020])
            self.assertEqual(len(self.calls), 2)
            reader.seek(-15, 2)
            self.assertEqual(reader.read(100), self.data[-15:])
            self.assertEqual(reader.read(1), b"")
        self.assertLessEqual(reader.bytes_fetched, len(self.data))

    def test_original_japanese_audio_wins_over_default_english_dub(self):
        info = {"formats": [
            {"format_id": "140", "acodec": "aac", "vcodec": "none", "protocol": "https", "filesize": 200, "language": "en", "abr": 128},
            {"format_id": "140-ja", "acodec": "aac", "vcodec": "none", "protocol": "https", "filesize": 200, "language": "ja", "abr": 128},
        ]}
        self.assertEqual(select_audio_format(info)["format_id"], "140-ja")

    def test_incomplete_range_rejected(self):
        reader = RangeReader("https://example.invalid/audio", 500000)
        with patch("urllib.request.urlopen", return_value=Response(b"short")):
            with self.assertRaisesRegex(ValueError, "Incomplete"):
                reader.read(1)

    def test_server_cannot_silently_return_full_video(self):
        reader = RangeReader("https://example.invalid/audio", 500000)
        response = Response(b"unexpected"); response.status = 200
        with patch("urllib.request.urlopen", return_value=response):
            with self.assertRaisesRegex(ValueError, "bounded"):
                reader.read(1)

if __name__ == "__main__": unittest.main()
