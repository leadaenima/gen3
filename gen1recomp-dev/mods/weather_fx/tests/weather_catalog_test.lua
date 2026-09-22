local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end end
local T=assert(loadfile('lib/Types.lua'))({})
check(#T.list==29,'catalog contains exactly 29 shipped weather types after RAVE removal')
local seen={}
for _,d in ipairs(T.list) do
  check(type(d.id)=='string' and d.id~='' and not seen[d.id],'weather id is nonempty and unique: '..tostring(d.id))
  seen[d.id]=true
  check(T.get(d.id)==d,'weather lookup resolves canonical definition: '..d.id)
  if d.id~='CLEAR' then
    local visual=false
    for _,v in pairs(d.ch or {}) do if type(v)=='number' and v>0 then visual=true break end end
    check(visual,'non-clear weather has a visible recipe: '..d.id)
    check(type(d.battle)=='string' and d.battle~='','non-clear weather maps into battle field weather: '..d.id)
    local rev=T.forBattleWeather(d.battle)
    check(rev and rev.id,'battle weather reverse lookup exists: '..d.id)
  end
end
local pins={}
for _,id in ipairs(T.PINNED) do
  check(seen[id] and not pins[id],'pinned weather row is valid and unique: '..id)
  pins[id]=true
end
check(#T.PINNED==28 and pins.MIST==nil and pins.RAVE==nil,'28 direct pins ship; removed RAVE is absent and MIST remains AUTO-only')
check(T.get('NO_SUCH_WEATHER').id=='CLEAR','unknown weather safely degrades to CLEAR')
print(('weather catalog: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
