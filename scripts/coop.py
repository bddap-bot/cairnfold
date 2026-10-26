"""Drive the existing build gestures with N peers, then check every peer's view."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import socket
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
# A stuck run is one where no player takes a step while together they spend this much CPU; a busy machine only slows the
# run in wall time, so no wall-clock limit applies. The joiner's strokes across the whole garden re-lay everything on it
# on every peer, one step that has taken 65 CPU-seconds together on a loaded machine.
QUIET_CPU = 150
# Going home before these steps means a player lost the garden it was visiting.
# The host and the joiner end their builds and turns of the sky at this command; late joiners build after it.
SEQ = 35
# After the final digest the joiner pulls the ground this far up in one stroke and then twice as far down, each
# step digested on every peer: one stroke of a guest's spans the whole ground.
EXTREME = 500
# Where the joiner drowns a tree under a pond and undoes it, clear of the easel and the held tools' wall.
DROWN = (14, -14)
# The custom avatars the joiners wear in turn, from tests/avatars.
AVATARS = ["crimsom-1.0.vrm", "godette-0.x.vrm", "crimsom-0.x.vrm"]
HOME_CUE = re.compile(r'"home": true|"digests": \["home"\]')


def barrier(names):
    return {"op": "until", "digests": names}


def sample(name, names, count):
    phase = f"{count}-players"
    return [
        {"op": "until", "players": count, "worn": count - (1 if name == "host" else 2)},
        {"op": "wait", "seconds": 1},
        {"op": "digest", "name": f"{name}-{phase}-ready"},
        barrier([f"{n}-{phase}-ready" for n in names]),
        {"op": "network_sample", "name": f"{name}-{phase}-cost", "seconds": 4},
        barrier([f"{n}-{phase}-cost" for n in names]),
    ]


# The host and the joiner, at the host's easel together, each take a stick of charcoal and a palette of their own, as
# an easel holds one of each, and switch, set down, tear and pick tools while the other paints; after each step the hand must hold what it should, and once the
# host's grip sends its palette home both see every palette at rest on the tray. They lay six commands: a stroke each,
# the joiner's fresh sheet, the joiner's stroke on it, the host's, and the host's blue painted onto the oil palette,
# which every peer's digest must show.
EASEL_PHASES = {
    "host": [
        [{"op": "take", "what": "stick"}, {"op": "holds", "what": "stick"},
         {"op": "brush", "points": [[0.2, 0.3, 0.8], [0.5, 0.35, 0.8]], "seconds": 0.3},
         {"op": "take", "what": "palette"}, {"op": "holds", "what": "oil palette"}],
        [{"op": "set_down"}, {"op": "holds", "what": "stick"}, {"op": "rests"},
         {"op": "pick", "tool": "seeds"}, {"op": "holds", "what": "seeds"},
         {"op": "pick", "tool": "easel"}, {"op": "holds", "what": "stick"}],
        [{"op": "brush", "points": [[0.2, 0.7, 0.8], [0.5, 0.75, 0.8]], "seconds": 0.3}, {"op": "holds", "what": "stick"},
         {"op": "take", "what": "box", "hand": "left"}, {"op": "holds", "hand": "left", "what": "water palette"},
         {"op": "take", "what": "big"}, {"op": "holds", "what": "big"},
         {"op": "dip", "what": "oil", "index": 5}, {"op": "mix", "points": [[-0.2, 0.0, 0.7], [0.1, 0.05, 0.7]], "seconds": 0.3},
         {"op": "set_down", "hand": "left"}],
    ],
    "join": [
        [{"op": "take", "what": "thin_stick"}, {"op": "holds", "what": "thin_stick"},
         {"op": "brush", "points": [[0.6, 0.3, 0.8], [0.9, 0.35, 0.8]], "seconds": 0.3},
         {"op": "take", "what": "box"}, {"op": "holds", "what": "water palette"}],
        [{"op": "take", "what": "thin_stick"}, {"op": "holds", "what": "thin_stick"},
         {"op": "sheet", "pull": 0.5}, {"op": "holds", "what": "thin_stick"},
         {"op": "brush", "points": [[0.6, 0.5, 0.8], [0.9, 0.55, 0.8]], "seconds": 0.3}],
        [{"op": "rests"}, {"op": "pick", "tool": "seeds"}, {"op": "holds", "what": "seeds"},
         {"op": "pick", "tool": "easel"}, {"op": "holds", "what": "thin_stick"},
         {"op": "take", "what": "flat"}, {"op": "holds", "what": "flat"},
         {"op": "take", "what": "thin_stick"}, {"op": "holds", "what": "thin_stick"},
         {"op": "pick", "tool": "camera"}, {"op": "holds", "what": "camera"}],
    ],
}
EASEL_COMMANDS = 6


def easel_steps(name, names, seq):
    steps = []
    for i, phase in enumerate(EASEL_PHASES.get(name, [])):
        steps += phase + [{"op": "digest", "name": f"{name}-easel-{i}"}, barrier([f"{n}-easel-{i}" for n in EASEL_PHASES])]
    return steps + [{"op": "until", "seq": seq + EASEL_COMMANDS}, {"op": "wait", "seconds": 0.5},
                    {"op": "digest", "name": f"{name}-easel"}, barrier([f"{n}-easel" for n in names])]



def held_steps(name, names, capture=False):
    steps = []
    tools = ["walls", "flowers", "grass", "trees", "delete", "pond", "fence", "windows", "decorations", "stone", "colour", "camera", "house", "seeds", "path", "style", "stairs", "tower", "arch", "book", "selfie", "bushes", "boulder", "moss", "none"]
    phases = [[{"op": "pick", "tool": t}] for t in tools]
    phases += [[{"op": "take", "what": b}] for b in ("small", "big", "flat", "stick")]
    phases += [[{"op": "take", "what": "big"}, {"op": "dip", "what": "oil", "index": 5},
                {"op": "take", "what": kit, "hand": "left"},
                {"op": "view", "eye": [-4, 1.65, 6], "at": [-4, 1.4, 4]},
                {"op": "hands", "left": [-0.32, -0.35, -0.4], "right": [0.32, -0.3, -0.4], "tip": 20}]
               for kit in ("palette", "box")]
    phases[-1].insert(0, {"op": "set_down", "hand": "left"})
    phases += [[{"op": "set_down", "hand": "left"}, {"op": "pick", "tool": "none"}]]
    phases += [[{"op": "wall", "points": [[-2, 9], [0, 9]], "seconds": 1}, {"op": "wait", "seconds": 1},
                {"op": "shoulder_bird", "trust": True}]]
    for i, phase in enumerate(phases):
        key = f"held-{i}"
        if name == "join":
            steps += phase + [{"op": "held_snapshot", "name": key, "loaded": i in (len(tools) + 4, len(tools) + 5)}]
        steps += [barrier([key])]
        if name != "join":
            steps += [{"op": "remote_holds", "name": key}]
            if capture and name == "host" and i == len(tools) + 4:
                steps += [{"op": "view", "eye": [-3.0, 1.7, 4.8], "at": [-4, 1.25, 5.6]},
                          {"op": "wait", "seconds": 1}, {"op": "capture", "name": "remote-palette-loaded-brush"}]
        steps += [{"op": "digest", "name": f"{name}-{key}-seen"},
                  barrier([f"{n}-{key}-seen" for n in names])]
    return steps


def scripts(count, capture=False):
    names = ["host", "join"] + [f"late-{i}" for i in range(2, count)]
    result = {}
    for name in names:
        if name in ("host", "join"):
            steps = json.loads((ROOT / f"demo/coop-{name}.json").read_text())
            steps += sample(name, names[:2], 2)
        else:
            i = names.index(name)
            steps = [{"op": "place", "x": -2 * i, "z": 9}, {"op": "join"},
                     {"op": "until", "seq": SEQ + 2 * (i - 2), "players": count},
                     {"op": "wall", "points": [[2 * i, 16], [2 * i + 1, 16]], "seconds": 0.3},
                     {"op": "until", "seq": SEQ + 1 + 2 * (i - 2)},
                     {"op": "press", "button": "dpad_down"}]
        if count > 2:
            steps += [{"op": "until", "seq": SEQ + 2 * (count - 2)}]
            steps += sample(name, names, count)
        # Once every player's fish have come to the joiner's pond, the host throws seeds on it; every player sees them
        # surface alike from the water and the fish swarm them.
        steps += [{"op": "until", "swimming": 1}, {"op": "digest", "name": f"{name}-fish"}]
        if name == "host":
            steps += [barrier([f"{n}-fish" for n in names]),
                      {"op": "toss", "from": [12, 1.2, 10], "velocity": [0.2, 0.5, 0.1]}, {"op": "digest", "name": "host-threw"}]
        steps += [barrier(["host-threw"]), {"op": "wait", "seconds": 9.0}, {"op": "digest", "name": f"{name}-fed"},
                  barrier([f"{n}-fed" for n in names])]
        steps += [{"op": "digest", "name": f"{name}-final"},
                  barrier([f"{n}-final" for n in names])]
        last = SEQ + 2 * (count - 2)
        steps += easel_steps(name, names, last)
        last += EASEL_COMMANDS
        for k, (shape, lift) in enumerate([("peak", EXTREME), ("pit", -2 * EXTREME)]):
            if name == "join":
                steps += [{"op": "sculpt", "x": -50, "z": 50, "lift": lift, "seconds": 0.5}]
            steps += [{"op": "until", "seq": last + 1 + k}, {"op": "digest", "name": f"{name}-{shape}"},
                      barrier([f"{n}-{shape}" for n in names])]
        if name == "host":
            steps += [{"op": "fit", "what": "decoration", "index": 0, "s": 0.5 + i * 0.25, "style": i} for i in range(7)]
            steps += [{"op": "fit", "what": "decoration", "x": 20 + i, "z": 20, "style": i} for i in (7, 8)]
            steps += [{"op": "press", "button": "dpad_down"}, {"op": "press", "button": "A"}]
        steps += [{"op": "until", "seq": last + 13}, {"op": "digest", "name": f"{name}-decorations"},
                  barrier([f"{n}-decorations" for n in names])]
        # The joiner holds delete at the sky until the garden is wiped, then undoes it; every peer digests both.
        for k, (phase, step) in enumerate([("wiped", {"op": "wipe", "seconds": 2.5}), ("unwiped", {"op": "press", "button": "dpad_down"})]):
            if name == "join":
                steps += [step]
            steps += [{"op": "until", "seq": last + 14 + k}, {"op": "digest", "name": f"{name}-{phase}"},
                      barrier([f"{n}-{phase}" for n in names])]
        # The joiner sets down a boulder twenty times the size a house could hide behind, the budget aside on every
        # peer, so what checks it is the command's own validation as it crosses the wire.
        steps += [{"op": "budget", "bounded": False}, {"op": "digest", "name": f"{name}-unbounded"},
                  barrier([f"{n}-unbounded" for n in names])]
        if name == "join":
            steps += [{"op": "boulder", "x": -30, "z": -30, "seed": 4242, "scale": 160.0}]
        steps += [{"op": "until", "seq": last + 16}, {"op": "wait", "seconds": 0.5}, {"op": "digest", "name": f"{name}-boulder"},
                  barrier([f"{n}-boulder" for n in names])]
        if name == "host":
            steps += [{"op": "wipe", "seconds": 2.5}, {"op": "until", "seq": last + 17},
                      {"op": "easel", "x": -4, "z": 4}]
        steps += [{"op": "until", "seq": last + 18}]
        # The joiner presses a hollow, plants a tree in it and pours a pond over the tree, which drowns it, then undoes
        # the pond: every peer takes the undo as sent and sees the tree stand again.
        if name == "join":
            steps += [{"op": "sculpt", "x": DROWN[0], "z": DROWN[1], "lift": -1.0, "radius": 2.8, "seconds": 0.4},
                      {"op": "until", "seq": last + 19}, {"op": "tree", "x": DROWN[0], "z": DROWN[1], "seed": 4},
                      {"op": "until", "seq": last + 20}, {"op": "pond", "x": DROWN[0], "z": DROWN[1], "brim": 8.4}]
        steps += [{"op": "until", "seq": last + 21}, {"op": "wait", "seconds": 0.5}, {"op": "digest", "name": f"{name}-drowned"},
                  barrier([f"{n}-drowned" for n in names])]
        if name == "join":
            steps += [{"op": "press", "button": "dpad_down"}]
        steps += [{"op": "until", "seq": last + 22}, {"op": "wait", "seconds": 0.5}, {"op": "digest", "name": f"{name}-undrowned"},
                  barrier([f"{n}-undrowned" for n in names])]
        steps += held_steps(name, names, capture)
        steps += [{"op": "pick", "action": "avatar:2"},
                  {"op": "digest", "name": f"{name}-avatar-picked"},
                  barrier([f"{n}-avatar-picked" for n in names]),
                  {"op": "until", "avatar": 2},
                  {"op": "digest", "name": f"{name}-avatar-seen"},
                  barrier([f"{n}-avatar-seen" for n in names])]
        if name == "join":
            steps += [{"op": "visit", "home": True},
                      {"op": "until", "players": 1},
                      {"op": "wait", "seconds": 0.5}, {"op": "digest", "name": "home"}]
        else:
            steps += [barrier(["home"])]
        steps += [{"op": "quit"}]
        # What is synced is under test here, not the frame budget, which tests/test_budget.gd holds.
        result[name] = [{"op": "budget", "bounded": False}] + steps
    return result


def spawn_scripts(capture=False):
    result = {
        "host": [
            {"op": "sculpt", "x": 0, "z": 4, "lift": 12, "radius": 9, "seconds": 0.5},
            {"op": "digest", "name": "raised"},
            barrier(["joined"]),
        ],
        "join": [
            barrier(["raised"]), {"op": "join"},
            {"op": "digest", "name": "joined", "ground": True},
        ],
    }

    if capture:
        result["host"] += [
            {"op": "until", "players": 2, "worn": 1},
            {"op": "wait", "seconds": 1},
            {"op": "view", "eye": [6, 15, 11], "at": [0, 12.5, 4]},
            {"op": "capture", "name": "joiner-on-mountain"},
            {"op": "digest", "name": "captured"},
        ]
        result["join"] += [barrier(["captured"])]
    # The joiner goes home before the host may quit, so the host leaving never sends it home unasked.
    result["host"] += [barrier(["home"]), {"op": "quit"}]
    result["join"] += [{"op": "visit", "home": True}, {"op": "digest", "name": "home"}, {"op": "quit"}]
    return result


def check_spawn(out):
    joined = json.loads((out / "joined.json").read_text())
    raised = json.loads((out / "raised.json").read_text())
    assert joined["seq"] == raised["seq"] == 1 and joined["heights"] == raised["heights"], "joiner received the raised garden"
    probe = joined["ground"]
    print(f"spawn: {probe}", flush=True)
    assert probe["terrain"] > 10, "host raised a mountain at spawn"
    assert abs(probe["feet"] - probe["terrain"]) < 0.01, "joiner stands on current ground"


def held_scripts():
    return {
        "host": [
            {"op": "easel", "x": -4, "z": 4}, {"op": "until", "seq": 1},
            {"op": "digest", "name": "ready"}, barrier(["loaded"]), {"op": "until", "seq": 2},
            {"op": "remote_holds", "name": "loaded"},
            {"op": "view", "eye": [-3.0, 1.7, 4.8], "at": [-4, 1.25, 5.6]},
            {"op": "wait", "seconds": 1}, {"op": "capture", "name": "remote-palette-loaded-brush"},
            {"op": "digest", "name": "captured"}, barrier(["seen"]), {"op": "quit"},
        ],
        "join": [
            barrier(["ready"]), {"op": "join"}, {"op": "until", "seq": 1},
            {"op": "take", "what": "big"}, {"op": "dip", "what": "oil", "index": 5},
            {"op": "mix", "points": [[-0.3, -0.2, 0.9], [0.2, 0.25, 0.9], [-0.1, 0.3, 0.9]], "seconds": 0.5},
            {"op": "until", "seq": 2}, {"op": "dip", "what": "oil", "index": 5},
            {"op": "take", "what": "palette", "hand": "left"},
            {"op": "view", "eye": [-4, 1.65, 6], "at": [-4, 1.4, 4]},
            {"op": "hands", "left": [-0.32, -0.35, -0.4], "right": [0.32, -0.3, -0.4], "tip": 20},
            {"op": "held_snapshot", "name": "loaded", "loaded": True}, barrier(["captured"]),
            {"op": "digest", "name": "seen"}, {"op": "quit"},
        ],
    }


# A flat-screen player joins a VR host's garden through the visit tool's figures, walks up and takes a photo; both games
# render under one virtual display. Each wears its own VRM from its avatars folder: the flat-screen player's picker
# shows the host's, the host's captures show the flat-screen player's standing in its garden, and the photo lands in
# OUT/photos. Then the flat-screen player holds out the seed dish by the host's wall: a conure comes to stand on it in
# its own game, and in the host's another stands on the dish its avatar holds.
FLAT_AVATARS = {"host": "godette-0.x.vrm", "join": "crimsom-1.0.vrm"}


def flat_scripts():
    return {name: json.loads((ROOT / f"demo/flat-{name}.json").read_text()) for name in FLAT_AVATARS}


def check_flat(out):
    worn = json.loads((out / "host-seen.json").read_text())["worn"]
    own = hashlib.sha256((out / "avatars-join" / FLAT_AVATARS["join"]).read_bytes()).hexdigest()
    if worn != [own]:
        raise RuntimeError("the host does not see the flat-screen player's own avatar")
    fed = json.loads((out / "host-fed.json").read_text())["fed"]["dish"]
    if fed < 1:
        raise RuntimeError("the host sees no animal eating at the flat-screen player's dish")
    if not any((out / "photos").glob("*.png")):
        raise RuntimeError(f"no photo in {out / 'photos'}")


def reserve_beacons():
    # Reserve a fifth socket, outside the four listeners, so all four can be used.
    for base in random.sample(range(20000, 60000, 5), 8000):
        sockets = []
        try:
            for port in range(base, base + 5):
                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sockets.append(sock)
                sock.bind(("127.0.0.1", port))
        except OSError:
            for sock in sockets:
                sock.close()
            continue
        for sock in sockets[:4]:
            sock.close()
        return base, sockets[4]
    raise RuntimeError("no free beacon block")


def check_peers(out, count):
    """Whether every peer of a run of count players ended with the same garden, each step of it as the scripts made it."""
    names = list(scripts(count))
    d = {n: json.load(open(f"{out}/{n}-final.json")) for n in names}
    seen = {n: g.pop("avatars") for n, g in d.items()}
    worn = {n: sorted(g.pop("worn")) for n, g in d.items()}
    for g in d.values():
        g.pop("handfuls")
        g.pop("frenzy")
    own = {n: hashlib.sha256((ROOT / "tests/avatars" / AVATARS[i % len(AVATARS)]).read_bytes()).hexdigest() for i, n in enumerate(names[1:])}
    failed = []

    def check(cond, what):
        print(("ok: " if cond else "FAIL: ") + what)
        if not cond:
            failed.append(what)
    check(d["host"] == d["join"], "host and joiner show the same garden")
    for n in names[2:]:
        check(d[n] == d["host"], f"{n} shows the same garden")
    g = d["host"]
    check(g["seq"] == SEQ + 2 * (len(names) - 2), "every late joiner built and undid its own wall")
    check(len(g["walls"]) == 6, f"six walls stand (A put back by its deleter's undo, B, C, the host's house, the joiner's storey on it, the host's wing across it): {len(g['walls'])}")
    check(sum("\"on\": PackedInt32Array(" in w["data"] and "\"on\": PackedInt32Array()" not in w["data"] for w in g["walls"].values()) == 1, "the joiner's storey stands on the host's house")
    check(any(abs(w["height"] - 4.2) < 0.01 for w in g["walls"].values()), "the joiner's raised wall stands 4.2 m high")
    def sides(w):
        m = re.search(r'"points": PackedVector3Array\(([^)]*)\)', w["data"])
        v = [float(x) for x in m.group(1).split(",")]
        p = [(v[i], v[i + 2]) for i in range(0, len(v), 3)]
        return sorted(round(math.dist(p[i], p[(i + 1) % len(p)]), 2) for i in range(len(p)))
    check(any("roof" in w["data"] and sides(w) == [3.5, 3.5, 10.0, 10.0] for w in g["walls"].values()), "the joiner stretched the host's wing from 8 m to 10 m long: " + str([sides(w) for w in g["walls"].values() if "roof" in w["data"]]))
    rises = sorted(round(float(m.group(1)), 2) for w in g["walls"].values() for m in [re.search(r'"rise": ([0-9.]+)', w["data"])] if m)
    check(rises.count(0.9) == 1 and rises.count(0.0) == len(rises) - 1, f"the joiner raised the host's wing 0.9 m onto a plinth, and nothing else: {rises}")
    ends = sorted(int(re.search(r'"gable_end": (\d+)', w["data"]).group(1)) for w in g["walls"].values() if "roof" in w["data"])
    check(ends == [0, 1, 2], f"the host's house has the wall's gable ends, the joiner's storey boards and the host's wing crow steps: {ends}")
    houses = [w for w in g["walls"].values() if "roof" in w["data"]]
    check(len(houses) == 3 and all(w["floor"] != -math.inf for w in houses), f"every house, storey and wing is floored alike on every machine: {[w['floor'] for w in houses]}")
    storey = next(w for w in houses if '"on": PackedInt32Array()' not in w["data"])
    check(storey["floor"] > min(w["floor"] for w in houses if w is not storey) + 2.0, f"the joiner's storey is floored on the host's house's top: {storey['floor']}")
    kinds = lambda k: [v for v in g["groups"].values() if v["kind"] == k]
    check(len(kinds("tree")) == 1 and kinds("tree")[0]["shown"] == 0, "the host's undo took its tree away")
    check(len(kinds("bush")) == 1 and kinds("bush")[0]["shown"] == 1, "the joiner's bush stands")
    check(len(kinds("flowers")) == 1 and kinds("flowers")[0]["shown"] == kinds("flowers")[0]["plants"], "the joiner's undo then redo left its flowers standing")
    check(len(g["paths"]) == 1 and len(kinds("grass")) == 1, "the host's path and the grass painted across it stand")
    check(len(g["pond_levels"]) == 1 and g["ponds"] == 1, f"the joiner's pond holds water in the hollow it pressed: {g['pond_levels']}")
    paints = {k: (w["data"].split('"paint": ')[1].split(")")[0] + ")", re.search(r'"finish": [12],', w["data"]) is not None, '"on": PackedInt32Array()' not in w["data"]) for k, w in g["walls"].items()}
    picked = "PackedInt32Array(0, 0, 0, 0, 2, 0, 0, 0, 0)"
    check(all((p == picked) == (plaster or on) for p, plaster, on in paints.values()), f"the joiner's plaster on the host's wall, and on the storey it built after, is every machine's; no other wall changes: {paints}")
    meadow = g["groups"]["0"]
    check(sorted(meadow["species"])[-1:] == [2] and sum(meadow["species"]) == 2, f"the joiner's style tool turned one meadow tree a poplar on every machine: {[k for k in meadow['species'] if k]}")
    grown = [(k, round(x, 2)) for k, x in zip(meadow["species"], meadow["scale"]) if x != 1.0]
    check(len(grown) == 1 and grown[0][0] == 2 and grown[0][1] > 1.3, f"the joiner's grip grew that poplar on every machine: {grown}")
    check(meadow["plants"] - meadow["shown"] > 10, f"the joiner's deletes took a spawned tree, a bush and mown meadow: {meadow['plants'] - meadow['shown']} of the meadow's plants gone")
    check(len(g["grounds"]) == 1 and any("lanterns\": PackedVector3Array(3" in w["data"] for w in g["walls"].values()), "the host's stone ground and lantern stand")
    easels = list(g["easels"].values())
    check(len(easels) == 1 and easels[0]["strokes"] == 2, f"the host's easel holds the joiner's watercolour stroke and the host's oil one: {easels}")
    check(easels[0]["palette"] == 1, f"and the host's blue painted onto its oil palette, a stroke there on every machine: {easels}")
    for shape, reach in [("peak", lambda h: h[1] > 450), ("pit", lambda h: h[0] < -450)]:
        seen_shape = {n: json.load(open(f"{out}/{n}-{shape}.json")) for n in names}
        for v in seen_shape.values():
            for k in ("avatars", "worn", "handfuls", "frenzy"):
                v.pop(k)
        check(all(v == seen_shape["host"] for v in seen_shape.values()), f"every peer shows the joiner's {shape} the same")
        check(reach(seen_shape["host"]["heights"]), f"the joiner's one stroke {shape} reaches past 450 m: {seen_shape['host']['heights']}")
    for phase, shown in [("drowned", False), ("undrowned", True)]:
        seen_phase = {n: json.load(open(f"{out}/{n}-{phase}.json")) for n in names}
        for v in seen_phase.values():
            for k in ("avatars", "worn", "handfuls", "frenzy"):
                v.pop(k)
        check(all(v == seen_phase["host"] for v in seen_phase.values()), f"every peer shows the garden alike once {phase}")
        trees = [v for v in seen_phase["host"]["groups"].values() if v["kind"] == "tree"]
        check(len(trees) == 1 and (trees[0]["shown"] == trees[0]["plants"] if shown else trees[0]["shown"] == 0)
              and seen_phase["host"]["ponds"] == int(not shown), f"the joiner's pond {'came away and the tree stands' if shown else 'drowned its tree'}: {trees}, {seen_phase['host']['ponds']} ponds")
    painted = {n: json.load(open(f"{out}/{n}-easel.json")) for n in names}
    for v in painted.values():
        for k in ("avatars", "worn", "handfuls", "frenzy"):
            v.pop(k)
    check(all(v == painted["host"] for v in painted.values()), "every peer shows the easel alike after the host and the joiner took charcoal, switched, set down and tore there together")
    check([e["strokes"] for e in painted["host"]["easels"].values()] == [2], f"the joiner's sheet tore off both first strokes; its charcoal stroke and the host's after stand: {painted['host']['easels']}")
    check([e["palette"] for e in painted["host"]["easels"].values()] == [1], f"the host's blue lies on the oil palette as one stroke, the same on every peer: {painted['host']['easels']}")
    turned = json.load(open(f"{out}/host-sun.json"))["sun"]
    check(abs(turned - 0.6683) < 0.02, f"the host sees the sun where the joiner turned it: {turned:.3f}")
    check(abs(g["sun"] - 0.3878) < 0.02, f"every peer sees the sun where the host turned it back: {g['sun']:.3f}")
    fed = {n: json.load(open(f"{out}/{n}-fed.json")) for n in names}
    landed = {n: f["handfuls"] for n, f in fed.items()}
    check(all(len(h) == 1 for h in landed.values()) and all(math.dist(h[0], landed["host"][0]) < 0.03 for h in landed.values()),
          f"the host's thrown seeds land alike for every player: {landed}")
    frenzy = {n: f["frenzy"] for n, f in fed.items()}
    check(all(f[1] > 0 and f[0] == f[1] for f in frenzy.values()), f"and every player sees every fish of the pond swarm them: {frenzy}")
    home = json.load(open(f"{out}/home.json"))
    for k in ("avatars", "worn", "handfuls", "frenzy"):
        home.pop(k)
    check(len(home["walls"]) == 1 and list(home["groups"]) == ["0"] and not home["paths"] and home["ponds"] == 0 and home["season"] == 1, "the visitor's own garden, one wall, is back when it goes home")
    check(seen == {n: len(names) - 1 for n in names}, f"each player sees all other avatars: {seen}")
    for n in names:
        expected = sorted(h for peer, h in own.items() if peer != n)
        check(worn[n] == expected, f"{n} sees every other custom avatar: {worn[n]}")
    decorated = {n: json.load(open(f"{out}/{n}-decorations.json"))["decorations"] for n in names}
    check(all(v == decorated["host"] for v in decorated.values()), "decoration styles and seeds sync after undo and redo")
    check(len(decorated["host"]) == 9, "all nine decoration styles survive co-op undo and redo")
    LIVE = ("seq", "avatars", "worn", "handfuls", "frenzy", "fed", "sun", "avatar_choices")
    garden = lambda phase: {n: {k: v for k, v in json.load(open(f"{out}/{n}-{phase}.json")).items() if k not in LIVE} for n in names}
    wiped, unwiped, built = garden("wiped"), garden("unwiped"), garden("decorations")
    w = wiped["host"]
    check(all(v == w for v in wiped.values()), "every peer shows the joiner's wipe alike")
    check(not w["walls"] and list(w["groups"]) == ["0"] and not w["paths"] and not w["grounds"] and not w["pond_levels"] and not w["easels"],
          f"the joiner's wipe left bare meadow: {len(w['walls'])} walls, groups {list(w['groups'])}, {len(w['paths'])} paths, {len(w['easels'])} easels")
    check(all(v == unwiped["host"] for v in unwiped.values()), "every peer shows the joiner's undone wipe alike")
    check(unwiped["host"] == built["host"], "the joiner's undo brings back every build of the garden as it was, every plant where it stood")
    rocks = {n: json.load(open(f"{out}/{n}-boulder.json"))["boulders"] for n in names}
    check(all(v == rocks["host"] for v in rocks.values()), "the joiner's huge boulder stands alike on every machine")
    check([b["scale"] for b in rocks["host"].values()] == [160.0], f"at twenty times the size a house could hide behind: {rocks['host']}")
    return not failed


def run(out, count, mode="full", capture=False):
    out.mkdir(parents=True, exist_ok=True)
    for path in out.glob("*.json"):
        path.unlink()
    full = mode == "full"
    generated = {"full": lambda: scripts(count, capture), "spawn": lambda: spawn_scripts(capture),
                 "held": held_scripts, "flat": flat_scripts}[mode]()
    for name, steps in generated.items():
        (out / f"script-{name}.json").write_text(json.dumps(steps, indent=2))
    beacon, reservation = reserve_beacons()
    processes = {}
    display = None
    xserver = None
    logs = []
    cpu = {}
    stopped = threading.Event()
    ticks_per_second = os.sysconf("SC_CLK_TCK")

    def monitor():
        while not stopped.is_set():
            for name, proc in list(processes.items()):
                try:
                    stat = Path(f"/proc/{proc.pid}/stat").read_text().rsplit(")", 1)[1].split()
                except FileNotFoundError:
                    continue
                cpu.setdefault(name, []).append([time.time(), (int(stat[11]) + int(stat[12])) / ticks_per_second])
            stopped.wait(0.1)

    sampler = threading.Thread(target=monitor)
    sampler.start()
    # One of Session's blocks of PORTS = 8 host ports in its PORT_RANGE from 7480, so runs side by side spread out.
    first = 7480 + 8 * random.randrange(7)

    def launch(name, port):
        rendered = mode == "flat" or capture and name == "host"
        args = ["godot4", "--path", str(ROOT / "game"), "--xr-mode", "off"]
        args += ["--resolution", "1200x900"] if mode == "flat" else [] if rendered else ["--headless"]
        args += ["--", "--desktop", "--script", str(out / f"script-{name}.json"),
                 "--capture-dir", str(out), "--host-port", str(port),
                 "--beacon-port", str(beacon), "--port", str(port if name == "host" else first)]
        vrm = None
        if mode == "flat":
            vrm = FLAT_AVATARS[name]
            args += ["--quit-after", "600"]
            if name == "join":
                args.append("--flat")
        elif name != "host":
            i = list(generated).index(name) - 1
            vrm = AVATARS[i % len(AVATARS)]
            args += ["--avatar", str(i + 1)]
        if vrm:
            folder = out / f"avatars-{name}"
            folder.mkdir(exist_ok=True)
            for path in folder.glob("*.vrm"):
                path.unlink()
            (folder / vrm).write_bytes((ROOT / "tests/avatars" / vrm).read_bytes())
            args += ["--avatars", str(folder)]
        log = (out / f"{name}.log").open("w")
        logs.append(log)
        env = dict(os.environ, DISPLAY=display) if rendered else None
        if mode == "flat":
            env["VK_ICD_FILENAMES"] = os.environ.get("CAIRNFOLD_ICD", "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json")
        processes[name] = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, env=env)

    progress = {"steps": 0, "cpu": 0.0, "quiet": 0.0}

    def fail(name, what):
        # The run's output is all a landing keeps, so the end of the player's log goes there.
        log = out / f"{name}.log"
        print("".join(f"{name}: {line}\n" for line in log.read_text(errors="replace").splitlines()[-60:]), end="", flush=True)
        raise RuntimeError(f"{name} {what}; see {log}")

    def check():
        last = {}
        if full:
            for name in generated:
                picked = out / f"{name}-avatar-seen.json"
                if picked.exists():
                    state = json.loads(picked.read_text())
                    if state.get("avatar_choices") != [2] * count or state.get("worn"):
                        fail(name, "wheel avatar selection did not replicate to every peer")
        for name, proc in processes.items():
            if proc.poll():
                fail(name, f"exited {proc.returncode}")
            text = (out / f"{name}.log").read_text(errors="replace")
            if "handle_crash" in text:
                # A crashing player writes its backtrace and core before it aborts; ending it first would lose both.
                proc.wait()
                fail(name, "crashed")
            if any(s in text for s in ("SCRIPT ERROR", "must be normalized", "timed out", "cannot apply", "tree_exited")):
                fail(name, "failed")
            if "session: home from" in HOME_CUE.split(text, 1)[0]:
                fail(name, "lost the garden it visited")
            last[name] = [line for line in text.splitlines() if line.startswith("driver: {")]
        steps = sum(len(lines) for lines in last.values())
        spent = sum(samples[-1][1] for samples in list(cpu.values()))
        if steps > progress["steps"]:
            progress.update(steps=steps, cpu=spent)
        progress["quiet"] = max(progress["quiet"], spent - progress["cpu"])
        if spent - progress["cpu"] > QUIET_CPU:
            raise RuntimeError(f"no player took a step in {QUIET_CPU} CPU-seconds: "
                               + "; ".join(f"{n} at {lines[-1] if lines else 'start'}" for n, lines in last.items()))

    def until(predicate):
        while not predicate():
            check()
            time.sleep(0.1)

    try:
        if capture or mode == "flat":
            # The flat-screen run puts both players' windows side by side.
            screen = "2560x1024x24" if mode == "flat" else "1600x1200x24"
            reader, writer = os.pipe()
            xserver = subprocess.Popen(["Xvfb", "-displayfd", str(writer), "-screen", "0", screen, "-nolisten", "tcp"], pass_fds=(writer,))
            os.close(writer)
            with os.fdopen(reader) as ready:
                display = ":" + ready.readline().strip()
        launch("host", first)
        def host_port():
            for line in (out / "host.log").read_text().splitlines():
                if line.startswith("session: hosting on port "):
                    return int(line.rsplit(" ", 1)[1])
        until(host_port)
        port = host_port()
        print(f"coop: {count} players, host port {port}, beacon ports {beacon}–{beacon + 3}", flush=True)
        launch("join", port)
        if full:
            until(lambda: all((out / f"{n}-2-players-cost.json").exists() for n in ("host", "join")))
            for name in list(generated)[2:]:
                launch(name, port)
        until(lambda: all(p.poll() is not None for p in processes.values()))
        check()
        if full:
            print("ok: inventory-wheel avatar selection is visible to every peer", flush=True)
    finally:
        for proc in processes.values():
            if proc.poll() is None:
                proc.terminate()
        for proc in processes.values():
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        for log in logs:
            log.close()
        stopped.set()
        sampler.join()
        (out / "process-cpu.json").write_text(json.dumps(cpu))
        reservation.close()
        if xserver is not None:
            xserver.terminate()
            xserver.wait()
    print(f"coop: longest stretch without a step took {progress['quiet']:.1f} of {QUIET_CPU} CPU-seconds", flush=True)
    if mode == "held":
        assert (out / "remote-palette-loaded-brush.png").is_file(), "remote held capture exists"
        return
    if mode == "spawn":
        check_spawn(out)
        return
    if mode == "flat":
        check_flat(out)
        return
    if not check_peers(out, count):
        raise SystemExit("coop: the peers' gardens differ")
    rows = []
    for path in sorted(out.glob("*-cost.json")):
        row = json.loads(path.read_text())
        name = path.stem.rsplit("-", 3)[0]
        samples = [s for s in cpu[name] if row["start_unix"] <= s[0] <= row["end_unix"]]
        if len(samples) < 2:
            raise RuntimeError(f"missing CPU samples for {name}")
        row["cpu_seconds"] = samples[-1][1] - samples[0][1]
        row["cpu_sample_seconds"] = samples[-1][0] - samples[0][0]
        row["cpu_ms_s"] = 1000 * row["cpu_seconds"] / row["cpu_sample_seconds"]
        rows.append(row)
        print(f"cost: {path.stem}: tx {row['tx_bytes_s']:.1f} B/s, rx {row['rx_bytes_s']:.1f} B/s, "
              f"CPU {row['cpu_ms_s']:.1f} ms/s, process {row['process_ms_frame']:.3f} ms/frame, "
              f"physics {row['physics_ms_frame']:.3f} ms/frame")
    (out / "costs.json").write_text(json.dumps(rows, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path)
    parser.add_argument("players", type=int, nargs="?", default=4)
    parser.add_argument("--held", action="store_true", help="capture and assert a peer holding a palette and loaded brush")
    parser.add_argument("--spawn", action="store_true", help="only the late-join mountain regression")
    parser.add_argument("--capture", action="store_true", help="render the spawn regression on a virtual display")
    parser.add_argument("--flat", action="store_true", help="only a flat-screen player visiting a rendered host")
    args = parser.parse_args()
    if not 2 <= args.players <= 8:
        parser.error("players must be 2..8 (Session.MAX_PLAYERS)")
    if args.held:
        run(args.out.resolve(), 2, "held", capture=True)
        raise SystemExit(0)
    if args.flat:
        run(args.out.resolve(), 2, "flat")
        raise SystemExit(0)
    run(args.out.resolve() / "spawn", 2, "spawn", capture=args.capture)
    if not args.spawn:
        run(args.out.resolve(), args.players, capture=args.capture)
