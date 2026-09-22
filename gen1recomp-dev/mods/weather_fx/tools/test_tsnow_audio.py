#!/usr/bin/env python3
"""THUNDERSNOW audio regressions.

THUNDERSNOW is the only weather that is SNOW-ONLY yet rain-family for audio --
its catalogue entry says so outright ("Snow only (no rain streaks); lightning
via strike"). Every audio gate written against "is rain on screen" therefore
fails for it, and it silences the storm a second or two after it starts.

Three separate faults produced the one symptom:
  1. Draw computed "precipitation on screen" as rain+hail, ignoring snow.
  2. nudgeFromVisual called stopAllBeds(), which also stopped the thunder
     one-shots -- so a clap already in the air was cancelled. Measured: 120
     claps killed in 2 seconds of THUNDERSNOW.
  3. The bed gate demanded a rain channel, so the `storm` bed started and was
     cut a frame later.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def decomment(src):
    """Drop whole-line Lua comments.

    These checks assert that certain calls are ABSENT, and the fixes are
    documented in place with comments that NAME those calls. Without this the
    checks match their own documentation and fail against a correct tree --
    which is exactly what happened on the first run.
    """
    return "\n".join(l for l in src.split("\n") if not l.lstrip().startswith("--"))


au = decomment((ROOT / "lib/Audio.lua").read_text())
dr = decomment((ROOT / "lib/Draw.lua").read_text())

failures = []


def check(ok, msg):
    if not ok:
        failures.append(msg)


# 1. snow counts as precipitation on screen
m = re.search(r"local rainOn = \(\(ch\.rain[^\n]*", dr)
check(m is not None, "the rainOn computation in Draw is gone")
if m:
    check("ch.snow" in m.group(0),
          "Draw counts only rain and hail as precipitation on screen -- a "
          "snow-only storm (THUNDERSNOW) reports nothing falling every frame "
          "and has its audio stopped continuously")

# 2. stopping beds must not stop thunder one-shots
check("function Audio.stopBedsOnly" in au,
      "stopBedsOnly is gone -- stopping the bed will stop thunder claps again")
m2 = re.search(r"function Audio\.nudgeFromVisual.*?\nend", au, re.S)
check(m2 is not None, "nudgeFromVisual not found")
if m2:
    check("stopAllBeds" not in m2.group(0),
          "nudgeFromVisual calls stopAllBeds, which also kills the thunder "
          "one-shots -- claps will be cut off mid-sound")
    check("hasLightning" in m2.group(0),
          "nudgeFromVisual ignores hasLightning -- the caller computes it and "
          "it must keep the beds alive while a strike is live")
m3 = re.search(r"function Audio\.stopBedsOnly.*?\nend", au, re.S)
if m3:
    check("_oneshots" not in m3.group(0),
          "stopBedsOnly touches _oneshots -- that is the whole point of it "
          "being separate from stopAllBeds")

# 3. the bed gate must accept snow
check("precipOnScreen" in au or "precipAudible" in au,
      "the audio bed gate requires rain on screen again -- THUNDERSNOW is "
      "snow-only, so its storm bed will start and immediately stop")

# 4. THUNDERSNOW must have NO bed. There is no snow bed in assets/sounds, and
# the `storm` bed is a RAIN recording -- nothing falls as rain in a thundersnow.
# `false` is the explicit-silence sentinel, distinct from nil ("unlisted, infer
# from channels"), which would let the rain fallback take over.
check(re.search(r"THUNDERSNOW\s*=\s*false", au) is not None,
      "THUNDERSNOW has a bed again -- the only beds available are rain "
      "recordings, and nothing falls as rain in a thundersnow")
check("silentBed" in au,
      "the generic rain fallback can override an explicit no-bed weather -- "
      "THUNDERSNOW would get the rain bed anyway")
# ...but thunder and wind must survive, or the weather is silent altogether.
m4 = re.search(r"local function strikeWeatherId.*?\nend", au, re.S)
check(m4 is not None and ("Types.hasLightning" in m4.group(0) or "THUNDERSNOW" in m4.group(0)),
      "THUNDERSNOW no longer qualifies for thunder -- strikeWeatherId must use "
      "the centralized Types lightning authority (or explicitly retain THUNDERSNOW)")

# --- profiles must not contradict the weather catalogue ---------------------
# GALE carries rain = 0.7 in Types.lua but its cloud profile said
# rainIntensity = 0, so the 2D layer rained and the 3D layer produced nothing.
# Any weather with a rain channel must map to a profile that supplies rain.
ca = decomment((ROOT / "lib/voxel_atmos/CinematicAtmos.lua").read_text())
ty = decomment((ROOT / "lib/Types.lua").read_text())
da = decomment((ROOT / "lib/DramalessAtmos.lua").read_text())

# Same split-on-headers approach as the profiles below, and for the same
# reason: a non-greedy dotall match ran past its own entry and reported rain for
# HARSH_SUN and HEATWAVE while MISSING GALE -- the one weather this check
# exists for. Bound each entry by the start of the next.
wstarts = [(m.start(), m.group(1)) for m in
           re.finditer(r'id = "([A-Z_0-9]+)"', ty)]
rain_weathers = set()
for i, (pos, name) in enumerate(wstarts):
    end = wstarts[i + 1][0] if i + 1 < len(wstarts) else len(ty)
    body = ty[pos:end]
    mr = re.search(r"[{,]\s*rain\s*=\s*([0-9.]+)", body)
    if mr and float(mr.group(1)) > 0.05:
        rain_weathers.add(name)

# Parse each profile's OWN body. A dotall regex here runs straight past the
# profile it matched into a later one -- a first version did exactly that and
# reported clear/thunderstorm/snow while missing gale entirely, so the check
# could not fail. Split on the profile headers instead.
prof_rain = {}
starts = [(m.start(), m.group(1)) for m in
          re.finditer(r"^  ([a-z]+)\s*=\s*\{", ca, re.M)]
for i, (pos, name) in enumerate(starts):
    end = starts[i + 1][0] if i + 1 < len(starts) else len(ca)
    body = ca[pos:end]
    mr = re.search(r"rainIntensity=([0-9.]+)", body)
    if mr:
        prof_rain[name] = float(mr.group(1))

for wid in sorted(rain_weathers):
    m7 = re.search(re.escape(wid) + r'\s*=\s*"([a-z]+)"', da)
    if not m7:
        continue
    prof = m7.group(1)
    if prof in prof_rain:
        check(prof_rain[prof] > 0.05,
              f"{wid} has a rain channel but maps to the '{prof}' cloud "
              f"profile, which supplies rainIntensity={prof_rain[prof]} -- the "
              f"2D layer will rain and the 3D layer will produce nothing")

# --- every weather-driver key must be reset each frame ----------------------
# `frame.weather` persists between frames. Keys in BLEND_NUMERIC are rebuilt
# from the profiles every frame; keys outside it are not reset by anything. So a
# driver written as `weather.x = weather.x or 0` and then raised for one weather
# KEEPS that value forever -- hailIntensity did exactly this, and 3D hail fell
# during RAIN, RAIN_HEAVY, PRIMAL_RAIN, SNOW and even CLEAR after one hailstorm.
blend = ca[ca.find("local BLEND_NUMERIC"):ca.find("local BLEND_DEFAULT")]
for key in re.findall(r"weather\.([a-zA-Z]+Intensity)\s*=", ca):
    check('"' + key + '"' in blend,
          f"{key} is a weather driver but is not in BLEND_NUMERIC -- nothing "
          f"resets it between frames, so once one weather raises it the value "
          f"leaks into every later weather")
# ...and the reset must not be the `or 0` idiom, which preserves rather than clears.
mh = re.search(r"weather\.hailIntensity\s*=\s*weather\.hailIntensity\s*or\s*0", ca)
check(mh is None,
      "hailIntensity is reset with `or 0`, which PRESERVES the previous value "
      "instead of clearing it -- that is the leak, not the fix")

# --- the rain-bed fallback must require an actual rain channel --------------
# Every bed in assets/sounds is a rain recording. The fallback exists so an
# UNLISTED rain type still gets rain -- not to hand a rain bed to a weather with
# no rain in it. The BEDS[id] silence check only covers the BASE weather; a
# weather VARIANT has its own id, is not in BEDS, and slipped straight past it,
# which is why THUNDERSNOW started sounding like rain again a minute in.
check("hasRainChannel" in au,
      "the rain-bed fallback no longer requires a rain channel -- any "
      "rain-family weather not listed in BEDS (every variant) will be given the "
      "generic rain bed, including snow-only ones")
# Check the GUARDING LINE itself, not a window before it. A first version
# looked backwards 260 chars from the assignment; `hasRainChannel` sits on the
# enclosing `if` line, which is inside that window either way, so removing the
# condition still passed. Match the condition on its own line.
mf = re.search(r"if \(not bed or not bed\.file\)([^\n]*)then", au)
check(mf is not None, "the rain-bed fallback condition is gone")
if mf:
    check("hasRainChannel" in mf.group(1),
          "the generic rain bed is assigned without checking for a rain "
          "channel -- a snow-only weather will be given rain")

# --- the bed must follow the WEATHER, not the live channel ------------------
# State.channel("rain") is eased between weathers and pushed by the drifting
# front system, so for a snow-only weather it starts at 0 and can creep above
# the threshold a minute in as a neighbouring front bleeds through. Gating the
# rain bed on it means the gate legitimately unlocks partway through the
# weather -- silent at first, raining later, which is exactly what was
# reported. The definition's own rain channel is static and is what the bed
# should follow.
check("defRain" in au,
      "the rain-bed gate reads the live rain channel instead of the weather "
      "definition's own -- a drifting front will unlock a rain bed partway "
      "through a snow-only weather")
mdr = re.search(r"local hasRainChannel\b(.{0,400})", au, re.S)
check(mdr is not None and "defRain" in mdr.group(1),
      "hasRainChannel is computed from the live channel again")

# --- dry-thunder weathers must not use the 60-second roll -------------------
# thunder_roll is a SIXTY SECOND sample (1.88 MB vs thunder_clap's 224 KB) --
# a sustained rumble with storm ambience under it. Layered over a rain bed that
# is correct; with no bed beneath it, it IS the rain sound. It is picked at
# random, so on THUNDERSNOW the second strike could start a minute of rain-like
# noise. One-shots are deliberately never stopped by the bed logic, so it runs
# its full length.
check("THUNDER_DRY" in au,
      "the dry-thunder sound list is gone -- a snow-only storm will pick the "
      "60-second roll again, which sounds like rain with no bed under it")
mt = re.search(r"local names = ([^\n]*)", au)
check(mt is not None and "THUNDER_DRY" in mt.group(1),
      "thunder sound selection ignores THUNDER_DRY")
# and the roll must still be available to weathers that DO have rain
check(re.search(r'Audio\.THUNDER = \{[^}]*thunder_roll', au) is not None,
      "thunder_roll was removed entirely -- rain storms should keep it, it is "
      "only wrong where there is no rain bed to sit under")

if failures:
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)
print("PASS thunder/snow audio")
