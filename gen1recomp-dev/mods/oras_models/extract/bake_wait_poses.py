"""Bake ORAS wait-pose display verts into mesh.json (national coverage).

Offline skin uses the same Ohana conventions as bch_mesh.py (rest err ~0).
Runtime LOVE skinner stays OFF — we replace display `vertices` with a mid-frame
waitA (else wait) pose, stash original bind as `bind_vertices`, and for
serpentine nationals also store 3 xyz frames for a cheap idle slither blend.

Writes AppData oras_extract/meshes/**/mesh.json in place. No GBA touch. No commit.

SAFETY (2026-09-14): mid-wait Rayquaza AABB exploded (Z~1525) and wait_loop
vertex-lerp produced spike soup. This baker refuses poses whose AABB span vs
bind exceeds MAX_SPAN_RATIO. Tries waitA candidate frames (mid first). Does
NOT write wait_loop_xyz (runtime ENABLE_WAIT_LOOP stays false). Failing
nationals keep bind verts for elong_tip. Use --restore-bind to reset.
"""
from __future__ import annotations

import argparse
import json
import math
import time
from pathlib import Path
from typing import Any

SLOPE_SCALE = 1.0 / 30.0

# Match OrasModels.ELONG_VERTICAL_NATS (+ a few more serpents).
SERPENT_NATS = {
    23, 24, 95, 130, 147, 148, 149, 206, 336, 349, 350, 367, 368,
    384, 445, 606, 690, 691, 693, 706, 718,
}

# Candidate waitA sample fractions (mid first). No wait_loop bake.
CANDIDATE_US = (0.5, 0.25, 0.35, 0.15, 0.0, 0.66)
# Reject wait bake if any AABB axis grows more than this vs bind.
MAX_SPAN_RATIO = 2.5


def m4id() -> list[list[float]]:
    return [[1.0, 0, 0, 0], [0, 1.0, 0, 0], [0, 0, 1.0, 0], [0, 0, 0, 1.0]]


def m4mul(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
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


def m4scale(sx: float, sy: float, sz: float) -> list[list[float]]:
    m = m4id()
    m[0][0], m[1][1], m[2][2] = sx, sy, sz
    return m


def m4rotx(a: float) -> list[list[float]]:
    c, s = math.cos(a), math.sin(a)
    m = m4id()
    m[1][1], m[2][1] = c, -s
    m[1][2], m[2][2] = s, c
    return m


def m4roty(a: float) -> list[list[float]]:
    c, s = math.cos(a), math.sin(a)
    m = m4id()
    m[0][0], m[2][0] = c, s
    m[0][2], m[2][2] = -s, c
    return m


def m4rotz(a: float) -> list[list[float]]:
    c, s = math.cos(a), math.sin(a)
    m = m4id()
    m[0][0], m[1][0] = c, -s
    m[0][1], m[1][1] = s, c
    return m


def m4trans(x: float, y: float, z: float) -> list[list[float]]:
    m = m4id()
    m[3][0], m[3][1], m[3][2] = x, y, z
    return m


def xform(m: list[list[float]], x: float, y: float, z: float) -> tuple[float, float, float]:
    return (
        x * m[0][0] + y * m[1][0] + z * m[2][0] + m[3][0],
        x * m[0][1] + y * m[1][1] + z * m[2][1] + m[3][1],
        x * m[0][2] + y * m[1][2] + z * m[2][2] + m[3][2],
    )


def inv_from_row_major(flat: list[float] | None) -> list[list[float]]:
    m = m4id()
    if not flat or len(flat) < 16:
        return m
    for r in range(4):
        for c in range(4):
            m[c][r] = float(flat[r * 4 + c])
    return m


def local_from_srt(
    sx: float, sy: float, sz: float,
    rx: float, ry: float, rz: float,
    tx: float, ty: float, tz: float,
) -> list[list[float]]:
    t = m4scale(sx, sy, sz)
    t = m4mul(t, m4rotx(rx))
    t = m4mul(t, m4roty(ry))
    t = m4mul(t, m4rotz(rz))
    t = m4mul(t, m4trans(tx, ty, tz))
    return t


def eval_channel(kfs: list[dict], frame: float) -> float:
    if not kfs:
        return 0.0
    if len(kfs) == 1:
        return float(kfs[0]["value"])
    f = frame
    if f <= float(kfs[0].get("frame", 0)):
        return float(kfs[0]["value"])
    last = kfs[-1]
    if f >= float(last.get("frame", 0)):
        return float(last["value"])
    for i in range(len(kfs) - 1):
        a, b = kfs[i], kfs[i + 1]
        fa, fb = float(a["frame"]), float(b["frame"])
        if fa <= f <= fb:
            span = fb - fa
            if span <= 1e-6:
                return float(a["value"])
            t = (f - fa) / span
            v0, v1 = float(a["value"]), float(b["value"])
            s0 = float(a.get("slope") or 0.0) * SLOPE_SCALE * span
            s1 = float(b.get("slope") or 0.0) * SLOPE_SCALE * span
            t2, t3 = t * t, t * t * t
            return (
                (2 * t3 - 3 * t2 + 1) * v0
                + (t3 - 2 * t2 + t) * s0
                + (-2 * t3 + 3 * t2) * v1
                + (t3 - t2) * s1
            )
    return float(last["value"])


def find_bone_channels(clip: dict, name: str) -> dict:
    for b in clip.get("bones") or []:
        if b.get("name") == name:
            return b.get("channels") or {}
    return {}


def sample_axis(ch: dict, axis: str, frame: float, fallback: float) -> float:
    if axis not in ch:
        return fallback
    return eval_channel(ch[axis], frame)


def build_skin(
    bones: list[dict], clip: dict | None = None, frame: float = 0.0
) -> tuple[list[list[list[float]]], list[list[list[float]]]]:
    n = len(bones)
    locals_: list[list[list[float]]] = []
    for b in bones:
        sx, sy, sz = (b.get("scale") or [1, 1, 1])[:3]
        rx, ry, rz = (b.get("rotation") or [0, 0, 0])[:3]
        tx, ty, tz = (b.get("translation") or [0, 0, 0])[:3]
        sx, sy, sz = float(sx), float(sy), float(sz)
        rx, ry, rz = float(rx), float(ry), float(rz)
        tx, ty, tz = float(tx), float(ty), float(tz)
        if clip:
            ch = find_bone_channels(clip, b["name"])
            if ch:
                sx = sample_axis(ch, "scale_x", frame, sx)
                sy = sample_axis(ch, "scale_y", frame, sy)
                sz = sample_axis(ch, "scale_z", frame, sz)
                rx = sample_axis(ch, "rotation_x", frame, rx)
                ry = sample_axis(ch, "rotation_y", frame, ry)
                rz = sample_axis(ch, "rotation_z", frame, rz)
                tx = sample_axis(ch, "translation_x", frame, tx)
                ty = sample_axis(ch, "translation_y", frame, ty)
                tz = sample_axis(ch, "translation_z", frame, tz)
        locals_.append(local_from_srt(sx, sy, sz, rx, ry, rz, tx, ty, tz))
    world: list[list[list[float]] | None] = [None] * n

    def bw(i: int) -> list[list[float]]:
        cached = world[i]
        if cached is not None:
            return cached
        t = locals_[i]
        pid = int(bones[i].get("parent_id", -1))
        if 0 <= pid < n:
            t = m4mul(t, bw(pid))
        world[i] = t
        return t

    for i in range(n):
        bw(i)
    worlds = [w for w in world if w is not None]
    skins = []
    for i, b in enumerate(bones):
        inv = inv_from_row_major(b.get("inv_transform"))
        skins.append(m4mul(worlds[i], inv))
    return skins, worlds


def skin_xyz(
    md: dict, skins: list, worlds: list
) -> list[float]:
    loc = md.get("local_vertices") or []
    bi = md.get("bone_indices") or []
    bw = md.get("bone_weights") or []
    mode = int(md.get("skinning_mode") or 1)
    vcount = len(loc) // 3
    out: list[float] = []
    for vi in range(vcount):
        lx, ly, lz = loc[vi * 3], loc[vi * 3 + 1], loc[vi * 3 + 2]
        if mode == 1:
            sx = sy = sz = wsum = 0.0
            for k in range(4):
                idx = vi * 4 + k
                bii = int(bi[idx]) if idx < len(bi) else 0
                w = float(bw[idx]) if idx < len(bw) else 0.0
                if 0 <= bii < len(skins) and w:
                    x, y, z = xform(skins[bii], lx, ly, lz)
                    sx += x * w
                    sy += y * w
                    sz += z * w
                    wsum += w
            if wsum > 1e-8:
                sx, sy, sz = sx / wsum, sy / wsum, sz / wsum
            else:
                sx, sy, sz = lx, ly, lz
        else:
            bii = int(bi[vi * 4]) if vi * 4 < len(bi) else 0
            if 0 <= bii < len(worlds):
                sx, sy, sz = xform(worlds[bii], lx, ly, lz)
            else:
                sx, sy, sz = lx, ly, lz
        out.extend((sx, sy, sz))
    return out


def xyz_to_vertices(xyz: list[float], uv_src: list[float]) -> list[float]:
    vcount = len(xyz) // 3
    out: list[float] = []
    for vi in range(vcount):
        out.append(xyz[vi * 3])
        out.append(xyz[vi * 3 + 1])
        out.append(xyz[vi * 3 + 2])
        if vi * 5 + 4 < len(uv_src):
            out.append(uv_src[vi * 5 + 3])
            out.append(uv_src[vi * 5 + 4])
        else:
            out.extend((0.0, 0.0))
    return out


def pick_wait_clip(pack: dict) -> dict | None:
    clips = pack.get("clips") or []
    # Prefer waitA (ORAS idle A often has fuller serpent motion).
    for c in clips:
        short = str(c.get("short") or "")
        name = str(c.get("name") or "")
        if c.get("role") == "wait" and ("waitA" in short or "waitA" in name):
            if not c.get("error"):
                return c
    roles = pack.get("roles") or {}
    want = roles.get("wait")
    if isinstance(want, str):
        for c in clips:
            if c.get("short") == want and not c.get("error"):
                return c
    for c in clips:
        if c.get("role") == "wait" and not c.get("error"):
            return c
    return None


def rest_max_err(mesh: dict) -> float:
    bones = mesh.get("bones") or []
    if not bones:
        return -1.0
    skins, worlds = build_skin(bones, None, 0.0)
    max_err = 0.0
    for md in mesh.get("meshes") or []:
        if not md.get("local_vertices"):
            continue
        bind = md.get("bind_vertices") or md.get("vertices") or []
        xyz = skin_xyz(md, skins, worlds)
        vcount = min(len(xyz) // 3, len(bind) // 5)
        for vi in range(vcount):
            dx = xyz[vi * 3] - bind[vi * 5]
            dy = xyz[vi * 3 + 1] - bind[vi * 5 + 1]
            dz = xyz[vi * 3 + 2] - bind[vi * 5 + 2]
            e = math.sqrt(dx * dx + dy * dy + dz * dz)
            if e > max_err:
                max_err = e
    return max_err


def update_bounds(mesh: dict) -> None:
    xs: list[float] = []
    ys: list[float] = []
    zs: list[float] = []
    for md in mesh.get("meshes") or []:
        if "OpenMouth" in str(md.get("name") or ""):
            continue
        v = md.get("vertices") or []
        for i in range(0, len(v), 5):
            xs.append(v[i])
            ys.append(v[i + 1])
            zs.append(v[i + 2])
    if not xs:
        return
    mesh["bounds_min"] = [min(xs), min(ys), min(zs)]
    mesh["bounds_max"] = [max(xs), max(ys), max(zs)]


def bake_one(
    mesh_path: Path,
    clip_pack: dict | None,
    national: int,
    *,
    force: bool = False,
) -> dict[str, Any]:
    mesh = json.loads(mesh_path.read_text(encoding="utf-8"))
    bones = mesh.get("bones") or []
    if not bones:
        return {"national": national, "ok": False, "why": "no_bones"}
    has_skin = any(
        m.get("local_vertices") and m.get("bone_indices")
        for m in (mesh.get("meshes") or [])
    )
    if not has_skin:
        return {"national": national, "ok": False, "why": "no_skin"}

    if mesh.get("wait_pose") and not force:
        return {"national": national, "ok": True, "why": "already", "skipped": True}

    # Validate rest skin once (cheap safety).
    err = rest_max_err(mesh)
    if err < 0 or err > 0.5:  # relative-tiny; units are model-space
        return {"national": national, "ok": False, "why": f"rest_err:{err}"}

    if not clip_pack:
        return {"national": national, "ok": False, "why": "no_clips"}
    clip = pick_wait_clip(clip_pack)
    if not clip:
        return {"national": national, "ok": False, "why": "no_wait_clip"}

    frames = max(1, int(clip.get("frames") or 1))
    serpent = national in SERPENT_NATS

    bind_xs: list[float] = []
    bind_ys: list[float] = []
    bind_zs: list[float] = []
    for md in mesh.get("meshes") or []:
        if "OpenMouth" in str(md.get("name") or ""):
            continue
        bind = md.get("bind_vertices") or md.get("vertices") or []
        for i in range(0, len(bind), 5):
            if i + 2 < len(bind):
                bind_xs.append(bind[i]); bind_ys.append(bind[i + 1]); bind_zs.append(bind[i + 2])
    if not bind_xs:
        return {"national": national, "ok": False, "why": "empty_bind"}
    bind_spans = [
        max(bind_xs) - min(bind_xs),
        max(bind_ys) - min(bind_ys),
        max(bind_zs) - min(bind_zs),
    ]

    def probe_u(u: float):
        skins, worlds = build_skin(bones, clip, u * frames)
        probe_xs: list[float] = []
        probe_ys: list[float] = []
        probe_zs: list[float] = []
        for md in mesh.get("meshes") or []:
            if "OpenMouth" in str(md.get("name") or ""):
                continue
            if not md.get("local_vertices") or not md.get("bone_indices"):
                continue
            xyz = skin_xyz(md, skins, worlds)
            for i in range(0, len(xyz), 3):
                probe_xs.append(xyz[i]); probe_ys.append(xyz[i + 1]); probe_zs.append(xyz[i + 2])
        if not probe_xs:
            return None
        posed_spans = [
            max(probe_xs) - min(probe_xs),
            max(probe_ys) - min(probe_ys),
            max(probe_zs) - min(probe_zs),
        ]
        ratios = [posed_spans[i] / max(bind_spans[i], 1e-3) for i in range(3)]
        return skins, worlds, posed_spans, ratios

    chosen = None
    tried = []
    for u in CANDIDATE_US:
        pr = probe_u(u)
        if not pr:
            tried.append({"u": u, "why": "empty_probe"})
            continue
        skins_mid, worlds_mid, posed_spans, ratios = pr
        tried.append({"u": u, "ratios": ratios, "posed_spans": posed_spans})
        if max(ratios) <= MAX_SPAN_RATIO:
            chosen = (u, skins_mid, worlds_mid, posed_spans, ratios)
            break

    if not chosen:
        return {
            "national": national,
            "ok": False,
            "why": "aabb_explode:all_candidates",
            "bind_spans": bind_spans,
            "tried": tried,
            "clip": clip.get("short") or clip.get("name"),
        }

    mid_u, skins_mid, worlds_mid, posed_spans, ratios = chosen

    for md in mesh.get("meshes") or []:
        if not md.get("local_vertices") or not md.get("bone_indices"):
            continue
        if "bind_vertices" not in md:
            md["bind_vertices"] = list(md.get("vertices") or [])
        uv_src = md["bind_vertices"]
        xyz = skin_xyz(md, skins_mid, worlds_mid)
        md["vertices"] = xyz_to_vertices(xyz, uv_src)
        md["posed_vertices"] = md["vertices"]
        # Never bake wait_loop_xyz — vertex-lerp caused spike soup.
        md.pop("wait_loop_xyz", None)
        md.pop("wait_loop_us", None)

    update_bounds(mesh)
    bmin, bmax = mesh.get("bounds_min"), mesh.get("bounds_max")
    spans = [0.0, 0.0, 0.0]
    if bmin and bmax:
        spans = [bmax[i] - bmin[i] for i in range(3)]
    mesh["wait_pose"] = {
        "clip": clip.get("short") or clip.get("name"),
        "role": "wait",
        "u": mid_u,
        "frame": mid_u * frames,
        "frames": frames,
        "serpent_loop": False,
        "safe": True,
        "rest_err": err,
        "aabb_spans": spans,
        "aabb_ratios": ratios,
        "bind_spans": bind_spans,
        "baker": "bake_wait_poses.py",
        "max_span_ratio": MAX_SPAN_RATIO,
    }
    mesh.pop("wait_pose_unsafe", None)
    mesh["phase"] = "3_wait_posed"
    mesh_path.write_text(json.dumps(mesh, separators=(",", ":")), encoding="utf-8")
    return {
        "national": national,
        "ok": True,
        "clip": mesh["wait_pose"]["clip"],
        "serpent": serpent,
        "u": mid_u,
        "spans": spans,
        "ratios": ratios,
        "rest_err": err,
    }



def appdata_root() -> Path:
    return Path.home() / "AppData" / "Roaming" / "LOVE" / "pokemon-love2d" / "oras_extract"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", type=int, nargs="*", help="national ids")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument(
        "--restore-bind",
        action="store_true",
        help="Restore display verts from bind_vertices; clear wait_pose / wait_loop",
    )
    args = ap.parse_args()

    root = appdata_root()
    mesh_idx = json.loads((root / "meshes" / "mesh_index.json").read_text(encoding="utf-8"))
    anim_idx = json.loads((root / "anims" / "anim_by_national.json").read_text(encoding="utf-8"))
    by_mesh = mesh_idx.get("by_national") or {}
    by_anim = anim_idx.get("by_national") or {}

    nats = sorted(int(k) for k in by_mesh.keys())
    if args.only:
        nats = [n for n in args.only if str(n) in by_mesh]
    if args.limit > 0:
        nats = nats[: args.limit]

    if args.restore_bind:
        n_files = n_parts = 0
        for nat in nats:
            row = by_mesh[str(nat)]
            rel = row.get("mesh_rel") or ""
            mesh_path = root / "meshes" / rel.replace("\\", "/")
            if not mesh_path.is_file():
                continue
            mesh = json.loads(mesh_path.read_text(encoding="utf-8"))
            changed = False
            for md in mesh.get("meshes") or []:
                bind = md.get("bind_vertices")
                if isinstance(bind, list) and len(bind) >= 5:
                    md["vertices"] = list(bind)
                    md.pop("posed_vertices", None)
                    changed = True
                    n_parts += 1
                md.pop("wait_loop_xyz", None)
                md.pop("wait_loop_us", None)
            if mesh.get("wait_pose") is not None:
                mesh["wait_pose_unsafe"] = mesh.get("wait_pose")
                mesh.pop("wait_pose", None)
                changed = True
            if mesh.get("phase") == "3_wait_posed":
                mesh["phase"] = "2_skinned_bind"
                changed = True
            if changed:
                update_bounds(mesh)
                mesh_path.write_text(
                    json.dumps(mesh, separators=(",", ":")), encoding="utf-8"
                )
                n_files += 1
        mesh_idx["phase"] = "2_skinned_bind"
        mesh_idx["wait_pose_bake"] = {
            "status": "disabled_unsafe",
            "restored_from_bind": True,
            "restored_files": n_files,
            "restored_parts": n_parts,
        }
        (root / "meshes" / "mesh_index.json").write_text(
            json.dumps(mesh_idx), encoding="utf-8"
        )
        print(json.dumps({"restored_files": n_files, "restored_parts": n_parts}, indent=2))
        return

    t0 = time.time()
    ok = fail = skip = 0
    results = []
    for i, nat in enumerate(nats):
        row = by_mesh[str(nat)]
        rel = row.get("mesh_rel") or ""
        mesh_path = root / "meshes" / rel.replace("\\", "/")
        if not mesh_path.is_file():
            fail += 1
            results.append({"national": nat, "ok": False, "why": "missing_mesh"})
            continue
        anim_row = by_anim.get(str(nat))
        clip_pack = None
        if anim_row and anim_row.get("rel"):
            cp = root / "anims" / anim_row["rel"]
            if cp.is_file():
                clip_pack = json.loads(cp.read_text(encoding="utf-8"))
        r = bake_one(mesh_path, clip_pack, nat, force=args.force)
        results.append(r)
        if r.get("skipped"):
            skip += 1
        elif r.get("ok"):
            ok += 1
        else:
            fail += 1
        if (i + 1) % 50 == 0 or nat in (4, 25, 130, 384, 718):
            print(
                f"[{i+1}/{len(nats)}] nat={nat} ok={r.get('ok')} "
                f"why={r.get('why') or r.get('clip')} serpent={r.get('serpent')} "
                f"spans={r.get('spans')}",
                flush=True,
            )

    report = {
        "phase": "3_wait_posed",
        "ok": ok,
        "fail": fail,
        "skip": skip,
        "total": len(nats),
        "elapsed_s": round(time.time() - t0, 1),
        "max_span_ratio": MAX_SPAN_RATIO,
        "candidate_us": list(CANDIDATE_US),
        "wait_loop_baked": False,
        "serpent_nats": sorted(SERPENT_NATS),
        "oks": [r for r in results if r.get("ok") and not r.get("skipped")],
        "fails": [r for r in results if not r.get("ok")],
        "rayquaza": next((r for r in results if r.get("national") == 384), None),
    }
    out = root / "meshes" / "wait_pose_bake_report.json"
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    # Stamp mesh_index
    mesh_idx["phase"] = "3_wait_posed"
    mesh_idx["wait_pose_bake"] = {
        "status": "safe_selective",
        "ok": ok,
        "fail": fail,
        "skip": skip,
        "elapsed_s": report["elapsed_s"],
        "max_span_ratio": MAX_SPAN_RATIO,
        "wait_loop_baked": False,
        "report": str(out),
    }
    (root / "meshes" / "mesh_index.json").write_text(
        json.dumps(mesh_idx), encoding="utf-8"
    )
    print(json.dumps({k: report[k] for k in ("ok", "fail", "skip", "total", "elapsed_s", "rayquaza")}, indent=2))
    print("report", out)


if __name__ == "__main__":
    main()

