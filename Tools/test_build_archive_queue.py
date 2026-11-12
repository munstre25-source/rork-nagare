import gzip
import json
import tempfile
import unittest
from pathlib import Path

from build_archive_queue import balanced_queue, candidates_from_archives


class ArchiveQueueTests(unittest.TestCase):
    def test_archive_requires_known_category_and_declared_japanese(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "candidates.jsonl.gz"
            rows = [
                dict(video_id="abcdefghijk", channel_id="known", channel_name="One",
                     title="Short", duration_sec=30, declared_audio_language="ja-JP",
                     metadata_candidate=True),
                dict(video_id="bcdefghijkl", channel_id="unknown", channel_name="Two",
                     title="Short", duration_sec=30, declared_audio_language="ja",
                     metadata_candidate=True),
                dict(video_id="cdefghijklm", channel_id="known", channel_name="One",
                     title="Dub", duration_sec=30, declared_audio_language="pt",
                     metadata_candidate=True),
            ]
            with gzip.open(path, "wt", encoding="utf-8") as stream:
                for row in rows:
                    stream.write(json.dumps(row) + "\n")
            candidates, uncategorized = candidates_from_archives(
                [path], {"known": "learning"}
            )
            self.assertEqual([v["video_id"] for v in candidates], ["abcdefghijk"])
            self.assertEqual(uncategorized["unknown"], 1)

    def test_balanced_queue_does_not_let_large_category_fill_every_slot(self):
        candidates = [
            dict(video_id=f"variety{i:04d}", category="variety", channel_id="v",
                 caption_available=False, duration_sec=30)
            for i in range(10)
        ] + [
            dict(video_id=f"anime{i:06d}", category="anime", channel_id="a",
                 caption_available=False, duration_sec=30)
            for i in range(3)
        ]
        selected = balanced_queue(candidates, limit=6, per_channel=10)
        self.assertEqual([v["category"] for v in selected[:6]],
                         ["anime", "variety"] * 3)


if __name__ == "__main__":
    unittest.main()
