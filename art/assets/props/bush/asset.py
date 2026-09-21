"""`bush` — Founder's Valley roadside shrub.

Deliberately NOT a small tree.  `tree` is a trunk with three concentric canopies
stacked on one vertical axis, so it reads as a pin; this asset has no trunk, no
shared axis and no stacking.  It is a *mound* of cabbaged lobes: four squat
foliage lobes sunk into each other around the ground line at different radii,
heights and top levels, then progressively smaller lobes laid over the joints so
no lobe top is left as an exposed flat plateau and no two tops are close enough
to read as one shelf.  The proportions are the inverse of the tree's — 0.252 ×
0.244 across against 0.202 tall — so the pair can never be confused at gameplay
zoom, and because the lobes are placed off-axis the bumpy outline survives all
eight 45° snaps (the runtime also spins every scenery instance, so a bush may
face any way).

Colour does the form reading (art-style: palette value contrast, not
micro-detail): `grass` lobes stepped 0.76…1.00 with vertex-baked AO on every
lobe underside — that dark band in the joints is what keeps nine overlapping
prisms reading as one leafy clump at default zoom — over an `earth` soil disc
that shows in the gaps, and two `wood_dark` stems at the ground line for the
shrub read.  All of it on the one shared vertex-colour material: no new
material, no textures, no transparency.

Scale: octagonal prisms in tile units taken from the context (octagon edges are
axis-aligned or 45°, per voxel-modeling invariant 2), inside the 0.3-tile prop
ceiling of `.agents/references/asset-scale.md`.  Static decoration — every
canonical animation state maps to null.
"""

#: Foliage lobes: (name, location, radius, depth, shade), ground-up, crown last.
#:
#: Each upper lobe is smaller than and sunk deep into the ones it covers, and
#: consecutive lobe top levels are kept at least 0.01 apart so their joints read
#: as leaf tiers instead of hairline slivers.  The four ground lobes are the
#: widest and bound the declared footprint.
LOBES = (
    ("lobe_west",  (-0.046,  0.024, 0.068), 0.082, 0.120, 0.82),
    ("lobe_east",  ( 0.048, -0.026, 0.062), 0.076, 0.112, 0.94),
    ("lobe_north", ( 0.024,  0.056, 0.056), 0.068, 0.100, 0.76),
    ("lobe_south", (-0.022, -0.056, 0.047), 0.064, 0.094, 0.86),
    ("lobe_mid",   (-0.012,  0.010, 0.098), 0.058, 0.100, 0.98),
    ("lobe_inner", ( 0.030, -0.020, 0.119), 0.048, 0.086, 0.90),
    ("lobe_crown", ( 0.000,  0.006, 0.152), 0.038, 0.072, 1.00),
    ("lobe_tuft",  (-0.026,  0.028, 0.179), 0.024, 0.046, 0.86),
)

#: Bare stems poking out at the ground line — the shrub read foliage alone
#: cannot give; they also seat the mound into the soil instead of balancing it.
STEMS = (
    ("stem_east", (0.050,  0.054, 0.032), (0.022, 0.022, 0.056), 0.84),
    ("stem_west", (-0.054, -0.034, 0.030), (0.022, 0.022, 0.052), 0.72),
)

SIDES = 8      # octagonal lobes: the valley's low-poly round shape, nothing curved


def build(ctx) -> None:
    soil = ctx.cylinder("soil_disc", radius=0.072, depth=0.020,
                        location=(0.0, 0.0, 0.010), colour="earth", sides=SIDES)
    ctx.paint(soil, "earth", shade=0.66)

    for name, location, size, shade in STEMS:
        ctx.paint(ctx.box(name, size=size, location=location, colour="wood_dark"),
                  "wood_dark", shade=shade)

    for name, location, radius, depth, shade in LOBES:
        lobe = ctx.cylinder(name, radius=radius, depth=depth, location=location,
                            colour="grass", sides=SIDES)
        ctx.paint(lobe, "grass", shade=shade)
        ctx.shade_faces_below(lobe, fraction=0.45, factor=0.64)

    ctx.set_extra("silhouette", "trunkless cabbage mound of eight offset octagonal lobes, "
                                "soil disc and two stems")


def describe() -> str:
    return "trunkless cabbaged foliage mound, eight octagonal lobes, stems, soil disc"
