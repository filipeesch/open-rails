"""LOD assembly: LOD0 = authored parts; LOD1/LOD2 = merged, auto-reduced copies
(or manual override sets supplied by the asset).

The GLB therefore contains sibling nodes named ``LOD0``/``LOD1``/``LOD2``;
``LOD0`` keeps per-part objects (so wheels can animate), reduced levels are
single static meshes — major geometry at LOD1, silhouette + colour at LOD2.
Reduction ratios are *cumulative against LOD0*; a level that fails to drop
strictly below its predecessor is re-reduced until monotonicity holds.
"""

from __future__ import annotations

import bpy

from . import blender_util as bu

MIN_RATIO = 0.03


class LodNode:
    """A named LOD root with its published triangle count."""

    def __init__(self, obj, tri_count: int):
        self.obj = obj
        self.tri_count = tri_count

    @property
    def name(self) -> str:
        return self.obj.name


def assemble(ctx) -> dict[str, LodNode]:
    """Parent all LOD0 parts under a `LOD0` empty; build reduced levels."""
    nodes: dict[str, LodNode] = {}

    lod0 = bpy.data.objects.new("LOD0", None)
    ctx.scene.collection.objects.link(lod0)
    for obj in ctx.parts:
        if obj.parent is None:
            obj.parent = lod0
            obj.matrix_parent_inverse = lod0.matrix_world.inverted()
    nodes["LOD0"] = LodNode(lod0, _subtree_tris(lod0))

    levels = max(1, min(3, ctx.lod_levels))
    prev_tris = nodes["LOD0"].tri_count
    for level in range(1, levels):
        name = f"LOD{level}"
        override = ctx.lod_overrides.get(level)
        if override:
            obj = _merge_objects(name, override, decimate_ratio=None)
            obj.hide_render = True
        else:
            if not ctx.lod_auto:
                continue
            ratio = ctx.lod_ratios[min(level, len(ctx.lod_ratios)) - 1]
            obj = _merge_objects(name, ctx.parts, decimate_ratio=ratio,
                                 min_tris_below=prev_tris)
            obj.hide_render = True
        if obj is None or obj.data is None or len(obj.data.polygons) == 0:
            continue
        nodes[name] = LodNode(obj, _subtree_tris(obj))
        prev_tris = nodes[name].tri_count
    return nodes


# --------------------------------------------------------------------------- helpers


def _subtree_tris(obj) -> int:
    total = 0
    stack = [obj]
    while stack:
        node = stack.pop()
        if node.type == "MESH":
            total += bu.triangles_of(node)
        stack.extend(node.children)
    return total


def _merge_objects(name: str, sources, decimate_ratio: float | None,
                   min_tris_below: int | None = None):
    """Merge world-space copies of `sources` into one mesh named `name`,
    preserving per-face colours and material slots.  Optionally decimate."""
    verts: list[tuple] = []
    loops_per_face: list[int] = []
    face_mats: list[int] = []
    face_colours: list[tuple] = []
    materials: list[str] = []

    def mat_index(mat_name: str) -> int:
        if mat_name not in materials:
            materials.append(mat_name)
        return materials.index(mat_name)

    deps = bpy.context.evaluated_depsgraph_get()
    for src in sources:
        if src.type != "MESH" or src.hide_render:
            continue
        ev = src.evaluated_get(deps)
        mesh = ev.to_mesh()
        if mesh is None or not mesh.polygons:
            continue
        mat = mesh.materials[0].name if len(mesh.materials) else "vertex_colour"
        attr = mesh.color_attributes.get("Col")
        world = ev.matrix_world
        base = len(verts)
        loop_colours: list[tuple] = []
        for loop in mesh.loops:
            v = world @ mesh.vertices[loop.vertex_index].co
            verts.append((v.x, v.y, v.z))
            if attr is not None:
                c = attr.data[loop.vertex_index].color
                loop_colours.append((c[0], c[1], c[2]))
            else:
                loop_colours.append((0.8, 0.8, 0.8))
        for poly in mesh.polygons:
            loops_per_face.append(len(poly.loop_indices))
            face_mats.append(mat_index(mat))
            first_loop = poly.loop_indices[0]
            face_colours.append(loop_colours[first_loop]
                                if first_loop < len(loop_colours) else (0.8, 0.8, 0.8))
        ev.to_mesh_clear()
        if not verts:
            continue

    if not verts:
        return None

    faces = []
    cursor = 0
    for n in loops_per_face:
        faces.append(tuple(range(cursor, cursor + n)))
        cursor += n

    merged = bu.new_mesh_object(name, verts, faces, collection=ctx_scene_collection())
    merged.data.materials.clear()
    for mat_name in materials:
        merged.data.materials.append(bpy.data.materials[mat_name])
    for poly, mi in zip(merged.data.polygons, face_mats):
        poly.material_index = mi
    attr = bu.ensure_vertex_colour_attribute(merged.data)
    for poly, colour in zip(merged.data.polygons, face_colours):
        for li in poly.loop_indices:
            attr.data[li].color = (colour[0], colour[1], colour[2], 1.0)
    merged.data.update()

    if decimate_ratio is not None:
        ratio = max(MIN_RATIO, min(0.95, decimate_ratio))
        for _attempt in range(6):
            bu.apply_modifiers(merged)  # no-op if no stack left
            bu.add_decimate(merged, ratio)
            bu.apply_modifiers(merged)
            tris = bu.triangles_of(merged)
            if min_tris_below is None or tris < min_tris_below:
                break
            ratio = max(MIN_RATIO, ratio * 0.55)
    return merged


def ctx_scene_collection():
    return bpy.context.scene.collection
