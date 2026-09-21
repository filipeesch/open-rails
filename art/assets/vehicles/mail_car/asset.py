"""`mail_car` — Railway Post Office on wheels.

Two small windows (it is a working car, not a palace), a large painted panel
carrying the company livery on both sides, and a roof-mounted mail cube that
makes the silhouette read as "mail" at isometric zoom.
"""

from railroad_art import vehicles

DECK_Z = 0.08
BODY_L, BODY_W, BODY_H = 0.62, 0.42, 0.24


def build(ctx) -> None:
    vehicles.frame(ctx, "frame", length=0.66, width=0.30, height=0.04,
                   loc=(0.0,), colour="iron")
    vehicles.waggon_wheels(ctx, xs=(-0.22, 0.22), radius=0.05, width=0.025)

    body = ctx.beveled_box("body", size=(BODY_L, BODY_W, BODY_H),
                           location=(0.0, 0.0, DECK_Z + BODY_H / 2),
                           colour="wood_dark", bevel=0.010)
    ctx.shade_faces_below(body, fraction=0.25, factor=0.90)

    for side, sgn in (("l", 1), ("r", -1)):
        panel = ctx.box("mail_panel_" + side, size=(0.46, 0.014, 0.11),
                        location=(0.02, sgn * (BODY_W / 2 + 0.006), DECK_Z + 0.13),
                        colour="wood_light")
        ctx.tag_company(panel, "primary")
        ctx.box("window_" + side, size=(0.07, 0.012, 0.07),
                location=(-0.18, sgn * (BODY_W / 2 + 0.007), DECK_Z + 0.15),
                colour="glass_fake")

    ctx.beveled_box("roof", size=(BODY_L + 0.02, BODY_W + 0.02, 0.03),
                    location=(0.0, 0.0, DECK_Z + BODY_H + 0.015),
                    colour="roof_dark", bevel=0.008)
    ctx.beveled_box("mail_cube", size=(0.16, 0.16, 0.06),
                    location=(-0.02, 0.0, DECK_Z + BODY_H + 0.06),
                    colour="wood_light", bevel=0.008)

    for tag, x in (("front", 0.31), ("rear", -0.31)):
        ctx.box(f"end_plate_{tag}", size=(0.02, 0.45, 0.18),
                location=(x, 0.0, DECK_Z + 0.09), colour="wood_dark")
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
    ctx.attachment("cargo_door", (-0.27, 0.25, 0.18), kind="cargo")
    ctx.set_extra("cargo", "mail")
