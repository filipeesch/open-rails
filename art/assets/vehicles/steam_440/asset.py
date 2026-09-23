"""`steam_440` — period American 4-4-0, built entirely from the library's
vehicle composites (frame, boiler, cab, chimney, driving/leading wheel sets).

Authoring conventions (railroad_art.vehicles): forward +X, axle Y, ground
z=0 with wheels resting on the rail head at RIDE_HEIGHT.  Wheel phases are
baked into the spoke geometry, so the `moving` action drives every wheel with
one shared 0→2π ramp and syncs the side rods through `reciprocate` — the
manifest's `wheel_phases` documents the crank offsets for the runtime.

Company livery: buffer beams take the primary region, cab side sheets the
secondary — both exported as shared parameterised materials, never baked
vertex colour.
"""

from railroad_art import vehicles

DRIVER_XS = (-0.05, 0.15)          # two driving axles, phased 0/90
LEAD_XS = (0.35,)                  # leading truck under the smokebox
BOILER_R = 0.14
BOILER_Z = 0.26


def build(ctx) -> None:
    chassis(ctx)
    boiler_unit(ctx)
    cab_unit(ctx)
    running_gear(ctx)
    _moving_animation(ctx)
    _attachments(ctx)


# --------------------------------------------------------------------------- chassis


def chassis(ctx) -> None:
    vehicles.frame(ctx, "frame", length=0.85, width=0.30, height=0.06,
                   loc=(0.0,), colour="iron")
    vehicles.buffer_beams(ctx, "buffer_beam", length=0.03, width=0.45,
                          height=0.16, front_x=0.47, rear_x=-0.47)  # primary
    for tag, x in (("front", 0.485), ("rear", -0.485)):
        ctx.box(f"coupler_{tag}", size=(0.03, 0.08, 0.025),
                location=(x, 0.0, 0.075), colour="iron")


def boiler_unit(ctx) -> None:
    vehicles.boiler(ctx, "boiler", length=0.55, radius=BOILER_R, z=BOILER_Z,
                    x=-0.05, colour="steel", bands=2)
    ctx.pipe("smokebox", radius=0.145, length=0.22, location=(0.33, 0.0, BOILER_Z),
             colour="iron", axis="x", sides=10)
    vehicles.smokebox_front(ctx, "smokebox_front", radius=0.145, x=0.455, z=BOILER_Z)
    vehicles.chimney(ctx, "chimney", radius=0.05, height=0.22, x=0.38,
                     base_z=BOILER_Z + BOILER_R + 0.005)
    vehicles.dome(ctx, "steam_dome", radius=0.05, height=0.07, x=0.0,
                  base_z=BOILER_Z + BOILER_R)
    vehicles.dome(ctx, "sand_dome", radius=0.045, height=0.06, x=-0.16,
                  base_z=BOILER_Z + BOILER_R)
    lamp = ctx.box("headlamp", size=(0.055, 0.055, 0.055),
                   location=(0.45, 0.0, 0.435), colour="iron")
    ctx.tag_company(lamp, "primary")      # company-fitted headlamp


def cab_unit(ctx) -> None:
    parts = vehicles.cab(ctx, "cab", length=0.30, width=0.28, height=0.30,
                         x=-0.34, floor_z=0.10)
    ctx.tag_company(parts["body"], "secondary")       # cab side livery
    riser = ctx.box("tender_riser", size=(0.10, 0.20, 0.14),
                    location=(-0.42, 0.0, 0.17), colour="iron")
    ctx.tag_company(riser, "secondary")


def running_gear(ctx) -> None:
    ctx._drivers = vehicles.add_driving_wheels(ctx, DRIVER_XS)
    ctx._leaders = vehicles.add_leading_wheels(ctx, LEAD_XS)
    rod_y = 0.15 + 0.035 + 0.008                      # outboard of the drivers
    ctx._rod_left = vehicles.side_rod(ctx, "side_rod_left", DRIVER_XS, y=rod_y)
    ctx._rod_right = vehicles.side_rod(ctx, "side_rod_right", DRIVER_XS, y=-rod_y)
    for tag, y in (("l", 0.17), ("r", -0.17)):
        ctx.box(f"cab_step_{tag}", size=(0.07, 0.05, 0.02),
                location=(-0.24, y, 0.09), colour="iron")


# --------------------------------------------------------------------------- animation


def _moving_animation(ctx) -> None:
    action = ctx.anim.action("run")
    for group in (ctx._drivers, ctx._leaders):
        for pair in group.values():
            for wheel in pair.values():
                ctx.anim.spin(wheel, action, axis="y", turns=1.0)
    crank = 0.03 * ctx.world.tile_size
    ctx.anim.reciprocate(ctx._rod_left, action, amplitude=crank, index=0)
    ctx.anim.reciprocate(ctx._rod_right, action, amplitude=crank, index=0)
    ctx.anim.register_state("moving", "run")


def _attachments(ctx) -> None:
    ctx.attachment("smoke_origin", (0.38, 0.0, 0.66), kind="effect")
    ctx.attachment("steam_origin", (0.30, 0.0, 0.18), kind="effect")
    ctx.attachment("coupler_front", (0.52, 0.0, 0.075), kind="coupling")
    ctx.attachment("coupler_rear", (-0.52, 0.0, 0.075), kind="coupling")
    ctx.set_extra("wheel_arrangement", "4-4-0")
