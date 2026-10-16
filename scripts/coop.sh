#!/usr/bin/env bash
# Two players build together and a third joins late, all headless on this machine: coop.sh OUT_DIR
# The second finds the first by its beacon and visits through the visit tool, then goes home. The second wears a
# VRM 1.0 avatar of its own and the third a VRM 0.x one, from their avatar folders.
# Fails unless the three gardens match each other and the expected outcome of the scripted session.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [ -z "${2:-}" ]; then
  exec python3 - "$root/scripts/coop.sh" "$1" <<'PYTHON'
import random, socket, subprocess, sys
# Hold the fourth socket for the whole run: other runs cannot select this block
# while the three players open and close their listeners.
for base in random.sample(range(20000, 60000, 4), 10000):
    sockets = []
    try:
        for port in range(base, base + 4):
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sockets.append(sock)
            sock.bind(("127.0.0.1", port))
    except OSError:
        for sock in sockets:
            sock.close()
        continue
    for sock in sockets[:3]:
        sock.close()
    print(f"coop: beacon ports {base}–{base + 3}", flush=True)
    sys.exit(subprocess.call(["bash", sys.argv[1], sys.argv[2], str(base)]))
sys.exit("coop: no free beacon block")
PYTHON
fi
beacon_port=$2
out=$(realpath -m "$1")
mkdir -p "$out"
cd "$out"
rm -f "$out"/*.json
# Ports of their own, so other instances on this machine (another checkout's tests) are not mistaken for the host.
port=$((7480 + 8 * (RANDOM % 7)))
run() { timeout 120 stdbuf -oL godot4 --headless --path "$root/game" --xr-mode off -- --desktop --script "$root/demo/coop-$1.json" --quit-after 110 --capture-dir "$out" --host-port "$port" --beacon-port "$beacon_port" "${@:2}" >"$out/$1.log" 2>&1; }
: >"$out/host.log"
run host --port "$port" & host=$!
# Session may fall back to another port when the requested one is occupied.
requested=$port
port=""
while kill -0 "$host" 2>/dev/null; do
  port=$(sed -n 's/^session: hosting on port //p' "$out/host.log" | head -1)
  [ -z "$port" ] || break
  sleep 0.1
done
if [ -z "$port" ]; then
  wait "$host" || true
  echo "coop: host exited before opening a port" >&2
  exit 1
fi
echo "coop: host requested $requested, bound $port"
for p in join late; do mkdir -p "$out/avatars-$p"; done
cp "$root/tests/avatars/crimsom-1.0.vrm" "$out/avatars-join/"
cp "$root/tests/avatars/godette-0.x.vrm" "$out/avatars-late/"
run join --avatar 1 --port $((port + 8)) --avatars "$out/avatars-join" & join=$!
while [ ! -e "$out/host.json" ] && kill -0 "$host" 2>/dev/null; do sleep 0.5; done
run late --avatar 2 --port $((port + 8)) --avatars "$out/avatars-late" & late=$!
status=0
for p in "$host" "$join" "$late"; do wait "$p" || status=1; done
for log in "$out"/*.log; do
  grep -q "^handle_crash" "$log" || continue
  echo "coop: $(basename "$log" .log) crashed in:" >&2
  grep -o 'godot4(+0x[0-9a-f]*)' "$log" | grep -o '0x[0-9a-f]*' | xargs addr2line -f -C -e "$(command -v godot4)" | sed -n 'p;n' >&2
done
grep -h "driver: until" "$out"/*.log && status=1
python3 - "$out" "$root/tests/avatars" <<'PY' || status=1
import hashlib, json, math, re, sys
out = sys.argv[1]
d = {n: json.load(open(f"{out}/{n}.json")) for n in ("host", "join", "late")}
seen = {n: g.pop("avatars") for n, g in d.items()}
worn = {n: sorted(g.pop("worn")) for n, g in d.items()}
own = {n: hashlib.sha256(open(f"{sys.argv[2]}/{f}", "rb").read()).hexdigest() for n, f in (("join", "crimsom-1.0.vrm"), ("late", "godette-0.x.vrm"))}
ok = True
def check(cond, what):
    global ok
    print(("ok: " if cond else "FAIL: ") + what)
    ok = ok and cond
check(d["host"] == d["join"], "host and joiner show the same garden")
check(d["late"] == d["host"], "the late joiner shows the same garden")
g = d["host"]
check(len(g["walls"]) == 6, f"six walls stand (A put back by its deleter's undo, B, C, the host's house, the joiner's storey on it, the host's wing across it): {len(g['walls'])}")
check(sum("\"on\": PackedInt32Array(" in w["data"] and "\"on\": PackedInt32Array()" not in w["data"] for w in g["walls"].values()) == 1, "the joiner's storey stands on the host's house")
check(any(abs(w["height"] - 4.2) < 0.01 for w in g["walls"].values()), "the joiner's raised wall stands 4.2 m high")
def sides(w):
    m = re.search(r'"points": PackedVector3Array\(([^)]*)\)', w["data"])
    v = [float(x) for x in m.group(1).split(",")]
    p = [(v[i], v[i + 2]) for i in range(0, len(v), 3)]
    return sorted(round(math.dist(p[i], p[(i + 1) % len(p)]), 2) for i in range(len(p)))
check(any("roof" in w["data"] and sides(w) == [3.5, 3.5, 10.0, 10.0] for w in g["walls"].values()), "the joiner stretched the host's wing from 8 m to 10 m long: " + str([sides(w) for w in g["walls"].values() if "roof" in w["data"]]))
kinds = lambda k: [v for v in g["groups"].values() if v["kind"] == k]
check(len(kinds("tree")) == 1 and kinds("tree")[0]["shown"] == 0, "the host's undo took its tree away")
check(len(kinds("flowers")) == 1 and kinds("flowers")[0]["shown"] == kinds("flowers")[0]["plants"], "the joiner's undo then redo left its flowers standing")
check(len(g["paths"]) == 1 and len(kinds("grass")) == 1, "the host's path and the grass painted across it stand")
check(len(g["seeds"]) == 1 and g["ponds"] == 1, f"the joiner's dug pond holds water: {g['ponds']} ponds")
paints = {k: (w["data"].split('"paint": ')[1].split(")")[0] + ")", '"plaster": true' in w["data"], '"on": PackedInt32Array()' not in w["data"]) for k, w in g["walls"].items()}
picked = "PackedInt32Array(0, 0, 0, 0, 2)"
check(all((p == picked) == (plaster or on) for p, plaster, on in paints.values()), f"the joiner's plaster on the host's wall, and on the storey it built after, is every machine's; no other wall changes: {paints}")
meadow = g["groups"]["0"]
check(meadow["plants"] - meadow["shown"] > 10, f"the joiner's deletes took a spawned tree, a bush and mown meadow: {meadow['plants'] - meadow['shown']} of the meadow's plants gone")
check(len(g["grounds"]) == 1 and any("lanterns\": PackedVector3Array(3" in w["data"] for w in g["walls"].values()), "the host's stone ground and lantern stand")
home = json.load(open(f"{out}/home.json"))
home.pop("avatars")
home.pop("worn")
check(len(home["walls"]) == 1 and list(home["groups"]) == ["0"] and not home["paths"] and home["ponds"] == 0 and home["season"] == 1, "the visitor's own garden, one wall, is back when it goes home")
check(seen == {"host": 1, "join": 1, "late": 2}, f"each player sees the others' avatars: {seen}")
check(worn == {"host": [own["join"]], "join": [], "late": [own["join"]]}, f"the host and the late joiner see the joiner in its own VRM 1.0 avatar: {worn}")
late = json.load(open(f"{out}/host-late.json"))["worn"]
check(sorted(late) == sorted(own.values()), f"the host then sees the late joiner in its own VRM 0.x avatar too: {late}")
sys.exit(0 if ok else 1)
PY
exit "$status"
