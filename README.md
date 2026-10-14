# Cairnfold

A cozy VR building toy, inspired by Tiny Glade. Draw stone walls across a meadow
and watch them grow courses of stone, crenellated tops and arches; teleport onto
the grass to stand beside them, or into the air to float above your build.

Runs standalone on the Steam Frame and on Meta Quest 2 and later (Godot 4.5, OpenXR). All assets are generated
by the code here; see [docs/design.md](docs/design.md) for the full design and
build order.

## Controls

Each hand holds a tool, shown as a small object on top of its controller: walls,
flowers, grass, trees, teleport or delete.

- Hold a stick's click, push toward a tool in the ring, let go: that hand takes it.
- Trigger: use the tool. Draw a wall, paint, plant a tree, aim a teleport (release
  to go; into the sky to float), or delete the one thing you point at.
- Holding walls: grip on a wall pulls its height, grip on a roof shapes it; A on a
  wall cuts or fills an arch, A on its top changes its style; a loop held closed
  snaps to a round tower. Both hands on walls, both grips on the ground: lay out a
  house.
- Left stick forward: teleport with any tool. While aiming, the other stick up or
  down moves an air target farther or nearer.
- Right stick left/right: snap turn.
- Left D-pad down: undo. Up: redo. Every tool shares the one history.

On Quest Touch controllers, which have no D-pad: left X undoes, left Y redoes,
right A cuts arches.

## Running

- Desktop preview and tests: `nix-shell --run scripts/test.sh`,
  `nix-shell --run 'scripts/render.sh demo/slice.json out'`.
- Steam library artwork: `nix-shell --run scripts/steam-art.sh` regenerates
  `steam/` from captures of `demo/steam.json`.
- Headset: `scripts/package.sh cairnfold.tar.gz` builds the aarch64 bundle.
  Unpack it in the headset's home, run
  `cairnfold/bin/godot --headless --path cairnfold/game --import` once, and add
  `cairnfold/play.sh` as a VR non-Steam shortcut with the art in
  `cairnfold/steam/`.

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
`scripts/release.sh` publishes the Frame bundle and the APK together.

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT) at your option.
