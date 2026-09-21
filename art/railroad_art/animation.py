"""Mechanical animation authoring with the canonical runtime state contract.

An asset authors one Blender action per mechanical behaviour and registers it
against a canonical state — idle / moving / working / loading / unloading.
The published manifest carries the complete map `{canonical state: action
name | null}`; the runtime resolves concrete names from metadata only.

Transient effects (smoke, steam, sparks, glow) are deliberately *not*
modelled here — the spec forbids baking them into GLB animations.

Blender 5.2 slotted-action details are confined to `blender_util`.
"""

from __future__ import annotations

import math

from . import blender_util as bu
from .conventions import ANIMATION_FPS, ANIMATION_LOOP_FRAMES, CANONICAL_STATES


class AnimationError(RuntimeError):
    pass


class AnimationRegistry:
    def __init__(self, ctx):
        self.ctx = ctx
        self.actions: dict[str, "bpy.types.Action"] = {}
        self.states: dict[str, str] = {}
        self.loop_frames = ANIMATION_LOOP_FRAMES
        self.fps = ANIMATION_FPS

    # ------------------------------------------------------------------ actions

    def action(self, name: str, loop_frames: int | None = None):
        """Create/retrieve a named action; returns the bpy Action."""
        if name in self.actions:
            return self.actions[name]
        action = bu.new_action(name)
        self.actions[name] = action
        if loop_frames:
            self.loop_frames = loop_frames
        return action

    # ------------------------------------------------------------------ channels

    def spin(self, obj, action, axis: str = "y", turns: float = 1.0,
             start_deg: float = 0.0, frames: int | None = None) -> None:
        """One full mechanical rotation over the loop.  The phase of a wheel is
        baked into its spoke geometry (`phase_deg`), so every spinning object
        can share the same 0→2π ramp without pulling the base transform out
        from under the authored pose."""
        axis_index = {"x": 0, "y": 1, "z": 2}[axis]
        frames = frames or self.loop_frames
        action, slot = bu.bind_action(obj, action)
        zero = list(obj.rotation_euler)
        angle = math.radians(start_deg)
        bu.keyframe(obj, "rotation_euler", axis_index, 1, zero[axis_index] + angle)
        bu.keyframe(obj, "rotation_euler", axis_index, frames + 1,
                    zero[axis_index] + angle + turns * 2 * math.pi)
        curves = bu.fcurves_of(action, slot)
        for curve in curves:
            for point in curve.keyframe_points:
                point.interpolation = "LINEAR"

    def translate(self, obj, action, data_path: str, index: int,
                  value_a: float, value_b: float,
                  frame_a: int = 1, frame_b: int | None = None) -> None:
        """Ping-pong linear slide (tips, gates, rams): A at frame_a, B at frame_b,
        mirrored back on cyclic playback."""
        frames = self.loop_frames
        frame_b = frame_b or (frames + 1)
        action, slot = bu.bind_action(obj, action)
        bu.keyframe(obj, data_path, index, frame_a, value_a)
        bu.keyframe(obj, data_path, index, frame_b, value_b)
        for curve in bu.fcurves_of(action, slot):
            for point in curve.keyframe_points:
                point.interpolation = "SINE_EASE" if len(curve.keyframe_points) > 2 else "LINEAR"

    def reciprocate(self, obj, action, amplitude: float, index: int = 0,
                    data_path: str = "location") -> None:
        """Rod slide: x(t) = base + A·sin over one loop, four+1 keys, linear —
        the period-stock coupling rod read at diorama scale."""
        frames = self.loop_frames
        action, slot = bu.bind_action(obj, action)
        base = list(getattr(obj, data_path))[index]
        quarter = frames / 4
        offsets = (0.0, 1.0, 0.0, -1.0, 0.0)
        for i, off in enumerate(offsets):
            frame = 1 + quarter * i
            bu.keyframe(obj, data_path, index, frame, base + amplitude * off)
        for curve in bu.fcurves_of(action, slot):
            for point in curve.keyframe_points:
                point.interpolation = "LINEAR"

    # ------------------------------------------------------------------ state contract

    def register_state(self, state: str, action_name: str) -> None:
        """Bind a canonical runtime state to an authored action name."""
        if state not in CANONICAL_STATES:
            raise AnimationError(
                f"animation state '{state}' is not canonical "
                f"(permitted: {', '.join(CANONICAL_STATES)})")
        if action_name not in self.actions:
            raise AnimationError(f"state '{state}' references unauthored action "
                                 f"'{action_name}'")
        self.states[state] = action_name

    def state_map(self) -> dict:
        """Complete canonical map with nulls for unimplemented states."""
        return {state: self.states.get(state) for state in CANONICAL_STATES}

    def actions_info(self) -> dict:
        return {name: {"frame_start": 1, "frame_end": self.loop_frames + 1,
                       "fps": self.fps}
                for name in sorted(self.actions)}

    def apply_scene_frames(self) -> None:
        if not self.actions:
            return
        scene = self.ctx.scene
        scene.render.fps = self.fps
        scene.frame_start = 1
        scene.frame_end = self.loop_frames
