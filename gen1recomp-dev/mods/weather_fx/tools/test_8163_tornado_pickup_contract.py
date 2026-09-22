#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1];s=(R/'lib/Tornado.lua').read_text();checks=[]
def ck(v,m): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
ck('if strict3d() then update3d(dt) else update2d(dt) end' in s,'2D and 3D tornado simulations are mutually exclusive')
ck('local e={destination=target' in s and 'T._legacyCarry=e;lockPlayerControls()' in s,'2D successful carry locks controls before screen sweep')
ck('OW.handleInput=guarded' in s and 'owner.isCarrying()' in s,'native overworld input choke point is guarded during carry')
ck('p.inputLocked=true' in s,'engine player native inputLocked asserted')
ck('if not r.seeker and tryTouchCarry' in s,'ordinary 3D walk-in contact remains independent from seeker navigation')
ck('r.contactCarry=(reason=="touch")' in s,'ordinary contact remains separately identified')
ck('local pickupRadius=math.max(30,tonumber(cfg().touchRadius) or 14)' in s,'seeker pickup matches visible minimum 30px footprint')
ck('r.speed=math.max(r.speed,18+math.min(12,r.seekAge*1.0))' in s,'committed seeker has explicit closing speed')
ck('dt*(r.seeker and 4.0 or .42)' in s,'committed seeker turns aggressively toward live player')
ck('q.solid and not q.water and not r.seeker' in s,'only ordinary roamers use static scenery deflection')
ck('r.seekSceneryCrossings' in s,'seeker scenery traversal is auditable')
ck('beginCarry(r,px,pz,"seeker")' in s,'seeker enters shared pickup/carry state machine')
ck('lockPlayerControls()\n  r.carryAge=' in s,'3D carry reasserts control ownership every update')
ck('restoreControlLock();startRope' in s or 'restoreControlLock();T.lastReason' in s,'landing/return paths restore prior control state')
print(f'8.1.63 tornado pickup contract: {sum(checks)}/{len(checks)} passed')
sys.exit(0 if all(checks) else 1)
