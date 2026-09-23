# animation-authoring

## Purpose
Owns asset-side (mechanical) animation: canonical animation names, loop
rules, wheel phase, industry animations, and named attachment points. Runtime
effects (smoke, steam, sparks, dust, selection glow) are **not** authored
here — they are created in Godot (`runtime-effects`).

## When to use
When an asset needs moving parts: locomotive wheels/rods, industry pumps,
conveyors, cranes, doors — or when publishing attachment points.

## Non-goals
Particle/effect authoring (`runtime-effects`), runtime playback control from
simulation state (`train-system`, `runtime-rendering`), animation LOD tiers
(`performance`, runtime side).

## Dependencies
- Canonical state contract: `idle`, `moving`, `working`, `loading`,
  `unloading` — assets implement a subset; missing states map to `null`.
- Generated manifest at `game/generated/manifests/<id>.json` carries the
  state→action mapping; runtime never hardcodes Blender action names.
- `gltf-export` for how actions land in the GLB; `voxel-modeling` for the
  parts being moved.

## Invariants
1. The manifest is the only animation-name channel between Blender and the
   runtime; unknown canonical states fail validation.
2. Wheel phase is `distance_travelled / wheel_circumference`; rod loops are
   authored to run on the same normalised phase so wheels never visually
   slide. Presentation computes `fmod(d / (2π·r), 1)` — simulation never
   reads it.
3. Every mechanical animation loops cleanly on an integer frame boundary
   (project decision: 24-frame cycles) with identical first/last poses.
4. Transient effects are never baked into GLB actions.
5. Animated parts are separate named nodes (e.g. `wheel_driving_L`) — an
   animated vertex group inside a static mesh cannot be driven by phase.

## Public interfaces
- Builder API: `train.animate_running()`-style helpers in `railroad_art`
  create the action and register it in the manifest mapping, e.g.
  `{"idle": null, "moving": "Move"}`.
- Attachment points (manifest, asset local space): `chimney_smoke`,
  `coupler_front`, `coupler_rear`, `cargo_load_<i>`.
- Runtime consumers read `manifest.animation_states[state]`,
  `manifest.wheel_circumference_tiles[role]` and `manifest.attachments[name]`.

## Implementation rules
- Name Blender actions after the canonical state they implement, or map
  explicitly; never rename an action without rebuilding.
- **Never name an action with a leading or trailing `loop` / `cycle` token.**
  Godot's glTF importer reads those two tokens out of a clip's name as a playback
  hint and *strips them from the name it files the clip under*: an action
  authored `run_cycle` arrives in the engine as `run`, and the published
  `animation_states` map would then point at a clip that does not exist. The
  importer's hint is worthless here — this library authors looping with cyclic
  keyframes and LINEAR interpolation — so `AnimationRegistry.action()` rejects
  such a name outright. Name the clip for what it is (`run`, `roll`,
  `mine_works`).
- A wheel's crank angle is travelled distance ÷ `wheel_circumference_tiles`,
  wrapped to a turn (spec: "wheels turn because the train moved"). Author the
  `moving` clip as **exactly one revolution** over its loop, so the phase is the
  clip position; `ctx.anim.spin()` and `ctx.register_wheel()` publish the
  circumference with the radius the wheel was built at.
- Animate rotation of wheel objects about their own axis only; drive rods by
  parented empties, not shape keys — shape keys don't survive cheaply.
- Keep action sample rate at project 24 fps (project decision); the runtime
  retimes via phase, so frame count only sets resolution of the loop.
- Industry animation (`working`) must be loopable at any playback rate —
  the runtime drives speed from production state, e.g. conveyor active only
  while `production_rate > 0`.
- Dwell/loading animation (`loading`/`unloading`) is a short prop animation
  (chute arm, crane); cargo quantities themselves are UI/inspector facts.

## The clip only exists once the engine has seen the file
A `.glb` is not loadable until Godot's importer has recorded it beside it
(`<id>.glb.import`). `python tools/rr.py art build` runs that import after any
asset it rebuilt, so `ModelCatalog.has_asset()` is true the moment a build
succeeds; a hand-copied or freshly-synced `.glb` without a sidecar is not — it
reports as unbuilt, and the asset draws its placeholder. An `AnimationPlayer`
is ordinary glTF content, so it shares that rule: the `working` machinery
clips authored here are silently absent until the file is reimported.
Never assert "the asset has no animation" without checking for the sidecar.

## Validation
`python tools/rr.py art validate <id>` checks: action names exist in the GLB,
mapping keys ⊆ canonical states, required `moving` present for vehicles,
loop-closure (first/last pose equal), attachment points listed with local
coordinates. `art preview` shows the asset mid-action.

## Common mistakes
- Playing the "moving" action at a fixed rate — wheels slide; drive from
  wheel phase instead.
- Baking smoke into the action because Blender made it easy.
- One giant action mixing idle sway + running gear; split nodes/actions.
- Forgetting the manifest mapping (`"moving": "Run_Gear"` typo) — validation
  catches it, so never ship unchecked renames.

## Related skills
`train-system`, `runtime-effects`, `gltf-export`, `lod-policy`,
`voxel-modeling`, `asset-validation`.
