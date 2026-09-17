#!/usr/bin/env python3
"""Extract ORAS battle move effect CGFX textures into AppData oras_extract/effects/.

Hard rules: never vendor Nintendo art into git / mods/oras_models/assets.
Pipeline:
  1. Ensure a/0/3/1 (move effects CGFX) + a/0/3/4 (SESD) are unpacked.
  2. Index CGFX by ewNNN / eaNNN move-id tokens (ORAS naming).
  3. Rip TXOB PNGs per mapped move into effects/moves/<id>/
  4. Write effects/move_fx_index.json for DramaticShapes OrasMoveFx.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from collections import defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from garc_tools import unpack_garc, scan_magic_counts  # noqa: E402
from cgfx_tex import rip_cgfx_textures, export_cgfx_file  # noqa: E402

# Shared type-family CGFX used when a Gen3 move has no ewNNN pack.
TYPE_SHARED = {
    "FIRE": [0, 1, 8, 12, 13, 202, 208, 209, 211],
    "WATER": [57],  # filled dynamically if present; else common water packs
    "ELECTRIC": [6, 7],
    "ICE": [9, 10],
    "GRASS": [],
    "PSYCHIC": [],
    "NORMAL": [2, 3, 4, 5],
    "FIGHTING": [],
    "POISON": [],
    "GROUND": [],
    "FLYING": [],
    "BUG": [],
    "ROCK": [],
    "GHOST": [],
    "DRAGON": [],
    "DARK": [],
    "STEEL": [],
    "FAIRY": [],
}

# Gen3 move id -> type name for fallback (Ruby/Sapphire national set 1..354).
# Compact: only IDs that commonly lack ewNNN packs, plus all for safety via
# a minimal type table built from known pokeemerald move types for Gen3.
GEN3_MOVE_TYPES: dict[int, str] = {}


def appdata_cache() -> Path:
    base = os.environ.get("APPDATA") or os.environ.get("HOME") or "."
    return Path(base) / "LOVE" / "pokemon-love2d" / "oras_extract"


def ensure_garcs(cache: Path) -> dict:
    romfs = cache / "romfs"
    out_root = cache / "garc_unpacked"
    results = {}
    for rel, role in (
        ("a/0/3/1", "move_effects"),
        ("a/0/3/4", "battle_anim_sesd"),
    ):
        src = romfs / Path(rel)
        dest = out_root / Path(rel)
        marker = dest / ".garc_ok"
        if not src.is_file():
            results[rel] = {"ok": False, "error": "missing_romfs"}
            continue
        if marker.is_file() and any(dest.glob("*")):
            results[rel] = {"ok": True, "skipped": True, **scan_magic_counts(dest)}
            continue
        print(f"unpacking {rel} ({role}) ...", flush=True)
        stats = unpack_garc(src, dest, decompress=True)
        marker.write_text(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + "\n")
        results[rel] = {"ok": True, "skipped": False, **stats, **scan_magic_counts(dest)}
    return results


_EW_RE = re.compile(rb"\bew(\d{3})[_a-zA-Z0-9]*")
_EA_RE = re.compile(rb"\bea(\d{3})[_a-zA-Z0-9]*")


def index_move_cgfx(eff_dir: Path) -> dict[int, list[int]]:
    """Map move_id -> sorted unique CGFX entry indices via ewNNN/eaNNN names."""
    move_to: dict[int, set[int]] = defaultdict(set)
    for p in sorted(eff_dir.glob("*.cgfx")):
        try:
            idx = int(p.stem)
        except ValueError:
            continue
        data = p.read_bytes()
        for rx in (_EW_RE, _EA_RE):
            for m in rx.finditer(data):
                mid = int(m.group(1))
                if 1 <= mid <= 900:
                    move_to[mid].add(idx)
    return {k: sorted(v) for k, v in sorted(move_to.items())}


def pick_primary_textures(pngs: list[Path], limit: int = 6) -> list[str]:
    """Prefer font/moji (Fire Blast kanji), fire, ring, impact; skip dust when possible."""
    forced: list[Path] = []
    scored: list[tuple[int, Path]] = []
    for p in pngs:
        name = p.stem.lower()
        if any(k in name for k in ("font", "moji")):
            forced.append(p)
            continue
        score = p.stat().st_size
        if any(k in name for k in ("fire", "flame", "beam", "aura", "ring", "impact", "blast", "spark", "pattern", "patern")):
            score += 5_000_000
        if any(k in name for k in ("dust", "smoke", "leaf")):
            score -= 500_000
        scored.append((score, p))
    scored.sort(key=lambda t: -t[0])
    ordered = forced + [p for _, p in scored]
    # unique preserve order
    seen = set()
    out = []
    for p in ordered:
        if p.name in seen:
            continue
        seen.add(p.name)
        out.append(p.name)
        if len(out) >= limit:
            break
    return out


def extract_effects(
    cache: Path,
    *,
    max_move: int = 354,
    smoke: bool = False,
) -> dict:
    t0 = time.time()
    garc = ensure_garcs(cache)
    eff_dir = cache / "garc_unpacked" / "a" / "0" / "3" / "1"
    sesd_dir = cache / "garc_unpacked" / "a" / "0" / "3" / "4"
    effects_root = cache / "effects"
    moves_root = effects_root / "moves"
    effects_root.mkdir(parents=True, exist_ok=True)

    print("indexing CGFX move tokens...", flush=True)
    move_map = index_move_cgfx(eff_dir)
    print(f"  moves with ew/ea packs: {len(move_map)}", flush=True)

    # Smoke: only Ember + Fire Blast
    targets = [52, 126] if smoke else list(range(1, max_move + 1))

    # Also rip a few shared packs into effects/shared/
    shared_dir = effects_root / "shared"
    shared_dir.mkdir(exist_ok=True)
    shared_idxs = sorted({i for ids in TYPE_SHARED.values() for i in ids})
    shared_files: dict[str, list[str]] = {}
    for idx in shared_idxs:
        src = eff_dir / f"{idx:04d}.cgfx"
        if not src.is_file():
            src = eff_dir / f"{idx}.cgfx"
        if not src.is_file():
            continue
        dest = shared_dir / f"{idx:04d}"
        if not (dest / ".ok").is_file():
            r = export_cgfx_file(src, dest)
            (dest / ".ok").write_text(f"{r['textures']}\n")
        pngs = sorted(dest.glob("*.png"))
        shared_files[str(idx)] = [p.name for p in pngs]

    by_move: dict[str, dict] = {}
    tex_count = 0
    mapped = 0
    fallback = 0

    for mid in targets:
        idxs = move_map.get(mid, [])
        # Prefer idxs whose stem names mention this move id
        preferred = []
        for idx in idxs:
            src = eff_dir / f"{idx:04d}.cgfx"
            if not src.is_file():
                src = eff_dir / f"{idx}.cgfx"
            if not src.is_file():
                continue
            blob = src.read_bytes()
            token = f"ew{mid:03d}".encode()
            token2 = f"ea{mid:03d}".encode()
            if token in blob or token2 in blob:
                preferred.append(idx)
        use = preferred or idxs
        # Cap per-move CGFX count for disk/time (keep richest packs)
        if len(use) > 8:
            # Prefer larger files
            sized = []
            for idx in use:
                src = eff_dir / f"{idx:04d}.cgfx"
                if not src.is_file():
                    src = eff_dir / f"{idx}.cgfx"
                if src.is_file():
                    sized.append((src.stat().st_size, idx))
            sized.sort(reverse=True)
            use = [i for _, i in sized[:8]]

        move_dir = moves_root / f"{mid:03d}"
        png_names: list[str] = []
        labels: list[str] = []
        if use:
            move_dir.mkdir(parents=True, exist_ok=True)
            for idx in use:
                src = eff_dir / f"{idx:04d}.cgfx"
                if not src.is_file():
                    src = eff_dir / f"{idx}.cgfx"
                if not src.is_file():
                    continue
                # Skip re-rip if marker present
                marker = move_dir / f".cgfx_{idx:04d}"
                if not marker.is_file():
                    r = export_cgfx_file(src, move_dir)
                    marker.write_text(f"{r['textures']}\n")
                    # collect emitter label hints
                    for m in re.finditer(rb"ew%03d[_a-zA-Z0-9]{0,40}" % mid, src.read_bytes()):
                        labels.append(m.group().decode("ascii", "replace"))
                tex_count += 1
            pngs = sorted(move_dir.glob("*.png"))
            png_names = pick_primary_textures(pngs, limit=8)
            mapped += 1
            source = "ew_ea_pack"
        else:
            # Type / shared fallback — still real ORAS art, not Gen3 redraws.
            # Infer type from nearby mapped moves is weak; use SESD presence + shared fire/etc.
            sesd = sesd_dir / f"{mid:03d}.sesd"
            has_sesd = sesd.is_file()
            # Default shared pack: normal lines + fire beam for damage-y feel
            pack_idxs = [0, 1, 2]
            # Heuristic from SESD size (larger = flashier move)
            if has_sesd and sesd.stat().st_size > 800:
                pack_idxs = [0, 1, 202, 211]
            png_names = []
            for idx in pack_idxs:
                key = str(idx)
                for name in shared_files.get(key, [])[:2]:
                    png_names.append(f"../shared/{idx:04d}/{name}")
            if png_names:
                fallback += 1
                source = "shared_oras"
            else:
                source = "none"

        entry = {
            "move_id": mid,
            "cgfx": use,
            "textures": png_names,
            "labels": sorted(set(labels))[:12],
            "sesd": (sesd_dir / f"{mid:03d}.sesd").is_file(),
            "source": source,
        }
        by_move[str(mid)] = entry
        if mid in (52, 126) or mid % 50 == 0:
            print(
                f"  move {mid}: source={source} cgfx={use} tex={len(png_names)}",
                flush=True,
            )

    # National ORAS coverage stats (beyond Gen3)
    oras_mapped = sum(1 for m in range(1, 622) if m in move_map)

    index = {
        "ok": True,
        "kind": "oras_move_effects",
        "garc": {
            "move_effects": "a/0/3/1",
            "battle_anim_sesd": "a/0/3/4",
            "status": garc,
        },
        "cgfx_total": len(list(eff_dir.glob('*.cgfx'))),
        "moves_with_ew_ea": len(move_map),
        "oras_moves_1_621_mapped": oras_mapped,
        "gen3_targets": len(targets),
        "gen3_mapped_ew_ea": mapped,
        "gen3_shared_fallback": fallback,
        "textures_ripped_batches": tex_count,
        "effects_dir": str(effects_root),
        "by_move": by_move,
        "verify": {
            "ember_52": by_move.get("52"),
            "fire_blast_126": by_move.get("126"),
        },
        "gap": (
            "Full NW particle simulation (emitter spawn/velocity/lifetime) is not "
            "played back; DramaticShapes billboards the ripped ORAS TXOB textures "
            "that compose each move. SESD scripts are indexed but not executed."
        ),
        "elapsed_s": round(time.time() - t0, 1),
        "probed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    index_path = effects_root / "move_fx_index.json"
    index_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {index_path}", flush=True)
    return index


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cache", default=None, help="oras_extract cache dir")
    ap.add_argument("--max-move", type=int, default=354, help="Gen3 move id ceiling")
    ap.add_argument("--smoke", action="store_true", help="only Ember+Fire Blast")
    ap.add_argument("--full-oras", action="store_true", help="map/extract through move 621")
    args = ap.parse_args(argv)
    cache = Path(args.cache) if args.cache else appdata_cache()
    max_move = 621 if args.full_oras else args.max_move
    idx = extract_effects(cache, max_move=max_move, smoke=args.smoke)
    print(
        json.dumps(
            {
                "ok": idx["ok"],
                "mapped": idx["gen3_mapped_ew_ea"],
                "fallback": idx["gen3_shared_fallback"],
                "oras_mapped": idx["oras_moves_1_621_mapped"],
                "ember": idx["verify"]["ember_52"],
                "fire_blast": idx["verify"]["fire_blast_126"],
                "elapsed_s": idx["elapsed_s"],
            },
            indent=2,
        )
    )
    return 0 if idx.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
