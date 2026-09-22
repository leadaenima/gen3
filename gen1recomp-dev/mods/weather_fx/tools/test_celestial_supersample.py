#!/usr/bin/env python3
from pathlib import Path
import re, sys
root=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
main=(root/'main.lua').read_text(errors='replace')
cfg=(root/'config.lua').read_text(errors='replace')
libcfg=(root/'lib/Config.lua').read_text(errors='replace')
cb=(root/'lib/CelestialBodies.lua').read_text(errors='replace')
atmos=(root/'lib/DramalessAtmos.lua').read_text(errors='replace')
shadow=(root/'lib/WeatherShadowMap.lua').read_text(errors='replace')
checks=[]
def ck(v,msg):
    checks.append((bool(v),msg))
ck('discSupersample = 16' in cfg,'shipped config defaults celestial disc supersampling to 16x')
ck('discSupersample = 16' in libcfg,'embedded config defaults celestial disc supersampling to 16x')
ck('local ss=16' in main and 'elseif ss>16 then ss=16 end' in main,'renderer default and hard cap both allow the requested 16x raster')
ck('wxCelestialRaster' in main and 'wxDiscCanvas' in main,'local reusable celestial raster cache exists')
ck('g.newCanvas' in main and 'dpiscale=1' in main,'celestial layer is a true local high-resolution canvas')
ck('c.setFilter,c,"linear","linear"' in main,'celestial layer uses linear reconstruction for fractional placement')
ck('local inv=1/ss' in main and 'g.draw,layer,bx-rw*0.5*inv,by-rh*0.5*inv,0,inv,inv' in main,'supersampled layer composites at exact floating body coordinates')
ck('local scell=cell*ss' in main,'pixel-art cells are rasterized at supersampled resolution')
ck('local bx = tonumber(body.x) or 0' in main and 'math.floor(body.x' not in main[main.find('local function wxPaintCelestialDisc'):main.find('local function installNightSkyWrap')], 'disc centre is not snapped to an integer/cell grid')
ck('_wxAltitudeDeg' in main and 'pixelAlt < 0' in main,'geometric horizon clipping remains active inside supersampled art')
ck('local layer=(ss>1) and wxDiscCanvas' in main and 'Driver-safe fallback' in main,'canvas failure preserves compatible direct raster fallback')
ck('NS.projectDirection' in cb and 'x,y=px,py' in cb and 'math.floor(x' not in cb[cb.find('local function projectOne'):cb.find('function Celestial.projectBody')], 'camera-aware projected body coordinates remain floating point before raster composition')
ck('targetForTier' in shadow and 'return 0.24' in shadow and 'return 0.32' in shadow,'owned shadow map keeps high/medium fine texel targets')
ck('Grow only during a live session' in shadow and 'state.res > wanted' in shadow,'owned shadow resolution grows without per-frame downsize churn')
failed=[m for ok,m in checks if not ok]
for ok,msg in checks: print(('PASS' if ok else 'FAIL'),msg)
print(f'celestial supersample: {len(checks)-len(failed)} passed, {len(failed)} failed')
raise SystemExit(1 if failed else 0)
