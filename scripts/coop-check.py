import hashlib, json, math, re, sys
out = sys.argv[1]
names = ["host", "join"] + [f"late-{i}" for i in range(2, int(sys.argv[3]))]
d = {n: json.load(open(f"{out}/{n}-final.json")) for n in names}
seen = {n: g.pop("avatars") for n, g in d.items()}
worn = {n: sorted(g.pop("worn")) for n, g in d.items()}
files = ["crimsom-1.0.vrm", "godette-0.x.vrm", "crimsom-0.x.vrm"]
own = {n: hashlib.sha256(open(f"{sys.argv[2]}/{files[i % len(files)]}", "rb").read()).hexdigest() for i, n in enumerate(names[1:])}
ok = True
def check(cond, what):
    global ok
    print(("ok: " if cond else "FAIL: ") + what)
    ok = ok and cond
check(d["host"] == d["join"], "host and joiner show the same garden")
for n in names[2:]:
    check(d[n] == d["host"], f"{n} shows the same garden")
g = d["host"]
check(g["seq"] == 31 + 2 * (len(names) - 2), "every late joiner built and undid its own wall")
check(len(g["walls"]) == 6, f"six walls stand (A put back by its deleter's undo, B, C, the host's house, the joiner's storey on it, the host's wing across it): {len(g['walls'])}")
check(sum("\"on\": PackedInt32Array(" in w["data"] and "\"on\": PackedInt32Array()" not in w["data"] for w in g["walls"].values()) == 1, "the joiner's storey stands on the host's house")
check(any(abs(w["height"] - 4.2) < 0.01 for w in g["walls"].values()), "the joiner's raised wall stands 4.2 m high")
def sides(w):
    m = re.search(r'"points": PackedVector3Array\(([^)]*)\)', w["data"])
    v = [float(x) for x in m.group(1).split(",")]
    p = [(v[i], v[i + 2]) for i in range(0, len(v), 3)]
    return sorted(round(math.dist(p[i], p[(i + 1) % len(p)]), 2) for i in range(len(p)))
check(any("roof" in w["data"] and sides(w) == [3.5, 3.5, 10.0, 10.0] for w in g["walls"].values()), "the joiner stretched the host's wing from 8 m to 10 m long: " + str([sides(w) for w in g["walls"].values() if "roof" in w["data"]]))
ends = sorted(int(re.search(r'"gable_end": (\d+)', w["data"]).group(1)) for w in g["walls"].values() if "roof" in w["data"])
check(ends == [0, 1, 2], f"the host's house has the wall's gable ends, the joiner's storey boards and the host's wing crow steps: {ends}")
kinds = lambda k: [v for v in g["groups"].values() if v["kind"] == k]
check(len(kinds("tree")) == 1 and kinds("tree")[0]["shown"] == 0, "the host's undo took its tree away")
check(len(kinds("flowers")) == 1 and kinds("flowers")[0]["shown"] == kinds("flowers")[0]["plants"], "the joiner's undo then redo left its flowers standing")
check(len(g["paths"]) == 1 and len(kinds("grass")) == 1, "the host's path and the grass painted across it stand")
check(len(g["seeds"]) == 1 and g["ponds"] == 1, f"the joiner's dug pond holds water: {g['ponds']} ponds")
paints = {k: (w["data"].split('"paint": ')[1].split(")")[0] + ")", '"plaster": true' in w["data"], '"on": PackedInt32Array()' not in w["data"]) for k, w in g["walls"].items()}
picked = "PackedInt32Array(0, 0, 0, 0, 2, 0)"
check(all((p == picked) == (plaster or on) for p, plaster, on in paints.values()), f"the joiner's plaster on the host's wall, and on the storey it built after, is every machine's; no other wall changes: {paints}")
meadow = g["groups"]["0"]
check(sorted(meadow["species"])[-1:] == [2] and sum(meadow["species"]) == 2, f"the joiner's style tool turned one meadow tree a poplar on every machine: {[k for k in meadow['species'] if k]}")
check(meadow["plants"] - meadow["shown"] > 10, f"the joiner's deletes took a spawned tree, a bush and mown meadow: {meadow['plants'] - meadow['shown']} of the meadow's plants gone")
check(len(g["grounds"]) == 1 and any("lanterns\": PackedVector3Array(3" in w["data"] for w in g["walls"].values()), "the host's stone ground and lantern stand")
easels = list(g["easels"].values())
check(len(easels) == 1 and easels[0]["strokes"] == 2, f"the host's easel holds the joiner's watercolour stroke and the host's oil one: {easels}")
home = json.load(open(f"{out}/home.json"))
home.pop("avatars")
home.pop("worn")
check(len(home["walls"]) == 1 and list(home["groups"]) == ["0"] and not home["paths"] and home["ponds"] == 0 and home["season"] == 1, "the visitor's own garden, one wall, is back when it goes home")
check(seen == {n: len(names) - 1 for n in names}, f"each player sees all other avatars: {seen}")
for n in names:
    expected = sorted(h for peer, h in own.items() if peer != n)
    check(worn[n] == expected, f"{n} sees every other custom avatar: {worn[n]}")
sys.exit(0 if ok else 1)
