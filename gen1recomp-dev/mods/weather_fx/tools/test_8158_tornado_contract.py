#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1];t=(R/'lib/Tornado.lua').read_text();f=(R/'lib/Funnel.lua').read_text();r=(R/'lib/voxel_atmos/Tornado3D.lua').read_text();c=[]
def ck(v,m): c.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
ck('derivedConnectedLanding' in t and 'source="connection"' in t,'visited-map connection landing fallback present')
ck('onDone=finished' in t and 'mapId==r.destination' in t,'warp callback plus destination-map proof present')
ck('r.stage="depart"' in t and 'r.stage="arrival"' in t,'3D visible departure and arrival stages present')
ck('tryTouchCarry(r,px,pz,mapId' in t and 'contactCarry' in t,'ordinary 3D funnel direct-contact pickup present')
ck('mode="relocate2d"' in t and 'legacyLockCamera' in t and 'legacyHidePlayer' in t,'2D camera/player ownership present')
ck('Funnel.relocationArrived' in t and 'ph=="blackout"' in t,'2D blackout waits for destination proof')
ck('playerDrawer' in f and 'sweepout' in f and 'sweepin' in f,'2D player sweep-out/sweep-in choreography present')
ck('drawBlackoutOverlay' in f and 'Funnel.drawBlackoutOverlay' in (R/'main.lua').read_text(),'2D blackout is reasserted at post-HUD framebuffer seam')
ck('waterSprayBase' in r and 'waterSpray=true' in r,'3D explicit waterspout contact layer present')
ck('map.isWaterCell' in t and 'targetWater' in t,'live map water authority drives waterspout state')
print(f'8.1.58 tornado contract: {sum(c)}/{len(c)} passed');sys.exit(0 if all(c) else 1)
