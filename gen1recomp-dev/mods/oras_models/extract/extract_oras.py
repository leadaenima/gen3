#!/usr/bin/env python3
"""Extract / probe a user-owned Omega Ruby (3DS) dump for mods/oras_models.

HARD RULES:
  - Never download Spriters Resource / Models Resource assets.
  - Never write Nintendo images into mods/oras_models assets/ or git.
  - Cache goes under %%APPDATA%%/LOVE/pokemon-love2d/oras_extract/ (or
    --cache) plus a sandbox-readable status copy at
    mods/oras_models/.local/status.json.

Pipeline:
  1. Probe zip / .3ds / RomFS tree.
  2. --extract-3ds: 7-Zip Deflate64 zip -> .3ds in cache (~2 GiB).
  3. --extract-romfs: ctrtool -p --contents, -p --ncch=0 --romfs=,
     then --romfsdir= into cache/romfs (or resume from existing pieces).
  4. Index PNG/JPG/BCH under RomFS into status.json for the mod.
  5. --extract-garc: unpack priority CRAG archives (pokemon/battle/OW)
     into cache/garc_unpacked/ via pure-Python garc_tools.py (+ LZ11).
  6. --extract-textures: BCH + BCLIM -> PNG under cache/textures/ only
     (pure-Python bch_tex.py; never mods/oras_models/assets or git).

Tools:
  Prefer PATH / Program Files. Otherwise use cache/tools/ (user-local,
  never git). ctrtool v1.3.0 + 3dstool v1.2.6 are expected there.
  GARC unpacker is mods/oras_models/extract/garc_tools.py (no Nintendo
  binaries required).
"""

from __future__ import annotations

import argparse
import json
import re
import os
import shutil
import struct
import subprocess
import sys
import time
import zipfile
from pathlib import Path

IMAGE_EXT = {".png", ".jpg", ".jpeg", ".bmp", ".tga", ".gif", ".webp"}
MODEL_EXT = {".bch", ".obj", ".gltf", ".glb", ".smd", ".dae"}
CONTAINER_EXT = {".3ds", ".cci", ".cxi", ".cia", ".app", ".ncch"}

# Documented ORAS RomFS a/** GARC roles (community notes / pk3DS).
# Full 298 is huge — prioritize battle/OW models & textures first.
GARC_PRIORITY = [
    ("a/0/0/8", "pokemon_models"),
    ("a/0/2/1", "trainer_overworld_models"),
    ("a/1/3/3", "trainer_battle_models"),
    ("a/0/1/4", "map_textures"),
    ("a/0/3/9", "map_models"),
    ("a/1/6/0", "trainer_mugshots"),
    ("a/0/9/1", "pokemon_icons"),  # 40x30 box/party icons (closest 2D mon art; NOT battle sprites)
    ("a/0/3/1", "move_effects"),  # 2040 CGFX battle particle/effect packs
    ("a/0/3/4", "battle_anim_sesd"),  # 976 SESD move animation scripts (NOT pokeballs)
    ("a/1/0/4", "pokeball_models"),
    ("a/0/0/7", "pokemon_model_related"),
]

DEFAULT_SOURCE = (
    r"C:\Users\Feces\Desktop\Pokemon Omega Ruby (USA) "
    r"(En,Ja,Fr,De,Es,It,Ko) (Rev 2) Decrypted.zip"
)


def appdata_cache() -> Path:
    base = os.environ.get("APPDATA") or os.environ.get("HOME") or "."
    return Path(base) / "LOVE" / "pokemon-love2d" / "oras_extract"


def find_7z() -> str | None:
    for cand in (
        shutil.which("7z"),
        shutil.which("7za"),
        r"C:\Program Files\7-Zip\7z.exe",
        r"C:\Program Files (x86)\7-Zip\7z.exe",
    ):
        if cand and Path(cand).is_file():
            return cand
    return None


def find_tool(name: str, cache: Path) -> str | None:
    """Find ctrtool/3dstool on PATH or under cache/tools/."""
    which = shutil.which(name) or shutil.which(f"{name}.exe")
    if which and Path(which).is_file():
        return which
    tools = cache / "tools"
    if tools.is_dir():
        for p in tools.rglob(f"{name}.exe"):
            return str(p)
        for p in tools.rglob(name):
            if p.is_file():
                return str(p)
    return None


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_status(cache: Path, mod_root: Path, payload: dict) -> None:
    payload.setdefault(
        "probed_at", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    )
    write_json(cache / "status.json", payload)
    write_json(mod_root / ".local" / "status.json", payload)



def build_battle_texture_map(textures: list[dict]) -> dict:
    """Map national dex -> battle front/back paths.

    ORAS battles are 3D: RomFS has no Gen5-style 2D battle front/back sprites.
    a/0/0/8 pm####_Body* sheets are model UV atlases — never use those for
    battlePic (they render as noisy rectangular blocks).

    Preference order when present and valid:
      1. explicit battle_front / battle_back roles
      2. a/0/9/1 poke icons (40x30) — only if decode looks coherent
    Otherwise by_national stays empty so Game3 keeps Gen3 sprites.
    Mugshots (a/1/6/0) remain separate.
    """
    from collections import Counter

    front: dict[int, tuple[int, str, str]] = {}  # nat -> (score, path, source_class)
    back: dict[int, tuple[int, str, str]] = {}
    mugshots: list[tuple[str, str]] = []
    icon_by_idx: dict[int, str] = {}

    def consider(bucket: dict, nat: int, score: int, path: str, source_class: str) -> None:
        prev = bucket.get(nat)
        if prev is None or score > prev[0]:
            bucket[nat] = (score, path, source_class)

    for t in textures:
        name = str(t.get("name") or "")
        path = t.get("path")
        rel = str(t.get("rel") or "").replace("\\", "/")
        if not isinstance(path, str) or not path:
            continue
        if rel.startswith("a/1/6/0/"):
            mugshots.append((rel, path))
            continue

        # Never map model body UV atlases into battle slots.
        if re.match(r"pm\d+_\d+_Body", name) or "Body" in name and rel.startswith("a/0/0/8/"):
            continue

        role = str(t.get("role") or "")
        w = int(t.get("width") or 0)
        h = int(t.get("height") or 0)

        if role in ("battle_front", "battle_back") or "battle_front" in rel or "battle_back" in rel:
            m = re.search(r"(\d{3,4})", name) or re.search(r"/(\d{3,4})\.", rel)
            if m:
                nat = int(m.group(1))
                sc = "battle_front" if "back" not in role and "back" not in rel else "battle_back"
                if sc == "battle_front":
                    consider(front, nat, 100, path, sc)
                else:
                    consider(back, nat, 100, path, sc)
            continue

        # Poke icons: a/0/9/1/NNN.png — index ~= national dex for base forms.
        if rel.startswith("a/0/9/1/"):
            m = re.search(r"/(\d{3,4})(?:\.|$)", rel) or re.match(r"^(\d+)$", name)
            if not m:
                continue
            idx = int(m.group(1))
            if w and h and not (20 <= w <= 64 and 20 <= h <= 64):
                continue
            icon_by_idx[idx] = path

    # Auto-map icons only after BCLIM decode is verified (currently scattered texels).
    use_icons = False
    if use_icons:
        for idx, path in icon_by_idx.items():
            if idx <= 0:
                continue
            consider(front, idx, 50, path, "poke_icon")
            consider(back, idx, 40, path, "poke_icon")

    by_national: dict[str, dict] = {}
    for nat in sorted(set(front) | set(back)):
        row: dict[str, str] = {}
        srcs: list[str] = []
        if nat in front:
            row["front"] = front[nat][1]
            row["front_source"] = front[nat][2]
            srcs.append(front[nat][2])
        if nat in back:
            row["back"] = back[nat][1]
            row["back_source"] = back[nat][2]
            srcs.append(back[nat][2])
        if "front" in row and "back" not in row:
            row["back"] = row["front"]
            row["back_source"] = row.get("front_source", "poke_icon")
        if "back" in row and "front" not in row:
            row["front"] = row["back"]
            row["front_source"] = row.get("back_source", "poke_icon")
        row["source_class"] = srcs[0] if srcs else "none"
        by_national[str(nat)] = row

    mugshots.sort(key=lambda x: x[0])
    source_class = "none"
    if by_national:
        c = Counter(r.get("source_class") for r in by_national.values())
        source_class = c.most_common(1)[0][0]
    return {
        "by_national": by_national,
        "mugshots": [p for _, p in mugshots],
        "meta": {
            "front_count": len(front),
            "back_count": len(back),
            "mugshot_count": len(mugshots),
            "icon_candidates": len(icon_by_idx),
            "source_class": source_class,
            "note": (
                "ORAS has no Gen5-style 2D battle front/back sprites (3D battles). "
                "a/0/0/8 Body* UV atlases are intentionally excluded. "
                "Closest 2D mon art is a/0/9/1 poke icons (40x30); auto-map disabled "
                "until BCLIM decode is verified. Battle pics stay Gen3 meanwhile."
            ),
        },
    }



def publish_mod_texture_sidecars(mod_root: Path, index_path: Path | None, textures: list[dict] | None = None) -> None:
    """Sandbox-readable copies under mods/oras_models/.local/ (never PNGs)."""
    local = mod_root / ".local"
    local.mkdir(parents=True, exist_ok=True)
    if index_path and Path(index_path).is_file():
        dest = local / "texture_index.json"
        data = Path(index_path).read_bytes()
        dest.write_bytes(data)
        if textures is None:
            try:
                obj = json.loads(data.decode("utf-8"))
                textures = obj.get("textures") if isinstance(obj, dict) else None
            except Exception:  # noqa: BLE001
                textures = None
    if isinstance(textures, list) and textures:
        write_json(local / "battle_texture_map.json", build_battle_texture_map(textures))


def probe_ncsd_header(data: bytes) -> dict:
    out: dict = {"size": len(data)}
    if len(data) < 0x200:
        out["magic"] = None
        out["note"] = "header too short"
        return out
    magic = data[0x100:0x104]
    out["magic"] = magic.decode("ascii", errors="replace")
    out["is_ncsd"] = magic == b"NCSD"
    if magic == b"NCSD":
        off_mu, size_mu = struct.unpack_from("<II", data, 0x120)
        out["partition0_offset"] = off_mu * 0x200
        out["partition0_size"] = size_mu * 0x200
        out["note"] = (
            "decrypted NCSD (.3ds). Next: ctrtool -p --contents / "
            "--romfs on partition 0, then --romfsdir."
        )
    elif magic == b"NCCH":
        out["is_ncch"] = True
        out["note"] = "NCCH/CXI -- use ctrtool -p --romfsdir to unpack RomFS"
    else:
        out["note"] = "unrecognized header; may already be a RomFS dump"
    return out


def index_tree(root: Path) -> tuple[list[dict], list[dict]]:
    textures: list[dict] = []
    models: list[dict] = []
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            p = Path(dirpath) / name
            rel = str(p.relative_to(root)).replace("\\", "/")
            ext = p.suffix.lower()
            if ext in IMAGE_EXT:
                textures.append(
                    {
                        "id": "ORAS_"
                        + rel.replace("/", "_").replace(".", "_").upper(),
                        "path": str(p),
                        "rel": rel,
                    }
                )
            elif ext in MODEL_EXT:
                models.append({"rel": rel, "path": str(p)})
    return textures, models


def list_zip(path: Path) -> list[zipfile.ZipInfo]:
    with zipfile.ZipFile(path, "r") as zf:
        return list(zf.infolist())


def zip_compress_name(code: int) -> str:
    return {
        0: "stored",
        8: "deflate",
        9: "deflate64",
        12: "bzip2",
        14: "lzma",
    }.get(code, f"method_{code}")


def run_logged(cmd: list[str], log_path: Path) -> int:
    print(f"$ {' '.join(cmd)}", flush=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
        )
        assert proc.stdout is not None
        for line in proc.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            log.write(line)
        return proc.wait()


def probe_zip(path: Path, cache: Path, seven: str | None) -> dict:
    try:
        infos = list_zip(path)
    except Exception as exc:  # noqa: BLE001
        return {
            "ok": False,
            "kind": "zip_unreadable",
            "message": f"zip open failed: {exc}",
            "needs_ctrtool": True,
        }

    names = [i.filename for i in infos if not i.is_dir()]
    entry_count = len(names)
    compress_methods = sorted({i.compress_type for i in infos})

    imageish = [n for n in names if Path(n).suffix.lower() in IMAGE_EXT]
    modelish = [n for n in names if Path(n).suffix.lower() in MODEL_EXT]
    if imageish or modelish:
        out_dir = cache / "romfs_tree"
        out_dir.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path, "r") as zf:
            for name in imageish + modelish:
                zf.extract(name, out_dir)
        textures, models = index_tree(out_dir)
        return {
            "ok": True,
            "kind": "zip_file_tree",
            "message": "zip contained image/model files; indexed under cache/romfs_tree",
            "entry_count": entry_count,
            "texture_count": len(textures),
            "model_count": len(models),
            "texture_index": textures[:500],
            "needs_ctrtool": False,
            "compress_methods": [zip_compress_name(m) for m in compress_methods],
        }

    containers = [n for n in names if Path(n).suffix.lower() in CONTAINER_EXT]
    if len(containers) == 1 and entry_count == 1:
        inner = containers[0]
        info = next(i for i in infos if i.filename == inner)
        method = zip_compress_name(info.compress_type)
        header = {
            "inner_name": inner,
            "file_size": info.file_size,
            "compress_size": info.compress_size,
            "compress_method": method,
        }
        header_bytes = b""
        header_err = None
        if info.compress_type == 9:
            if not seven:
                header_err = (
                    "zip uses Deflate64; install 7-Zip and re-run to probe NCSD magic"
                )
            else:
                try:
                    proc = subprocess.run(
                        [seven, "e", str(path), "-so", inner],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                        check=False,
                    )
                    header_bytes = proc.stdout[:512]
                except Exception as exc:  # noqa: BLE001
                    header_err = f"7z stream failed: {exc}"
        else:
            try:
                with zipfile.ZipFile(path, "r") as zf:
                    with zf.open(inner) as fh:
                        header_bytes = fh.read(512)
            except Exception as exc:  # noqa: BLE001
                header_err = str(exc)

        ncsd = probe_ncsd_header(header_bytes) if header_bytes else {}
        if header_err:
            ncsd["read_error"] = header_err

        tip = (
            "This dump is a decrypted .3ds inside a zip, not a RomFS PNG tree. "
            "Next: --extract-3ds then --extract-romfs "
            "(ctrtool -p --contents / --romfs / --romfsdir)."
        )
        return {
            "ok": False,
            "kind": "zip_ncsd_container",
            "message": tip,
            "entry_count": entry_count,
            "texture_count": 0,
            "model_count": 0,
            "needs_ctrtool": True,
            "container": header,
            "ncsd": ncsd,
            "compress_methods": [zip_compress_name(m) for m in compress_methods],
            "seven_zip": seven,
        }

    return {
        "ok": False,
        "kind": "zip_unknown",
        "message": f"zip has {entry_count} file(s); no images and no single .3ds/cxi/cia",
        "entry_count": entry_count,
        "sample_names": names[:40],
        "needs_ctrtool": True,
        "compress_methods": [zip_compress_name(m) for m in compress_methods],
    }


def probe_file(path: Path) -> dict:
    data = path.read_bytes()[:512]
    ncsd = probe_ncsd_header(data)
    return {
        "ok": False,
        "kind": "raw_container",
        "message": ncsd.get("note")
        or "raw container -- run ctrtool to unpack RomFS, then re-run on that folder",
        "texture_count": 0,
        "model_count": 0,
        "needs_ctrtool": True,
        "ncsd": ncsd,
        "entry_count": 1,
    }


def count_garc(root: Path) -> int:
    n = 0
    a_root = root / "a" if (root / "a").is_dir() else root
    for p in a_root.rglob("*"):
        if not p.is_file():
            continue
        try:
            with p.open("rb") as fh:
                if fh.read(4) == b"CRAG":
                    n += 1
        except OSError:
            continue
    return n


def probe_dir(path: Path) -> dict:
    textures, models = index_tree(path)
    garc_count = count_garc(path)
    file_count = sum(1 for _dp, _dn, fn in os.walk(path) for _ in fn)
    ok = True
    needs_ctrtool = len(textures) == 0 and len(models) == 0 and garc_count == 0
    msg = (
        f"indexed {len(textures)} image(s), {len(models)} model-ish, "
        f"{garc_count} GARC(CRAG); {file_count} files total"
    )
    if garc_count and not textures:
        msg += ". Next: unpack GARC then BCH/texture rip (cache only)."
    return {
        "ok": ok,
        "kind": "romfs_extracted" if garc_count else "directory_tree",
        "message": msg,
        "texture_count": len(textures),
        "model_count": len(models),
        "archive_count": garc_count,
        "file_count": file_count,
        "texture_index": textures[:500],
        "needs_ctrtool": needs_ctrtool,
        "needs_garc": garc_count > 0 and len(textures) == 0,
        "romfs_dir": str(path),
        "entry_count": len(textures) + len(models) + garc_count,
        "next_steps": [
            "Unpack GARC (CRAG) under a/0/**",
            "Find Pokemon BCH + textures inside GARC",
            "Rip textures to PNG in user cache (never git)",
            "Re-run this script on the PNG tree to fill texture_index",
        ] if garc_count and not textures else [],
    }


def find_3ds_in_cache(cache: Path) -> Path | None:
    for p in sorted(cache.glob("*.3ds")):
        if p.is_file() and p.stat().st_size > 0:
            return p
    return None


def extract_3ds_from_zip(
    source: Path, cache: Path, seven: str, inner: str
) -> Path:
    dest = cache / Path(inner).name
    print(f"extracting {inner} -> {dest} (this is ~2 GiB)...", flush=True)
    log = cache / "extract_3ds.log"
    code = run_logged(
        [seven, "e", str(source), f"-o{cache}", "-y", "-bsp1", inner], log
    )
    if code != 0 or not dest.is_file():
        raise RuntimeError(f"7z extract failed (exit={code}) dest={dest}")
    return dest


def extract_romfs(
    cache: Path, three_ds: Path, ctrtool: str, tool_3dstool: str | None = None
) -> dict:
    """Extract NCCH0 RomFS binary + directory. Uses -p for pre-decrypted dumps.

    Directory unpack prefers 3dstool (more reliable on pre-decrypted ORAS);
    falls back to ctrtool --romfsdir.
    """
    contents = cache / "contents"
    romfs_bin = cache / "partition0.romfs"
    romfs_dir = cache / "romfs"
    contents.mkdir(parents=True, exist_ok=True)
    romfs_dir.mkdir(parents=True, exist_ok=True)

    steps: list[dict] = []

    # Step 1: contents (NCCH .app files) — optional if romfs bin already exists
    apps = list(contents.glob("00_*.app"))
    if not apps and not romfs_bin.is_file():
        print("ctrtool -p --contents ...", flush=True)
        code = run_logged(
            [ctrtool, "-p", f"--contents={contents}", str(three_ds)],
            cache / "contents_extract.log",
        )
        apps = list(contents.glob("00_*.app"))
        steps.append({"step": "contents", "exit": code, "apps": len(apps)})
        if code != 0 and not apps:
            return {
                "ok": False,
                "kind": "romfs_contents_failed",
                "message": (
                    "ctrtool --contents failed. Decrypted dumps may need -p; "
                    f"see {cache / 'contents_extract.log'}"
                ),
                "steps": steps,
                "needs_ctrtool": True,
            }

    # Step 2: raw RomFS blob from NCSD partition 0
    if not romfs_bin.is_file() or romfs_bin.stat().st_size < 1024:
        print("ctrtool -p --ncch=0 --romfs=partition0.romfs ...", flush=True)
        code = run_logged(
            [
                ctrtool,
                "-p",
                "--ncch=0",
                f"--romfs={romfs_bin}",
                str(three_ds),
            ],
            cache / "romfs_bin_extract.log",
        )
        steps.append(
            {
                "step": "romfs_bin",
                "exit": code,
                "size": romfs_bin.stat().st_size if romfs_bin.is_file() else 0,
            }
        )
        if not romfs_bin.is_file() or romfs_bin.stat().st_size < 1024:
            # Fallback: extract from .app
            if apps:
                print(f"fallback: --romfs from {apps[0].name}", flush=True)
                code = run_logged(
                    [ctrtool, "-p", f"--romfs={romfs_bin}", str(apps[0])],
                    cache / "romfs_bin_from_app.log",
                )
                steps.append({"step": "romfs_bin_from_app", "exit": code})
        if not romfs_bin.is_file() or romfs_bin.stat().st_size < 1024:
            return {
                "ok": False,
                "kind": "romfs_bin_failed",
                "message": "could not extract partition0.romfs",
                "steps": steps,
                "needs_ctrtool": True,
            }
    else:
        steps.append(
            {
                "step": "romfs_bin",
                "exit": 0,
                "size": romfs_bin.stat().st_size,
                "skipped": True,
            }
        )

    # Step 3: unpack directory tree (LARGE — many files)
    marker = romfs_dir / ".oras_romfs_ok"
    if not marker.is_file():
        t0 = time.time()
        code = 1
        used = None
        if tool_3dstool:
            print(
                f"3dstool -xvtf romfs {romfs_bin.name} --romfs-dir={romfs_dir} ...",
                flush=True,
            )
            code = run_logged(
                [
                    tool_3dstool,
                    "-xvtf",
                    "romfs",
                    str(romfs_bin),
                    "--romfs-dir",
                    str(romfs_dir),
                ],
                cache / "romfsdir_3dstool.log",
            )
            used = "3dstool"
        if code != 0:
            print(
                f"ctrtool --romfsdir={romfs_dir} {romfs_bin.name} (fallback)...",
                flush=True,
            )
            code = run_logged(
                [ctrtool, f"--romfsdir={romfs_dir}", str(romfs_bin)],
                cache / "romfsdir_extract.log",
            )
            used = "ctrtool"
        elapsed = round(time.time() - t0, 1)
        steps.append(
            {
                "step": "romfsdir",
                "exit": code,
                "elapsed_s": elapsed,
                "tool": used,
            }
        )
        # Accept partial ctrtool trees only if a/ exists with files; prefer success code
        a_files = list((romfs_dir / "a").rglob("*")) if (romfs_dir / "a").is_dir() else []
        a_files = [p for p in a_files if p.is_file()]
        if code != 0 and len(a_files) < 50:
            return {
                "ok": False,
                "kind": "romfsdir_failed",
                "message": (
                    f"RomFS dir unpack failed (exit={code}, tool={used}); "
                    f"see cache logs"
                ),
                "steps": steps,
                "romfs_bin": str(romfs_bin),
                "romfs_dir": str(romfs_dir),
                "needs_ctrtool": False,
            }
        marker.write_text(
            time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            + f" via {used}\n",
            encoding="utf-8",
        )
    else:
        steps.append({"step": "romfsdir", "exit": 0, "skipped": True})

    textures, models = index_tree(romfs_dir)
    # ORAS keeps most assets in extensionless GARC (CRAG) under a/
    garc_count = 0
    a_root = romfs_dir / "a"
    if a_root.is_dir():
        for p in a_root.rglob("*"):
            if not p.is_file():
                continue
            try:
                with p.open("rb") as fh:
                    mag = fh.read(4)
                if mag == b"CRAG":
                    garc_count += 1
            except OSError:
                pass
    msg = (
        f"RomFS unpacked: {len(textures)} image(s), {len(models)} model-ish, "
        f"{garc_count} GARC(CRAG) under a/"
    )
    if garc_count and not textures:
        msg += (
            ". No raw PNGs yet — next: unpack GARC then BCH/texture rip into cache."
        )
    return {
        "ok": True,
        "kind": "romfs_extracted",
        "message": msg,
        "texture_count": len(textures),
        "model_count": len(models),
        "archive_count": garc_count,
        "needs_garc": garc_count > 0 and len(textures) == 0,
        "texture_index": textures[:500],
        "model_sample": models[:100],
        "needs_ctrtool": False,
        "extracted_3ds": str(three_ds),
        "romfs_bin": str(romfs_bin),
        "romfs_dir": str(romfs_dir),
        "steps": steps,
        "entry_count": len(textures) + len(models) + garc_count,
        "next_steps": [
            "Unpack GARC (CRAG) under romfs/a/0/**",
            "Find Pokemon BCH + textures inside GARC",
            "Rip textures to PNG in user cache (never git)",
            "Re-run this script on the PNG tree to fill texture_index",
        ],
    }



def extract_garc_priority(
    cache: Path,
    romfs_dir: Path,
    *,
    only: list[str] | None = None,
) -> dict:
    """Unpack priority (or selected) CRAG archives into cache/garc_unpacked."""
    try:
        from garc_tools import unpack_garc, scan_magic_counts, rip_nested_models
    except ImportError:
        import importlib.util

        tools_path = Path(__file__).resolve().parent / "garc_tools.py"
        spec = importlib.util.spec_from_file_location("garc_tools", tools_path)
        if spec is None or spec.loader is None:
            return {
                "ok": False,
                "kind": "missing_garc_tools",
                "message": f"garc_tools.py not found at {tools_path}",
                "needs_garc": True,
            }
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        unpack_garc = mod.unpack_garc
        scan_magic_counts = mod.scan_magic_counts
        rip_nested_models = mod.rip_nested_models

    out_root = cache / "garc_unpacked"
    out_root.mkdir(parents=True, exist_ok=True)
    wanted = set(only) if only else None
    results: list[dict] = []
    t0 = time.time()
    for rel, role in GARC_PRIORITY:
        if wanted is not None and rel not in wanted and role not in wanted:
            continue
        src = romfs_dir / Path(rel)
        if not src.is_file():
            results.append(
                {"rel": rel, "role": role, "ok": False, "error": "missing"}
            )
            continue
        dest = out_root / Path(rel)
        marker = dest / ".garc_ok"
        if marker.is_file() and any(dest.iterdir()):
            scan = scan_magic_counts(dest)
            results.append(
                {
                    "rel": rel,
                    "role": role,
                    "ok": True,
                    "skipped": True,
                    "out_dir": str(dest),
                    "bch": scan.get("bch", 0),
                    "cgfx": scan.get("cgfx", 0),
                    "png": scan.get("png", 0),
                    "files": scan.get("files", 0),
                    "by_ext": scan.get("by_ext", {}),
                }
            )
            print(f"skip (exists): {rel} ({role})", flush=True)
            continue
        print(f"unpacking GARC {rel} ({role}) -> {dest} ...", flush=True)
        try:
            stats = unpack_garc(src, dest, decompress=True)
            marker.write_text(
                time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + "\n",
                encoding="utf-8",
            )
            scan = scan_magic_counts(dest)
            results.append(
                {
                    "rel": rel,
                    "role": role,
                    "ok": True,
                    "skipped": False,
                    "out_dir": str(dest),
                    "entry_count": stats["entry_count"],
                    "written": stats["written"],
                    "decompressed": stats["decompressed"],
                    "bch": scan.get("bch", 0),
                    "cgfx": scan.get("cgfx", 0),
                    "png": scan.get("png", 0),
                    "files": scan.get("files", 0),
                    "by_ext": scan.get("by_ext", {}),
                    "errors": stats.get("errors", [])[:10],
                }
            )
            print(
                f"  -> {stats['written']} files, "
                f"BCH={scan.get('bch', 0)} CGFX={scan.get('cgfx', 0)} "
                f"PNG={scan.get('png', 0)}",
                flush=True,
            )
        except Exception as exc:  # noqa: BLE001
            results.append(
                {"rel": rel, "role": role, "ok": False, "error": str(exc)}
            )
            print(f"  FAILED {rel}: {exc}", flush=True)

    # Second pass: unwrap MM/PC/PT/... containers -> sibling .bch
    print("ripping nested BCH/CGFX from containers ...", flush=True)
    nest = rip_nested_models(out_root)
    print(f"  nested: {nest}", flush=True)
    scan_all = scan_magic_counts(out_root)

    totals = {"bch": 0, "cgfx": 0, "png": 0, "files": 0, "garc_ok": 0}
    for r in results:
        if r.get("ok"):
            totals["garc_ok"] += 1
    totals["bch"] = int(scan_all.get("bch") or 0)
    totals["cgfx"] = int(scan_all.get("cgfx") or 0)
    totals["png"] = int(scan_all.get("png") or 0)
    totals["files"] = int(scan_all.get("files") or 0)

    return {
        "ok": totals["garc_ok"] > 0,
        "kind": "garc_unpacked",
        "message": (
            f"unpacked {totals['garc_ok']}/{len(results)} priority GARC(s); "
            f"BCH={totals['bch']} CGFX={totals['cgfx']} PNG={totals['png']} "
            f"files={totals['files']} under cache/garc_unpacked"
        ),
        "garc_unpacked_dir": str(out_root),
        "garc_tool": "garc_tools.py (pure Python CRAG + LZ11)",
        "garc_results": results,
        "bch_count": totals["bch"],
        "cgfx_count": totals["cgfx"],
        "png_count": totals["png"],
        "unpacked_file_count": totals["files"],
        "nested_rip": nest,
        "by_ext": scan_all.get("by_ext", {}),
        "elapsed_s": round(time.time() - t0, 1),
        "needs_garc": totals["garc_ok"] == 0,
        "needs_bch_rip": totals["bch"] > 0 and totals["png"] == 0,
        "next_steps": [
            "Rip BCH/CGFX textures to PNG in cache (Ohana3DS / Spica / custom)",
            "Never copy Nintendo PNG/BCH into mods/oras_models/assets or git",
            "Re-run probe on cache/garc_unpacked PNG tree to fill texture_index",
        ],
    }


def _load_bch_tex():
    try:
        from bch_tex import (
            rip_bch_textures,
            parse_bclim,
            is_bclim,
            export_textures,
            RippedTexture,
        )
        return rip_bch_textures, parse_bclim, is_bclim, export_textures, RippedTexture
    except ImportError:
        import importlib.util

        tools_path = Path(__file__).resolve().parent / "bch_tex.py"
        spec = importlib.util.spec_from_file_location("bch_tex", tools_path)
        if spec is None or spec.loader is None:
            raise ImportError(f"bch_tex.py not found at {tools_path}")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return (
            mod.rip_bch_textures,
            mod.parse_bclim,
            mod.is_bclim,
            mod.export_textures,
            mod.RippedTexture,
        )


def extract_textures(
    cache: Path,
    *,
    roots: list[str] | None = None,
    limit: int | None = None,
    smoke: bool = False,
) -> dict:
    """Rip BCH + BCLIM textures to cache/textures/ (never assets/)."""
    rip_bch_textures, parse_bclim, is_bclim, _export_textures, _RT = _load_bch_tex()

    unpacked = cache / "garc_unpacked"
    out_root = cache / "textures"
    out_root.mkdir(parents=True, exist_ok=True)

    default_roots = ["a/0/0/8", "a/0/1/4", "a/1/6/0", "a/0/9/1"]
    if smoke:
        sel = []
        poke = unpacked / "a" / "0" / "0" / "8"
        for name in ("0005.bch", "0006.bch", "0003.bch"):
            p = poke / name
            if p.is_file():
                sel.append(p)
        mug = unpacked / "a" / "1" / "6" / "0"
        for name in ("006.bin", "007.bin", "013.bin"):
            p = mug / name
            if p.is_file():
                sel.append(p)
        mapd = unpacked / "a" / "0" / "1" / "4"
        for p in sorted(mapd.glob("*.bch"))[:3]:
            sel.append(p)
        file_list = sel
        root_label = "smoke"
    else:
        use = roots or default_roots
        file_list = []
        for rel in use:
            base = unpacked / Path(rel)
            if not base.exists():
                continue
            for p in base.rglob("*"):
                if not p.is_file() or p.name.startswith("."):
                    continue
                ext = p.suffix.lower()
                if ext == ".bch":
                    file_list.append(p)
                elif ext in {".bin", ".bclim"}:
                    if p.stat().st_size >= 0x40 and is_bclim(p):
                        file_list.append(p)
        root_label = ",".join(use)

    if limit is not None:
        file_list = file_list[:limit]

    t0 = time.time()
    png_written = 0
    bch_ok = bch_fail = bclim_ok = bclim_fail = 0
    texture_index: list[dict] = []
    errors: list[str] = []
    fmt_counts: dict[str, int] = {}

    for src in file_list:
        try:
            rel = src.relative_to(unpacked).as_posix()
        except ValueError:
            rel = src.name
        stem = Path(rel).stem
        dest_dir = out_root / Path(rel).parent / stem
        try:
            head = src.read_bytes()[:4]
            if src.suffix.lower() == ".bch" or head[:3] == b"BCH":
                texs = rip_bch_textures(src)
                if not texs:
                    bch_fail += 1
                    continue
                dest_dir.mkdir(parents=True, exist_ok=True)
                for tex in texs:
                    safe = "".join(
                        c if c.isalnum() or c in "-_" else "_" for c in tex.name
                    )
                    dest = dest_dir / f"{safe}.png"
                    n = 1
                    while dest.exists():
                        dest = dest_dir / f"{safe}_{n}.png"
                        n += 1
                    tex.image.save(dest, "PNG")
                    png_written += 1
                    fmt_counts[tex.fmt_name] = fmt_counts.get(tex.fmt_name, 0) + 1
                    rid = (
                        "ORAS_TEX_"
                        + rel.replace("/", "_").replace(".", "_").upper()
                        + "_"
                        + safe.upper()
                    )
                    texture_index.append(
                        {
                            "id": rid,
                            "path": str(dest),
                            "rel": str(dest.relative_to(out_root)).replace("\\", "/"),
                            "name": tex.name,
                            "width": tex.width,
                            "height": tex.height,
                            "format": tex.fmt_name,
                            "source": rel,
                        }
                    )
                bch_ok += 1
            else:
                tex = parse_bclim(src)
                if tex is None:
                    bclim_fail += 1
                    continue
                dest_dir = out_root / Path(rel).parent
                dest_dir.mkdir(parents=True, exist_ok=True)
                dest = dest_dir / f"{stem}.png"
                tex.image.save(dest, "PNG")
                png_written += 1
                fmt_counts[tex.fmt_name] = fmt_counts.get(tex.fmt_name, 0) + 1
                bclim_ok += 1
                rid = "ORAS_TEX_" + rel.replace("/", "_").replace(".", "_").upper()
                texture_index.append(
                    {
                        "id": rid,
                        "path": str(dest),
                        "rel": str(dest.relative_to(out_root)).replace("\\", "/"),
                        "name": tex.name,
                        "width": tex.width,
                        "height": tex.height,
                        "format": tex.fmt_name,
                        "source": rel,
                    }
                )
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{rel}: {exc}")
            if src.suffix.lower() == ".bch":
                bch_fail += 1
            else:
                bclim_fail += 1

    index_path = out_root / "texture_index.json"
    write_json(
        index_path,
        {
            "png_count": png_written,
            "bch_ok": bch_ok,
            "bclim_ok": bclim_ok,
            "roots": root_label,
            "textures": texture_index,
        },
    )

    return {
        "ok": png_written > 0,
        "kind": "textures_extracted",
        "message": (
            f"ripped {png_written} PNG(s) from {bch_ok} BCH + {bclim_ok} BCLIM "
            f"(fail bch={bch_fail} bclim={bclim_fail}) -> cache/textures/"
        ),
        "textures_dir": str(out_root),
        "texture_count": png_written,
        "texture_index": texture_index[:500],
        "texture_index_path": str(index_path),
        "texture_index_total": len(texture_index),
        "bch_ok": bch_ok,
        "bch_fail": bch_fail,
        "bclim_ok": bclim_ok,
        "bclim_fail": bclim_fail,
        "format_counts": fmt_counts,
        "texture_roots": root_label,
        "files_scanned": len(file_list),
        "elapsed_s": round(time.time() - t0, 1),
        "errors": errors[:20],
        "needs_bch_rip": png_written == 0,
        "assets_vendored_count": 0,
        "next_steps": [
            "Point oras_models apply.lua at cache/textures (never vendor into assets/)",
            "Optional: mesh/geometry export from BCH (not done yet — textures only)",
            "Batch remaining GARC roles if needed (trainers a/0/2/1, maps a/0/3/9)",
        ],
    }




def _load_bch_mesh():
    try:
        from bch_mesh import (
            rip_bch_meshes,
            model_to_dict,
            build_texture_name_index,
        )
        return rip_bch_meshes, model_to_dict, build_texture_name_index
    except ImportError:
        import importlib.util
        tools_path = Path(__file__).resolve().parent / "bch_mesh.py"
        spec = importlib.util.spec_from_file_location("bch_mesh", tools_path)
        if spec is None or spec.loader is None:
            raise ImportError(f"bch_mesh.py not found at {tools_path}")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.rip_bch_meshes, mod.model_to_dict, mod.build_texture_name_index


def extract_meshes(
    cache: Path,
    *,
    smoke: bool = False,
    limit: int | None = None,
    nationals: list[int] | None = None,
    keep_skin: bool = False,
) -> dict:
    """Rip BCH Pokemon battler meshes to cache/meshes/ (JSON only, never assets/)."""
    rip_bch_meshes, model_to_dict, build_texture_name_index = _load_bch_mesh()

    unpacked = cache / "garc_unpacked" / "a" / "0" / "0" / "8"
    out_root = cache / "meshes"
    out_root.mkdir(parents=True, exist_ok=True)

    tex_index_path = cache / "textures" / "texture_index.json"
    tex_paths: dict[str, str] = {}
    tex_index_rows: list[dict] = []
    if tex_index_path.is_file():
        try:
            obj = json.loads(tex_index_path.read_text(encoding="utf-8"))
            tex_index_rows = list(obj.get("textures") or [])
            tex_paths = build_texture_name_index(tex_index_rows)
        except Exception:  # noqa: BLE001
            tex_paths = {}
            tex_index_rows = []

    # Prefer form-00 model BCHs (models>0). Smoke: Torchic/Wurmple/Groudon.
    smoke_nats = {255, 265, 383}
    wanted = set(nationals) if nationals else (smoke_nats if smoke else None)

    bch_files = sorted(unpacked.glob("*.bch"))
    t0 = time.time()
    models_ok = 0
    models_fail = 0
    mesh_index: list[dict] = []
    by_national: dict[str, dict] = {}
    errors: list[str] = []

    for src in bch_files:
        if limit is not None and models_ok >= limit:
            break
        try:
            model = rip_bch_meshes(src)
        except Exception as exc:  # noqa: BLE001
            models_fail += 1
            if len(errors) < 20:
                errors.append(f"{src.name}: {exc}")
            continue
        if model is None or not model.meshes:
            continue
        if wanted is not None and model.national not in wanted:
            continue
        # Prefer form 00; keep others under form-suffixed keys
        if model.form != 0 and wanted is None and not smoke:
            # still extract all forms for full batch
            pass

        # Drop OpenMouth duplicate for phase-1 static pose
        keep = [m for m in model.meshes if "OpenMouth" not in (m.name or "")]
        if keep:
            model.meshes = keep

        rel = f"a/0/0/8/{src.name}"
        dest_dir = out_root / "a" / "0" / "0" / "8" / src.stem
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / "mesh.json"
        payload = model_to_dict(
            model,
            tex_paths,
            texture_index=tex_index_rows,
            model_stem=src.stem,
            keep_skin=keep_skin,
        )
        payload["source_rel"] = rel
        write_json(dest, payload)

        entry = {
            "national": model.national,
            "form": model.form,
            "name": model.name,
            "path": str(dest),
            "rel": str(dest.relative_to(out_root)).replace("\\", "/"),
            "source": rel,
            "mesh_count": len(model.meshes),
            "bounds_min": model.bounds_min,
            "bounds_max": model.bounds_max,
        }
        mesh_index.append(entry)
        key = str(model.national)
        # Prefer form 00 as canonical battle mesh
        prev = by_national.get(key)
        if prev is None or (model.form == 0 and prev.get("form", 99) != 0):
            by_national[key] = {
                "front": str(dest),
                "back": str(dest),
                "form": model.form,
                "name": model.name,
                "mesh_rel": entry["rel"],
                "source_class": ("oras_mesh_phase2_skinned" if keep_skin else "oras_mesh_phase1"),
            }
        models_ok += 1

    phase_label = "2_skinned_bind" if keep_skin else "1_static_posed"
    index_path = out_root / "mesh_index.json"
    write_json(
        index_path,
        {
            "phase": phase_label,
            "keep_skin": bool(keep_skin),
            "model_count": models_ok,
            "mesh_entries": len(mesh_index),
            "by_national": by_national,
            "models": mesh_index,
        },
    )

    return {
        "ok": models_ok > 0,
        "kind": "meshes_extracted",
        "message": (
            f"ripped {models_ok} Pokemon mesh model(s) "
            f"(fail/skip parse={models_fail}) -> cache/meshes/"
        ),
        "meshes_dir": str(out_root),
        "mesh_index_path": str(index_path),
        "model_count": models_ok,
        "national_count": len(by_national),
        "elapsed_s": round(time.time() - t0, 1),
        "errors": errors[:20],
        "phase": phase_label,
        "keep_skin": bool(keep_skin),
        "next_steps": [
            "Point oras_models Lua mesh loader at cache/meshes",
            "Hook Game3:drawBattlePic to draw Mesh+Body texture when present",
            "Phase-2: skeletal animation / shinies / camera polish",
        ],
    }


def publish_mod_mesh_sidecars(mod_root: Path, index_path: Path | None) -> None:
    local = mod_root / ".local"
    local.mkdir(parents=True, exist_ok=True)
    if index_path and Path(index_path).is_file():
        dest = local / "mesh_index.json"
        dest.write_bytes(Path(index_path).read_bytes())



def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        default=os.environ.get("ORAS_SOURCE", DEFAULT_SOURCE),
        help="path to ORAS decrypted zip / .3ds / RomFS folder",
    )
    parser.add_argument(
        "--cache",
        default=None,
        help="extract cache dir (default: %%APPDATA%%/LOVE/pokemon-love2d/oras_extract)",
    )
    parser.add_argument(
        "--mod-root",
        default=str(Path(__file__).resolve().parents[1]),
        help="mods/oras_models root (for .local/status.json)",
    )
    parser.add_argument(
        "--extract-3ds",
        action="store_true",
        help="if source zip wraps a .3ds, extract the full .3ds into cache (large)",
    )
    parser.add_argument(
        "--extract-romfs",
        action="store_true",
        help="extract NCCH0 RomFS via ctrtool into cache/romfs (large)",
    )
    parser.add_argument(
        "--extract-garc",
        action="store_true",
        help="unpack priority CRAG/GARC archives into cache/garc_unpacked",
    )
    parser.add_argument(
        "--garc",
        action="append",
        default=None,
        help="limit --extract-garc to rel path or role (repeatable), e.g. a/0/0/8",
    )
    parser.add_argument(
        "--extract-textures",
        action="store_true",
        help="rip BCH/BCLIM textures to cache/textures/ (PNG only, never assets/)",
    )
    parser.add_argument(
        "--texture-root",
        action="append",
        default=None,
        help="limit texture rip to rel under garc_unpacked (repeatable)",
    )
    parser.add_argument(
        "--texture-limit",
        type=int,
        default=None,
        help="max source files to process (smoke / partial batch)",
    )
    parser.add_argument(
        "--texture-smoke",
        action="store_true",
        help="tiny fixed subset (few BCH + mugshot BCLIM) for validation",
    )
    parser.add_argument(
        "--extract-meshes",
        action="store_true",
        help="rip Pokemon BCH meshes to cache/meshes/ (JSON, never assets/)",
    )
    parser.add_argument(
        "--mesh-smoke",
        action="store_true",
        help="only Torchic/Wurmple/Groudon meshes for validation",
    )
    parser.add_argument(
        "--mesh-limit",
        type=int,
        default=None,
        help="max mesh models to write",
    )
    parser.add_argument(
        "--keep-skin",
        action="store_true",
        help="export local_vertices/bone weights/bones (phase-2 skinned bind)",
    )
    parser.add_argument(
        "--extract-effects",
        action="store_true",
        help="rip ORAS move-effect CGFX TXOBs to cache/effects/ + move_fx_index.json",
    )
    parser.add_argument(
        "--effects-smoke",
        action="store_true",
        help="only Ember + Fire Blast for --extract-effects",
    )
    parser.add_argument(
        "--effects-full-oras",
        action="store_true",
        help="extract effects through ORAS move 621 (not just Gen3 354)",
    )
    args = parser.parse_args(argv)

    source = Path(args.source)
    cache = Path(args.cache) if args.cache else appdata_cache()
    mod_root = Path(args.mod_root)
    seven = find_7z()
    cache.mkdir(parents=True, exist_ok=True)
    ctrtool = find_tool("ctrtool", cache)

    if getattr(args, "extract_effects", False) or getattr(args, "effects_smoke", False) or getattr(args, "effects_full_oras", False):
        try:
            from extract_oras_effects import extract_effects as _extract_effects
        except ImportError:
            import importlib.util
            ep = Path(__file__).resolve().parent / "extract_oras_effects.py"
            spec = importlib.util.spec_from_file_location("extract_oras_effects", ep)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            _extract_effects = mod.extract_effects
        max_move = 621 if getattr(args, "effects_full_oras", False) else 354
        fx = _extract_effects(cache, max_move=max_move, smoke=bool(getattr(args, "effects_smoke", False)))
        write_status(cache, mod_root, fx)
        print(json.dumps({"ok": fx.get("ok"), "mapped": fx.get("gen3_mapped_ew_ea"),
                          "ember": fx.get("verify", {}).get("ember_52"),
                          "fire_blast": fx.get("verify", {}).get("fire_blast_126")}, indent=2))
        return 0 if fx.get("ok") else 1

    tool_3ds = find_tool("3dstool", cache)

    payload: dict

    if not source.exists() and not find_3ds_in_cache(cache):
        payload = {
            "ok": False,
            "kind": "missing_source",
            "message": f"source not found: {source}",
            "source": str(source),
            "cache_dir": str(cache),
            "needs_ctrtool": True,
        }
    elif source.is_dir():
        payload = probe_dir(source)
        payload["source"] = str(source)
        payload["cache_dir"] = str(cache)
    elif source.suffix.lower() == ".zip":
        payload = probe_zip(source, cache, seven)
        payload["source"] = str(source)
        payload["cache_dir"] = str(cache)
        if args.extract_3ds and payload.get("kind") == "zip_ncsd_container":
            if not seven:
                payload["message"] = "need 7-Zip for Deflate64 --extract-3ds"
            else:
                inner = payload.get("container", {}).get("inner_name")
                existing = find_3ds_in_cache(cache)
                if existing and existing.stat().st_size >= (
                    payload.get("container", {}).get("file_size") or 0
                ):
                    dest = existing
                    print(f"reusing existing .3ds: {dest}", flush=True)
                elif inner:
                    write_status(
                        cache,
                        mod_root,
                        {
                            **payload,
                            "ok": False,
                            "kind": "extracting_3ds",
                            "message": "7-Zip extracting .3ds ...",
                        },
                    )
                    dest = extract_3ds_from_zip(source, cache, seven, inner)
                else:
                    dest = None
                if dest and dest.is_file():
                    payload["extracted_3ds"] = str(dest)
                    payload["ncsd"] = probe_ncsd_header(dest.read_bytes()[:512])
                    payload["kind"] = "extracted_3ds"
                    payload["message"] = (
                        f".3ds extracted to {dest}; next: --extract-romfs"
                    )
    else:
        payload = probe_file(source)
        payload["source"] = str(source)
        payload["cache_dir"] = str(cache)
        if source.suffix.lower() in {".3ds", ".cci"}:
            payload["extracted_3ds"] = str(source)

    # RomFS stage
    if args.extract_romfs:
        three = None
        if payload.get("extracted_3ds"):
            three = Path(payload["extracted_3ds"])
        if three is None or not three.is_file():
            three = find_3ds_in_cache(cache)
        if three is None and source.suffix.lower() in {".3ds", ".cci"}:
            three = source
        if not ctrtool:
            payload.update(
                {
                    "ok": False,
                    "kind": "missing_ctrtool",
                    "message": (
                        "ctrtool not on PATH and not under cache/tools/. "
                        "Download https://github.com/3DSGuy/Project_CTR/releases "
                        f"win_x64 zip into {cache / 'tools'}"
                    ),
                    "needs_ctrtool": True,
                    "tools_dir": str(cache / "tools"),
                }
            )
        elif three is None or not three.is_file():
            payload.update(
                {
                    "ok": False,
                    "kind": "missing_3ds",
                    "message": "no .3ds in cache — run --extract-3ds first",
                    "needs_ctrtool": False,
                }
            )
        else:
            write_status(
                cache,
                mod_root,
                {
                    "ok": False,
                    "kind": "extracting_romfsdir",
                    "message": "ctrtool unpacking RomFS ...",
                    "source": str(source),
                    "cache_dir": str(cache),
                    "extracted_3ds": str(three),
                    "ctrtool": ctrtool,
                    "needs_ctrtool": False,
                },
            )
            romfs_payload = extract_romfs(cache, three, ctrtool, tool_3ds)
            payload.update(romfs_payload)
            payload["source"] = str(source)
            payload["cache_dir"] = str(cache)
            payload["ctrtool"] = ctrtool
            payload["tool_3dstool"] = tool_3ds

    # GARC stage (priority subset -> cache/garc_unpacked)
    if args.extract_garc:
        romfs_dir = None
        if payload.get("romfs_dir"):
            romfs_dir = Path(payload["romfs_dir"])
        elif (cache / "romfs" / "a").is_dir():
            romfs_dir = cache / "romfs"
        elif source.is_dir() and (source / "a").is_dir():
            romfs_dir = source
        if romfs_dir is None or not romfs_dir.is_dir():
            payload.update(
                {
                    "ok": False,
                    "kind": "missing_romfs_for_garc",
                    "message": "no romfs/a tree — run --extract-romfs first",
                    "needs_garc": True,
                }
            )
        else:
            write_status(
                cache,
                mod_root,
                {
                    "ok": False,
                    "kind": "extracting_garc",
                    "message": "unpacking priority GARC (CRAG) archives ...",
                    "source": str(source),
                    "cache_dir": str(cache),
                    "romfs_dir": str(romfs_dir),
                    "needs_garc": True,
                },
            )
            garc_payload = extract_garc_priority(
                cache, romfs_dir, only=args.garc
            )
            payload.update(garc_payload)
            payload["romfs_dir"] = str(romfs_dir)
            payload["archive_count"] = payload.get("archive_count") or count_garc(
                romfs_dir
            )
            unpacked = cache / "garc_unpacked"
            if unpacked.is_dir():
                tex, models = index_tree(unpacked)
                payload["texture_count"] = len(tex)
                payload["model_count"] = len(models)
                payload["texture_index"] = tex[:500]
                payload["model_sample"] = [
                    {"rel": m["rel"], "path": m["path"]} for m in models[:100]
                ]

    # Texture rip stage (BCH + BCLIM -> cache/textures/)
    if args.extract_textures:
        unpacked = cache / "garc_unpacked"
        if not unpacked.is_dir():
            payload.update(
                {
                    "ok": False,
                    "kind": "missing_garc_for_textures",
                    "message": "no cache/garc_unpacked — run --extract-garc first",
                    "needs_bch_rip": True,
                }
            )
        else:
            write_status(
                cache,
                mod_root,
                {
                    "ok": False,
                    "kind": "extracting_textures",
                    "message": "ripping BCH/BCLIM textures to PNG ...",
                    "source": str(source),
                    "cache_dir": str(cache),
                    "needs_bch_rip": True,
                },
            )
            tex_payload = extract_textures(
                cache,
                roots=args.texture_root,
                limit=args.texture_limit,
                smoke=args.texture_smoke,
            )
            payload.update(tex_payload)
            payload["png_count"] = tex_payload.get("texture_count", 0)

    # Mesh rip stage (BCH models -> cache/meshes/)
    if args.extract_meshes:
        unpacked_models = cache / "garc_unpacked" / "a" / "0" / "0" / "8"
        if not unpacked_models.is_dir():
            payload.update(
                {
                    "ok": False,
                    "kind": "missing_garc_for_meshes",
                    "message": "no cache/garc_unpacked/a/0/0/8 — run --extract-garc first",
                }
            )
        else:
            write_status(
                cache,
                mod_root,
                {
                    "ok": False,
                    "kind": "extracting_meshes",
                    "message": "ripping BCH Pokemon meshes to JSON ...",
                    "source": str(source),
                    "cache_dir": str(cache),
                },
            )
            mesh_payload = extract_meshes(
                cache,
                smoke=args.mesh_smoke,
                limit=args.mesh_limit,
                keep_skin=args.keep_skin,
            )
            payload.update(mesh_payload)
            # model_count drives readyForModels()
            payload["model_count"] = mesh_payload.get("model_count", 0)

    payload.setdefault("seven_zip", seven)
    payload.setdefault("ctrtool", ctrtool)
    payload.setdefault("tool_3dstool", tool_3ds)
    payload.setdefault("tools_dir", str(cache / "tools"))
    payload.setdefault("cache_dir", str(cache))
    payload.setdefault("source", str(source))

    write_status(cache, mod_root, payload)

    tip = payload.get("texture_index_path")
    tex = payload.get("texture_index")
    # Prefer full index file; embed is only first 500.
    full_tex = None
    if tip and Path(str(tip)).is_file():
        try:
            full_tex = json.loads(Path(str(tip)).read_text(encoding="utf-8")).get("textures")
        except Exception:  # noqa: BLE001
            full_tex = None
    publish_mod_texture_sidecars(
        mod_root,
        Path(str(tip)) if tip else None,
        full_tex if isinstance(full_tex, list) else (tex if isinstance(tex, list) else None),
    )
    mip = payload.get("mesh_index_path")
    publish_mod_mesh_sidecars(mod_root, Path(str(mip)) if mip else None)
    # If meshes already on disk from a prior run, refresh model_count for status.
    if not mip:
        existing = cache / "meshes" / "mesh_index.json"
        if existing.is_file():
            try:
                mi = json.loads(existing.read_text(encoding="utf-8"))
                payload["model_count"] = int(mi.get("model_count") or 0)
                publish_mod_mesh_sidecars(mod_root, existing)
            except Exception:  # noqa: BLE001
                pass

    printable = {k: payload[k] for k in payload if k not in ("texture_index", "model_sample", "garc_results")}
    print(json.dumps(printable, indent=2))
    print(f"\nWrote {cache / 'status.json'}")
    print(f"Wrote {mod_root / '.local' / 'status.json'}")
    if (mod_root / ".local" / "texture_index.json").is_file():
        print(f"Wrote {mod_root / '.local' / 'texture_index.json'}")
    if (mod_root / ".local" / "battle_texture_map.json").is_file():
        print(f"Wrote {mod_root / '.local' / 'battle_texture_map.json'}")
    return 0 if payload.get("ok") else 2


if __name__ == "__main__":
    sys.exit(main())
