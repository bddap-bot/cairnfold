#!/usr/bin/env bash
# Two players build together and a third joins late, all headless on this machine: coop.sh OUT_DIR
# The second finds the first by its beacon and visits through the visit tool, then goes home.
# Fails unless the three gardens match each other and the expected outcome of the scripted session.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(realpath -m "$1")
mkdir -p "$out"
cd "$out"
# Ports of their own, so other instances on this machine (another checkout's tests) are not mistaken for the host.
port=$((7480 + 8 * (RANDOM % 7)))
run() { timeout 120 stdbuf -oL godot4 --headless --path "$root/game" --xr-mode off -- --desktop --script "$root/demo/coop-$1.json" --quit-after 110 --capture-dir "$out" --host-port "$port" "${@:2}" >"$out/$1.log" 2>&1; }
run host --port "$port" & host=$!
sleep 2
run join --avatar 1 --port $((port + 8)) & join=$!
while [ ! -e "$out/host.json" ] && kill -0 "$host" 2>/dev/null; do sleep 0.5; done
run late --avatar 2 --port $((port + 8)) & late=$!
status=0
for p in "$host" "$join" "$late"; do wait "$p" || status=1; done
grep -h "driver: until" "$out"/*.log && status=1
python3 - "$out" <<'PY' || status=1
import json, sys
out = sys.argv[1]
d = {n: json.load(open(f"{out}/{n}.json")) for n in ("host", "join", "late")}
seen = {n: g.pop("avatars") for n, g in d.items()}
ok = True
def check(cond, what):
    global ok
    print(("ok: " if cond else "FAIL: ") + what)
    ok = ok and cond
check(d["host"] == d["join"], "host and joiner show the same garden")
check(d["late"] == d["host"], "the late joiner shows the same garden")
g = d["host"]
check(len(g["walls"]) == 3, f"three walls stand (A put back by its deleter's undo, B, C): {len(g['walls'])}")
check(any(abs(w["height"] - 4.2) < 0.01 for w in g["walls"].values()), "the joiner's raised wall stands 4.2 m high")
kinds = lambda k: [v for v in g["groups"].values() if v["kind"] == k]
check(len(kinds("tree")) == 1 and kinds("tree")[0]["shown"] == 0, "the host's undo took its tree away")
check(len(kinds("flowers")) == 1 and kinds("flowers")[0]["shown"] == kinds("flowers")[0]["plants"], "the joiner's undo then redo left its flowers standing")
check(len(g["paths"]) == 1 and len(kinds("grass")) == 1, "the host's path and the grass painted across it stand")
check(len(g["seeds"]) == 1 and g["ponds"] == 1, f"the joiner's dug pond holds water: {g['ponds']} ponds")
check(g["palette"][2] == 3, f"the joiner's roof colour is the garden's: {g['palette']}")
check(len(g["grounds"]) == 1 and any("lanterns\": PackedVector3Array(3" in w["data"] for w in g["walls"].values()), "the host's stone ground and lantern stand")
home = json.load(open(f"{out}/home.json"))
home.pop("avatars")
check(len(home["walls"]) == 1 and list(home["groups"]) == ["0"] and not home["paths"] and home["ponds"] == 0 and home["palette"] == [1, 0, 0, 0, 0], "the visitor's own garden, one wall, is back when it goes home")
check(seen == {"host": 1, "join": 1, "late": 2}, f"each player sees the others' avatars: {seen}")
sys.exit(0 if ok else 1)
PY
exit "$status"
