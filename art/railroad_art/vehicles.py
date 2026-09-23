"""Vehicle composite helpers — the vocabulary of rolling stock.

Each composite is expressed with the primitive library only (box, beveled
box, cylinder, pipe, wheel): asset builders for locomotives and wagons call
these helpers and never touch mesh data (art-authoring spec scenario "A
locomotive is built from primitives only").

Orientation: forward +X, rail axis Y, ground z=0; wheel bottoms rest on rail
top at `RIDE_HEIGHT_TILES` above the tile surface, which is the authoring
ground plane for rolling stock.
"""

from __future__ import annotations

from . import primitives as P
from .conventions import (DRIVING_WHEEL_RADIUS_TILES, LEADING_WHEEL_RADIUS_TILES,
                          RAIL_GAUGE_TILES, RIDE_HEIGHT_TILES)


def frame(ctx, name, length, width, height, loc=(0, 0), colour="iron",
          deck_height=None):
    """Buffer-to-buffer chassis frame slab. `loc=(x,z)`; the frame sits with
    its underside at rail height. Returns the frame object."""
    deck = deck_height if deck_height is not None else RIDE_HEIGHT_TILES + height
    obj = P.box(ctx, name, size=(length, width, height),
                location=(loc[0], 0.0, deck - height / 2), colour=colour)
    return obj


def buffer_beams(ctx, name, length, width, height, front_x, rear_x,
                 colour="company"):
    """Pair of chunky buffer beams capping a frame at both ends.  These are
    the classic company-coloured surfaces of period stock."""
    out = []
    for tag, x in (("front", front_x), ("rear", rear_x)):
        obj = P.box(ctx, f"{name}_{tag}", size=(length, width, height),
                    location=(x, 0.0, RIDE_HEIGHT_TILES + height / 2), colour="iron")
        if colour == "company":
            ctx.tag_company(obj, "primary")
        out.append(obj)
    return out


def boiler(ctx, name, length, radius, z, x=0.0, colour="steel",
           bands=2, band_colour="iron", sides=10):
    """Locomotive boiler barrel with flange/band rings; axis along X.
    `z` is the boiler centreline height in tile units."""
    return P.pipe(ctx, name, radius=radius, length=length,
                  location=(x, 0.0, z), colour=colour,
                  flanges=tuple((i + 1) / (bands + 1) for i in range(bands)),
                  axis="x", sides=sides)


def smokebox_front(ctx, name, radius, x, z, colour="iron", sides=10, depth=None):
    """Flat capped front plate of the smokebox — a short fat cylinder on the
    boiler centreline at `x`, facing +X."""
    return P.cylinder(ctx, name, radius=radius * 1.04, depth=depth or radius * 0.25,
                      location=(x, 0.0, z), colour=colour,
                      sides=sides, axis="x")


def cab(ctx, name, length, width, height, x, floor_z, colour="wood_light",
        window_colour="glass_fake", window_size=0.085, roof_overhang=0.02):
    """Chunky cab: floor-height walls + window band + overhanging slab roof.
    Returns dict with parts for further company tagging."""
    parts = {}
    parts["body"] = P.beveled_box(ctx, f"{name}_body",
                                  size=(length, width, height),
                                  location=(x, 0.0, floor_z + height / 2),
                                  colour=colour, bevel=0.01)
    parts["roof"] = P.box(ctx, f"{name}_roof",
                          size=(length + 2 * roof_overhang, width + 2 * roof_overhang,
                                height * 0.10),
                          location=(x, 0.0, floor_z + height + height * 0.05),
                          colour="roof_dark")
    wz = floor_z + height * 0.62
    for tag, wx, wy in (("side_l", x + length * 0.10, width / 2),
                        ("side_r", x + length * 0.10, -width / 2)):
        parts["window_" + tag] = P.box(ctx, f"{name}_window_{tag}",
                                       size=(window_size * 1.6, 0.012, window_size),
                                       location=(wx, wy, wz), colour=window_colour)
    return parts


def chimney(ctx, name, radius, height, x, base_z, colour="iron", cap=True):
    """Balloon/straight stack: flared base cylinder + riser, optional cap."""
    riser = P.cylinder(ctx, f"{name}_riser", radius=radius * 0.75,
                       depth=height, location=(x, 0.0, base_z + height / 2),
                       colour=colour, sides=8, axis="z")
    base = P.cylinder(ctx, f"{name}_flair", radius=radius, depth=height * 0.22,
                      location=(x, 0.0, base_z + height * 0.11),
                      colour=colour, sides=8, axis="z")
    parts = [riser, base]
    if cap:
        parts.append(P.cylinder(ctx, f"{name}_cap", radius=radius * 1.1,
                                depth=height * 0.10,
                                location=(x, 0.0, base_z + height * 0.97),
                                colour=colour, sides=8, axis="z"))
    return parts


def dome(ctx, name, radius, height, x, base_z, colour="steel"):
    """Steam/sand dome slab — a squat cylinder on the boiler crown."""
    return P.cylinder(ctx, name, radius=radius, depth=height,
                      location=(x, 0.0, base_z + height / 2), colour=colour,
                      sides=8, axis="z")


# --------------------------------------------------------------------------- wheel sets


def _wheel_pair(ctx, tag, x, radius, width, phase_deg, colour, tyre_colour,
                y_gauge=None):
    gauge = (y_gauge if y_gauge is not None else RAIL_GAUGE_TILES)
    y_in = gauge / 2 + width / 2
    wheels = {}
    for side, sign in (("left", 1), ("right", -1)):
        w = P.wheel(ctx, f"wheel_{tag}_{side}", radius=radius, width=width,
                    location=(x, sign * y_in, RIDE_HEIGHT_TILES + radius),
                    colour=colour, tyre_colour=tyre_colour, spokes=5,
                    phase_deg=phase_deg if side == "left" else -phase_deg)
        ctx.register_wheel(w, tag, phase_deg, side, radius=radius)
        wheels[side] = w
    return wheels


def add_driving_wheels(ctx, xs, radius=DRIVING_WHEEL_RADIUS_TILES, width=0.035,
                       phases=(0.0, 90.0), colour="iron", tyre_colour="steel"):
    """Driving wheel set: pairs at each `xs`, phased (crank angles) so rods can
    read as mechanical.  Returns {x: {'left': obj, 'right': obj}}."""
    out = {}
    for i, x in enumerate(xs):
        phase = phases[i % len(phases)]
        out[x] = _wheel_pair(ctx, f"driving{i + 1}", x, radius, width, phase,
                             colour, tyre_colour)
    return out


def add_leading_wheels(ctx, xs, radius=LEADING_WHEEL_RADIUS_TILES, width=0.028,
                       phases=(0.0,), colour="iron", tyre_colour="steel"):
    """Small leading/bogbie wheels, same phasing contract as the drivers."""
    out = {}
    for i, x in enumerate(xs):
        phase = phases[i % len(phases)]
        out[x] = _wheel_pair(ctx, f"leading{i + 1}", x, radius, width, phase,
                             colour, tyre_colour)
    return out


def waggon_wheels(ctx, xs, radius=0.05, width=0.025, colour="iron"):
    """Plain spoked wheels for a wagon truck (no crank phasing)."""
    out = {}
    for i, x in enumerate(xs):
        out[x] = _wheel_pair(ctx, f"wheel{i + 1}", x, radius, width, 0.0,
                             colour, None)
    return out


def side_rod(ctx, name, xs, y, radius=DRIVING_WHEEL_RADIUS_TILES,
             crank_radius=0.03, bar=0.016, colour="steel"):
    """Coupling rod bar spanning driving axles `xs` outboard at rail-side `y`.
    The asset script animates its reciprocation with
    `ctx.anim.reciprocate(rod, action, crank_radius)` — the visual of a rod
    read at diorama scale (chunky, mechanical, no micro-detail)."""
    lo, hi = min(xs) - radius * 0.9, max(xs) + radius * 0.9
    z = RIDE_HEIGHT_TILES + radius
    return P.box(ctx, name, size=(hi - lo, bar, bar * 1.4),
                 location=((lo + hi) / 2, y, z), colour=colour)
