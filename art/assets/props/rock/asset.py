"""`rock` — Founder's Valley roadside boulder.

Shape language (art-style): a boulder must not read as a stack of crates or as
a plinth with something on top, so this build is organised around *fracture*:

  * two footing blocks on different plan orientations, so the ground line is
    jagged rather than one neat rectangle;
  * a heavy main mass dipped 14° in one elevation and heeled 10° in the other,
    which makes every facet meet the light at its own angle;
  * a block rotated 45° in plan plus a small tilted crest on the summit, so the
    silhouette ends in cleaved corners instead of a flat plateau;
  * a flagstone propped against the flank at 22°, a slumped shelf, and scree
    chips that all lean *against* a block rather than sitting out in the open.

No two blocks share an orientation and nothing lines up vertically — that is
what separates rock from architecture.  Plan-view edges stay axis-aligned or
45° (voxel-modeling invariant 2); the tilts are elevation-only, so the piece
still belongs to the tile grid.

Palette: `stone` carries the form through value contrast (1.00 on the lit
corner down to 0.70 in ground shadow) with one `iron` chip for the coolest,
darkest fragment, plus vertex-baked AO where blocks meet the ground.  One
shared vertex-colour material — no new material, no textures.

Scale: tile units through the context (never a literal tile size), inside the
0.3-tile prop ceiling of `.agents/references/asset-scale.md`; the foot blocks
sink a hair below z = 0 so the boulder reads as bedded, not placed.  Static
decoration — every canonical animation state maps to null.
"""

import math

D45 = math.radians(45.0)
DIP = math.radians(-14.0)        # the mass leans toward +Y …
HEEL = math.radians(10.0)        # … and tips a little along X as well
PROP = math.radians(22.0)        # flagstone propped against the flank
SLUMP = math.radians(16.0)       # shelf slumped against the foot
LOLL = math.radians(8.0)         # crest overhangs its corner block

#: (name, size, location, rotation, colour, shade, bevel) — ground-up.
#:
#: Every block either starts at/below z = 0 or is buried in the block below it
#: (nothing floats, nothing perches).  `bevel` 0 keeps a cleaved facet crisp;
#: only the mass blocks take the small signature chamfer.
BLOCKS = (
    ("foot_a",    (0.215, 0.190, 0.110), (-0.018, -0.028, 0.0550), (0.0, 0.0, 0.0),
     "stone", 0.78, 0.010),
    ("foot_b",    (0.140, 0.122, 0.092), (0.050, 0.050, 0.0460), (0.0, 0.0, D45),
     "stone", 0.88, 0.0),
    ("main_mass", (0.175, 0.146, 0.108), (0.004, -0.006, 0.1260), (DIP, HEEL, 0.0),
     "stone", 0.94, 0.012),
    ("corner",    (0.140, 0.112, 0.082), (0.006, -0.004, 0.1920), (0.0, 0.0, D45),
     "stone", 1.00, 0.010),
    ("crest",     (0.096, 0.082, 0.050), (-0.026, 0.014, 0.2400), (LOLL, 0.0, D45),
     "stone", 0.96, 0.0),
    ("flagstone", (0.048, 0.126, 0.120), (0.080, 0.018, 0.0660), (0.0, PROP, 0.0),
     "stone", 0.84, 0.0),
    ("shelf",     (0.105, 0.048, 0.068), (-0.028, -0.090, 0.0380), (SLUMP, 0.0, 0.0),
     "stone", 0.80, 0.0),
    ("scree_a",   (0.046, 0.038, 0.032), (-0.106, -0.078, 0.0160), (0.0, 0.0, D45),
     "stone", 0.72, 0.0),
    ("scree_b",   (0.040, 0.034, 0.028), (0.066, -0.098, 0.0140), (0.0, 0.0, 0.0),
     "stone", 0.70, 0.0),
    ("scree_c",   (0.036, 0.032, 0.028), (-0.088, 0.056, 0.0140), (0.0, 0.0, D45),
     "iron", 0.90, 0.0),
)


def build(ctx) -> None:
    for name, size, location, rotation, colour, shade, bevel in BLOCKS:
        part = _block(ctx, name, size, location, rotation, colour, bevel)
        ctx.paint(part, colour, shade=shade)
        # Vertex-baked AO only where a block actually meets the ground; upper
        # facets stay bright so the faceted silhouette keeps reading.
        if location[2] - size[2] / 2 < 0.02:
            ctx.shade_faces_below(part, fraction=0.30, factor=0.78)

    ctx.set_extra("silhouette",
                  "jagged footing, dipped mass, 45° cleaved corner and tilted crest, "
                  "propped flagstone, scree against the foot blocks")


def _block(ctx, name, size, location, rotation, colour, bevel):
    if bevel:
        return ctx.beveled_box(name, size=size, location=location, colour=colour,
                               bevel=bevel, rotation=rotation)
    return ctx.box(name, size=size, location=location, colour=colour,
                   rotation=rotation)


def describe() -> str:
    return "fractured boulder: dipped mass, 45° corner + tilted crest, flagstone, scree"
