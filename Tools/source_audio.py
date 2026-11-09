"""Read only a public source window over HTTP Range; no full long-video download."""
import io
import math
import urllib.request


class RangeReader(io.RawIOBase):
    def __init__(self, url, size, headers=None):
        self.url, self.size, self.headers = url, int(size), dict(headers or {})
        self.position, self.blocks, self.block_size = 0, {}, 256 * 1024
        self.bytes_fetched = 0

    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.position

    def seek(self, offset, whence=0):
        target = offset + (0 if whence == 0 else self.position if whence == 1 else self.size)
        if target < 0: raise ValueError("Negative audio seek")
        self.position = min(target, self.size)
        return self.position

    def read(self, size=-1):
        if size is None or size < 0: size = self.size - self.position
        remaining, chunks = min(size, self.size - self.position), []
        while remaining > 0:
            block = self.position // self.block_size
            if block not in self.blocks:
                start = block * self.block_size
                end = min(self.size, start + self.block_size) - 1
                req = urllib.request.Request(self.url, headers={**self.headers, "Range": f"bytes={start}-{end}"})
                with urllib.request.urlopen(req, timeout=45) as response:
                    if response.status != 206:
                        raise ValueError("Source does not support bounded audio reads")
                    data = response.read(end - start + 1)
                if len(data) != end - start + 1:
                    raise ValueError("Incomplete source audio range")
                self.blocks[block] = data
                self.bytes_fetched += len(data)
                # Bound per-source memory even when seeking a window near the end.
                if len(self.blocks) > 12:
                    self.blocks.pop(next(iter(self.blocks)))
            data = self.blocks[block]
            offset = self.position % self.block_size
            amount = min(remaining, len(data) - offset)
            if amount <= 0: raise ValueError("Empty source audio range")
            chunks.append(data[offset:offset+amount])
            self.position += amount
            remaining -= amount
        return b"".join(chunks)



def select_audio_format(info):
    formats = [f for f in info["formats"] if f.get("acodec") not in (None, "none") and
               f.get("vcodec") == "none" and f.get("protocol") == "https" and f.get("filesize")]
    def language(fmt):
        return str(fmt.get("language") or "").lower().replace("_", "-").split("-", 1)[0]

    japanese = [f for f in formats if language(f) in ("ja", "jpn")]
    unlabelled = [f for f in formats if language(f) in ("", "und")]
    original = [f for f in unlabelled if "original" in str(f.get("format_note") or "").lower()]
    preferred = japanese or original or unlabelled
    chosen = next((f for f in preferred if f.get("format_id") == "140"), None)
    if chosen is None:
        chosen = max(preferred, key=lambda f: f.get("abr") or 0) if preferred else None
    if chosen is None: raise ValueError("No accessible Japanese or unlabelled seekable source audio")
    return chosen

def extract_source_window(info, start, duration):
    import av
    import numpy as np
    chosen = select_audio_format(info)
    if not math.isfinite(start) or not math.isfinite(duration) or start < 0 or not 0 < duration <= 300:
        raise ValueError("Invalid source window")
    reader = RangeReader(chosen["url"], chosen["filesize"], chosen.get("http_headers"))
    length, origin = round(duration * 16000), round(start * 16000)
    audio, covered = np.zeros(length, dtype=np.float32), np.zeros(length, dtype=bool)
    with av.open(reader) as container:
        stream = container.streams.audio[0]
        container.seek(round(start * av.time_base), backward=True)
        resampler = av.AudioResampler(format="flt", layout="mono", rate=16000)
        for raw in container.decode(stream):
            for frame in resampler.resample(raw):
                if frame.pts is None: raise ValueError("Source frame has no audio timestamp")
                position = round(float(frame.pts * frame.time_base) * 16000) - origin
                data = frame.to_ndarray().reshape(-1)
                lo, hi = max(0, position), min(length, position + len(data))
                if hi > lo:
                    audio[lo:hi] = data[lo-position:hi-position]
                    covered[lo:hi] = True
            if raw.time is not None and raw.time > start + duration + .1: break
    if not covered.all():
        # Container durations can include a few trailing encoder-padding samples.
        # Trim only a short missing tail; never fill missing speech in the window.
        valid = np.flatnonzero(covered)
        first = int(valid[0]) if len(valid) else length
        last = int(valid[-1]) + 1 if len(valid) else 0
        middle_missing = int((~covered[first:last]).sum()) if last else length
        # Preserve source time zero. Short codec priming / rounded container tails
        # contain no audio frames; they are silence, not invented speech.
        if not (last and first <= 1920 and length-last <= 16800 and middle_missing == 0):
            raise ValueError(f"Source audio gap: head={first/16000:.3f}s tail={(length-last)/16000:.3f}s internal={middle_missing} samples")
    if not np.isfinite(audio).all() or float(np.max(np.abs(audio))) < .001:
        raise ValueError("Source window has no usable audio")
    return audio, reader.bytes_fetched
