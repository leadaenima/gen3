#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
failed = 0
def ok(c, m):
    global failed
    print(("PASS" if c else "FAIL"), m)
    if not c: failed += 1

h = (ROOT/"lib/Harden.lua").read_text()
ok("function H.call" in h, "Harden.call")
ok("function H.require" in h, "Harden.require")
ok("function H.zeroChannels" in h, "Harden.zeroChannels")

st = (ROOT/"lib/Settings.lua").read_text()
ok("minimal schema" in st or "mod page is never empty" in st, "settings fallback schema")
ok("rebuildValid" in st, "rebuildValid")
ok("Settings.define" in st, "Settings.define")

ws = (ROOT/"lib/WeatherState.lua").read_text()
ok("type(State.ch) ~= \"table\"" in ws, "State.ch guard")
ok("beginSoftWeather" in ws, "soft transitions")

main = (ROOT/"main.lua").read_text()
ok(("EngineRuntime.update" in main and "if not okRuntime then" in main) or "State.update failed" in main or "pcall(function()" in main, "safe State.update")
ok("ensureOptions" in main or "Settings.define" in main, "options ensure")

print("RESULT", "OK" if not failed else "FAIL", failed)
sys.exit(1 if failed else 0)
