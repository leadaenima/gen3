-- Weather FX 8.1.91: current Battle Art compatibility + compiled relief ownership.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local captured=nil
local CW={setVoxelWaterHost=function(c)captured=c end}
local V={mod={},require=function(n) if n=='ConnectedWater' then return CW end error(n,0) end}
local A=assert(loadfile(ROOT..'lib/DramalessAtmos.lua'))(V)
local W={WAVE_TRAINS={{.15,.06,1,.6}},WAVE_SWELL={.03,.01,.5,.3},WAVE_BEND={-.01,.03,.3,1},
 _waveTime=function()return 0 end,_trainSource=function()return 'public-current' end,
 begin=function()return true end,draw=function()end,finish=function()end}
local L={require=function(n) if n=='Water' then return W elseif n=='WorldUnderlay' then return {RANGE=32768,draw=function()end} end error(n,0) end}
local c=A._publishWaterHostCaps('BATTLE_ART_VOXEL_FORK',L,{drawWater=function()end})
ck(c.publicBattleArtWater and not c.voxelNexusWater,'current Battle Art _trainSource export is not mistaken for Voxel Nexus')
local tide=function()return 1 end
L.realisticWorld={WaterEngine={tideOffset=tide}}
local n=A._publishWaterHostCaps('BATTLE_ART_VOXEL_FORK',L,{drawWater=function()end})
ck(n.voxelNexusWater and n.hostWaterModelTide and not n.publicBattleArtWater,'Nexus-only WaterEngine tide seam remains correctly classified')
local src=assert(io.open(ROOT..'lib/voxel_atmos/ConnectedWater3D.lua','rb')):read('*a')
ck(src:find('local reliefMode=physical and "weather-fx" or "host"',1,true)~=nil,'renderer tracks physical-vs-host relief ownership as an explicit mode')
ck(src:find('if changed and type(Water.invalidate)=="function" then hostTry(Water.invalidate) end',1,true)~=nil,'host Water shader is invalidated exactly when compiled relief ownership changes')
ck(src:find('Water.WAVE_HEIGHT=physical and 0 or waveH',1,true)~=nil,'Weather FX physical ownership forces host geometric relief height to zero')
print(('8.1.91 current Battle Art water: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
