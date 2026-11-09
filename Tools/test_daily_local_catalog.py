import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from daily_local_catalog import publish_batch, run


class DailyLocalCatalogTests(unittest.TestCase):
    def test_empty_inbox_uses_no_remote_api_or_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root / "report.json"
            report.write_text(
                json.dumps(dict(newSources=dict(candidates=[]), pending=[]))
            )
            args = SimpleNamespace(state=root, report=report, publish_reviewed=True)
            with patch("daily_local_catalog.configuration") as config:
                result = run(args)
            config.assert_not_called()
            self.assertEqual(result["status"], "waiting_for_authorized_media_or_review")
            self.assertEqual(result["paidInferenceCalls"], 0)

    def test_changed_draft_audio_cannot_be_published_using_an_old_review(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root / "report.json"
            report.write_text(
                json.dumps(
                    dict(
                        newSources=dict(
                            candidates=[
                                dict(
                                    video_id="abcdefghijk",
                                    channel_id="expected",
                                    category="learning",
                                )
                            ]
                        ),
                        pending=[],
                    )
                )
            )
            (root / "reviews.json").write_text(
                json.dumps(
                    [
                        dict(
                            id="draft",
                            videoId="abcdefghijk",
                            notes="Reviewed audio",
                            audioSha256="old",
                        )
                    ]
                )
            )
            (root / "drafts").mkdir()
            (root / "drafts/draft.json").write_text(
                json.dumps(dict(alignment=dict(audioSha256="new")))
            )
            args = SimpleNamespace(state=root, report=report, publish_reviewed=True)
            with patch(
                "daily_local_catalog.configuration",
                return_value=("https://example.test", "anon"),
            ), patch("daily_local_catalog.public_catalog", return_value=[]), patch(
                "daily_local_catalog.maintenance_headers"
            ) as credentials:
                with self.assertRaisesRegex(ValueError, "reviewed audio"):
                    run(args)
            credentials.assert_not_called()

    def test_source_metadata_mismatch_blocks_registration_and_publication(self):
        clips = [dict(video_id="abcdefghijk")]
        candidates = {"abcdefghijk": dict(channel_id="expected")}
        with patch(
            "daily_local_catalog.request_json",
            return_value=dict(
                videos=[
                    dict(
                        video_id="abcdefghijk",
                        metadata_candidate=True,
                        channel_id="different",
                    )
                ]
            ),
        ) as request:
            result = publish_batch("https://example.test", {}, clips, candidates)
        self.assertEqual(result["accepted"], 0)
        self.assertEqual(request.call_count, 1)

    def test_verified_source_is_registered_before_reviewed_publication(self):
        clips = [dict(video_id="abcdefghijk")]
        candidates = {
            "abcdefghijk": dict(
                channel_id="expected", channel_name="Creator", category="learning"
            )
        }
        replies = [
            dict(
                videos=[
                    dict(
                        video_id="abcdefghijk",
                        metadata_candidate=True,
                        channel_id="expected",
                    )
                ]
            ),
            dict(sources=[dict(channel_id="expected", status="resolved")]),
            dict(accepted=1),
        ]
        with patch("daily_local_catalog.request_json", side_effect=replies) as request:
            result = publish_batch("https://example.test", {}, clips, candidates)
        self.assertEqual(result["accepted"], 1)
        self.assertEqual(request.call_args_list[1].args[2]["action"], "register")
        self.assertEqual(request.call_args_list[2].args[2], {"clips": clips})
