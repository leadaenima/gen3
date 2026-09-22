#!/usr/bin/env python3
"""Structural checks for the world-space precipitation path.

READ THIS BEFORE ADDING A CHECK HERE.

Every assertion in the previous version of this file was a substring grep:
`"function WP.update" in wp`, `"STREAM_RADIUS" in wp`, and so on. All of them
passed, on every release, while WorldPrecip.lua was a hard compile error that
loaded on no host at all -- the file contained Lua 5.3 bitwise operators (`~`,
`>>`, `&`) that LuaJIT cannot parse, so `V.require("WorldPrecip")` threw and 3D
snow never ran. Greps cannot see that. They only prove text is present.

So the division of labour here is:

  * this file  -- wiring only: does module A still reference module B, are the
                  registration points intact. Cheap, no interpreter needed.
  * dialect    -- the LuaJIT compatibility scan below. This is the check that
                  would have caught the shipped bug, and it is the reason this
                  file is not purely greps any more.
  * behaviour  -- tests/world_precip_sim_test.lua, which loads and RUNS the
                  module. Particle counts, landing rates, near-field density,
                  face contact and allocation churn all live there, because
                  none of them can be established from source text.

If you are about to add an assertion about what the code DOES, it belongs in
the sim test, not here.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
wp_path = ROOT / "lib/voxel_atmos/WorldPrecip.lua"
wp = wp_path.read_text()
ca = (ROOT / "lib/voxel_atmos/CinematicAtmos.lua").read_text()
da = (ROOT / "lib/DramalessAtmos.lua").read_text()

failures = []

def strip(src: str) -> str:
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("--", i):
            m2 = re.match(r"--\[(=*)\[", src[i:])
            if m2:
                close = "]" + m2.group(1) + "]"
                j = src.find(close, i)
                i = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j
            continue
        m2 = re.match(r"\[(=*)\[", src[i:])
        if m2:
            close = "]" + m2.group(1) + "]"
            j = src.find(close, i)
            i = n if j < 0 else j + len(close)
            out.append(" ")
            continue
        c = src[i]
        if c in "\"'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == c:
                    j += 1
                    break
                j += 1
            i = j
            out.append('""')
            continue
        out.append(c)
        i += 1
    return "".join(out)





def check(ok, msg):
    if not ok:
        failures.append(msg)


# --- wiring -----------------------------------------------------------------
check("function WP.update" in wp, "WP.update missing")
check("function WP.draw" in wp, "WP.draw missing")
check("STREAM_RADIUS" in wp, "STREAM_RADIUS missing")
check(
    any(s in wp.lower() for s in ("camera rotation", "camera orientation", "not camera")),
    "the camera-independence rule is no longer stated in WorldPrecip",
)
check("WorldPrecip.update" in ca, "CinematicAtmos no longer drives WorldPrecip")
check(
    'WorldPrecip = "lib/voxel_atmos/WorldPrecip.lua"' in da,
    "WorldPrecip is no longer registered in the DramalessAtmos namespace",
)

# handlesSnow must consult the 3D path rather than answering from a constant.
# Both a hardcoded true (blanks snow when 3D fails) and a hardcoded false
# (double-draws the 2D sheet over working 3D snow) have shipped.
m = re.search(r"function Atmos\.handlesSnow\(\).*?\nend", da, re.S)
check(m is not None, "Atmos.handlesSnow not found")
if m:
    body = m.group(0)
    check("drawingSnow" in body,
          "handlesSnow no longer asks WorldPrecip whether it is actually drawing")
check("function WP.drawingSnow" in wp, "WP.drawingSnow missing")

# --- battle / indoors wiring (audit fixes) ----------------------------------
# The world precipitation volume must stand down during battles BEFORE it reads
# the battle camera/focus or performs stream-anchor carry. 8.1.55's old 1-second
# cached `q = 0` gate was too late: the battle focus could jump first, dragging
# the entire snow pool into the battle transition (visible dump), then the cache
# stopped it, and BattleDraw later restarted its own snow. 8.1.56 uses the
# frame-live Battle.current()/Scene authority and returns before any re-anchor.
wp_stripped=strip(wp)
check('B.current and B.current()' in wp,
      'WorldPrecip battle gate no longer consults frame-live Battle.current()')
update_pos=wp.find('function WP.update')
battle_gate=wp.find('if battleActive() then return end', update_pos)
focus_pos=wp.find('local px = focus[1] or 0', update_pos)
shift_pos=wp.find('shiftPool(', update_pos)
check(battle_gate != -1 and focus_pos != -1 and battle_gate < focus_pos,
      'WorldPrecip battle suspension no longer happens before battle camera/focus is read')
check(battle_gate != -1 and shift_pos != -1 and battle_gate < shift_pos,
      'WorldPrecip can still shift/re-anchor world precipitation during battle entry')
draw_pos=wp.find('function WP.draw')
draw_gate=wp.find('if battleActive() then', draw_pos)
check(draw_gate != -1 and draw_gate < wp.find('wpDrawSerial = wpDrawSerial + 1', draw_pos),
      'WorldPrecip draw path can still emit stale overworld precipitation during battle transition')

# Scene must NOT infer "outdoors" from an unsampleable overworld. The overworld
# is routinely unsampleable during a battle, and treating that as outdoors is
# what put weather into cave/building/SS Anne battles and reset the 5-minute
# indoor timer mid-fight.
# NOTE: strip comments first. The fixes below are documented in-place with
# comments that QUOTE the old lines verbatim, so a naive substring check matches
# its own documentation and fails on a correct tree. It did exactly that once.
sc = strip(( ROOT / "lib/Scene.lua").read_text())
check("owKnown" in sc,
      "Scene no longer tracks whether the overworld was sampleable")
check("now.indoors = (ow ~= nil) and (not now.outdoor)" not in sc,
      "Scene has reverted to fail-open indoors: an unsampleable overworld will "
      "read as outdoors again")

# strip() blanks string literals, which is right for operator scanning and
# useless here -- these checks are ABOUT string values. A first draft used it
# and both checks below became vacuous: the regex matched nothing and the HAIL
# check failed against a correct tree. Drop whole-line comments instead, so the
# data survives and this file's own explanatory comments do not self-match.
def decomment(src):
    out = []
    for ln in src.split("\n"):
        if ln.lstrip().startswith("--"):
            continue
        out.append(ln)
    return "\n".join(out)


# --- chip damage: HAIL only ------------------------------------------------
# SNOW_LIGHT, BLIZZARD and SLEET all carried chipType = "ICE" and chipped every
# turn. From Gen 9 on, Snow does not damage at all -- it raises Ice-type
# Defence -- and only Hail chips. Any weather whose battle mapping is "SNOWY"
# must not carry a chipType.
ty = decomment((ROOT / "lib/Types.lua").read_text())
for m2 in re.finditer(r'id = "([A-Z_]+)"[^\n]*battle = "SNOWY"', ty):
    line = m2.group(0)
    check("chipType" not in line,
          f'{m2.group(1)} is a SNOWY weather but still carries chipType -- '
          f'snow must not deal residual chip damage, only HAIL does')
check('id = "HAIL", label = "HAIL", chipType = "ICE"' in ty,
      "HAIL lost its chipType -- hail is the one weather that SHOULD chip")

# --- lightning must tick without the 2D rect -------------------------------
# Draw.update returns early when lastRect is unset, and lastRect is only
# populated by Draw.frame -- which returns BEFORE setting it when the 2D draw
# scale is 0. That is exactly the case when the 3D voxel atmosphere owns
# precipitation, so on first-person setups Lightning.update() was never reached:
# no strikes scheduled, no flash, and no thunder (Audio fires thunder off
# Lightning.justStruck). Lightning must be ticked BEFORE the rect guard.
dw = decomment((ROOT / "lib/Draw.lua").read_text())
li = dw.find("Lightning.update(")
guard = dw.find("if lastRect.w <= 1 or lastRect.h <= 1 then return end")
check(li != -1, "Draw no longer ticks Lightning at all")
check(guard != -1, "the lastRect guard in Draw.update is gone -- re-check this")
if li != -1 and guard != -1:
    check(li < guard,
          "Lightning.update sits AFTER the lastRect early-return in Draw.update "
          "-- it will never run when the 3D atmosphere owns precipitation, so "
          "there will be no lightning and no thunder")

# --- no snow during rain weathers ------------------------------------------
# CinematicAtmos runs its own dynamic profile cycle, independent of the Weather
# FX weather id, so the profile could sit on `snow`/`blizzard` (snowIntensity
# 3.6/5.5) while the game was raining -- and WorldPrecip rendered it. Both
# id-classifiers were already correct; the intensity arrived behind them.
ca = decomment((ROOT / "lib/voxel_atmos/CinematicAtmos.lua").read_text())
check("precipWxId" in ca,
      "the precipitating-weather predicate is gone")
check("weather.snowIntensity = 0" in ca,
      "CinematicAtmos no longer clamps snow to zero for non-snowy precipitating "
      "weathers -- 3D snow will fall during rain, storm and primal again")

# --- 3D clouds + precipitation must share a camera-invariant world anchor ---
# Voxel3D.focus is a LOOK TARGET in first person, while Voxel3D.eye is an orbiting
# camera position in third person. Either point can be camera-driven depending on
# mode. The streamer must therefore prefer the real player, use eye only in FPV,
# and use focus for orbit/third-person. The cloud-cell streamer must use the same
# helper or clouds and falling precipitation can visibly separate while turning.
anchor_fn = re.search(r"local function worldPrecipAnchor\(Voxel3D\).*?\nend", ca, re.S)
check(anchor_fn is not None, "worldPrecipAnchor helper is missing")
if anchor_fn:
    body = anchor_fn.group(0)
    check("Voxel3D.player" in body,
          "WorldPrecip anchor no longer prefers the real Voxel3D.player position")
    check("isFirstPerson" in body and "fp and Voxel3D.eye" in body,
          "first-person precipitation no longer anchors to the rotation-invariant camera eye")
    check("Voxel3D.focus" in body and "focus-orbit" in body,
          "third-person/orbit precipitation no longer anchors near the avatar via focus")

cell_fn = re.search(r"local function eachWeatherCell\(Voxel3D, cell, baseRadius, fn\).*?\nend", ca, re.S)
check(cell_fn is not None and "worldPrecipAnchor(Voxel3D)" in cell_fn.group(0),
      "3D cloud cells and precipitation do not share the same world anchor -- "
      "turning the camera can separate the cloud bank from the falling weather")

# Falling cloud precipitation must get its emission band from the SAME deck
# geometry the visible 3D clouds use. The old code read `weather.cloudBase`, a
# field the live profiles normally do not publish, so snow silently spawned from
# a generic player-relative slab instead of out of the cloud bank.
check("local function precipitationDeckBand" in ca,
      "CinematicAtmos no longer derives a precipitation emission band from the 3D cloud deck")
check("weather.deckY0" in ca and "weather.deckYSpan" in ca,
      "precipitation deck linkage no longer reads the live cloud profile deckY0/deckYSpan")
update_pos = ca.find('CinematicAtmos._safePass("world-precip-update"')
if update_pos < 0: update_pos = ca.find("WorldPrecip.update(dt, foc")
update_call = ca[max(0,update_pos - 900): update_pos + 500] if update_pos >= 0 else ""
meta_ok = ("meta.anchorKind,meta.deckY,meta.deckSpan=focKind,deckY,deckSpan" in update_call)
for token in ("anchorKind = focKind", "deckY = deckY", "deckSpan = deckSpan"):
    check(token in update_call or meta_ok,
          f"WorldPrecip.update is missing 3D storm metadata: {token}")
for family, marker in (("rain", "local rainBase = precipDeckY"),
                       ("snow", "local snowBase = precipDeckY"),
                       ("hail", "local hailBase = precipDeckY"),
                       ("ash", "local ashBase = precipDeckY")):
    check(marker in wp,
          f"3D {family} is no longer emitted from the live cloud-deck band")
check("weather and weather.cloudBase" not in wp,
      "WorldPrecip is reading the obsolete cloudBase field again instead of the rendered 3D deck")
check("WL.strike(foc, max(60, boltDeck)," in ca and "boltDeck = deckY" in ca,
      "3D lightning is no longer rooted in the same physical cloud deck as the storm particles")

# Camera values may be used only to VIEW/billboard/cull particles, never to move
# their simulated X/Y/Z. The warp carry is allowed only while the selected world
# anchor source stays the same; a camera-mode/source switch must not drag pools.
check("sameAnchorKind" in wp and "lastStreamKind" in wp,
      "WorldPrecip no longer guards warp-carry against camera/anchor source changes")

# The actual Weather FX state must drive the 3D atmosphere and all particle
# channels. An independent cinematic CLEAR/PARTLY cycle must never be allowed to
# turn real SNOW/RAIN into missing 3D precipitation again.
check("local function wxAtmosProfileKey" in ca,
      "3D atmosphere no longer maps Weather FX precipitation to a matching cloud profile")
check('weather, weatherKey = WEATHER[linkedProfile], "wx:" .. linkedProfile' in ca,
      "recognized Weather FX precipitation no longer overrides the independent cinematic profile")
check('local def = Types and Types.byId and Types.byId[wxId]' in ca,
      "3D particle authority no longer retains the exact Weather FX catalogue fallback")
auth0 = ca.find("local channelSnapshot = V and V.weatherFxChannels or nil")
auth = ca[auth0:ca.find("-- Always tag the weather bag",auth0)] if auth0 >= 0 else ""
check('local liveChannels = type(channelSnapshot)=="table"' in auth and
      'local function resolvedChannel(key)' in auth,
      "3D Weather FX authority no longer consumes live eased WeatherState channels")
for key in ("rain", "snow", "hail", "sand", "ash", "debris"):
    check(f'resolvedChannel("{key}")' in auth or f"resolvedChannel('{key}')" in auth,
          f"3D Weather FX authority is missing the live {key} particle channel")
check('weather.rainIntensity = resolvedChannel("rain")' in auth,
      "3D rain can again jump by discrete id instead of following WeatherState")
check('weather.snowIntensity = resolvedChannel("snow")' in auth,
      "3D snow can again jump by discrete id instead of following WeatherState")
check('weather._wxChannelsResolved = liveChannels == true' in ca,
      "CinematicAtmos no longer marks the live channel bag as authoritative")
check('local resolvedByAtmos = weather._wxChannelsResolved == true' in wp and
      'if not resolvedByAtmos then' in wp,
      "WorldPrecip can again refill zero live channels from the target weather id")

# --- 2D snow must be suppressed when 3D snow draws -------------------------
# Atmos.handlesSnow() existed since 4.28.69 but was never exposed on the bridge,
# so Draw could not ask it. Worse, Draw.passPrecipitationOnly -- the diorama
# path -- handed raw channels to Particles.draw with NO ownership check, while
# its own comment claimed it skipped the 2D pass when 3D was drawing. The 2D
# snow sheet therefore drew over the 3D flakes and read as a locked overlay.
br = decomment((ROOT / "lib/VoxelAtmosBridge.lua").read_text())
check("function Bridge.handlesSnow" in br,
      "VoxelAtmosBridge no longer exposes handlesSnow -- Draw cannot ask "
      "whether 3D snow is drawing, so the 2D sheet will stack on top of it")
dr = decomment((ROOT / "lib/Draw.lua").read_text())
check("local function use3dSnow" in dr, "Draw has no snow ownership gate")
ppo = dr[dr.find("function Draw.passPrecipitationOnly"):]
ppo = ppo[:ppo.find("\nend")]
check("Particles.draw(alpha, Draw.channels())" not in ppo,
      "Draw.passPrecipitationOnly hands RAW channels to Particles.draw again -- "
      "2D snow will draw over the 3D flakes on the diorama path")
check("filtered2dPrecipChannels" in ppo,
      "Draw.passPrecipitationOnly no longer uses the shared per-family 3D "
      "ownership filter -- the normal and diorama routes can drift again")

# --- the rain gate must report facts, not assumptions -----------------------
# use3dPrecip() used to fall back to `VoxelAtmos.active or
# VoxelAtmos.handlesPrecipitation` -- function REFERENCES, never called, always
# truthy. The gate could not fail, so it never checked anything.
check("function WP.drawingRain" in wp, "WP.drawingRain missing")
da2 = decomment((ROOT / "lib/DramalessAtmos.lua").read_text())
check("drawingRain" in da2,
      "handlesPrecipitation no longer asks WorldPrecip what it actually drew -- "
      "it is back to assuming 3D rain draws whenever the weather id looks rainy")
dr2 = decomment((ROOT / "lib/Draw.lua").read_text())
check("VoxelAtmos.active or VoxelAtmos.handlesPrecipitation" not in dr2,
      "the always-true function-reference test is back in use3dPrecip -- that "
      "gate cannot fail and so checks nothing")

# --- world-space lightning --------------------------------------------------
# The 2D system builds its bolt in SCREEN space from pickFarImpact(viewW,viewH),
# so every strike is in front of the player by construction and slides with the
# camera. World lightning strikes a world tile and stays on it.
wl_path = ROOT / "lib/voxel_atmos/WorldLightning.lua"
check(wl_path.exists(), "WorldLightning.lua is missing")
da6 = decomment((ROOT / "lib/DramalessAtmos.lua").read_text())
check("WorldLightning" in da6, "WorldLightning is not registered in the namespace")
check("function Atmos.handlesLightning" in da6, "Atmos.handlesLightning is gone")
# Lightning is INTERMITTENT: the gate must test that 3D lightning is running,
# not that it drew this frame, or the 2D overlay returns between strikes.
mg = re.search(r"function Atmos\.handlesLightning\(\).*?\nend", da6, re.S)
check(mg is not None and "drawingBolt" not in mg.group(0),
      "handlesLightning tests whether a bolt DREW this frame -- a bolt lasts a "
      "fraction of a second, so the 2D overlay would come back between strikes")
br6 = decomment((ROOT / "lib/VoxelAtmosBridge.lua").read_text())
check("function Bridge.handlesLightning" in br6,
      "the bridge does not expose handlesLightning, so Draw cannot ask")
dr6 = decomment((ROOT / "lib/Draw.lua").read_text())
check("not use3dLightning()" in dr6,
      "the 2D bolt is drawn unconditionally again -- it will overlay the 3D one")
li6 = decomment((ROOT / "lib/Lightning.lua").read_text())
check("strikeSerial" in li6,
      "Lightning.strikeSerial is gone -- 3D bolts would have to read the "
      "CONSUMED justStruck flag and would steal the thunder one-shot")

# --- no 2D weather at all on the 3D setting ---------------------------------
# Channel-by-channel gating never converged: each pass covered the channels in
# the last report and missed whatever the next weather carried (SLEET hail,
# PSYSTORM debris, DRAGONSTORM sand+debris, VERDANT_RAIN splash). The rule is
# now blanket -- if the 3D atmosphere is running, the flat layer does not draw.
da8 = decomment((ROOT / "lib/DramalessAtmos.lua").read_text())
check("function Atmos.handlesAllPrecipitation" in da8,
      "the blanket 3D-owns-precipitation gate is gone -- 2D weather will leak "
      "back in on whichever channel the next weather happens to carry")
br8 = decomment((ROOT / "lib/VoxelAtmosBridge.lua").read_text())
check("function Bridge.handlesGrains" in br8,
      "the bridge does not expose per-family grain ownership")
dr8 = decomment((ROOT / "lib/Draw.lua").read_text())
check(dr8.count("filtered2dPrecipChannels") >= 3,
      "the shared per-family 2D fallback filter is not used by both draw paths")
for key in ("rain", "snow", "hail", "sand", "debris", "ash"):
    check(f'suppress("{key}"' in dr8,
          f"the per-family fallback filter does not guard {key}")
check("hailIntensity" in wp,
      "3D hail is gone -- hail needs its own proven family path")

# --- every grain family needs a stable per-pass colour -----------------------
# UV/falloff data consumes the vertex tint channels, so colour belongs to the
# family draw pass.  The old per-particle loop repeatedly read Settings for
# leaves and then let the last processed particle tint the entire mesh.
pass_color = wp[wp.find("local passKind = wantedKind"):wp.find("local DEPTH =", wp.find("local passKind = wantedKind"))]
check(pass_color.strip() != "", "the stable per-family grain pass-colour setup is missing")
for k, name in ((1, "hail"), (2, "sand"), (3, "debris"), (4, "ash")):
    check(f"passKind == {k}" in pass_color,
          f"grain kind {k} ({name}) has no stable pass-colour branch")
check("0.90, 0.95, 1.00" in pass_color,
      "the hail ice tint is missing from the family pass")
check("leafColor()" in pass_color,
      "LEAF COLOR no longer reaches the real 3D leaf-family tint")
particle_loop = wp[wp.find("for i = 1, active do", wp.find("local function drawGrainPass")):
                   wp.find("grainMesh = uploadMesh", wp.find("local function drawGrainPass"))]
check("leafColor()" not in particle_loop and 'V.require("Settings")' not in particle_loop,
      "3D leaves are reading Settings per particle again; tint must be resolved once per draw pass")

# --- 4.35.20 leaf collision / seasonal colour -------------------------------
lp_path = ROOT / "lib/LeafPhysics.lua"
check(lp_path.exists(), "LeafPhysics module is missing")
if lp_path.exists():
    lp = decomment(lp_path.read_text())
    check("VoxelScene" in lp and "groundAt" in lp,
          "3D leaves do not use voxel surface height for building/terrain collision")
    check("NPC_MAX_CONTACT = 2.0" in lp,
          "leaf/NPC contact no longer has the strict two-second escape cap")
    check("leafSettled" in wp and "leafWallT" in wp,
          "WorldPrecip does not retain leaf pile/wall-contact state")
    check("LP.resolve" in wp and "MAX_SETTLED_FRACTION" in lp,
          "live 3D leaves are not routed through bounded collision/pile physics")
    check(('pcall(V.require, "VoxelScene")' in wp or 'safe(V.require, "VoxelScene")' in wp or 'V.safeCall(V.require, "VoxelScene")' in wp) and
          'LP.beginFrame, streamMeta, groundY, hostVoxelSceneModule()' in wp,
          "WorldPrecip no longer passes the real voxel-host VoxelScene into root LeafPhysics")
    check("hostVoxelScene or meta.voxelScene or meta.VoxelScene" in lp,
          "LeafPhysics no longer accepts explicit host VoxelScene authority")
    check("sweptWall" in lp and "sweptNpc" in lp and "SWEEP_STEP = 0.5" in lp,
          "leaf collision lost sub-unit continuous swept building/NPC collision")
    check("local function ddaCells" in lp and "local function ddaWall" in lp and "TILE = 16" in lp,
          "leaf collision lost exact 16-unit voxel-grid DDA traversal")
    check("local gridHit=ddaWall" in lp and "if gridHit then return gridHit end" in lp,
          "DDA is no longer the primary building collision before the 0.5-unit fallback sweep")
    check("surfaceEnvelope" in lp and "LEAF_RADIUS = 1.25" in lp,
          "leaf collision lost physical footprint/corner sampling")
    check("function LP.isPenetrating" in lp and "LP.isPenetrating" in wp and "tries < 5" in wp,
          "leaf collision no longer repairs particles that spawn inside solid building volume")
    check("PILE_MIN = 35.0" in lp and "PILE_MAX = 90.0" in lp,
          "leaf pile lifetime is no longer extended to 35-90 seconds")
    check("(2.0 + random() * 2.8) * 5.0" in wp and "(3.2 + random() * 4.2) * 5.0" in wp,
          "airborne leaf lifetime is no longer at least 5x the old values")
    cin_text = decomment((ROOT / "lib/voxel_atmos/CinematicAtmos.lua").read_text())
    drama_text = decomment((ROOT / "lib/DramalessAtmos.lua").read_text())
    check(("state = state" in cin_text or "meta.player,meta.state,meta.Voxel3D=player,state,Voxel3D" in cin_text)
          and "Atmos._lastPlayer, Atmos._lastState" in drama_text,
          "real overworld state no longer reaches LeafPhysics for host-private NPC pose fallback")
    check("state.entities" in lp and "state.ghosts" in lp,
          "LeafPhysics cannot rebuild NPC collision bodies when host posed actors are private")
settings_text = decomment((ROOT / "lib/Settings.lua").read_text())
check('key = "leafColor"' in settings_text and 'default = "seasonal"' in settings_text,
      "LEAF COLOR does not default to season-driven colour")
check('season == "AUTUMN"' in settings_text and 'season == "WINTER"' in settings_text,
      "seasonal leaf colour mapping is missing autumn/winter behavior")
particles_text = decomment((ROOT / "lib/Particles.lua").read_text())
check('S.leafColor' in particles_text and 'local leafR, leafG, leafB = leafTint()' in particles_text,
      "legacy/2D leaves no longer share the seasonal leaf-colour authority")
config_text = decomment((ROOT / "lib/Config.lua").read_text())
season_text = decomment((ROOT / "lib/Seasons.lua").read_text())
cel_sim_text = decomment((ROOT / "lib/CelestialSim.lua").read_text())
check('daysPerSeason = 15' in config_text and 'return 15' in season_text and 'or 15' in cel_sim_text,
      "accelerated 15-day / six-real-hour season authority is not consistent across config, Seasons and CelestialSim")

# --- 8.1.28 flat-world SnowPack redesign ---------------------------------
sp_path = ROOT / "lib/SnowPack.lua"
check(sp_path.exists(), "SnowPack collision/accumulation helper is missing")
if sp_path.exists():
    sp = decomment(sp_path.read_text())
    check("SP.ACCUMULATION_ENABLED = true" in sp,
          "8.1.28 SnowPack redesign is not enabled")
    check("function SP.resolveFlake" in sp and "groundAt" in sp and "hostVoxelScene" in sp,
          "falling snow lost real voxel-host surface collision")
    check("function SP.surfaceAt" in sp and "ctx.TS.at" in sp,
          "falling snow lost point-accurate host/model surface collision")
    check("local function retentionFor" in sp and 'if kind=="water" then return 0 end' in sp,
          "flat-world surface retention/water rejection is missing")
    check("SP.MAX_CELLS = 2048" in sp and "SP.MAX_PATCHES_PER_CELL" in sp and "SP.MAX_FOOTPRINTS" in sp,
          "SnowPack persistent state is not explicitly bounded")
    check(('SP.ACCUMULATION_ENABLED and kind~="water"' in sp or 'accumulationEnabled() and kind~="water"' in sp),
          "flake hit path does not explicitly reject water before persistent deposit")
    snow_ground_suspended = "function WP.snowGroundCollisionEnabled() return false end" in wp
    check(("SP.resolveFlake" in wp and "SP and SP.ACCUMULATION_ENABLED and SP.beginFrame" in wp) or
          (snow_ground_suspended and "Do not call SnowPack.resolveFlake()" in wp),
          "WorldPrecip neither integrates SnowPack nor explicitly suspends snow-ground collision")
    check("else\n    gsnow.active=0; foot.active=0" in wp,
          "WorldPrecip fail-closed path clears snow-bank/footprint pools when exact support is unavailable")
    if snow_ground_suspended:
        check("creates no ground snow" in wp and "addGroundSnow(" not in wp[wp.find("-- ---- SNOW"):wp.find("-- ---- GRAINS")],
              "suspended snow-ground path can still create persistent ground snow")
    else:
        start=wp.find("elseif (not (snowCtx and snowCtx.collisionEnabled))")
        fallback = wp[start:wp.find("elseif slife[i]", start)]
        check("addGroundSnow(" not in fallback,
              "host-without-collision fallback can invent unsupported persistent ground snow")

# --- hail must be hail ------------------------------------------------------
# HAIL must not also request snow, or hail and snow fall together and the two
# cannot be told apart.
st = wp[wp.find("local SNOW_TARGET"):wp.find("local SNOW_TARGET") + 800]
check(not re.search(r"\bHAIL\s*=", st),
      "HAIL is back in SNOW_TARGET -- hail weather will drop snowflakes as well "
      "as hailstones, which muddies the distinction")

# Hail has a dedicated shape shader and stable ice tint; it must never inherit
# the sand family appearance.
check("getHailShader" in wp,
      "hail has no dedicated shader -- through the snow shader it renders as a "
      "soft smudge, i.e. indistinguishable from a snowflake")
check("HAIL_MAX" in wp,
      "hail is back on the shared grain cap, which is far too sparse to read as a hailstorm")
check(re.search(r"if passKind == 1 then\s*\n\s*grainR, grainG, grainB = 0\.90, 0\.95, 1\.00", wp) is not None,
      "hail has no stable ice pass tint -- it may render with another grain family's colour")

# --- hail must look like hail, not sand and not snow ------------------------
# And it must be distinguishable from snow. The UV range is what separates a
# tight bright pellet from a soft smudge, and INSETTING is the wrong direction:
# it keeps d small so the falloff never completes, which gave hard squares.
m4 = re.search(r"if kind == 1 then u0, u1 = (-?[0-9.]+), (-?[0-9.]+) end", wp)
check(m4 is not None, "the hail UV range is gone")
if m4:
    lo, hi = float(m4.group(1)), float(m4.group(2))
    check(lo < 0.0 and hi > 1.0,
          f"hail UVs are inset ({lo}/{hi}) -- inset keeps the falloff from "
          f"completing, which renders hail as a square or as a snow-like blob; "
          f"they must EXPAND past 0..1 so the lit core is tight and the corners "
          f"fade out")

# --- grains must be uniform per AREA ----------------------------------------
# spawnGrainAt used random()^1.6 -- an exponent above 1 pulls mass toward the
# centre, so every grain family bunched into a lump over the player instead of
# covering the rendered map. Reported for hail; sand, ash and debris had it too.
# sqrt of a uniform sample is what makes density constant per unit area.
gs2 = wp[wp.find("local function spawnGrainAt"):wp.find("local function spawnGrainAt") + 1400]
check("local t = sqrt(random())" in gs2,
      "grain radial sampling is not uniform per area -- grains will bunch over "
      "the player instead of covering the map")
check("random() ^ 1.6" not in gs2,
      "the inward-biased grain exponent is back")

bt = strip((ROOT / "lib/Battle.lua").read_text())
check("if not Scene.now.mapId then indoors = false end" not in bt,
      "Battle has reverted to forcing indoors=false when the map id is missing "
      "-- which is exactly the case during a battle underground")

# 4.35.26 ground snow is real 3D volume geometry, not a flat soft-disc decal.
# It intentionally uses the simple per-vertex colour shader: the snow bank's
# silhouette is authored by beveled/rounded geometry, so applying the old
# radial snow-card shader would punch circular holes/discard side faces.
# This wiring test ensures the live pass keeps its full volume mesh.
m = re.search(r"local function drawGroundSnow\(Voxel3D\).*?\nend\n", wp, re.S)
check(m is not None, "drawGroundSnow not found")
if m:
    body = m.group(0)
    check("BankGeom.patch" in body and "BankGeom.rect" not in body,
          "drawGroundSnow is not using the sub-cell radial 3D mound geometry")
    check("getGrainShader" in body,
          "3D snow bank no longer uses the full per-vertex volume shader")
    check("SNOW_FMT" in body,
          "3D snow bank no longer uses the proven world-space vertex format")
    check("gsnow.height" in body and "gsnow.baseY" in body,
          "drawGroundSnow stopped consuming physical snow depth/height")
    check(wp.count("drawGroundSnow(Voxel3D)") >= 2,
          "drawGroundSnow exists but is no longer invoked by the live WorldPrecip draw path")


# --- dialect: LuaJIT is Lua 5.1 and has no bitwise operators ----------------
# This is the check that matters. Strings and comments are removed first so a
# `~` inside a shader source block or a prose comment does not trip it.
BANNED = [
    (r"(?<![<>=~])~(?!=)", "bitwise ~"),
    (r">>", "bitwise >>"),
    (r"<<", "bitwise <<"),
    (r"(?<!&)&(?!&)", "bitwise &"),
    (r"(?<!/)//(?!/)", "integer division //"),
]

for path in sorted((ROOT / "lib").rglob("*.lua")) + sorted(ROOT.glob("*.lua")):
    body = strip(path.read_text())
    for ln, line in enumerate(body.split("\n"), 1):
        for pat, why in BANNED:
            if re.search(pat, line):
                failures.append(
                    f"{path.relative_to(ROOT)}:{ln}: {why} is Lua 5.3 only and "
                    f"will not compile under LuaJIT"
                )

if failures:
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)

print("PASS world precip (wiring + LuaJIT dialect)")

# --- 4.33.8 world-space lightning + local weather lighting -----------------
wl8 = decomment((ROOT / "lib/voxel_atmos/WorldLightning.lua").read_text())
ca8 = decomment((ROOT / "lib/voxel_atmos/CinematicAtmos.lua").read_text())
da8 = decomment((ROOT / "lib/DramalessAtmos.lua").read_text())
check('WorldLighting = "lib/voxel_atmos/WorldLighting.lua"' in da8,
      "WorldLighting is not registered in the private 3D namespace")
check("VoxelScene" in wl8 and "groundAt" in wl8,
      "world lightning no longer resolves actual voxel terrain height")
check("renderedRegions" in wl8 and "neighbors" in wl8,
      "lightning no longer samples the current + rendered-neighbour map set")
for zone in ('"near"', '"mid"', '"far"'):
    check(zone in wl8, f"lightning distribution lost {zone} strike band")
check("local topY = tonumber(deckY)" in wl8 and "py + (deckY" not in wl8,
      "lightning cloud origin is not an absolute world-space deck altitude")
check("GROUND_DROP" not in wl8,
      "lightning still terminates on the old player-relative generic ground plane")
check("deckSpan = deckSpan" in ca8 and "map = map, neighbors = neighbors" in ca8,
      "CinematicAtmos does not pass live cloud/map context to WorldLightning")
check('V.require("WorldLighting")' in ca8,
      "3D lightning does not feed the world-space weather lighting pass")
check("function WL.lights" in wl8,
      "WorldLightning does not publish localized strike lights")
dr8light = decomment((ROOT / "lib/Draw.lua").read_text())
check("local flash = use3dLightning() and 0 or Lightning.flash(lightMode)" in dr8light,
      "healthy 3D lightning still applies a full-screen 2D flash/grade")
check('if not use3dLightning() then' in dr8light,
      "healthy 3D lightning still calls the 2D screen-space lightning compositor")
check("player = player" in ca8,
      "CinematicAtmos does not pass live player/render-distance context to lightning")
check("RenderDistance" in wl8 and "RD.point" in wl8,
      "lightning targets are not constrained to the host's rendered world radius")
