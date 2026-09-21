"""railroad_art — the Open Rails asset authoring library.

Runs ONLY inside a headless Blender process; `tools/rr.py art build` imports
this package exclusively from inside its generated runner scripts.  The host
interpreter never touches it (no `bpy` on the host, ever).

Typical asset builder (from `asset.py`)::

    from railroad_art import vehicles

    def build(ctx):
        ctx.beveled_box("body", size=(0.6, 0.24, 0.14), location=(0, 0, 0.14),
                        colour="wood_light")
        wheels = vehicles.waggon_wheels(ctx, xs=[-0.2, 0.2])
        ctx.attachment("coupler_front", (0.46, 0, 0.04), kind="coupling")
"""

from .version import RAILROAD_ART_VERSION  # noqa: F401  (host-side readers use this only)

__all__ = ["RAILROAD_ART_VERSION"]
