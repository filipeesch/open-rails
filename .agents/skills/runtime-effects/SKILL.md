# runtime-effects

## Purpose
Owns transient runtime effects: locomotive smoke/steam, wheel dust, sparks,
selection glow — created in Godot from attachment-point data, pooled, and
LOD-throttled. These are never baked into GLB animations.

## When to use
Adding an effect to a train/industry/selection, tuning effect density under
stress, or wiring effect LOD tiers to the camera.

## Non-goals
Mechanical animation in assets (`animation-authoring`), particle meshes
exported from Blender (forbidden), UI notifications (also "effects" in
prose — owned by `ui-components`).

## Dependencies
- Manifest attachment points (`chimney_smoke`, `cargo_load_<i>`, coupling
  sockets) — effects attach by name, never by guessed offsets.
- Camera orthographic size + on-screen visibility as the LOD proxy
  (`lod-policy` tiers).
- Godot Compatibility renderer: `GPUParticles3D`/`CPUParticles3D` cheaply,
  no volumetrics, no expensive transparency.

## Invariants
1. Effects never influence simulation: removing every effect changes no
   gameplay outcome (offscreen trains still arrive and earn).
2. Effects are pooled; spawning must not allocate scene nodes per burst at
   gameplay rates.
3. Far distance: particles disabled, update frequency reduced. Offscreen:
   visual animation suspended entirely.
4. Selection feedback is subtle (outline/tint), geometry-based, colour
   accompanied by shape — not a bloom shader (Compatibility renderer).
5. Effect count is bounded by camera distance buckets, not by entity count:
   100 trains in the stress world must not spawn 100 emitters at full rate.

## Public interfaces
`Effects` service under `World3D`:
- `spawn_attached(effect_id, entity_id, attachment)` → pooled handle
  (e.g. `smoke_chimney` on `steam_440` at `chimney_smoke`).
- `set_lod_bucket(handle_or_entity, near|medium|far|offscreen)` driven by
  the renderer/camera proxy.
- `despawn(entity_id)` on train sell/entity removal.
Selection highlight: `set_highlight(entity_id, bool)`.

## Implementation rules
- Steam intensity scales with speed and load; smoke rate rises with
  effort, both reading only *presentation mirrors* of speed (never the
  source of truth for anything).
- Reuse one material + one mesh per effect kind; colour from the palette
  (`iron` greys, `company_primary` for tinted glow).
- Dwell/loading animations play the asset's `loading` action (`animation-
  authoring`), not a particle substitute.
- Keep effect tuning in data (rate, lifetime, gravity) so pacing tweaks
  don't touch code.

## Validation
Stress world at furthest zoom: draw calls and particle counts stay bounded;
`F3` visible-train count vs emitter count confirms throttling. Delete all
effects (debug flag) → integration test outcomes unchanged.

## Common mistakes
- Baking smoke into the locomotive GLB action.
- A new `CPUParticles3D` per train, alive even offscreen.
- Positioning effects by hand-computed local offsets instead of the
  manifest's attachment point.
- Letting effect code read/write domain state "to sync it" — one-way only,
  presentation consumes.

## Related skills
`animation-authoring`, `lod-policy`, `runtime-rendering`, `train-system`,
`performance`, `diagnostics`.
