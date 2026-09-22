#!/usr/bin/env python3
"""
Aggressive Gen1Recomp compatibility suite for Weather FX.

Runs on every revision via tools/run_all.py.
- Static analysis of our hooks, options, pipelines, host IDs
- Cross-check against tools/known_mods_registry.json
- Optional: scan extracted mod trees under /tmp, attachments, compat_check
- Fails (exit 1) on HIGH severity conflicts
"""
from __future__ import annotations

import json
import re
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
REG = HERE / "known_mods_registry.json"

HIGH = []
MED = []
INFO = []
PASS = []


def note(bucket, msg):
    bucket.append(msg)


def read(p: Path) -> str:
    try:
        return p.read_text(errors="ignore")
    except Exception:
        return ""


def all_lua_text() -> str:
    parts = []
    for p in ROOT.rglob("*.lua"):
        if "tests/" in str(p).replace("\\", "/"):
            continue
        parts.append(read(p))
    return "\n".join(parts)


def extract_option_keys(text: str) -> set[str]:
    keys = set(re.findall(r'key\s*=\s*"([A-Za-z0-9_]+)"', text))
    keys |= set(re.findall(r'\["([A-Za-z0-9_]+)"\]\s*=\s*\{[^}]*label', text))
    return keys


def extract_wraps(text: str) -> set[str]:
    return set(re.findall(r'hooks:wrap\(\s*"([^"]+)"', text))


def extract_events(text: str) -> set[str]:
    return set(re.findall(r'events:on\(\s*"([^"]+)"', text))


def extract_mod_finds(text: str) -> set[str]:
    return set(re.findall(r'mod\.find\(\s*(?:mod,\s*)?"([A-Za-z0-9_]+)"', text))


def extract_pipeline_registers(text: str) -> set[str]:
    return set(re.findall(r'render_pipelines:register\(\s*"([^"]+)"', text))


def scan_our_mod():
    main = read(ROOT / "main.lua")
    settings = read(ROOT / "lib/Settings.lua")
    battle_draw = read(ROOT / "lib/BattleDraw.lua")
    atmos = read(ROOT / "lib/DramalessAtmos.lua")
    all_txt = all_lua_text()
    man = json.loads(read(ROOT / "manifest.json") or "{}")

    our = {
        "option_keys": extract_option_keys(settings) | extract_option_keys(main),
        "wraps": extract_wraps(main) | extract_wraps(all_txt),
        "events": extract_events(main) | extract_events(all_txt),
        "mod_finds": extract_mod_finds(all_txt),
        "pipelines": extract_pipeline_registers(main) | extract_pipeline_registers(all_txt),
        "hosts_block": atmos,
        "manifest": man,
        "all": all_txt,
        "main": main,
        "settings": settings,
        "battle_draw": battle_draw,
    }
    return our


def check_forbidden(our, reg):
    all_txt = our["all"]
    # love.draw assignment
    if re.search(r"\blove\.draw\s*=", all_txt):
        note(HIGH, "FORBIDDEN: assigns love.draw (breaks other UI mods)")
    else:
        note(PASS, "No love.draw assignment")

    # save.options write
    if re.search(r"save\.options\s*=", all_txt):
        note(HIGH, "FORBIDDEN: writes save.options = (can clobber other mods)")
    else:
        note(PASS, "No save.options = writes")

    # editing other mod paths
    if re.search(r"mods/[A-Za-z0-9_]+/.*write|io\.open\(.*mods/", all_txt):
        note(HIGH, "FORBIDDEN: appears to write into other mods/")
    else:
        note(PASS, "No other-mod filesystem writes detected")


def check_required_hosts(our, reg):
    hosts_src = our["hosts_block"]
    missing = []
    for h in reg.get("our_required_hosts", []):
        if h not in hosts_src:
            missing.append(h)
    if missing:
        note(HIGH, f"Missing voxel host IDs in DramalessAtmos HOSTS: {missing}")
    else:
        note(PASS, "All required voxel host IDs present in HOSTS")


def check_crystal_standdown(our):
    bt = read(ROOT / "lib/Battle.lua")
    main = our["main"]
    if "crystal" not in bt.lower() and "CRYSTAL" not in bt:
        note(HIGH, "Crystal 251: no crystal markers in Battle.lua")
    else:
        note(PASS, "Crystal 251 markers present in Battle.lua")
    if "CRYSTAL" not in main and "crystal" not in main.lower():
        note(MED, "Crystal mention missing in main.lua (optional)")
    else:
        note(PASS, "Crystal referenced from main/bootstrap path")


def check_registry_mods(our, reg):
    our_keys = {k.lower() for k in our["option_keys"]}
    our_wraps = our["wraps"]
    all_txt = our["all"]
    readme = read(ROOT / "README.md").lower()
    battle = read(ROOT / "lib/Battle.lua")
    main = our["main"]

    for mod in reg.get("mods", []):
        mid = mod["id"]
        kind = mod.get("kind", "")

        # Option key collisions with known UI mod keys
        for ok in mod.get("option_keys") or []:
            if ok.lower() in our_keys:
                note(HIGH, f"OPTION KEY COLLISION with {mid}: '{ok}'")
            else:
                note(PASS, f"No option collision with {mid}.{ok}")

        # Weather peer mutex warning
        if kind == "weather_peer":
            if mid.lower() in readme and "one weather-authority mod at a time" in readme:
                note(PASS, f"Peer weather mod '{mid}' is explicitly documented as mutually exclusive")
            else:
                note(MED, f"Peer weather mod '{mid}': document one-weather-mod-only for users")

        # Voxel host markers
        if kind == "voxel_host":
            markers = mod.get("our_markers") or [mid]
            if not any(m in our["hosts_block"] or m in all_txt for m in markers):
                note(HIGH, f"Voxel host '{mid}' not referenced in our host bridge")
            else:
                note(PASS, f"Voxel host '{mid}' wired")

        # UI stacking risks
        risk = mod.get("risk")
        if risk:
            note(INFO, f"[{mid}] risk: {risk}")

        # Hook overlap advisory
        their_hooks = set(mod.get("hooks") or [])
        overlap = their_hooks & our_wraps
        if overlap:
            guarded = False
            reason = ""
            if mid == "CRYSTAL_251" and overlap <= {"battle.damage"}:
                guarded = ("function Battle.hostCrystal" in battle and "if Battle.hostCrystal() then return false end" in battle)
                reason = "Crystal weather damage stand-down"
            elif "battle.overlay" in overlap and mid in {"gen3_battle_ui", "colosseum_ui_overhaul"}:
                guarded = ("local function runNext()" in battle and "return next_(battle" in battle and "Priority 50" in battle)
                reason = "battle overlay chains next_ and remains below high-priority UI"
            elif overlap <= {"render.hud", "render.letterbox"} or overlap <= {"render.hud"}:
                guarded = ('mod.hooks:wrap("render.hud"' in main and 'local result = next_(game, viewport)' in main)
                if "render.letterbox" in overlap:
                    guarded = guarded and ('mod.hooks:wrap("render.letterbox"' in main and 'local result = next_(ctx)' in main)
                reason = "UI hooks preserve next_ chain before Weather FX diagnostics/art"
            if guarded:
                note(PASS, f"Shared hook with {mid}: {sorted(overlap)} guarded ({reason})")
            elif "battle.overlay" in overlap:
                note(MED, f"Shared hook with {mid}: {sorted(overlap)} — verify coexistence guards")
            else:
                note(MED, f"Hook name overlap with {mid}: {sorted(overlap)}")


def check_ui_stacking_guards(our):
    bd = our["battle_draw"]
    draw = read(ROOT / "lib/Draw.lua")
    if "kanto_companion" not in bd and "kanto_companion" not in our["all"]:
        note(MED, "No kanto_companion soft-detect (UI stacking harder to tune)")
    else:
        note(PASS, "kanto_companion soft-detect present")

    # Battle weather can be disabled
    if "battles" not in our["settings"] and "battles" not in our["all"]:
        note(MED, "Battle weather visual control not found in settings")
    else:
        note(PASS, "Single BATTLE WEATHER visual control present")

    if "battleDamage" not in our["settings"] and "battleDamage" not in our["all"]:
        note(MED, "Battle damage toggle not found")
    else:
        note(PASS, "Battle damage toggle present")


def check_mobile(our):
    q = read(ROOT / "lib/Quality.lua")
    q_code = "\n".join(line for line in q.splitlines()
                       if not line.lstrip().startswith("--"))
    # Mods cannot safely read love.system: the sandbox throws on field access.
    # Portable AUTO therefore starts HIGH everywhere and adapts from whole-frame
    # timing instead of guessing the OS. A platform probe here is a regression.
    if "love.system" in q_code or "isMobileDevice" in q_code:
        note(HIGH, "Quality probes sandboxed OS state; AUTO must be frame-time driven")
    else:
        note(PASS, "Quality avoids sandboxed OS probing")
    if ("Quality.update" in q and "auto.ema" in q and "platformDefault" in q
            and "autoPerformance" in q and "performanceTarget" in q
            and "Quality.ORDER" in q and "potato" in q and "high" in q):
        note(PASS, "Portable adaptive AUTO quality path present")
    else:
        note(MED, "Adaptive AUTO quality governor is incomplete")
    if "potato" in q:
        note(PASS, "POTATO manual quality tier present")
    else:
        note(MED, "POTATO manual quality tier missing")


def check_pipeline_isolation(our):
    pipes = our["pipelines"]
    if "weather" not in pipes and "weather" not in our["main"]:
        note(HIGH, "Weather render pipeline not registered")
    else:
        note(PASS, "Weather pipeline registered")
    if len(pipes) > 3:
        note(MED, f"Many pipelines registered: {sorted(pipes)}")


def scan_external_mod_trees():
    """Scan known locations for other mod sources to diff hooks/keys."""
    candidates = []
    for base in [
        Path("/tmp"),
        Path("/home/workdir/attachments"),
        Path("/home/workdir/artifacts/compat_check"),
        ROOT.parent / "compat_check",
    ]:
        if not base.exists():
            continue
        for p in base.rglob("manifest.json"):
            # skip our own
            if "weather_fx" in str(p):
                continue
            candidates.append(p.parent)

    # Also unzip any attached mod zips that look like mods (small)
    att = Path("/home/workdir/attachments")
    if att.exists():
        for z in att.glob("*.zip"):
            name = z.name.lower()
            if "weather_fx" in name:
                continue
            if z.stat().st_size > 80_000_000:
                note(INFO, f"Skip huge zip for extract scan: {z.name}")
                continue
            dest = Path("/tmp/compat_scan") / z.stem
            if not dest.exists():
                try:
                    dest.mkdir(parents=True, exist_ok=True)
                    with zipfile.ZipFile(z, "r") as zf:
                        zf.extractall(dest)
                except Exception as e:
                    note(INFO, f"Could not extract {z.name}: {e}")
                    continue
            for p in dest.rglob("manifest.json"):
                if "weather_fx" not in str(p):
                    candidates.append(p.parent)

    seen = set()
    external = []
    for c in candidates:
        key = str(c.resolve()) if c.exists() else str(c)
        if key in seen:
            continue
        seen.add(key)
        man_p = c / "manifest.json"
        if not man_p.exists():
            continue
        try:
            man = json.loads(read(man_p) or "{}")
        except Exception:
            continue
        mid = man.get("id") or c.name
        # gather lua
        text = ""
        for lp in list(c.rglob("*.lua"))[:40]:
            text += "\n" + read(lp)
        external.append({
            "id": mid,
            "path": str(c),
            "option_keys": extract_option_keys(text),
            "wraps": extract_wraps(text),
            "events": extract_events(text),
            "pipelines": extract_pipeline_registers(text),
            "manifest": man,
        })
    return external


def cross_check_external(our, external):
    our_keys = {k.lower() for k in our["option_keys"]}
    our_wraps = our["wraps"]
    for ext in external:
        mid = ext["id"]
        if mid in ("weather_fx",):
            continue
        shared_keys = our_keys & {k.lower() for k in ext["option_keys"]}
        # Per-mod option namespaces in Gen1Recomp: common labels like
        # lightning/debug/fog are not true collisions unless keys are global.
        GENERIC = {"debug", "lightning", "fog", "rain", "clouds", "stars", "quality", "enabled", "on", "off"}
        hard = sorted(k for k in shared_keys if k not in GENERIC)
        soft = sorted(k for k in shared_keys if k in GENERIC)
        if hard:
            note(HIGH, f"LIVE SCAN option key collision with {mid}: {hard}")
        elif soft:
            note(INFO, f"LIVE SCAN shared generic option labels with {mid}: {soft} (per-mod namespace OK)")
        elif ext["option_keys"]:
            note(PASS, f"LIVE SCAN no option collision with {mid} ({len(ext['option_keys'])} keys)")

        shared_wraps = our_wraps & ext["wraps"]
        if shared_wraps:
            # ui.options.rows alone is usually fine if we call next_
            if shared_wraps <= {"ui.options.rows"}:
                note(INFO, f"LIVE SCAN shared wrap with {mid}: {sorted(shared_wraps)} (must call next_)")
            elif "battle.overlay" in shared_wraps:
                note(MED, f"LIVE SCAN shared battle.overlay with {mid}")
            else:
                note(MED, f"LIVE SCAN shared hooks with {mid}: {sorted(shared_wraps)}")

        if "weather" in ext["pipelines"] and "weather" in our["pipelines"]:
            note(HIGH, f"LIVE SCAN duplicate 'weather' pipeline with {mid}")

        conf = (ext["manifest"] or {}).get("conflicts") or []
        if any("weather_fx" in str(c) for c in conf):
            note(MED, f"{mid} manifest lists conflict with weather_fx: {conf}")


def main() -> int:
    if not REG.exists():
        print("FAIL: known_mods_registry.json missing")
        return 1
    reg = json.loads(REG.read_text())
    our = scan_our_mod()

    print("=== AGGRESSIVE COMPATIBILITY SUITE ===")
    print(f"registry mods: {len(reg.get('mods', []))}")
    print(f"our option keys: {len(our['option_keys'])}")
    print(f"our wraps: {sorted(our['wraps'])}")
    print(f"our pipelines: {sorted(our['pipelines'])}")
    print()

    check_forbidden(our, reg)
    check_required_hosts(our, reg)
    check_crystal_standdown(our)
    check_registry_mods(our, reg)
    check_ui_stacking_guards(our)
    check_mobile(our)
    check_pipeline_isolation(our)

    print("\n--- External mod tree scan ---")
    external = scan_external_mod_trees()
    print(f"external mod trees found: {len(external)}")
    for e in external:
        print(f"  · {e['id']} @ {e['path']}")
    cross_check_external(our, external)

    print("\n=== RESULTS ===")
    print(f"PASS {len(PASS)}  MED {len(MED)}  HIGH {len(HIGH)}  INFO {len(INFO)}")
    if HIGH:
        print("\nHIGH:")
        for m in HIGH:
            print("  !", m)
    if MED:
        print("\nMED:")
        for m in MED:
            print("  ~", m)
    if INFO:
        print("\nINFO (sample):")
        for m in INFO[:12]:
            print("  ·", m)

    # Fail revision on any HIGH
    if HIGH:
        print("\nCOMPAT SUITE FAILED (HIGH findings)")
        return 1
    print("\nCOMPAT SUITE PASSED (no HIGH findings)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
