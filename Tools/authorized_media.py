"""Read exact, creator-authorized source windows from local media files."""

import hashlib
import json
import math
import re
from pathlib import Path


class AuthorizedMedia:
    def __init__(self, manifest):
        self.root = Path(manifest).resolve().parent
        self.entries = json.loads(Path(manifest).read_text())
        if not isinstance(self.entries, dict):
            raise ValueError(
                "The authorized media manifest must map video IDs to files"
            )

    def __contains__(self, video_id):
        return video_id in self.entries

    def entry(self, video_id):
        item = self.entries.get(video_id)
        if not re.fullmatch(r"[A-Za-z0-9_-]{11}", video_id) or not isinstance(
            item, dict
        ):
            raise ValueError("No authorized media for this source")
        start, duration = float(item["sourceStartSec"]), float(item["durationSec"])
        if (
            not math.isfinite(start)
            or not math.isfinite(duration)
            or start < 0
            or duration <= 0
        ):
            raise ValueError("Invalid authorized media bounds")
        if (
            not isinstance(item.get("permission"), str)
            or not item["permission"].strip()
        ):
            raise ValueError("Record the source owner’s permission or license")
        return item, start, duration

    def file_path(self, video_id):
        item, _, _ = self.entry(video_id)
        path = (self.root / item["file"]).resolve()
        if not path.is_relative_to(self.root):
            raise ValueError(
                "Authorized media file must be inside the manifest directory"
            )
        if not path.is_file():
            raise FileNotFoundError("Authorized media file has not arrived")
        return path

    def window(self, video_id, start, duration):
        from local_word_alignment import extract_audio

        item, origin, length = self.entry(video_id)
        if (
            not math.isfinite(start)
            or not 0 < duration <= 300
            or start < origin - 0.001
            or start + duration > origin + length + 0.001
        ):
            raise ValueError(
                "Authorized media does not cover the complete source window"
            )
        path = self.file_path(video_id)
        before = path.stat()
        with path.open("rb") as stream:
            fingerprint = hashlib.file_digest(stream, "sha256").hexdigest()
        if fingerprint != item.get("sha256"):
            raise ValueError("Authorized media checksum mismatch")
        audio = extract_audio(path, max(0, start - origin), duration)
        after = path.stat()
        if (before.st_size, before.st_mtime_ns, before.st_ino) != (
            after.st_size,
            after.st_mtime_ns,
            after.st_ino,
        ):
            raise ValueError("Authorized media changed during extraction")
        if abs(len(audio) / 16000 - duration) > 0.025:
            raise ValueError("Authorized media audio ended before the requested window")
        return audio

    def draft_input(self, video):
        video_id = video["video_id"]
        item, start, length = self.entry(video_id)
        if item.get("channelId") != video["channel_id"]:
            raise ValueError(
                "Authorized media does not match the verified source channel"
            )
        width, height = int(item["width"]), int(item["height"])
        if width <= 0 or height <= 0:
            raise ValueError("Verified original video dimensions are required")
        source_duration = float(video["duration_sec"])
        if start + length > source_duration + 0.1:
            raise ValueError("Authorized media exceeds the verified source duration")
        duration = min(
            length, source_duration - start, 120 if source_duration > 180 else 180
        )
        if duration < 3:
            raise ValueError("Authorized source window is shorter than three seconds")
        info = dict(
            id=video_id,
            channel_id=video["channel_id"],
            duration=source_duration,
            width=width,
            height=height,
        )
        return self.window(video_id, start, duration), start, info
