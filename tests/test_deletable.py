import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/deletable.py"


def chunk(*events):
    return "".join(json.dumps(e) + "\n" for e in events).encode()


def take(samples, counted=None):
    data = b"\0\0" * samples
    return b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt " + bytes(20) + b"data" + struct.pack("<I", len(data) if counted is None else counted) + data


class Deletable(unittest.TestCase):
    def deletable(self, device, store):
        with tempfile.TemporaryDirectory() as folder:
            for name, data in store.items():
                (Path(folder) / name).write_bytes(data)
            listing = "".join(f"{len(data)} /sessions/{name}\n" for name, data in device.items())
            out = subprocess.run([sys.executable, str(SCRIPT), folder], input=listing, capture_output=True, text=True,
                                 check=True).stdout
        return sorted(p.removeprefix("/sessions/") for p in out.split())

    def test_closed_and_copied_whole(self):
        start, frame, end = {"event": "start"}, {"event": "frame"}, {"event": "end"}
        ended = {"9-1-1-0000.jsonl": chunk(start, frame), "9-1-1-0001.jsonl": chunk(start, frame, end), "9-1-1.wav": take(8)}
        running = {"1-2-2-0000.jsonl": chunk(start, frame), "1-2-2-0001.jsonl": chunk(start, frame), "1-2-2.wav": take(8)}
        device = ended | running
        self.assertEqual(self.deletable(device, device), ["1-2-2-0000.jsonl", "9-1-1-0000.jsonl", "9-1-1-0001.jsonl", "9-1-1.wav"],
                         "an ended session goes whole; a running one, though it sorts first by its start time, keeps "
                         "the chunk it writes and its take")

    def test_not_copied_whole(self):
        start, end = {"event": "start"}, {"event": "end"}
        device = {"5-1-1-0000.jsonl": chunk(start), "5-1-1-0001.jsonl": chunk(start, {"event": "frame"}, end), "5-1-1.wav": take(8)}
        store = {"5-1-1-0000.jsonl": chunk(start)[:-1], "5-1-1-0001.jsonl": device["5-1-1-0001.jsonl"], "5-1-1.wav": take(8, counted=6)}
        self.assertEqual(self.deletable(device, store), ["5-1-1-0001.jsonl"],
                         "a chunk copied short and a take copied before its header counted all of it stay")
        self.assertEqual(self.deletable({"5-1-1-0001.jsonl": device["5-1-1-0001.jsonl"]}, {}), [], "an uncopied chunk stays")

    def test_end_already_taken_off(self):
        start, end = {"event": "start"}, {"event": "end"}
        store = {"7-1-1-0000.jsonl": chunk(start), "7-1-1-0001.jsonl": chunk(start, end), "7-1-1.wav": take(4)}
        device = {"7-1-1-0000.jsonl": store["7-1-1-0000.jsonl"], "7-1-1.wav": store["7-1-1.wav"]}
        self.assertEqual(self.deletable(device, store), ["7-1-1-0000.jsonl", "7-1-1.wav"],
                         "the end record copied on an earlier run closes what is left on the headset")

    def test_other_names(self):
        end = chunk({"event": "start"}, {"event": "end"})
        files = {"notes.jsonl": end, "3-1-1-0000.jsonl": end}
        self.assertEqual(self.deletable(files, files), ["3-1-1-0000.jsonl"], "a name PlayLog never writes stays and stops nothing")

    def test_nothing_listed(self):
        self.assertEqual(self.deletable({}, {}), [])


if __name__ == "__main__":
    unittest.main()
