#!/usr/bin/env python3
"""Camera-driven weather ownership, FPV restore, and the snow flicker."""
import re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def dc(s): return "\n".join(l for l in s.split("\n") if not l.lstrip().startswith("--"))
WP = dc((ROOT/"lib/voxel_atmos/WorldPrecip.lua").read_text())
DA = dc((ROOT/"lib/DramalessAtmos.lua").read_text())
ST = dc((ROOT/"lib/Settings.lua").read_text())
CA = dc((ROOT/"lib/voxel_atmos/CinematicAtmos.lua").read_text())
fails = []
def check(ok, m):
    if not ok: fails.append(m)

# 1. ownership must follow the camera, not just "is 3D on"
check("immersiveCamera" in WP, "WorldPrecip no longer reports the camera mode")
m = re.search(r"function Atmos\.handlesAllPrecipitation\(\).*?\nend", DA, re.S)
check(m is not None, "handlesAllPrecipitation is gone")
if m:
    check("immersiveCamera" in m.group(0),
          "handlesAllPrecipitation ignores the camera. At voxel tilt 15/35/50 "
          "it will blanket-suppress the 2D layer while the 3D field is viewed "
          "from 190-300 units up, and sand will vanish in the overworld again")

# 2. the FPV setter must VERIFY, not assume
m2 = re.search(r"function Settings\.setFirstPersonEngaged.*?\n  local function try.*?\n  end", ST, re.S)
check(m2 is not None, "setFirstPersonEngaged's try helper not found")
if m2:
    check("isFirstPerson" in m2.group(0),
          "the FPV setter treats 'did not throw' as success again. Most of "
          "these host setters return nil, so the first one that merely EXISTS "
          "reports success and the chain stops -- the Anime Realism battle "
          "switch then believes it dropped FPV when it did not")

# 3. snow ownership must be based on successful submission, not intent.
# A prior heuristic accepted lastEye/active state even when mesh upload/draw had
# failed, which could erase snow completely. The executable render pipeline
# test now covers transition/failure behaviour, so this static guard enforces
# the stronger fail-closed contract.
m3 = re.search(r"function WP\.drawingSnow\(\).*?\nend", WP, re.S)
check(m3 is not None, "WP.drawingSnow is gone")
if m3:
    check("drawnSnowHealthy" in m3.group(0) and "lastEye" not in m3.group(0),
          "drawingSnow is optimistic again -- ownership must require a proven "
          "healthy 3D snow pass so 2D can rescue real upload/draw failures")
    check("drawnSnowVerts" not in m3.group(0),
          "drawingSnow is tied to visible vertex count again -- rear-camera "
          "culling would resurrect the flat 2D overlay over healthy 3D snow")

# 4. sand ground fog must follow the sand dial
check("sandIntensity" in CA and re.search(r"haze = haze \* min", CA) is not None,
      "the sand ground fog no longer scales with the sand intensity dial")

# --- UI mods: never composite the world over an open menu -------------------
# Scene.inspect stopped only on `s.isOpaque`. Menu states that do not set that
# flag fell through, the walk found the overworld beneath, reported
# visible = "world", and the pipeline drew the world OVER the menu. With a UI
# overhaul like gen3_battle_ui this is worst: that mod hides several native
# states and repaints them in render.hud, AFTER our world pass, and its
# sub-menus carry markers like __gen3uiBag / __gen3uiPCList, never isOpaque.
SC = dc((ROOT/"lib/Scene.lua").read_text())
walk0 = SC.find("local function inspect")
walk1 = SC.find("-- Presentation clock", walk0)
walk = SC[walk0:walk1 if walk1 > walk0 else len(SC)]
check("isPauseMenuState" in walk and "pauseAnchor" in walk and "elseif pauseAnchor then" in walk,
      "Scene.inspect lost the explicit START/pause-menu overlay exception")
check('now.visible = "hidden"' in walk and "Every other unknown UI remains fail-closed" not in walk
      or ('now.visible = "hidden"' in walk and "return" in walk),
      "Scene.inspect no longer fails closed for unrelated unknown UI")
i_bat = walk.find("elseif isBattle")
i_ow = walk.find("elseif s.isOverworld")
i_pause = walk.find("elseif isPauseMenuState")
i_unknown = walk.find("Every other unknown UI")
if i_unknown < 0:
    i_unknown = walk.rfind('now.visible = "hidden"')
check(i_bat != -1 and i_ow != -1 and i_pause != -1 and i_unknown != -1
      and i_bat < i_unknown and i_ow < i_unknown and i_pause < i_unknown,
      "battle, overworld, and pause-menu recognition must run before the unknown-UI fail-closed branch")

# --- WX Pokémon split boundary ---------------------------------------------
check(not (ROOT/"lib/WeatherVariants.lua").exists(),
      "core unexpectedly contains WX Pokémon variant implementation")
check("WeatherVariants" not in (ROOT/"main.lua").read_text(),
      "core main still wires WX Pokémon variant code")

# --- cloud deck must be seamless across a map change ------------------------
# The cell grid is world-anchored (identity = floor(worldX / cell)), so walking
# already streams cells in and out. A MAP CHANGE teleports the focus to
# unrelated coordinates, every cell index changes at once, and a whole new sky
# pops in. Clouds are sky and have no reason to be tied to absolute world
# position, so the cloud-space origin absorbs the jump.
check("cloudShiftX" in CA and "updateCloudOrigin" in CA,
      "the cloud-space origin is gone -- the deck will pop to a completely new "
      "sky on every map transition")
m4 = re.search(r"local function eachWeatherCell.*?\n  local ix0, iz0", CA, re.S)
check(m4 is not None and "cloudShiftX" in m4.group(0),
      "eachWeatherCell takes cell identity from raw world position again, so "
      "the cloud-space shift is not applied and map changes will pop")
# Ordinary movement must never shift it, or the deck is dragged with the player.
m5 = re.search(r"local function updateCloudOrigin.*?\nend", CA, re.S)
check(m5 is not None, "updateCloudOrigin not found")
if m5:
    body = m5.group(0)
    for req, why in (("CLOUD_JUMP_SPEED", "speed"), ("isolated", "isolation")):
        check(req in body,
              f"the map-change detector lost its {why} test -- a bare distance "
              f"check fires during ordinary fast movement and drags the whole "
              f"cloud deck along with the player")

# --- leaves must use the leaf shader, not the snow blob ---------------------
WPx = dc((ROOT/"lib/voxel_atmos/WorldPrecip.lua").read_text())
check("getLeafShader" in WPx, "the leaf shader is gone -- leaves fall back to "
      "the soft radial snow blob and read as coloured discs")
m6 = re.search(r"local gSh = getSnowShader\(\).*?\n  end", WPx, re.S)
check(m6 is not None and "gKind == 3" in m6.group(0),
      "leaves are not dispatched to the leaf shader in the grain pass")

# --- the cloud BANK lattice must also live in cloud space -------------------
# There are TWO cloud paths. 4.30.84 moved the eachWeatherCell grid into cloud
# space; the bank lattice was missed, and it is the one carrying the bank on
# most weathers -- so the bank still jumped at every load point.
check("cloudShiftX" in CA and CA.count("cloudShiftX") >= 4,
      "the cloud bank lattice no longer uses the cloud-space origin -- the bank "
      "will jump to a new sky on every map change")
m7 = re.search(r"local midX = \(e\[1\] \+ f\[1\]\) \* 0\.5[^\n]*", CA)
check(m7 is not None and "cloudShiftX" in m7.group(0),
      "the bank lattice takes cell identity from raw world position again")
m8 = re.search(r"local cx = \(ix \+ 0\.12[^\n]*", CA)
check(m8 is not None and "cloudShiftX" in m8.group(0),
      "the bank's DRAWN position does not shift back to world space -- clouds "
      "would render offset from the player by the accumulated jump")

# --- every declared particle channel must get a 3D driver --------------------
# 8.0.7: the eased WeatherState channel bag is authoritative while natural
# weather changes are staged. The static Types catalogue is retained only as
# a fallback for hosts that do not publish that bag. This prevents the 3D path
# from jumping to full target precipitation at the discrete id handoff.
auth0 = CA.find("local channelSnapshot = V and V.weatherFxChannels or nil")
auth = CA[auth0:CA.find("-- Always tag the weather bag", auth0)] if auth0 >= 0 else ""
check(auth.strip() != "", "the Weather FX -> 3D particle authority block is missing")
check('local liveChannels = type(channelSnapshot)=="table"' in auth and
      'local function resolvedChannel(key)' in auth,
      "3D particle drivers no longer prefer live eased WeatherState channels")
check('Types.byId[wxId]' in auth and ('Types.channel(def,key)' in auth or 'Types.channel(def, key)' in auth),
      "3D particle drivers lost the exact Types compatibility fallback")
for key in ("rain", "snow", "hail", "sand", "ash", "debris"):
    check(f'resolvedChannel("{key}")' in auth or f"resolvedChannel('{key}')" in auth,
          f"{key} is no longer covered by the live 3D particle-channel bridge")
for field, key in (("rainIntensity", "rain"), ("snowIntensity", "snow"),
                   ("hailIntensity", "hail"), ("sandIntensity", "sand"),
                   ("ashIntensity", "ash"), ("debrisIntensity", "debris")):
    check(f"weather.{field} = " in auth and (f'resolvedChannel("{key}")' in auth or f"resolvedChannel('{key}')" in auth),
          f"{key} no longer reaches its live 3D driver {field}")
check('floorProgress("debris")' in auth,
      "authored debris tuning no longer scales with live transition progress")
check('floorProgress("hail")' in auth,
      "authored hail tuning no longer scales with live transition progress")

if fails:
    for f in fails: print("FAIL " + f)
    sys.exit(1)
print("PASS camera modes / fpv restore / snow flicker / sand fog")
