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

Only parameters marked Saved are restored when that avatar is worn again. The
local file is keyed by avatar identity. Reading and writing it run on workers,
and icon decoding happens during avatar import.

The runtime consumes the imported FX states, conditions, parameter drivers,
clips and blend trees. Targets include visibility, blend shapes, bone scales,
atlas material choices and hue regions. The importer reports controller features
it cannot translate. Menu semantics follow the
[VRChat Expressions Menu documentation](https://creators.vrchat.com/avatars/expression-menu-and-controls/).

`tests/test_expressions.gd` checks parameters, controller evaluation, malformed
input and a VRM round trip. `tests/test_expression_wheel.gd` exercises the actual
wheel inputs, visible avatar changes, puppet operation with the menu button
released, and per-avatar persistence. `demo/expressions.json` operates the same
controls in a mirror and measures open and closed phases on the generated test
avatar in `game/demo/expressions.gd`. The stress scene includes its open menu and
radial. All of these assets are authored test content.
