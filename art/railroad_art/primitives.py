"""Chunky low-poly primitives.

Every primitive:
  * takes sizes/locations in **tile units** and converts through the context's
    world scale (so `world.toml` remains the only source of TILE_SIZE);
  * produces ONE mesh object whose faces carry baked palette vertex colours
    (faces are unshared, so flat colour never bleeds across a hard edge);
  * is registered with the context as an LOD0 part and named cleanly for the
    exported GLB.

Geometry convention: the asset origin sits at the footprint centre on the
ground plane, +Z up; rolling stock runs along +X with wheel axles along Y.
Locations passed to primitives are the object origin, in tile units.
"""

from __future__ import annotations

import math

import bmesh  # only ever present inside Blender

from . import blender_util as bu


def _m(ctx, v):
    """Tile units -> metres (scalar or sequence)."""
    if isinstance(v, (tuple, list)):
        return tuple(float(c) * ctx.world.tile_size for c in v)
    return float(v) * ctx.world.tile_size


class _Shell:
    """Accumulates polygon vertices and exact per-part face ranges so each
    part of a multi-colour primitive knows which polygons to paint."""

    def __init__(self):
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.parts: list[tuple[tuple[int, int], object]] = []

    # -- parts ----------------------------------------------------------------

    def add_cylinder(self, colour, radius, half_depth, sides, offset=(0.0, 0.0, 0.0),
                     axis="z"):
        """Closed cylinder shell along `axis` ('x' | 'y' | 'z')."""
        n = max(3, int(sides))
        start = len(self.faces)
        ring_a, ring_b = [], []
        for i in range(n):
            a = 2 * math.pi * i / n
            p, q = radius * math.cos(a), radius * math.sin(a)
            if axis == "z":
                ring_a.append((p + offset[0], q + offset[1], -half_depth + offset[2]))
                ring_b.append((p + offset[0], q + offset[1], half_depth + offset[2]))
            elif axis == "x":
                ring_a.append((-half_depth + offset[0], p + offset[1], q + offset[2]))
                ring_b.append((half_depth + offset[0], p + offset[1], q + offset[2]))
            else:  # y
                ring_a.append((p + offset[0], -half_depth + offset[1], q + offset[2]))
                ring_b.append((p + offset[0], half_depth + offset[1], q + offset[2]))
        base = len(self.verts)
        self.verts.extend(ring_a)
        self.verts.extend(ring_b)
        for i in range(n):
            j = (i + 1) % n
            self.faces.append((base + i, base + j, base + n + j, base + n + i))
        self.faces.append(tuple(reversed(range(base, base + n))))
        self.faces.append(tuple(range(base + n, base + 2 * n)))
        self.parts.append(((start, len(self.faces) - start), colour))

    def add_box(self, colour, centre, size, rotation_z=0.0):
        """Closed box shell, `size` full extents, optional rotation about Z."""
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        start = len(self.faces)
        base = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
                (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]
        if rotation_z:
            ca, sa = math.cos(rotation_z), math.sin(rotation_z)
            base = [(x * ca - y * sa + centre[0], x * sa + y * ca + centre[1], z + centre[2])
                    for (x, y, z) in base]
        else:
            base = [(x + centre[0], y + centre[1], z + centre[2]) for (x, y, z) in base]
        v0 = len(self.verts)
        self.verts.extend(base)
        for quad in [(4, 5, 1, 0), (7, 6, 2, 3), (5, 6, 7, 4), (0, 1, 2, 3),
                     (1, 5, 6, 2), (3, 7, 4, 0)]:
            self.faces.append(tuple(i + v0 for i in quad))
        self.parts.append(((start, len(self.faces) - start), colour))

    def add_prism(self, colour, rect_hw, rect_hd, height, ridge="x"):
        """Gable roof prism: eaves rectangle ±hw(x) ±hd(y) at z=0; ridge runs
        along `ridge` ("x"|"y"), centred, peaking at z=height.  Closed; winding
        corrected later by recalc_face_normals."""
        hw, hd, h = rect_hw, rect_hd, height
        start = len(self.faces)
        v0 = len(self.verts)
        base = [(-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0)]
        if ridge == "x":
            apex = [(-hw, 0, h), (hw, 0, h)]
            faces = [(0, 1, 2, 3), (0, 1, 5, 4), (2, 3, 4, 5), (0, 3, 4), (1, 5, 2)]
        else:
            apex = [(0, -hd, h), (0, hd, h)]
            faces = [(0, 1, 2, 3), (1, 2, 5, 4), (0, 4, 5, 3), (0, 1, 4), (3, 2, 5)]
        self.verts.extend(base + apex)
        for face in faces:
            self.faces.append(tuple(i + v0 for i in face))
        self.parts.append(((start, len(self.faces) - start), colour))

    # -- baking ----------------------------------------------------------------

    def build_raw(self, obj):
        """Write geometry, recalc normals (shared topology kept)."""
        mesh = obj.data
        mesh.from_pydata(self.verts, [], self.faces)
        mesh.validate()
        mesh.update()
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()

    def build_unshared(self, obj):
        """As build_raw, then split faces so each owns its vertices."""
        self.build_raw(obj)
        bu.unshare_mesh(obj)
        bu.ensure_vertex_colour_attribute(obj.data)

    def paint(self, obj):
        attr = obj.data.color_attributes["Col"]
        for (start, count), colour in self.parts:
            for fi in range(start, min(start + count, len(obj.data.polygons))):
                for loop_idx in obj.data.polygons[fi].loop_indices:
                    attr.data[loop_idx].color = (colour[0], colour[1], colour[2], 1.0)
        obj.data.update()


def _finish(ctx, name, shell, location=(0, 0, 0), rotation=(0, 0, 0)):
    obj = bu.new_mesh_object(name, [], [])
    shell.build_unshared(obj)
    obj.data.materials.append(ctx.materials.vertex_colour)
    shell.paint(obj)
    obj.location = _m(ctx, location)
    obj.rotation_euler = tuple(rotation)
    ctx.register_part(obj)
    return obj


# --------------------------------------------------------------------------- boxes


def box(ctx, name, size, location=(0, 0, 0), colour="wood_light", rotation=(0, 0, 0)):
    """Chunky box, `size=(dx,dy,dz)` tile units, origin at the box centre."""
    shell = _Shell()
    shell.add_box(ctx.palette.colour(colour), (0, 0, 0), _m(ctx, size))
    return _finish(ctx, name, shell, location, rotation)


def beveled_box(ctx, name, size, location=(0, 0, 0), colour="wood_light",
                bevel=0.015, rotation=(0, 0, 0)):
    """Box with a small chamfer — the signature silhouette softener.  The
    bevel is applied on shared topology, then the mesh is split and painted."""
    shell = _Shell()
    shell.add_box(ctx.palette.colour(colour), (0, 0, 0), _m(ctx, size))
    obj = bu.new_mesh_object(name, [], [])
    shell.build_raw(obj)
    bu.bevel(obj, _m(ctx, bevel))
    bu.apply_modifiers(obj)
    bu.unshare_mesh(obj)
    bu.ensure_vertex_colour_attribute(obj.data)
    obj.data.materials.append(ctx.materials.vertex_colour)
    bu.paint_all_face_loops(obj, ctx.palette.colour(colour))
    obj.location = _m(ctx, location)
    obj.rotation_euler = tuple(rotation)
    ctx.register_part(obj)
    return obj


# --------------------------------------------------------------------------- cylinders / pipes


def cylinder(ctx, name, radius, depth, location=(0, 0, 0), colour="iron",
             sides=10, axis="z", rotation=(0, 0, 0)):
    """Low-poly cylinder along `axis`."""
    shell = _Shell()
    shell.add_cylinder(ctx.palette.colour(colour), _m(ctx, radius),
                       _m(ctx, depth) / 2, sides, axis=axis)
    return _finish(ctx, name, shell, location, rotation)


def pipe(ctx, name, radius, length, location=(0, 0, 0), colour="iron",
         flanges=(), flange_radius=None, axis="x", sides=10):
    """Cylinder along `axis` with flange rings at fractional positions along
    its length — boiler barrels, standpipes, steam lines."""
    shell = _Shell()
    c = ctx.palette.colour(colour)
    r = _m(ctx, radius)
    ln = _m(ctx, length)
    fr = _m(ctx, flange_radius if flange_radius is not None else radius * 1.3)
    shell.add_cylinder(c, r, ln / 2, sides, axis=axis)
    for frac in flanges:
        off = -ln / 2 + frac * ln
        o = (off, 0, 0) if axis == "x" else (0, 0, off) if axis == "z" else (0, off, 0)
        shell.add_cylinder(c, fr, max(ln * 0.02, r * 0.06), sides, offset=o, axis=axis)
    return _finish(ctx, name, shell, location)


# --------------------------------------------------------------------------- roofs


def roof(ctx, name, width, depth, height, location=(0, 0, 0), colour="roof_red",
         ridge_axis="x"):
    """Gable roof; origin at the eaves centre (base plane), ridge along
    `ridge_axis`.  `width` spans X, `depth` spans Y."""
    shell = _Shell()
    shell.add_prism(ctx.palette.colour(colour), _m(ctx, width) / 2,
                    _m(ctx, depth) / 2, _m(ctx, height), ridge=ridge_axis)
    return _finish(ctx, name, shell, location)


# --------------------------------------------------------------------------- wheels


def wheel(ctx, name, radius, width, location=(0, 0, 0), colour="iron",
          spokes=4, hub_radius=None, tyre_colour=None, web_colour=None,
          phase_deg=0.0):
    """Railway wheel, axle along +Y: tyre ring, recessed web, optional flat
    spokes and a hub.  `phase_deg` rotates the spoke pattern in-plane — this
    is how wheels are visually phased without touching the base transform
    (which the rolling animation owns)."""
    shell = _Shell()
    r = _m(ctx, radius)
    w = _m(ctx, width)
    n = 12
    tyre = ctx.palette.colour(tyre_colour) if tyre_colour else ctx.palette.colour(colour)
    body = ctx.palette.colour(web_colour) if web_colour else ctx.palette.colour(colour)

    def ring_pair(base_r, half_w):
        lo = len(shell.verts)
        for i in range(n):
            a = 2 * math.pi * i / n
            shell.verts.append((base_r * math.cos(a), -half_w, base_r * math.sin(a)))
        hi = len(shell.verts)
        for i in range(n):
            a = 2 * math.pi * i / n
            shell.verts.append((base_r * math.cos(a), half_w, base_r * math.sin(a)))
        return lo, hi

    # tyre
    start = len(shell.faces)
    lo, hi = ring_pair(r, w / 2)
    for i in range(n):
        j = (i + 1) % n
        shell.faces.append((lo + i, lo + j, hi + j, hi + i))
    shell.faces.append(tuple(reversed(range(lo, lo + n))))
    shell.faces.append(tuple(range(hi, hi + n)))
    shell.parts.append(((start, len(shell.faces) - start), tyre))

    # recessed web (inward-wound so recalc orients it consistently with a
    # visibly darker silhouette band around the rim)
    inner_r, inner_w = r * 0.62, w * 0.30
    start = len(shell.faces)
    lo2, hi2 = ring_pair(inner_r, inner_w)
    for i in range(n):
        j = (i + 1) % n
        shell.faces.append((lo2 + j, lo2 + i, hi2 + i, hi2 + j))
    shell.faces.append(tuple(range(lo2, lo2 + n)))
    shell.faces.append(tuple(reversed(range(hi2, hi2 + n))))
    shell.parts.append(((start, len(shell.faces) - start), body))

    # spokes (box shells in the wheel plane)
    if spokes:
        sw = max(_m(ctx, 0.006), r * 0.12)
        hw = w * 0.42
        a0 = math.radians(phase_deg)
        for k in range(spokes):
            a = a0 + math.pi * k / spokes
            dirx, dirz = math.cos(a), math.sin(a)
            px, pz = -dirz, dirx
            length = r * 0.62
            start = len(shell.faces)
            v0 = len(shell.verts)
            pts = []
            for s in (-1, 1):
                for t in (-1, 1):
                    for along in (-length, length):
                        pts.append((dirx * along + px * sw * t, hw * s,
                                    dirz * along + pz * sw * t))
            shell.verts.extend(pts)
            for quad in [(0, 1, 3, 2), (7, 5, 4, 6), (4, 5, 1, 0), (2, 3, 7, 6),
                         (0, 2, 6, 4), (1, 3, 7, 5)]:
                shell.faces.append(tuple(i + v0 for i in quad))
            shell.parts.append(((start, len(shell.faces) - start), body))

    # hub
    hr = _m(ctx, hub_radius if hub_radius is not None else radius * 0.22)
    shell.add_cylinder(body, hr, w * 0.60, 8, axis="y")

    obj = _finish(ctx, name, shell, location)
    obj["rr_kind"] = "wheel"
    return obj
