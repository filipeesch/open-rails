# Visual Style

Shared facts about how the game must look. Values here are drawn from
`docs/requirements/v1.md` (V1 spec); choices the spec leaves open are marked
**project decision**.

## Identity

The game should feel like an interactive miniature railway diorama:
isometric presentation, voxel-inspired geometry, stylized low-poly modeling,
strong silhouettes, a restrained color palette, miniature proportions, and
smooth mechanical animation inviting close inspection of trains and
industries.

## Geometry language (spec §20)

Use: chunky geometry, clean silhouettes, small bevels, simple cylinders,
low-poly curves, a limited palette, visibly geometric construction.
Avoid: photorealism, micro-detail, tiny geometry, complex textures,
high-frequency surface detail.

Rule of thumb: detail must survive at gameplay zoom. If it cannot be seen at
the closest supported gameplay zoom (≈4 tiles tall on screen), it usually
should not exist.

## Color and materials

- One canonical palette (see `material-palette.md`); most opaque assets share
  one vertex-color material. Unique materials per asset are prohibited.
- Textures are exceptional: no 4K textures, no normal maps.
- Windows are stylized opaque or mildly emissive (`glass_fake`); real
  transparent glass is not required.
- Company liveries use the shared `company_primary` / `company_secondary`
  parameterised material, tintable at runtime.

## Lighting (spec §18)

Exactly: 1 `DirectionalLight3D`, an ambient environment, and vertex-baked
ambient-occlusion-style shading (baked into vertex color at asset generation
time). No dynamic GI, no point lights for normal buildings, limited shadow
distance, and far scenery may disable shadows.

## Water (spec §10)

A cheap colored plane or chunked surface with optional lightweight movement.
No reflection, no refraction, no simulation.

## Runtime renderer (spec §19)

Godot **Compatibility** renderer (`gl_compatibility`, already set in
`game/project.godot`). No dependency on Forward+-only features; keep Mobile
benchmarking easy. Prefer geometry, vertex colors, shared materials,
instancing, simple directional lighting, LOD, and frustum culling.

## Camera framing (spec §12–13)

Orthographic; default yaw 45°, pitch fixed at 35.264°; full 360° yaw with
45° snaps; zoom (orthographic size) from 4 tiles (closest) through 28 tiles
(default) to 96 tiles (furthest), logarithmic. Close zoom must clearly show
locomotive wheels, windows, connecting rods, station detail, machinery,
individual wagons and loading areas — model detail is sized for that view.

## Historical stylization

V1 starts in 1850; content is a 4-4-0 American steam locomotive, a small
station, coal mines and power plants in a mid-19th-century American valley
("Founder's Valley"). Stylized rather than accurate; silhouettes should read
as period-appropriate (wood, brick, iron — no modern materials).

## Project decisions (spec silent)

- Sky/ambient: flat ambient color plus directional light; no sky textures,
  no day/night cycle in V1 (already excluded by spec §115).
- Outline/selection highlight is a subtle tint/outline, not a full-screen
  post-process — Compatibility renderer has cheap geometry-based options.
- Company default colors: `company_primary` deep red, `company_secondary`
  cream (see `material-palette.md`).
