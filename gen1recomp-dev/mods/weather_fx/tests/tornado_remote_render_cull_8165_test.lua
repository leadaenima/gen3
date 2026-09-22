local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,m) if v then pass=pass+1;print('PASS '..m) else fail=fail+1;print('FAIL '..m) end end
local list={{id=1,x=40,z=40,age=30,formation=8,stage='roam',ropeAge=0,ropeFor=12,spin=4.6,waterBlend=0,groundY=0,offscreen=true}}
local mods={Tornado={renderState=function() return list end,cloudBase=function() return 180 end},CinematicAtmos={precipitationDeck=function() return 177 end},WeatherState={elapsed=5}}
local V={require=function(n) return mods[n] end}
local submitted=0
love={graphics={newShader=function() return {send=function() end} end,newMesh=function(fmt,cap,mode,use) return {setVertices=function(self,v,s,n) submitted=n or #v end,setDrawRange=function() end} end,setBlendMode=function() end,setDepthMode=function() end,setShader=function() end,setColor=function() end,draw=function() end}}
local T3=assert(loadfile(ROOT..'lib/voxel_atmos/Tornado3D.lua'))(V)
local Vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},eye={0,20,-40},beginEffect=function() return false end,endEffect=function() end}
ck(T3.draw(Vox)==false,'offscreen tornado submits no invisible 3D geometry')
local n=T3.geometryStatus();ck(n==0,'offscreen tornado consumes zero tornado mesh vertices')
list[1].offscreen=false
ck(T3.draw(Vox)==true,'same tornado renders immediately when it re-enters live map set')
local n2=T3.geometryStatus();ck(n2>2000,'visible re-entry restores full procedural funnel geometry')
print(('tornado remote render cull 8.1.65: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
