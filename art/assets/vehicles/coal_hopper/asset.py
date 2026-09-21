"""`coal_hopper` — open-top iron box car carrying a mounded coal load.

Thick side and end walls at full wagon width, a recessed inner floor, coping
along the top edges, and chunky beveled coal mounds (darkened iron, reading
as anthracite) stacked proud of the rim.  No company livery — hoppers are
road equipment; the manifest's company_regions stays empty.
"""

from railroad_art import vehicles

DECK_Z = 0.08
WALL_H = 0.22
WALL_Y = 0.2075       # side wall centre; outer face lands on ±0.225 exactly


def build(ctx) -> None:
    vehicles.frame(ctx, "frame", length=0.66, width=0.30, height=0.04,
                   loc=(0.0,), colour="iron")
    vehicles.waggon_wheels(ctx, xs=(-0.22, 0.22), radius=0.05, width=0.025)

    for side, sgn in (("l", 1), ("r", -1)):
        ctx.box(f"side_wall_{side}", size=(0.58, 0.035, WALL_H),
                location=(0.0, sgn * WALL_Y, DECK_Z + WALL_H / 2),
                colour="iron")
    for tag, x in (("front", 0.2725), ("rear", -0.2725)):
        ctx.box(f"end_wall_{tag}", size=(0.035, 0.415, WALL_H),
                location=(x, 0.0, DECK_Z + WALL_H / 2), colour="iron")

    floor = ctx.box("inner_floor", size=(0.52, 0.36, 0.05),
                    location=(0.0, 0.0, DECK_Z + 0.025), colour="iron")
    ctx.paint(floor, "iron", shade=0.7)

    rim_z = DECK_Z + WALL_H
    for side, sgn in (("l", 1), ("r", -1)):
        ctx.box(f"coping_{side}", size=(0.58, 0.04, 0.02),
                location=(0.0, sgn * 0.200, rim_z), colour="iron")
        ctx.shade_faces_below(ctx.parts[-1], fraction=0.3, factor=0.8)
        gate = ctx.box(f"discharge_gate_{side}", size=(0.12, 0.010, 0.06),
                       location=(0.0, sgn * 0.219, DECK_Z + 0.05),
                       colour="wood_dark")

    _coal_load(ctx)

    for tag, x in (("front", 0.33), ("rear", -0.33)):
        ctx.box(f"coupler_{tag}", size=(0.04, 0.06, 0.02),
                location=(x, 0.0, 0.06), colour="iron")

    action = ctx.anim.action("roll")
    for obj in ctx.parts:
        if obj.get("rr_kind") == "wheel":
            ctx.anim.spin(obj, action, axis="y", turns=1.0)
    ctx.anim.register_state("moving", "roll")

    ctx.attachment("coupler_front", (0.37, 0.0, 0.06), kind="coupling")
    ctx.attachment("coupler_rear", (-0.37, 0.0, 0.06), kind="coupling")
    ctx.attachment("load_zone", (0.0, 0.0, 0.42), kind="cargo")
    ctx.attachment("unload_chute", (0.0, -0.25, 0.06), kind="cargo")
    ctx.set_extra("cargo", "coal")


def _coal_load(ctx) -> None:
    mounds = (("coal_a", (0.44, 0.34, 0.07), (0.0, 0.0, 0.315), 0.30),
             ("coal_b", (0.30, 0.24, 0.06), (-0.07, 0.04, 0.37), 0.26),
             ("coal_c", (0.16, 0.14, 0.05), (0.09, -0.05, 0.40), 0.34))
    for name, size, loc, shade in mounds:
        mound = ctx.beveled_box(name, size=size, location=loc, colour="stone",
                                bevel=0.02)
        ctx.paint(mound, "iron", shade=shade)
