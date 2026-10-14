# Cairnfold

A cozy VR building toy, inspired by Tiny Glade. Draw stone walls across a meadow
and watch them grow courses of stone, crenellated tops and arches; teleport onto
the grass to stand beside them, or into the air to float above your build.

Runs standalone on the Steam Frame (Godot 4.5, OpenXR). All assets are generated
by the code here; see [docs/design.md](docs/design.md) for the full design and
build order.

## Controls

- Left stick forward: aim a straight teleport ray; release to go. Aim into the
  sky to target a point in the air and float there; while aiming, right stick
  up or down moves that point farther or nearer.
- Left D-pad up, left or right: glide back down to the ground.
- Right stick left/right: snap turn.
- Right trigger: draw a wall along the ground.
- Right grip on a wall: pull its height up or down.
- A on a wall: cut or fill an arch.
- Hold the left D-pad down: undo the last wall.
- Left trigger: paint flowers or grass; X switches which. Left grip: plant a tree.

## Running

- Desktop preview and tests: `nix-shell --run scripts/test.sh`,
  `nix-shell --run 'scripts/render.sh demo/slice.json out'`.
- Headset (developer mode on: it enables SSH and the Steam client's debug port,
  through which deploy adds the shortcut):
  `scripts/package.sh cairnfold.tar.gz`, then
  `nix-shell --run 'scripts/deploy.sh cairnfold.tar.gz <ssh-host>'`. It installs
  `~/cairnfold` and a "Cairnfold" VR shortcut in the Steam library that launches
  it.

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT) at your option.
