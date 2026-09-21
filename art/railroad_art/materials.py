"""Shared palette materials: `vertex_colour` (opaque, attribute-driven),
`water`, and the parameterised company material with its two export instances.

An asset never creates a material of its own; it asks the context for these.
Names follow `art/config/material_palette.json` exactly so GLB material slots
can be validated against the palette by name.
"""

from __future__ import annotations

import bpy

from . import blender_util as bu


class MaterialStore:
    """Creates the canonical shared materials once per Blender session."""

    def __init__(self, palette):
        self.palette = palette
        self.vertex_colour = self._make_vertex_colour()
        self.water = self._make_water()
        self.company = self._make_company()
        # region -> bpy material whose *name* is the palette export name
        self.company_by_region = {
            "primary": self._company_instance("primary"),
            "secondary": self._company_instance("secondary"),
        }

    # -- vertex colour ------------------------------------------------------

    def _make_vertex_colour(self) -> "bpy.types.Material":
        material = bu.new_shared_material(self.palette.vertex_colour_material)
        bu.link_vertex_colour(material, self.palette.materials["vertex_colour"]["colour_attribute"])
        return material

    # -- water ---------------------------------------------------------------

    def _make_water(self) -> "bpy.types.Material":
        material = bu.new_shared_material(self.palette.water_material)
        bsdf = bu.principled(material)
        r, g, b = self.palette.colour("water")
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.15
        try:
            bsdf.inputs["Alpha"].default_value = 0.85
        except KeyError:  # pragma: no cover
            pass
        material.blend_method = "BLEND"
        return material

    # -- company -------------------------------------------------------------

    def _make_company(self) -> "bpy.types.Material":
        """The shared parameterised company material (source of the instances).

        Its base colour is *not* baked per-asset: the two named instances below
        carry the default livery, and the runtime re-parameterises them, which
        is exactly why these surfaces cannot live in vertex colour.
        """
        material = bu.new_shared_material("company_colour")
        bsdf = bu.principled(material)
        bsdf.inputs["Roughness"].default_value = 0.5
        return material

    def _company_instance(self, region: str) -> "bpy.types.Material":
        export_name = self.palette.company_export_name(region)
        category = self.palette.company_category(region)
        material = self.company.copy()
        material.name = export_name
        material.use_fake_user = True
        r, g, b = self.palette.colour(category)
        bu.principled(material).inputs["Base Color"].default_value = (r, g, b, 1.0)
        return material

    # -- helpers -------------------------------------------------------------

    def clear_slots(self, obj: "bpy.types.Object") -> None:
        while obj.data.materials:
            obj.data.materials.pop()

    def assign_vertex_colour(self, obj: "bpy.types.Object") -> None:
        self.clear_slots(obj)
        obj.data.materials.append(self.vertex_colour)

    def assign_company(self, obj: "bpy.types.Object", region: str) -> None:
        if region not in self.company_by_region:
            raise ValueError(f"company region must be 'primary' or 'secondary', got '{region}'")
        self.clear_slots(obj)
        obj.data.materials.append(self.company_by_region[region])

    def assign_water(self, obj: "bpy.types.Object") -> None:
        self.clear_slots(obj)
        obj.data.materials.append(self.water)
