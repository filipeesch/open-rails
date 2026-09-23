"""BuildContext — the asset author's entire surface.

The orchestrator's generated runner script does exactly:

    ctx = BuildContext.from_job_file(job_path)   # inside Blender
    BuildContext.load_asset_module(path).build(ctx)
    summary = ctx.finalize()                     # LODs, GLB, manifest

Everything an asset author calls lives on this object; everything finalize()
does (LOD reduction, palette discipline, GLB + manifest publication) is
mechanical, which is what makes the pipeline reviewable and cacheable.

Authoring coordinates are TILE UNITS (+Z up; rolling stock faces +X), so a
change to TILE_SIZE in `art/config/world.toml` rescales every rebuild without
editing any asset (art-authoring spec: "Scale is read from configuration").

This module imports bpy: it runs only inside headless Blender.
"""

from __future__ import annotations

import datetime as _dt
import importlib.util
import json
import math
import sys
from pathlib import Path

import bpy
import mathutils

from . import blender_util as bu
from . import lod as lod_mod
from . import primitives as P
from .animation import AnimationRegistry
from .config import Palette, WorldScale, load_world
from .materials import MaterialStore

MANIFEST_SCHEMA = "openrails.art.manifest/1"


class BuildError(RuntimeError):
    pass


class BuildContext:
    """Scene bootstrap + authoring API + publication, per build job."""

    def __init__(self, *, repo_root: Path, job: dict):
        self.repo_root = Path(repo_root)
        self.job = job
        self.id: str = job["id"]
        self.type: str = job["type"]
        self.lod_class: str = job["lod_class"]
        self.footprint: tuple[float, float] = tuple(job["footprint"])
        self.height_tiles = job.get("height")
        self.required_states: list[str] = list(job.get("required_states") or [])
        self.declared_company_regions: list[str] = list(job.get("company_regions") or [])
        self.lod_levels: int = int(job.get("lod_levels", 3))
        self.lod_auto: bool = bool(job.get("lod_auto", True))
        self.lod_ratios: tuple = tuple(job.get("lod_ratios", (0.45, 0.15)))
        self.mode: str = job.get("mode", "build")  # build | preview
        self.out_dir = Path(job["out_dir"])         # staging dir (job temp)
        self.preview_dir = job.get("preview_dir")
        self.cache_key: str = job.get("cache_key", "")
        self.library_version: str = job.get("library_version", "")
        self.blender_executable: str = job.get("blender_executable", "")

        self.world = WorldScale(load_world(self.repo_root / "art" / "config" / "world.toml"))
        self.palette = Palette.load(self.repo_root / "art" / "config" / "material_palette.json")
        self.materials = MaterialStore(self.palette)

        self.scene = bu.reset_scene()
        bu.set_units(self.scene)

        # registries filled while building
        self.parts: list["bpy.types.Object"] = []
        self.attachments: dict[str, tuple] = {}
        self.attachment_kinds: dict[str, str] = {}
        self.company_regions: dict[str, list[str]] = {}
        self.wheel_roles: dict[str, list[dict]] = {}
        self.wheel_circumferences: dict[str, float] = {}
        self.wheel_radii: dict[str, float] = {}
        self.extras: dict[str, object] = {}
        self.lod_overrides: dict[int, list] = {}
        self.anim = AnimationRegistry(self)

    # ------------------------------------------------------------------ construction

    @classmethod
    def from_job_file(cls, path: str | Path) -> "BuildContext":
        path = Path(path)
        job = json.loads(path.read_text(encoding="utf-8"))
        return cls(repo_root=Path(job["repo_root"]), job=job)

    @staticmethod
    def load_asset_module(asset_py: str | Path):
        """Import an asset's asset.py by file path under a unique module name."""
        asset_py = Path(asset_py)
        name = f"rr_asset_{asset_py.parent.name}"
        spec = importlib.util.spec_from_file_location(name, asset_py)
        if spec is None or spec.loader is None:
            raise BuildError(f"cannot load asset module from {asset_py}")
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
        if not hasattr(module, "build"):
            raise BuildError(f"{asset_py}: asset module defines no build(ctx)")
        return module

    # ------------------------------------------------------------------ scale

    def tiles(self, n: float) -> float:
        """Tile units -> scene metres."""
        return self.world.tiles(n)

    # ------------------------------------------------------------------ parts

    def register_part(self, obj) -> None:
        """Called by every primitive; assets rarely need it directly."""
        self.parts.append(obj)

    # -- primitives (the author never touches bpy) -------------------------

    def box(self, *a, **kw): return P.box(self, *a, **kw)

    def beveled_box(self, *a, **kw): return P.beveled_box(self, *a, **kw)

    def cylinder(self, *a, **kw): return P.cylinder(self, *a, **kw)

    def pipe(self, *a, **kw): return P.pipe(self, *a, **kw)

    def roof(self, *a, **kw): return P.roof(self, *a, **kw)

    def wheel(self, *a, **kw): return P.wheel(self, *a, **kw)

    # -- colour -----------------------------------------------------------

    def paint(self, obj, category: str, shade: float = 1.0) -> None:
        """Bake a palette category over an whole object (optionally darkened
        for the vertex-baked-AO convention)."""
        r, g, b = self.palette.colour(category)
        self.materials.assign_vertex_colour(obj)
        bu.paint_all_face_loops(obj, (r * shade, g * shade, b * shade))

    def paint_faces(self, obj, face_indices, category: str, shade: float = 1.0) -> None:
        """Palette colour on specific polygons (stripes, junction darkening).
        Primitives are created unshared, so this never bleeds into neighbours."""
        r, g, b = self.palette.colour(category)
        bu.paint_face_range(obj, face_indices, (r * shade, g * shade, b * shade))

    def shade_faces_below(self, obj, fraction: float = 0.25, factor: float = 0.82) -> None:
        """Cheap AO: darken polygons in the lowest `fraction` of the object."""
        if not obj.data.polygons:
            return
        zs = [ (obj.matrix_world @ p.center).z for p in obj.data.polygons ]
        zmin, zmax = min(zs), max(zs)
        cut = zmin + (zmax - zmin) * fraction
        low = [p.index for p, z in zip(obj.data.polygons, zs) if z <= cut]
        attr = obj.data.color_attributes.get("Col")
        if attr is None or not low:
            return
        for fi in low:
            for li in obj.data.polygons[fi].loop_indices:
                c = attr.data[li].color
                attr.data[li].color = (c[0] * factor, c[1] * factor, c[2] * factor, 1.0)
        obj.data.update()

    # -- company colour -----------------------------------------------------

    def tag_company(self, obj, region: str) -> None:
        """Route an object through the shared parameterised company material
        (exported as `company_primary`/`company_secondary`); never vertex
        colour, so liveries stay runtime-tintable."""
        if region not in ("primary", "secondary"):
            raise BuildError(f"company region must be primary|secondary, got '{region}'")
        self.materials.assign_company(obj, region)
        self.company_regions.setdefault(region, []).append(obj.name)

    # -- attachments -----------------------------------------------------------

    def attachment(self, name: str, location=(0.0, 0.0, 0.0), kind: str = "point") -> None:
        """Named attachment point (tile units, local space).  Published in the
        manifest and exported as an `attach_<name>` node in the GLB."""
        coords = (float(location[0]), float(location[1]), float(location[2]))
        self.attachments[name] = coords
        self.attachment_kinds[name] = kind
        obj = bpy.data.objects.new(f"attach_{name}", None)
        self.scene.collection.objects.link(obj)
        obj.empty_display_type = "SPHERE"
        obj.empty_display_size = 0.04
        obj.location = (coords[0] * self.world.tile_size,
                        coords[1] * self.world.tile_size,
                        coords[2] * self.world.tile_size)
        obj["rr_attachment"] = kind

    # -- wheels (metadata for the manifest; geometry lives in primitives) --------

    def register_wheel(self, obj, role: str, phase_deg: float = 0.0, side: str = "centre",
                       radius: float = None) -> None:
        self.wheel_roles.setdefault(role, []).append(
            {"object": obj.name, "role": role,
             "phase_deg": round(float(phase_deg), 3), "side": side})
        if radius is not None:
            # The wheelbase is the asset's, not the runtime's to guess: a wheel
            # that rolls one revolution per `moving` clip converts the train's
            # travelled distance into a crank angle, and that conversion is the
            # circumference.  Published here so the renderer measures nothing.
            self.wheel_circumferences[role] = 2.0 * math.pi * float(radius)
            self.wheel_radii[role] = float(radius)

    # -- LOD policy ----------------------------------------------------------------

    def set_lod_override(self, level: int, objects) -> None:
        """Manual LOD level: use these objects as the content of LOD<level>
        instead of the auto-reduction result."""
        self.lod_overrides[level] = list(objects)

    # -- free-form manifest additions -------------------------------------------------

    def set_extra(self, key: str, value) -> None:
        self.extras[key] = value

    # ------------------------------------------------------------------ finalise

    def finalize(self) -> dict:
        """Assemble LOD nodes, enforce palette discipline, export the GLB (or
        render previews), write the manifest.  Returns the run summary."""
        self._enforce_company_contract()
        self.anim.apply_scene_frames()
        lod_nodes = lod_mod.assemble(self)

        lod_path = self.out_dir / "models" / f"{self.id}.glb"
        manifest_path = self.out_dir / "manifests" / f"{self.id}.json"
        lod_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.parent.mkdir(parents=True, exist_ok=True)

        summary: dict = {"id": self.id}
        if self.mode == "preview":
            summary.update(self._render_previews(lod_nodes))
        else:
            export_nodes = [node.obj for node in lod_nodes.values()]
            export_nodes += [o for o in self.scene.collection.objects
                             if o.get("rr_attachment")]
            bu.export_glb(str(lod_path), export_nodes)
            summary["glb"] = str(lod_path)

        lod_tris = {name: lod_nodes[name].tri_count for name in lod_nodes}
        manifest = {
            "schema": MANIFEST_SCHEMA,
            "id": self.id,
            "type": self.type,
            "lod_class": self.lod_class,
            "footprint": [float(self.footprint[0]), float(self.footprint[1])],
            "height": float(self.height_tiles) if self.height_tiles is not None else None,
            "units": "tile units; footprint=(extent along local +X, extent along local +Y); z up",
            "lod_levels": sorted(lod_tris.keys()),
            "lod_triangles": lod_tris,
            "materials": sorted(self._used_material_names()),
            "attachments": {n: [round(c, 6) for c in xyz]
                            for n, xyz in self.attachments.items()},
            "attachment_kinds": dict(sorted(self.attachment_kinds.items())),
            "animation_states": self.anim.state_map(),
            "actions": self.anim.actions_info(),
            "required_states": sorted(self.required_states),
            "company_regions": {k: sorted(v) for k, v in sorted(self.company_regions.items())},
            "wheel_phases": {role: sorted(entries, key=lambda e: e["object"])
                             for role, entries in sorted(self.wheel_roles.items())},
            "wheel_circumference_tiles": {r: round(c, 6)
                                          for r, c in sorted(self.wheel_circumferences.items())},
            "wheel_radius_tiles": {r: round(v, 6)
                                   for r, v in sorted(self.wheel_radii.items())},
            "lod_method_manual": sorted(str(k) for k in self.lod_overrides),
            "extras": self.extras,
            "cache_key": self.cache_key,
            "library_version": self.library_version,
            "blender_version": bu.BLENDER_VERSION_STRING,
            "blender_version_tuple": list(bu.BLENDER_VERSION_TUPLE),
            "blender_executable": self.blender_executable,
            "build_timestamp": _dt.datetime.now(_dt.timezone.utc)
                                  .isoformat(timespec="seconds"),
            "world": {"tile_size": self.world.tile_size,
                      "height_step": self.world.height_step},
        }
        if self.mode != "preview":
            manifest["model"] = f"models/{self.id}.glb"
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                                 encoding="utf-8")
        summary.update({
            "manifest": str(manifest_path),
            "lod_triangles": lod_tris,
            "materials": manifest["materials"],
            "animation_states": manifest["animation_states"],
        })
        return summary

    # ------------------------------------------------------------------ internals

    def _enforce_company_contract(self) -> None:
        for region in self.declared_company_regions:
            if region not in self.company_regions:
                raise BuildError(
                    f"asset.toml declares company region '{region}' but no object "
                    "was tagged via ctx.tag_company()")

    def _used_material_names(self) -> set[str]:
        """Materials actually referenced by exported faces — mirroring the
        glTF exporter, which skips material slots no polygon uses."""
        names: set[str] = set()
        for obj in self.scene.collection.all_objects:
            if obj.type != "MESH":
                continue
            slots = obj.data.materials
            for poly in obj.data.polygons:
                idx = poly.material_index
                if 0 <= idx < len(slots) and slots[idx] is not None:
                    names.add(slots[idx].name)
        return names

    # ------------------------------------------------------------------ previews

    def _render_previews(self, lod_nodes: dict) -> dict:
        """8 yaw angles × 45° apart, at close and normal ortho zoom, on the
        game's fixed pitch (camera section of world.toml)."""
        out = Path(self.preview_dir)
        out.mkdir(parents=True, exist_ok=True)
        # keep only LOD0 visible for review renders
        for obj in list(self.scene.collection.all_objects):
            if obj.type == "MESH" and (obj.name == "LOD1" or obj.name == "LOD2"):
                obj.hide_render = True
                obj.hide_set(True)
            if obj.type == "MESH" and obj.name == "LOD0":
                obj.hide_render = False
        mins, maxs = self._scene_bbox()
        centre = (mins + maxs) / 2
        diag = max((maxs - mins).length, 1e-3)
        pitch = math.radians(self.world.camera.get("fixed_pitch_degrees", 35.264))

        self.scene.render.engine = bu.resolve_render_engine()
        self.scene.render.resolution_x = 480
        self.scene.render.resolution_y = 360
        self.scene.render.image_settings.file_format = "PNG"
        self.scene.render.film_transparent = True
        _setup_preview_lighting(self.scene)

        cam_data = bpy.data.cameras.new("rr_preview_cam")
        cam_data.type = "ORTHO"
        cam = bpy.data.objects.new("rr_preview_cam", cam_data)
        self.scene.collection.objects.link(cam)
        self.scene.camera = cam

        written = []
        for zoom_name, factor in (("close", 1.3), ("normal", 2.8)):
            cam_data.ortho_scale = diag * factor
            for i in range(8):
                yaw = math.radians(i * 45.0)
                direction = mathutils.Vector(
                    (math.cos(yaw) * math.cos(pitch),
                     math.sin(yaw) * math.cos(pitch),
                     math.sin(pitch)))
                cam.location = centre + direction * (diag * 5.0 + 1.0)
                # a camera looks down its own -Z: track +Z along the
                # subject->camera vector so the lens faces the asset
                cam.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
                fp = out / f"{i * 45:03d}_{zoom_name}.png"
                self.scene.render.filepath = str(fp)
                bpy.ops.render.render(write_still=True)
                written.append(str(fp))
        return {"previews": written, "engine": self.scene.render.engine}

    def _scene_bbox(self):
        mins = mathutils.Vector((1e9, 1e9, 1e9))
        maxs = mathutils.Vector((-1e9, -1e9, -1e9))
        deps = bpy.context.evaluated_depsgraph_get()
        for obj in self.scene.collection.all_objects:
            if obj.type != "MESH" or obj.hide_render or not obj.visible_get():
                continue
            ev = obj.evaluated_get(deps)
            try:
                corners = [ev.matrix_world @ mathutils.Vector(c) for c in ev.bound_box]
            except Exception:  # pragma: no cover - empty evaluated mesh
                continue
            for w in corners:
                mins = mathutils.Vector((min(mins.x, w.x), min(mins.y, w.y), min(mins.z, w.z)))
                maxs = mathutils.Vector((max(maxs.x, w.x), max(maxs.y, w.y), max(maxs.z, w.z)))
        if mins.x > 1e8:
            mins = mathutils.Vector((0, 0, 0))
            maxs = mathutils.Vector((1, 1, 1))
        return mins, maxs


def _setup_preview_lighting(scene) -> None:
    sun_data = bpy.data.lights.new("rr_sun", "SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("rr_sun", sun_data)
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("rr_preview_world")
    scene.world = world
    tree = world.node_tree
    if tree is None:  # pragma: no cover - defensive
        try:
            world.use_nodes = True
        except TypeError:
            return
        tree = world.node_tree
    bg = tree.nodes.get("Background")
    if bg is not None:
        bg.inputs[0].default_value = (0.32, 0.38, 0.44, 1.0)
        bg.inputs[1].default_value = 0.7
