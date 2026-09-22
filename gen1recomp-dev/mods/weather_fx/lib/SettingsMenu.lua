local V = ...
local mod = V.mod
local Settings = V.require("Settings")

local Menu = { installed=false }
local ROOT_ID = "WeatherFXSettingsRoot"
local GROUP_PREFIX = "WeatherFXSettingsGroup_"

local function displayFor(row, value)
  value = value == nil and row.default or value
  if row and row.key=="quality" and value=="auto" then
    local ok,Q=pcall(V.require,"Quality")
    if ok and Q and Q.tier then local ok2,t=pcall(Q.tier); if ok2 and t then return "AUTO / "..tostring(t):upper() end end
  end
  -- FOLLOW QUALITY rows show their *effective* live value instead of looking
  -- permanently unchanged when the master preset moves. This makes the preset
  -- relationship obvious to players without destructively overwriting their
  -- advanced overrides.
  if row and value=="quality" then
    local ok,Q=pcall(V.require,"Quality")
    if ok and Q then
      if row.key=="textureDetail" and Q.textureScale then
        local ok2,v=pcall(Q.textureScale);if ok2 and tonumber(v) then return ("FOLLOW / %d%%"):format(math.floor(v*100+.5)) end
      elseif row.key=="reflectionDetail" and Q.reflectionMode then
        local ok2,v=pcall(Q.reflectionMode);if ok2 and v then return "FOLLOW / "..tostring(v):upper() end
      elseif row.key=="effectDistance" and Q.effectDistanceScale then
        local ok2,v=pcall(Q.effectDistanceScale);if ok2 and tonumber(v) then return ("FOLLOW / %d%%"):format(math.floor(v*100+.5)) end
      elseif row.key=="simulationDetail" and Q.simulationIntervalMultiplier then
        local ok2,v=pcall(Q.simulationIntervalMultiplier);if ok2 and tonumber(v) then return ("FOLLOW / %.2fX"):format(v) end
      end
    end
  end
  for _,c in ipairs(row.choices or {}) do
    if c[2] == value or tostring(c[2]) == tostring(value) then return tostring(c[1]) end
  end
  return tostring(value or "-"):upper()
end

local function choiceIndex(row, value)
  local choices=row.choices or {}
  for i,c in ipairs(choices) do
    if c[2]==value or tostring(c[2])==tostring(value) then return i end
  end
  return 1
end

-- Public mod.options currently has define/get but no guaranteed set(). The
-- engine save table is the documented backing store, so the custom in-game
-- submenu writes that same table and then dispatches the exact live-change path
-- Settings already uses. Older/forked hosts with options:set still use it.
local function persist(game,key,value)
  local wrote=false
  pcall(function()
    if mod.options and type(mod.options.set)=="function" then
      mod.options:set(key,value); wrote=true
    end
  end)
  pcall(function()
    local opts=game and game.save and game.save.options
    if not opts then
      local ok,G=pcall(require,"src.core.Game")
      opts=ok and G and G.save and G.save.options or nil
    end
    if opts then
      opts.modOptions=opts.modOptions or {}
      opts.modOptions[mod.id]=opts.modOptions[mod.id] or {}
      opts.modOptions[mod.id][key]=value
      wrote=true
    end
  end)
  pcall(function()
    -- Some custom screen hosts pass a lightweight UI/game facade whose `mods`
    -- field is absent even though src.core.Game owns the real loader. Mirror
    -- both objects when they differ. Otherwise the custom OPTIONS submenu can
    -- update the save/runtime value while Mod Manager's loader cache remains
    -- stale; merely opening Mod Manager then refreshes that cache and makes the
    -- setting appear to start working.
    local loaders={}
    if game and game.mods then loaders[#loaders+1]=game.mods end
    local okG,G=pcall(require,"src.core.Game")
    if okG and G and G.mods and G.mods~=(game and game.mods) then loaders[#loaders+1]=G.mods end
    for _,loader in ipairs(loaders) do
      loader.modOptions=loader.modOptions or {}
      loader.modOptions[mod.id]=loader.modOptions[mod.id] or {}
      loader.modOptions[mod.id][key]=value
      -- Current builds may keep the authoritative cache one level deeper on
      -- the loader object. Mirror both shapes so mod.options:get(), the manager
      -- page and this custom OPTIONS submenu cannot disagree until restart.
      if loader.loader then
        loader.loader.modOptions=loader.loader.modOptions or {}
        loader.loader.modOptions[mod.id]=loader.loader.modOptions[mod.id] or {}
        loader.loader.modOptions[mod.id][key]=value
      end
    end
  end)
  -- Update Weather FX synchronously. Then publish through the loader event bus
  -- when a host exposes it so other option observers see the same live change.
  Settings.handleOptionChanged({mod=mod.id,key=key,value=value})
  pcall(function()
    local buses={game and game.mods and game.mods.events,game and game.mods and game.mods.loader and game.mods.loader.events}
    for _,bus in ipairs(buses) do
      if bus and type(bus.emit)=="function" then bus:emit("mod.options_changed",{mod=mod.id,key=key,value=value}) end
    end
  end)
  return wrote and Settings.get(key)==value
end

function Menu.applyOption(game,key,value)
  local row=Settings.row(key)
  if not row then return false,"unknown setting" end
  local found=false
  for _,c in ipairs(row.choices or {}) do if c[2]==value or tostring(c[2])==tostring(value) then found=true;value=c[2];break end end
  if not found then return false,"invalid value" end
  return persist(game,key,value)
end

local function stepRow(row,game,dir)
  local choices=row.choices or {}; if #choices==0 then return false end
  local cur=Settings.get(row.key)
  local i=choiceIndex(row,cur)
  dir=(dir and dir<0) and -1 or 1
  i=((i-1+dir)%#choices)+1
  persist(game,row.key,choices[i][2])
  return true
end

local function makeSettingRows(group)
  local rows={}
  for _,key in ipairs(group.keys or {}) do
    local row=Settings.row(key)
    if row and row.choices and #row.choices>0 then
      rows[#rows+1]={
        id=mod.id..":"..key,
        label=row.label,
        help=row.help,
        -- UI skins differ on which field they read for the always-visible
        -- explanation panel. Publish the same player description through all
        -- established names so a premium skin never falls back to generic copy.
        description=row.help,
        desc=row.help,
        value=function() return displayFor(row,Settings.get(row.key)) end,
        step=function(game,dir) return stepRow(row,game,dir) end,
      }
    end
  end
  return rows
end

local function drawHelp(screen)
  local row=screen.helpRow; if not row then return false end
  local okFont,Font=pcall(require,"src.render.Font")
  local okTB,TextBox=pcall(require,"src.render.TextBox")
  if not (okFont and Font and okTB and TextBox and love and love.graphics) then return false end
  love.graphics.setColor(1,1,1,1); love.graphics.rectangle("fill",0,0,160,144)
  Font.drawBox(0,1,20,3)
  love.graphics.setColor(0,0,0,1); Font.draw(tostring(row.label or "SETTING"),8,16)
  Font.drawBox(0,4,20,13)
  love.graphics.setColor(0,0,0,1)
  local pages=TextBox.paginate((row.help or "No description available."):gsub("\v","\n"),17)
  local pageCount=math.max(1,#pages); screen.helpPage=math.max(1,math.min(pageCount,screen.helpPage or 1))
  local lines=pages[screen.helpPage] or {}
  for i,line in ipairs(lines) do
    if i>10 then break end
    Font.draw(tostring(line),8,32+i*8)
  end
  local footer=(pageCount>1) and ("PAGE %d/%d  B:BACK"):format(screen.helpPage,pageCount) or "B:BACK"
  Font.draw(footer,8,132)
  return true
end

local function screenObject(game,rows,isRoot)
  local okOR,OptionRows=pcall(require,"src.ui.OptionRows")
  if not okOR or not OptionRows then return nil end
  local screen={game=game,rows=rows,index=1,scroll=0,isOpaque=true,helpRow=nil,helpPage=1,root=isRoot}
  function screen:sgbPalettes(g)
    local ok,P=pcall(require,"src.render.PaletteFX")
    if ok and P and P.wholeNamed then return P.wholeNamed(g.data,"MEWMON") end
  end
  function screen:update(dt)
    local input=self.game and self.game.input; if not input then return end
    if self.helpRow then
      if input:wasPressed("b") or input:wasPressed("a") or input:wasPressed("select") then self.helpRow=nil; self.helpPage=1; return end
      if input:wasPressed("left") then self.helpPage=math.max(1,(self.helpPage or 1)-1) end
      if input:wasPressed("right") then self.helpPage=(self.helpPage or 1)+1 end
      return
    end
    local cancel=#self.rows+1
    if input:wasPressed("up") then self.index=self.index>1 and self.index-1 or cancel
    elseif input:wasPressed("down") then self.index=self.index<cancel and self.index+1 or 1
    elseif input:wasPressed("select") then
      local row=self.rows[self.index]; if row and row.help then self.helpRow=row; self.helpPage=1 end
    elseif input:wasPressed("left") or input:wasPressed("right") or input:wasPressed("a") then
      local row=self.rows[self.index]
      if row and row.activate then
        if input:wasPressed("a") then row.activate(self.game) end
      elseif row and row.step then
        local dir=input:wasPressed("left") and -1 or 1
        if row.step(self.game,dir) and self.game.writeOptions then pcall(self.game.writeOptions,self.game) end
      elseif input:wasPressed("a") then self.game.stack:pop() end
    elseif input:wasPressed("b") or input:wasPressed("start") then self.game.stack:pop() end
    self.scroll=OptionRows.clampScroll(self.index,self.scroll or 0,#self.rows,cancel)
  end
  function screen:draw()
    if self.helpRow and drawHelp(self) then return end
    OptionRows.draw(self.game,self.rows,self.index,self.scroll or 0,self.root and "A:OPEN SEL:HELP" or "SEL:HELP B:BACK",#self.rows+1)
  end
  return screen
end

local function makeGroupScreen(group)
  return function(game) return screenObject(game,makeSettingRows(group),false) end
end

local function makeRootScreen(game)
  local rows={}
  for _,group in ipairs(Settings.GROUPS or {}) do
    local g=group
    rows[#rows+1]={
      id=mod.id..":group:"..g.id,label=g.label,help=g.help,description=g.help,desc=g.help,
      value=function() return tostring(#(g.keys or {})).." OPTIONS" end,
      activate=function(game2)
        local ok,Screens=pcall(require,"src.ui.Screens")
        if ok and Screens and Screens.push then Screens.push(game2,GROUP_PREFIX..g.id) end
      end,
    }
  end
  return screenObject(game,rows,true)
end

function Menu.install()
  if Menu.installed then return true end
  if not (mod and mod.content and mod.content.screens and type(mod.content.screens.register)=="function") then return false end
  local ok=pcall(function()
    mod.content.screens:register(ROOT_ID,{new=makeRootScreen})
    for _,group in ipairs(Settings.GROUPS or {}) do mod.content.screens:register(GROUP_PREFIX..group.id,{new=makeGroupScreen(group)}) end
  end)
  if not ok then return false end

  -- Route the Weather FX card in the normal mod manager to the grouped screen.
  pcall(function()
    if not (mod.events and type(mod.events.once)=="function") then return end
    mod.events:once("mods.loaded",function()
      local okM,ManagerState=pcall(require,"src.mods.ManagerState"); if not okM or not ManagerState then return end
      local routes=rawget(ManagerState,"__modOptionScreenRoutes")
      if not routes then
        routes={}; local openOptions=ManagerState.openOptions
        ManagerState.openOptions=function(self,manifest)
          local screenId=manifest and routes[manifest.id]
          if screenId then
            local okS,Screens=pcall(require,"src.ui.Screens")
            if okS and Screens and Screens.push then return Screens.push(self.game,screenId) end
          end
          return openOptions(self,manifest)
        end
        ManagerState.__modOptionScreenRoutes=routes
      end
      routes[mod.id]=ROOT_ID
    end)
  end)

  -- One discoverable opener in the game's OPTIONS menu. It is a submenu row,
  -- not fifty Weather FX rows, so the base OPTIONS screen stays clean.
  pcall(function()
    if not (mod.hooks and type(mod.hooks.wrap)=="function") then return end
    mod.hooks:wrap("ui.options.rows",function(next,game,rows)
      local out=next(game,rows); if type(out)~="table" then return out end
      for _,r in ipairs(out) do if r.id==mod.id..":settings" then return out end end
      local row={id=mod.id..":settings",label="WEATHER FX",value=function() return "SETTINGS" end,
        activate=function(g) local okS,Screens=pcall(require,"src.ui.Screens"); if okS and Screens and Screens.push then Screens.push(g,ROOT_ID) end end}
      if mod.ui and type(mod.ui.insertBefore)=="function" then return mod.ui.insertBefore(out,"MODS",row) end
      out[#out+1]=row; return out
    end)
  end)
  Menu.installed=true
  return true
end

Menu.ROOT_ID=ROOT_ID
return Menu
