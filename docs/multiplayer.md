# Co-op

Directive (verbatim): "It's probably a multiplayer game. What do you think we can do about that"

Directive (verbatim): "Maybe we uh, target VR avatars and then we... We build the game with some very simple ones and then... That gives us the option to... Let users load their own later"

Several people build one garden together and see each other's heads and hands. The first
increment works on a local network (a Steam Frame and a Quest 2 in one house). Play over the
internet comes next and uses the same protocol.

## The garden is a command log

Every finished edit is a **build command**: a small dictionary of plain values. `wall`
carries the walls a stroke built, `unwall` removes walls, and `reshape` changes a wall's
height, top, arches, fittings, ruins or roof. `path` and `unpath` lay and lift paths, `plant` grows a
paint stroke or a tree, `show` hides or restores plants, and `heights` sets an area of
ground (a dug pond's seed, the point its water fills from, rides on the same command), and
`palette` sets one material's swatch or the season. `wipe` takes the garden back to bare meadow, and
`garden` (only ever the undo of a wipe) rebuilds it from the snapshot the wipe took. `World` (game/src/world.gd) applies them, and nothing else changes the garden.
The time of day is each player's own view of it: dragging the sun sends nothing.
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
  same ones. A command runs from tens of bytes to a few kilobytes and is sent once per
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
8 m patch of the meadow's own plants, or one material's colour. A step is still yours if every other player's last
change to everything it touched came before it. A wipe touches everything: anyone's later change stands on it, it stands on
every earlier step of the others, and a wipe dropped from your undo takes your older steps with it, since
the garden they changed is gone. Only the host may wipe its garden. The host does not track one kind of
dependency: things standing on each other. If you undo a ground edit, a wall a friend
later built on that patch settles onto the restored ground.

## Avatars

Players appear as **VRM 1.0** avatars. VRM is the open VR avatar standard: a glTF 2.0
file with a humanoid bone map. Godot 4.5 reads the glTF. Nestcombe's `Vrm` extension
reads the VRM humanoid bones and eye offset, which is all a head-and-hands avatar needs.
For the rest of the format (MToon materials, spring bones, expressions), the V-Sekai
[godot-vrm](https://github.com/V-Sekai/godot-vrm) addon is maintained and supports
Godot 4.0 and later. It plugs into the same `GLTFDocument` path if user avatars need it.

- **Built-in avatars** (`game/avatars/*.vrm`) are generated by `scripts/avatars.gd` in
  Nestcombe's look: a pebble, an acorn and a hooded figure. Each is a floating head with
  eyes, two mittens and a small smock, a few hundred triangles and six draw calls.
  Surfaces whose material is named `tint…` take the player's colour. Each file is read
  once at start; every avatar of it shares its meshes.
- **Pose.** The head follows the tracked headset and the mittens follow the
  controllers. The body hangs below the head and turns with it but stays upright. This
  is procedural placement of tracked parts only; there is no invented animation. A
  future skinned user avatar will play human-made animation only.
- **User avatars later.** `Avatar.open(path, tint)` takes any VRM. Loading a player's
  own file and sending it to the others is the next avatar step and is not built yet.

Each player's avatar and colour go to every other player once, reliably. After that a
pose packet carries three transforms, sent unreliable and ordered at 30 Hz and smoothed
on arrival. Transforms that are not finite are dropped.

## Finding each other

Every host announces itself on the local network once a second: a UDP broadcast on ports
7469–7472 carrying its game port (7480 and up), avatar and colour. Pick the **visit**
tool from either hand's ring; its model is a little figure. A small figure of each nearby
garden's host then stands in an arc in front of you, in their avatar and colour. Point at
one and pull the trigger to join their garden. While you visit, a small cairn of three
stones stands among them; pick it to go home. There is no text, no menu and no address to
type.

`--join ADDRESS[:PORT]` and `--avatar N` are launch arguments for scripts and tests.

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

`scripts/coop.sh OUT` plays three headless instances on one machine:
1. One hosts.
2. A second finds it by its beacon, on loopback, and joins through the visit tool.
3. Both build: walls, a tree, flowers, a path, raised ground, a pond and grass across the path.
   Each deletes and undoes, including an undo that has to skip a step the other built on.
4. A third joins late.
5. The visitor goes home.

The script fails unless all three gardens match: every wall's data and laid stones,
every plant group's standing plants, the paths, the ground and the ponds. It also checks the
expected outcome, that each player sees the others' avatars, and that the visitor's own
garden comes back. `tests/test_world.gd` covers the undo rule, the schema and the
snapshot round trip.

## Budget

Networking adds no per-frame work beyond reading sockets and sending one pose packet
every other frame. Each remote player adds about seven small draw calls and a few hundred
triangles. Frame times with 1, 2 and 4 players in the stress scene are under
"Measurements".

## Increments

1. Local network co-op: command log, per-player undo, late join, avatars, discovery. (Done.)
2. Over the internet: a relay or hole punching, and a way to invite a friend.
3. A player's own VRM avatar, sent to the others when they join.

## Measurements

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
