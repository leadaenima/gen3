#!/usr/bin/env python3
"""Celestial-sphere NightSky contracts: density, brightness, positions, rendering."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ns = (ROOT / "lib/NightSky.lua").read_text()
da = (ROOT / "lib/DramalessAtmos.lua").read_text()
main = (ROOT / "main.lua").read_text()
ce = (ROOT / "lib/CelestialEngine.lua").read_text()
fails = 0

def check(cond, msg):
    global fails
    if cond:
        print("  PASS", msg)
    else:
        print("  FAIL", msg)
        fails += 1

print("night sky celestial contracts")

# Architecture
check("FIXED celestial direction" in ns or "dx = dx / L" in ns, "fixed unit directions")
check("camera_eye + D" in ns or "e[1] + s.dx * radius" in ns, "position = eye + D * radius")
check("Voxel3D.vp" in ns, "uses host view-projection")
check("player_delta" not in ns and "star_x +=" not in ns, "no screen-delta position hacks")
pre_catalog = ns.split("for i = 1, N do")[0] if "for i = 1, N do" in ns else ns
check("star_x +=" not in pre_catalog and "star_y +=" not in pre_catalog,
      "no pre-catalog mutable screen-space star positions")

# Density
m = re.search(r"local N = (\d+)", ns) or re.search(r"for i = 1, (\d+)", ns)
n = int(m.group(1)) if m else 0
check(n >= 400, f"star count >= 400 (got {n})")
check("PLANETS" in ns and "PLANETS[i]" in ns, "planets present")
check("PLANET_SIZE_SCALE = 0.56" in ns and "SATURN_SIZE_SCALE = 0.455" in ns and 'p.feature == "rings"' in ns, "planet 20pct / Saturn 35pct visual scale")

# Brightness
check(re.search(r"bright\s*=\s*0\.[5-9]|a = bright|s\.a \* scale", ns) is not None, "brightness model")
check("starScale" in ns or "starScaleNow" in ns, "scale floor path")
check('"add"' in ns, "additive blend")

# 360 / determinism
check("math.pi * 2" in ns, "full azimuth circle")
check("hash(" in ns or "math.sin(n" in ns, "deterministic hash catalog")
check("STARS[i]" in ns and "dx =" in ns, "per-star direction stored")

# Rendering
check("function NightSky.drawWorld" in ns, "drawWorld defined")
check("ensureShader" in ns, "shader path")
check("beginEffect" in ns or "setShader" in ns, "shader bind")
check("function NightSky.draw" in ns, "math fallback draw")
check("projectCelestial" in ns or "basis^T" in ns or "View-space direction" in ns,
      "fallback uses orientation transform not position hack")
check("twinkleAlpha" in ns or "Twinkle" in ns, "twinkle function")
check("twDepth" in ns, "per-star twinkle depth")

# Night gate
check("function NightSky.isNight" in ns, "isNight")
check('NITE' in ns, "NITE supported")
check("computeNightVisibility" in ns.split("function NightSky.drawWorld")[1][:500] or "nightVis" in ns.split("function NightSky.drawWorld")[1][:500], "drawWorld night visibility gated")

# Integration — 4.35.34 strict 3D ownership.
# The reliable fallback is now a fixed-WORLD projected vault drawn immediately
# after Voxel3D.beginScene/Sky.paint and before terrain. It is intentionally not
# the old Sky.region fallback whose height changed with camera pitch.
check("function NightSky.drawProjectedWorld" in ns, "fixed-world projected vault defined")
check("function NightSky.drawSunMoonProjectedWorld" in ns, "projected sun/moon vault defined")
check("vpProjectDirection" in ns and "Voxel3D.vp" in ns, "projected vault uses exact host VP")
projected = ns.split("function NightSky.drawProjectedWorld",1)[1].split("analytic celestial",1)[0]
check("Sky.region" not in projected and "edge" not in projected, "projected vault never uses camera-dependent sky region")
vp_body = ns.split("local function vpProjectDirection",1)[1].split("NightSky.projectDirection",1)[0]
vp_code = "\n".join(line.split("--",1)[0] for line in vp_body.splitlines())
check(re.search(r"\bVoxel3D\.project\s*\(", vp_code) is None,
      "sky projection bypasses terrain WorldCurve helper")
check("Atmos._origBeginScene=Voxel3D.beginScene" in da and "function Voxel3D.beginScene(...)" in da,
      "Atmos owns a background-stage beginScene hook")
check('CR2.drawProjected' in da and len(re.findall(r'CR2\.drawProjected\(', da)) == 1,
      "Dramaless has exactly one CelestialRenderer2 projected background call")
check('function C.drawProjected' in (ROOT / "lib/CelestialRenderer2.lua").read_text(),
      "CelestialRenderer2 owns deep-sky and sun/moon projected passes")
check("after world depth exists" in da and "drawWorldCelestial()" in da and "if cin.draw then" in da,
      "depth-populated celestial ordering is documented")
check("CB.drawWorld(Voxel3D" not in da,
      "Dramaless does not double-render sun/moon through CelestialBodies")
check("Sky.paint" in da, "Sky.paint wrap")
check("function Atmos.handlesCelestialWorld" in da and "celestialWorldWanted()" in da.split("function Atmos.handlesCelestialWorld",1)[1][:500],
      "3D atmosphere exposes independently selectable world-celestial ownership")
check("Atmos._celestialBackgroundDrew=Atmos._worldCelestialDrew" in da,
      "3D ownership reports the depth-tested projected celestial stage")
check("worldCelestial" in main and "DA.handlesCelestialWorld" in main,
      "host Sky.paint queries world-celestial ownership")
main_wrap = main.split("function Sky.paint(w,h,sky,horizonY,cell,body,...)",1)[1].split("Sky._wxNightWrapped=true",1)[0]
check("if not worldCelestial then" in main_wrap and "NightSky.draw" in main_wrap and "wxPaintCelestialDisc" in main_wrap,
      "old screen-space celestial layer remains gated off during 3D ownership")
check("edge` changes with camera pitch" in main_wrap or "vertically squashes" in main_wrap,
      "pitch-compression regression is documented beside the ownership guard")

# 4.35.34 presentation contracts
check("TOD.pin==\"NITE\" or TOD.pin==\"NIGHT\"" in ns and "NightSky._nightVis=target" in ns,
      "manual NIGHT snaps projected vault to weather-attenuated visibility")
check("worldGoldenHour" in ce and "sunsetWarmth" in ce and "warmTarget" in ce,
      "sunrise/sunset warmth reaches host world tint")
check("draw3dScenePost" in da and "discTransmission" in da and "local glareStart=18.0" in da and "local angleDeg=math.deg(math.acos(dot))" in da,
      "direct-sun optics begin from the wider gradual 18-degree cone and remain cloud attenuated")
check("math.min(.94,white*.94)" in da and 'rectangle,"fill",0,0,w,h' in da and "for i=1,28 do" in da,
      "near-direct sun view can produce god rays and strong camera whiteout")
check('setColor,.42,.10,.55' in da and 'math.min(.60,psy*.42)' in da and 'PSYSTORM' in da
      and 'setBlendMode,"add","alphamultiply"' in da,
      "3D PSYSTORM matches the 2D additive pink-violet wash")

# Marker / debug
check("NightSky.DEBUG" in ns, "debug flag")
check("STARS[1]" in ns and ("0.82" in ns or "gold" in ns.lower() or "1.0, 0.82" in ns),
      "distinctive marker star for rotate tests")

# Meteors preserved
check("METEOR" in ns and "function NightSky.update" in ns, "meteor system preserved")


# Continuous astronomy-driven star fade
check("function NightSky.computeNightVisibility" in ns, "night visibility function")
check("function NightSky.starFade" in ns, "per-star alpha fade")
check("_nightVis" in ns, "smoothed visibility state")
check("CelestialEngine" in ns and "starVisibility" in ns, "visibility follows celestial engine")
check("CelestialSim" in ns and "Sim.sample" in ns, "astronomy fallback available")
check('st.starVisibility' in ns or 'st.starVisibility)' in ns, "astronomy fallback uses continuous solar-altitude visibility")
check('sim.starVisibility' in ce and 'starVisibility=clamp01' in ce, "celestial engine composes continuous time-of-day star visibility")
check("local se = hash(i * 7.91) * 2 - 1" in ns, "star catalogue spans full celestial sphere")
check("starRotator" in ns and "starVaultAngle" in ns, "vault uses shared quarter-speed continuous celestial-pole rotation")
check("Milky Way" in ns and "milkyWayVisibility" in ns, "Milky Way follows celestial visibility")
check("uniform float phase;" in ns and "uniform float illumination;" in ns and "litMask" in ns, "moon disc uses continuous physical phase mask")
check("starFade" in ns.split("function NightSky.drawWorld")[1][:4200], "drawWorld uses starFade")
check("nightVis" in ns.split("function NightSky.drawWorld")[1][:1000], "drawWorld uses continuous visibility")

# Time pins force astronomical time but must not override environmental cloud occlusion.
vis_body = ns.split("function NightSky.computeNightVisibility", 1)[1].split("function NightSky.starFade", 1)[0]
check(re.search(r'pin\s*==\s*"(?:NITE|NIGHT)"[^\n]*return\s+1', vis_body) is None and "CelestialEngine" in vis_body,
      "NITE pin preserves cloud attenuation")
check(re.search(r'pin\s*==\s*"DAY"[^\n]*return\s+0', vis_body) is not None,
      "DAY pin returns zero night visibility")
if fails:
    print(f"{fails} failed")
    sys.exit(1)
print("all night-sky contracts passed")

# BuildingLight proximity
blp = ROOT / "lib/BuildingLight.lua"
if blp.exists():
    bl = blp.read_text()
    print("BuildingLight contracts")
    check("REGISTRY" in bl, "building location registry")
    check("collectFromMapData" in bl or "scanEvents" in bl, "map-data building collection")
    check("smoothstep" in bl, "continuous falloff")
    check("SMOOTH" in bl, "temporal smoothing constant")
    check("_lastDist" in bl, "preserve distance when metadata missing")
    check("function BuildingLight.starScale" in bl, "starScale export")
    check("function BuildingLight.update" in bl, "update tick")
    check("warp" in bl and "door" in bl, "warp/door sources")
ns2 = (ROOT / "lib/NightSky.lua").read_text()
check("hideNearBuilding" in ns2, "building-hidden star group")
check("buildingDensityMul" in ns2, "building density multiplier")
check("AZ_BINS" in ns2 or "spatially balanced" in ns2.lower() or "EL_BINS" in ns2, "spatial bins for density")
