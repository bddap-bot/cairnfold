# Replay

A session record (design.md, "Local play-session history") replays the session: on the desktop or a headset, on the
build that recorded it or a later one, from the player's head or an authored camera.

## Playing a record

`--replay FILE` plays a session back from its record, `FILE` any chunk of it with the session's other chunks beside
it. The game starts from the record's seeds and garden, and `Replayer` takes the place of the network: Godot polls it
at the start of every frame, before anything else runs, and there it delivers each message the record says came in
before that frame, as from the peer that sent it, then puts the head and hands where the record has them and presses
the inputs the record has held. Peers come and go as the record says; a join reaches no one, and from where the
record joins a garden to where it leaves it the game plays as the id the record says it joined as; what the game
sends goes nowhere. Each frame is scaled to its recorded delta: the run's first frame plays none of the record, with
the tree paused, and gives the engine's step, and under `--fixed-fps` every frame then takes its recorded delta, the
first one's too (a headset's, a load long, feeds how tall the player is measured).
At a rate that is a power of two (`--fixed-fps 64`) every delta is exact and the replay is the session again, bit for
bit, however the session ran; at another a few deltas miss by their last bit. The replay turns off the engine's
snapping of frames to physics ticks, which would move the step. In real time a frame's length is only known after it,
so deltas and whatever depends on them can differ. A hand played on its
joints replays as a controller held at its palm, giving the same inputs. The game quits when the record runs out.

What game logic reads never waits on the machine's timing, so a replay is the session again however loaded either
machine was. A worker thread's work for it is taken at a frame the frames decide (`Work`): a garden wall's stones
the frames `Budget.lay_frames` prices from what it lays after their lay began, so the lay fits them on a Quest 2, its
perches `Budget.PERCH_FRAMES` after, a command's water
`Budget.WATER_FRAMES` after, waited for then if the worker is not done (Metrics notes the wait), frames counted without
the replay's paused first one. Work spread over frames is metered by counts: a committed stroke grows
`Budget.GROW_PLANTS` plants a frame, the ground wears `Budget.GROUND_WEAR_ROWS` marks or rows of a laid path a frame,
the builds the garden reshaped lay again `Budget.RELAYS` a frame and butterflies look over `Budget.BUTTERFLY_SCAN`
flowers a frame. Only drawing takes its workers' results as they finish and keeps time budgets
(`Budget.MASONRY_FLUSH_US`, `Budget.PARTICLE_BIRTHS_US`). tests/test_replay_timing.gd records a session, metered as a
game is, whose pond fills, whose walls go up and are laid again, whose trees and flowers grow and whose path wears the
ground while threads spin beside the game and every command finds the worker pool held for a second; ducks and then
birds come, and the player teleports to a wall's foot. Replayed with nothing else running, every check of the player and
the wildlife holds.

The garden is the record's: every build command replays as the host ordered it (`ordered` in a host's record,
`_commit` in a visitor's; multiplayer.md), applied when the record says it came (an order does not wait again for the
water the host waited for before ordering it), and a proposal a host received is only the order that follows it. The
tools still see the replayed input, draw their ghosts and submit what they make of it, but in a replay
(`World.replayed`) a submitted command goes nowhere.

The player is the record's too. How tall they stand in the world is their avatar's eye height over their own
(`Rig.fit`), so the replay wears what they wore: the look they began in and each they put on (`look`, `Session.put_on`),
put on between frames, where the session put it on, so both refit them from the same frame. A built-in avatar is named
by its number and colour; a file of their own the record keeps only as its hash, and the replay reads it from the
folder `--avatars` names, by default the player folder's own `avatars`, so on the device that recorded it nothing is
passed. A record whose file that folder lacks is refused, naming the file: pull the avatars folder off the device
with its sessions. The head is the runtime's alone: a refit sets the player down where the runtime will next report
the head at the new scale and leaves the head as it was given (`Rig.place`), so the record keeps every head pose as
the runtime gave it. A replay never pauses, but where the headset left focus and came back (`paused`, `resumed`;
`Main.held`) it does what the pause did to play: an aim under way ends, and on return the controls are taken as they
are.

tests/test_replay.gd records a scripted session in which a visiting player proposes a tree, the headset leaves focus
mid-aim, the player puts on a file of their own and is refitted to it, and some frames run at half speed; it replays it
in a fresh game, and finds every frame's delta and head pose and the final garden equal, and every check the record
took holding. tests/test_replay_visit.gd records a player who plants at home and then joins a garden at the same
command; its replay compares the visited garden once it is restored whole, not halfway, though a look is put on later
in the frame it is restored and kept in, and plays as the id it joined as.

In a headset the eyes are drawn where its own tracking puts them, so before each draw a replay shifts the play space
under the headset's pose until the eyes see from the recorded head; the game's state never moves. A Quest's session
therefore replays on a Quest under `scripts/bench.sh` with `CAIRNFOLD_REPLAY=CHUNK.jsonl`, proximity held and unworn,
its rows written to the bench's `--metrics` file and its per-activity timing printed beside the recorded session's
(`scripts/sessions.py DIR --replayed METRICS.json`). `demo/played.json` is a session made only of what a player's
controllers give, so a bench run of it leaves a record the replay plays whole; a script's other steps place the rig
or the garden directly, which no record holds.

`scripts/render.sh CHUNK.jsonl OUT` re-renders a record on the desktop renderer with the graphics of the build running
it, seen from the recorded head; with `CAIRNFOLD_CAMERA=PATH.json` it is seen instead from an authored camera
(`CameraPath`, Main's `--camera`): a JSON list of keys, each a time `t` in game seconds from the start, an `eye` and
the point it looks `at` in the garden's space, as a script's `view` takes them, the camera on a curve through the eyes
looking at a point on a curve through the points looked at, holding before the first key and after the last. It sees
and hears what an onlooker there would, the player's own body too; what the player did still comes from the player's
head, so a wheel opens facing it and a pond is over it as in the session. Each frame of `--write-movie OUT/x.avi
--fixed-fps RATE` shows one recorded frame, so at the rate the session ran the clip keeps its pace but for its late
frames. `demo/cameras/played.json` circles a session of `demo/played.json`.

## Later builds

Every chunk's start record names its build revision, its `schema` (`PlayLog.SCHEMA`): how a frame lays out, and its
`events` (`Replayer.events`): a fingerprint of the events the replay delivers, each a `Replayer._deliver_` method, and
of every RPC of `World` and `Session` with its arguments' names and types, and of `World.FORMAT`. A record of another schema or other events
is refused with the reason, as is one missing frames or keeping its gardens without `heard` and `turn`, and so is one
whose starting garden is not in this build's `World.format()`: `World.FORMAT` and a digest of the meadow, every
plant's pool in the order the snapshot numbers them and the state its seeded scatter ends in. One from another
revision replays. A frame's inputs
are read by the names the record lists, so a later controls table that reads other inputs presses none it lost.

What a later build changes, a replay of an earlier record shows the session under: the same head, hands, inputs,
messages and build commands, with this build's logic between them. Where that logic changed, the replay diverges from
the session:

- A command's result. The same command applies through this build's `World`, so a changed build, clutter, plant or
  water rule leaves a different garden. One this build's `Commands.clean` turns down stops the garden there, as it
  stops a visitor's until the host sends the whole garden again. The edits themselves never diverge with the tools:
  what a tool makes of the input is not replayed.
- Wildlife and other seeded simulation. Every animal starts from the record's seed, but a changed rule draws from its
  generator a different number of times or acts on what it drew differently, and from there it goes its own way.
- Physics. A thrown handful's flight, and where it lands, follows this build's rules.
- Where the player stands. The head and hands are the record's, but in the play space; a teleport is the input
  played through this build's aiming and the ground under it, so a changed teleport stands the player elsewhere, and
  every later head pose with it.
- What reads the input. A tool, wheel or menu that reads the same input differently does something else; only its
  ghosts and sounds show it, since its commands go nowhere. A replay hears no gardens near (it listens for no
  beacons), so its menu never joins one; the messages from the garden the session joined arrive all the same.

A replay says where it diverged. Every `Replay.CHECK_EVERY` (60) frames the session keeps a check (`Replay.check`): a
digest of where the play space stands (`player`), of every node under the wildlife and every generator held there as
`rng` (`wildlife`), and of every thrown handful (`physics`). Whenever the garden is kept (`World._keep`, at most every
five seconds while it changes) the session keeps the snapshot's digest too (`garden`), with the command it stands
after; a host serializes that snapshot to save it anyway, and a visitor, who saves none, serializes it for the record
alone. The log's worker takes every digest, and beside a garden's the number of messages heard before it was kept
(`heard`) and whether World kept it in its turn of the frame or between frames (`turn`). The replay compares each part
at the point of the frame the record took it, and a garden where it was kept: in its frame, after the messages heard
before it, and in `World`'s turn of the frame if it was kept there, the frame's messages heard after it delivered once
that turn is done. A keep waits for the last save to be written, so the recording machine chose that point, and the
garden moves between commands, a running sky a `World.RUN_STEP` of the day at a time. It notes the first check each part
fails: its frame, the game second, and for the garden the commands it ran since it last matched, among which is the one
whose result changed, or, where the replay stood at another command, that command, or that it never came to where the
garden was kept. It prints each as it finds it and once more as the record runs out, or that every check held. The parts
compare exactly, so they hold only where every frame replays at its recorded length (`--fixed-fps`); a replay in real
time, as on a headset, diverges in them from its first check, and in the garden wherever a change waits on the frames'
lengths: a running sky's time of day is their deltas summed, and a whole garden coming in waits for the view to fade,
while the rest of the garden is made of the record's commands.

tests/test_replay.gd replays its record on a later revision with the input's sticks and buttons cleared, where the
garden still comes out as recorded and the player is said to stand elsewhere from the first check, and replays it with
one command's tree grown from another seed, the wildlife from another seed and one check's handfuls changed, where it
names each part's first failed check and, for the garden, the commands since it last matched.
tests/test_replay_sky.gd records a running sky and a tree planted while the garden's next keep is put off, which comes
after the sky has stepped on from where it stood when the tree was planted; a tree planted in the frame of that keep,
after it, from a node that runs after `World` as a tool does; and a keep between frames with a tree planted after it,
before the next frame. Replayed, every garden holds; with one kept garden's digest changed, or its command, the replay
names it and the commands since the last that held.
