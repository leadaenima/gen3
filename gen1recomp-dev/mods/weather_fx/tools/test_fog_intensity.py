#!/usr/bin/env python3
from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[1]
failed = 0
def ok(c, m):
    global failed
    print(("PASS" if c else "FAIL"), m)
    if not c: failed += 1
s = (ROOT/"lib/Settings.lua").read_text()
ws = (ROOT/"lib/WeatherState.lua").read_text()
ok('"off"' in s and '"10"' in s, "OFF and 10%")
for pct in range(50, 501, 50):
    ok(f'"{pct}"' in s or f'"{pct}%"' in s, f"{pct}% choice")
ok(re.search(r'\["500"\]\s*=\s*20', s) is not None, "500% → 20x")
ok("math.min(20.0" in ws or "min(20.0" in ws, "channel cap 20")
print("RESULT", "OK" if not failed else "FAIL", failed)
sys.exit(1 if failed else 0)
