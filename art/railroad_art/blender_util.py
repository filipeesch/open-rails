"""Blender façade — every version-sensitive `bpy` call lives here.

Blender 5.2 LTS differs from the 4.x API the rest of the code would naturally
be written against (slotted actions without ``action.fcurves``, ``Scene.
frame_set`` becoming a method, ``use_nodes`` deprecated, POINT-domain-only
vertex-colour GLB export, single 'BLENDER_EEVEE' engine).  This module
absorbs those differences so the primitives and composites read as plain,
stable Blender Python.

Importing this module requires a live ``bpy``: it is only ever imported
inside a headless Blender process, never by the host interpreter.
"""

from __future__ import annotations

import bpy

BLENDER_VERSION_TUPLE = tuple(bpy.app.version)
BLENDER_VERSION_STRING = bpy.app.version_string  # e.g. "5.2.0 LTS"


# --------------------------------------------------------------------------- scene


def reset_scene() -> "bpy.types.Scene":
    """Wipe the startup scene; return the clean scene to build into."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block_collection in (bpy.data.meshes, bpy.data.materials, bpy.data.actions,
                             bpy.data.lights, bpy.data.cameras, bpy.data.worlds):
        for block in list(block_collection):
            if block.users == 0:
                block_collection.remove(block)
    scene = bpy.context.scene
    for collection in list(scene.collection.children):
        scene.collection.children.unlink(collection)
    return scene


def set_units(scene: "bpy.types.Scene", scale_length: float = 1.0) -> None:
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = scale_length


def set_frame(scene: "bpy.types.Scene", frame: float) -> None:
    # Blender 5.x: frame_set is a method; 4.x allowed direct assignment.
    scene.frame_set(int(frame))


# --------------------------------------------------------------------------- meshes


def new_mesh_object(name: str, verts: list, faces: list,
                    collection: "bpy.types.Collection | None" = None) -> "bpy.types.Object":
    """Create a mesh object from raw vertex/face data."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    mesh.validate()
    mesh.update()
    return link_object(name, mesh, collection)


def link_object(name: str, mesh: "bpy.types.Mesh",
                collection: "bpy.types.Collection | None" = None) -> "bpy.types.Object":
    obj = bpy.data.objects.new(name, mesh)
    target = collection if collection is not None else bpy.context.scene.collection
    target.objects.link(obj)
    return obj


def unshare_mesh(obj: "bpy.types.Object") -> None:
    """Split every face so it owns its vertices.

    Chunky flat-shaded art with per-face colour needs one vertex per corner:
    shared corners would blend two palette colours across a hard edge.  The
    triangle count does not change; only the vertex count grows.
    """
    mesh = obj.data
    new_verts: list[tuple] = []
    new_faces: list[tuple] = []
    for poly in mesh.polygons:
        start = len(new_verts)
        for idx in poly.vertices:
            v = mesh.vertices[idx].co
            new_verts.append((v.x, v.y, v.z))
        new_faces.append(tuple(range(start, start + len(poly.vertices))))
    mesh.clear_geometry()
    mesh.from_pydata(new_verts, [], new_faces)
    mesh.validate()
    mesh.update()


def apply_object_transform(obj: "bpy.types.Object") -> None:
    """Bake the object's world transform into its mesh data."""
    obj.data.transform(obj.matrix_world)
    obj.matrix_world.identity()


def triangles_of(obj: "bpy.types.Object") -> int:
    """Triangle count of the evaluated mesh (ngons fan-triangulated)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        return sum(len(p.vertices) - 2 for p in mesh.polygons)
    finally:
        evaluated.to_mesh_clear()


# --------------------------------------------------------------------------- colour


def ensure_vertex_colour_attribute(mesh: "bpy.types.Mesh", name: str = "Col") -> "bpy.types.Attribute":
    """POINT-domain float colour attribute — the only domain the GLB
    exporter writes out as COLOR_0 in Blender 5.2."""
    existing = mesh.color_attributes.get(name)
    if existing is not None and existing.domain == "POINT":
        return existing
    if existing is not None:
        mesh.color_attributes.remove(existing)
    attr = mesh.color_attributes.new(name=name, type="FLOAT_COLOR", domain="POINT")
    return attr


def paint_all_face_loops(obj: "bpy.types.Object", colour: tuple, attr_name: str = "Col") -> None:
    attr = ensure_vertex_colour_attribute(obj.data, attr_name)
    for elem in attr.data:
        elem.color = (colour[0], colour[1], colour[2], 1.0)
    obj.data.update()


def paint_face_range(obj: "bpy.types.Object", face_indices, colour: tuple,
                     attr_name: str = "Col") -> None:
    """Colour specific polygons.  Requires an unshared mesh (primitives are
    created unshared, so every face owns its corner vertices)."""
    attr = ensure_vertex_colour_attribute(obj.data, attr_name)
    for fi in face_indices:
        poly = obj.data.polygons[fi]
        for loop_idx in poly.loop_indices:
            attr.data[loop_idx].color = (colour[0], colour[1], colour[2], 1.0)
    obj.data.update()


# --------------------------------------------------------------------------- materials


def new_shared_material(name: str) -> "bpy.types.Material":
    """Create a material with a usable node tree (5.2 ships nodes by default
    and deprecates toggling ``use_nodes``)."""
    material = bpy.data.materials.new(name)
    material.use_fake_user = True
    if material.node_tree is None:  # pragma: no cover - defensive for 4.x
        try:
            material.use_nodes = True
        except TypeError:  # pragma: no cover - Blender 5.2 rejects the toggle
            raise RuntimeError(f"cannot enable nodes on material '{name}'")
    return material


def principled(material: "bpy.types.Material"):
    return material.node_tree.nodes.get("Principled BSDF")


def link_vertex_colour(material: "bpy.types.Material", attribute: str = "Col") -> None:
    """Wire a colour Attribute node into the Principled base colour."""
    tree = material.node_tree
    bsdf = principled(material)
    attr = tree.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = attribute
    tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])


# --------------------------------------------------------------------------- modifiers


def add_decimate(obj: "bpy.types.Object", ratio: float) -> None:
    modifier = obj.modifiers.new("rr_decimate", "DECIMATE")
    modifier.ratio = max(0.01, min(1.0, ratio))


def apply_modifiers(obj: "bpy.types.Object") -> None:
    """Bake the whole modifier stack via evaluated-mesh swap.

    The operator path (`modifier_apply`) needs UI-ish context background mode
    does not reliably provide; the evaluated swap is context-free and keeps
    vertex-colour attributes (DECIMATE interpolates them)."""
    if not obj.modifiers:
        return
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    new_mesh = bpy.data.meshes.new_from_object(evaluated)
    old = obj.data
    obj.data = new_mesh
    bpy.data.meshes.remove(old)
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)


def bevel(obj: "bpy.types.Object", width: float, segments: int = 1) -> None:
    modifier = obj.modifiers.new("rr_bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    modifier.harden_normals = False


# --------------------------------------------------------------------------- actions (slotted in 5.x)


def new_action(name: str) -> "bpy.types.Action":
    return bpy.data.actions.new(name)


def bind_action(obj: "bpy.types.Object", action: "bpy.types.Action"):
    """Assign an action to an object; returns (action, slot)."""
    data = obj.animation_data_create()
    data.action = action
    slot = data.action_slot
    if slot is None:
        slot = action.slots.new(id_type="OBJECT", name=obj.name)
        data.action_slot = slot
    return action, slot


def keyframe(obj: "bpy.types.Object", data_path: str, index: int, frame: float,
             value: float) -> None:
    """Set one channel value and keyframe it (5.x auto-creates the layer,
    strip and channel bag for the bound slot)."""
    parts = data_path.split(".")
    target = obj
    for part in parts[:-1]:
        target = getattr(target, part)
    setattr(target, parts[-1], value if index < 0 else _with_index(target, data_path, index, value))
    if index < 0:
        obj.keyframe_insert(data_path=data_path, frame=frame)
    else:
        obj.keyframe_insert(data_path=data_path, index=index, frame=frame)


def _with_index(container, data_path: str, index: int, value: float):
    current = list(getattr(container, data_path.split(".")[-1]))
    current[index] = value
    return current


def fcurves_of(action: "bpy.types.Action", slot) -> list:
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            try:
                bag = strip.channelbag(slot, ensure=True)
            except TypeError:  # pragma: no cover - older signature without ensure
                bag = strip.channelbag(slot)
            out.extend(bag.fcurves)
    return out


def make_action_linear_cyclic(action: "bpy.types.Action", slot, start: int, end: int) -> None:
    for curve in fcurves_of(action, slot):
        for point in curve.keyframe_points:
            point.interpolation = "LINEAR"
    action.frame_start = start
    action.frame_end = end - 1  # last frame is the loop seam; see rotate_full
    action.use_cyclic = True
    action.use_frame_range = True


# --------------------------------------------------------------------------- export / render


def resolve_render_engine() -> str:
    """First available engine name, EEVEE preferred."""
    available = bpy.context.scene.render.bl_rna.properties["engine"].enum_items.keys()
    for preferred in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH"):
        if preferred in available:
            return preferred
    return available[0] if available else "BLENDER_EEVEE"


def _hierarchy_of(obj: "bpy.types.Object") -> list:
    out = [obj]
    for child in obj.children:
        out.extend(_hierarchy_of(child))
    return out


def export_glb(filepath: str, objects: list) -> None:
    """Export exactly ``objects`` (with their children) as a single GLB."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        for node in _hierarchy_of(obj):
            node.select_set(True)
    if objects:
        bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_materials="EXPORT",
        export_vertex_color="NAME",
        export_vertex_color_name="Col",
        export_attributes=True,
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_cameras=False,
        export_lights=False,
        export_skins=False,
        export_morph=False,
        export_extras=True,
    )
