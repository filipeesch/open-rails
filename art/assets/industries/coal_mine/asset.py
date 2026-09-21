"""`coal_mine` — deep-shaft coal industry with a `working` animation.

Headframe with spinning sheave wheel, coal bunker with a reciprocating
screening chute, a conveyor to the tipple shed, coal piles, a boiler hut and
a spur rail running the full 3.0-tile footprint.  The working action combines
sheave rotation and chute shake; the manifest publishes it under the
canonical `working` state.
"""

SHAFT_X = -1.05


def build(ctx) -> None:
    _spur_track(ctx)
    _headframe(ctx)
    _bunker_and_conveyor(ctx)
    _tipple_shed(ctx)
    _coal_piles(ctx)
    _boiler_hut(ctx)
    _working_animation(ctx)
    _attachments(ctx)


# --------------------------------------------------------------------------- parts


def _spur_track(ctx) -> None:
    rail = ctx.box("spur_rail", size=(3.00, 0.05, 0.02), location=(0, -0.75, 0.01),
                   colour="iron")
    ctx.paint(rail, "iron", shade=0.85)


def _headframe(ctx) -> None:
    leg_z, leg_h = 0.65, 1.30
    for tag, dx, dy in (("a", -0.22, 0.18), ("b", 0.22, 0.18),
                        ("c", -0.22, -0.18), ("d", 0.22, -0.18)):
        ctx.cylinder(f"headframe_leg_{tag}", radius=0.035, depth=leg_h,
                     location=(SHAFT_X + dx, dy, leg_z), colour="wood_dark", sides=6)
    ctx.beveled_box("headframe_top", size=(0.56, 0.46, 0.07),
                    location=(SHAFT_X, 0, leg_z + leg_h / 2 + 0.02),
                    colour="wood_light", bevel=0.008)
    ctx.box("headframe_brace", size=(0.50, 0.05, 0.05),
            location=(SHAFT_X, 0, 0.55), colour="wood_dark")
    ctx.box("shaft_collar", size=(0.34, 0.34, 0.10), location=(SHAFT_X, 0, 0.05),
            colour="stone")

    ctx._sheave = ctx.wheel("sheave_wheel", radius=0.18, width=0.05,
                            location=(SHAFT_X, 0, 1.45), colour="wood_light",
                            spokes=4, hub_radius=0.05)


def _bunker_and_conveyor(ctx) -> None:
    bunker = ctx.beveled_box("bunker", size=(0.55, 0.70, 0.50),
                             location=(-0.30, 0.0, 0.25), colour="wood_light",
                             bevel=0.012)
    ctx.shade_faces_below(bunker, fraction=0.2, factor=0.85)
    ctx.box("bunker_hopper", size=(0.30, 0.45, 0.14), location=(-0.30, 0.0, 0.57),
            colour="wood_dark")

    ctx._screen = ctx.box("screen_chute", size=(0.14, 0.55, 0.09),
                          location=(-0.62, 0.0, 0.20), colour="wood_dark")

    ctx.pipe("conveyor", radius=0.11, length=0.90, location=(0.15, 0.0, 0.55),
             colour="iron", flanges=(0.5,), axis="x", sides=8)
    for tag, x in (("a", -0.12), ("b", 0.42)):
        ctx.box(f"conveyor_post_{tag}", size=(0.05, 0.05, 0.50),
                location=(x, 0.0, 0.25), colour="wood_dark")


def _tipple_shed(ctx) -> None:
    shed = ctx.beveled_box("tipple_shed", size=(1.30, 1.80, 0.55),
                           location=(0.78, 0.0, 0.275), colour="wood_light",
                           bevel=0.012)
    ctx.shade_faces_below(shed, fraction=0.18, factor=0.86)
    ctx.roof("tipple_roof", width=1.40, depth=2.00, height=0.35,
             location=(0.78, 0.0, 0.55), colour="roof_dark", ridge_axis="y")
    ctx.box("tipple_door", size=(0.014, 0.30, 0.26), location=(0.13, 0.45, 0.17),
            colour="wood_dark")
    ctx.box("tipple_chute", size=(0.30, 0.24, 0.10), location=(0.05, 0.0, 0.30),
            colour="iron")


def _coal_piles(ctx) -> None:
    piles = (("pile_a", (0.55, 0.50, 0.18), (1.05, -0.55, 0.09), 0.26),
             ("pile_b", (0.40, 0.35, 0.14), (0.82, -0.72, 0.07), 0.30),
             ("pile_c", (0.30, 0.30, 0.12), (1.22, -0.82, 0.06), 0.34))
    for name, size, loc, shade in piles:
        pile = ctx.beveled_box(name, size=size, location=loc, colour="stone",
                               bevel=0.03)
        ctx.paint(pile, "iron", shade=shade)


def _boiler_hut(ctx) -> None:
    ctx.box("boiler_hut", size=(0.40, 0.40, 0.34), location=(-0.70, -0.65, 0.17),
            colour="brick_brown")
    ctx.roof("boiler_hut_roof", width=0.46, depth=0.46, height=0.12,
             location=(-0.70, -0.65, 0.34), colour="roof_dark", ridge_axis="x")
    ctx.cylinder("boiler_steam_pipe", radius=0.025, depth=0.30,
                 location=(-0.58, -0.52, 0.45), colour="iron", sides=6)


# --------------------------------------------------------------------------- animation


def _working_animation(ctx) -> None:
    action = ctx.anim.action("mine_works")
    ctx.anim.spin(ctx._sheave, action, axis="y", turns=2.0)
    ctx.anim.reciprocate(ctx._screen, action, amplitude=ctx.tiles(0.035))
    ctx.anim.register_state("working", "mine_works")


def _attachments(ctx) -> None:
    ctx.attachment("load_point", (0.60, -0.35, 0.25), kind="cargo")
    ctx.attachment("cart_spawn", (SHAFT_X, -0.55, 0.0), kind="spawn")
    ctx.set_extra("industry_role", "coal producer — deep shaft + tipple")
