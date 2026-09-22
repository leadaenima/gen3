local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local p,f=0,0;local function ck(v,m) if v then p=p+1;print('PASS '..m) else f=f+1;print('FAIL '..m) end end
local list={{id=1,x=40,z=40,age=30,formation=8,stage='roam',ropeAge=0,ropeFor=12,spin=4.6,waterBlend=1,groundY=0}}
local mods={Tornado={renderState=function() return list end,cloudBase=function() return 180 end},CinematicAtmos={precipitationDeck=function() return 177 end},WeatherState={elapsed=5}}
local V={require=function(n) return mods[n] end};local submitted=0
love={graphics={newShader=function() return {send=function() end} end,newMesh=function(fmt,cap,mode,use) return {setVertices=function(self,v,s,n) submitted=n or #v end,setDrawRange=function() end} end,setBlendMode=function() end,setDepthMode=function() end,setShader=function() end,setColor=function() end,draw=function() end}}
local T3=assert(loadfile(ROOT..'lib/voxel_atmos/Tornado3D.lua'))(V);local Vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},eye={0,20,-40},beginEffect=function() return false end,endEffect=function() end}
ck(T3.draw(Vox)==true,'waterspout submits 3D geometry');local n,l=T3.geometryStatus();ck(l.waterSpray==true and l.groundSkirt==false,'waterspout uses water spray layer and suppresses land dirt skirt');ck(n>2000 and n<8000,'waterspout geometry remains dense but bounded')
list[1].waterBlend=0;ck(T3.draw(Vox)==true,'land tornado submits 3D geometry');local n2,l2=T3.geometryStatus();ck(l2.waterSpray==false and l2.groundSkirt==true,'land tornado restores dirt skirt and removes water spray layer')
print(('waterspout presentation 8.1.58: %d passed, %d failed'):format(p,f));os.exit(f==0 and 0 or 1)
