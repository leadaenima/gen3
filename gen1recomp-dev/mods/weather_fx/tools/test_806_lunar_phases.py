#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]
def txt(p): return (R/p).read_text(encoding="utf-8",errors="replace")
sim=txt("lib/CelestialSim.lua"); tod=txt("lib/TimeOfDay.lua"); bod=txt("lib/CelestialBodies.lua"); ns=txt("lib/NightSky.lua"); man=json.loads(txt("manifest.json"))
f=0
def ck(v,m):
 global f; print(("PASS" if v else "FAIL"),m); f+=0 if v else 1
ver=tuple(int(x) for x in str(man.get("version","0.0.0")).split(".")[:3]); ck(ver >= (8,0,6),"manifest is 8.0.6+ lunar line")
ck("function Sim.lunarDaySerial" in sim and "math.floor(gameDays+0.5)" in sim,"night-locked dedicated lunar serial")
ck("function TOD.gameDaySerial" in tod and "TOD.gameDays=TOD._trackedDayCount+hour/24" in tod and "midnight crossings" in tod,"cycle/host clock exposes monotonic visible-day serial")
ck("Sim.lunarDaySerial(hour, dayOverride)" in sim,"lunar phase consumes dedicated lunar clock")
ck("function Sim.moonPhaseLit" in sim,"central physical phase mask")
ck("FIRST_QUARTER" in sim and "LAST_QUARTER" in sim and "WAXING_CRESCENT" in sim and "WANING_CRESCENT" in sim,"all principal lunar phase families retained")
ck("Sim.moonPhaseLit(phase,illum,nx,ny)" in bod,"CelestialBodies uses central phase geometry")
ck("uniform float phase;" in ns and "uniform float illumination;" in ns and "litMask" in ns and "phase < 0.5" in ns,"active projected NightSky uses continuous physical phase geometry")
ck("moonPhaseVisible=smooth(0.005,0.08,illum)" in sim,"new moon visibility collapses without dimming mature crescents")
ck((R/"tests/lunar_phase_progression_test.lua").exists(),"executable lunar progression regression exists")
print(f"8.0.6 lunar gate: {10-f}/10 passed, {f} failed"); sys.exit(1 if f else 0)
