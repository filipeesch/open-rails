"""Minimal GLB (binary glTF) reader — stdlib only, host-side.

Validation must not need Blender, so this parses just enough of the glTF 2.0
binary container to answer the checks: node names and hierarchy, mesh
triangle counts, material references, POSITION bounds (accessor min/max are
mandatory for POSITION per the glTF spec) and animation names.
"""

from __future__ import annotations

import json
import struct
from dataclasses import dataclass, field

GLB_MAGIC = 0x46546C67  # 'glTF'
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


class GlbError(RuntimeError):
    pass


@dataclass
class Glb:
    json_chunk: dict
    length: int
    path: str = ""

    # -- container ----------------------------------------------------------

    @classmethod
    def load(cls, path: str) -> "Glb":
        data = open(path, "rb").read()
        if len(data) < 12:
            raise GlbError(f"{path}: too small to be a GLB")
        magic, version, length = struct.unpack_from("<III", data, 0)
        if magic != GLB_MAGIC:
            raise GlbError(f"{path}: bad GLB magic 0x{magic:08x}")
        if version != 2:
            raise GlbError(f"{path}: unsupported glTF version {version}")
        offset = 12
        json_chunk = None
        while offset + 8 <= len(data):
            clen, ctype = struct.unpack_from("<II", data, offset)
            cdata = data[offset + 8: offset + 8 + clen]
            if ctype == CHUNK_JSON:
                json_chunk = json.loads(cdata.decode("utf-8").rstrip("\x00 "))
            offset += 8 + clen
        if json_chunk is None:
            raise GlbError(f"{path}: no JSON chunk found")
        return cls(json_chunk=json_chunk, length=length, path=path)

    # -- queries --------------------------------------------------------------

    def nodes(self) -> list[dict]:
        return self.json_chunk.get("nodes", [])

    def node_by_name(self, name: str) -> dict | None:
        for n in self.nodes():
            if n.get("name") == name:
                return n
        return None

    def meshes(self) -> list[dict]:
        return self.json_chunk.get("meshes", [])

    def materials(self) -> list[dict]:
        return self.json_chunk.get("materials", [])

    def animation_names(self) -> list[str]:
        return [a.get("name", "") for a in self.json_chunk.get("animations", [])]

    def accessors(self) -> list[dict]:
        return self.json_chunk.get("accessors", [])

    # -- subtree utilities --------------------------------------------------------

    def descendants(self, node: dict) -> list[dict]:
        nodes = self.nodes()
        out: list[dict] = []
        stack = [nodes[i] for i in node.get("children", [])]
        while stack:
            n = stack.pop()
            out.append(n)
            stack.extend(nodes[i] for i in n.get("children", []))
        return out

    def node_and_descendants(self, node: dict) -> list[dict]:
        return [node] + self.descendants(node)

    def primitive_triangles(self, mesh_index: int) -> int:
        mesh = self.meshes()[mesh_index]
        total = 0
        for prim in mesh.get("primitives", []):
            if "indices" in prim:
                total += self.accessors()[prim["indices"]]["count"] // 3
            else:
                total += self.accessors()[prim["attributes"]["POSITION"]]["count"] // 3
        return total

    def subtree_triangles(self, root_name: str) -> int | None:
        """Sum triangles of every mesh under the named node (and itself)."""
        node = self.node_by_name(root_name)
        if node is None:
            return None
        return sum(self.primitive_triangles(n["mesh"])
                   for n in self.node_and_descendants(node) if "mesh" in n)

    def subtree_material_indices(self, root_name: str) -> set[int]:
        node = self.node_by_name(root_name)
        if node is None:
            return set()
        out: set[int] = set()
        for n in self.node_and_descendants(node):
            if "mesh" not in n:
                continue
            for prim in self.meshes()[n["mesh"]].get("primitives", []):
                if "material" in prim:
                    out.add(prim["material"])
        return out

    def all_material_names_used(self) -> list[str]:
        used: set[int] = set()
        for mesh in self.meshes():
            for prim in mesh.get("primitives", []):
                if "material" in prim:
                    used.add(prim["material"])
        mats = self.materials()
        return sorted(mats[i].get("name", f"material_{i}") for i in used)

    # -- world-space bounds of a node subtree, honouring Y-up export -------------

    def subtree_bounds(self, root_name: str) -> tuple[tuple, tuple] | None:
        """(min, max) axis-aligned bounds in glTF space (Y up) of the named
        subtree, computed by transforming accessor min/max AABB corners with
        the composed node transforms.  Conservative for rotated children,
        which is acceptable for scale/origin checks."""
        node = self.node_by_name(root_name)
        if node is None:
            return None
        nodes = self.nodes()
        accessors = self.accessors()
        mins = [float("inf")] * 3
        maxs = [float("-inf")] * 3

        def walk(n: dict, parent_mat):
            mat = mat4_mul(parent_mat, node_matrix(n))
            if "mesh" in n:
                for prim in self.meshes()[n["mesh"]].get("primitives", []):
                    acc = accessors[prim["attributes"]["POSITION"]]
                    lo, hi = acc.get("min"), acc.get("max")
                    if lo is None or hi is None:
                        continue
                    for corner in _corners(lo, hi):
                        p = mat4_point(mat, corner)
                        for k in range(3):
                            mins[k] = min(mins[k], p[k])
                            maxs[k] = max(maxs[k], p[k])
            for ci in n.get("children", []):
                walk(nodes[ci], mat)

        walk(node, MAT_IDENTITY)
        if mins[0] == float("inf"):
            return None
        return (tuple(mins), tuple(maxs))


# --------------------------------------------------------------------------- mat4 helpers

MAT_IDENTITY = (1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)


def node_matrix(node: dict) -> tuple:
    """glTF node transform -> column-major 4x4 tuple."""
    if "matrix" in node:
        return tuple(node["matrix"])
    mat = list(MAT_IDENTITY)
    t = node.get("translation", (0, 0, 0))
    r = node.get("rotation", (0, 0, 0, 1))  # quaternion xyzw
    s = node.get("scale", (1, 1, 1))
    mat = list(mat4_mul(tuple(mat), _quat_mat(r)))
    for col in range(3):
        for row in range(3):
            mat[col * 4 + row] *= s[col]
    mat[12], mat[13], mat[14] = t[0], t[1], t[2]
    return tuple(mat)


def mat4_mul(a: tuple, b: tuple) -> tuple:
    out = [0.0] * 16
    for bc in range(4):
        for ac in range(4):
            s = 0.0
            for k in range(4):
                s += a[k * 4 + ac] * b[bc * 4 + k]
            out[bc * 4 + ac] = s
    return tuple(out)


def mat4_point(m: tuple, p: tuple) -> tuple:
    x, y, z = p
    return (m[0] * x + m[4] * y + m[8] * z + m[12],
            m[1] * x + m[5] * y + m[9] * z + m[13],
            m[2] * x + m[6] * y + m[10] * z + m[14])


def _quat_mat(q: tuple) -> tuple:
    x, y, z, w = q
    return (
        1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
        2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
        2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0,
        0, 0, 0, 1,
    )


def _corners(lo: tuple, hi: tuple):
    for i in range(8):
        yield (lo[0] if i & 1 else hi[0],
               lo[1] if i & 2 else hi[1],
               lo[2] if i & 4 else hi[2])
