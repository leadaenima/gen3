#!/usr/bin/env python3
"""National ORAS battle-sheet color fix pipeline.

1) Re-rip a/0/0/8 BCH textures with current bch_tex (RGB8 BGR->RGB).
2) Detect near-greyscale Body2/Eye2/Fire* albedo sheets.
3) For Petal/Flower mesh parts: bake Body2*_colorized / keep *_petal.
4) For FireCore/FireSten: bake colorized from material constants.
5) Emit material color index + report.
6) Does NOT commit; writes only under AppData oras_extract (+ LIVE tmp report).
"""
from __future__ import annotations

import json
import struct
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

from PIL import Image
import numpy as np

LIVE = Path(r"C:\Users\Feces\Desktop\backup pkmn\97 - Copy\gen1recomp-dev")
EXTRACT = LIVE / "mods" / "oras_models" / "extract"
sys.path.insert(0, str(EXTRACT))

from bch_tex import rip_bch_textures, BCH_FMT_NAMES  # noqa: E402
from bch_mesh import (  # noqa: E402
    _apply_bch_relocations,
    _u32,
    _read_cstr,
    _f32,
    _material_shader_name,
    pick_diffuse_texture,
    _is_secondary_albedo_shader,
    _part_wants_secondary_sheet,
)

CACHE = Path(r"C:\Users\Feces\AppData\Roaming\Love\pokemon-love2d\oras_extract")
GARC = CACHE / "garc_unpacked" / "a" / "0" / "0" / "8"
TEX_OUT = CACHE / "textures" / "a" / "0" / "0" / "8"
MESH_IDX = CACHE / "meshes" / "mesh_index.json"
REPORT = LIVE / "tmp" / "oras_national_colorize_report.txt"

CHROMA_GREY = 40.0  # mean |r-g|+|g-b|+|b-r| below => near-greyscale


def sheet_chroma(path: Path) -> float:
    im = np.array(Image.open(path).convert("RGBA"), dtype=np.int16)
    op = im[im[:, :, 3] > 8]
    if len(op) < 16:
        return 0.0
    return float(
        (np.abs(op[:, 0] - op[:, 1]) + np.abs(op[:, 1] - op[:, 2]) + np.abs(op[:, 2] - op[:, 0])).mean()
    )


def parse_materials(bch_path: Path) -> list[dict]:
    data = bytearray(bch_path.read_bytes())
    if data[:3] != b"BCH":
        return []
    meta = _apply_bch_relocations(data)
    bc = meta["bc"]
    main = meta["main"]
    models_ptr = _u32(data, main)
    if not models_ptr:
        return []
    moff = _u32(data, models_ptr)
    off = moff + 4 + 48
    mats_off = _u32(data, off)
    mats_n = _u32(data, off + 4)
    esz = 0x2C if bc >= 0x21 else 0x58
    out = []
    for i in range(mats_n):
        ment = mats_off + i * esz
        params = _u32(data, ment)
        if bc >= 0x21:
            n0 = _u32(data, ment + 0x1C)
            n1 = _u32(data, ment + 0x20)
            nm = _u32(data, ment + 0x28)
        else:
            n0 = _u32(data, ment + 0x48)
            n1 = _u32(data, ment + 0x4C) if esz >= 0x50 else 0
            nm = 0
        unit0 = _read_cstr(data, n0) or ""
        unit1 = _read_cstr(data, n1) or ""
        name = _read_cstr(data, nm) or ""
        shader = _material_shader_name(data, ment, esz)
        colors = {}
        if params and params + 0x80 < len(data):
            p = params + 4 + 4 + 4 + 3 * 24 + 4
            for nm_c in (
                "emission",
                "ambient",
                "diffuse",
                "specular0",
                "specular1",
                "constant0",
                "constant1",
                "constant2",
                "constant3",
                "constant4",
                "constant5",
                "blend",
            ):
                colors[nm_c] = tuple(int(x) for x in data[p : p + 4])
                p += 4
        diffuse = pick_diffuse_texture(unit0, unit1, shader, part_name="")
        out.append(
            {
                "name": name,
                "shader": shader,
                "unit0": unit0,
                "unit1": unit1,
                "diffuse": diffuse,
                "colors": colors,
            }
        )
    return out


def colorize_multiply(src: Path, rgb: tuple[float, float, float], dest: Path) -> None:
    """Greyscale intensity * color (matches prior petal bake ~lum*C)."""
    im = np.array(Image.open(src).convert("RGBA"), dtype=np.float32)
    lum = (im[:, :, 0] + im[:, :, 1] + im[:, :, 2]) / 3.0
    out = im.copy()
    for c in range(3):
        out[:, :, c] = np.clip(lum * (rgb[c] / 128.0), 0, 255)
    Image.fromarray(out.astype(np.uint8), "RGBA").save(dest)


def pick_fire_color(colors: dict) -> tuple[float, float, float]:
    for key in ("constant3", "constant4", "constant0"):
        c = colors.get(key)
        if not c:
            continue
        r, g, b, a = c
        if r + g + b < 30:
            continue
        if abs(r - g) + abs(g - b) + abs(b - r) < 20 and r < 200:
            continue  # skip grey
        return (float(r), float(g), float(b))
    return (255.0, 140.0, 40.0)  # default flame


def pick_petal_color(body1: Path | None, colors: dict) -> tuple[float, float, float]:
    # Prefer warm non-grey from Body1 if available; else constant; else classic flower orange.
    if body1 and body1.is_file():
        im = np.array(Image.open(body1).convert("RGBA"), dtype=np.int16)
        op = im[im[:, :, 3] > 200]
        if len(op) > 100:
            # take high-chroma warm pixels
            chroma = np.abs(op[:, 0] - op[:, 1]) + np.abs(op[:, 1] - op[:, 2]) + np.abs(op[:, 2] - op[:, 0])
            warm = op[(chroma > 80) & (op[:, 0] > op[:, 2])]
            if len(warm) > 50:
                m = warm[:, :3].mean(0)
                return (float(m[0]), float(m[1]), float(m[2]))
    c0 = colors.get("constant0")
    if c0 and (abs(c0[0] - c0[1]) + abs(c0[1] - c0[2]) + abs(c0[2] - c0[0])) > 30:
        return (float(c0[0]), float(c0[1]), float(c0[2]))
    return (200.0, 70.0, 40.0)


def rerip_all_bch() -> dict:
    t0 = time.time()
    written = 0
    bch_ok = 0
    bch_fail = 0
    fmt_counts: Counter = Counter()
    # Prefer .bch; also PT-wrapped .bin that contain BCH at 0x80 (type1 textures)
    files = sorted(GARC.glob("*.bch"))
    for src in files:
        try:
            texs = rip_bch_textures(src)
        except Exception:
            bch_fail += 1
            continue
        if not texs:
            bch_fail += 1
            continue
        bch_ok += 1
        dest_dir = TEX_OUT / src.stem
        dest_dir.mkdir(parents=True, exist_ok=True)
        for tex in texs:
            safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in tex.name)
            dest = dest_dir / f"{safe}.png"
            # Preserve existing colorized sidecars; overwrite base albedo
            tex.image.save(dest)
            written += 1
            fmt_counts[tex.fmt_name] += 1
    return {
        "bch_ok": bch_ok,
        "bch_fail": bch_fail,
        "png_written": written,
        "fmt_counts": dict(fmt_counts),
        "elapsed_s": round(time.time() - t0, 1),
    }


def national_colorize() -> dict:
    idx = json.loads(MESH_IDX.read_text(encoding="utf-8"))
    models = idx["models"]
    stats = Counter()
    flags = []
    colorized = []
    mat_index = {}  # national -> materials summary

    for row in models:
        nat = row["national"]
        form = row.get("form", 0)
        src = Path(row["source"])
        # source like a/0/0/8/0043.bch
        stem = Path(row["rel"]).parent.name if row.get("rel") else src.stem
        model_bch = GARC / f"{stem}.bch"
        if not model_bch.is_file():
            stats["missing_model"] += 1
            continue
        mats = parse_materials(model_bch)
        mat_index[f"{nat}_{form}"] = [
            {"name": m["name"], "shader": m["shader"], "diffuse": m["diffuse"], "c0": m["colors"].get("constant0")}
            for m in mats
        ]

        # Resolve texture folder: mesh stem N -> textures often N+2 (model, meta, tex)
        # Prefer folders that contain pm#### sheets matching model name
        pm = row.get("name") or f"pm{nat:04d}_{form:02d}"
        tex_dirs = []
        for d in TEX_OUT.iterdir() if TEX_OUT.exists() else []:
            if not d.is_dir():
                continue
            if any(d.glob(f"{pm}_Body*.png")) or any(d.glob(f"{pm}_BodyA*.png")):
                tex_dirs.append(d)
        if not tex_dirs:
            # fallback: stem+2 pattern
            for delta in (2, 1, 3, 0, 4):
                cand = TEX_OUT / f"{int(stem)+delta:04d}"
                if cand.is_dir():
                    tex_dirs.append(cand)
                    break

        # Load mesh parts for petal detection
        mesh_path = Path(row["path"])
        parts = []
        if mesh_path.is_file():
            try:
                md = json.loads(mesh_path.read_text(encoding="utf-8"))
                parts = md.get("meshes") or []
            except Exception:
                parts = []

        petal_parts = [
            p
            for p in parts
            if _part_wants_secondary_sheet(p.get("name") or "")
            or "petal" in (p.get("name") or "").lower()
        ]
        fire_parts = [p for p in parts if "fire" in (p.get("texture") or "").lower() or "fire" in (p.get("material_shader") or "").lower()]

        for td in tex_dirs:
            # Petal Body2 colorize
            if petal_parts:
                for body2 in list(td.glob(f"{pm}_Body2.png")) + list(td.glob(f"{pm}_BodyB2.png")):
                    chroma = sheet_chroma(body2)
                    petal_dest = body2.with_name(body2.stem + "_petal.png")
                    color_dest = body2.with_name(body2.stem + "_colorized.png")
                    if chroma < CHROMA_GREY:
                        body1 = td / f"{pm}_Body1.png"
                        if not body1.exists():
                            body1 = td / f"{pm}_BodyA1.png"
                        # material colors from BodyB / Body01
                        cols = {}
                        for m in mats:
                            if _is_secondary_albedo_shader(m["shader"]) or "bodyb" in m["name"].lower() or "body01" in m["name"].lower():
                                cols = m["colors"]
                                break
                        rgb = pick_petal_color(body1 if body1.exists() else None, cols)
                        colorize_multiply(body2, rgb, color_dest)
                        if not petal_dest.exists():
                            colorize_multiply(body2, rgb, petal_dest)
                        colorized.append(str(color_dest))
                        stats["petal_colorized"] += 1
                    else:
                        stats["petal_already_chroma"] += 1

            # Fire intensity sheets
            for fire in list(td.glob("Fire*.png")):
                if fire.name.endswith("_colorized.png") or "Mask" in fire.name or "Nor" in fire.name:
                    continue
                chroma = sheet_chroma(fire)
                if chroma >= CHROMA_GREY:
                    continue
                cols = {}
                for m in mats:
                    if "fire" in m["name"].lower() or "fire" in (m["shader"] or "").lower():
                        cols = m["colors"]
                        break
                rgb = pick_fire_color(cols)
                dest = fire.with_name(fire.stem + "_colorized.png")
                colorize_multiply(fire, rgb, dest)
                colorized.append(str(dest))
                stats["fire_colorized"] += 1

            # Greyscale Body2 used by non-petal Body01: leave as shadow map (binding fix handles it)
            for body2 in td.glob(f"{pm}_Body2.png"):
                if sheet_chroma(body2) < CHROMA_GREY:
                    stats["grey_body2"] += 1

        stats["models_ok"] += 1

    # write material index
    mat_path = CACHE / "material_color_index.json"
    mat_path.write_text(json.dumps({"count": len(mat_index), "by_key": mat_index}, indent=1), encoding="utf-8")

    return {
        "stats": dict(stats),
        "colorized_count": len(colorized),
        "colorized_sample": colorized[:30],
        "material_index": str(mat_path),
        "flags": flags,
    }


def main():
    lines = []
    lines.append("=== ORAS national colorize pipeline ===")
    lines.append(f"cache={CACHE}")
    lines.append("")
    lines.append("--- phase1: re-rip a/0/0/8 BCH textures (BGR-fixed RGB8) ---")
    print(lines[-1])
    rip = rerip_all_bch()
    lines.append(json.dumps(rip, indent=2))
    print("rerip", rip)

    lines.append("")
    lines.append("--- phase2: national colorize intensity albedos ---")
    print(lines[-1])
    col = national_colorize()
    lines.append(json.dumps({k: col[k] for k in col if k != "flags"}, indent=2))
    print("colorize stats", col["stats"], "n=", col["colorized_count"])

    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", REPORT)


if __name__ == "__main__":
    main()