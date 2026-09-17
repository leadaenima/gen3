#!/usr/bin/env python3
"""BCH mesh ripper for ORAS Pokemon battlers — phase-1 static posed geometry.

Ports the essential Ohana3DS-Rebirth BCH model path (relocations already in
bch_tex.py): models -> materials -> skeleton -> objects -> PICA attrs/indices.
Applies rigid bind-pose skinning; exports JSON for LÖVE Mesh construction.
Never writes into mods/*/assets or git — caller chooses cache dir.

Animation note (phase-2 skin sidecars via keep_skin=True):
  Companion files in the same GARC block use Game Freak containers:
    PF (small), PT (textures), PBJ (skeletal + material wait/attack clips),
    PKj (visibility / extras). Clip names like pmXXXX_00_ba10_waitA01 exist
  inside PBJ but the skeletal track format is proprietary (Ohana never fully
  cracked it). mesh.json therefore ships bind-pose only; DRAMATIC_SHAPE
  OrasModels plays a procedural idle until a PBJ ripper lands.
"""
from __future__ import annotations

import json
import math
import re
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from bch_tex import _apply_bch_relocations, _read_cstr

# --- PICA command IDs (gdkchan) ---
CMD_ATTR_BUF_ADDR = 0x200
CMD_ATTR_FMT_LO = 0x201
CMD_ATTR_FMT_HI = 0x202
CMD_ATTR_BUF0_ADDR = 0x203
CMD_ATTR_BUF0_PERM = 0x204
CMD_ATTR_BUF0_STRIDE = 0x205
CMD_INDEX_CFG = 0x227
CMD_INDEX_TOTAL = 0x228
CMD_BLOCK_END = 0x23D
CMD_VSH_TOTAL_ATTR = 0x242
CMD_VSH_PERM_LO = 0x2BB
CMD_VSH_PERM_HI = 0x2BC
CMD_VSH_FUNIFORM_CFG = 0x2C0
CMD_VSH_FUNIFORM_DATA = 0x2C1

ATTR_POSITION = 0
ATTR_NORMAL = 1
ATTR_TANGENT = 2
ATTR_COLOR = 3
ATTR_TEXCOORD0 = 4
ATTR_TEXCOORD1 = 5
ATTR_TEXCOORD2 = 6
ATTR_BONE_INDEX = 7
ATTR_BONE_WEIGHT = 8

FMT_SBYTE, FMT_UBYTE, FMT_SSHORT, FMT_FLOAT = 0, 1, 2, 3


def _u32(data: bytes | bytearray, off: int) -> int:
    return struct.unpack_from("<I", data, off)[0]


def _u16(data: bytes | bytearray, off: int) -> int:
    return struct.unpack_from("<H", data, off)[0]


def _i16(data: bytes | bytearray, off: int) -> int:
    return struct.unpack_from("<h", data, off)[0]


def _f32(data: bytes | bytearray, off: int) -> float:
    return struct.unpack_from("<f", data, off)[0]


def _mat4_identity() -> list[list[float]]:
    # Ohana OMatrix: indexed [col][row]; M11=m[0][0], M41=m[3][0] (translation).
    m = [[0.0] * 4 for _ in range(4)]
    m[0][0] = m[1][1] = m[2][2] = m[3][3] = 1.0
    return m


def _mat4_mul(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    # Same as Ohana operator*: c[i,j] = sum_k a[i,k]*b[k,j] with [col,row].
    out = [[0.0] * 4 for _ in range(4)]
    for i in range(4):
        for j in range(4):
            out[i][j] = (
                a[i][0] * b[0][j]
                + a[i][1] * b[1][j]
                + a[i][2] * b[2][j]
                + a[i][3] * b[3][j]
            )
    return out


def _mat4_scale(sx: float, sy: float, sz: float) -> list[list[float]]:
    m = _mat4_identity()
    m[0][0], m[1][1], m[2][2] = sx, sy, sz
    return m


def _mat4_rotate_x(a: float) -> list[list[float]]:
    c, s = math.cos(a), math.sin(a)
    m = _mat4_identity()
    m[1][1] = c
    m[2][1] = -s
    m[1][2] = s
    m[2][2] = c
    return m


def _mat4_rotate_y(a: float) -> list[list[float]]:
    c, s = math.cos(a), math.sin(a)
    m = _mat4_identity()
    m[0][0] = c
    m[2][0] = s
    m[0][2] = -s
    m[2][2] = c
    return m


def _mat4_rotate_z(a: float) -> list[list[float]]:
    c, s = math.cos(a), math.sin(a)
    m = _mat4_identity()
    m[0][0] = c
    m[1][0] = -s
    m[0][1] = s
    m[1][1] = c
    return m


def _mat4_translate(x: float, y: float, z: float) -> list[list[float]]:
    m = _mat4_identity()
    m[3][0], m[3][1], m[3][2] = x, y, z
    return m


def _xform_point(m: list[list[float]], x: float, y: float, z: float) -> tuple[float, float, float]:
    # Ohana OVector3.transform: row-vector * matrix
    return (
        x * m[0][0] + y * m[1][0] + z * m[2][0] + m[3][0],
        x * m[0][1] + y * m[1][1] + z * m[2][1] + m[3][1],
        x * m[0][2] + y * m[1][2] + z * m[2][2] + m[3][2],
    )


class PicaReader:
    def __init__(self, data: bytes | bytearray, offset: int, word_count: int, ignore_align: bool = False):
        self.cmds = [0] * 0x10000
        self.float_uniform: list[list[float] | None] = [None] * 96
        self._read(data, offset, word_count, ignore_align)

    def _read(self, data: bytes | bytearray, offset: int, word_count: int, ignore_align: bool) -> None:
        pos = offset
        readed = 0
        current_uniform = 0
        pending: list[float] = []

        def u32() -> int:
            nonlocal pos, readed
            v = struct.unpack_from("<I", data, pos)[0]
            pos += 4
            readed += 1
            return v

        def to_f(v: int) -> float:
            return struct.unpack("<f", struct.pack("<I", v & 0xFFFFFFFF))[0]

        while readed < word_count and pos + 8 <= len(data):
            parameter = u32()
            header = u32()
            cid = header & 0xFFFF
            mask = (header >> 16) & 0xF
            extra = (header >> 20) & 0x7FF
            consecutive = (header & 0x80000000) != 0
            self.cmds[cid] = (self.cmds[cid] & (~mask & 0xF)) | (parameter & (0xFFFFFFF0 | mask))
            if cid == CMD_BLOCK_END:
                break
            if cid == CMD_VSH_FUNIFORM_CFG:
                current_uniform = parameter & 0x7FFFFFFF
            elif cid == CMD_VSH_FUNIFORM_DATA:
                pending.append(to_f(self.cmds[cid]))
            for _ in range(extra):
                if consecutive:
                    cid += 1
                if readed >= word_count:
                    break
                self.cmds[cid] = (self.cmds[cid] & (~mask & 0xF)) | (u32() & (0xFFFFFFF0 | mask))
                if CMD_VSH_FUNIFORM_CFG < cid < CMD_VSH_FUNIFORM_DATA + 8:
                    pending.append(to_f(self.cmds[cid]))
            if pending:
                if self.float_uniform[current_uniform] is None:
                    self.float_uniform[current_uniform] = []
                self.float_uniform[current_uniform].extend(pending)
                pending = []
            if not ignore_align:
                while (pos & 7) != 0 and readed < word_count:
                    u32()

    def get(self, cid: int) -> int:
        return self.cmds[cid]

    def float_uniform_stack(self, reg: int) -> list[float]:
        """Return values so .pop() matches Ohana Stack.Pop (LIFO)."""
        vals = self.float_uniform[reg] or []
        return list(vals)  # caller pops from end

    def attr_buffer_address(self, buf: int = 0) -> int:
        return self.get(CMD_ATTR_BUF0_ADDR + buf * 3)

    def attr_buffer_stride(self, buf: int = 0) -> int:
        return (self.get(CMD_ATTR_BUF0_STRIDE + buf * 3) >> 16) & 0xFF

    def attr_total(self, buf: int = 0) -> int:
        return self.get(CMD_ATTR_BUF0_STRIDE + buf * 3) >> 28

    def main_permutation(self) -> list[int]:
        lo = self.get(CMD_VSH_PERM_LO)
        hi = self.get(CMD_VSH_PERM_HI)
        perm = lo | (hi << 32)
        return [(perm >> (i * 4)) & 0xF for i in range(23)]

    def buffer_permutation(self, buf: int = 0) -> list[int]:
        lo = self.get(CMD_ATTR_BUF0_PERM + buf * 3)
        hi = self.get(CMD_ATTR_BUF0_STRIDE + buf * 3) & 0xFFFF
        perm = lo | (hi << 32)
        return [(perm >> (i * 4)) & 0xF for i in range(23)]

    def attr_formats(self) -> list[tuple[int, int]]:
        lo = self.get(CMD_ATTR_FMT_LO)
        hi = self.get(CMD_ATTR_FMT_HI)
        fmt = lo | (hi << 32)
        out = []
        for i in range(23):
            v = (fmt >> (i * 4)) & 0xF
            out.append((v & 3, v >> 2))  # type, length
        return out

    def index_address(self) -> int:
        return self.get(CMD_INDEX_CFG) & 0x7FFFFFFF

    def index_format_short(self) -> bool:
        return (self.get(CMD_INDEX_CFG) >> 31) != 0

    def index_total(self) -> int:
        return self.get(CMD_INDEX_TOTAL)


@dataclass
class Bone:
    name: str
    parent_id: int
    scale: tuple[float, float, float]
    rotation: tuple[float, float, float]
    translation: tuple[float, float, float]
    inv_transform: list[list[float]]



def _material_shader_name(data: bytes | bytearray, ment: int, esz: int) -> str:
    """Best-effort shader / material-type name (BodyA_00, BodyB_00, Eye, ...)."""
    for off in (0x28, 40, 0x24, 0x20):
        if off + 4 > esz:
            continue
        ptr = _u32(data, ment + off)
        if not ptr or ptr >= len(data):
            continue
        s = _read_cstr(data, ptr) or ""
        if not s or s.startswith("pm"):
            continue
        low = s.lower()
        if any(
            k in low
            for k in ("body", "eye", "mouth", "iris", "leaf", "fire", "aura")
        ):
            return s
        # CamelCase shader ids without the usual keywords (rare)
        if re.match(r"^[A-Za-z][A-Za-z0-9_]{1,62}$", s):
            return s
    return ""


def _tex_unusable(name: str) -> bool:
    """Dummy / mask / env slots are never valid diffuse albedo."""
    if not name or not str(name).strip():
        return True
    low = name.lower().strip()
    if low in ("dummytex", "dummy", "dummy_tex") or "dummy" in low:
        return True
    if "mask" in low:
        return True
    if low.endswith("nor") or "_nor" in low or "normal" in low:
        return True
    if "env" in low and not any(
        t in low for t in ("body1", "body2", "bodya", "bodyb", "eye", "mouth", "iris")
    ):
        return True
    return False


def _is_plain_body2(name: str) -> bool:
    """pm####_FF_Body2 shared-atlas sheet (not BodyB2)."""
    low = (name or "").lower()
    return "body2" in low and "bodyb" not in low


def _is_bodyb_sheet(name: str) -> bool:
    return "bodyb" in (name or "").lower()


def _is_secondary_albedo_shader(shader: str) -> bool:
    """Shaders whose diffuse comes from the secondary body atlas.

    ORAS packs two common patterns:
      * Body00 / Body01 -- sheet index; Body01 samples Body2
      * BodyB* -- second material family; either Body1+Body2 split or BodyB1 sheet
    Do NOT treat mesh names (BodyBSkin), BodyA01, or BodyBuffron as secondary.
    BodyB matching uses CamelCase BodyB token so BodyBuffron (Body+Buffron) is excluded.
    """
    raw = (shader or "").replace(" ", "")
    s = raw.lower()
    if not s:
        return False
    # Body01 / Body01_00 / Body01_01 (sheet index), not BodyA01 / BodyDesukarn01
    if re.search(r"(^|_)body01($|_)", s) or s.startswith("body01"):
        return True
    # CamelCase BodyB token: BodyB, BodyB00, BodyB_00, BodyBVco, BodyBKurumiru, ...
    if re.search(r"BodyB($|[0-9_]|[A-Z])", raw):
        return True
    return False


def _part_wants_secondary_sheet(part_name: str) -> bool:
    """Petal/Flower parts often use BodyVco on the Body2 flower atlas."""
    n = (part_name or "").lower()
    return any(k in n for k in ("petal", "flower", "blossom"))


def pick_diffuse_texture(
    unit0: str,
    unit1: str,
    shader: str,
    part_name: str = "",
) -> str:
    """Choose the albedo texture unit for a BCH material.

    Rules (durable across the national dex):
      1. Never bind DummyTex / Mask / Nor / bare Env as diffuse.
      2. BodyB* + Body01* shaders prefer the secondary sheet when present:
         Body1+Body2 -> Body2; BodyB1(+BodyB2/Mask/Dummy) -> BodyB1.
      3. Petal/Flower parts with Body1+Body2 available prefer Body2 even on
         BodyVco (Vileplume petals share the flower atlas).
      4. Eyes / Mouth / Iris / BodyA / Body00 / default -> unit0 (*1 sheet).
    """
    u0, u1 = unit0 or "", unit1 or ""
    prefer_secondary = _is_secondary_albedo_shader(shader) or (
        _part_wants_secondary_sheet(part_name)
        and _is_plain_body2(u1)
        and ("body1" in u0.lower() or "bodya" in u0.lower())
    )

    def score(name: str) -> int:
        if _tex_unusable(name):
            return -1000
        low = name.lower()
        if prefer_secondary:
            if _is_plain_body2(name):
                return 100
            if _is_bodyb_sheet(name):
                # Within BodyB* naming, *1 is the albedo; *2 is often mask/detail
                if "bodyb1" in low:
                    return 80
                if "bodyb2" in low:
                    return 60
                return 70
            if "body1" in low or "bodya" in low:
                return 20  # usable fallback when Body2 missing (Dummy unit1)
            return 10
        # Primary / eye / mouth: prefer *1 sheets on unit0
        if any(
            t in low
            for t in ("body1", "bodya1", "bodyb1", "bodyc1", "eye1", "mouth1", "iris1")
        ):
            return 80
        if _is_plain_body2(name) or "bodyb2" in low:
            return 30
        if any(t in low for t in ("vco", "rare")):
            return 40
        return 50

    s0, s1 = score(u0), score(u1)
    if s1 > s0:
        return u1
    if s0 >= 0:
        return u0
    if s1 >= 0:
        return u1
    return u0 or u1


@dataclass
class MeshOut:
    name: str
    material_id: int
    texture: str
    material_shader: str = ""
    vertices: list[float] = field(default_factory=list)  # x,y,z,u,v (bind-pose skinned)
    indices: list[int] = field(default_factory=list)
    local_vertices: list[float] = field(default_factory=list)  # x,y,z before skin
    bone_indices: list[int] = field(default_factory=list)  # 4 per vert
    bone_weights: list[float] = field(default_factory=list)  # 4 per vert
    skinning_mode: int = 0


@dataclass
class ModelOut:
    name: str
    national: int
    form: int
    source: str
    meshes: list[MeshOut] = field(default_factory=list)
    bounds_min: list[float] = field(default_factory=lambda: [0.0, 0.0, 0.0])
    bounds_max: list[float] = field(default_factory=lambda: [0.0, 0.0, 0.0])
    bones: list[dict] = field(default_factory=list)


def _read_vector(data: bytes | bytearray, pos: int, fmt_type: int, length: int) -> tuple[tuple[float, float, float, float], int]:
    x = y = z = w = 0.0
    if fmt_type == FMT_FLOAT:
        x = _f32(data, pos)
        pos += 4
        if length > 0:
            y = _f32(data, pos)
            pos += 4
        if length > 1:
            z = _f32(data, pos)
            pos += 4
        if length > 2:
            w = _f32(data, pos)
            pos += 4
    elif fmt_type == FMT_SSHORT:
        x = float(_i16(data, pos))
        pos += 2
        if length > 0:
            y = float(_i16(data, pos))
            pos += 2
        if length > 1:
            z = float(_i16(data, pos))
            pos += 2
        if length > 2:
            w = float(_i16(data, pos))
            pos += 2
    elif fmt_type == FMT_SBYTE:
        x = float(struct.unpack_from("<b", data, pos)[0])
        pos += 1
        if length > 0:
            y = float(struct.unpack_from("<b", data, pos)[0])
            pos += 1
        if length > 1:
            z = float(struct.unpack_from("<b", data, pos)[0])
            pos += 1
        if length > 2:
            w = float(struct.unpack_from("<b", data, pos)[0])
            pos += 1
    else:  # UBYTE
        x = float(data[pos])
        pos += 1
        if length > 0:
            y = float(data[pos])
            pos += 1
        if length > 1:
            z = float(data[pos])
            pos += 1
        if length > 2:
            w = float(data[pos])
            pos += 1
    return (x, y, z, w), pos


def _parse_pm_name(name: str) -> tuple[int, int]:
    m = re.match(r"pm(\d{3,4})_(\d+)", name or "")
    if not m:
        return 0, 0
    return int(m.group(1)), int(m.group(2))


def _bone_world_matrices(bones: list[Bone]) -> list[list[list[float]]]:
    # Match Ohana transformSkeleton: accumulate scale*rotX*rotY*rotZ*trans up the parent chain.
    cache: dict[int, list[list[float]]] = {}

    def build(idx: int) -> list[list[float]]:
        if idx in cache:
            return cache[idx]
        b = bones[idx]
        t = _mat4_identity()
        t = _mat4_mul(t, _mat4_scale(*b.scale))
        t = _mat4_mul(t, _mat4_rotate_x(b.rotation[0]))
        t = _mat4_mul(t, _mat4_rotate_y(b.rotation[1]))
        t = _mat4_mul(t, _mat4_rotate_z(b.rotation[2]))
        t = _mat4_mul(t, _mat4_translate(*b.translation))
        if b.parent_id > -1 and b.parent_id < len(bones):
            t = _mat4_mul(t, build(b.parent_id))
        cache[idx] = t
        return t

    return [build(i) for i in range(len(bones))]


def rip_bch_meshes(path: Path | str) -> ModelOut | None:
    path = Path(path)
    raw = path.read_bytes()
    data = bytearray(raw)
    if data[:3] != b"BCH":
        if len(data) > 0x84 and data[0x80:0x83] == b"BCH":
            data = bytearray(data[0x80:])
        else:
            return None
    meta = _apply_bch_relocations(data)
    bc = meta["bc"]
    main = meta["main"]
    models_ptr = _u32(data, main)
    models_n = _u32(data, main + 4)
    if models_n == 0 or models_ptr == 0:
        return None

    moff = _u32(data, models_ptr)
    # model header
    off = moff + 4 + 48  # flags/skelScale/sil + worldTransform (12 floats)
    mats_off = _u32(data, off)
    mats_n = _u32(data, off + 4)
    off += 12
    verts_off = _u32(data, off)
    verts_n = _u32(data, off + 4)
    skip = 0x28 if bc > 6 else 0x20
    off2 = off + 8 + skip
    skel_off = _u32(data, off2)
    skel_n = _u32(data, off2 + 4)
    off2 += 12
    node_vis_off = _u32(data, off2)
    node_count = _u32(data, off2 + 4)
    off2 += 8
    model_name_off = _u32(data, off2)
    model_name = _read_cstr(data, model_name_off) or path.stem
    off2 += 4
    objects_node_name_entries = _u32(data, off2)
    objects_node_name_offset = _u32(data, off2 + 4)

    national, form = _parse_pm_name(model_name)
    model = ModelOut(name=model_name, national=national, form=form, source=str(path))

    # Material texture units + shader/type name.
    # Diffuse pick is deferred to each mesh so Petal/Flower can prefer Body2.
    mat_meta: list[tuple[str, str, str]] = []  # unit0, unit1, shader
    esz = 0x2C if bc >= 0x21 else 0x58
    for i in range(mats_n):
        ment = mats_off + i * esz
        if bc >= 0x21:
            n0 = _u32(data, ment + 0x1C)
            n1 = _u32(data, ment + 0x20)
        else:
            n0 = _u32(data, ment + 0x48)
            n1 = _u32(data, ment + 0x4C) if esz >= 0x50 else 0
        unit0 = _read_cstr(data, n0) or ""
        unit1 = _read_cstr(data, n1) or ""
        shader = _material_shader_name(data, ment, esz)
        mat_meta.append((unit0, unit1, shader))

    # Object names (radix tree then entries)
    object_names: list[str] = [""] * objects_node_name_entries
    if objects_node_name_offset and objects_node_name_entries:
        p = objects_node_name_offset
        p += 12  # root node
        for i in range(objects_node_name_entries):
            p += 8  # refBit + left + right
            object_names[i] = _read_cstr(data, _u32(data, p))
            p += 4

    # Skeleton
    bones: list[Bone] = []
    p = skel_off
    for i in range(skel_n):
        flags = _u32(data, p)
        parent_id = _i16(data, p + 4)
        # spacer u16 at p+6
        sx, sy, sz = _f32(data, p + 8), _f32(data, p + 12), _f32(data, p + 16)
        rx, ry, rz = _f32(data, p + 20), _f32(data, p + 24), _f32(data, p + 28)
        tx, ty, tz = _f32(data, p + 32), _f32(data, p + 36), _f32(data, p + 40)
        # invTransform: 3x4 Ohana layout M11,M21,M31,M41, M12,...
        inv = _mat4_identity()
        o = p + 44
        inv[0][0] = _f32(data, o); inv[1][0] = _f32(data, o + 4); inv[2][0] = _f32(data, o + 8); inv[3][0] = _f32(data, o + 12)
        inv[0][1] = _f32(data, o + 16); inv[1][1] = _f32(data, o + 20); inv[2][1] = _f32(data, o + 24); inv[3][1] = _f32(data, o + 28)
        inv[0][2] = _f32(data, o + 32); inv[1][2] = _f32(data, o + 36); inv[2][2] = _f32(data, o + 40); inv[3][2] = _f32(data, o + 44)
        p += 44 + 48
        bname = _read_cstr(data, _u32(data, p))
        p += 4
        meta_ptr = _u32(data, p)
        p += 4
        bones.append(
            Bone(
                name=bname or f"bone{i}",
                parent_id=parent_id,
                scale=(sx, sy, sz),
                rotation=(rx, ry, rz),
                translation=(tx, ty, tz),
                inv_transform=inv,
            )
        )
    bone_world = _bone_world_matrices(bones) if bones else []
    # Rest-pose skin matrices: boneWorld * invBind
    bone_skin = []
    for i, b in enumerate(bones):
        bone_skin.append(_mat4_mul(bone_world[i], b.inv_transform))
    def _inv_row_major(inv: list[list[float]]) -> list[float]:
        # Ohana [col][row] -> Mat4-compatible row-major flat (translation at 4,8,12).
        out: list[float] = []
        for r in range(4):
            for c in range(4):
                out.append(inv[c][r])
        return out

    model.bones = [
        {
            "name": b.name,
            "parent_id": b.parent_id,
            "scale": list(b.scale),
            "rotation": list(b.rotation),
            "translation": list(b.translation),
            "inv_transform": _inv_row_major(b.inv_transform),
        }
        for b in bones
    ]

    node_visibility = _u32(data, node_vis_off) if node_vis_off else 0xFFFFFFFF

    # Objects
    objects = []
    p = verts_off
    for i in range(verts_n):
        material_id = _u16(data, p)
        flags = _u16(data, p + 2)
        is_sil = (flags & 1) > 0 if bc != 8 else False
        node_id = _u16(data, p + 4)
        render_priority = _u16(data, p + 6)
        vsh_off = _u32(data, p + 8)
        vsh_wc = _u32(data, p + 12)
        faces_off = _u32(data, p + 16)
        faces_n = _u32(data, p + 20)
        # skip extra vsh + center + flags + pad + bbox = rest of 0x38
        p += 0x38
        objects.append(
            {
                "material_id": material_id,
                "is_sil": is_sil,
                "node_id": node_id,
                "priority": render_priority,
                "vsh_off": vsh_off,
                "vsh_wc": vsh_wc,
                "faces_off": faces_off,
                "faces_n": faces_n,
            }
        )

    bmin = [1e9, 1e9, 1e9]
    bmax = [-1e9, -1e9, -1e9]

    for oi, obj in enumerate(objects):
        if obj["is_sil"]:
            continue
        if node_count and obj["node_id"] < 32 and (node_visibility & (1 << obj["node_id"])) == 0:
            continue
        mesh_name = (
            object_names[obj["node_id"]]
            if obj["node_id"] < len(object_names) and object_names[obj["node_id"]]
            else f"mesh{oi}"
        )
        mid = obj["material_id"]
        if mid < len(mat_meta):
            unit0, unit1, shader_name = mat_meta[mid]
            tex_name = pick_diffuse_texture(unit0, unit1, shader_name, part_name=mesh_name)
        else:
            unit0 = unit1 = shader_name = ""
            tex_name = ""
        mesh = MeshOut(
            name=mesh_name,
            material_id=mid,
            texture=tex_name,
            material_shader=shader_name,
        )

        try:
            vsh = PicaReader(data, obj["vsh_off"], obj["vsh_wc"])
        except Exception:
            continue

        reg6 = vsh.float_uniform_stack(6)
        reg7 = vsh.float_uniform_stack(7)

        def pop(stack: list[float], default: float = 0.0) -> float:
            return stack.pop() if stack else default

        # Ohana pops positionOffset xy zw then scales from reg7
        pos_off_x = pop(reg6)
        pos_off_y = pop(reg6)
        pos_off_z = pop(reg6)
        pos_off_w = pop(reg6)
        tex0_scale = pop(reg7, 1.0)
        tex1_scale = pop(reg7, 1.0)
        tex2_scale = pop(reg7, 1.0)
        bone_weight_scale = pop(reg7, 1.0)
        position_scale = pop(reg7, 1.0)
        normal_scale = pop(reg7, 1.0)
        tangent_scale = pop(reg7, 1.0)
        color_scale = pop(reg7, 1.0)

        main_perm = vsh.main_permutation()
        buf_perm = vsh.buffer_permutation(0)
        formats = vsh.attr_formats()
        vbuf = vsh.attr_buffer_address(0)
        stride = vsh.attr_buffer_stride(0)
        total_attrs = vsh.attr_total(0)

        faces_n = obj["faces_n"]
        has_faces = faces_n > 0
        for fi in range(faces_n if has_faces else 0):
            base = obj["faces_off"] + fi * 0x34
            skinning_mode = _u16(data, base)  # 0 none, 1 smooth, 2 rigid?
            node_id_entries = _u16(data, base + 2)
            node_list = [_u16(data, base + 4 + n * 2) for n in range(node_id_entries)]
            face_hdr_off = _u32(data, base + 0x2C)
            face_hdr_wc = _u32(data, base + 0x30)
            try:
                idx_cmds = PicaReader(data, face_hdr_off, face_hdr_wc)
            except Exception:
                continue
            idx_addr = idx_cmds.index_address()
            idx_short = idx_cmds.index_format_short()
            idx_total = idx_cmds.index_total()
            if idx_total == 0 or idx_addr >= len(data):
                continue

            # Build unique vertices referenced by this face group, then indices
            # Ohana expands; we keep indexed for LÖVE.
            vert_map: dict[int, int] = {}

            def ensure_vert(index: int) -> int:
                if index in vert_map:
                    return vert_map[index]
                vpos = vbuf + index * stride
                if vpos < 0 or vpos + max(stride, 1) > len(data):
                    vert_map[index] = 0
                    return 0
                px = py = pz = 0.0
                u = v = 0.0
                nodes: list[int] = []
                weights: list[float] = []
                ap = vpos
                for attribute in range(total_attrs):
                    perm_i = buf_perm[attribute]
                    att = main_perm[perm_i]
                    fmt_type, fmt_len = formats[perm_i]
                    if att == ATTR_BONE_WEIGHT:
                        fmt_type = FMT_UBYTE
                    vec, ap2 = _read_vector(data, ap, fmt_type, fmt_len)
                    # attributes may not be tightly packed to ap advancement vs stride —
                    # Ohana advances by reading; stride is the vertex pitch. Using
                    # sequential read within the vertex is correct for interleaved layout.
                    ap = ap2
                    if att == ATTR_POSITION:
                        px = vec[0] * position_scale + pos_off_x
                        py = vec[1] * position_scale + pos_off_y
                        pz = vec[2] * position_scale + pos_off_z
                    elif att == ATTR_TEXCOORD0:
                        u = vec[0] * tex0_scale
                        v = vec[1] * tex0_scale
                    elif att == ATTR_BONE_INDEX:
                        if node_list:
                            try:
                                nodes.append(node_list[int(vec[0])])
                                if skinning_mode == 1:  # smooth
                                    if fmt_len > 0:
                                        nodes.append(node_list[int(vec[1])])
                                    if fmt_len > 1:
                                        nodes.append(node_list[int(vec[2])])
                                    if fmt_len > 2:
                                        nodes.append(node_list[int(vec[3])])
                            except (IndexError, ValueError):
                                pass
                    elif att == ATTR_BONE_WEIGHT:
                        weights.append(vec[0] * bone_weight_scale)
                        if skinning_mode == 1:
                            if fmt_len > 0:
                                weights.append(vec[1] * bone_weight_scale)
                            if fmt_len > 1:
                                weights.append(vec[2] * bone_weight_scale)
                            if fmt_len > 2:
                                weights.append(vec[3] * bone_weight_scale)

                if not nodes and node_list and len(node_list) <= 4:
                    nodes = list(node_list)
                    if not weights:
                        weights = [1.0]

                lx, ly, lz = px, py, pz
                # Skinning: rigid = boneWorld; smooth = weighted boneWorld*invBind.
                if nodes and bone_skin:
                    if skinning_mode == 1 and weights:
                        sx = sy = sz = 0.0
                        wsum = sum(weights) or 1.0
                        for bi, w in zip(nodes, weights):
                            if 0 <= bi < len(bone_skin) and w:
                                x, y, z = _xform_point(bone_skin[bi], px, py, pz)
                                sx += x * w
                                sy += y * w
                                sz += z * w
                        px, py, pz = sx / wsum, sy / wsum, sz / wsum
                    elif skinning_mode != 1:
                        bi = nodes[0]
                        if 0 <= bi < len(bone_world):
                            px, py, pz = _xform_point(bone_world[bi], px, py, pz)

                bmin[0] = min(bmin[0], px)
                bmin[1] = min(bmin[1], py)
                bmin[2] = min(bmin[2], pz)
                bmax[0] = max(bmax[0], px)
                bmax[1] = max(bmax[1], py)
                bmax[2] = max(bmax[2], pz)

                local = len(mesh.vertices) // 5
                mesh.vertices.extend([px, py, pz, u, v])
                mesh.local_vertices.extend([lx, ly, lz])
                bi = (nodes + [0, 0, 0, 0])[:4]
                if weights:
                    wsum = sum(weights) or 1.0
                    bw = [w / wsum for w in weights]
                else:
                    bw = [1.0]
                bw = (bw + [0.0, 0.0, 0.0, 0.0])[:4]
                mesh.bone_indices.extend(bi)
                mesh.bone_weights.extend(bw)
                mesh.skinning_mode = skinning_mode
                vert_map[index] = local
                return local

            ip = idx_addr
            for _face in range(idx_total):
                if idx_short:
                    if ip + 2 > len(data):
                        break
                    index = _u16(data, ip)
                    ip += 2
                else:
                    if ip >= len(data):
                        break
                    index = data[ip]
                    ip += 1
                mesh.indices.append(ensure_vert(index))

        if mesh.vertices and mesh.indices:
            model.meshes.append(mesh)

    if bmin[0] <= bmax[0]:
        model.bounds_min = bmin
        model.bounds_max = bmax
    if not model.meshes:
        return None
    return model


def model_to_dict(
    model: ModelOut,
    texture_paths: dict[str, str] | None = None,
    *,
    texture_index: list[dict] | None = None,
    model_stem: str | None = None,
    keep_skin: bool = False,
) -> dict[str, Any]:
    texture_paths = texture_paths or {}
    meshes = []
    for m in model.meshes:
        path = texture_paths.get(m.texture)
        if texture_index is not None and model_stem:
            path = resolve_texture_for_model(
                m.texture or "", model_stem, texture_index, texture_paths
            ) or path
        meshes.append(
            {
                "name": m.name,
                "material_id": m.material_id,
                "texture": m.texture,
                "material_shader": getattr(m, "material_shader", "") or "",
                "texture_path": path,
                "vertices": m.vertices,
                "indices": m.indices,
                "vertex_count": len(m.vertices) // 5,
                "index_count": len(m.indices),
            }
        )
        if keep_skin and m.local_vertices and m.bone_indices:
            meshes[-1]["local_vertices"] = m.local_vertices
            meshes[-1]["bone_indices"] = m.bone_indices
            meshes[-1]["bone_weights"] = m.bone_weights
            meshes[-1]["skinning_mode"] = m.skinning_mode
            meshes[-1]["influences"] = 4
    out = {
        "name": model.name,
        "national": model.national,
        "form": model.form,
        "source": model.source,
        "phase": ("2_skinned_bind" if keep_skin else "1_static_posed"),
        "bounds_min": model.bounds_min,
        "bounds_max": model.bounds_max,
        "meshes": meshes,
        "mesh_count": len(meshes),
    }
    if keep_skin and model.bones:
        out["bones"] = model.bones
        out["bone_count"] = len(model.bones)
    return out


def _folder_num_from_tex(t: dict) -> int:
    rel = str(t.get("rel") or t.get("path") or "").replace("\\", "/")
    for part in reversed(rel.split("/")):
        if part.isdigit():
            return int(part)
    return 10**9


def build_texture_name_index(texture_index: list[dict]) -> dict[str, str]:
    """Map texture name -> preferred PNG path.

    Prefer Body1/BodyA1 albedo, demote Eye/Nor/Rare/Vco, and when scores tie
    pick the *lower* garc file id (ORAS packs normal albedo before shiny).
    """
    best: dict[str, tuple[int, int, str]] = {}
    for t in texture_index:
        name = t.get("name")
        path = t.get("path")
        if not isinstance(name, str) or not isinstance(path, str):
            continue
        score = 10
        if "Body1" in name or "BodyA1" in name:
            score = 50
        elif "Body" in name and "Nor" not in name and "Eye" not in name:
            score = 30
        lname = name.lower()
        if any(tag in lname for tag in ("vco", "rare", "nor", "id")):
            score -= 25
        if "eye" in lname or "mouth" in lname:
            score -= 5  # still valid for eye mats; just don't win Body ties
        folder = _folder_num_from_tex(t)
        prev = best.get(name)
        # Higher score wins; tie -> lower folder (normal before shiny).
        if prev is None or score > prev[0] or (score == prev[0] and folder < prev[1]):
            best[name] = (score, folder, path)
    return {k: v[2] for k, v in best.items()}


def resolve_texture_for_model(
    tex_name: str,
    model_stem: str,
    texture_index: list[dict],
    fallback: dict[str, str] | None = None,
) -> str | None:
    """Prefer albedo BCH next to the model (typically stem+2), never shiny (+3)."""
    fallback = fallback or {}
    if not tex_name:
        return None
    try:
        model_id = int(model_stem)
    except ValueError:
        return fallback.get(tex_name)
    prefer = {model_id + 2, model_id + 1}
    demote = {model_id + 3, model_id + 4}
    cands: list[tuple[float, str]] = []
    for t in texture_index:
        if t.get("name") != tex_name:
            continue
        path = t.get("path")
        if not isinstance(path, str):
            continue
        folder = _folder_num_from_tex(t)
        score = 0.0
        if folder in prefer:
            score += 100.0
        if folder in demote:
            score -= 80.0
        score -= folder * 1e-6
        lname = tex_name.lower()
        if any(tag in lname for tag in ("vco", "rare")):
            score -= 40.0
        cands.append((score, path))
    if cands:
        cands.sort(key=lambda x: -x[0])
        return cands[0][1]
    return fallback.get(tex_name)


if __name__ == "__main__":
    import sys

    p = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    m = rip_bch_meshes(p)
    if not m:
        print("no mesh")
        sys.exit(1)
    d = model_to_dict(m)
    print(json.dumps({k: d[k] for k in d if k != "meshes"}, indent=2))
    for mesh in d["meshes"]:
        print(
            " mesh",
            mesh["name"],
            "tex",
            mesh["texture"],
            "verts",
            mesh["vertex_count"],
            "idx",
            mesh["index_count"],
        )
