# Working on Cairnfold

Read [docs/design.md](docs/design.md) first; it holds the element inventory, the
controls and the build order.

- Clean room: never use, inspect or derive anything from Tiny Glade's files.
  Public talks and store material may inform the feel; every asset is generated
  here or authored for this project.
- Holding the headset's refresh rate is a hard requirement. Measure each change on
  the device with `play.sh --script ... --metrics ...`; desktop renders do not
  establish frame rate.
- Generators stay pure data (like `WallLayout`), tested headless in `tests/`.
- Delete comments that restate code; keep only a why the code cannot show.
- Edit by subtraction: fix problems by removing code where possible, one
  implementation per thing.
- `nix-shell --run scripts/test.sh` must pass before landing.
