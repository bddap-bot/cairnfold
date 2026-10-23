"""Drive the existing build gestures with N peers, then check every peer's view."""
import argparse
import hashlib
import json
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


# The host and the joiner, at the host's easel together, take the charcoal and switch, set down, tear and pick tools
# while the other paints or holds the same palette; after each step the hand must hold what it should, and once the
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
        [{"op": "take", "what": "stick"}, {"op": "holds", "what": "stick"},
         {"op": "brush", "points": [[0.6, 0.3, 0.8], [0.9, 0.35, 0.8]], "seconds": 0.3},
         {"op": "take", "what": "palette"}, {"op": "holds", "what": "oil palette"}],
        [{"op": "take", "what": "stick"}, {"op": "holds", "what": "stick"},
         {"op": "sheet", "pull": 0.5}, {"op": "holds", "what": "stick"},
         {"op": "brush", "points": [[0.6, 0.5, 0.8], [0.9, 0.55, 0.8]], "seconds": 0.3}],
        [{"op": "rests"}, {"op": "pick", "tool": "seeds"}, {"op": "holds", "what": "seeds"},
         {"op": "pick", "tool": "easel"}, {"op": "holds", "what": "stick"},
         {"op": "take", "what": "flat"}, {"op": "holds", "what": "flat"},
         {"op": "take", "what": "stick"}, {"op": "holds", "what": "stick"},
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
    tools = ["walls", "flowers", "grass", "trees", "delete", "pond", "fence", "windows", "decorations", "stone", "colour", "camera", "house", "seeds", "dirt_path", "style", "stairs", "tower", "arch", "book", "selfie", "bushes", "boulder", "moss", "none"]
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
            {"op": "digest", "name": "ready"}, barrier(["loaded"]),
            {"op": "remote_holds", "name": "loaded"},
            {"op": "view", "eye": [-3.0, 1.7, 4.8], "at": [-4, 1.25, 5.6]},
            {"op": "wait", "seconds": 1}, {"op": "capture", "name": "remote-palette-loaded-brush"},
            {"op": "digest", "name": "captured"}, barrier(["seen"]), {"op": "quit"},
        ],
        "join": [
            barrier(["ready"]), {"op": "join"}, {"op": "until", "seq": 1},
            {"op": "take", "what": "big"}, {"op": "dip", "what": "oil", "index": 5},
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
    assert worn == [own], "the host sees the flat-screen player's own avatar"
    fed = json.loads((out / "host-fed.json").read_text())["fed"]["dish"]
    assert fed >= 1, "the host sees an animal eating at the flat-screen player's dish"
    assert any((out / "photos").glob("*.png")), f"a photo in {out / 'photos'}"


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
    files = ["crimsom-1.0.vrm", "godette-0.x.vrm", "crimsom-0.x.vrm"]

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
            if name == "join":
                args.append("--flat")
        elif name != "host":
            i = list(generated).index(name) - 1
            vrm = files[i % len(files)]
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
        icd = os.environ.get("NESTCOMBE_ICD", "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json")
        processes[name] = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT,
                                           env=dict(os.environ, DISPLAY=display, VK_ICD_FILENAMES=icd) if rendered else None)

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
    subprocess.run(["python3", str(ROOT / "scripts/coop-check.py"), str(out),
                    str(ROOT / "tests/avatars"), str(count)], check=True)
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
