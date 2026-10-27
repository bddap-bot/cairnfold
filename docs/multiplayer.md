# Co-op

Directive (verbatim): "It's probably a multiplayer game. What do you think we can do about that"

Directive (verbatim): "Maybe we uh, target VR avatars and then we... We build the game with some very simple ones and then... That gives us the option to... Let users load their own later"

Several people build one garden together and see each other's heads and hands. The first
increment works on a local network (a Steam Frame and a Quest 2 in one house). Play over the
internet comes next and uses the same protocol.

## The garden is a command log

Every finished edit is a **build command**: a small dictionary of plain values. `wall`
carries the walls a stroke built, `take` removes builds of one table (`of`) by id, with whatever stands on them, and `reshape` changes a build
named by its table in the garden (`of`) and id: a wall's height, top, gable ends, openings, fittings, ruins, roof or paint
(its colours), stairs' railings or paint, or a boulder's scale, paint or stone style. `path` lays a path, `plant` grows a
paint stroke or a tree, `show` hides or restores plants, `heights` sets an area of
ground, `ponds` puts a pond at its level by the grid point it fills from (from a player, one; from the
host, undoing or rebuilding, any, and it may take ponds out, as a `heights` from the host may too), and
`season` sets the garden's season. `easel` sets an easel up (from the host, with the strokes on its canvas and its oil
palette); `paint` adds a stroke to its canvas, or with `palette` to its oil palette's board, `unpaint` takes the last
one off, and `sheet` sets its canvas's strokes whole (a player's only ever a fresh, empty sheet). `boulder` sets down a boulder grown from its seed, at its scale. `wipe` takes the garden back to bare meadow, and
`garden` (only ever the undo of a wipe) rebuilds it from the snapshot the wipe took. `batch` carries several takings (`take`, `reshape`, `show`) of different things, applied in order as one step: a delete stroke across many things is
one undo, and its inverse is the batch of their inverses. `World` (game/src/world.gd) applies them, and nothing else changes the garden.
`sky` sets where the sun stands, sent once the sky tool lets the sky go; it is not an edit, so it
goes on nobody's undo stack, and a wipe leaves it be.
Every machine applies the same commands in the same order, so every copy of the garden
comes out the same. A ponds or ground command whose water fills again over many grid points has that worked
out on another thread first (`Refill`), and the commands after it wait behind it, on every machine alike.

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
- **Commands carry results, not gestures.** A wall carries its points, height, openings,
  top, roof and the ids of the builds it stands on. A ground edit carries the heights it leaves. A paint stroke carries its
  random seed and its brush dabs, from which every machine grows the same plants, and it
  records which plants fell on a path when it grew, so a garden rebuilt later grows the
  same ones. Its plants grow over the frames after it applies, a share a frame, so a
  stroke of thousands costs no frame; a command on plants or on the ground's heights
  grows them whole first, so every machine still fills its pools in command order.
  A command runs from tens of bytes to a few kilobytes and is sent once per
  gesture, so networking costs no frame time.
  Openings are one packed list of `(arc length, click height, door style)`: a low
  click is a door, a higher click a window, and the archway is a door style.
  They share placement, removal, undo and the fitting count limit.
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
  its command back: `reshape height 2.6` for `reshape height 4.2`, `take` for `wall`,
  the old heights for `heights`. The host keeps these for undo; nobody else needs them.
- **Single player is the same game with nobody connected.** Every instance starts as a
  host with no one else on it and runs the one code path above; its broadcasts reach
  nobody. There is no single-player branch.

### Late joiners

The garden is data (`World.state`), so the host can describe it as a short list of
commands that rebuild it from an empty meadow:
- the ground, if it was ever shaped, and each pond's level
- each path and wall
- each plant group, in the order it was planted, with the plants since hidden
- each material whose swatch, or the season, was changed
- the sky, if it was turned

A joiner clears its own garden, applies that snapshot, and then applies the log from the
snapshot's sequence number on. ENet delivers reliable messages in order, so nothing
broadcast after the snapshot can overtake it. While you visit, your own garden waits in
memory as a snapshot and comes back when you leave or the host goes away. Undo history
stays with the garden it belongs to: visiting starts fresh, and so does coming home.
Either swap (`World.swap`) waits in the command queue until the player's view has faded to black, rebuilds there,
and sets the player down on open ground at the spawn point, or the nearest open ground to it, before the view fades
in: nobody sees the jump or the frame the rebuild holds, and nobody arrives inside a build.

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
the garden they changed is gone. Any player may wipe the garden; the host applies it like any other command. The host does not track one kind of
dependency: things standing on each other. If you undo a ground edit, a wall a friend
later built on that patch settles onto the restored ground.

## Avatars

Directive (verbatim): "Yes please" (the answer to building loading your own VRM).

Players appear as **VRM** avatars. VRM is the open VR avatar standard: a glTF 2.0
file with a humanoid bone map. Godot 4.6 reads the glTF. Cairnfold's `Vrm` extension
reads the humanoid bones, the eye offset, how the eyes look (lookAt) and which way the
model faces, from VRM 1.0 (`VRMC_vrm`) and from VRM 0.x (`VRM`, which faces -Z and keeps
its offset in Unity's axes). `VRMC_springBone` and legacy `secondaryAnimation` feed the
same spring runtime, including sphere/capsule colliders, collider groups and centers.

- **Built-in avatars** (`game/avatars/*.vrm`) are generated by `scripts/avatars.gd` in
  Cairnfold's look: a pebble, an acorn and a hooded figure. Each is a floating head with
  eyes on VRM eye bones, two mittens and a small smock, a few hundred triangles, with a three-link cloth tassel beside the head.
  Surfaces whose material is named `tint…` take the player's colour. Each file is read
  once at start; every avatar of it shares its meshes.
- **Pose.** The head follows the tracked headset and the hands follow the
  controllers, pointing where the controller points with the palm inward. The body
  hangs from the head bone in its rest pose and turns with the head but stays upright.
  Each arm is the one bend of its two bones that joins the shoulder to the tracked
  hand, its elbow down, out and a little back; a hand beyond reach leaves the arm
  straight toward it.
- **Size.** An avatar is drawn at its own size and proportions whoever wears it, and the
  wearer is fitted to it. Directive (verbatim): "I think our fitting of x height
  players to y height avatars needs some thought, to prevent avatars from squishing or
  stretching to fit the player. The player's experience should change depending on the
  avatar's height." The world's scale (`XROrigin3D.world_scale`) makes the wearer
  `Rig.fit` times their own size, the avatar's eye height over theirs: head, hands, hand
  joints and the distance between the eyes all scale, so in a short avatar they see from
  its eyes and reach as far as its arms while the garden looms larger, and in a tall one
  the reverse. Standing, their eyes are the avatar's, so its feet meet the floor, and
  others see it at its true size from the poses they already receive. `Stature` measures
  the wearer's own eye height as they play: the height their head is held at or below
  nine tenths of the time, so crouching to plant or a moment on tiptoe leaves it alone,
  and someone seated throughout stands as tall as the avatar; until two seconds are
  measured it is the typical `Rig.EYE`. A new fit, from another avatar or the measure
  settling, comes behind a fade, as a teleport does: the world never grows in view. On a
  flat screen the eyes stand at the avatar's eye height.
- **Gaze.** Every avatar, built-in or a player's own, points its eyes through one path,
  the model's VRM lookAt: by eye bones or by the four look expressions, whichever the
  model declares, each angle mapped and clamped by its range maps. Where the eyes look
  comes from the player: on a headset that tracks eyes (`XR_EXT_eye_gaze_interaction`,
  the Steam Frame) the tracked gaze, held through a blink; on one that does not (the
  Quests) or on a flat screen, ahead of the head, or at the nearest other player's face
  within 30 degrees of ahead and 4 m. The player's own game steadies the look before
  sending it: slowly for small movements, so tracking noise does not jitter the eyes, and
  faster the further it lags, so a glance lands in a few frames instead of drifting. This places tracked parts only. Avatar
  body motion prefers human-made recordings to invented poses. A flat-screen player waves
  with CMU mocap trial 141_16 (see `LICENSE-CMU-WAVE`); its recorded hands travel
  through the same Session poses as tracked VR hands.
  Avatars keep their own size, so a small one's feet stand off the ground under a
  tall player's head.
- **Your own avatars.** Every `.vrm` in the game's `avatars` folder that reads as an
  avatar within the limits is yours to wear
  (`~/.local/share/godot/app_userdata/Cairnfold/avatars` on Linux and the Frame,
  `%APPDATA%\Godot\app_userdata\Cairnfold\avatars` on Windows). The game creates
  the folder and looks at it every two seconds, reading only files that are new or
  changed, one at a time, newest first. Dropping a file in puts it on within a few
  seconds, mid-session included; removing the one worn brings the built-in avatar back.
  The inventory wheel's avatars branch holds the built-in figures and a slot per file,
  in file-name order. On a Quest the folder is
  `/sdcard/Android/data/io.github.bddapbot.cairnfold/files/avatars`, the one place
  there that both the game and `adb push` or a file manager reach.
- **From a Unity package.** `scripts/unity_avatar.gd` imports the avatar in a Unity source
  package (a `.unitypackage`, or an `Assets` folder with its `.meta` files) straight into the
  avatar model (see "Skinned bodies") and writes it as a Godot scene: from `game/`,
  `godot4 --headless --path . --script ../scripts/unity_avatar.gd -- PACKAGE avatar.scn [AVATAR]`.
  No VRM lies between them: VRM cannot carry Unity's shader properties, Animator controllers,
  menus, Contacts or PhysBones settings, which later importer work adds to the same model.
  Named `avatar.vrm`, the output is instead the file a player wears: the avatars folder reads
  only VRM, since a worn file travels to everyone met and a Godot scene can run code, and
  `Avatar.read` reads it back into the same model, with what VRM cannot carry left behind.
  The avatar is the GameObject with a VRChat avatar descriptor (AVATAR names it where a package
  holds several), instantiated as its scene or prefab does: prefab instances, nested ones too,
  expand with their modifications, so the renderers it draws are those active there, with the
  materials and blend shape weights saved on them. Unity names a model's objects by fixed IDs
  from its `.meta` or, since 2019, by the XXH64 of each object's type and path, so the importer
  finds the model objects a scene modifies the same way. The skeleton is the humanoid model's
  the descriptor's Animator names; its `.meta` humanDescription, Unity's Avatar definition, maps
  the humanoid bones, which keep their Unity names. Unity suffixes a transform named like another
  in the model (`head 1`) and Godot's importer does not, so a mapped name the skeleton lacks
  matches the bone without the suffix, under the bone its Unity parent is. A mesh from another
  model binds by bone name; a bone the humanoid's model lacks, and an unskinned mesh of another
  model, become bones where the avatar's Unity transforms place them.

  Every renderer merges into one mesh over one skin, every triangle kept as its author made it,
  its blend shapes kept (those of one name in several renderers one shape) and set to their
  saved weights: a heavy mesh is its author's cost to carry, not the importer's to edit. Shader
  programs do not port;
  each material's saved colour texture, colour, tiling and alpha mode (opaque, cut out at its
  cutoff, or blended) take a cell of one 2048 px atlas. A renderer's material slots follow the
  FBX's materials in their connections' order where the slots match them one for one;
  otherwise a surface takes the slot whose material is named like its own. PhysBones become
  spring chains, one per path from a PhysBone's root to each leaf and on to its endpoint, with
  pull, spring, stiffness, gravity and radius mapped approximately and limits and grabbing
  dropped, and their sphere and capsule colliders spring colliders. The file keeps every chain;
  an avatar simulates its longest within 60 joints, whatever file it came from (each one costs
  the Quest 2's CPU every frame). The descriptor's view position places
  the eyes. The importer prints what it kept and dropped: Animator controllers, expression
  menus, visemes, Contacts, constraints, particles and scripts are not translated. A renderer
  that a constraint places from outside the avatar (a follower, a prop left in the world) is not
  drawn, since without its constraint it would stand glued to the body.
  `tests/test_private_avatars.gd` imports a private corpus of packages that never enters this
  repository, and says it checked nothing where that corpus is absent.
- **Seeing yourself.** The body uses the photo layer, so a camera sees the whole avatar
  while the wearer sees the meshes only its spring joints move, such as the built-ins'
  tassels. Chains stay posed and simulated even without a
  camera. Empty hands can grip a nearby tip; a held implement retains its own controls.
- **Sending it.** The file goes once, reliably, to every player you meet, and again
  whenever it changes. It travels on its own ENet channel, so build commands never
  wait behind it. A receiver reads it on a worker thread, so a file that takes a
  second or two to read costs no frame, and shows your built-in avatar until then.
  Players wearing the same file share one read. A file is dropped if it is over the
  size limit or is not a humanoid VRM.
- **Limits.** `Avatar.read` reads every file the same way, the player's own before
  it is sent, so all players see the same avatar: at most 24 MB, surfaces merged per
  material within a mesh, animations dropped, every triangle and blend shape kept as the
  author made them, and textures shrunk to 1024 px with mipmaps. A heavy mesh is its
  author's cost to carry; the reader edits none. The quality ladder already changes how much
  of the scene draws; avatars need no setting of their own.
- **Skinned bodies.** Every importer builds one avatar model, which `Avatar.model` loads:
  a scene of skinned meshes over one `Skeleton3D`, the skins' weights, inverse binds and
  blend shapes as the source has them, and on its root the avatar data: each humanoid
  bone and spring joint as a bone of that skeleton, where the eyes sit, which way the model
  faces, how its eyes look and its spring chains. A pose moves the hips, head, eyes, upper
  and lower arms and hands as skeleton bones, and the GPU bends the skin over them, so
  shoulders, elbows and knees bend continuously. Where a hand is held past the arm's reach,
  the hand still goes to the controller and the forearm's skin stretches after it. The
  built-in avatars are skinned the same way, each part wholly weighed to its bone. Each
  surface is a draw call, one per material of each mesh, and the limit is 40.
  On a Quest 2 at quality step 6, seven figures of Seed-san, the Unity sample package, in `demo/avatar-chain-cost.json`, all
  in view across the meadow, take 11.97 GPU ms against 9.37 with built-ins
  (`perf/quest-2/avatar-chain-cost/20261027T094550Z-c2cb2af.json`), 2.6 ms for the seven
  where their rigid parts took 1.6, which puts that view 0.86 ms past the 11.11 ms budget;
  one in view close takes 9.14 against 8.37. Each adds 3.2 MB of buffers and 3.1 MB of
  video memory; each phase's record keeps its peak texture, buffer and video memory.
- **Materials.** Godot's glTF reader reads each VRM material's glTF base: its
  colour, texture and alpha. Each is then lit once a vertex rather than once a pixel, draws
  front faces only, and is cut out, never blended, where it is see-through; normal maps and
  emission are dropped. Unlit (toon) surfaces are lit like the rest of the garden, so an
  avatar darkens at dusk instead of glowing.

### Spring motion and gripping

Avatar Workshop supplies the shared VRM spring definitions and their runtime, which drives
nodes or, through its `skeleton_bone.gd`, a skinned skeleton's bones.
Adjacent skeleton chains with unit transforms share one Godot `SpringBoneSimulator3D`
per skeleton, processed in definition order with shared sphere and capsule colliders.
Their completed endpoints feed replication. Held groups use the constraint solver,
which preserves release momentum until the chains settle before returning to native
simulation. Gapped chains, materially scaled transforms and collider dependencies the
native group cannot preserve use that same solver. It adapts godot-vrm's Verlet
integration and collision projection at 60 Hz with a bounded accumulator, retaining
its MIT notice. A declared center carries the simulation frame; a long pause resets
momentum. The game binds imported glTF node indices to skeleton bones. The selection
is by supported transforms and constraints, identical on every device.

Opening a scene also compacts its skin bindings: unused bindings disappear and exactly
identical bone/inverse-pose bindings share an index. Geometry, weights and blend shapes
stay unchanged. The result is cached on the scene and prepared on the main thread,
because reading mesh surfaces accesses the renderer while file import can run on a worker.

The 60-joint simulation ceiling is priced with the skinned runtime on Quest 2: three
figures visibly in view plus the same avatar worn, six private fixtures, give frame
p50 of 13.60–13.94 ms at 72 Hz under the common quality governor. GPU p50 is
7.81–9.20 ms (`perf/quest-2/avatar-skin-cost/20261027T214340Z-785038e.json`).
The fixtures keep up to 60 definition joints; endpoints are not additional driven
joints. These medians do not exclude occasional late frames, whose counts and p99
remain in the record.

The wearer owns their avatar's simulation. Empty-hand grip within 12 cm selects the
nearest unclaimed tip. A remote request identifies its hand and the target chain;
the wearer checks the hand is within 20 cm to allow for pose smoothing and rejects
an already-held chain. Held tips follow the hand within the chain's reach and yield
to colliders; release restores free motion. Tracking loss, leaving, changing avatars,
and releasing the grip clear the relevant holds. The hold consumes the hand before
building tools act. A paused player releases their local grip.

At 30 Hz the wearer's pose packet includes world-space chain endpoints and current
holders. Replicas interpolate those endpoints and apply rotations without another
simulation, so release motion and collision results come from the same owner. Late
joiners receive the next complete snapshot. Nonfinite positions, points outside the pose
packet's world bounds, mismatched endpoint counts and invalid holder records are rejected.
Snapshots and grip requests are transient avatar state, separate from garden commands.

`demo/avatar-springs-host.json` and `demo/avatar-springs-guest.json` drive a real
wearer/visitor session through the ordinary wheel and grip inputs. The observer
waits for the wearer's grip and release before pulling the same chain; the owner
checks that remote hold and release arrived. Sway records actual collider responses.
The avatar cost scene measures three figures; the stress tour includes seven chained
figures in view. Avatar files used by scripted figures load through the same worker
path as players' files.

Quest 2, quality step 6 at 72 Hz, three figures in `demo/avatar-cost.json`:
the matched Godette runs are
`perf/quest-2/avatar-cost/20261025T233338Z-a5fe9f9.json` before and
`perf/quest-2/avatar-cost/20261025T234834Z-5c5ef5d.json` after. Both use
`tests/avatars/godette-0.x.vrm`; each view repeats three times.

| Figures / view | Before GPU ms | With chains GPU ms |
| --- | ---: | ---: |
| Built-in / close | 7.24 | 7.27 |
| Built-in / across | 7.94 | 8.02 |
| Built-in / away | 8.10 | 8.06 |
| Godette / close | 7.58 | 7.63 |
| Godette / across | 8.44 | 8.79 |
| Godette / away | 8.10 | 8.14 |

Every phase holds the 11.11 ms GPU budget. The widest Godette view adds 24 draws
(88 to 112) while its triangle count stays effectively unchanged. These runs read
avatars as rigid parts, each spring joint its own part. These runs measure the complete
change, including the wearer's body pose and chain, rather than isolating solver
cost. Labeled phases contain six late frames before and eight after; their causes
are not isolated. The baseline's first Godette load also records a 3623 ms stall
with shader compilation. GPU medians do not establish hitch-free loading.

The seven-figure scene, `demo/avatar-chain-cost.json`, keeps the same views,
quality and repeated measurement sequence with seven figures. Its records are
`perf/quest-2/avatar-chain-cost/20261026T000249Z-a5fe9f9.json` before and
`perf/quest-2/avatar-chain-cost/20261026T000805Z-5c5ef5d.json` after.

| Seven figures / view | Before GPU ms | With chains GPU ms |
| --- | ---: | ---: |
| Built-in / close | 7.27 | 7.25 |
| Built-in / across | 8.13 | 8.28 |
| Built-in / away | 8.01 | 8.05 |
| Godette / close | 7.30 | 7.29 |
| Godette / across | 9.26 | 9.60 |
| Godette / away | 8.05 | 8.13 |

All six phases hold the GPU budget. The widest Godette view adds 55 draws
(125 to 180). Labeled phases contain seven late frames before and sixteen after;
the runs do not isolate their causes. This is a budget measurement on the Quest 2,
not a substitute for a worn-headset feel check.


Each player's avatar and colour go to every other player once, reliably. A pose packet carries
three transforms, the look direction in the head's frame, and spring state, unreliable and ordered at 30 Hz,
smoothed on arrival. Held implements use the same hand transforms. A reliable description of
both hands travels on change and when a peer arrives: model kind, variant, transform relative
to the visible hand, paint colour and load, source easel or book page, and whether seeds are
being offered. The same description carries a conure on either shoulder, standing on it in the
torso's frame (`Torso`), which every peer works out from the head pose as the avatar's body does.
An idle implement sends no repeated description.

`HeldItem` builds ordinary wheel tools, brushes and charcoal, both palettes and the book from
the holder's model builders. Empty or untracked hands remove their model. Painting models
carry their actual colour and load; held palettes reuse their easel's materials, including the
paint on the oil palette's board. A seed dish's separate feeding target stays alive when put away so animals never
retain a freed target; its drawing goes through the same held-model path as other tools.
Descriptions reject invalid kinds, nonfinite values and unbounded transforms. The garden's
build commands remain separate from these transient held appearances.

A thrown handful of seeds goes to every other player once, reliably: where it left the dish,
its velocity and the seed of its spread, from which each game throws the same handful
(docs/design.md, "Feeding").

## Finding each other

Every host announces itself on the local network once a second: a UDP broadcast on ports
7469–7472 carrying its game port (7480 and up), a random key, its built-in avatar, its colour,
and the hash of the player's own VRM if they wear one. Anyone who connects over TCP to the
game's port number gets that file (its length, then its bytes), the same file every player who
joins gets anyway, so the wheel shows it before anyone joins: a game hearing a hash it lacks
fetches the file, at most two at a time, reads it on a worker thread like a joined player's,
and keeps it only if its hash is the one the beacon named.
Hold the inventory wheel and enter its people branch. The avatar page offers the
built-in figures and the loaded VRM; releasing on one wears it and updates every peer.
The friends page shows nearby hosts in their avatars, with names and Steam pictures
where available. Each page holds at most four slots; its nested fan continues to more
friends. An empty ring marks no gardens available. Release on a host to join, or the
cairn to go home. Closing the wheel, changing tools or teleporting frees its figures.
Flat players hold Q or the left shoulder button, move the mouse or right stick through
the same wheel, and release to select. Names remain the game's one text exception.

Only gardens of a build with the same networked methods can be joined. Godot numbers a
node's RPCs by name, so a build with one more or one fewer calls the wrong methods on the
other: a visitor's digs, ponds and plants never land, and its strokes show and then vanish.
The beacon carries a fingerprint of `World`'s and `Session`'s RPCs (`Session.protocol`).
A garden whose beacon carries another (or the constant 1 of builds before the fingerprint)
still appears on the wheel, with a small X over it, and selecting it joins nothing. Builds
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
- **Without Steam,** the avatar page includes your own figure under a name the game
  offers, faint while only you can see it. Pick it and the name joins your beacon; pick it
  again for another. The game keeps the name you picked for later starts. A host who never
  picked one stands unnamed.

`Persona` (game/src/persona.gd) holds all of this. Steam is optional: only a Steam package
(`scripts/package.sh TARGET OUT steam`, or the Frame's `scripts/android.sh lepton OUT steam`) carries the GodotSteam extension and Valve's
`steam_api` library, and the game starts Steam only when Steam launched it (`SteamAppId`
in its environment) or a script names an app with `--steam-app ID`. Every other build and
launch plays without Steam on the same code path.

`--join ADDRESS[:PORT]`, `--avatar N`, `--name NAME` (a picked name) and `--steam-app ID`
are launch arguments for scripts and tests. `demo/avatar-wheel.json` captures the wheel; Valve's
test app 480 stands in for this game's app in development.

Only a game a player launched beacons on the network. One started with `--script`,
`--join` or `--port`, or built inside a test, sends its beacon to this machine's loopback address only
and listens there only, so a player never sees a scripted or test instance on the wheel.
Scripts can select a private four-port discovery range with `--beacon-port BASE`.
`coop.sh` reserves a separate range for each run, so unrelated headless instances
cannot take its listeners. Player launches still use ports 7469–7472.
Scripts on one machine still find each other by beacon, and scripts that play with another
machine (the bench's players) connect with `--join`. `tests/test_beacon.gd` fails if a
scripted or test instance beacons past loopback.

## Proof

`scripts/coop.sh OUT [N]` plays N headless instances on one machine (four by default,
two through eight supported):
1. One hosts; a second discovers its beacon and joins through the inventory wheel wearing
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
one model in both versions stands alike. It also converts the Unity sample package there and
checks the VRM keeps its skins, blend shapes and every bone of its Avatar definition as a skin
joint, and
that it reads, poses and reaches as the VRM samples do.

`scripts/coop.sh OUT --flat` renders a host and a flat-screen player (`--flat`) on one machine,
each wearing a sample avatar from its own avatars folder: the flat-screen player hears the
host's beacon, opens the shared inventory wheel and picks the host's figure (in
the host's file), walks up to the host and takes a photo of it into `OUT/photos`; the
host's captures show it standing in the garden in its own file. `tests/test_flat.gd`
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
phase lasts four wall-clock seconds after all peers have loaded the other avatars
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


`CAIRNFOLD_PLAYERS=N scripts/bench.sh OUT ...` plays the stress scene with N-1 other
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

Every phase is over the then 12.5 ms budget in these runs, the bare meadow included, so the
budget verdict belongs to the stress scene and the headset's state. Co-op costs a fraction
of a millisecond per player against it.

The Quest build must hold the network permission. Without it, every socket the game
opens fails, it hosts nothing, and no one can join. With it, a Quest and a desktop find
each other by beacon within seconds, both ways. `scripts/android.sh` refuses an APK whose manifest
lacks it.

### A player's own avatar

`CAIRNFOLD_GUEST_AVATAR=FILE.vrm` dresses the other players in a VRM, and
`CAIRNFOLD_SCENE=demo/avatars.json` looks at them three ways, three times over: close
(one of them 3.6 m away, the others behind), across the meadow (all three, 6 to 18 m)
and away (none in view). The VRM is the CC0 VRoid sample AvatarSample_D (VRM 1.0, 16.6 MB),
which read as 15,000 triangles in 17 surfaces when these runs were made.

On the Quest 2, `CAIRNFOLD_PLAYERS=4 bench.sh OUT --android APK`, the game's GPU
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

On the Quest 2, the VRM in view cost the headset 2 to 3 ms a frame, and neither the triangles,
the texture size nor alpha blending was what cost. `CAIRNFOLD_SCENE=demo/avatar-cost.json`
finds what does on one headset with no network in the way: its `figures` step stands three
other players, re-posed every frame as streamed poses pose them, at the spots above, in
built-in avatars or in the VRM, which `bench.sh` pushes from `CAIRNFOLD_GUEST_AVATAR`, and
looks at them close (one in view), across the meadow (all three) and away, three times over,
built-in and VRM in turn. Taking one thing at a time off the VRM as it was then read, the one at 3.6 m
cost a Quest 2 1.94 ms a frame over built-ins, at the top of the quality ladder of the time,
and each took off:

| Taken off | Saved |
| --- | --- |
| Skinning (its GPU pass over every vertex, every frame) | 0.79 |
| Both sides drawn | 0.45 |
| Normal maps | 0.39 |
| Emission | 0.21 |
| Alpha | 0.19 |
| All five | 1.68 of 1.94 |

The VRM then read as rigid parts with plain materials, and lighting each pixel was the
largest share left, 0.6 ms of the three across the meadow, so avatars are lit once a vertex.
Quest 2, quality step 6, median GPU milliseconds of three runs of each phase, before avatars
were skinned again (see "Skinned bodies" for skinning's cost now):

| Other players wear | Close (one in view) | Across (three) | Away (none) |
| --- | --- | --- | --- |
| built-in | 7.23 | 7.88 | 7.86 |
| the VRM, skinned, as read before | 8.85 | 10.00 | 7.90 |
| the VRM, rigid and plain | 7.71 | 8.88 | 7.88 |

The VRM in view costs 0.5 ms close and 0.34 ms each across the meadow, from 1.6 and 0.7, and
nothing out of view.

Every file arrives. With the Quest 2 hosting over Wi-Fi, the three 16.6 MB files cross the
link at once, and a burst of loss leaves some of a sender's packets unacknowledged for seconds.
ENet's default timeout dropped a live player for that within about 15 s, so the files that player
was sending and relaying never arrived. A player is now dropped only after 30 s without an
acknowledgement; on the Quest 2, all three files arrive and are worn within 25 s.

### Shared avatar runtime

VRM 0.x/1.0 and VRChat-style Unity packages feed one runtime in
[Avatar Workshop](https://github.com/bddap-bot/avatar-workshop), a public Godot
addon under MIT OR Apache-2.0, through the one avatar model above. Its expression mixer
weighs the eye expressions, `Avatar` supplying bindings and applying the results, and its
spring runtime swings the skeleton's spring bones. Avatar selection, networking, tracked
poses and quality policy stay in the game. The importer limits described above still
apply until the fidelity milestones land.

`game/addons/avatar_workshop/source.json` pins the upstream commit and SHA256 of
each vendored file, following the immutable-version and content-hash convention
of `scripts/pins.sh`. Vendoring keeps ordinary editor imports and the existing
`git archive` packaging path offline. To update, copy only the listed source
paths from the new upstream commit, update the commit and hashes, then run
`scripts/test.sh`; its pin check rejects local edits to upstream files. Make
runtime changes upstream first. Both license texts ship beside the runtime.
No plugin activation or synchronous asset load was added.
