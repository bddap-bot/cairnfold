#!/usr/bin/env python3
"""Which of a headset's session files the host may delete from it, given its copies under STORE.

    deletable.py STORE < LISTING

LISTING is one `SIZE PATH` line per file in the headset's sessions folder, as `stat -c '%s %n'` prints them: PlayLog's
chunks `<session>-<part>.jsonl` and takes `<session>.wav`. Prints the PATH of each whose copy STORE/<name> is whole
(its size, and for a take a header that counts all of it) and that its session has closed: a chunk once a later part
of its session exists or the session's end record is copied, a take once that end record is. A session killed before
its end record keeps its last chunk and take on the headset."""
import json
import re
from pathlib import Path
import sys


def ended(chunk):
    with open(chunk, "rb") as f:
        f.seek(max(0, f.seek(0, 2) - 4096))
        lines = f.read().splitlines()
    try:
        return bool(lines) and json.loads(lines[-1]).get("event") == "end"
    except ValueError:
        return False


def whole_take(take):
    with open(take, "rb") as f:
        header = f.read(44)
    return len(header) == 44 and int.from_bytes(header[40:44], "little") == take.stat().st_size - 44


def split(name):
    """A chunk's session and part, a take's session and None, or None for a name PlayLog writes neither as."""
    if name.endswith(".wav"):
        return name[:-len(".wav")], None
    match = re.fullmatch(r"(.+)-(\d+)\.jsonl", name)
    return (match[1], int(match[2])) if match else None


def deletable(store, listing):
    store = Path(store)
    files = [(int(size), path, *split(Path(path).name))
             for size, path in (line.split(" ", 1) for line in listing.splitlines() if line.strip()) if split(Path(path).name)]
    copied = {s: list(store.glob(f"{s}-*.jsonl")) for _, _, s, _ in files}
    last = {s: max([part for _, _, t, part in files if t == s and part is not None] + [split(c.name)[1] for c in chunks if split(c.name)],
                   default=-1) for s, chunks in copied.items()}
    closed = {s for s, chunks in copied.items() if any(ended(c) for c in chunks)}
    out = []
    for size, path, session, part in files:
        copy = store / Path(path).name
        if not copy.is_file() or copy.stat().st_size != size:
            continue
        if part is None and session in closed and whole_take(copy) or part is not None and (session in closed or part < last[session]):
            out.append(path)
    return out


if __name__ == "__main__":
    sys.stdout.writelines(p + "\n" for p in deletable(sys.argv[1], sys.stdin.read()))
