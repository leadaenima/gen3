#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
a=(R/'lib/DramalessAtmos.lua').read_text(); s=(R/'lib/WeatherShadowMap.lua').read_text(); run=(R/'tools/run_all.py').read_text()
checks=[]
def ck(v,m): checks.append((bool(v),m))
ck('V.require("WeatherShadowMap")' in a and 'WXShadow.install(hostLib,ShadowMap)' in a,'multi-host bridge installs Weather-owned map')
ck('_wxFineMotionWrapped' not in a and '_wxContinuousProjectionWrapped' not in a,'old host wrappers removed')
ck('uniform mat4 model;' in s and 'lightVP * (model * VertexPosition)' in s,'writer applies host caster model transform')
ck('vec4(floor(d) / 255.0, fract(d), sprite, 1.0)' in s,'packed RG depth plus caster-class blue channel preserved')
ck('Intentionally NO light-space floor(l/texel)' in s,'rotating-light texel snap absent')
ck('_wxCameraAnchorStep=1/16' in s,'independent 1/16 camera anchor declared')
ck('caster-endpoint-drift' in s and 'return 0.04' in s and 'return 0.07' in s and 'return 0.12' in s,'bounded drift recast policy')
ck('available()' in s and 'return shader() ~= nil' in s,'availability does not request a shadow canvas')
ck('Grow only during a live session' in s and 'state.res > wanted' in s,'resolution grow-only hysteresis')
ck('depth24stencil8' in s and 'depth32f' in s and 'depth16' in s and 'depthstencil=state.depth' in s,'explicit depth ladder with attachment')
ck('state.committedKX' in s and 'activeDirection' in s,'map reuse keeps committed light direction')
ck('weather_shadow_engine_test.lua' in run and 'shadow_projection_monotonic_test.lua' in run,'owned-shadow executable tests wired into release runner')
failed=[m for v,m in checks if not v]
for v,m in checks: print(('PASS' if v else 'FAIL'),m)
print(f'8.1.19 shadow engine contract: {len(checks)-len(failed)}/{len(checks)} passed')
sys.exit(1 if failed else 0)
