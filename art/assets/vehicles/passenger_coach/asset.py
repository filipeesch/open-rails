"""`passenger_coach` — varnished-wood coach with a band of windows.

Cargo read: five window bays per side, a boarding door on the +Y platform
side, end plates at full wagon width, plain spoked wheels on a two-axle
truck.  A company-liveried lower panel gives the runtime a tintable band.
"""

from railroad_art import vehicles

FRAME_L = 0.66
BODY_L, BODY_W, BODY_H = 0.62, 0.42, 0.26
DECK_Z = 0.08


def build(ctx) -> None:
    vehicles.frame(ctx, "frame", length=FRAME_L, width=0.30, height=0.04,
                   loc=(0.0,), colour="iron")
    vehicles.waggon_wheels(ctx, xs=(-0.22, 0.22), radius=0.05, width=0.025)

    body = ctx.beveled_box("body", size=(BODY_L, BODY_W, BODY_H),
                           location=(0.0, 0.0, DECK_Z + BODY_H / 2),
                           colour="wood_light", bevel=0.010)
    ctx.shade_faces_below(body, fraction=0.25, factor=0.88)

    for side, sgn in (("l", 1), ("r", -1)):
        w = ctx.box(f"livery_panel_{side}", size=(0.58, 0.014, 0.05),
                    location=(0.0, sgn * (BODY_W / 2 + 0.006), DECK_Z + 0.055),
                    colour="wood_light")
        ctx.tag_company(w, "secondary")

    _windows_and_door(ctx)

    ctx.beveled_box("roof", size=(BODY_L + 0.02, BODY_W + 0.02, 0.03),
                    location=(0.0, 0.0, DECK_Z + BODY_H + 0.015),
                    colour="roof_dark", bevel=0.008)

    for tag, x in (("front", 0.31), ("rear", -0.31)):
        ctx.box(f"end_plate_{tag}", size=(0.02, 0.45, 0.20),
                location=(x, 0.0, DECK_Z + 0.10), colour="wood_dark")
    for tag, x in (("front", 0.33), ("rear", -0.33)):
        ctx.box(f"coupler_{tag}", size=(0.04, 0.06, 0.02),
                location=(x, 0.0, 0.06), colour="iron")

    _moving_animation(ctx)
    ctx.attachment("coupler_front", (0.37, 0.0, 0.06), kind="coupling")
    ctx.attachment("coupler_rear", (-0.37, 0.0, 0.06), kind="coupling")
    ctx.attachment("cargo_door", (0.27, 0.25, 0.20), kind="cargo")
    ctx.set_extra("cargo", "passengers")


def _windows_and_door(ctx) -> None:
    y_face = BODY_W / 2 + 0.006
    for side, sgn in (("l", 1), ("r", -1)):
        for i, wx in enumerate((-0.24, -0.12, 0.0, 0.12, 0.24)):
            if side == "l" and wx == 0.24:
                continue          # boarding door takes this bay
            ctx.box(f"window_{side}_{i}", size=(0.07, 0.012, 0.07),
                    location=(wx, sgn * y_face, DECK_Z + 0.16),
                    colour="glass_fake")
    ctx.box("boarding_door", size=(0.09, 0.012, 0.17),
            location=(0.24, y_face + 0.001, DECK_Z + 0.095), colour="wood_dark")


def _moving_animation(ctx) -> None:
    action = ctx.anim.action("roll")
    for obj in ctx.parts:
        if obj.get("rr_kind") == "wheel":
            ctx.anim.spin(obj, action, axis="y", turns=1.0)
    ctx.anim.register_state("moving", "roll")
