local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local p,f=0,0;local function ck(v,m)if v then p=p+1;print('PASS '..m)else f=f+1;print('FAIL '..m)end end
local hydrated=true
local map={id='ROUTE_4',widthCells=4,heightCells=4,cellTile=function(self,x,z)return (hydrated and x==1 and z==2) and 54 or 57 end,tileAt=function(self,tx,tz)return self:cellTile(math.floor(tx/2),math.floor(tz/2)) end,isWaterCell=function()return false end}
local VS={groundAt=function(m,cx,cz) if cx==1 and cz==2 then return 6 end return 0 end}
local TS={forMap=function()return {[54]={class='ledge',art='top',h=6,authored=true},[57]={class='ground',art='flat',h=0,authored=false}} end,at=function(m,shapes,tile) if tile==54 then return shapes[57] end return shapes[tile] end}
local SP=assert(loadfile(ROOT..'lib/SnowPack.lua'))({require=function()error('optional')end})
local ctx=SP.beginFrame({map=map,player={cellX=1,cellY=1}},12.8,VS,TS,nil)
ck(math.abs((ctx.fallbackGroundY or 99)-0)<1e-6,'camera-height fallback is replaced by exact player voxel floor')
local gy,gk=SP.surfaceAt(ctx,24,24)
ck(math.abs(gy-0)<1e-6 and gk=='ground','ordinary ground resolves to the real zero-height voxel floor')
local ly,lk=SP.surfaceAt(ctx,24,40)
ck(math.abs(ly-6)<1e-6 and lk=='raised','authored Route-style ledge resolves to its real raised top surface')
ck(TS.at(map,TS.forMap(map),54,2,4).class=='ground' and ly==6 and lk=='raised','authored ledge pin outranks a host TileShape.at flattening wrapper')
-- Predictive-map regression: the same map object first answers placeholder
-- ground, then hydrates to the authored ledge tile. The shape cache must follow
-- the tile id instead of preserving stale ground forever.
hydrated=false;ctx=SP.beginFrame({map=map,player={cellX=1,cellY=1}},12.8,VS,TS,nil)
local py,pk=SP.surfaceAt(ctx,24,40)
ck(py==0 and pk=='ground','predictive placeholder surface initially resolves as ground')
hydrated=true;ctx=SP.beginFrame({map=map,player={cellX=1,cellY=1}},12.8,VS,TS,nil)
local hy,hk=SP.surfaceAt(ctx,24,40)
ck(math.abs(hy-6)<1e-6 and hk=='raised','same live map object refreshes stale shape cache when ledge tile hydrates')

-- Live Route 4 also mixes ground and ledge subtiles inside one 16x16 cell.
-- Six ordinary ground patches must not starve the first real ledge impact.
local mixed={id='ROUTE_4_MIXED',widthCells=4,heightCells=4,
  cellTile=function(self,x,z) return (x==1 and z==2) and 54 or 57 end,
  tileAt=function(self,tx,tz) if math.floor(tx/2)==1 and math.floor(tz/2)==2 and (tz%2)==1 then return 54 end return 57 end,
  isWaterCell=function() return false end}
local mts={forMap=function() return {[54]={class='ledge',art='top',h=6,authored=true},[57]={class='ground',art='flat',h=0,authored=false}} end,
  at=function(m,shapes,tile) return shapes[tile] end}
local mctx=SP.beginFrame({map=mixed,player={cellX=1,cellY=1}},0,VS,mts,nil)
local groundPts={{17,33},{21,33},{25,33},{29,33},{19,37},{27,37}}
for _,q in ipairs(groundPts) do SP.deposit(mctx,q[1],q[2],nil,1.0) end
local mc,mp=SP.deposit(mctx,24,44,nil,1.0)
ck(mp~=nil and mp.kind=='raised' and math.abs((mp.baseY or 0)-6)<1e-6,'full mixed cell recycles duplicate ground patch so ledge keeps a repaint representative')

print(('snow live surface alignment 8.1.67: %d passed, %d failed'):format(p,f));os.exit(f==0 and 0 or 1)
