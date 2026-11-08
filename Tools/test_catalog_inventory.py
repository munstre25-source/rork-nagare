import tempfile
import unittest
from pathlib import Path

from catalog_inventory import archive_summary, resolve_rows, scan_channel, write_json


CHANNEL = "UC" + "a" * 22
OTHER_CHANNEL = "UC" + "b" * 22


class CatalogInventoryTests(unittest.TestCase):
    def test_only_observed_handles_or_exact_titles_resolve(self):
        channels = [
            dict(channel_id=CHANNEL, title="Studio One", handle="@Studio"),
            dict(channel_id=OTHER_CHANNEL, title="Studio One", handle="@Other"),
        ]
        labels = [
            dict(id="plain", label="Studio"),
            dict(id="handle", label="@Studio"),
            dict(id="same-title", label="Studio One"),
            dict(id="partial", label="Studio One", partial=True),
            dict(id="verified", label="Studio One", channelId=OTHER_CHANNEL),
        ]
        plain, handle, same_title, partial, verified = resolve_rows(
            labels, channels, False
        )
        self.assertEqual(plain["status"], "unresolved_name")
        self.assertEqual(handle["channel_id"], CHANNEL)
        self.assertEqual(same_title["candidate_ids"], [CHANNEL, OTHER_CHANNEL])
        self.assertEqual(partial["status"], "needs_source_label_check")
        self.assertEqual(verified["channel_id"], OTHER_CHANNEL)

    def test_resume_uses_checkpoint_and_rejects_wrong_owner(self):
        channel = dict(channel_id=CHANNEL, title="Studio One", public_upload_count=2)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_json(
                root / "pages" / CHANNEL / "00000.json",
                dict(
                    channel_id=CHANNEL,
                    request_page_token=None,
                    next_page_token="second",
                    listed_video_ids=["a"],
                    missing_video_ids=[],
                    videos=[
                        dict(
                            video_id="a",
                            channel_id=CHANNEL,
                            metadata_candidate=True,
                            duration_sec=320,
                        )
                    ],
                ),
            )
            calls = []

            def call(body):
                calls.append(body)
                if body["action"] == "uploads":
                    return dict(
                        videos=[dict(video_id="b")],
                        nextPageToken=None,
                        playlist_total=2,
                    )
                return dict(
                    videos=[
                        dict(
                            video_id="b",
                            channel_id=OTHER_CHANNEL,
                            metadata_candidate=True,
                        )
                    ],
                    missing=[],
                )

            state = scan_channel(channel, root, call)
            self.assertTrue(state["complete"])
            self.assertEqual(calls[0]["pageToken"], "second")
            self.assertEqual(len(calls), 2)
            summary = archive_summary(root, [channel])
            self.assertEqual(summary["unique_listed_videos"], 2)
            self.assertEqual(summary["metadata_candidates"], 1)
            self.assertEqual(summary["candidates_at_most_180_seconds"], 0)


if __name__ == "__main__":
    unittest.main()
