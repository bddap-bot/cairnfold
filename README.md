# Nestcombe

A cozy VR building toy, inspired by Tiny Glade. Draw stone or plaster walls across a meadow
and watch them grow courses of stone, crenellated tops and arches; teleport onto
the grass to stand beside them, or into the air to float above your build.

Runs standalone on the Steam Frame and on Meta Quest 2 and later (Godot 4.6, OpenXR). All assets are generated
by the code here; see [docs/design.md](docs/design.md) for the full design and
build order.

## Controls

Each hand holds a tool, shown as a small object on top of its controller: walls,
dirt paths, stone, flowers, grass, trees, boulders, pond, colour, style, camera, seeds, delete or visit.

- Hold the upper face button (B on the right, Y on the left; on the Steam Frame B
  on the right, D-pad left on the left), and a wheel of tools stands up in front of that
  hand: sweep the hand onto a tool and let go to take it, or let go on none to hold nothing. A slot showing a little
  cluster opens more tools on its far side: swing back onto one. Picks zig-zag
  left and right, the same motion every time.
- Trigger: use the tool. Draw a wall, lay a path, paint (a stone stroke begun on
  stone paints meadow back), plant a tree, fill a pond (press a hollow with the grip,
  then point at its rim to fill it to the brim, or lower down its side for shallower water), or erase: hold it and swipe, and everything
  the beam passes over goes in one stroke, one undo step: walls break into ruins
  along the stretch swept (a tap breaks a short gap, sweeping it all takes it
  all), trees, bushes, paths and stone go, and grass and flowers are mown. A path through a wall opens an
  arch, a wide one an arcade.
- Holding colour: hold the trigger on a wall, roof, gable, fence, window or door, or
  the meadow, and twist your wrist to turn a wheel of swatches for that material, or
  of seasons for the meadow; let go to keep the one at the top.
- Holding style: the same, with a little model of each style of what you point
  at: a gable end's, a roof's (pitched, a tower's cone, flat), a wall's top, along
  a wall stone or plaster (a house's timber framings too), or a tree's species.
- Holding the arch: the trigger on a wall cuts an archway there; on an arch, it fills it.
- Holding camera: the screen on its back shows what its lens sees, tilted as you
  hold it and with your own avatar in view when you turn it on yourself; the trigger
  takes a photo at the game's best quality, saved as a PNG in the game's `photos` folder
  (`~/.local/share/godot/app_userdata/Nestcombe/photos` from the Linux package;
  `Pictures/Nestcombe` in the headset's shared storage from an APK, where they
  outlive an uninstall). The PNG
  records where and how it was taken and, unless it is very large, the garden itself:
  `nestcombe -- --photo FILE` opens that garden seen from the photo's lens.
- Holding seeds: hold the hand out and keep it calm. A conure may fly down and eat
  standing on it; ducks and sheep come to seeds held low by their pond or fence.
  Animals let you come right up if you move slowly; a sudden move startles them.
- Grip, whatever the hand holds: grab what you point at and drag it. Grab the
  ground (a pond's bed too) and raise the hand to pull a hill or lower it to press
  a hollow; grab a wall, fence, house, tower, boulder or stairs to carry and turn it, a
  house rising onto a plinth as the hand rises; grab open sky, or the sun or the moon, to turn
  it by aiming, round the whole day: the moon stands opposite the sun and lights the night. Two hands size: grip a house with both and spread them for
  width or depth, a wall for its length, stairs for their width; draw them apart upright for
  taller walls; both on a roof raise the ridge upright and bow it across; both on its eaves
  pull them out. Grip never builds anything.
  Each hand grabs on its own: hold a pond's bed in one hand while the other carries a house,
  or shape two hills at once.
- A hand’s pointer disappears while grabbing and returns when released, except
  on the sky, where aiming is what turns it.
- On the inventory wheel, enter the people branch to pick your avatar or a nearby
  garden. Release on a host figure to join; while visiting, pick the cairn to go home.
- Plaster keeps stone bases, corners and opening trim; either material supports the same
  roofs and fittings.
- A wall drawn round into a loop stays a wall.
- Holding the house or the tower: trigger puts one up where you point; the grip moves it.
- Left stick forward: aim a teleport from the left hand, whatever it holds;
  release to go, into the sky to float. Ease the stick back to land nearer
  along the aim.
- Right stick left/right: snap turn.
- Left X (the Frame's D-pad down): undo. Right A: redo. One history across every
  tool; with others, each player undoes only their own steps.
- Animals come on their own, drawn by what you make: ducks and fish to a pond, butterflies
  to painted flowers, and fireflies at dusk over both.
- Your garden is saved after every edit and is back when the game starts again.

## Running

- Desktop preview and tests: `nix-shell --run scripts/test.sh`,
  `nix-shell --run 'scripts/render.sh demo/slice.json out'`.
- Steam and Horizon Store art and screenshots: `nix-shell --run scripts/store-art.sh`
  regenerates `steam/` and `meta/` from captures of `demo/steam.json` and `demo/steam-coop.json`; the
  title is its one input. The trailer: `nix-shell --run 'scripts/steam-trailer.sh trailer.mp4'`
  records `demo/trailer.json`. Store copy: `steam/store.md`.
- Release builds: `nix-shell --run 'scripts/package.sh TARGET OUT'` exports
  `linux-x64` or `linux-arm64` (a `.tar.gz`) or `windows` (a `.zip`). Each
  unpacks to `nestcombe/` holding the game (`nestcombe` or `Nestcombe.exe`),
  which starts in VR on the system's OpenXR runtime, such as SteamVR.
- Steam Frame: unpack the `linux-arm64` package in the headset's home and add
  `nestcombe/nestcombe` as a VR non-Steam shortcut with the art in
  `nestcombe/steam/`.
- The game keeps its garden, photos and engine logs in Godot's user
  directory: `~/.local/share/godot/app_userdata/Nestcombe` on Linux,
  `%APPDATA%\Godot\app_userdata\Nestcombe` on Windows. An APK keeps the garden
  (`garden.save`), photos and avatars in `/sdcard/Android/data/io.github.bddapbot.nestcombe/files`,
  where adb reads them.
  Put a VRM avatar (1.0 or 0.x) in its `avatars` folder to wear it: the newest file there
  is yours, and other players see it (see [docs/multiplayer.md](docs/multiplayer.md)). On a
  Quest the folder is `/sdcard/Android/data/io.github.bddapbot.nestcombe/files/avatars`:
  `adb push avatar.vrm /sdcard/Android/data/io.github.bddapbot.nestcombe/files/avatars/`.

Session telemetry is off by default and never sent by the game. Launch with
`--record-sessions`, or put a `record-sessions` file in the player folder, to opt this
device into bounded local frame and head-pose history in that folder's `sessions/`;
`--forget-sessions` opts out. `scripts/sessions.py DIR` summarises a pulled folder.
See [local play-session history](docs/design.md#local-play-session-history).

## Quest

Each [release](https://github.com/bddap-bot/nestcombe/releases) carries
`nestcombe-quest.apk`. To install it:

1. Turn on developer mode for the headset in the Meta Horizon phone app
   (Devices, then Developer Mode; it asks you to register as a developer once).
2. Connect the headset by USB and accept the debugging prompt inside it.
3. Install with [SideQuest](https://sidequestvr.com) (drag the APK onto it) or
   `adb install -r nestcombe-quest.apk`.
4. In the headset, open the library's Unknown Sources filter and start Nestcombe.

Build it yourself with `nix-shell android.nix --run 'scripts/android.sh quest nestcombe.apk'`;
it signs with your own key (AGENTS.md, "Signing"), so a release install must go before yours does:
`scripts/quest-install.sh nestcombe.apk` uninstalls it when it must and puts your garden and avatars back.
`scripts/release.sh` publishes the desktop and Frame builds and both APKs together.

## Privacy

The game collects nothing about you: [PRIVACY.md](PRIVACY.md).

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT) at your option.

Avatar and multiplayer choices share the inventory wheel. Its people branch contains
avatar figures and paged gardens to join. In flat mode, hold Q or the gamepad left
shoulder button, move the mouse or right stick through the wheel, and release to pick.
