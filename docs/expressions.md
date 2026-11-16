# Avatar expressions

Hold B on the right hand or Y on the left, sweep into the people group, then onto
its wand slot. The avatar's Expressions Menu opens in the tool wheel, with its
own control names and icons. The slot is available wherever that avatar is worn.

Release on a toggle to change it, or on a button to send its one-second pulse.
Reach into a submenu to open its wheel. Its optional parameter stays set while
inside it and resets on leaving. The trigger goes back one level.

Reach a puppet and release B/Y to free the thumb. A radial follows the wrist's
twist from its saved value. Two-axis and four-axis puppets follow the right
thumbstick; tracked hands use the right little-finger pinch stick. Press B/Y
again to return to the parent wheel. Closing a puppet preserves its axis values
and clears its optional open parameter.

The slot beside it, a curled arrow, resets: release B/Y on it and the avatar
returns to its creator's defaults and its saved values are forgotten, as VRChat's
Reset Avatar does.

Only parameters marked Saved are restored when that avatar is worn again. The
local file is keyed by avatar identity. Reading and writing it run on workers,
and icon decoding happens during avatar import.

The runtime consumes the imported FX states, conditions, parameter drivers,
clips and blend trees. Targets include visibility, blend shapes, bone scales,
atlas material choices, hue regions and particle systems, switched, recoloured or
given another material ([particles](particles.md)). VRCFury features join the menu as
VRCFury builds them at upload: each Toggle becomes a control, its parameter and
a layer of its actions, and each FullController's FX controller, menus and
parameters merge in before MoveMenuItem and SetIcon apply. VRCFury then
sets every state's Write Defaults as its build does: on or off as its Fix Write
Defaults feature says (on under MMD compatibility), otherwise as most of the
avatar's own FX states have it, over every layer, or over only the layers VRCFury
added when the avatar has no such feature or it is disabled. Among the layers it
sets, one that blends additively or holds a direct blend tree always writes
defaults. When states are turned off, a new first layer writes the resting value
of everything they animate but the controller's parameters, and a state left
without Write Defaults and without a motion gets an empty clip. With ten or fewer
FX states of its own VRCFury also counts the avatar's other controllers; the
importer reads only FX's, and that only with the avatar's menu. Where it cannot
count, only the layers that always write defaults are set, and the report says so. A clip that animates one of
the controller's own parameters writes it every frame, as Unity's animator does. The
avatar's VRChat contacts come along: each receiver sets its parameter from the tagged
senders touching it (constant, on enter, or proximity), the wearer's hands and every
other player among them, each body carrying the senders VRChat gives every avatar.
A Poiyomi UDIM
discard tile is a switch: its triangles draw while it is off. A clip moving a Poiyomi
material's lighting addition or post-processing brightness adds that light after the
material's light cap or scales its final colour, as the shader does, wherever a locked
shader keeps the property animated and, for brightness, post-processing is on. The importer reports controller features
it cannot translate. Menu semantics follow the
[VRChat Expressions Menu documentation](https://creators.vrchat.com/avatars/expression-menu-and-controls/).

A state with Write Defaults off plays as Unity's animator plays it, which is not
per layer. While some layer is in such a state and the state has a motion, a
property that neither it nor a layer before it animates does not return to its
default: it keeps the value it last had while any layer animated it, blended over
the default by the weight of the first such layer. So one layer of that kind
leaves every toggle in the controller on after it is turned off, unless the
toggle's off state animates the property back. A state with Write Defaults off
and no motion repeats what its layer played last, and, where that was a state
with Write Defaults off too, every other property at the value then kept.
Transitions here are instant: Unity leaves a property part-way through a timed
transition when one ends under such a state, and that remainder is not reproduced.
`tests/unity/write-defaults.json` holds the Unity runs this follows.

The converter writes the menu, parameters and controller as the `VRCHAT_expressions` extension and an avatar's
constraints as `UNITY_constraints`, each carrying its version (`Vrm.VERSIONS`). Every record carries the fields
below, and a file whose record lacks one is refused, naming it.

`VRCHAT_expressions` records and the fields each must carry (`Vrm.REQUIRED`):

| record | fields |
|---|---|
| `parameter` | `default`, `saved` |
| `target` | `default` |
| `clip` | `length`, `curves` |
| `curve` | `step` |
| `layer` | `weight`, `default` |
| `driver` | `source`, `drive`, `value`, `min`, `max`, `chance` |
| `transition` | `conditions` |
| `control` | `name`, `parameter`, `value`, `axes` |
| `child` | `speed`, `offset`, `threshold` |
| `emission` | `replace` |
| `material` | `matcaps` |
| `hue` | `shift`, `space`, `select` |

`UNITY_constraints` records and the fields each must carry (`Vrm.REQUIRED`):

| record | fields |
|---|---|
| `constraint` | `weight` |
| `source` | `weight` |

`tests/test_expressions.gd` checks parameters, controller evaluation, malformed
input and a VRM round trip. `tests/test_expression_wheel.gd` exercises the actual
wheel inputs, visible avatar changes, puppet operation with the menu button
released, and per-avatar persistence. `demo/expressions.json` operates the same
controls in a mirror and measures open and closed phases on the generated test
avatar in `game/demo/expressions.gd`. The stress scene includes its open menu and
radial. All of these assets are authored test content.
