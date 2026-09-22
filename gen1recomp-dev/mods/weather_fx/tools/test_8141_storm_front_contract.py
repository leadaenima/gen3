#!/usr/bin/env python3
from pathlib import Path
import re,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
sc=(R/'lib/StormCells.lua').read_text();dw=(R/'lib/DistantWeather.lua').read_text();ca=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text();ws=(R/'lib/WeatherState.lua').read_text()
for cls in ('cell','regional','broad','synoptic'): ck(('"'+cls+'"') in sc,f'{cls} storm-front class present')
ck('local edgeGap=420+rand()*720' in sc,'spawn separation is solved from leading edge')
ck('local edgeTravel=edgeGap/math.max(.5,speed)' in sc and 'edgeTravel/.56' in sc,'lifetime protects useful leading-edge arrival')
ck('maxShift=dt*math.max(7.0,(tonumber(c.speed) or 1)*2.35)' in sc,'player-following interception is bounded by finite world speed')
ck('if not c.reachedTarget and metric<=lifeRadius*.98' in sc,'contact is footprint-based rather than center-based')
ck('local speed=clamp(speedBase*(speedMul or 1),.75,4.10)' in sc,'spawn speed capped at slow interceptable maximum')
ck('local nearFade=1-.48*smooth(penetration)' in dw,'remote cloud handoff retains >=52% floor after contact')
ck('(edge>0) and 1' in dw and 'shaftHandoff' in dw,'no approach fade before physical contact')
ck('q.bankX' in dw and 'q.bankZ' in dw,'nearest physical front edge exported')
ck('local anchorX=tonumber(a.bankX) or tonumber(a.x)' in ca,'cloud-bank renderer consumes leading-edge anchor')
ck('local physicalCross=max(tonumber(a.rz) or 220,180)' in ca,'render width derives from physical cross-front radius')
ck('_cellCloudWeather' in ws and 'spatialCloud' in ws,'local cloud authority remains available for continuous handoff')
failed=sum(not v for v,_ in checks);print(f'8.1.41 storm-front source contract: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
