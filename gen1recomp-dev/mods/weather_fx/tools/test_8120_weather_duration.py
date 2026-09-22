#!/usr/bin/env python3
from pathlib import Path
import re, sys
R=Path(__file__).resolve().parents[1]
settings=(R/'lib/Settings.lua').read_text()
state=(R/'lib/WeatherState.lua').read_text()
fronts=(R/'lib/Fronts.lua').read_text()
checks=[]
def ck(v,m): checks.append((bool(v),m))

# Exact requested menu surface.
row=re.search(r'key = "speed", label = "WEATHER DURATION".*?\n  },', settings, re.S)
ck(row is not None, 'WEATHER DURATION row exists')
rb=row.group(0) if row else ''
for label,val in [('NORMAL','normal'),('2X','2x'),('4X','4x'),('10X','10x'),('20X','20x')]:
    ck(f'{{ "{label}", "{val}" }}' in rb, f'choice {label} is exposed')
ck('does not speed up the game, particles, wind, clouds, or weather transitions' in rb,
   'menu help explicitly limits setting to weather lifetime only')

# Exact lifetime multipliers: N× means N times faster expiry, not faster particles.
for val,want in [('normal','1.0'),('2x','0.50'),('4x','0.25'),('10x','0.10'),('20x','0.05')]:
    if val=='normal': pat=r'normal\s*=\s*1\.0'
    else: pat=rf'\["{re.escape(val)}"\]\s*=\s*{re.escape(want)}'
    ck(re.search(pat, settings) is not None, f'{val} lifetime multiplier = {want}')

# Transition animation speed is completely independent of the duration setting.
ck('Settings.get("speed")' not in state, 'WeatherState transition path never branches on duration setting')
soft_block=re.search(r'local function beginSoftWeather\(toId\).*?\n  end\n\n  -- Menu pin', state, re.S)
soft=soft_block.group(0) if soft_block else ''
ck('Settings.speedScale' not in soft and 'weatherLifetimeScale' not in soft,
   'soft weather transition duration is not scaled by WEATHER DURATION')

# Only dwell scheduling is allowed to consume the scalar outside Settings itself.
users=[]
for p in (R/'lib').rglob('*.lua'):
    if p.name=='Settings.lua': continue
    txt=p.read_text(errors='replace')
    if 'Settings.speedScale()' in txt or 'Settings.weatherLifetimeScale()' in txt:
        users.append(p.relative_to(R).as_posix())
ck(set(users) <= {'lib/WeatherState.lua'}, 'lifetime scalar is not consumed by particle/cloud/wind/audio render modules')
ck('seconds * Settings.speedScale()' in state, 'visible weather dwell uses lifetime scalar')
ck('Fronts.update(dt, Settings.speedScale())' in state, 'regional front dwell receives lifetime scalar')
ck('State.left = State.left * ratio' in state, 'current visible weather remaining lifetime rescales immediately')
ck('Fronts.rescaleRemaining(priorLifetimeScale, lifetimeScale)' in state,
   'existing regional front remaining lifetimes rescale immediately')
ck('st.left = st.left * ratio' in fronts, 'regional remaining lifetimes rescale without changing simulation dt')
ck('dt = dt * speedScale' not in fronts and 'dt*speedScale' not in fronts,
   'front simulation time step is not accelerated')

failed=[m for ok,m in checks if not ok]
for ok,m in checks: print(('PASS' if ok else 'FAIL'), m)
print(f'8.1.20 weather-duration contract: {len(checks)-len(failed)}/{len(checks)} passed')
sys.exit(1 if failed else 0)
