"""`house` — Founder's Valley small house.

One storey on a stone footing, chamfered timber body, red gable roof with a
ridge cap, brick chimney, front door and fake-glass windows on the +X (street)
face and both sides.  Everything sits inside the roof rectangle so the
declared footprint equals the roof extents.  Static asset: no animation.
"""

ROOF_W = 0.70      # along X — footprint length
ROOF_D = 0.58      # along Y — footprint width
WALL_H = 0.30
FLOOR_Z = 0.06     # top of the stone footing


def build(ctx) -> None:
    footing = ctx.box("footing", size=(0.64, 0.52, FLOOR_Z), location=(0, 0, FLOOR_Z / 2),
                      colour="stone")
    ctx.paint(footing, "stone", shade=0.82)

    body = ctx.beveled_box("body", size=(0.60, 0.48, WALL_H),
                           location=(0, 0, FLOOR_Z + WALL_H / 2),
                           colour="wood_light", bevel=0.012)
    ctx.shade_faces_below(body, fraction=0.20, factor=0.86)

    wall_top = FLOOR_Z + WALL_H                       # 0.36
    ctx.roof("roof", width=ROOF_W, depth=ROOF_D, height=0.20,
             location=(0, 0, wall_top), colour="roof_red", ridge_axis="x")
    ctx.beveled_box("ridge_cap", size=(ROOF_W, 0.05, 0.035),
                    location=(0, 0, wall_top + 0.20), colour="roof_dark", bevel=0.006)

    # brick chimney at -X / +Y corner, cap tops out at 0.61 = declared height
    ctx.beveled_box("chimney", size=(0.08, 0.08, 0.34),
                    location=(-0.20, 0.10, 0.42), colour="brick_red", bevel=0.006)
    ctx.box("chimney_cap", size=(0.11, 0.11, 0.03),
            location=(-0.20, 0.10, 0.605), colour="stone")

    _windows_and_door(ctx)


def _windows_and_door(ctx) -> None:
    front_x = 0.30 + 0.006                            # just proud of the +X wall
    ctx.box("door", size=(0.012, 0.09, 0.18), location=(front_x, 0.0, 0.15),
            colour="wood_dark")
    ctx.box("step", size=(0.05, 0.14, 0.04), location=(0.325, 0.0, 0.02),
            colour="stone")
    for tag, wx, wy, size in (
        ("front_l", front_x, -0.16, (0.012, 0.09, 0.09)),
        ("front_r", front_x, 0.16, (0.012, 0.09, 0.09)),
        ("side_a_l", -0.14, 0.24 + 0.006, (0.09, 0.012, 0.09)),
        ("side_a_r", 0.14, 0.24 + 0.006, (0.09, 0.012, 0.09)),
        ("side_b_l", -0.14, -(0.24 + 0.006), (0.09, 0.012, 0.09)),
        ("side_b_r", 0.14, -(0.24 + 0.006), (0.09, 0.012, 0.09)),
    ):
        ctx.box("window_" + tag, size=size,
                location=(wx, wy, FLOOR_Z + 0.16), colour="glass_fake")


def describe() -> str:
    return "1-tile gable house, wood_light body, roof_red roof, brick chimney"
