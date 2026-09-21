"""`tree` — Founder's Valley roadside tree.

Shape language (art-style): chunky octagonal blobs stacked into a slightly
asymmetric canopy on a stub trunk; no smooth shading, no micro-detail.
Palette: wood_dark trunk, grass canopy with vertex-baked AO on the underside
of each blob.  Fully static — the manifest maps every canonical animation
state to null.
"""


def build(ctx) -> None:
    ctx.cylinder("trunk", radius=0.055, depth=0.50, location=(0.0, 0.0, 0.25),
                 colour="wood_dark", sides=8)

    # (name, radius, depth, centre z, shade) — stacked canopy, wide to tall
    canopy = (
        ("canopy_low", 0.36, 0.34, 0.62, 0.80),
        ("canopy_mid", 0.30, 0.30, 0.86, 0.90),
        ("canopy_top", 0.20, 0.26, 1.06, 1.00),
    )
    for name, radius, depth, z, shade in canopy:
        blob = ctx.cylinder(name, radius=radius, depth=depth, location=(0.0, 0.0, z),
                            colour="grass", sides=8)
        ctx.paint(blob, "grass", shade=shade)
        ctx.shade_faces_below(blob, fraction=0.35, factor=0.78)

    ctx.set_extra("silhouette", "stacked octagonal canopy, 8-sided trunk")
