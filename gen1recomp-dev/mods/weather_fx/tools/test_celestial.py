#!/usr/bin/env python3
"""Ultimate celestial-engine source contracts.

The executable astronomy/math assertions live in tests/celestial_engine_test.lua.
This gate protects architecture and integration surfaces without re-encoding the
astronomy in Python.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SIM = (ROOT / "lib/CelestialSim.lua").read_text()
ENG = (ROOT / "lib/CelestialEngine.lua").read_text()
BOD = (ROOT / "lib/CelestialBodies.lua").read_text()
NS = (ROOT / "lib/NightSky.lua").read_text()
MAIN = (ROOT / "main.lua").read_text()
CIN = (ROOT / "lib/voxel_atmos/CinematicAtmos.lua").read_text()
DA = (ROOT / "lib/DramalessAtmos.lua").read_text()
WCL = (ROOT / "lib/voxel_atmos/WorldCelestialLighting.lua").read_text()

fails = 0

def check(cond, msg):
    global fails
    print(("PASS" if cond else "FAIL"), msg)
    if not cond:
        fails += 1

check((ROOT / "lib/CelestialSim.lua").exists(), "CelestialSim exists")
check((ROOT / "lib/CelestialEngine.lua").exists(), "CelestialEngine exists")
check("Sim.SYNODIC_MONTH = 29.530588" in SIM, "synodic lunar month")
check("Sim.DRACONIC_MONTH = 27.212221" in SIM, "draconic lunar month")
check("Sim.TROPICAL_YEAR = 365.2422" in SIM, "tropical year")
check("function Sim.solarDeclination" in SIM, "seasonal solar declination")
check("function Sim.sunriseSunset" in SIM, "latitude/season sunrise and sunset")
check("verticalOrbitAngle" in SIM and "VERTICAL_EAST_UP_WEST" in SIM, "default East-Up-West vertical orbit mode")
check("verticalOrbit = true" in (ROOT / "lib/Config.lua").read_text(), "vertical orbit house rule enabled by default")
check("pairedMoonOrbit = true" in (ROOT / "lib/Config.lua").read_text(), "paired moon daily orbit enabled by default")
check("function Sim.discHorizonFraction" in SIM, "limb-aware gradual horizon visibility")
check(all(x in SIM for x in ['"GOLDEN"','"CIVIL"','"NAUTICAL"','"ASTRONOMICAL"','"NIGHT"']), "continuous twilight stages")
check("function Sim.lunarPhase" in SIM and "illum" in SIM, "lunar phase/illumination")
check("solarObscuration" in SIM and "lunarDarkening" in SIM, "solar and lunar eclipses")
check("function Sim.starRotator" in SIM and "north celestial pole" in SIM, "physical celestial-pole rotation")
check("function Sim.siderealAngle" in SIM and "1.00273790935" in SIM, "sidereal rotation")
check("Sim.STAR_VAULT_RATE = 0.25" in SIM and "daySerial(hour, dayOverride)" in SIM and "* Sim.STAR_VAULT_RATE" in SIM, "quarter-speed deep-sky rotation uses continuous unwrapped phase")
check("function Engine.observeCloudField" in ENG and "expireCloudObservation" in ENG, "live cloud occlusion with stale-observation expiry")
check("cloudShadowStrength" in ENG, "cloud shadow authority")
check("milkyWayVisibility" in ENG and "lightPollution" in ENG, "Milky Way and light-pollution authority")
check("particleTint" in ENG and "forwardScatter" in ENG, "particle and atmospheric scattering authority")
check("__weather_fx" in ENG and "moonPhase" in ENG and "dayFraction" in ENG, "companion/water celestial state published")
check("function Celestial.projectBoth" in BOD, "sun and moon can coexist in projected sky")
check("_wxPhase" in BOD and "_wxIllumination" in BOD, "projected moon carries phase metadata")
check('_projectedBodyShaderSource' in NS and 'uniform float illumination;' in NS and 'litMask' in NS and 'solarEclipse' in NS, "3D moon renders continuous physical phase and eclipse silhouette")
check("local b=Celestial.bodies(hour)" in BOD and "hour or (TOD and TOD.hour)" not in BOD, "3D celestial draw consumes composed live CelestialEngine state")
check("_wxAlpha" in MAIN and "_wxColor" in MAIN and "_wxSolarEclipse" in MAIN, "2D celestial discs consume cloud/weather/eclipsing metadata")
check("cloudTransmissionAlongRay" in CIN, "cloud occlusion samples along the real celestial light ray")
check("WorldCelestialLighting" in CIN and "cloudShadowStrength" in WCL, "terrain-conforming 3D cloud-shadow pass is connected")
check("DayNight.body" in DA and "DayNight.bodyAt" in DA and "DayNight.glow" in DA, "voxel host water/day-night body and glow APIs are synchronized")
check("local N = 5120" in NS and "local se = hash(i * 7.91) * 2 - 1" in NS, "full-sphere 5120-star catalogue")
check("starRotator" in NS and "siderealAngle" in NS, "NightSky consumes physical vault rotation")
check("Milky Way" in NS and "milkyWayVisibility" in NS, "Milky Way rendered from celestial authority")
RUNTIME=(ROOT / "lib/EngineRuntime.lua").read_text()
check('EngineRuntime.update(dt, level, sc' in MAIN and 'register("celestial","celestial2"' in RUNTIME, "staged runtime updates celestial authority")
check('register("climate","weather_state"' in RUNTIME and RUNTIME.find('register("celestial","celestial2"') > RUNTIME.find('register("climate","weather_state"'), "celestial stage follows WeatherState authority")
check((ROOT / "tests/celestial_engine_test.lua").exists(), "executable celestial-engine regression exists")
check((ROOT / "tests/celestial_riseset_continuity_test.lua").exists(), "rise/set continuity regression exists")
check((ROOT / "tests/celestial_horizon_handoff_test.lua").exists(), "horizon/handoff regression exists")
check("CB.projectBoth(w,h,edge,nil,nil)" in MAIN, "fallback sky consumes composed celestial presentation state")
check('altitudeDeg - p.y*radiusDeg < 0.0' in NS and 'return NightSky.drawSunMoonProjectedWorld(Voxel3D)' in NS, "active 3D sun/moon path clips below the geometric horizon")

print("RESULT", "OK" if not fails else "FAIL", fails)
sys.exit(1 if fails else 0)
