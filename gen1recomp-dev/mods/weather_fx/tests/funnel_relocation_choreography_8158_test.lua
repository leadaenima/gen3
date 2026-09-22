local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local p,f=0,0;local function ck(v,m) if v then p=p+1;print('PASS '..m) else f=f+1;print('FAIL '..m) end end
local black,ell=0,0
love={math={random=function() return .42 end},graphics={getColor=function() return 1,1,1,1 end,getBlendMode=function() return 'alpha','alphamultiply' end,setBlendMode=function() end,setColor=function() end,rectangle=function(mode,x,y,w,h) if mode=='fill' and x==0 and y==0 and w==640 and h==480 then black=black+1 end end,ellipse=function() ell=ell+1 end}}
local F=assert(loadfile(ROOT..'lib/Funnel.lua'))({});local events={};local pos={sweepout={},sweepin={}}
local function ev(s) events[#events+1]=s end
F.start(2.5,function() ev('done') end,{mode='relocate2d',waterTwister=true,onCapture=function() ev('capture') end,onPickup=function() ev('pickup') end,onDrop=function() ev('drop') end,playerDrawer=function(x) local q=pos[F.phaseName()];if q then q[#q+1]=x end end})
local seen={}
for _=1,80 do local ph=F.phaseName();seen[ph]=true;F.draw(0,0,640,480,4);F.update(.1);if F.phaseName()=='blackout' then break end end
ck(seen.approach and seen.sweepout and F.phaseName()=='blackout','approach -> sweepout -> blackout')
ck(events[1]=='capture' and events[2]=='pickup','capture precedes transfer callback')
for _=1,20 do F.update(.1);F.draw(0,0,640,480,4) end
ck(F.phaseName()=='blackout' and black>0,'blackout holds until destination proof')
ck(#pos.sweepout>2 and pos.sweepout[#pos.sweepout]>pos.sweepout[1],'player proxy sweeps off to right')
F.relocationArrived()
for _=1,100 do if not F.active then break end;F.draw(0,0,640,480,4);F.update(.1) end
ck(#pos.sweepin>2 and pos.sweepin[#pos.sweepin]>pos.sweepin[1],'player proxy enters from left')
ck(table.concat(events,',')=='capture,pickup,drop,done','drop occurs before tornado exit completion')
ck(ell>=3,'water twister renders surface spray rings')
print(('funnel relocation choreography 8.1.58: %d passed, %d failed'):format(p,f));os.exit(f==0 and 0 or 1)
