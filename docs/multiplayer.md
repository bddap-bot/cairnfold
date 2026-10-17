# Co-op

Directive (verbatim): "It's probably a multiplayer game. What do you think we can do about that"

Directive (verbatim): "Maybe we uh, target VR avatars and then we... We build the game with some very simple ones and then... That gives us the option to... Let users load their own later"

Several people build one garden together and see each other's heads and hands. The first
increment works on a local network (a Steam Frame and a Quest 2 in one house). Play over the
internet comes next and uses the same protocol.

## The garden is a command log

Every finished edit is a **build command**: a small dictionary of plain values. `wall`
carries the walls a stroke built, `unwall` removes walls, and `reshape` changes a wall's
height, top, gable ends, arches, fittings, ruins, roof or paint (its colours). `path` and `unpath` lay and lift paths, `plant` grows a
paint stroke or a tree, `show` hides or restores plants, and `heights` sets an area of
ground (a dug pond's seed, the point its water fills from, rides on the same command), and
`season` sets the garden's season. `wipe` takes the garden back to bare meadow, and
`garden` (only ever the undo of a wipe) rebuilds it from the snapshot the wipe took. `batch` carries several takings (`unwall`, `reshape`, `unpath`,
`unground`, `show`) of different things, applied in order as one step: a delete stroke across many things is
one undo, and its inverse is the batch of their inverses. `World` (game/src/world.gd) applies them, and nothing else changes the garden.
The time of day is each player's own view of it: turning the sky sends nothing.
Every machine applies the same commands in the same order, so every copy of the garden
comes out the same.

- **The host orders the commands.** A tool sends its command to the host
  (`World.submit`). The host checks it, stamps it with its author and the next sequence
  number, applies it and broadcasts it. Everyone else applies what the host broadcasts,
  in that order. The host assigns every id. A stroke's walls take ids from the command's
  sequence number, so one stroke that builds several walls is still one step.
- **Live feedback stays on your own machine.** While you draw a wall, pull its height,
  paint, lay a path or raise the ground, only your machine shows it. That **ghost** stays
  until the command comes back, the host turns it down, or the garden is swapped. Then
  `World` calls the `done` the tool submitted with, and the ghost gives way to the real
  thing. Painted ghosts grow in pools of their own, so the garden's plant pools fill in
  command order on every machine.
- **Commands carry results, not gestures.** A wall carries its points, height, arches,
  top, roof and the ids of the builds it stands on. A ground edit carries the heights it leaves. A paint stroke carries its
  random seed and its brush dabs, from which every machine grows the same plants, and it
  records which plants fell on a path when it grew, so a garden rebuilt later grows the
  same ones. Its plants grow over the frames after it applies, a share a frame, so a
  stroke of thousands costs no frame; a command on plants or on the ground's heights
  grows them whole first, so every machine still fills its pools in command order.
  A command runs from tens of bytes to a few kilobytes and is sent once per
  gesture, so networking costs no frame time.
- **Derived things are derived everywhere.** How builds meet (what of one lies inside another, how
  high a storey stands on the house under it) is worked out from the walls standing on every machine.
  The arches a path opens in a wall are not
  stored. Each machine works them out from the walls and paths standing, taking paths in
  id order, whenever either changes. They therefore come and go with the path, in any
  order and on every machine.
- **One schema checks every command.** `Commands.clean` keeps only the fields an op
  defines and checks each field's type and range against what a tool can make. That
  covers counts, finite values, staying on the map, and edits of things that still
  exist. Anything else becomes nothing. The host runs it on every proposal, and every
  machine runs it on everything the host sends. The host also limits each player to 20
  commands a second, in bursts of up to 60. A device on the network can therefore not
  wedge or corrupt anyone's garden.
- **Applying returns the inverse.** `World._apply` returns the command that would take
  its command back: `reshape height 2.6` for `reshape height 4.2`, `unwall` for `wall`,
  the old heights for `heights`. The host keeps these for undo; nobody else needs them.
- **Single player is the same game with nobody connected.** Every instance starts as a
  host with no one else on it and runs the one code path above; its broadcasts reach
  nobody. There is no single-player branch.

### Late joiners

The garden is data (`World.state`), so the host can describe it as a short list of
commands that rebuild it from an empty meadow:
- the ground, if it was ever shaped, and the seeds ponds fill from
- each path and wall
- each plant group, in the order it was planted, with the plants since hidden
- each material whose swatch, or the season, was changed

A joiner clears its own garden, applies that snapshot, and then applies the log from the
snapshot's sequence number on. ENet delivers reliable messages in order, so nothing
broadcast after the snapshot can overtake it. While you visit, your own garden waits in
memory as a snapshot and comes back when you leave or the host goes away. Undo history
stays with the garden it belongs to: visiting starts fresh, and so does coming home.

The same snapshot keeps your garden between sessions: the host writes it to disk after every frame in which
a command changed its garden, and loads it at start. A player visiting writes nothing, so a visit never
overwrites their own garden.

## Undo and redo: your own steps, never someone else's

The host keeps an undo stack and a redo stack for each player. Undo takes back **your
most recent step that nobody else has touched since**. If another player has since built
on your latest step, the step is dropped and the undo moves on to your next one. That
covers raising the wall you drew, removing the tree you planted, or reshaping ground in
the same patch. Redo puts back your most recent undone step on the same condition; a
redo of a step someone has since built on does nothing.

The other options and why not:
- **One shared stack.** Your undo would take back whatever a friend did last, possibly
  across the garden, which feels like the game breaking.
- **Undo your steps regardless.** Undoing your wall after a friend arched it would throw
  their work away.

"Your own, unless built on" keeps every tap about what you made, and it never destroys
another player's later work. A player alone sees plain single-player history, since
nobody else ever builds on their steps.

The host tracks, for each thing in the garden, which player last changed it and at which
sequence number. A thing is a wall, a path, a plant group, an 8 m patch of ground, an
8 m patch of the meadow's own plants, or the season. A step is still yours if every other player's last
change to everything it touched came before it. A wipe touches everything: anyone's later change stands on it, it stands on
every earlier step of the others, and a wipe dropped from your undo takes your older steps with it, since
the garden they changed is gone. Only the host may wipe its garden. The host does not track one kind of
dependency: things standing on each other. If you undo a ground edit, a wall a friend
later built on that patch settles onto the restored ground.

## Avatars

Directive (verbatim): "Yes please" (the answer to building loading your own VRM).

Players appear as **VRM** avatars. VRM is the open VR avatar standard: a glTF 2.0
file with a humanoid bone map. Godot 4.5 reads the glTF. Nestcombe's `Vrm` extension
reads the humanoid bones, the eye offset and which way the model faces, from VRM 1.0
(`VRMC_vrm`) and from VRM 0.x (`VRM`, which faces -Z and keeps its offset in Unity's
axes). That is all a head-and-hands avatar needs.

- **Built-in avatars** (`game/avatars/*.vrm`) are generated by `scripts/avatars.gd` in
  Nestcombe's look: a pebble, an acorn and a hooded figure. Each is a floating head with
  eyes, two mittens and a small smock, a few hundred triangles and six draw calls.
  Surfaces whose material is named `tint…` take the player's colour. Each file is read
  once at start; every avatar of it shares its meshes.
- **Pose.** The head follows the tracked headset and the hands follow the
  controllers, pointing where the controller points with the palm inward. The body
  hangs from the head bone in its rest pose and turns with the head but stays upright.
  Each arm is the one bend of its two bones that joins the shoulder to the tracked
  hand, its elbow down, out and a little back; a hand beyond reach leaves the arm
  straight toward it. This places tracked parts only; there is no invented
  animation. Avatars play human-made animation only, and none is played yet.
  Avatars keep their own size, so a small one's feet stand off the ground under a
  tall player's head.
- **Your own avatar.** The newest `.vrm` in the game's `avatars` folder is yours
  (`~/.local/share/godot/app_userdata/Nestcombe/avatars` on Linux and the Frame,
  `%APPDATA%\Godot\app_userdata\Nestcombe\avatars` on Windows). The game creates
  the folder and looks at it every two seconds, so dropping a file in changes your
  avatar within a few seconds, mid-session included; removing it brings the built-in
  one back. There is nothing to pick in the headset and no text: the folder is the
  choice, and the Steam Workshop is the later way to share and pick avatars from
  inside the game. On a Quest the folder is
  `/sdcard/Android/data/io.github.bddapbot.nestcombe/files/avatars`, the one place
  there that both the game and `adb push` or a file manager reach.
- **Seeing yourself.** Your own avatar is opened by the same `Avatar` path as everyone
  else's and posed from your head and hands, on a render layer (`Rig.SELF_LAYER`) only
  the camera's lens sees: it is in your photos and on the camera's screen, never in your
  own view. It is drawn only while you hold a camera, and the hand holding it folds into
  its wrist there, so the camera stands in for it and no finger crosses the lens.
- **Sending it.** The file goes once, reliably, to every player you meet, and again
  whenever it changes. It travels on its own ENet channel, so build commands never
  wait behind it. A receiver reads it on a worker thread, so a file that takes a
  second or two to read costs no frame, and shows your built-in avatar until then.
  Players wearing the same file share one read. A file is dropped if it is over the
  size limit, is not a humanoid VRM, or is still too heavy after cutting.
- **Limits.** `Avatar.read` cuts every file the same way, the player's own before
  it is sent, so all players see the same avatar: at most 24 MB, surfaces merged per
  material within a mesh, expressions (blend shapes) and animations dropped,
  triangles simplified to at most 20,000, at most 20 surfaces (draw calls), and
  textures shrunk to 1024 px with mipmaps. Every surface also gets levels of detail,
  which the renderer picks by size on screen, so a player across the garden costs a
  fraction of one up close. The quality ladder already changes how much of the scene
  draws; avatars need no setting of their own. A VRoid avatar (34,000 triangles,
  65 primitives, 17 materials, 16 MB) reads as 15,000 triangles in 17 surfaces.
- **Materials.** Godot's glTF reader reads each VRM material's glTF base: its
  colour, texture and alpha. Unlit (toon) surfaces are lit like the rest of the
  garden, so an avatar darkens at dusk instead of glowing.

The V-Sekai [godot-vrm](https://github.com/V-Sekai/godot-vrm) addon would add MToon,
spring bones and expressions. Nestcombe does not use it. MToon's outline pass draws every
outlined surface twice, which would double an avatar's draw calls against the limit above,
and its toon shading would stand apart from the garden's light. Spring bones run physics on
every avatar every frame. The addon is also a large editor import plugin, and the game needs
only the ~60 lines of humanoid reading it already has.

Each player's avatar and colour go to every other player once, reliably. After that a
pose packet carries three transforms, sent unreliable and ordered at 30 Hz and smoothed
on arrival. Transforms that are not finite are dropped.

## Finding each other

Every host announces itself on the local network once a second: a UDP broadcast on ports
7469–7472 carrying its game port (7480 and up), a random key, its avatar and its colour.
Pick the **visit** tool from either hand's ring; its model is a little figure. A small
figure of each nearby garden's host then stands in an arc in front of you, in their avatar
and colour, with their name under it. Point at one and pull the trigger to join their
garden. While you visit, a small cairn of three stones stands among them; pick it to go
home. The names are the game's one text (docs/design.md, "Requirements"); there is no
menu and no address to type.

Only gardens of a build with the same networked methods can be joined. Godot numbers a
node's RPCs by name, so a build with one more or one fewer calls the wrong methods on the
other: a visitor's digs, ponds and plants never land, and its strokes show and then vanish.
The beacon carries a fingerprint of `World`'s and `Session`'s RPCs (`Session.protocol`).
A garden whose beacon carries another (or the constant 1 of builds before the fingerprint)
still stands in the arc, with a small X over it, and pointing at it picks nothing. Builds
from one revision always match. Builds before the fingerprint drop every beacon but their
own constant, so they list no newer garden at all.

### Names

The beacon goes to anyone on the network without the player doing anything, so it carries
nothing that says who they are. A name reaches others only by a way the player chose:

- **With Steam,** a host's Steam name and picture reach only their Steam friends, through
  Steam itself. The host puts its beacon's random key in its Steam rich presence; a friend's
  game, seeing that key in a beacon, shows the friend's Steam picture and Steam name under
  the figure. Who sees you playing is what you set in Steam. Two games on one Steam account
  on one machine share one rich presence, so only the later one is named; on two machines
  each reads only its own, so neither is. Anyone on the network can copy a
  friend's key into their own beacon, so when two gardens announce one key neither is named.
- **Without Steam,** your own figure stands nearer, to your left, under a name the game
  offers, faint while only you can see it. Pick it and the name joins your beacon; pick it
  again for another. The game keeps the name you picked for later starts. A host who never
  picked one stands unnamed.

`Persona` (game/src/persona.gd) holds all of this. Steam is optional: only a Steam package
(`scripts/package.sh TARGET OUT steam`, or the Frame's `scripts/android.sh lepton OUT steam`) carries the GodotSteam extension and Valve's
`steam_api` library, and the game starts Steam only when Steam launched it (`SteamAppId`
in its environment) or a script names an app with `--steam-app ID`. Every other build and
launch plays without Steam on the same code path.

`--join ADDRESS[:PORT]`, `--avatar N`, `--name NAME` (a picked name) and `--steam-app ID`
are launch arguments for scripts and tests. `demo/picker.json` captures the picker; Valve's
test app 480 stands in for this game's app in development.

Only a game a player launched beacons on the network. One started with `--script`,
`--join` or `--port`, or built inside a test, sends its beacon to this machine's loopback address only
and listens there only, so a player never sees a scripted or test instance in the arc.
Scripts can select a private four-port discovery range with `--beacon-port BASE`.
`coop.sh` reserves a separate range for each run, so unrelated headless instances
cannot take its listeners. Player launches still use ports 7469–7472.
Scripts on one machine still find each other by beacon, and scripts that play with another
machine (the bench's players) connect with `--join`. `tests/test_beacon.gd` fails if a
scripted or test instance beacons past loopback.

## Proof

`scripts/coop.sh OUT [N]` plays N headless instances on one machine (four by default,
two through eight supported):
1. One hosts; a second discovers its beacon and joins through the visit tool wearing
   a custom VRM 1.0 avatar.
2. Both build walls, houses, plants, paths, ground and a pond, and exercise deletion,
   undo, redo and edits to each other's builds.
3. The pair samples ten seconds of settled co-op before any late joiner starts.
4. N-2 players join late with custom VRM 0.x/1.0 files. Each builds and undoes its own
   wall, in command order. Every player waits for all avatars to load before another
   ten-second sample of the same settled garden.
5. Every player records its garden and all remote avatar hashes. Nobody leaves until
   every view and cost sample exists; the visitor then goes home and records its own
   garden. A script error, a player losing the garden it visits, a failed check, or a
   stretch in which no player takes a step while together they spend `QUIET_CPU`
   CPU-seconds fails the run. There are no retries and no wall-clock limit: a loaded
   machine only makes the run slower.

The JSON gestures in `demo/coop-host.json` and `demo/coop-join.json` supply the initial
building sequence through their first digest. `scripts/coop.py` supplies the N-player
barriers and teardown. `tests/test_coop.py` checks the choreography. The harness reserves
its discovery range with a socket outside the four listener ports, leaving all four
available to players.

All N gardens must match the expected build, including laid stones, plants, paths,
ground and ponds. Every player must see N-1 avatars and the exact multiset of other
players' custom-file hashes (N-1 on the host, N-2 on each visitor). The returning
visitor must recover its own garden. `tests/test_world.gd` covers the undo rule, the
schema and the snapshot round trip. `tests/test_avatar.gd` reads the public sample avatars in
`tests/avatars/` (VRM 1.0 and 0.x) and checks the limits, the pose, the arms' reach, and that
one model in both versions stands alike.

`scripts/flat.sh OUT` renders a host and a flat-screen player (`--flat`) on one machine:
the flat-screen player hears the host's beacon, takes up the visit tool with its own
controls, picks the host's figure, walks up to the host and takes a photo of it into
`OUT/photos`; the host's captures show it standing in the garden. `tests/test_flat.gd`
covers its controls, its hands' pose and that none of its controls sends an edit.

## Budget

Each remote player costs one avatar pose a frame, as their avatar follows their latest pose
packet, and on the host the relaying of their packets; networking otherwise adds only reading
sockets and sending one pose packet every other frame. Each remote player adds about seven
small draw calls and a few hundred triangles. Frame times with 1, 2 and 4 players in the stress scene are under
"Measurements".

## Increments

1. Local network co-op: command log, per-player undo, late join, avatars, discovery. (Done.)
2. Over the internet: a relay or hole punching, and a way to invite a friend.
3. A player's own VRM avatar, sent to the others when they join. (Done.)

## Measurements

### Headless co-op CPU and traffic

`coop.sh` writes `costs.json`, raw `*-cost.json` ENet samples and
`process-cpu.json` process-counter samples alongside the gardens and logs. Each
phase lasts ten wall-clock seconds after all peers have loaded the other avatars
and the garden has settled. The two-player phase precedes the N-player phase in
the same host and visitor processes; the late joiners build and undo before the
second phase, leaving the same garden. These samples measure idle pose streaming,
not initial avatar transfer or peak building traffic.

Traffic is ENet's sent/received byte counters divided by measured elapsed time,
per process; it excludes discovery and UDP/IP headers. Clients communicate through
the host, which also relays traffic between visitors, so its load grows faster than
a visitor's. CPU is the delta of Linux `/proc/PID/stat` user + system CPU ticks over
the sample window, in milliseconds per second (1000 is one fully occupied core).
The harness polls at 100 ms and uses the first and last samples inside each window.
Godot's elapsed process/physics milliseconds per frame are also retained, but those
include scheduler delays and are not the CPU measurement. Runs share a busy desktop;
they establish neither headset frame rate nor a device CPU budget.

Where a player's CPU goes, from main-thread user instructions per frame (`perf stat`, which a
busy machine does not inflate) with parts of the work removed in turn: at the host, of about
0.32 million instructions per frame per added player, the avatar follow is about 0.15 million
(one `Avatar.pose`, about 150 thousand instructions, most of it GDScript), relaying and handling
pose packets about 0.1 million, and the remaining 0.09 million is within run-to-run noise.
System time is 3–6% of the process's CPU; the frame loop sleeps between frames rather than
polling.


`NESTCOMBE_PLAYERS=N scripts/bench.sh OUT ...` plays the stress scene with N-1 other
players, headless on the benching machine, who join the measured instance and stand in
view streaming their heads and hands. The measured instance waits for all of them before
its first phase.

On the Steam Frame, with the bench's earlier flat-window mode (both eyes' pixels in one
window, about a third of the headset's XR cost; see "Frame measurements" in
[design.md](design.md)), GPU milliseconds per frame:

| Phase | 1 player | 2 players | 4 players |
| --- | --- | --- | --- |
| Meadow, from the air | 3.54 | 3.53 | 3.59 |
| Meadow, standing | 3.51 | 3.61 | 3.63 |
| Every flora pool full, standing | 6.35 | 6.49 | 6.46 |
| Walls on a 15 m disc, from the air | 7.03 | 7.06 | 7.02 |
| Walls on a 25 m disc, from the air | 13.41 | 13.25 | 13.19 |
| Walls on a 25 m disc, standing | 12.83 | 14.41 | 12.58 |
| Village, from the air | 7.53 | 7.53 | 7.56 |
| Village, standing | 8.41 | 8.85 | 9.10 |
| Hills, standing | 12.86 | 13.94 | 14.03 |

Each other player adds about 7 draw calls, and an avatar casts no shadow. From the air,
other players cost at most 0.4 ms. Standing phases cost up to 1.2 ms more with players,
for example hills 12.86, 13.94 and 14.03 ms. That figure is an upper bound. There is one
run per player count, and the scene itself differs between runs by up to 8% in
primitives (the village from the ground: 2.73 M, 2.96 M and 2.78 M), so the avatars'
own cost is not separated from the scene's differences.

On the Quest 2 (`bench.sh OUT --android APK`, in the headset with its clocks held at
level 4), the game's GPU milliseconds per frame, taken from the runtime's own per-frame
reading, the median of three runs at each player count:

| Phase | 1 player | 4 players |
| --- | --- | --- |
| Meadow, from the air | 32.37 | 32.92 |
| Meadow, standing | 22.73 | 22.96 |
| Every flora pool full, standing | 31.92 | 31.17 |
| Walls on a 25 m disc, from the air | 50.77 | 50.91 |
| Village, from the air | 73.59 | 77.02 |
| Village, standing | 40.76 | 40.45 |
| Hills, standing | 52.75 | 50.85 |
| The camera held up, standing | 57.60 | 57.49 |

Three other players add a median of 21 draw calls a phase, about 7 each. The primitives of a phase
agree between runs of one player count to within 15% (the villages) and mostly to a few
percent. Over the 38 phases the median change with 3 other players is -0.13 ms, and single
phases move between -7.7 and +3.4 ms. That spread is the headset's, not the players': the
same phase at the same clocks can differ by more between two runs of one player count. In
the first run of each count the phases without walls or houses read 13 to 32 ms; in the
other runs they read 23 to 43 ms.

Other players do not make a photo cost more. Holding the camera up, its screen drawing the
lens's view, costs the same with and without them: 57.6 and 57.5 ms. The photo phase used to take five photos back to back. The runtime reads GPU time once a
second, so the photos fell two, three or none to a reading, and on one build the phase read
71.2, 71.8 and 71.8 ms at 1 player and 57.1, 48.7 and 72.2 ms at 4. It now takes a photo a
second, and every reading in it holds one. Three runs read 62.4 and 54.0 ms at 1 player
and 52.4 ms at 4.

Earlier runs disagreed by about twice in draw calls and primitives in 13 of 34 phases.
Each phase ended with a view capture, which on a headset renders the view again through
the photo viewport. Whichever second caught that frame doubled the phase's draw calls and
primitives. The captures now stand outside the phases.

Every phase is over the 12.5 ms budget in these runs, the bare meadow included, so the
budget verdict belongs to the stress scene and the headset's state. Co-op costs a fraction
of a millisecond per player against it.

The Quest build must hold the network permission. Without it, every socket the game
opens fails, it hosts nothing, and no one can join. With it, a Quest and a desktop find
each other by beacon within seconds, both ways. `scripts/android.sh` refuses an APK whose manifest
lacks it.

### A player's own avatar

`NESTCOMBE_GUEST_AVATAR=FILE.vrm` dresses the other players in a VRM, and
`NESTCOMBE_SCENE=demo/avatars.json` looks at them three ways, three times over: close
(one of them 3.6 m away, the others behind), across the meadow (all three, 6 to 18 m)
and away (none in view). The VRM is the CC0 VRoid sample AvatarSample_D (VRM 1.0, 16.6 MB),
which reads as 15,000 triangles in 17 surfaces.

On the Quest 2, `NESTCOMBE_PLAYERS=4 bench.sh OUT --android APK`, the game's GPU
milliseconds per frame, median of each phase. "Arrived" counts the other players whose
file the headset read and wore (the game logs `session: player N wears`). The close view
reads about 22.6 ms whenever the near player's file did not arrive:

| Other players wear | Arrived | Limits | Close | Across | Away |
| --- | --- | --- | --- | --- | --- |
| built-in | | | 22.81 | 24.20 | 23.43 |
| built-in | | | 22.82 | 24.22 | 23.42 |
| the VRM | 2 | 20,000 triangles, 1024 px | 25.75 | 27.45 | 23.68 |
| the VRM | 2 | 20,000 triangles, 1024 px | 25.85 | 27.46 | 23.45 |
| the VRM | 2 | 20,000 triangles, 1024 px | 25.99 | 26.83 | 23.82 |
| the VRM | 2 | 20,000 triangles, 1024 px | 22.55 | 26.22 | 23.50 |
| the VRM | 1 | 20,000 triangles, 1024 px | 25.90 | 26.55 | 23.51 |
| the VRM | 2 | 5,000 triangles, 512 px | 22.53 | 26.09 | 23.46 |
| the VRM | 2 | 5,000 triangles, 512 px | 22.56 | 26.08 | 23.58 |
| the VRM | 1 | 5,000 triangles, 512 px, alpha cut out | 22.62 | 26.04 | 23.53 |
| the VRM | 1 | 5,000 triangles, 512 px, alpha cut out | 25.46 | 26.31 | 23.45 |

On the Steam Frame, in its XR session unworn, the same scene and three other players
from another machine (the measured instance launched with `--port 7480` so they can join),
the game's GPU milliseconds per frame, two runs each. All three files arrived every time:

| Other players wear | Close | Across | Away |
| --- | --- | --- | --- |
| built-in | 6.75 | 7.22 | 6.91 |
| built-in | 6.75 | 7.20 | 6.90 |
| the VRM | 7.67 | 7.96 | 6.90 |
| the VRM | 7.69 | 7.97 | 6.91 |

Three VRMs cost the Frame 0.9 ms close and 0.75 ms across the meadow, and nothing out of
view: under a millisecond for all three, well inside its frame.

On the Quest 2, the VRM in view costs the headset 2 to 3 ms a frame: one at 3.6 m adds 2.6 to 3.2 ms,
and one or two across the meadow add 1.8 to 3.2 ms. Out of view it costs nothing (away:
23.4 to 23.8 ms against 23.4). The cost does not follow the triangles, the texture size or
alpha blending: cutting to 5,000 triangles and 512 px, and alpha blending to a cut-out, leave
it where it was, and one VRM costs about what two do. So lowering these limits would not buy
the frame back; the limits stay at 20,000 triangles, 20 surfaces and 1024 px until what does
cost is found. Against a 12.5 ms budget, 2 to 3 ms for the first VRM in view is too much.

Not every file arrives. With the Quest 2 hosting over Wi-Fi, one or two of the three
other players' files arrived, within about 30 s, and the last never did, even after four
minutes. The Frame and one machine got all three within seconds. Until that is fixed, a player's
own avatar can stay unseen by some of the others.
