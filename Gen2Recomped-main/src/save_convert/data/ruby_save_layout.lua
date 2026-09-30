-- US Ruby / Sapphire 1.0 SaveBlock layout (pokeruby, not Emerald).
-- Money, coins, bag quantities and game stats are stored PLAIN -- there is
-- no SaveBlock2 encryptionKey.  Sector split is still 1 + 4 + 9.
--
-- Sizes: SaveBlock2 0x890 (2192), SaveBlock1 0x3AC0 (15040),
-- PokemonStorage 0x83D0 (33744).  Flash image is 128 KiB, two 14-sector slots.

local SECTOR_DATA = 3968

return {
  _romInfo = {
    fields = true,
    orders = 24,
    sectors = 14,
    source = "pokeruby SaveBlock1/2 + PokemonStorage",
    total = 2192 + 15040 + 33744,
  },
  saveBlock2Size = 2192,
  saveBlock1Size = 15040,
  pokemonStorageSize = 33744,
  sectorSize = 4096,
  sectorsPerSlot = 14,
  security = 134291493,
  sectors = {
    { offset = 0, size = 2192 },
    { offset = 0, size = SECTOR_DATA },
    { offset = SECTOR_DATA, size = SECTOR_DATA },
    { offset = SECTOR_DATA * 2, size = SECTOR_DATA },
    { offset = SECTOR_DATA * 3, size = 15040 - SECTOR_DATA * 3 },
    { offset = 0, size = SECTOR_DATA },
    { offset = SECTOR_DATA, size = SECTOR_DATA },
    { offset = SECTOR_DATA * 2, size = SECTOR_DATA },
    { offset = SECTOR_DATA * 3, size = SECTOR_DATA },
    { offset = SECTOR_DATA * 4, size = SECTOR_DATA },
    { offset = SECTOR_DATA * 5, size = SECTOR_DATA },
    { offset = SECTOR_DATA * 6, size = SECTOR_DATA },
    { offset = SECTOR_DATA * 7, size = SECTOR_DATA },
    { offset = SECTOR_DATA * 8, size = 33744 - SECTOR_DATA * 8 },
  },
  fields = {
    metGame = 2, -- VERSION_RUBY; Sapphire overlay sets 1 at load time
    flagBytes = 288,
    varCount = 256,
    varsStartId = 0x4000,
    bag = {
      capacities = { 20, 20, 16, 64, 46 },
      itemSlotSize = 4,
      pcItemCount = 50,
      pcItems = 0x498,
      pockets = { 0x560, 0x5B0, 0x600, 0x640, 0x740 },
    },
    berryTrees = {
      count = 128,
      offset = 0x1608,
      stride = 8,
    },
    party = {
      count = 0x234,
      monSize = 100,
      size = 6,
      start = 0x238,
    },
    saveBlock1 = {
      posX = 0,
      posY = 2,
      location = 0x04,
      lastHeal = 0x1C,
      weather = 0x2E,
      weatherCycleStage = 0x2F,
      mapLayoutId = 0x32,
      playerPartyCount = 0x234,
      playerParty = 0x238,
      money = 0x490,
      coins = 0x494,
      registeredItem = 0x496,
      pcItems = 0x498,
      flags = 0x1220,
      vars = 0x1340,
      gameStats = 0x1540,
      gameStatCount = 50,
      berryTrees = 0x1608,
    },
    saveBlock2 = {
      playerName = 0x00,
      playerGender = 0x08,
      playerTrainerId = 0x0A,
      playTimeHours = 0x0E,
      playTimeMinutes = 0x10,
      playTimeSeconds = 0x11,
      playTimeVBlanks = 0x12,
      pokedexOwned = 0x28,
      pokedexSeen = 0x5C,
      pokedexOwnedBytes = 52,
      -- encryptionKey omitted: Ruby/Sapphire store money and bag counts in the clear
    },
    storage = {
      boxCapacity = 30,
      boxCount = 14,
      boxMonSize = 80,
      boxNameLength = 9,
      boxNames = 0x8344,
      boxWallpapers = 0x83C2,
      boxes = 4,
      currentBox = 0,
    },
  },
  -- personality % 24 substructure order; same table Emerald uses
  substructOrders = {
    { 0, 1, 2, 3 }, { 0, 1, 3, 2 }, { 0, 2, 1, 3 }, { 0, 3, 1, 2 },
    { 0, 2, 3, 1 }, { 0, 3, 2, 1 }, { 1, 0, 2, 3 }, { 1, 0, 3, 2 },
    { 2, 0, 1, 3 }, { 3, 0, 1, 2 }, { 2, 0, 3, 1 }, { 3, 0, 2, 1 },
    { 1, 2, 0, 3 }, { 1, 3, 0, 2 }, { 2, 1, 0, 3 }, { 3, 1, 0, 2 },
    { 2, 3, 0, 1 }, { 3, 2, 0, 1 }, { 1, 2, 3, 0 }, { 1, 3, 2, 0 },
    { 2, 1, 3, 0 }, { 3, 1, 2, 0 }, { 2, 3, 1, 0 }, { 3, 2, 1, 0 },
  },
}
