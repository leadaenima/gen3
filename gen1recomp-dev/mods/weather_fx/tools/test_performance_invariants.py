#!/usr/bin/env python3
"""Performance/quality invariants for Weather FX MAX paths.

This gate protects optimizations that remove redundant CPU/GPU work without
reducing particle populations, celestial populations, animation channels, or
world coverage. It intentionally fails if a future edit reintroduces known hot
loop work or silently lowers the visual budgets used by the 4.33.x baseline.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NS = (ROOT / "lib" / "NightSky.lua").read_text(encoding="utf-8")
WP = (ROOT / "lib" / "voxel_atmos" / "WorldPrecip.lua").read_text(encoding="utf-8")
SP = (ROOT / "lib" / "SnowPack.lua").read_text(encoding="utf-8")
LP = (ROOT / "lib" / "LeafPhysics.lua").read_text(encoding="utf-8")
AU = (ROOT / "lib" / "Audio.lua").read_text(encoding="utf-8")
CA = (ROOT / "lib" / "voxel_atmos" / "CinematicAtmos.lua").read_text(encoding="utf-8")
CFG = (ROOT / "lib" / "Config.lua").read_text(encoding="utf-8")
WE = (ROOT / "lib" / "WindEngine.lua").read_text(encoding="utf-8")
DR = (ROOT / "lib" / "Draw.lua").read_text(encoding="utf-8")
DA = (ROOT / "lib" / "DramalessAtmos.lua").read_text(encoding="utf-8")
QL = (ROOT / "lib" / "Quality.lua").read_text(encoding="utf-8")

checks: list[tuple[str, bool]] = []

def check(name: str, ok: bool) -> None:
    checks.append((name, bool(ok)))
    print(("PASS " if ok else "FAIL ") + name)

def const(text: str, name: str) -> float | None:
    m = re.search(rf"local\s+{re.escape(name)}\s*=\s*([0-9]+(?:\.[0-9]+)?)", text)
    return float(m.group(1)) if m else None

# Quality-preservation budgets from the 4.33.0 MAX renderer. These are not
# performance knobs for this revision; lowering them would be a visual change.
check("MAX star catalogue expanded to 5120 with LOD stepping", "local N = 5120" in NS)
check("RAIN_MAX unchanged at 12000", const(WP, "RAIN_MAX") == 12000)
check("RAIN_PER_TILE unchanged at 18", const(WP, "RAIN_PER_TILE") == 18)
check("SNOW_MAX unchanged at 100000", const(WP, "SNOW_MAX") == 100000)
check("SNOW_PER_TILE unchanged at 22", const(WP, "SNOW_PER_TILE") == 22)
check("GRAIN_MAX unchanged at 3600", const(WP, "GRAIN_MAX") == 3600)
check("HAIL_MAX unchanged at 45000", const(WP, "HAIL_MAX") == 45000)
check("QUALITY defines a manual MAX tier", "max = {" in QL and 'worldSnowCap=100000' in QL and 'worldRainCap=12000' in QL)
check("POTATO hard-caps live 3D weather", 'worldRainCap=550' in QL and 'worldSnowCap=1600' in QL and 'worldRadiusCap=180' in QL)
check("LOW/MEDIUM/HIGH have distinct live 3D ceilings", all(x in QL for x in ('worldSnowCap=5000','worldSnowCap=15000','worldSnowCap=45000')))
check("WorldPrecip consumes quality hard caps", all(x in WP for x in ('qb.worldRainCap','qb.worldSnowCap','qb.worldHailCap','qb.worldSandCap','qb.worldDebrisCap','qb.worldAshCap')))
check("WorldPrecip quality caps radius and respects snow-ground staging policy",
      'qb.worldRadiusCap' in WP and ((all(x in WP for x in ('qb.snowPackDrawCap','qb.footDrawCap'))) or 'function WP.snowGroundCollisionEnabled() return false end' in WP))
check("Cinematic atmosphere consumes whole-mod quality scale", 'Q.profile()' in CA and 'p.atmosphereScale' in CA)
check("Psychic Storm thunder is every-second-bolt only", '_psychicBoltCounter' in AU and '(serial % 2) == 0' in AU and 'if (not psychic) or audible[i] then' in AU)

# NightSky hot-loop invariants.
check("NightSky resolves building factor once per frame", "local buildingFactor = buildingFactorNow()" in NS)
check("NightSky caches celestial vault rotator once per frame", "local vaultRotate = (Sim and Sim.starRotator and Sim.starRotator(vaultAng))" in NS)
check("NightSky caches successful host modules", "if _CelestialSim then return _CelestialSim end" in NS and "if _BuildingLight then return _BuildingLight end" in NS)
check("star loop does not call buildingDensityMul per star", "NightSky.buildingDensityMul(s)" not in NS[NS.find("for i = 1, #STARS, step do"):NS.find("local nPlan", NS.find("for i = 1, #STARS, step do"))])
star_loop = NS[NS.find("for i = 1, #STARS, step do"):NS.find("local nPlan", NS.find("for i = 1, #STARS, step do"))]
check("star loop has no private module require", "V.require" not in star_loop)
check("star loop has no per-star sin/cos", "math.sin" not in star_loop and "math.cos" not in star_loop)
check("star loop has no protected-call closure", "pcall(function" not in star_loop)
push_start = NS.find("local function pushQuad")
push_end = NS.find("local function pushPixelDisk", push_start)
check("pushQuad allocates no per-card nested closure", "local function corner" not in NS[push_start:push_end])

# World precipitation hot-loop invariants.
check("grain target storage is persistent", "target={0,0,0,0}" in WP)
check("grain family segment starts are persistent", "start={1,1,1,1}" in WP)
check("no per-frame grainWant table allocation", "local grainWant = {" not in WP)
check("camera-forward visibility gate exists", "local function cameraForward" in WP)
check("rain keeps precomputed gravity", "grav={}" in WP and "rain.grav[i]" in WP)
check("snow removes redundant invariant coefficient arrays", all(x not in WP for x in ("phRate={}", "turb={}", "bobPhase={}")) and "local turb = 1.1 + seed * 2.4" in WP and "dt * (0.7 + seed * 1.4)" in WP)
check("snow instancing uses bounded staging window", "chunk=8192" in WP and "for i=snowInstance.rowCap+1,chunk" in WP and "need>snowInstance.cap" not in WP)
check("grain removes redundant deterministic animation arrays", all(x not in WP for x in ("uFreq1={}", "uPhase1={}", "uFreq2={}", "uPhase2={}", "drawRotRate={}", "drawFlutterFreq={}", "drawFlutterPhase={}", "drawBaseRot={}")) and "hSpeed={}" in WP and "3.2 + seed * 6.5" in WP and "4.0 + seed * 3.0" in WP)
check("grain draw is segment-bounded", "firstIdx, lastIdx" in WP and "grain.start" in WP)
check("stream focus reuses existing vector", "lastStreamFocus[1], lastStreamFocus[2], lastStreamFocus[3] = px, py, pz" in WP)
check("Settings/Quality/Scene successful modules are cached", all(x in WP for x in ("if _Settings then return _Settings end", "if _Quality then return _Quality end", "if _Scene then return _Scene end")))

# 4.35.23 whole-mod quality-neutral performance hardening.
check("snow flake hot loop has no per-particle pcall", "pcall(SP.resolveFlake" not in WP)
check("Snow accumulation redesign is enabled",
      "SP.ACCUMULATION_ENABLED = true" in SP)
check("SnowPack state remains strictly bounded",
      all(x in SP for x in ("SP.MAX_CELLS = 2048", "SP.MAX_PATCHES_PER_CELL", "SP.MAX_FOOTPRINTS")))
check("SnowPack has flat-world support retention and water rejection",
      "local function retentionFor" in SP and 'if kind=="water" then return 0 end' in SP and 'profile=="thin"' in SP)
check("Falling snow retains point-accurate host collision with banks live",
      "function SP.surfaceAt" in SP and "ctx.TS.at" in SP and "function SP.resolveFlake" in SP)
check("WorldPrecip restores SnowPack only through bounded exact-support authority",
      "SP and SP.ACCUMULATION_ENABLED and SP.beginFrame" in WP and
      "snowCtx and snowCtx.collisionEnabled and SP and SP.resolveFlake" in WP and
      "at most 24 exact-support samples/second" in WP)
check("Host-without-collision or accumulation-OFF path cannot invent a bank",
      ("if accumulationOn and snowCtx and snowCtx.collisionEnabled and SP and SP.fillGroundPool and SP.fillFootPool then" in WP or
       "if snowCtx and snowCtx.collisionEnabled and SP and SP.fillGroundPool and SP.fillFootPool then" in WP) and
      "else\n    gsnow.active=0; foot.active=0" in WP)
check("LeafPhysics ground cache uses numeric stamped cell keys",
      "local key = cx * (r.h + 1) + cz + 1" in LP and "groundStamp[key]" in LP)
check("Leaf ground collision has analytic same-cell fast path",
      "local function sweptGround" in LP and "sameCell=true" in LP)
check("Leaf cross-cell ground sweep remains sub-unit",
      "LP.GROUND_SWEEP_STEP = 0.5" in LP and "ceil(span/LP.GROUND_SWEEP_STEP)" in LP)
check("WindEngine exposes zero-allocation live state", "function Wind.peek()" in WE and "return S" in WE[WE.find("function Wind.peek()"):WE.find("function Wind.state()")])
check("Audio consumes WindEngine live state", "WE.peek and WE.peek()" in AU)
check("2D Draw caches WindEngine after successful resolution", "WindEngineCached" in DR and "local WE = windEngine()" in DR)
check("Config tuningFor caches composed tuning", "Config._tuningCache" in CFG and "local cached = Config._tuningCache[id]" in CFG)
check("Audio one-shot pruning compacts in place", "local w = 0" in AU[AU.find("local function pruneOneShots"):AU.find("Audio.pruneOneShots")])
check("Audio pending thunder queue compacts in place", "local w = 0" in AU[AU.find("local function resolveStrikeEvents"):AU.find("Audio.resolveStrikeEvents")])
check("Audio scheduled thunder queue compacts in place", "local w = 0" in AU[AU.find("local function processScheduledThunder"):AU.find("Audio.processScheduledThunder")])
check("Audio fallback distance table is reused", "local fallbackDistanceOne = { 320 }" in AU)
check("Cinematic atmosphere caches successful optional modules", "local function cachedRequire(name)" in CA and "moduleCache[name] = value" in CA)
check("Cinematic atmosphere reuses weather/frame scratch tables", "local weatherScratch = {}" in CA and "local frameScratch =" in CA)
check("Cinematic atmosphere does not allocate liveChannels table", "liveChannels = {}" not in CA)
check("Cinematic draw reuses pass proof records", "CinematicAtmos._drawPassRecords" in CA and "function CinematicAtmos._safePass" in CA)
check("Cinematic draw reuses precipitation metadata", "CinematicAtmos._precipMetaScratch" in CA)
check("WorldPrecip caches VP uniform once per shader per frame", "sendVPOnce(sh, Voxel3D.vp)" in WP and "vpSentSerial[sh] == wpDrawSerial" in WP)
check("WorldPrecip learns one compatible VP send signature", "vpSendMode" in WP and 'mode == "default"' in WP and 'mode == "row"' in WP)
check("Cinematic cloud descriptors reuse candidate pool",
      "CinematicAtmos._cloudCandidatePool" in CA and "CinematicAtmos._cloudCandidates" in CA and "CinematicAtmos._cloudSort" in CA)
check("Cinematic cloud descriptors avoid fresh candidate array",
      "local candidates = {}" not in CA)
check("Cinematic particle/cloud staging reuses vertex/index pools",
      "CinematicAtmos._particleVertRows" in CA and "CinematicAtmos._particleVerts" in CA and "CinematicAtmos._particleIndices" in CA)
bp0 = CA.find("local function buildParticleVertices")
bp1 = CA.find("local function drawParticles", bp0)
build_particle = CA[bp0:bp1] if bp0 >= 0 and bp1 > bp0 else ""
check("Cinematic particle/cloud staging avoids per-vertex table allocation",
      "verts[#verts + 1] = {" not in build_particle)
check("DramalessAtmos caches WorldPrecip ownership module",
      "function Atmos._worldPrecipForOwnership()" in DA and "Atmos._worldPrecipNs==ns" in DA)
check("DramalessAtmos ownership queries use cached helper",
      DA.count("Atmos._worldPrecipForOwnership()") >= 4)
check("DramalessAtmos caches NPC lightning runtime module",
      "function Atmos._npcLightningForRuntime()" in DA and "Atmos._npcLightningNs==ns" in DA)
check("Cinematic lightning uses cached module resolution",
      'local WL = cachedRequire("WorldLightning")' in CA and
      'local L = cachedRequire("Lightning")' in CA and
      'local NL = cachedRequire("NpcLightning")' in CA)

fails = [name for name, ok in checks if not ok]
print(f"\nperformance invariants: {len(checks)-len(fails)} passed, {len(fails)} failed")
if fails:
    for name in fails:
        print("  -", name)
    sys.exit(1)
