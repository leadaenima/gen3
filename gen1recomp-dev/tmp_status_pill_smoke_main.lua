local romPath = "misc/Pokemon - Ruby Version (USA).gba"
local f = assert(io.open(romPath, "rb"), "rom open failed: " .. romPath)
local data = f:read("*a"); f:close()
local CacheFs = require("src.import.CacheFs")
CacheFs.prefix = "ruby/"
local Ui = require("src.import.RomExtractorGen3Ui")
local sheetPath, individuals = Ui.saveStatusPills(data)
print("sheetPath=", tostring(sheetPath))
local ok = CacheFs.exists("assets/generated/ui/battle_status_pills.png")
local bytes = CacheFs.read("assets/generated/ui/battle_status_pills.png")
print("exists=", tostring(ok), "bytes=", bytes and #bytes or "nil")
if individuals then for k,v in pairs(individuals) do print(k, v) end end
assert(sheetPath and ok and bytes and #bytes > 100, "extract failed")
print("SMOKE_OK")
