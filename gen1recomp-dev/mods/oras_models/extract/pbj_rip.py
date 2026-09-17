#!/usr/bin/env python3
"""PBJ battle-clip ripper — GF1Motion skeletal decode (SPICA GFL port).

ORAS packs battle clips in companion PBJ bins (model stem N+5) under
garc a/0/0/8. Section 0 is a GF1MotionPack (gdkchan/SPICA Formats/GFL);
later sections are small BCH material/visibility clips whose names label
the skeletal slots.

Output (cache only, never assets/ or git):
  anims/<pbj_stem>_clips.json   — per-clip bone S/R/T hermite keyframes
  anims/pbj_index.json          — national / stem coverage
  anims/anim_by_national.json   — national -> clip paths / roles
"""
from __future__ import annotations

import argparse
import json
import math
import re
import struct
from pathlib import Path
from typing import Any

CLIP_RE = re.compile(r"pm\d{4}_\d{2}_(?:ba|kw)\d{2}_[A-Za-z0-9]+", re.ASCII)

ROLE_MAP = (
    ("buturi", "attack_physical"),
    ("tokusyu", "attack_special"),
    ("damage", "damage"),
    ("down", "faint"),
    ("land", "land"),
    ("wait", "wait"),
)


def _role_for(clip: str) -> str:
    low = clip.lower()
    for needle, role in ROLE_MAP:
        if needle in low:
            return role
    return "other"


class Buf:
    __slots__ = ("data", "pos")

    def __init__(self, data: bytes, pos: int = 0):
        self.data = data
        self.pos = pos

    def remaining(self) -> int:
        return len(self.data) - self.pos

    def u8(self) -> int:
        v = self.data[self.pos]
        self.pos += 1
        return v

    def u16(self) -> int:
        v = struct.unpack_from("<H", self.data, self.pos)[0]
        self.pos += 2
        return v

    def u24(self) -> int:
        b0, b1, b2 = self.data[self.pos : self.pos + 3]
        self.pos += 3
        return b0 | (b1 << 8) | (b2 << 16)

    def u32(self) -> int:
        v = struct.unpack_from("<I", self.data, self.pos)[0]
        self.pos += 4
        return v

    def f32(self) -> float:
        v = struct.unpack_from("<f", self.data, self.pos)[0]
        self.pos += 4
        return v

    def align(self, n: int = 4) -> None:
        rem = self.pos % n
        if rem:
            self.pos += n - rem

    def cstr(self) -> str:
        start = self.pos
        while self.pos < len(self.data) and self.data[self.pos] != 0:
            self.pos += 1
        s = self.data[start : self.pos].decode("ascii", errors="replace")
        if self.pos < len(self.data):
            self.pos += 1
        return s

    def seek(self, pos: int) -> None:
        self.pos = pos


def read_skeleton(buf: Buf) -> list[dict[str, Any]]:
    bones_count = buf.u8()
    first_skel = buf.u8()
    bones: list[dict[str, Any]] = [
        {
            "name": "Origin",
            "parent_index": -1,
            "flags": 0,
            "childs_count": 0,
            "translation": [0.0, 0.0, 0.0],
            "quat": [0.0, 0.0, 0.0, 1.0],
            "first_skeleton_bone_index": first_skel,
        }
    ]
    for _ in range(1, bones_count):
        bones.append(
            {
                "name": "",
                "parent_index": buf.u8(),
                "flags": buf.u8(),
                "childs_count": buf.u8(),
                "translation": [0.0, 0.0, 0.0],
                "quat": [0.0, 0.0, 0.0, 1.0],
            }
        )
    for i in range(1, bones_count):
        bones[i]["name"] = buf.cstr()
    buf.align(4)
    for i in range(bones_count):
        tx, ty, tz = buf.f32(), buf.f32(), buf.f32()
        qx, qy, qz, qw = buf.f32(), buf.f32(), buf.f32(), buf.f32()
        bones[i]["translation"] = [tx, ty, tz]
        bones[i]["quat"] = [qx, qy, qz, qw]
    return bones


def read_motion(buf: Buf, skeleton: list[dict[str, Any]], index: int) -> dict[str, Any]:
    """Port of SPICA GF1Motion ctor (octal-packed S/R/T tracks)."""
    start = buf.pos
    octals_count = buf.u16()
    frames_count = buf.u16()
    octals = [0] * octals_count
    key_frames_count = 0
    current = 0
    for i in range(octals_count):
        if (i & 7) == 0:
            current = buf.u24()
        octals[i] = current & 7
        current >>= 3
        if octals[i] > 5:
            key_frames_count += 1

    frame16 = frames_count > 0xFF
    if frame16 and (buf.pos & 1) != 0:
        buf.u8()

    key_frames: list[list[int]] = []
    for _ in range(key_frames_count):
        count = buf.u16() if frame16 else buf.u8()
        frames = [0] * (count + 2)
        frames[count + 1] = frames_count
        for j in range(1, count + 1):
            frames[j] = buf.u16() if frame16 else buf.u8()
        key_frames.append(frames)

    buf.align(4)

    bone_out: list[dict[str, Any]] = []
    current_bone: dict[str, Any] | None = None
    current_kfl = 0
    octal_index = 2
    elem_index = 0
    old_index = -1

    axis_names = (
        "translation_x",
        "translation_y",
        "translation_z",
        "rotation_x",
        "rotation_y",
        "rotation_z",
        "scale_x",
        "scale_y",
        "scale_z",
    )

    while octal_index < octals_count:
        current_octal = octals[octal_index]
        octal_index += 1
        if current_octal != 1:
            bone_index = elem_index // 9
            if bone_index != old_index:
                if bone_index >= len(skeleton):
                    break
                sk = skeleton[bone_index]
                current_bone = {
                    "name": sk["name"],
                    "is_world_space": (sk["flags"] & 8) != 0,
                    "channels": {n: [] for n in axis_names},
                }
                bone_out.append(current_bone)
                old_index = bone_index
            assert current_bone is not None
            axis = axis_names[elem_index % 9]
            kfs: list[dict[str, float]] = current_bone["channels"][axis]
            if current_octal == 0:
                kfs.append({"frame": 0, "value": 0.0, "slope": 0.0})
            elif current_octal == 2:
                kfs.append({"frame": 0, "value": math.pi * 0.5, "slope": 0.0})
            elif current_octal == 3:
                kfs.append({"frame": 0, "value": math.pi, "slope": 0.0})
            elif current_octal == 4:
                kfs.append({"frame": 0, "value": -math.pi * 0.5, "slope": 0.0})
            elif current_octal == 5:
                kfs.append({"frame": 0, "value": buf.f32(), "slope": 0.0})
            elif current_octal == 6:
                for fr in key_frames[current_kfl]:
                    kfs.append({"frame": fr, "value": buf.f32(), "slope": 0.0})
                current_kfl += 1
            elif current_octal == 7:
                for fr in key_frames[current_kfl]:
                    kfs.append(
                        {"frame": fr, "value": buf.f32(), "slope": buf.f32()}
                    )
                current_kfl += 1
            elem_index += 1
        else:
            elem_index += 3

    # Drop empty channels
    for b in bone_out:
        b["channels"] = {k: v for k, v in b["channels"].items() if v}

    return {
        "index": index,
        "frames": frames_count,
        "octals_count": octals_count,
        "bones": bone_out,
        "byte_span": [start, buf.pos],
    }


def pbj_section0(data: bytes) -> tuple[int, int, bytes]:
    if data[:3] != b"PBJ":
        raise ValueError("not PBJ")
    o0 = struct.unpack_from("<I", data, 4)[0]
    o1 = struct.unpack_from("<I", data, 8)[0]
    return o0, o1, data[o0:o1]


def clip_names_from_pbj(data: bytes, s0_end: int) -> list[str]:
    """Ordered unique clip names from nested BCH region (material anim labels)."""
    region = data[s0_end:]
    seen: set[str] = set()
    ordered: list[str] = []
    for m in CLIP_RE.finditer(region.decode("latin1", errors="ignore")):
        name = m.group(0)
        if name not in seen:
            seen.add(name)
            ordered.append(name)
    if ordered:
        return ordered
    # Fallback: whole file order
    for m in CLIP_RE.finditer(data.decode("latin1", errors="ignore")):
        name = m.group(0)
        if name not in seen:
            seen.add(name)
            ordered.append(name)
    return ordered


def short_clip(name: str) -> str:
    # pm0255_00_ba20_buturi01 -> ba20_buturi01
    parts = name.split("_")
    if len(parts) >= 3:
        return "_".join(parts[2:])
    return name


def parse_pbj(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    o0, o1, blob = pbj_section0(data)
    buf = Buf(blob, 0)
    anims_count = buf.u32()
    # GF1MotionPack: seek to first address (skeleton)
    first_addr = buf.u32()
    buf.seek(first_addr)
    skeleton = read_skeleton(buf)
    clip_names = clip_names_from_pbj(data, o1)

    clips: list[dict[str, Any]] = []
    slot_addrs: list[int] = []
    for index in range(anims_count):
        # re-read address table from start
        addr = struct.unpack_from("<I", blob, 4 + index * 4)[0]
        slot_addrs.append(addr)

    name_i = 0
    for index in range(1, anims_count):
        addr = slot_addrs[index]
        if addr == 0:
            continue
        buf.seek(addr)
        try:
            motion = read_motion(buf, skeleton, index - 1)
        except Exception as exc:  # noqa: BLE001
            clips.append(
                {
                    "slot": index,
                    "error": str(exc),
                    "addr": addr,
                }
            )
            continue
        cname = clip_names[name_i] if name_i < len(clip_names) else f"slot_{index}"
        name_i += 1
        motion["name"] = cname
        motion["short"] = short_clip(cname)
        motion["role"] = _role_for(cname)
        motion["slot"] = index
        # Compact: count keyframes
        kf_total = sum(
            len(ch) for b in motion["bones"] for ch in b["channels"].values()
        )
        motion["keyframe_count"] = kf_total
        clips.append(motion)

    # National from clip name
    national = 0
    form = 0
    for c in clip_names:
        m = re.match(r"pm(\d{4})_(\d{2})_", c)
        if m:
            national = int(m.group(1))
            form = int(m.group(2))
            break

    roles = {c["role"]: c["short"] for c in clips if "role" in c and "error" not in c}
    return {
        "file": str(path),
        "stem": path.stem,
        "kind": "PBJ",
        "size": len(data),
        "section0": [o0, o1],
        "anims_count_field": anims_count,
        "skeleton_bone_count": len(skeleton),
        "skeleton": skeleton,
        "clip_names_bch": clip_names,
        "clips": clips,
        "roles": roles,
        "national": national,
        "form": form,
        "skeletal_status": "gf1_decoded",
        "anim_source_label": "pbj_gf1",
        "decoder": "SPICA GF1Motion / GF1MotionPack port",
    }


def default_cache() -> Path:
    import os

    base = os.environ.get("APPDATA") or str(Path.home())
    return Path(base) / "LOVE" / "pokemon-love2d" / "oras_extract"


def compact_clip(c: dict[str, Any]) -> dict[str, Any]:
    """Drop byte spans for smaller cache JSON; keep playback fields."""
    if "error" in c:
        return c
    return {
        "name": c.get("name"),
        "short": c.get("short"),
        "role": c.get("role"),
        "slot": c.get("slot"),
        "index": c.get("index"),
        "frames": c.get("frames"),
        "keyframe_count": c.get("keyframe_count"),
        "bones": c.get("bones"),
    }


def write_clip_file(info: dict[str, Any], dest: Path) -> None:
    out = {
        "stem": info["stem"],
        "national": info["national"],
        "form": info["form"],
        "skeletal_status": info["skeletal_status"],
        "anim_source_label": info["anim_source_label"],
        "skeleton_bone_count": info["skeleton_bone_count"],
        "skeleton": [
            {
                "name": b["name"],
                "parent_index": b["parent_index"],
                "flags": b["flags"],
                "translation": b["translation"],
                "quat": b["quat"],
            }
            for b in info["skeleton"]
        ],
        "roles": info["roles"],
        "clips": [compact_clip(c) for c in info["clips"]],
    }
    dest.write_text(json.dumps(out, separators=(",", ":")), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cache", type=Path, default=None)
    ap.add_argument(
        "--files",
        nargs="*",
        default=None,
        help="PBJ stems (default: samples; --all for every PBJ)",
    )
    ap.add_argument("--all", action="store_true", help="Rip every PBJ in a/0/0/8")
    ap.add_argument(
        "--nationals-from-mesh-index",
        action="store_true",
        help="Rip PBJ N+5 for every mesh_index national",
    )
    ap.add_argument(
        "--mesh-index",
        type=Path,
        default=None,
        help="Path to mesh_index.json (mod .local or cache)",
    )
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args(argv)
    cache = args.cache or default_cache()
    root = cache / "garc_unpacked" / "a" / "0" / "0" / "8"
    out = cache / "anims"
    out.mkdir(parents=True, exist_ok=True)

    stems: list[str] = []
    if args.all:
        for p in sorted(root.glob("*.bin")):
            if p.read_bytes()[:3] == b"PBJ":
                stems.append(p.stem)
    elif args.nationals_from_mesh_index:
        mi = args.mesh_index
        if mi is None:
            # Prefer mod .local copy if present beside extract/
            here = Path(__file__).resolve().parents[1] / ".local" / "mesh_index.json"
            mi = here if here.is_file() else cache / "mesh_index.json"
        idx = json.loads(mi.read_text(encoding="utf-8"))
        seen: set[str] = set()
        for _nat, row in idx.get("by_national", {}).items():
            rel = str(row.get("mesh_rel") or "").replace("\\", "/")
            parts = [p for p in rel.split("/") if p]
            stem = None
            for part in reversed(parts):
                if part.isdigit() and len(part) >= 4:
                    stem = part
                    break
            if not stem:
                for part in reversed(parts):
                    if part.isdigit():
                        stem = part
                        break
            if not stem:
                continue
            pbj_stem = f"{int(stem) + 5:04d}"
            if pbj_stem not in seen:
                seen.add(pbj_stem)
                stems.append(pbj_stem)
    else:
        stems = list(args.files or ["2832", "0504", "4176"])

    if args.limit and args.limit > 0:
        stems = stems[: args.limit]

    index: dict[str, Any] = {
        "phase": "pbj_gf1",
        "decoder": "SPICA GF1Motion port",
        "files": [],
        "by_stem": {},
        "by_national": {},
        "stats": {
            "ok": 0,
            "fail": 0,
            "clips_total": 0,
            "with_attack_physical": 0,
            "with_attack_special": 0,
        },
    }

    for stem in stems:
        src = root / f"{stem}.bin"
        if not src.is_file():
            print(f"missing {src}")
            index["stats"]["fail"] += 1
            continue
        try:
            info = parse_pbj(src)
        except Exception as exc:  # noqa: BLE001
            print(f"FAIL {stem}: {exc}")
            index["stats"]["fail"] += 1
            index["by_stem"][stem] = {"error": str(exc)}
            continue
        dest = out / f"{stem}_clips.json"
        write_clip_file(info, dest)
        ok_clips = [c for c in info["clips"] if "error" not in c]
        entry = {
            "kind": "PBJ",
            "national": info["national"],
            "form": info["form"],
            "clips": len(ok_clips),
            "roles": info["roles"],
            "bone_count": info["skeleton_bone_count"],
            "rel": dest.name,
            "skeletal_status": "gf1_decoded",
        }
        index["files"].append(str(dest))
        index["by_stem"][stem] = entry
        if info["national"]:
            index["by_national"][str(info["national"])] = {
                "stem": stem,
                "form": info["form"],
                "roles": info["roles"],
                "rel": dest.name,
                "clips": len(ok_clips),
            }
        index["stats"]["ok"] += 1
        index["stats"]["clips_total"] += len(ok_clips)
        if "attack_physical" in info["roles"]:
            index["stats"]["with_attack_physical"] += 1
        if "attack_special" in info["roles"]:
            index["stats"]["with_attack_special"] += 1
        print(
            f"wrote {dest.name} nat={info['national']} "
            f"clips={len(ok_clips)} bones={info['skeleton_bone_count']} "
            f"roles={list(info['roles'])}"
        )

    (out / "pbj_index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")
    # Slim national lookup for runtime
    slim = {
        "phase": "pbj_gf1",
        "by_national": index["by_national"],
        "stats": index["stats"],
    }
    (out / "anim_by_national.json").write_text(
        json.dumps(slim, indent=2), encoding="utf-8"
    )
    print(f"wrote {out / 'pbj_index.json'} stats={index['stats']}")
    return 0 if index["stats"]["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
