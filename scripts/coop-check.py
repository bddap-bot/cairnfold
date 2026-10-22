import hashlib, json, math, re, sys
out = sys.argv[1]
names = ["host", "join"] + [f"late-{i}" for i in range(2, int(sys.argv[3]))]
d = {n: json.load(open(f"{out}/{n}-final.json")) for n in names}
seen = {n: g.pop("avatars") for n, g in d.items()}
worn = {n: sorted(g.pop("worn")) for n, g in d.items()}
for g in d.values():
    g.pop("handfuls")
    g.pop("frenzy")
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
check(g["seq"] == 35 + 2 * (len(names) - 2), "every late joiner built and undid its own wall")
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
check(len(houses) == 3 and all(len(w["floors"]) == 1 for w in houses), f"every house, storey and wing is floored alike on every machine: {[w['floors'] for w in houses]}")
storey = next(w for w in houses if '"on": PackedInt32Array()' not in w["data"])
check(storey["floors"][0] > min(w["floors"][0] for w in houses if w is not storey) + 2.0, f"the joiner's storey is floored on the host's house's top: {storey['floors']}")
kinds = lambda k: [v for v in g["groups"].values() if v["kind"] == k]
check(len(kinds("tree")) == 1 and kinds("tree")[0]["shown"] == 0, "the host's undo took its tree away")
check(len(kinds("bush")) == 1 and kinds("bush")[0]["shown"] == 1, "the joiner's bush stands")
check(len(kinds("flowers")) == 1 and kinds("flowers")[0]["shown"] == kinds("flowers")[0]["plants"], "the joiner's undo then redo left its flowers standing")
check(len(g["paths"]) == 1 and len(kinds("grass")) == 1, "the host's path and the grass painted across it stand")
check(len(g["pond_levels"]) == 1 and g["ponds"] == 1, f"the joiner's pond holds water in the hollow it pressed: {g['pond_levels']}")
paints = {k: (w["data"].split('"paint": ')[1].split(")")[0] + ")", '"plaster": true' in w["data"], '"on": PackedInt32Array()' not in w["data"]) for k, w in g["walls"].items()}
picked = "PackedInt32Array(0, 0, 0, 0, 2, 0, 0)"
check(all((p == picked) == (plaster or on) for p, plaster, on in paints.values()), f"the joiner's plaster on the host's wall, and on the storey it built after, is every machine's; no other wall changes: {paints}")
meadow = g["groups"]["0"]
check(sorted(meadow["species"])[-1:] == [2] and sum(meadow["species"]) == 2, f"the joiner's style tool turned one meadow tree a poplar on every machine: {[k for k in meadow['species'] if k]}")
grown = [(k, round(x, 2)) for k, x in zip(meadow["species"], meadow["scale"]) if x != 1.0]
check(len(grown) == 1 and grown[0][0] == 2 and grown[0][1] > 1.3, f"the joiner's grip grew that poplar on every machine: {grown}")
check(meadow["plants"] - meadow["shown"] > 10, f"the joiner's deletes took a spawned tree, a bush and mown meadow: {meadow['plants'] - meadow['shown']} of the meadow's plants gone")
check(len(g["grounds"]) == 1 and any("lanterns\": PackedVector3Array(3" in w["data"] for w in g["walls"].values()), "the host's stone ground and lantern stand")
easels = list(g["easels"].values())
check(len(easels) == 1 and easels[0]["strokes"] == 2, f"the host's easel holds the joiner's watercolour stroke and the host's oil one: {easels}")
for shape, reach in [("peak", lambda h: h[1] > 450), ("pit", lambda h: h[0] < -450)]:
    seen_shape = {n: json.load(open(f"{out}/{n}-{shape}.json")) for n in names}
    for v in seen_shape.values():
        for k in ("avatars", "worn", "handfuls", "frenzy"):
            v.pop(k)
    check(all(v == seen_shape["host"] for v in seen_shape.values()), f"every peer shows the joiner's {shape} the same")
    check(reach(seen_shape["host"]["heights"]), f"the joiner's one stroke {shape} reaches past 450 m: {seen_shape['host']['heights']}")
painted = {n: json.load(open(f"{out}/{n}-easel.json")) for n in names}
for v in painted.values():
    for k in ("avatars", "worn", "handfuls", "frenzy"):
        v.pop(k)
check(all(v == painted["host"] for v in painted.values()), "every peer shows the easel alike after the host and the joiner took charcoal, switched, set down and tore there together")
check([e["strokes"] for e in painted["host"]["easels"].values()] == [2], f"the joiner's sheet tore off both first strokes; its charcoal stroke and the host's after stand: {painted['host']['easels']}")
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
sys.exit(0 if ok else 1)
