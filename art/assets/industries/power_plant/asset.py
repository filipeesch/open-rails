"""`power_plant` — coal-fired steam plant: boiler hall, stack, engine room.

A 4.00 x 2.60 tile flagged yard (the industry's 4 x 3 claim, with clearance at
the flanks) walled on three sides, the coal spur running along the open -Y
front — the same rail-side convention the station platform and the mine tipple
use.  Inside it: a long brick boiler hall with a clerestory ridge, a tapering
brick stack at the +X end breeched into the hall, an engine-room annex with a
flywheel and a crosshead rod, a low-walled coal bunker with a tipping grate at
the spur, and an elevated steel water tank on timber trestle.

Reading order at the game's fixed 35.264° pitch is stack (2.20) > clerestory
(1.16) > water tank (0.93) > coal bunker heap (0.47), so the silhouette is nobody
else's: the mine is a timber headframe, the station a low red gable, this is
brick + round tank + one tall tapering stack from all eight 45° snaps.

Colour is the shared vertex-colour material only — `brick_red` walls,
`brick_brown` annex, `roof_dark` roofs, `steel` tank, `iron` machinery, coal
and cast-iron work, `stone` kerb, chimney bands and yard walls.  No company
region: `art-style` reserves the parameterised livery material for rolling
stock and station trim.

The `working` action is the engine room — the flywheel turns while the
crosshead rod slides in its cylinder.  Everything vertical is derived from
`world.toml` through the context (the plot floor is a fraction of one
HEIGHT_STEP, the rails ride `RIDE_HEIGHT_TILES` above it), so a change to the
canonical scale reflows the plant without an edited literal.
"""

from railroad_art.conventions import RAIL_GAUGE_TILES, RIDE_HEIGHT_TILES

# --- plot ---------------------------------------------------------------
# asset.toml `footprint` must match PLOT_L / PLOT_W: the flagged pad and the
# spur rails are what define the declared extents.
PLOT_L = 4.00                      # along +X
PLOT_W = 2.60                      # along +Y
#: Plot floor (kerb/flagging) as a fraction of one HEIGHT_STEP from world.toml.
PAD_STEP_FRACTION = 0.20
STACK_TOP = 2.20                   # stack coping soffit = declared height

# --- boiler hall --------------------------------------------------------
HALL_L, HALL_D, HALL_WALL_H = 1.40, 1.25, 0.66
HALL_CX, HALL_CY = 0.75, 0.225
ROOF_RISE = 0.30
CLEL_L, CLEL_D, CLEL_H = 1.05, 0.22, 0.14
HALL_DOOR_X = 0.19
WINDOW_XS = (0.45, 0.75, 1.05, 1.35)

# --- engine room --------------------------------------------------------
ANNEX_L, ANNEX_D, ANNEX_WALL_H = 0.60, 0.90, 0.44
ANNEX_CX, ANNEX_CY = -0.25, 0.20
FLYWHEEL = (-0.10, 0.655, 0.30)
FLYWHEEL_R = 0.17
ROD_X, ROD_Y, ROD_Z = -0.42, 0.80, 0.26
ROD_TRAVEL_TILES = 0.035

# --- stack --------------------------------------------------------------
STACK_X, STACK_Y = 1.72, 0.225

# --- coal yard ----------------------------------------------------------
BIN_CX, BIN_CY = -1.45, -0.42      # coal heap centre
SPUR_Y = -1.10                     # rail centreline along the open front

# --- water tank ---------------------------------------------------------
TANK_X, TANK_Y, TANK_R = -1.55, 0.40, 0.28


def build(ctx) -> None:
    floor = _plot(ctx)
    _perimeter_walls(ctx, floor)
    _boiler_hall(ctx, floor)
    _engine_room(ctx, floor)
    _stack(ctx, floor)
    _coal_yard(ctx, floor)
    _water_tank(ctx, floor)
    _working_animation(ctx)
    _attachments(ctx, floor)


# --------------------------------------------------------------------------- plot


def _plot(ctx) -> float:
    """Flagged yard, cinder coal ground and the delivery spur.

    Returns the plot floor height: everything on site is stacked from it, and
    it comes out of HEIGHT_STEP rather than a bare number.
    """
    floor = round(ctx.world.height_step * PAD_STEP_FRACTION, 4)

    pad = ctx.box("yard_pad", size=(PLOT_L, PLOT_W, floor), location=(0, 0, floor / 2),
                  colour="stone")
    ctx.paint(pad, "stone", shade=0.74)

    cinder = ctx.box("cinder_yard", size=(1.90, 1.00, 0.012),
                     location=(-0.95, -0.40, floor + 0.006), colour="earth")
    ctx.paint(cinder, "earth", shade=0.58)

    road = ctx.box("spur_road", size=(PLOT_L, 0.34, 0.012),
                   location=(0, SPUR_Y, floor + 0.006), colour="earth")
    ctx.paint(road, "earth", shade=0.46)

    # Sleepers first, then the two rails riding RIDE_HEIGHT_TILES above the
    # plot floor: a lone rail line reads as a cart track, a sleeper row reads
    # as the railway the plant is served by.
    sleeper_z = floor + 0.012 + 0.006
    for i in range(11):
        ctx.box(f"spur_sleeper_{i:02d}", size=(0.055, 0.32, 0.012),
                location=(-1.80 + i * 0.36, SPUR_Y, sleeper_z), colour="wood_dark")

    rail_z = floor + RIDE_HEIGHT_TILES - 0.01
    half = RAIL_GAUGE_TILES / 2
    for tag, y in (("near", SPUR_Y + half), ("far", SPUR_Y - half)):
        ctx.box(f"spur_rail_{tag}", size=(PLOT_L, 0.05, 0.02), location=(0, y, rail_z),
                colour="iron")
    return floor


def _perimeter_walls(ctx, floor) -> None:
    """Low stone yard wall: full length across the back, half length at each
    end, left open on the spur side so wagons can pull in."""
    wall_h = 0.14
    z = floor + wall_h / 2
    back = ctx.box("yard_wall_back", size=(PLOT_L - 0.02, 0.07, wall_h),
                   location=(0, PLOT_W / 2 - 0.035, z), colour="stone")
    ctx.paint(back, "stone", shade=0.94)
    for tag, x in (("west", -PLOT_L / 2 + 0.04), ("east", PLOT_L / 2 - 0.04)):
        wall = ctx.box(f"yard_wall_{tag}", size=(0.07, 1.56, wall_h),
                       location=(x, 0.48, z), colour="stone")
        ctx.paint(wall, "stone", shade=0.94)


# --------------------------------------------------------------------------- buildings


def _boiler_hall(ctx, floor) -> None:
    """Long brick boiler hall: clerestory ridge, tall windows both sides,
    gable-end glazing and a sliding coal door on the spur side."""
    body = ctx.beveled_box("boiler_hall", size=(HALL_L, HALL_D, HALL_WALL_H),
                           location=(HALL_CX, HALL_CY, floor + HALL_WALL_H / 2),
                           colour="brick_red", bevel=0.012)
    ctx.shade_faces_below(body, fraction=0.20, factor=0.84)

    eaves = floor + HALL_WALL_H
    ctx.roof("hall_roof", width=HALL_L + 0.10, depth=HALL_D + 0.12, height=ROOF_RISE,
             location=(HALL_CX, HALL_CY, eaves), colour="roof_dark", ridge_axis="x")

    ridge = eaves + ROOF_RISE
    clere_z = ridge + CLEL_H / 2 - 0.02
    ctx.beveled_box("hall_clerestory", size=(CLEL_L, CLEL_D, CLEL_H),
                    location=(HALL_CX, HALL_CY, clere_z), colour="roof_dark",
                    bevel=0.008)
    ctx.box("clerestory_cap", size=(CLEL_L + 0.06, CLEL_D + 0.08, 0.03),
            location=(HALL_CX, HALL_CY, clere_z + CLEL_H / 2 + 0.015), colour="iron")

    front_y = HALL_CY - HALL_D / 2 - 0.006            # spur-facing wall
    back_y = HALL_CY + HALL_D / 2 + 0.006
    win_z = floor + 0.37
    for tag, x in zip(("a", "b", "c", "d"), WINDOW_XS):
        ctx.box(f"hall_window_south_{tag}", size=(0.09, 0.012, 0.24),
                location=(x, front_y, win_z), colour="glass_fake")
        ctx.box(f"hall_window_north_{tag}", size=(0.09, 0.012, 0.24),
                location=(x, back_y, win_z), colour="glass_fake")
    gable_x = HALL_CX + HALL_L / 2 + 0.006            # valley-facing end
    for tag, y in (("a", -0.12), ("b", 0.57)):
        ctx.box(f"hall_window_gable_{tag}", size=(0.012, 0.09, 0.16),
                location=(gable_x, y, floor + 0.39), colour="glass_fake")

    ctx.box("coal_door", size=(0.26, 0.014, 0.34),
            location=(HALL_DOOR_X, front_y, floor + 0.17), colour="wood_dark")
    ctx.box("coal_door_rail", size=(0.30, 0.02, 0.03),
            location=(HALL_DOOR_X, front_y - 0.004, floor + 0.35), colour="iron")


def _engine_room(ctx, floor) -> None:
    """Lower cross-gabled engine room abutting the hall's up-valley end, with
    the flywheel and the cylinder/crosshead rod proud of its +Y wall."""
    body = ctx.beveled_box("engine_room", size=(ANNEX_L, ANNEX_D, ANNEX_WALL_H),
                           location=(ANNEX_CX, ANNEX_CY, floor + ANNEX_WALL_H / 2),
                           colour="brick_brown", bevel=0.012)
    ctx.shade_faces_below(body, fraction=0.22, factor=0.84)

    ctx.roof("engine_room_roof", width=ANNEX_L + 0.10, depth=ANNEX_D + 0.10,
             height=0.20, location=(ANNEX_CX, ANNEX_CY, floor + ANNEX_WALL_H),
             colour="roof_dark", ridge_axis="y")

    ctx.box("engine_room_door", size=(0.014, 0.18, 0.30),
            location=(ANNEX_CX - ANNEX_L / 2 - 0.006, ANNEX_CY, floor + 0.15),
            colour="wood_dark")

    ctx.cylinder("engine_cylinder", radius=0.06, depth=0.16,
                 location=(ROD_X, 0.69, ROD_Z), colour="iron", sides=8, axis="y")
    ctx._rod = ctx.box("crosshead_rod", size=(0.05, 0.28, 0.05),
                       location=(ROD_X, ROD_Y, ROD_Z), colour="steel")
    ctx._flywheel = ctx.wheel("flywheel", radius=FLYWHEEL_R, width=0.055,
                              location=FLYWHEEL, colour="iron", spokes=6,
                              hub_radius=0.05, web_colour="iron",
                              tyre_colour="steel")


# --------------------------------------------------------------------------- stack


def _stack(ctx, floor) -> None:
    """Tapering brick stack: stone plinth, three chamfered courses, two stone
    bands, an iron coping and a breeching duct into the boiler hall."""
    ctx.beveled_box("stack_plinth", size=(0.40, 0.40, 0.14),
                    location=(STACK_X, STACK_Y, floor + 0.07), colour="stone",
                    bevel=0.012)
    z = floor + 0.14
    course = (0.34, 0.62)
    ctx.beveled_box("stack_course_1", size=(course[0], course[0], course[1]),
                    location=(STACK_X, STACK_Y, z + course[1] / 2), colour="brick_red",
                    bevel=0.010)
    z += course[1]
    ctx.box("stack_band_lower", size=(0.39, 0.39, 0.06),
            location=(STACK_X, STACK_Y, z + 0.03), colour="stone")
    z += 0.06

    course = (0.29, 0.66)
    ctx.beveled_box("stack_course_2", size=(course[0], course[0], course[1]),
                    location=(STACK_X, STACK_Y, z + course[1] / 2), colour="brick_red",
                    bevel=0.010)
    z += course[1]
    ctx.box("stack_band_upper", size=(0.33, 0.33, 0.06),
            location=(STACK_X, STACK_Y, z + 0.03), colour="stone")
    z += 0.06

    top_course = STACK_TOP - z - 0.06
    ctx.beveled_box("stack_course_3", size=(0.24, 0.24, top_course),
                    location=(STACK_X, STACK_Y, z + top_course / 2), colour="brick_red",
                    bevel=0.010)
    z += top_course
    ctx.box("stack_coping", size=(0.30, 0.30, 0.06),
            location=(STACK_X, STACK_Y, z + 0.03), colour="iron")

    ctx.box("stack_breeching", size=(0.26, 0.18, 0.20),
            location=(HALL_CX + HALL_L / 2 + 0.12, STACK_Y, floor + 0.26),
            colour="iron")


# --------------------------------------------------------------------------- coal & water


def _coal_yard(ctx, floor) -> None:
    """Open three-sided coal bunker with a tipping grate at the spur mouth,
    plus delivered heaps on the cinder ground and one at the stack end.

    Deliberately *not* a shed: the mine already owns the roofed-tipple read,
    and a roof would bury the coal at the camera's fixed 35.264° pitch.  Low
    stone walls with the heap mounding over them keeps the black mass — the
    one thing that says what this plant burns — visible from every angle.
    """
    for tag, size, loc in (
        ("west", (0.12, 0.85, 0.30), (-1.79, -0.475)),
        ("north", (0.75, 0.12, 0.30), (-1.475, -0.11)),
    ):
        wall = ctx.box(f"coal_bin_wall_{tag}", size=size,
                       location=(loc[0], loc[1], floor + 0.15), colour="stone")
        ctx.paint(wall, "stone", shade=0.88)

    heap = ctx.beveled_box("coal_heap", size=(0.56, 0.52, 0.42),
                           location=(BIN_CX, BIN_CY, floor + 0.21), colour="iron",
                           bevel=0.05)
    ctx.paint(heap, "iron", shade=0.30)

    # Tipping grate at the bunker mouth, directly off the spur lane — the
    # `unload_point` attachment sits above it.
    ctx.box("coal_tip_sill", size=(0.46, 0.20, 0.02),
            location=(-1.45, -0.80, floor + 0.02), colour="wood_dark")
    ctx.box("coal_tip_grate", size=(0.40, 0.16, 0.04),
            location=(-1.45, -0.80, floor + 0.05), colour="iron")

    for tag, size, loc, shade in (
        ("a", (0.34, 0.30, 0.16), (-0.72, -0.60, 0.08), 0.30),
        ("b", (0.24, 0.22, 0.11), (-0.46, -0.36, 0.055), 0.38),
        # One heap at the stack end, off the spur side: the bunker sits in the
        # far corner and the boiler hall hides it at the default yaw 45°, so
        # the near corner carries the "this burns coal" read for that view.
        ("c", (0.30, 0.26, 0.13), (1.68, -0.55, 0.065), 0.32),
    ):
        pile = ctx.beveled_box(f"coal_pile_{tag}", size=size,
                               location=(loc[0], loc[1], floor + loc[2]),
                               colour="iron", bevel=0.035)
        ctx.paint(pile, "iron", shade=shade)


def _water_tank(ctx, floor) -> None:
    """Elevated steel feed-water tank on a timber trestle, with a standpipe
    and a covered main running into the engine room."""
    for tag, (dx, dy) in (("a", (-0.19, -0.19)), ("b", (0.19, -0.19)),
                          ("c", (-0.19, 0.19)), ("d", (0.19, 0.19))):
        ctx.box(f"tank_leg_{tag}", size=(0.06, 0.06, 0.46),
                location=(TANK_X + dx, TANK_Y + dy, floor + 0.23), colour="wood_dark")
    ctx.box("tank_brace_x", size=(0.42, 0.045, 0.045),
            location=(TANK_X, TANK_Y, floor + 0.25), colour="wood_dark")
    ctx.box("tank_brace_y", size=(0.045, 0.42, 0.045),
            location=(TANK_X, TANK_Y, floor + 0.25), colour="wood_dark")

    body_z = floor + 0.46 + 0.19
    tank = ctx.cylinder("water_tank", radius=TANK_R, depth=0.38,
                        location=(TANK_X, TANK_Y, body_z), colour="steel", sides=12)
    ctx.shade_faces_below(tank, fraction=0.25, factor=0.86)
    ctx.cylinder("water_tank_lid", radius=TANK_R + 0.02, depth=0.035,
                 location=(TANK_X, TANK_Y, body_z + 0.19 + 0.0175), colour="iron",
                 sides=12)
    ctx.cylinder("tank_standpipe", radius=0.035, depth=0.55,
                 location=(TANK_X + 0.22, TANK_Y, floor + 0.275), colour="iron",
                 sides=6)
    ctx.pipe("feed_water_main", radius=0.03, length=0.90,
             location=(-0.92, TANK_Y, floor + 0.09), colour="iron",
             flanges=(0.5,), axis="x", sides=8)


# --------------------------------------------------------------------------- animation


def _working_animation(ctx) -> None:
    action = ctx.anim.action("plant_runs")
    ctx.anim.spin(ctx._flywheel, action, axis="y", turns=1.0)
    ctx.anim.reciprocate(ctx._rod, action, amplitude=ctx.tiles(ROD_TRAVEL_TILES),
                        index=1)
    ctx.anim.register_state("working", "plant_runs")


# --------------------------------------------------------------------------- attachments


def _attachments(ctx, floor) -> None:
    """What the runtime is told about the plant: where coal leaves a wagon on
    the spur, where the delivery cart appears, where the bunker is, who may
    knock, and where the smoke comes out."""
    ctx.attachment("unload_point", (BIN_CX, SPUR_Y, floor + 0.20), kind="cargo")
    ctx.attachment("cart_spawn", (-1.75, SPUR_Y, 0.0), kind="spawn")
    ctx.attachment("coal_bunker", (BIN_CX, BIN_CY, floor + 0.45), kind="cargo")
    ctx.attachment("building_entrance",
                   (HALL_DOOR_X, HALL_CY - HALL_D / 2 - 0.06, floor), kind="entrance")
    ctx.attachment("chimney_smoke", (STACK_X, STACK_Y, STACK_TOP + 0.02), kind="effect")
    ctx.set_extra("industry_role", "coal consumer — boiler hall + beam engine")


def describe() -> str:
    return ("4 x 2.6-tile walled steam plant: brick boiler hall with clerestory, "
            "tapering brick stack, engine room with flywheel, coal bin, steel "
            "water tank on trestle")
