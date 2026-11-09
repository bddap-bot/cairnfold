# Avatar particles

`scripts/unity_avatar.gd` keeps an avatar's Unity ParticleSystems: footstep effects, auras and the
sparks a menu toggles. They travel in a VRM as the root extension `UNITY_particles`, and
`AvatarParticles` draws them. Import samples every curve and gradient and mirrors every vector into
the avatar's axes (`scripts/unity/particles.gd`), so a runtime needs none of Unity's types.

## File

```
"UNITY_particles": {"systems": [System...], "meshes": [Mesh...]}
```

A **curve** is `{"min": [s...], "max": [s...], "scale": [a, b]}`. Samples are evenly spaced over
its span, from 0 to 1, and are read linearly between neighbours; a lone sample holds everywhere. Its
value at `t` is `lerp(a * min(t), b * max(t), r)`, where `r` is the particle's own random draw for
that property. A **gradient** is `{"min": [[r, g, b, a]...], "max": [...]}`, sampled the same way and
blended by `r`. Its colour is sRGB, as Unity saves it and possibly above 1; its alpha is linear.

A **system**:

| field | meaning |
|---|---|
| `node` | the glTF node it hangs from; the emitter is that node's world position and rotation |
| `duration`, `loop`, `delay` | its cycle in seconds, whether the cycle repeats, and the wait before the first one |
| `awake` | whether it plays from the start of its cycle whenever it becomes active |
| `world` | whether particles keep their world position; otherwise they move with the emitter |
| `max` | the most particles alive at once |
| `lifetime`, `speed`, `gravity`, `rate`, `distance` | curves over the cycle, read when a particle is born; `gravity` scales 9.81 m/s² down, `rate` is per second and `distance` is per metre the emitter moves |
| `size`, `rotation` | a curve, or three (x, y, z); a lone rotation turns about the view axis (radians) |
| `color` | a gradient over the cycle |
| `bursts` | `[{"time", "count" (curve), "cycles", "interval", "probability"}]` within each cycle |
| `shape` | where particles start: `type` (`point`, `sphere`, `hemisphere`, `cone`, `box`, `circle`, `edge`), `radius`, `thickness` (0 emits from the surface, 1 from the whole volume), `angle` and `arc` (radians), `length` (a cone's volume), `matrix` (its placement in the emitter's axes, column-major, any scale included), `randomDirection`, `spherical` and `randomPosition` |
| `velocity` | `{"x", "y", "z", "world"}`, curves over life added to a particle's velocity, in world or emitter axes |
| `limit` | `{"speed", "dampen"}`: a particle's start speed past `speed` (read at birth) falls away by `dampen` each thirtieth of a second |
| `inherit` | a curve: the share of the emitter's velocity a particle starts with |
| `noise` | `{"strength", "frequency"}`: a smooth wander of `strength` m/s |
| `sizeOverLife`, `spin` | a curve or three over life, multiplying size or turning at radians per second |
| `colorOverLife` | a gradient over life, multiplying the colour |
| `sizeBySpeed`, `colorBySpeed` | `{"size" or "color", "range": [low, high]}` over speed in m/s |
| `subEmitters` | up to four `[{"system", "on": "birth" or "death", "inherit": ["color", "size", "rotation", "lifetime"]}]`; a system another names emits only through it, and a name leading back to the system naming it is dropped |
| `renderer` | how it draws (below) |

Shapes face +Z. A cone opens about +Z, a box emits along +Z, a circle lies in XY and emits
outward, and an edge runs along X and emits along +Y.

The **renderer** is `{"draw", "mode", "align", "mesh", "pivot", "length", "velocityScale", "maxSize",
"materials"}`. `mode` is `billboard`, `stretched` (along the velocity, `length` times the size plus
`velocityScale` times the speed), `horizontal` (flat, facing up), `vertical` (upright, facing the eye)
or `mesh` (`meshes[mesh]`, shifted by `pivot` sizes). A billboard or mesh turns by its rotation in the
frame `align` names: `view` (the view's plane, turning about the view axis alone), `world`, `local`
(the emitter's), `facing` (toward the eye) or `velocity` (+Z along the velocity). A quad spans at most
`maxSize` of the view's height. A system whose `draw` is false runs unseen and can still drive
sub-emitters. `materials` lists the materials a clip may choose among, the default first. Each is
`{"color", "emission", "blend", "cutoff", "image", "uv"}`. `color` multiplies and `emission` adds
(both sRGB), `blend` is one of `opaque`, `cutout`, `alpha`, `add`, `premultiplied` or `multiply`,
`image` is a glTF image no texture names (lossless WebP), and `uv` is Unity's
`[scale x, scale y, offset x, offset y]`.

A **mesh** is `{"positions", "uvs", "indices"}`, flat arrays in glTF axes.

An avatar runs at most `Avatar.MAX_PARTICLE_SYSTEMS` systems; past `Avatar.MAX_PARTICLES` particles
alive at once, or `Avatar.MAX_PARTICLE_VERTICES` vertices drawn by them, every system's `max` is cut
by one share. Import multiplies sizes, speeds and shapes by the emitter's scale and folds Unity's
simulation speed into times, rates and speeds, as it does a clip's values for them.

## Switches and menu effects

In `VRCHAT_expressions`, `particles` lists `{"system", "when"}` for each system that a switch
controls. A system runs while every condition in `when` holds, and stops while any fails, with its
particles cleared, as a GameObject switched off hides them. A `particle` effect,
`{"system", "field", "end", "channel"}`, sets one value:

- `rate`, `distance`, `speed`, `size`, `lifetime` or `gravity` set a curve's `scale`: its low end,
  its high end, or `both`.
- `color` sets one `channel` of the start colour's `end`.
- `material` chooses `renderer.materials[round(value)]`.
- `tint` and `emission` set one `channel` (`emission` has three) of the material's `color` or
  `emission`, whichever material is chosen, as Unity's animator sets it on the drawn one.

A target's default is the value the file saves.

## Drawing

Each system is one MultiMesh. A particle's instance is written once, when it is born: its start
position and velocity, size, rotation, birth time, lifetime, random seed, gravity and colour.
`particle.gdshaderinc` then works out where it is at any age in closed form, so the CPU spends
nothing on a living particle. Godot's own GPUParticles3D lacks emission by distance, Unity's cone and
random-between-two-curves, so the simulation is this one. Life curves reach the shader as a
16-sample float texture (`AvatarParticles.ROW_*`), and velocity and spin carry their integrals. A
sub-emitter's CPU side follows its parent by the same closed form, leaving out the velocity curves
and the noise. Births spend at most `Budget.PARTICLE_BIRTHS_US` of a frame's main thread for each
avatar; the rest wait for the frames after.

## Tests

`tests/test_unity_package.gd` converts a synthetic package with a ParticleSystem and a clip toggling
and recolouring it. `tests/test_avatar_particles.gd` reads a file through `ParticleDefinition`,
refuses malformed systems, emits bursts and sub-emitters and switches a system off and on.
