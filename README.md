# Cairnfold

A cozy VR building toy, inspired by Tiny Glade. Draw stone walls across a meadow
and watch them grow courses of stone, crenellated tops and arches; teleport onto
the grass to stand beside them, or into the air to float above your build.

Runs standalone on the Steam Frame and on Meta Quest 2 and later (Godot 4.5, OpenXR). All assets are generated
by the code here; see [docs/design.md](docs/design.md) for the full design and
build order.

## Controls

Each hand holds a tool, shown as a small object on top of its controller: walls,
paths, flowers, grass, trees, terrain, pond, colour, camera, delete or visit.

- Hold B (right) or View (left), and a wheel of tools stands up in front of that
  hand: sweep the hand onto a tool and let go to take it. A slot showing a little
  cluster opens more tools on its far side: swing back onto one. Picks zig-zag
  left and right, the same motion every time.
- Trigger: use the tool. Draw a wall, lay a path, paint, plant a tree, grab the
  ground and lift or lower the hand to pull a hill or press a hollow, dig a pond
  (hold to dig deeper, release to fill), or erase: hold it on a wall and sweep
  along it to break that stretch into a ruin (a tap breaks a short gap, sweeping
  it all takes it all), or press on a tree or painted plants to take them. A path through a wall opens an
  arch, a wide one an arcade.
- Holding colour: hold the trigger on a wall, roof, gable, fence, window or door, or
  the meadow, and twist your wrist to turn a wheel of swatches for that material, or
  of seasons for the meadow; let go to keep the one at the top.
- Holding camera: the screen on its back shows what its lens sees; the trigger
  takes a photo, saved as a PNG in the game's `photos` folder
  (`~/.local/share/godot/app_userdata/Cairnfold/photos` on the Frame; inside the
  app on a Quest).
- Point any hand at the sun and grip it, then move the hand to drag it across the sky: dawn to dusk.
- A hand’s pointer disappears while grabbing and returns when released.
- Holding visit: a small figure of each player nearby on the same network stands
  in front of you; point at one and pull the trigger to build in their garden
  with them. While visiting, pick the little cairn to go home.
- Holding walls: grip on a wall pulls its height, grip on a roof shapes it; A on a
  wall cuts or fills an arch, A on its top changes its style; a loop held closed
  snaps to a round tower. Both hands on walls, both grips on the ground: lay out a
  house.
- Left stick forward: aim a teleport from the left hand, whatever it holds;
  release to go, into the sky to float. While aiming, the other stick up or
  down moves an air target farther or nearer.
- Right stick left/right: snap turn.
- Left D-pad down: undo. Up: redo. One history across every tool; with others,
  each player undoes only their own steps.
- Animals come on their own, drawn by what you make: ducks to a pond, butterflies
  to painted flowers, and fireflies at dusk over both.
- Your garden is saved after every edit and is back when the game starts again.

On Quest Touch controllers, which have no D-pad: left X undoes, left Y redoes,
right A cuts arches, and the wheels open on right B and left ≡.

## Running

- Desktop preview and tests: `nix-shell --run scripts/test.sh`,
  `nix-shell --run 'scripts/render.sh demo/slice.json out'`.
- Steam library artwork: `nix-shell --run scripts/steam-art.sh` regenerates
  `steam/` from captures of `demo/steam.json`.
- Release builds: `nix-shell --run 'scripts/package.sh TARGET OUT'` exports
  `linux-x64` or `linux-arm64` (a `.tar.gz`) or `windows` (a `.zip`). Each
  unpacks to `cairnfold/` holding the game (`cairnfold` or `Cairnfold.exe`),
  which starts in VR on the system's OpenXR runtime, such as SteamVR.
- Steam Frame: unpack the `linux-arm64` package in the headset's home and add
  `cairnfold/cairnfold` as a VR non-Steam shortcut with the art in
  `cairnfold/steam/`.
- The game keeps its garden, photos, `metrics.json` and logs in Godot's user
  directory: `~/.local/share/godot/app_userdata/Cairnfold` on Linux,
  `%APPDATA%\Godot\app_userdata\Cairnfold` on Windows.

## Quest

Each [release](https://github.com/bddap-bot/cairnfold/releases) carries
`cairnfold-quest.apk`. To install it:

1. Turn on developer mode for the headset in the Meta Horizon phone app
   (Devices, then Developer Mode; it asks you to register as a developer once).
2. Connect the headset by USB and accept the debugging prompt inside it.
3. Install with [SideQuest](https://sidequestvr.com) (drag the APK onto it) or
   `adb install -r cairnfold-quest.apk`.
4. In the headset, open the library's Unknown Sources filter and start Cairnfold.

Build it yourself with `nix-shell android.nix --run 'scripts/android.sh cairnfold.apk'`;
it signs with a local key, so remove a release install before installing your own.
`scripts/release.sh` publishes the desktop and Frame builds and the APK together.

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT) at your option.
