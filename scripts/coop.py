"""Drive the existing build gestures with N peers, then check every peer's view."""
import argparse
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
# run in wall time, so no wall-clock limit applies.
QUIET_CPU = 40
# Going home before these steps means a player lost the garden it was visiting.
# The host and the joiner end their builds and turns of the sky at this command; late joiners build after it.
SEQ = 33
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
        {"op": "network_sample", "name": f"{name}-{phase}-cost", "seconds": 10},
        barrier([f"{n}-{phase}-cost" for n in names]),
    ]


def scripts(count):
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
        # land alike and the fish swarm them.
        steps += [{"op": "until", "swimming": 1}, {"op": "digest", "name": f"{name}-fish"}]
        if name == "host":
            steps += [barrier([f"{n}-fish" for n in names]),
                      {"op": "toss", "from": [12, 1.2, 10], "velocity": [0.2, 0.5, 0.1]}, {"op": "digest", "name": "host-threw"}]
        steps += [barrier(["host-threw"]), {"op": "wait", "seconds": 1.5}, {"op": "digest", "name": f"{name}-fed"},
                  barrier([f"{n}-fed" for n in names])]
        steps += [{"op": "digest", "name": f"{name}-final"},
                  barrier([f"{n}-final" for n in names])]
        if name == "join":
            steps += [{"op": "visit", "home": True},
                      {"op": "until", "players": 1},
                      {"op": "wait", "seconds": 0.5}, {"op": "digest", "name": "home"}]
        else:
            steps += [barrier(["home"])]
        steps += [{"op": "quit"}]
        result[name] = steps
    return result


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


def run(out, count):
    out.mkdir(parents=True, exist_ok=True)
    for path in out.glob("*.json"):
        path.unlink()
    generated = scripts(count)
    for name, steps in generated.items():
        (out / f"script-{name}.json").write_text(json.dumps(steps, indent=2))
    beacon, reservation = reserve_beacons()
    processes = {}
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
        args = ["godot4", "--headless", "--path", str(ROOT / "game"), "--xr-mode", "off",
                "--", "--desktop", "--script", str(out / f"script-{name}.json"),
                "--capture-dir", str(out), "--host-port", str(port),
                "--beacon-port", str(beacon), "--port", str(port if name == "host" else first)]
        if name != "host":
            i = list(generated).index(name) - 1
            folder = out / f"avatars-{name}"
            folder.mkdir(exist_ok=True)
            for path in folder.glob("*.vrm"):
                path.unlink()
            (folder / files[i % len(files)]).write_bytes((ROOT / "tests/avatars" / files[i % len(files)]).read_bytes())
            args += ["--avatars", str(folder), "--avatar", str(i + 1)]
        log = (out / f"{name}.log").open("w")
        logs.append(log)
        processes[name] = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)

    progress = {"steps": 0, "cpu": 0.0, "quiet": 0.0}

    def check():
        last = {}
        for name, proc in processes.items():
            if proc.poll():
                raise RuntimeError(f"{name} exited unsuccessfully")
            text = (out / f"{name}.log").read_text(errors="replace")
            if any(s in text for s in ("SCRIPT ERROR", "timed out", "handle_crash", "cannot apply", "tree_exited")):
                raise RuntimeError(f"{name} failed; see {out / (name + '.log')}")
            if "session: home from" in HOME_CUE.split(text, 1)[0]:
                raise RuntimeError(f"{name} lost the garden it visited; see {out / (name + '.log')}")
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
        launch("host", first)
        def host_port():
            for line in (out / "host.log").read_text().splitlines():
                if line.startswith("session: hosting on port "):
                    return int(line.rsplit(" ", 1)[1])
        until(host_port)
        port = host_port()
        print(f"coop: {count} players, host port {port}, beacon ports {beacon}–{beacon + 3}", flush=True)
        launch("join", port)
        until(lambda: all((out / f"{n}-2-players-cost.json").exists() for n in ("host", "join")))
        for name in list(generated)[2:]:
            launch(name, port)
        until(lambda: all(p.poll() is not None for p in processes.values()))
        check()
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
    print(f"coop: longest stretch without a step took {progress['quiet']:.1f} of {QUIET_CPU} CPU-seconds", flush=True)
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
    args = parser.parse_args()
    if not 2 <= args.players <= 8:
        parser.error("players must be 2..8 (Session.MAX_PLAYERS)")
    run(args.out.resolve(), args.players)
