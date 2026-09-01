-- Gen 3 field-script IR.  Bytecode is walked at import (ROM pointers become
-- Latin strings and op indices) so playtime never reads the .gba.
local GbaBin = require("src.import.GbaBin")
local GbaText = require("src.import.GbaText")

local Script = {}

Script.END = 0x02
Script.RETURN = 0x03
Script.CALL = 0x04
Script.GOTO = 0x05
Script.GOTO_IF = 0x06
Script.CALL_IF = 0x07
Script.GOTOSTD = 0x08
Script.CALLSTD = 0x09
Script.LOADWORD = 0x0F
Script.SETVAR = 0x16
Script.ADDVAR = 0x17
Script.SUBVAR = 0x18
Script.COPYVAR = 0x19
Script.SETORCOPYVAR = 0x1A
Script.COMPARE_VAR_VALUE = 0x21
Script.COMPARE_VAR_VAR = 0x22
Script.SPECIAL = 0x25
Script.SPECIALVAR = 0x26
Script.WAITSTATE = 0x27
Script.DELAY = 0x28
Script.SETFLAG = 0x29
Script.CLEARFLAG = 0x2A
Script.CHECKFLAG = 0x2B
Script.PLAYSE = 0x2F
Script.WAITSE = 0x30
Script.PLAYFANFARE = 0x31
Script.WAITFANFARE = 0x32
Script.PLAYBGM = 0x33
Script.SAVEBGM = 0x34
Script.FADEDEFAULTBGM = 0x35
Script.FADENEWBGM = 0x36
Script.FADEOUTBGM = 0x37
Script.FADEINBGM = 0x38
Script.WARP = 0x39
Script.WARPSILENT = 0x3A
Script.WARPDOOR = 0x3B
Script.WARPHOLE = 0x3C
Script.WARPTELEPORT = 0x3D
Script.SETWARP = 0x3E
Script.SETDYNAMICWARP = 0x3F
Script.SETDIVEWARP = 0x40
Script.SETHOLEWARP = 0x41
Script.SETESCAPEWARP = 0xC4
Script.FADESCREEN = 0x97
Script.DOFIELDEFFECT = 0x9C
Script.SETFIELDEFFECTARGUMENT = 0x9D
Script.WAITFIELDEFFECT = 0x9E
Script.SETRESPAWN = 0x9F
Script.GETPLAYERXY = 0x42
Script.GETPARTYSIZE = 0x43
Script.ADDITEM = 0x44
Script.REMOVEITEM = 0x45
Script.CHECKITEMSPACE = 0x46
Script.CHECKITEM = 0x47
Script.ADDDECORATION = 0x4B
Script.APPLYMOVEMENT = 0x4F
Script.WAITMOVEMENT = 0x51
Script.REMOVEOBJECT = 0x53
Script.ADDOBJECT = 0x55
Script.SETOBJECTXY = 0x57
Script.SHOWOBJECTAT = 0x58
Script.HIDEOBJECTAT = 0x59
Script.FACEPLAYER = 0x5A
Script.TURNOBJECT = 0x5B
Script.TRAINERBATTLE = 0x5C
Script.CHECKTRAINERFLAG = 0x60
Script.SETTRAINERFLAG = 0x61
Script.CLEARTRAINERFLAG = 0x62
Script.SETOBJECTXYPERM = 0x63
Script.MOVEOBJECTOFFSCREEN = 0x64
Script.SETOBJECTMOVEMENTTYPE = 0x65
Script.CHECKPLAYERGENDER = 0xA0
Script.SETMETATILE = 0xA2
Script.RESETWEATHER = 0xA3
Script.SETWEATHER = 0xA4
Script.DOWEATHER = 0xA5
Script.SETSTEPCALLBACK = 0xA6
Script.SETMAPLAYOUTINDEX = 0xA7
Script.SETOBJECTPRIORITY = 0xA8
Script.RESETOBJECTPRIORITY = 0xA9
Script.OPENDOOR = 0xAC
Script.CLOSEDOOR = 0xAD
Script.SETDOOROPEN = 0xAF
Script.SETDOORCLOSED = 0xB0
Script.LOCALID_PLAYER = 0xFF
Script.STEP_END = 0xFE
-- DewfordTown_Movement_SailToPetalburg is ~194 actions; 48 cut the boat.
Script.MAX_MOVE = 512
Script.MOVE_DELAY_1 = 0x10
Script.MOVE_DELAY_16 = 0x14
Script.MOVE_FACE_PLAYER = 0x3E
Script.MOVE_FACE_AWAY_PLAYER = 0x3F
Script.MOVE_LOCK_FACING = 0x40
Script.MOVE_UNLOCK_FACING = 0x41
Script.MOVE_START_ANIM = 0x39
Script.MOVE_FACE_ORIGINAL = 0x4E
Script.MOVE_NURSE_BOW = 0x4F
Script.MOVE_ENABLE_JUMP_LAND = 0x50
Script.MOVE_DISABLE_JUMP_LAND = 0x51
Script.MOVE_DISABLE_ANIM = 0x52
Script.MOVE_RESTORE_ANIM = 0x53
Script.MOVE_SET_INVISIBLE = 0x54
Script.MOVE_SET_VISIBLE = 0x55
Script.MOVE_REVEAL_TRAINER = 0x59
Script.MOVE_ROCK_SMASH = 0x5A
Script.MOVE_CUT_TREE = 0x5B
Script.MOVE_SET_PRIORITY = 0x5C
Script.MOVE_CLEAR_PRIORITY = 0x5D
Script.MOVE_INIT_AFFINE = 0x5E
Script.MOVE_CLEAR_AFFINE = 0x5F
Script.MOVE_HIDE_REFLECTION = 0x60
Script.MOVE_SHOW_REFLECTION = 0x61
Script.MOVE_LOCK_ANIM = 0x94
Script.MOVE_UNLOCK_ANIM = 0x95
Script.MOVE_EMOTE_EXCLAIM = 0x56
Script.MOVE_EMOTE_QUESTION = 0x57
Script.MOVE_EMOTE_HEART = 0x58
Script.MOVE_WALK_DOWN_AFFINE = 0x62
Script.MOVE_ACRO_WHEELIE_FACE_DOWN = 0x64
Script.MOVE_ACRO_WHEELIE_HOP_DOWN = 0x74
Script.MOVE_ACRO_WHEELIE_JUMP_DOWN = 0x78
Script.MOVE_DIAGONAL_UP_LEFT = 0x8C
Script.MOVE_LEVITATE = 0x98
Script.MOVE_STOP_LEVITATE = 0x99
Script.MOVE_FLY_UP = 0x9C
Script.MOVE_FLY_DOWN = 0x9D
Script.WAITMESSAGE = 0x66
Script.MESSAGE = 0x67
Script.CLOSEMESSAGE = 0x68
Script.LOCKALL = 0x69
Script.LOCK = 0x6A
Script.RELEASEALL = 0x6B
Script.RELEASE = 0x6C
Script.WAITBUTTON = 0x6D
Script.GIVEMON = 0x79
Script.GIVEEGG = 0x7A
Script.CHECKPARTYMOVE = 0x7C
Script.BUFFERSPECIESNAME = 0x7D
Script.BUFFERLEADMON = 0x7E
Script.BUFFERPARTYMONNICK = 0x7F
Script.BUFFERITEMNAME = 0x80
Script.BUFFERDECORATIONNAME = 0x81
Script.BUFFERMOVENAME = 0x82
Script.BUFFERNUMBER = 0x83
Script.SETFLASHRADIUS = 0x99
Script.ANIMATEFLASH = 0x9A
Script.RANDOM = 0x8F
Script.PLAYSLOTMACHINE = 0x89
Script.ADDMONEY = 0x90
Script.REMOVEMONEY = 0x91
Script.CHECKMONEY = 0x92
Script.SHOWMONEYBOX = 0x93
Script.HIDEMONEYBOX = 0x94
Script.UPDATEMONEYBOX = 0x95
Script.GETPRICEREDUCTION = 0x96
Script.CHECKCOINS = 0xB3
Script.ADDCOINS = 0xB4
Script.REMOVECOINS = 0xB5
Script.SETWILDBATTLE = 0xB6
Script.DOWILDBATTLE = 0xB7
Script.SHOWCOINSBOX = 0xC0
Script.HIDECOINSBOX = 0xC1
Script.UPDATECOINSBOX = 0xC2
Script.PLAYMONCRY = 0xA1
Script.WAITMONCRY = 0xC5
Script.WAITDOORANIM = 0xAE
Script.INCREMENTGAMESTAT = 0xC3
Script.TRAINER_FLAG_START = 0x500
Script.MAX_MONEY = 999999
Script.SETBERRYTREE = 0x8A
Script.CHOOSECONTESTMON = 0x8B
Script.STARTCONTEST = 0x8C
Script.POKEMART = 0x86
Script.POKEMART_DECORATION = 0x87
Script.POKEMART_DECORATION2 = 0x88
Script.SHOWCONTESTRESULTS = 0x8D
Script.SHOWCONTESTWINNER = 0x77
Script.STD_OBTAIN_ITEM = 0
Script.STD_FIND_ITEM = 1
Script.STD_MSGBOX_NPC = 2
Script.STD_MSGBOX_SIGN = 3
Script.STD_MSGBOX_DEFAULT = 4
Script.STD_MSGBOX_YESNO = 5
Script.STD_MSGBOX_AUTOCLOSE = 6
Script.STD_OBTAIN_DECORATION = 7
Script.VAR_0x8000 = 0x8000
Script.VAR_0x8001 = 0x8001
Script.VAR_0x8004 = 0x8004
Script.VAR_0x8005 = 0x8005
Script.VAR_0x8006 = 0x8006
Script.VAR_FACING = 0x800C
Script.VAR_RESULT = 0x800D
Script.VAR_ITEM_ID = 0x800E
Script.VAR_LAST_TALKED = 0x800F
Script.COND_EQ = 1
Script.YESNOBOX = 0x6E
Script.MULTICHOICE = 0x6F
Script.MULTICHOICEDEFAULT = 0x70
Script.MULTICHOICEGRID = 0x71
Script.VARS_START = 0x4000
-- Runaway guards, not budgets: a bad pointer must not walk the whole cart,
-- but a real script must never be clipped.  tools/gen3_script_audit.lua
-- measures Ruby's worst case at 823 commands and 5 nested calls across all
-- 2089 map entry points, so these sit clear of the cart with room to spare.
Script.MAX_OPS = 2048
Script.MAX_CALL = 8
-- gym-guide / Roxanne speeches exceed 512 ROM bytes (Rustboro ~581).
Script.TEXT_LEN = 1024

-- Byte length of one command, from pokeruby include/macros/event.inc.  A
-- `map` argument is two bytes (group then number).  Every command Ruby
-- can store needs a length even when nothing below decodes it: a sized
-- command with no case becomes a nop and the walk carries on, so one
-- unimplemented effect never truncates the rest of a ROM script.
local SIZE = {
  [0x00] = 1, [0x01] = 1, [0x02] = 1, [0x03] = 1,
  [0x04] = 5, [0x05] = 5, [0x06] = 6, [0x07] = 6,
  [0x08] = 2, [0x09] = 2, [0x0A] = 3, [0x0B] = 3,
  [0x0C] = 1, [0x0D] = 1, [0x0E] = 2,
  [0x0F] = 6, [0x10] = 3,
  [0x11] = 6, [0x12] = 6, [0x13] = 6, [0x14] = 3, [0x15] = 9,
  [0x16] = 5, [0x17] = 5, [0x18] = 5, [0x19] = 5, [0x1A] = 5,
  [0x1B] = 3, [0x1C] = 3, [0x1D] = 6, [0x1E] = 6, [0x1F] = 6,
  [0x20] = 9, [0x21] = 5, [0x22] = 5, [0x23] = 5, [0x24] = 5,
  [0x25] = 3, [0x26] = 5, [0x27] = 1, [0x28] = 3,
  [0x29] = 3, [0x2A] = 3, [0x2B] = 3,
  [0x2C] = 5, [0x2D] = 1, [0x2E] = 1,
  [0x2F] = 3, [0x30] = 1, [0x31] = 3, [0x32] = 1,
  [0x33] = 4, [0x34] = 3, [0x35] = 1, [0x36] = 3,
  [0x37] = 2, [0x38] = 2,
  [0x39] = 8, [0x3A] = 8, [0x3B] = 8, [0x3C] = 3, [0x3D] = 8,
  [0x3E] = 8, [0x3F] = 8, [0x40] = 8, [0x41] = 8,
  [0x42] = 5, [0x43] = 1, [0x44] = 5, [0x45] = 5, [0x46] = 5,
  [0x47] = 5, [0x48] = 3, [0x49] = 5, [0x4A] = 5, [0x4B] = 3,
  [0x4C] = 3, [0x4D] = 3, [0x4E] = 3,
  [0x4F] = 7, [0x50] = 9, [0x51] = 3, [0x52] = 5,
  [0x53] = 3, [0x54] = 5, [0x55] = 3, [0x56] = 5,
  [0x57] = 7, [0x58] = 5, [0x59] = 5,
  [0x5A] = 1, [0x5B] = 4, [0x5C] = 14,
  [0x5D] = 1, [0x5E] = 1, [0x5F] = 1,
  [0x60] = 3, [0x61] = 3, [0x62] = 3,
  [0x63] = 7, [0x64] = 3, [0x65] = 4,
  [0x66] = 1, [0x67] = 5, [0x68] = 1, [0x69] = 1,
  [0x6A] = 1, [0x6B] = 1, [0x6C] = 1, [0x6D] = 1, [0x6E] = 3,
  [0x6F] = 5, [0x70] = 6, [0x71] = 6, [0x72] = 5, [0x73] = 5,
  [0x74] = 5, [0x75] = 5, [0x76] = 1, [0x77] = 2, [0x78] = 5,
  [0x79] = 15, [0x7A] = 3, [0x7B] = 5, [0x7C] = 3,
  [0x7D] = 4, [0x7E] = 2, [0x7F] = 4,
  [0x80] = 4, [0x81] = 4, [0x82] = 4, [0x83] = 4, [0x84] = 4,
  [0x85] = 6, [0x86] = 5, [0x87] = 5, [0x88] = 5, [0x89] = 3,
  [0x8A] = 4,
  [0x8B] = 1, [0x8C] = 1, [0x8D] = 1, [0x8E] = 1, [0x8F] = 3,
  [0x90] = 6, [0x91] = 6, [0x92] = 6, [0x93] = 3, [0x94] = 3,
  [0x95] = 3, [0x96] = 3,
  [0x97] = 2, [0x98] = 3, [0x99] = 3, [0x9A] = 2, [0x9B] = 5,
  [0x9C] = 3, [0x9D] = 4, [0x9E] = 3, [0x9F] = 3,
  [0xA0] = 1, [0xA1] = 5, [0xA2] = 9, [0xA3] = 1, [0xA4] = 3,
  [0xA5] = 1, [0xA6] = 2, [0xA7] = 3, [0xA8] = 6, [0xA9] = 5,
  [0xAA] = 9, [0xAB] = 3,
  [0xAC] = 5, [0xAD] = 5, [0xAE] = 1, [0xAF] = 5, [0xB0] = 5,
  [0xB1] = 1, [0xB2] = 1, [0xB3] = 3, [0xB4] = 3, [0xB5] = 3,
  [0xB6] = 6, [0xB7] = 1, [0xB8] = 5, [0xB9] = 5, [0xBA] = 5,
  [0xBB] = 6, [0xBC] = 6, [0xBD] = 5, [0xBE] = 5, [0xBF] = 6,
  [0xC0] = 3, [0xC1] = 3, [0xC2] = 3, [0xC3] = 2, [0xC4] = 8,
  [0xC5] = 1, [0xC6] = 4, [0xC7] = 2, [0xC8] = 5, [0xC9] = 1,
  [0xCA] = 1, [0xCB] = 1, [0xCC] = 6,
}

-- trainerbattle is the one command whose length is not fixed: a 6-byte
-- header, then one pointer per TRAINER_BATTLE_* type (pokeruby
-- include/constants/battle_setup.h).  A wrong length here misaligns every
-- command after it, so the count is tabulated per type rather than
-- guessed from the common cases.
local TRAINER_BATTLE_HEAD = 6
local TRAINER_BATTLE_PTRS = {
  [0] = 2, -- SINGLE
  [1] = 3, -- CONTINUE_SCRIPT_NO_MUSIC
  [2] = 3, -- CONTINUE_SCRIPT
  [3] = 1, -- SINGLE_NO_INTRO_TEXT
  [4] = 3, -- DOUBLE
  [5] = 2, -- REMATCH
  [6] = 4, -- CONTINUE_SCRIPT_DOUBLE
  [7] = 3, -- REMATCH_DOUBLE
  [8] = 4, -- CONTINUE_SCRIPT_DOUBLE_NO_MUSIC
}

-- Byte length of the command at `off`, or nil when the byte is not a
-- command and the walk cannot know where the next one starts.
function Script.cmdSize(data, off)
  if type(data) ~= "string" or type(off) ~= "number" then return nil end
  if off < 0 or off >= #data then return nil end
  local cmd = GbaBin.u8(data, off)
  if cmd ~= Script.TRAINERBATTLE then return SIZE[cmd] end
  local ptrs = off + 1 < #data and TRAINER_BATTLE_PTRS[GbaBin.u8(data, off + 1)]
  if not ptrs then return SIZE[cmd] end
  return TRAINER_BATTLE_HEAD + ptrs * 4
end

local function romPtr(data, offset)
  local ptr = GbaBin.u32(data, offset)
  if not GbaBin.isRomPtr(ptr, #data) then return nil end
  return GbaBin.romOffset(ptr)
end

local function readText(data, off)
  if not off then return nil end
  local blob = data:sub(off + 1, off + Script.TEXT_LEN)
  local pages = GbaText.decodePages(blob, Script.TEXT_LEN)
  if #pages > 0 then
    return table.concat(pages, "\n")
  end
  local text = GbaText.decodeText(blob, Script.TEXT_LEN)
  if text == "" then return nil end
  return text
end

-- pokeruby gTrainerBattleSpecs_1 / _4: CONTINUE_SCRIPT kinds load
-- sTrainerBattleEndScript from the last pointer.  gotobeatenscript
-- (0x5F) jumps there after a win; the next opcode is only the
-- already-defeated talk-again path.  trainerbattle_double with an
-- event_script argument assembles as CONTINUE_SCRIPT_DOUBLE (kind 6),
-- not DOUBLE (kind 4); kind 4 has no after pointer.
local function parseTrainerAfter(data, kind, ptrBase, depth)
  local dest
  if kind == 1 or kind == 2 then
    dest = romPtr(data, ptrBase + 8)
  elseif kind == 6 or kind == 8 then
    dest = romPtr(data, ptrBase + 12)
  end
  if dest and depth < Script.MAX_CALL then
    return Script.parse(data, dest, depth + 1)
  end
end

-- pokeemerald sScriptConditionTable[cond][comparisonResult] where
-- result 0=<, 1==, 2=>.  checkflag stores 0/1 in that same slot.
local COND = {
  [0] = { [0] = true, [1] = false, [2] = false },
  [1] = { [0] = false, [1] = true, [2] = false },
  [2] = { [0] = false, [1] = false, [2] = true },
  [3] = { [0] = true, [1] = true, [2] = false },
  [4] = { [0] = false, [1] = true, [2] = true },
  [5] = { [0] = true, [1] = false, [2] = true },
}

function Script.condJump(cond, result)
  local row = COND[cond or 0]
  return row and row[result or 0] or false
end

local MOVE_DIR = { "south", "north", "west", "east" }
local DELAY_FRAMES = {
  [0x10] = 1, [0x11] = 2, [0x12] = 4, [0x13] = 8, [0x14] = 16,
}
local EMOTE_OF = {
  [0x56] = "exclaim", [0x57] = "question", [0x58] = "heart",
}
local DIAGONAL = {
  [0x8C] = { dx = -1, dy = -1, dir = "north" },
  [0x8D] = { dx = 1, dy = -1, dir = "north" },
  [0x8E] = { dx = -1, dy = 1, dir = "south" },
  [0x8F] = { dx = 1, dy = 1, dir = "south" },
  [0x90] = { dx = -1, dy = -1, dir = "north" },
  [0x91] = { dx = 1, dy = -1, dir = "north" },
  [0x92] = { dx = -1, dy = 1, dir = "south" },
  [0x93] = { dx = 1, dy = 1, dir = "south" },
}
local JUMP_SPECIAL_DIR = {
  [0x3A] = "south", [0x3B] = "north", [0x3C] = "west", [0x3D] = "east",
}
local MOVE_FLAG = {
  [0x50] = { key = "jumpLand", on = true },
  [0x51] = { key = "jumpLand", on = false },
  [0x52] = { key = "lockAnim", on = true },
  [0x53] = { key = "lockAnim", on = false },
  [0x5C] = { key = "fixedPriority", on = true },
  [0x5D] = { key = "fixedPriority", on = false },
  [0x5E] = { key = "affine", on = true },
  [0x5F] = { key = "affine", on = false },
  [0x60] = { key = "hideReflection", on = true },
  [0x61] = { key = "hideReflection", on = false },
}

-- event_object_movement.h + do_go_anim speed / sub_806468C.
-- "slow" is 32 frames; 0..4 index gUnknown_08376194 {16,8,6,4,2}.
function Script.walkSpeed(action)
  action = action or 0
  if (action >= 0x4 and action <= 0x7)
      or (action >= 0x19 and action <= 0x1C) then
    return "slow"
  end
  if (action >= 0x8 and action <= 0xB)
      or (action >= 0x1D and action <= 0x20) then
    return 0
  end
  if (action >= 0x15 and action <= 0x18)
      or (action >= 0x21 and action <= 0x24)
      or (action >= 0x35 and action <= 0x38) then
    return 1
  end
  if action >= 0x29 and action <= 0x2C then return 2 end
  if (action >= 0x2D and action <= 0x30)
      or (action >= 0x25 and action <= 0x28) then
    return 3
  end
  if action >= 0x31 and action <= 0x34 then return 4 end
  return 0
end

function Script.dirOfAction(action)
  action = action or 0
  local idx
  if action >= 0x42 and action <= 0x45 then
    idx = action - 0x42
  elseif action >= 0x46 and action <= 0x49 then
    idx = action - 0x46
  elseif action >= 0x15 and action <= 0x38 then
    idx = (action - 0x15) % 4
  else
    idx = action % 4
  end
  return MOVE_DIR[idx + 1]
end

function Script.delayFrames(action)
  return DELAY_FRAMES[action or 0]
end

function Script.emoteOfAction(action)
  return EMOTE_OF[action or 0]
end

function Script.kindOfAction(action)
  action = action or 0
  if action <= 3 then return "face" end
  if DELAY_FRAMES[action] then return "delay" end
  if action == Script.MOVE_FACE_PLAYER then return "faceplayer" end
  if action == Script.MOVE_FACE_AWAY_PLAYER then return "faceaway" end
  if action == Script.MOVE_LOCK_FACING then return "lockface" end
  if action == Script.MOVE_UNLOCK_FACING then return "unlockface" end
  if action == Script.MOVE_FACE_ORIGINAL then return "faceoriginal" end
  if action == Script.MOVE_NURSE_BOW then return "bow" end
  if action == Script.MOVE_START_ANIM then return "place" end
  if MOVE_FLAG[action] then return "flag" end
  if action == Script.MOVE_SET_INVISIBLE then return "invisible" end
  if action == Script.MOVE_SET_VISIBLE then return "visible" end
  if EMOTE_OF[action] then return "emote" end
  if action == Script.MOVE_REVEAL_TRAINER then return "reveal" end
  if action == Script.MOVE_ROCK_SMASH then return "smash" end
  if action == Script.MOVE_CUT_TREE then return "cut" end
  if action == Script.MOVE_LOCK_ANIM then return "lockanim" end
  if action == Script.MOVE_UNLOCK_ANIM then return "unlockanim" end
  if action >= 0x19 and action <= 0x28 then return "walkplace" end
  if action >= 0x0C and action <= 0x0F then return "jump2" end
  if action >= 0x42 and action <= 0x45 then return "jump" end
  if JUMP_SPECIAL_DIR[action] then return "jump" end
  if action >= 0x46 and action <= 0x4D then return "face" end
  if action == 0x62 or action == 0x63 then return "walk" end
  if action >= 0x64 and action <= 0x73 then return "face" end
  if action >= 0x74 and action <= 0x77 then return "walk" end
  if action >= 0x78 and action <= 0x7B then return "jump2" end
  if action >= 0x7C and action <= 0x7F then return "face" end
  if action >= 0x80 and action <= 0x8B then return "walk" end
  if DIAGONAL[action] then return "walk" end
  if action == Script.MOVE_LEVITATE then return "levitate" end
  if action == Script.MOVE_STOP_LEVITATE or action == 0x9A then return "land" end
  if action == 0x9B then return "delay" end
  if action == Script.MOVE_FLY_UP then return "flyup" end
  if action == Script.MOVE_FLY_DOWN then return "flydown" end
  if action == 0x96 or action == 0x97 then return "walk" end
  if action >= 4 and action <= 0x38 then return "walk" end
  return "skip"
end

function Script.parseMartList(data, off)
  local items = {}
  if type(data) ~= "string" or type(off) ~= "number" then return items end
  for i = 0, 15 do
    if off + i * 2 + 2 > #data then break end
    local id = GbaBin.u16(data, off + i * 2)
    if id == 0 then break end
    items[#items + 1] = id
  end
  return items
end

function Script.parseMovement(data, start)
  if type(data) ~= "string" or type(start) ~= "number" then return nil end
  local steps = {}
  for i = 0, Script.MAX_MOVE - 1 do
    local off = start + i
    if off < 0 or off >= #data then break end
    local action = GbaBin.u8(data, off)
    if action == Script.STEP_END then break end
    local kind = Script.kindOfAction(action)
    local diag = DIAGONAL[action]
    if kind == "delay" then
      steps[#steps + 1] = { kind = "delay", frames = DELAY_FRAMES[action] or 16 }
    elseif kind == "emote" then
      steps[#steps + 1] = { kind = "emote", emote = EMOTE_OF[action] }
    elseif kind == "invisible" or kind == "visible" or kind == "faceplayer"
        or kind == "faceaway" or kind == "faceoriginal"
        or kind == "lockface" or kind == "unlockface"
        or kind == "bow" or kind == "reveal"
        or kind == "smash" or kind == "cut"
        or kind == "lockanim" or kind == "unlockanim"
        or kind == "levitate" or kind == "land"
        or kind == "flyup" or kind == "flydown"
        or kind == "place" then
      steps[#steps + 1] = { kind = kind }
    elseif kind == "walkplace" then
      steps[#steps + 1] = {
        kind = "walkplace",
        dir = Script.dirOfAction(action),
        speed = Script.walkSpeed(action),
      }
    elseif kind == "flag" then
      local flag = MOVE_FLAG[action]
      steps[#steps + 1] = { kind = "flag", key = flag.key, on = flag.on }
    elseif action == 0x62 or action == 0x63 then
      steps[#steps + 1] = { kind = "walk", dir = "south" }
    elseif diag then
      steps[#steps + 1] = {
        kind = "walk", dir = diag.dir, dx = diag.dx, dy = diag.dy,
      }
    elseif JUMP_SPECIAL_DIR[action] then
      steps[#steps + 1] = { kind = "jump", dir = JUMP_SPECIAL_DIR[action] }
    elseif kind ~= "skip" then
      local step = { kind = kind, dir = Script.dirOfAction(action) }
      if kind == "walk" then
        step.speed = Script.walkSpeed(action)
      end
      steps[#steps + 1] = step
    end
  end
  return steps
end

local function decode(data, off, depth)
  if off < 0 or off >= #data then return nil, 1, nil end
  local cmd = GbaBin.u8(data, off)
  local size = Script.cmdSize(data, off)
  if not size then return nil, 1, nil end
  if off + size > #data then return { op = "end" }, 1, nil end
  local nextOff = off + size
  if cmd == Script.END or cmd == Script.RETURN then
    return { op = "end" }, size, nil
  end
  if cmd == Script.GOTO then
    return { op = "goto", at = romPtr(data, off + 1) }, size, nil
  end
  if cmd == Script.GOTO_IF then
    return {
      op = "goto_if",
      cond = GbaBin.u8(data, off + 1),
      at = romPtr(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.CALL_IF then
    local dest = romPtr(data, off + 2)
    local body
    if dest and depth < Script.MAX_CALL then
      body = Script.parse(data, dest, depth + 1)
    end
    return {
      op = "call_if",
      cond = GbaBin.u8(data, off + 1),
      body = body,
    }, size, nextOff
  end
  if cmd == Script.CALL then
    local dest = romPtr(data, off + 1)
    local body
    if dest and depth < Script.MAX_CALL then
      body = Script.parse(data, dest, depth + 1)
    end
    return { op = "call", body = body }, size, nextOff
  end
  if cmd == Script.CALLSTD then
    return { op = "callstd", id = GbaBin.u8(data, off + 1) }, size, nextOff
  end
  if cmd == Script.LOADWORD then
    return { op = "loadword", text = readText(data, romPtr(data, off + 2)) },
      size, nextOff
  end
  if cmd == Script.MESSAGE then
    return { op = "message", text = readText(data, romPtr(data, off + 1)) },
      size, nextOff
  end
  if cmd == Script.SETFLAG then
    return { op = "setflag", flag = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.CLEARFLAG then
    return { op = "clearflag", flag = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.CHECKFLAG then
    return { op = "checkflag", flag = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.SETVAR then
    return {
      op = "setvar",
      var = GbaBin.u16(data, off + 1),
      val = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.SETORCOPYVAR or cmd == Script.COPYVAR then
    return {
      op = "setorcopyvar",
      var = GbaBin.u16(data, off + 1),
      val = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.COMPARE_VAR_VALUE then
    return {
      op = "compare",
      var = GbaBin.u16(data, off + 1),
      val = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.COMPARE_VAR_VAR then
    return {
      op = "compare_vars",
      var = GbaBin.u16(data, off + 1),
      other = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.GOTOSTD then
    return { op = "gotostd", id = GbaBin.u8(data, off + 1) }, size, nextOff
  end
  if cmd == Script.ADDVAR then
    return {
      op = "addvar",
      var = GbaBin.u16(data, off + 1),
      val = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.SUBVAR then
    return {
      op = "subvar",
      var = GbaBin.u16(data, off + 1),
      val = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.SPECIALVAR then
    return {
      op = "specialvar",
      var = GbaBin.u16(data, off + 1),
      id = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.ADDITEM or cmd == Script.REMOVEITEM
      or cmd == Script.CHECKITEM or cmd == Script.CHECKITEMSPACE then
    local name = "checkitem"
    if cmd == Script.ADDITEM then name = "additem"
    elseif cmd == Script.REMOVEITEM then name = "removeitem"
    elseif cmd == Script.CHECKITEMSPACE then name = "checkitemspace" end
    return {
      op = name,
      item = GbaBin.u16(data, off + 1),
      count = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.GETPARTYSIZE then
    return { op = "getpartysize" }, size, nextOff
  end
  if cmd == Script.ADDDECORATION then
    return {
      op = "adddecoration",
      id = GbaBin.u16(data, off + 1),
    }, size, nextOff
  end
  if cmd == Script.GETPLAYERXY then
    return {
      op = "getplayerxy",
      x = GbaBin.u16(data, off + 1),
      y = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.CHECKTRAINERFLAG then
    return { op = "checktrainerflag", id = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.SETTRAINERFLAG then
    return { op = "settrainerflag", id = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.CLEARTRAINERFLAG then
    return { op = "cleartrainerflag", id = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.RANDOM then
    return { op = "random", limit = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.ADDMONEY or cmd == Script.REMOVEMONEY
      or cmd == Script.CHECKMONEY then
    local name = "checkmoney"
    if cmd == Script.ADDMONEY then name = "addmoney"
    elseif cmd == Script.REMOVEMONEY then name = "removemoney" end
    return {
      op = name,
      amount = GbaBin.u32(data, off + 1),
      ignore = GbaBin.u8(data, off + 5),
    }, size, nextOff
  end
  if cmd == Script.SHOWMONEYBOX then
    return {
      op = "showmoneybox",
      x = GbaBin.u8(data, off + 1),
      y = GbaBin.u8(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.HIDEMONEYBOX then
    return {
      op = "hidemoneybox",
      x = GbaBin.u8(data, off + 1),
      y = GbaBin.u8(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.UPDATEMONEYBOX then
    return {
      op = "updatemoneybox",
      x = GbaBin.u8(data, off + 1),
      y = GbaBin.u8(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.GETPRICEREDUCTION then
    return { op = "getpricereduction", index = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.PLAYSLOTMACHINE then
    return { op = "playslotmachine", id = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.CHECKCOINS then
    return { op = "checkcoins", var = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.ADDCOINS or cmd == Script.REMOVECOINS then
    local name = "addcoins"
    if cmd == Script.REMOVECOINS then name = "removecoins" end
    return { op = name, count = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.SETWILDBATTLE then
    return {
      op = "setwildbattle",
      species = GbaBin.u16(data, off + 1),
      level = GbaBin.u8(data, off + 3),
      item = GbaBin.u16(data, off + 4),
    }, size, nextOff
  end
  if cmd == Script.DOWILDBATTLE then
    return { op = "dowildbattle" }, size, nextOff
  end
  if cmd == Script.SHOWCOINSBOX then
    return {
      op = "showcoinsbox",
      x = GbaBin.u8(data, off + 1),
      y = GbaBin.u8(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.HIDECOINSBOX then
    return {
      op = "hidecoinsbox",
      x = GbaBin.u8(data, off + 1),
      y = GbaBin.u8(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.UPDATECOINSBOX then
    return {
      op = "updatecoinsbox",
      x = GbaBin.u8(data, off + 1),
      y = GbaBin.u8(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.PLAYMONCRY then
    return {
      op = "playmoncry",
      species = GbaBin.u16(data, off + 1),
      mode = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.WAITMONCRY then
    return { op = "waitmoncry" }, size, nextOff
  end
  if cmd == Script.BUFFERSPECIESNAME then
    return {
      op = "bufferspecies",
      slot = GbaBin.u8(data, off + 1),
      species = GbaBin.u16(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.BUFFERITEMNAME then
    return {
      op = "bufferitem",
      slot = GbaBin.u8(data, off + 1),
      item = GbaBin.u16(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.BUFFERDECORATIONNAME then
    return {
      op = "bufferdecoration",
      slot = GbaBin.u8(data, off + 1),
      id = GbaBin.u16(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.BUFFERNUMBER then
    return {
      op = "buffernumber",
      slot = GbaBin.u8(data, off + 1),
      val = GbaBin.u16(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.WAITDOORANIM then
    return { op = "waitdooranim" }, size, nextOff
  end
  if cmd == Script.INCREMENTGAMESTAT then
    return { op = "incrementgamestat", id = GbaBin.u8(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.TRAINERBATTLE then
    local kind = GbaBin.u8(data, off + 1)
    local trainerId = GbaBin.u16(data, off + 2)
    local intro, defeat, cannot
    local ptrBase = off + TRAINER_BATTLE_HEAD
    if kind == 3 then
      defeat = readText(data, romPtr(data, ptrBase))
    else
      intro = readText(data, romPtr(data, ptrBase))
      defeat = readText(data, romPtr(data, ptrBase + 4))
      -- gTrainerBattleSpecs_2 / _4: kinds 4, 6, 7, 8 load
      -- sTrainerCannotBattleSpeech from the 3rd pointer.
      if kind == 4 or kind == 6 or kind == 7 or kind == 8 then
        cannot = readText(data, romPtr(data, ptrBase + 8))
      end
    end
    return {
      op = "trainerbattle",
      kind = kind,
      trainerId = trainerId,
      intro = intro,
      defeat = defeat,
      cannot = cannot,
      after = parseTrainerAfter(data, kind, ptrBase, depth),
    }, size, nextOff
  end
  if cmd == Script.GIVEMON then
    return {
      op = "givemon",
      species = GbaBin.u16(data, off + 1),
      level = GbaBin.u8(data, off + 3),
      item = GbaBin.u16(data, off + 4),
    }, size, nextOff
  end
  if cmd == Script.GIVEEGG then
    return {
      op = "giveegg",
      species = GbaBin.u16(data, off + 1),
    }, size, nextOff
  end
  if cmd == Script.BUFFERLEADMON then
    return { op = "bufferleadmon", slot = GbaBin.u8(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.CHECKPARTYMOVE then
    return { op = "checkpartymove", move = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.BUFFERPARTYMONNICK then
    return {
      op = "bufferpartymonnick",
      slot = GbaBin.u8(data, off + 1),
      partyIndex = GbaBin.u16(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.BUFFERMOVENAME then
    return {
      op = "buffermovename",
      slot = GbaBin.u8(data, off + 1),
      move = GbaBin.u16(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.CHOOSECONTESTMON then
    return { op = "choosecontestmon" }, size, nextOff
  end
  if cmd == Script.STARTCONTEST then
    return { op = "startcontest" }, size, nextOff
  end
  if cmd == Script.SHOWCONTESTRESULTS then
    return { op = "showcontestresults" }, size, nextOff
  end
  if cmd == Script.SHOWCONTESTWINNER then
    return {
      op = "showcontestwinner",
      contestId = GbaBin.u8(data, off + 1),
    }, size, nextOff
  end
  if cmd == Script.YESNOBOX then
    return {
      op = "yesno",
      x = GbaBin.u8(data, off + 1),
      y = GbaBin.u8(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.MULTICHOICE then
    return {
      op = "multichoice",
      x = GbaBin.u8(data, off + 1),
      y = GbaBin.u8(data, off + 2),
      list = GbaBin.u8(data, off + 3),
      ignoreB = GbaBin.u8(data, off + 4),
    }, size, nextOff
  end
  if cmd == Script.MULTICHOICEDEFAULT then
    return {
      op = "multichoice",
      x = GbaBin.u8(data, off + 1),
      y = GbaBin.u8(data, off + 2),
      list = GbaBin.u8(data, off + 3),
      default = GbaBin.u8(data, off + 4),
      ignoreB = GbaBin.u8(data, off + 5),
    }, size, nextOff
  end
  if cmd == Script.MULTICHOICEGRID then
    return {
      op = "multichoice",
      x = GbaBin.u8(data, off + 1),
      y = GbaBin.u8(data, off + 2),
      list = GbaBin.u8(data, off + 3),
      perRow = GbaBin.u8(data, off + 4),
      ignoreB = GbaBin.u8(data, off + 5),
    }, size, nextOff
  end
  if cmd == Script.SPECIAL then
    return { op = "special", id = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.DELAY then
    return { op = "delay", frames = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.WAITSTATE then
    return { op = "waitstate" }, size, nextOff
  end
  if cmd == Script.FADESCREEN then
    return { op = "fadescreen", mode = GbaBin.u8(data, off + 1) }, size, nextOff
  end
  -- 0x98 is fadescreenspeed here; MOVE_LEVITATE is movement-only.
  if cmd == 0x98 then
    return {
      op = "fadescreen",
      mode = GbaBin.u8(data, off + 1),
      speed = GbaBin.u8(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.WARP or cmd == Script.WARPSILENT
      or cmd == Script.WARPDOOR or cmd == Script.WARPTELEPORT then
    return {
      op = "warp",
      mapGroup = GbaBin.u8(data, off + 1),
      mapNum = GbaBin.u8(data, off + 2),
      warpId = GbaBin.u8(data, off + 3),
      x = GbaBin.u16(data, off + 4),
      y = GbaBin.u16(data, off + 6),
    }, size, nextOff
  end
  if cmd == Script.SETDYNAMICWARP or cmd == Script.SETWARP
      or cmd == Script.SETHOLEWARP or cmd == Script.SETDIVEWARP
      or cmd == Script.SETESCAPEWARP then
    local name = "setdynamicwarp"
    if cmd == Script.SETWARP then name = "setwarp"
    elseif cmd == Script.SETHOLEWARP then name = "setholewarp"
    elseif cmd == Script.SETDIVEWARP then name = "setdivewarp"
    elseif cmd == Script.SETESCAPEWARP then name = "setescapewarp" end
    return {
      op = name,
      mapGroup = GbaBin.u8(data, off + 1),
      mapNum = GbaBin.u8(data, off + 2),
      warpId = GbaBin.u8(data, off + 3),
      x = GbaBin.u16(data, off + 4),
      y = GbaBin.u16(data, off + 6),
    }, size, nextOff
  end
  if cmd == Script.WARPHOLE then
    return {
      op = "warphole",
      mapGroup = GbaBin.u8(data, off + 1),
      mapNum = GbaBin.u8(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.DOFIELDEFFECT then
    return { op = "dofieldeffect", id = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.SETFIELDEFFECTARGUMENT then
    return {
      op = "setfieldeffectargument",
      index = GbaBin.u8(data, off + 1),
      value = GbaBin.u16(data, off + 2),
    }, size, nextOff
  end
  if cmd == Script.WAITFIELDEFFECT then
    return { op = "waitfieldeffect", id = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.SETRESPAWN then
    return { op = "setrespawn", id = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.PLAYSE then
    return { op = "playse", id = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.WAITSE then
    return { op = "waitse" }, size, nextOff
  end
  if cmd == Script.PLAYFANFARE then
    return { op = "playfanfare", id = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.WAITFANFARE then
    return { op = "waitfanfare" }, size, nextOff
  end
  if cmd == Script.PLAYBGM then
    return {
      op = "playbgm",
      id = GbaBin.u16(data, off + 1),
      save = GbaBin.u8(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.SAVEBGM then
    return { op = "savebgm", id = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.FADEDEFAULTBGM then
    return { op = "fadedefaultbgm" }, size, nextOff
  end
  -- The three fade commands carry a speed in units the driver counts down
  -- per frame; 0 means the default.
  if cmd == Script.FADENEWBGM then
    return { op = "fadenewbgm", id = GbaBin.u16(data, off + 1) }, size, nextOff
  end
  if cmd == Script.FADEOUTBGM then
    return { op = "fadeoutbgm", speed = GbaBin.u8(data, off + 1) }, size, nextOff
  end
  if cmd == Script.FADEINBGM then
    return { op = "fadeinbgm", speed = GbaBin.u8(data, off + 1) }, size, nextOff
  end
  if cmd == Script.WAITMESSAGE then
    return { op = "waitmessage" }, size, nextOff
  end
  if cmd == Script.WAITBUTTON then
    return { op = "waitbuttonpress" }, size, nextOff
  end
  if cmd == Script.CLOSEMESSAGE then
    return { op = "closemessage" }, size, nextOff
  end
  if cmd == Script.APPLYMOVEMENT then
    local dest = romPtr(data, off + 3)
    return {
      op = "applymovement",
      localId = GbaBin.u16(data, off + 1),
      steps = dest and Script.parseMovement(data, dest) or {},
    }, size, nextOff
  end
  if cmd == Script.WAITMOVEMENT then
    return { op = "waitmovement", localId = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.REMOVEOBJECT or cmd == 0x54 then
    return { op = "removeobject", localId = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.ADDOBJECT or cmd == 0x56 then
    return { op = "addobject", localId = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.SETOBJECTXY then
    return {
      op = "setobjectxy",
      localId = GbaBin.u16(data, off + 1),
      x = GbaBin.u16(data, off + 3),
      y = GbaBin.u16(data, off + 5),
    }, size, nextOff
  end
  if cmd == Script.SETOBJECTXYPERM then
    return {
      op = "setobjectxyperm",
      localId = GbaBin.u16(data, off + 1),
      x = GbaBin.u16(data, off + 3),
      y = GbaBin.u16(data, off + 5),
    }, size, nextOff
  end
  if cmd == Script.MOVEOBJECTOFFSCREEN then
    return {
      op = "moveobjectoffscreen",
      localId = GbaBin.u16(data, off + 1),
    }, size, nextOff
  end
  if cmd == Script.SETOBJECTMOVEMENTTYPE then
    return {
      op = "setobjectmovementtype",
      localId = GbaBin.u16(data, off + 1),
      movementType = GbaBin.u8(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.CHECKPLAYERGENDER then
    return { op = "checkplayergender" }, size, nextOff
  end
  if cmd == Script.SHOWOBJECTAT then
    return {
      op = "showobject",
      localId = GbaBin.u16(data, off + 1),
      mapGroup = GbaBin.u8(data, off + 3),
      mapNum = GbaBin.u8(data, off + 4),
    }, size, nextOff
  end
  if cmd == Script.HIDEOBJECTAT then
    return {
      op = "hideobject",
      localId = GbaBin.u16(data, off + 1),
      mapGroup = GbaBin.u8(data, off + 3),
      mapNum = GbaBin.u8(data, off + 4),
    }, size, nextOff
  end
  if cmd == Script.FACEPLAYER then
    return { op = "faceplayer" }, size, nextOff
  end
  if cmd == Script.TURNOBJECT then
    return {
      op = "turnobject",
      localId = GbaBin.u16(data, off + 1),
      dir = GbaBin.u8(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.SETMETATILE then
    return {
      op = "setmetatile",
      x = GbaBin.u16(data, off + 1),
      y = GbaBin.u16(data, off + 3),
      tile = GbaBin.u16(data, off + 5),
      collision = GbaBin.u16(data, off + 7),
    }, size, nextOff
  end
  if cmd == Script.RESETWEATHER then
    return { op = "resetweather" }, size, nextOff
  end
  if cmd == Script.SETWEATHER then
    return { op = "setweather", weather = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.DOWEATHER then
    return { op = "doweather" }, size, nextOff
  end
  if cmd == Script.SETSTEPCALLBACK then
    return { op = "setstepcallback", id = GbaBin.u8(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.SETMAPLAYOUTINDEX then
    return { op = "setmaplayoutindex", index = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.SETFLASHRADIUS then
    return { op = "setflashradius", level = GbaBin.u16(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.ANIMATEFLASH then
    return { op = "animateflash", level = GbaBin.u8(data, off + 1) },
      size, nextOff
  end
  if cmd == Script.OPENDOOR or cmd == Script.SETDOOROPEN then
    return {
      op = "opendoor",
      x = GbaBin.u16(data, off + 1),
      y = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.CLOSEDOOR or cmd == Script.SETDOORCLOSED then
    return {
      op = "closedoor",
      x = GbaBin.u16(data, off + 1),
      y = GbaBin.u16(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.POKEMART or cmd == Script.POKEMART_DECORATION
      or cmd == Script.POKEMART_DECORATION2 then
    local dest = romPtr(data, off + 1)
    local op = "pokemart"
    if cmd ~= Script.POKEMART then op = "pokemartdecoration" end
    return {
      op = op,
      items = dest and Script.parseMartList(data, dest) or {},
    }, size, nextOff
  end
  if cmd == Script.SETBERRYTREE then
    return {
      op = "setberrytree",
      tree = GbaBin.u8(data, off + 1),
      berry = GbaBin.u8(data, off + 2),
      stage = GbaBin.u8(data, off + 3),
    }, size, nextOff
  end
  if cmd == Script.LOCKALL then
    return { op = "lockall" }, size, nextOff
  end
  if cmd == Script.LOCK then
    return { op = "lock" }, size, nextOff
  end
  if cmd == Script.RELEASEALL then
    return { op = "releaseall" }, size, nextOff
  end
  if cmd == Script.RELEASE then
    return { op = "release" }, size, nextOff
  end
  if cmd == Script.SETOBJECTPRIORITY then
    return {
      op = "setobjectpriority",
      localId = GbaBin.u16(data, off + 1),
      mapGroup = GbaBin.u8(data, off + 3),
      mapNum = GbaBin.u8(data, off + 4),
      priority = GbaBin.u8(data, off + 5),
    }, size, nextOff
  end
  if cmd == Script.RESETOBJECTPRIORITY then
    return {
      op = "resetobjectpriority",
      localId = GbaBin.u16(data, off + 1),
      mapGroup = GbaBin.u8(data, off + 3),
      mapNum = GbaBin.u8(data, off + 4),
    }, size, nextOff
  end
  return { op = "nop" }, size, nextOff
end

function Script.parse(data, start, depth)
  if type(data) ~= "string" or type(start) ~= "number" then return nil end
  depth = depth or 0
  local byOff = {}
  local queue = { start }
  local n = 0
  while #queue > 0 and n < Script.MAX_OPS do
    local off = table.remove(queue)
    if type(off) == "number" and not byOff[off] then
      local op, size, follow = decode(data, off, depth)
      if op then
        byOff[off] = op
        n = n + 1
        if op.at then queue[#queue + 1] = op.at end
        if follow then queue[#queue + 1] = follow end
      end
    end
  end
  local offs = {}
  for off, op in pairs(byOff) do
    if op.op ~= "nop" then offs[#offs + 1] = off end
  end
  if #offs < 1 then return nil end
  table.sort(offs)
  local indexOf = {}
  local ops = {}
  for i = 1, #offs do
    local op = byOff[offs[i]]
    if op.op ~= "nop" then
      ops[#ops + 1] = op
      indexOf[offs[i]] = #ops
    end
  end
  local function resolve(off)
    if type(off) ~= "number" then return #ops + 1 end
    if indexOf[off] then return indexOf[off] end
    for i = 1, #offs do
      if offs[i] >= off and indexOf[offs[i]] then return indexOf[offs[i]] end
    end
    return #ops + 1
  end
  for i = 1, #ops do
    local op = ops[i]
    if op.op == "goto" or op.op == "goto_if" then
      op.to = resolve(op.at)
      op.at = nil
    end
  end
  -- Offsets are sorted, so a goto to an earlier shared label (Petalburg
  -- EnterRoom at 0x154BA8, before Accuracy and every later door) becomes
  -- ops[1]. Run must start at the requested entry, not the lowest address.
  ops.entry = resolve(start)
  if ops.entry < 1 or ops.entry > #ops then ops.entry = 1 end
  return ops
end

-- Cached ruby27 IR has no .entry. Those door scripts start with the
-- shared closemessage/warp prefix and goto 1; the real start is lockall.
function Script.entryOf(ops)
  if type(ops) ~= "table" then return 1 end
  local marked = tonumber(ops.entry)
  if marked and marked >= 1 and marked <= #ops then return marked end
  local first = ops[1]
  if not first or (first.op ~= "closemessage" and first.op ~= "delay") then
    return 1
  end
  local targetsOne, lockAt = false, nil
  for i = 1, #ops do
    local op = ops[i]
    if op and (op.op == "goto" or op.op == "goto_if") and (op.to or 0) == 1 then
      targetsOne = true
    end
    if not lockAt and op and (op.op == "lockall" or op.op == "lock") then
      lockAt = i
    end
  end
  if targetsOne and lockAt and lockAt > 1 then return lockAt end
  return 1
end

function Script.firstText(ops)
  if type(ops) ~= "table" then return nil end
  for i = 1, #ops do
    local op = ops[i]
    if op and (op.op == "loadword" or op.op == "message") and op.text then
      return op.text
    end
  end
end

local function getVar(vars, id)
  id = tonumber(id) or 0
  if id < Script.VARS_START then return id end
  return (vars and vars[id]) or 0
end

-- pokeruby Std_FindItem / EventScript_PickUpItem: after a successful
-- additem, removeobject VAR_LAST_TALKED so the ball stays gone.
local function removeLastTalked(host, vars)
  if not host.removeObject then return end
  local last = 0
  if host.varGet then
    last = host:varGet(Script.VAR_LAST_TALKED) or 0
  else
    last = getVar(vars, Script.VAR_LAST_TALKED)
  end
  if last ~= 0 then host:removeObject(last) end
end

function Script.varGet(vars, id)
  return getVar(vars, id)
end

local function setVar(vars, dest, src)
  if src >= Script.VARS_START then
    vars[dest] = getVar(vars, src)
  else
    vars[dest] = src
  end
end

local function wrap16(n)
  n = math.floor(tonumber(n) or 0) % 65536
  if n < 0 then n = n + 65536 end
  return n
end

function Script.run(host, ops, from)
  if not host or type(ops) ~= "table" then return false end
  host.scriptVars = host.scriptVars or {}
  host.flags = host.flags or {}
  local vars = host.scriptVars
  local i = from or Script.entryOf(ops)
  local loaded = host._scriptLoaded
  local result = host._scriptCmp or 0
  local steps = 0
  local said = false
  local function pauseYesNo()
    host._scriptLoaded = loaded
    host._scriptCmp = result
    host._scriptPause = { ops = ops, at = i + 1 }
    return said, "yesno"
  end
  while i >= 1 and i <= #ops and steps < Script.MAX_OPS do
    steps = steps + 1
    local op = ops[i]
    if not op or op.op == "end" then break end
    if op.op == "goto" then
      i = op.to or (i + 1)
    elseif op.op == "goto_if" then
      if Script.condJump(op.cond, result) then
        i = op.to or (i + 1)
      else
        i = i + 1
      end
    elseif op.op == "call" then
      if op.body then
        local innerSaid, pause = Script.run(host, op.body)
        if innerSaid then said = true end
        if pause then
          host._scriptReturn = host._scriptReturn or {}
          host._scriptReturn[#host._scriptReturn + 1] = {
            ops = ops, at = i + 1, loaded = loaded, result = result,
          }
          return said, pause
        end
      end
      i = i + 1
    elseif op.op == "call_if" then
      if Script.condJump(op.cond, result) and op.body then
        local innerSaid, pause = Script.run(host, op.body)
        if innerSaid then said = true end
        if pause then
          host._scriptReturn = host._scriptReturn or {}
          host._scriptReturn[#host._scriptReturn + 1] = {
            ops = ops, at = i + 1, loaded = loaded, result = result,
          }
          return said, pause
        end
      end
      i = i + 1
    elseif op.op == "loadword" then
      loaded = op.text
      i = i + 1
    elseif op.op == "message" then
      loaded = op.text or loaded
      i = i + 1
    elseif op.op == "bufferleadmon" then
      if host.bufferLeadMonSpecies then
        host:bufferLeadMonSpecies(op.slot or 0)
      end
      i = i + 1
    elseif op.op == "checkpartymove" then
      local slot = 6
      if host.checkPartyMove then
        slot = tonumber(host:checkPartyMove(op.move or 0)) or 6
      end
      vars[Script.VAR_RESULT] = slot
      i = i + 1
    elseif op.op == "bufferpartymonnick" then
      local idx = host.varGet and host:varGet(op.partyIndex or 0)
        or getVar(vars, op.partyIndex or 0)
      if host.bufferPartyMonNick then
        host:bufferPartyMonNick(op.slot or 0, idx)
      end
      i = i + 1
    elseif op.op == "buffermovename" then
      local move = host.varGet and host:varGet(op.move or 0)
        or getVar(vars, op.move or 0)
      if host.bufferMoveName then
        host:bufferMoveName(op.slot or 0, move)
      end
      i = i + 1
    elseif op.op == "yesno" then
      if loaded and host.sayScript then host:sayScript(loaded); said = true end
      host._scriptYesNo = { x = op.x, y = op.y }
      return pauseYesNo()
    elseif op.op == "multichoice" then
      local labels
      if host.multichoiceLabels then
        labels = host:multichoiceLabels(op.list or 0)
      end
      if type(labels) ~= "table" or #labels < 1 then
        if host.setScriptVar then
          host:setScriptVar(Script.VAR_RESULT, 127)
        else
          vars[Script.VAR_RESULT] = 127
        end
        i = i + 1
      else
        local cursor = op.default or 0
        if cursor < 0 or cursor >= #labels then cursor = 0 end
        host._scriptChoice = {
          labels = labels,
          cursor = cursor,
          ignoreB = (op.ignoreB or 0) ~= 0,
          x = op.x,
          y = op.y,
          perRow = op.perRow,
        }
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "choice"
      end
    elseif op.op == "callstd" or op.op == "gotostd" then
      local id = op.id or 0
      local jump = op.op == "gotostd"
      local function afterStd()
        if jump then return #ops + 1 end
        return i + 1
      end
      if id == Script.STD_OBTAIN_ITEM or id == Script.STD_FIND_ITEM then
        local item = getVar(vars, Script.VAR_0x8000)
        local n = getVar(vars, Script.VAR_0x8001)
        if n < 1 then n = 1 end
        local ok = false
        if item > 0 and host.addItem then
          ok = host:addItem(item, n) and true or false
        end
        if host.setScriptVar then
          host:setScriptVar(Script.VAR_RESULT, ok and 1 or 0)
        else
          vars[Script.VAR_RESULT] = ok and 1 or 0
        end
        if host.sayScript then
          local name = host.itemName and host:itemName(item)
            or ("ITEM %d"):format(item)
          local player = host.playerName and host:playerName() or "PLAYER"
          if not ok then
            host:sayScript("The BAG is full...")
          elseif id == Script.STD_FIND_ITEM then
            host:sayScript(("%s found one %s!"):format(player, name))
          else
            host:sayScript(("Obtained the %s."):format(name))
          end
          -- obtain_item.inc Text_PutItemInPocket after a successful
          -- obtain or pick-up. Full bag skips it (VAR_RESULT 0).
          if ok then
            if host.playObtainFanfare then
              host:playObtainFanfare(item)
            elseif host.playFanfare then
              host:playFanfare(host.MUS_OBTAIN_ITEM or 370)
            end
            local pocket = host.itemPocket and host:itemPocket(item) or 1
            local pocketName = host.pocketName and host:pocketName(pocket)
              or "ITEMS"
            host:sayScript(("%s put away the %s\nin the %s POCKET."):format(
              player, name, pocketName))
          end
          said = true
        end
        if ok and id == Script.STD_FIND_ITEM then
          removeLastTalked(host, vars)
        end
        i = afterStd()
      elseif id == Script.STD_OBTAIN_DECORATION then
        local decor = getVar(vars, Script.VAR_0x8000)
        local ok = false
        if decor > 0 and host.addDecoration then
          ok = host:addDecoration(decor) and true or false
        end
        vars[Script.VAR_RESULT] = ok and 1 or 0
        if host.setScriptVar then
          host:setScriptVar(Script.VAR_RESULT, ok and 1 or 0)
        end
        if host.sayScript then
          local name = host.decorationName and host:decorationName(decor)
            or ("DECOR %d"):format(decor)
          if ok then
            if host.playFanfare then
              host:playFanfare(host.MUS_OBTAIN_ITEM or 370)
            end
            host:sayScript(("Obtained the %s!"):format(name))
            host:sayScript(("The %s was transferred to the PC."):format(name))
          else
            host:sayScript("There's no more room for decorations.")
          end
          said = true
        end
        i = afterStd()
      elseif id == Script.STD_MSGBOX_YESNO then
        if loaded and host.sayScript then host:sayScript(loaded); said = true end
        host._scriptYesNo = { x = 20, y = 8 }
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = afterStd() }
        return said, "yesno"
      elseif id == Script.STD_MSGBOX_SIGN or id == Script.STD_MSGBOX_DEFAULT then
        if loaded and host.sayScript then host:sayScript(loaded); said = true end
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = afterStd() }
        return said, "msg"
      elseif id >= Script.STD_MSGBOX_NPC and id <= Script.STD_MSGBOX_AUTOCLOSE then
        if loaded and host.sayScript then host:sayScript(loaded); said = true end
        i = afterStd()
      else
        i = afterStd()
      end
    elseif op.op == "setflag" then
      if op.flag then host.flags[op.flag] = true end
      i = i + 1
    elseif op.op == "clearflag" then
      if op.flag then host.flags[op.flag] = nil end
      if host.trySpawnByFlag then host:trySpawnByFlag(op.flag) end
      i = i + 1
    elseif op.op == "checkflag" then
      result = (op.flag and host.flags[op.flag]) and 1 or 0
      i = i + 1
    elseif op.op == "setvar" then
      vars[op.var] = op.val or 0
      i = i + 1
    elseif op.op == "addvar" then
      vars[op.var] = wrap16((vars[op.var] or 0) + (op.val or 0))
      i = i + 1
    elseif op.op == "subvar" then
      local sub = host.varGet and host:varGet(op.val) or getVar(vars, op.val)
      vars[op.var] = wrap16((vars[op.var] or 0) - sub)
      i = i + 1
    elseif op.op == "setorcopyvar" then
      local src = op.val or 0
      if host.varGet then
        vars[op.var] = host:varGet(src)
      else
        setVar(vars, op.var, src)
      end
      i = i + 1
    elseif op.op == "compare" then
      local a = host.varGet and host:varGet(op.var) or getVar(vars, op.var)
      local b = op.val or 0
      if a < b then result = 0 elseif a == b then result = 1 else result = 2 end
      i = i + 1
    elseif op.op == "compare_vars" then
      local a = host.varGet and host:varGet(op.var) or getVar(vars, op.var)
      local b = host.varGet and host:varGet(op.other) or getVar(vars, op.other)
      if a < b then result = 0 elseif a == b then result = 1 else result = 2 end
      i = i + 1
    elseif op.op == "special" then
      if host.runSpecial then host:runSpecial(op.id or 0) end
      -- ShowEasyChatScreen (and other SetMainCallback2 specials) have no
      -- waitstate; pause here so the script cannot compare RESULT early.
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "specialvar" then
      local v = 0
      if host.runSpecial then v = tonumber(host:runSpecial(op.id or 0)) or 0 end
      vars[op.var] = wrap16(v)
      i = i + 1
    elseif op.op == "checkitem" then
      local item = host.varGet and host:varGet(op.item) or getVar(vars, op.item)
      local n = host.varGet and host:varGet(op.count) or getVar(vars, op.count)
      local have = 0
      if host.itemCount then have = host:itemCount(item) or 0 end
      vars[Script.VAR_RESULT] = (have >= n) and 1 or 0
      i = i + 1
    elseif op.op == "checkitemspace" then
      vars[Script.VAR_RESULT] = 1
      i = i + 1
    elseif op.op == "additem" then
      local item = host.varGet and host:varGet(op.item) or getVar(vars, op.item)
      local n = host.varGet and host:varGet(op.count) or getVar(vars, op.count)
      local ok = false
      if item > 0 and n > 0 and host.addItem then ok = host:addItem(item, n) end
      vars[Script.VAR_RESULT] = ok and 1 or 0
      i = i + 1
    elseif op.op == "adddecoration" then
      local id = host.varGet and host:varGet(op.id) or getVar(vars, op.id)
      local ok = false
      if id > 0 and host.addDecoration then ok = host:addDecoration(id) end
      vars[Script.VAR_RESULT] = ok and 1 or 0
      if host.setScriptVar then
        host:setScriptVar(Script.VAR_RESULT, ok and 1 or 0)
      end
      i = i + 1
    elseif op.op == "removeitem" then
      local item = host.varGet and host:varGet(op.item) or getVar(vars, op.item)
      local n = host.varGet and host:varGet(op.count) or getVar(vars, op.count)
      local ok = false
      if host.takeItem then ok = host:takeItem(item, n) end
      vars[Script.VAR_RESULT] = ok and 1 or 0
      i = i + 1
    elseif op.op == "getpartysize" then
      vars[Script.VAR_RESULT] = type(host.party) == "table" and #host.party or 0
      i = i + 1
    elseif op.op == "getplayerxy" then
      vars[op.x] = host.playerX or 0
      vars[op.y] = host.playerY or 0
      i = i + 1
    elseif op.op == "trainerbattle" then
      local started, refuse
      if host.scriptTrainerBattle then
        started, refuse = host:scriptTrainerBattle(op)
      end
      if started then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        if type(op.after) == "table" then
          -- EventScript_GoToBeatenScript / gotobeatenscript.
          -- parse sorts by ROM offset, so a goto into a shared common
          -- script can make ops[1] the bag-full line. Start at .entry.
          host._scriptPause = { ops = op.after, at = Script.entryOf(op.after) }
        else
          -- SINGLE_NO_INTRO gotopostbattlescript, or no 3rd pointer.
          host._scriptPause = { ops = ops, at = i + 1 }
        end
        if host.beginScriptWait then host:beginScriptWait() end
        return said, "wait"
      end
      -- EventScript_NotEnoughMonsForDoubleBattle: show the 3rd pointer
      -- and end. Falling through would run the post-battle talk.
      if type(refuse) == "string" and refuse ~= "" then
        if host.sayScript then
          host:sayScript(refuse)
          said = true
        end
        break
      end
      i = i + 1
    elseif op.op == "checktrainerflag" then
      local id = host.varGet and host:varGet(op.id) or getVar(vars, op.id)
      result = (host.flags[Script.TRAINER_FLAG_START + id]) and 1 or 0
      i = i + 1
    elseif op.op == "settrainerflag" then
      local id = host.varGet and host:varGet(op.id) or getVar(vars, op.id)
      host.flags[Script.TRAINER_FLAG_START + id] = true
      i = i + 1
    elseif op.op == "cleartrainerflag" then
      local id = host.varGet and host:varGet(op.id) or getVar(vars, op.id)
      host.flags[Script.TRAINER_FLAG_START + id] = nil
      i = i + 1
    elseif op.op == "random" then
      local limit = host.varGet and host:varGet(op.limit) or getVar(vars, op.limit)
      if limit < 1 then
        vars[Script.VAR_RESULT] = 0
      else
        vars[Script.VAR_RESULT] = math.floor(math.random() * limit)
      end
      i = i + 1
    elseif op.op == "addmoney" or op.op == "removemoney" then
      if (op.ignore or 0) == 0 and type(host.money) == "number" then
        local delta = op.amount or 0
        if op.op == "removemoney" then delta = -delta end
        local n = (host.money or 0) + delta
        if n < 0 then n = 0 end
        if n > Script.MAX_MONEY then n = Script.MAX_MONEY end
        host.money = n
      end
      i = i + 1
    elseif op.op == "checkmoney" then
      if (op.ignore or 0) == 0 then
        vars[Script.VAR_RESULT] = ((host.money or 0) >= (op.amount or 0)) and 1 or 0
      end
      i = i + 1
    elseif op.op == "showmoneybox" then
      if host.showMoneyBox then host:showMoneyBox(op.x or 0, op.y or 0) end
      i = i + 1
    elseif op.op == "hidemoneybox" then
      if host.hideMoneyBox then host:hideMoneyBox() end
      i = i + 1
    elseif op.op == "updatemoneybox" then
      if host.updateMoneyBox then host:updateMoneyBox() end
      i = i + 1
    elseif op.op == "getpricereduction" then
      local kind = op.index or 0
      if host.varGet then
        kind = host:varGet(kind)
      else
        kind = getVar(vars, kind)
      end
      local ok = host.getPriceReduction and host:getPriceReduction(kind)
      vars[Script.VAR_RESULT] = (ok and ok ~= 0) and 1 or 0
      i = i + 1
    elseif op.op == "playslotmachine" then
      local id = op.id or 0
      if host.varGet then
        id = host:varGet(id)
      else
        id = getVar(vars, id)
      end
      if host.playSlotMachine then host:playSlotMachine(id) end
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "checkcoins" then
      local n = host.getCoins and host:getCoins() or (tonumber(host.coins) or 0)
      if host.setScriptVar then
        host:setScriptVar(op.var or 0, n)
      else
        vars[op.var or 0] = n
      end
      i = i + 1
    elseif op.op == "setwildbattle" then
      if host.setWildBattle then
        host:setWildBattle(op.species or 0, op.level or 1, op.item or 0)
      end
      i = i + 1
    elseif op.op == "dowildbattle" then
      if host.doWildBattle then host:doWildBattle() end
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "addcoins" or op.op == "removecoins" then
      local n = host.varGet and host:varGet(op.count) or getVar(vars, op.count)
      local r = 1
      if op.op == "addcoins" then
        if host.addCoinsScript then
          r = host:addCoinsScript(n)
        elseif host.addCoins then
          r = host:addCoins(n) and 0 or 1
        end
      else
        if host.removeCoinsScript then
          r = host:removeCoinsScript(n)
        elseif host.removeCoins then
          r = host:removeCoins(n) and 0 or 1
        end
      end
      vars[Script.VAR_RESULT] = r
      i = i + 1
    elseif op.op == "showcoinsbox" then
      if host.showCoinsBox then host:showCoinsBox(op.x or 0, op.y or 0) end
      i = i + 1
    elseif op.op == "hidecoinsbox" then
      if host.hideCoinsBox then host:hideCoinsBox() end
      i = i + 1
    elseif op.op == "updatecoinsbox" then
      if host.updateCoinsBox then host:updateCoinsBox() end
      i = i + 1
    elseif op.op == "playmoncry" then
      local species = op.species or 0
      local mode = op.mode or 0
      if host.varGet then
        species = host:varGet(species)
        mode = host:varGet(mode)
      else
        if species >= Script.VARS_START then species = getVar(vars, species) end
        if mode >= Script.VARS_START then mode = getVar(vars, mode) end
      end
      if host.playMonCry then host:playMonCry(species, mode) end
      i = i + 1
    elseif op.op == "waitmoncry" then
      if host.waitMonCry then host:waitMonCry() end
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "bufferspecies" then
      local species = host.varGet and host:varGet(op.species) or getVar(vars, op.species)
      local name = host.speciesName and host:speciesName(species) or ""
      if host.setStringVar then host:setStringVar((op.slot or 0) + 1, name) end
      i = i + 1
    elseif op.op == "bufferitem" then
      local item = host.varGet and host:varGet(op.item) or getVar(vars, op.item)
      local name = host.itemName and host:itemName(item) or ""
      if host.setStringVar then host:setStringVar((op.slot or 0) + 1, name) end
      i = i + 1
    elseif op.op == "bufferdecoration" then
      local id = host.varGet and host:varGet(op.id) or getVar(vars, op.id)
      local name = host.decorationName and host:decorationName(id) or ""
      if host.setStringVar then host:setStringVar((op.slot or 0) + 1, name) end
      i = i + 1
    elseif op.op == "buffernumber" then
      local n = host.varGet and host:varGet(op.val) or getVar(vars, op.val)
      if host.setStringVar then host:setStringVar((op.slot or 0) + 1, tostring(n)) end
      i = i + 1
    elseif op.op == "waitdooranim" then
      if host.doorAnimating and host:doorAnimating() then
        local d = host.doorAnim
        local left = (d.dur or 0) - (d.t or 0)
        if left < 0 then left = 0 end
        local frames = math.ceil(left * 60)
        if frames < 1 then frames = 1 end
        if host.startScriptDelay then host:startScriptDelay(frames) end
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i }
        return said, "delay"
      end
      i = i + 1
    elseif op.op == "incrementgamestat" then
      if host.incrementGameStat then
        host:incrementGameStat(op.id or 0)
      else
        host.gameStats = host.gameStats or {}
        local id = op.id or 0
        host.gameStats[id] = wrap16((host.gameStats[id] or 0) + 1)
      end
      i = i + 1
    elseif op.op == "givemon" then
      local species = op.species or 0
      if species >= Script.VARS_START then species = getVar(vars, species) end
      if species > 0 and host.giveMon then
        local ok = host:giveMon(species, op.level or 5, op.item)
        if ok and host.sayScript then
          local name = host.speciesName and host:speciesName(species)
            or ("POKeMON %d"):format(species)
          host:sayScript(("Got %s!"):format(name))
          said = true
        end
      end
      i = i + 1
    elseif op.op == "giveegg" then
      local species = op.species or 0
      if species >= Script.VARS_START then
        species = host.varGet and host:varGet(species) or getVar(vars, species)
      end
      local sent = 2
      if species > 0 and host.giveEgg then
        local r = host:giveEgg(species)
        if type(r) == "number" then sent = r end
      end
      vars[Script.VAR_RESULT] = sent
      if host.setScriptVar then host:setScriptVar(Script.VAR_RESULT, sent) end
      i = i + 1
    elseif op.op == "choosecontestmon" then
      if host.chooseContestMon then host:chooseContestMon() end
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "startcontest" then
      if host.startContest then host:startContest() end
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "showcontestresults" then
      if host.showContestResults then host:showContestResults() end
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "showcontestwinner" then
      if host.showContestWinnerPainting then
        host:showContestWinnerPainting(op.contestId or 0)
      end
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "applymovement" then
      if host.applyMovement then
        local id = op.localId or 0
        if host.varGet then
          id = host:varGet(id)
        else
          id = getVar(vars, id)
        end
        host:applyMovement(id, op.steps or {})
      end
      i = i + 1
    elseif op.op == "waitmovement" then
      if host.scriptMoving and host:scriptMoving() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i }
        return said, "move"
      end
      i = i + 1
    elseif op.op == "delay" or op.op == "fadescreen" then
      local frames = op.frames
      if op.op == "fadescreen" then
        frames = host.FADE_FRAMES or 16
        if host.beginScreenFade then host:beginScreenFade(op.mode) end
      end
      if host.delayLeft == nil and host.startScriptDelay then
        host:startScriptDelay(frames or 0)
      end
      if host.scriptDelaying and host:scriptDelaying() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i }
        return said, "delay"
      end
      host.delayLeft = nil
      i = i + 1
    elseif op.op == "waitstate" then
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "warp" then
      local x, y = op.x or 0, op.y or 0
      if x >= Script.VARS_START then x = getVar(vars, x) end
      if y >= Script.VARS_START then y = getVar(vars, y) end
      if host.scriptWarp then
        host:scriptWarp(op.mapGroup or 0, op.mapNum or 0,
          op.warpId or 0xFF, x, y)
      end
      i = i + 1
    elseif op.op == "setdynamicwarp" then
      local x, y = op.x or 0, op.y or 0
      if x >= Script.VARS_START then x = getVar(vars, x) end
      if y >= Script.VARS_START then y = getVar(vars, y) end
      if host.setDynamicWarp then
        host:setDynamicWarp(op.mapGroup or 0, op.mapNum or 0,
          op.warpId or 0xFF, x, y)
      end
      i = i + 1
    elseif op.op == "setholewarp" then
      local x, y = op.x or 0, op.y or 0
      if x >= Script.VARS_START then x = getVar(vars, x) end
      if y >= Script.VARS_START then y = getVar(vars, y) end
      if host.setHoleWarp then
        host:setHoleWarp(op.mapGroup or 0, op.mapNum or 0,
          op.warpId or 0xFF, x, y)
      end
      i = i + 1
    elseif op.op == "setdivewarp" then
      local x, y = op.x or 0, op.y or 0
      if x >= Script.VARS_START then x = getVar(vars, x) end
      if y >= Script.VARS_START then y = getVar(vars, y) end
      if host.setDiveWarp then
        host:setDiveWarp(op.mapGroup or 0, op.mapNum or 0,
          op.warpId or 0xFF, x, y)
      end
      i = i + 1
    elseif op.op == "warphole" then
      if host.warpHole then
        host:warpHole(op.mapGroup or 0, op.mapNum or 0)
      end
      i = i + 1
    elseif op.op == "setescapewarp" then
      local x, y = op.x or 0, op.y or 0
      if x >= Script.VARS_START then x = getVar(vars, x) end
      if y >= Script.VARS_START then y = getVar(vars, y) end
      if host.setEscapeWarp then
        host:setEscapeWarp(op.mapGroup or 0, op.mapNum or 0,
          op.warpId or 0xFF, x, y)
      end
      i = i + 1
    elseif op.op == "setfieldeffectargument" then
      local value = op.value or 0
      if host.varGet then
        value = host:varGet(value)
      elseif value >= Script.VARS_START then
        value = getVar(vars, value)
      end
      if host.setFieldEffectArgument then
        host:setFieldEffectArgument(op.index or 0, value)
      end
      i = i + 1
    elseif op.op == "dofieldeffect" then
      local id = op.id or 0
      if host.varGet then
        id = host:varGet(id)
      elseif id >= Script.VARS_START then
        id = getVar(vars, id)
      end
      if host.doFieldEffect then host:doFieldEffect(id) end
      i = i + 1
    elseif op.op == "waitfieldeffect" then
      local id = op.id or 0
      if host.varGet then
        id = host:varGet(id)
      elseif id >= Script.VARS_START then
        id = getVar(vars, id)
      end
      if host.waitFieldEffect then host:waitFieldEffect(id) end
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "setrespawn" then
      local id = op.id or 0
      if id >= Script.VARS_START then id = getVar(vars, id) end
      if host.setHealLocation then host:setHealLocation(id) end
      i = i + 1
    elseif op.op == "hideobject" then
      local id = op.localId or 0
      if id >= Script.VARS_START then id = getVar(vars, id) end
      if host.hideObject then
        host:hideObject(id, op.mapGroup, op.mapNum)
      end
      i = i + 1
    elseif op.op == "showobject" then
      local id = op.localId or 0
      if id >= Script.VARS_START then id = getVar(vars, id) end
      if host.showObject then
        host:showObject(id, op.mapGroup, op.mapNum)
      end
      i = i + 1
    elseif op.op == "removeobject" then
      local id = op.localId or 0
      if host.varGet then
        id = host:varGet(id)
      elseif id >= Script.VARS_START then
        id = getVar(vars, id)
      end
      if host.removeObject then host:removeObject(id) end
      i = i + 1
    elseif op.op == "addobject" then
      local id = op.localId or 0
      if id >= Script.VARS_START then id = getVar(vars, id) end
      if host.addObject then host:addObject(id) end
      i = i + 1
    elseif op.op == "setobjectxy" then
      local id = op.localId or 0
      local x, y = op.x or 0, op.y or 0
      if id >= Script.VARS_START then id = getVar(vars, id) end
      if x >= Script.VARS_START then x = getVar(vars, x) end
      if y >= Script.VARS_START then y = getVar(vars, y) end
      if host.setObjectXY then host:setObjectXY(id, x, y) end
      i = i + 1
    elseif op.op == "setobjectxyperm" then
      local id = op.localId or 0
      local x, y = op.x or 0, op.y or 0
      if id >= Script.VARS_START then id = getVar(vars, id) end
      if x >= Script.VARS_START then x = getVar(vars, x) end
      if y >= Script.VARS_START then y = getVar(vars, y) end
      if host.setObjectXYPerm then host:setObjectXYPerm(id, x, y) end
      i = i + 1
    elseif op.op == "setobjectmovementtype" then
      local id = op.localId or 0
      if id >= Script.VARS_START then id = getVar(vars, id) end
      if host.setObjectMovementType then
        host:setObjectMovementType(id, op.movementType or 0)
      end
      i = i + 1
    elseif op.op == "setobjectpriority" then
      local id = op.localId or 0
      if host.varGet then
        id = host:varGet(id)
      elseif id >= Script.VARS_START then
        id = getVar(vars, id)
      end
      if host.setObjectPriority then
        host:setObjectPriority(id, op.priority or 0, op.mapGroup, op.mapNum)
      end
      i = i + 1
    elseif op.op == "resetobjectpriority" then
      local id = op.localId or 0
      if host.varGet then
        id = host:varGet(id)
      elseif id >= Script.VARS_START then
        id = getVar(vars, id)
      end
      if host.resetObjectPriority then
        host:resetObjectPriority(id, op.mapGroup, op.mapNum)
      end
      i = i + 1
    elseif op.op == "moveobjectoffscreen" then
      local id = op.localId or 0
      if host.varGet then
        id = host:varGet(id)
      elseif id >= Script.VARS_START then
        id = getVar(vars, id)
      end
      if host.moveObjectOffscreen then host:moveObjectOffscreen(id) end
      i = i + 1
    elseif op.op == "checkplayergender" then
      local gender = 0
      if type(host.gender) == "number" then gender = host.gender end
      vars[Script.VAR_RESULT] = gender
      i = i + 1
    elseif op.op == "turnobject" then
      local id = op.localId or 0
      if id >= Script.VARS_START then id = getVar(vars, id) end
      if host.turnObject then host:turnObject(id, op.dir or 1) end
      i = i + 1
    elseif op.op == "faceplayer" then
      if host.faceScriptNpc then host:faceScriptNpc() end
      i = i + 1
    elseif op.op == "setmetatile" then
      local x, y = op.x or 0, op.y or 0
      if x >= Script.VARS_START then x = getVar(vars, x) end
      if y >= Script.VARS_START then y = getVar(vars, y) end
      local tile = op.tile or 0
      if tile >= Script.VARS_START then tile = getVar(vars, tile) end
      if host.setMetatile then
        host:setMetatile(x, y, tile, op.collision or 0)
      end
      i = i + 1
    elseif op.op == "setweather" then
      local w = op.weather or 0
      if host.varGet then
        w = host:varGet(w)
      elseif w >= Script.VARS_START then
        w = getVar(vars, w)
      end
      if host.setSav1Weather then host:setSav1Weather(w) end
      i = i + 1
    elseif op.op == "resetweather" then
      if host.resetWeather then host:resetWeather() end
      i = i + 1
    elseif op.op == "doweather" then
      if host.doCurrentWeather then host:doCurrentWeather() end
      i = i + 1
    elseif op.op == "setflashradius" then
      local level = op.level or 0
      if host.varGet then
        level = host:varGet(level)
      elseif level >= Script.VARS_START then
        level = getVar(vars, level)
      end
      if host.setFlashLevel then host:setFlashLevel(level) end
      i = i + 1
    elseif op.op == "animateflash" then
      local level = op.level or 0
      if host.animateFlash then
        host:animateFlash(level)
      elseif host.setFlashLevel then
        host:setFlashLevel(level)
      end
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "closemessage" then
      if host.closeField then host:closeField() end
      i = i + 1
    elseif op.op == "waitmessage" then
      if loaded and host.sayScript then
        host:sayScript(loaded)
        said = true
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "msg"
      end
      i = i + 1
    elseif op.op == "waitbuttonpress" then
      if not (host.waitButton or host._waitButtonDone) then
        if host.waitButtonPress then host:waitButtonPress() end
      end
      if host.waitButton
          or (host.scriptWaiting and host:scriptWaiting()) then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i }
        return said, "wait"
      end
      host._waitButtonDone = nil
      i = i + 1
    elseif op.op == "pokemart" or op.op == "pokemartdecoration" then
      local list = op.items
      local kind
      if op.op == "pokemartdecoration" then kind = "decor" end
      if host.openMartList then
        host:openMartList(list, kind)
      elseif host.openMart then
        host:openMart({ mart = list })
      end
      host._scriptLoaded = loaded
      host._scriptCmp = result
      host._scriptPause = { ops = ops, at = i + 1 }
      return said, "mart"
    elseif op.op == "opendoor" then
      local x, y = op.x or 0, op.y or 0
      if x >= Script.VARS_START then x = getVar(vars, x) end
      if y >= Script.VARS_START then y = getVar(vars, y) end
      if host.openDoor then host:openDoor(x, y) end
      i = i + 1
    elseif op.op == "closedoor" then
      local x, y = op.x or 0, op.y or 0
      if x >= Script.VARS_START then x = getVar(vars, x) end
      if y >= Script.VARS_START then y = getVar(vars, y) end
      if host.closeDoor then host:closeDoor(x, y) end
      i = i + 1
    elseif op.op == "setstepcallback" then
      if host.setStepCallback then host:setStepCallback(op.id or 0) end
      i = i + 1
    elseif op.op == "setmaplayoutindex" then
      local id = op.index or 0
      if host.varGet then
        id = host:varGet(id)
      elseif id >= Script.VARS_START then
        id = getVar(vars, id)
      end
      if host.setMapLayoutIndex then host:setMapLayoutIndex(id) end
      i = i + 1
    elseif op.op == "setberrytree" then
      if host.plantBerryTree then
        host:plantBerryTree(op.tree or 0, op.berry or 0, op.stage or 0, false)
      end
      i = i + 1
    elseif op.op == "lockall" then
      if host.lockScriptNpcs then host:lockScriptNpcs(true) end
      i = i + 1
    elseif op.op == "lock" then
      if host.lockScriptNpcs then host:lockScriptNpcs(false) end
      i = i + 1
    elseif op.op == "releaseall" or op.op == "release" then
      if host.unlockScriptNpcs then host:unlockScriptNpcs() end
      i = i + 1
    elseif op.op == "playse" then
      if host.playSe then host:playSe(op.id) end
      i = i + 1
    elseif op.op == "waitse" then
      if host.waitSe then host:waitSe() end
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "playfanfare" then
      if host.playFanfare then host:playFanfare(op.id) end
      i = i + 1
    elseif op.op == "waitfanfare" then
      if host.waitFanfare then host:waitFanfare() end
      if host.scriptWaiting and host:scriptWaiting() then
        host._scriptLoaded = loaded
        host._scriptCmp = result
        host._scriptPause = { ops = ops, at = i + 1 }
        return said, "wait"
      end
      i = i + 1
    elseif op.op == "playbgm" then
      -- The second operand asks the driver to remember the outgoing song so
      -- fadedefaultbgm can bring it back.
      if host.playSong then
        if (op.save or 0) ~= 0 and host.saveBgm then host:saveBgm() end
        host:playSong(op.id, true)
      end
      i = i + 1
    elseif op.op == "savebgm" then
      if host.saveBgm then host:saveBgm(op.id) end
      i = i + 1
    elseif op.op == "fadedefaultbgm" then
      if host.fadeDefaultBgm then host:fadeDefaultBgm() end
      i = i + 1
    elseif op.op == "fadenewbgm" then
      if host.playSong then host:playSong(op.id, true) end
      i = i + 1
    elseif op.op == "fadeoutbgm" then
      if host.fadeOutMapMusic then
        host:fadeOutMapMusic((op.speed or 0) ~= 0 and op.speed * 4 or nil)
      end
      i = i + 1
    elseif op.op == "fadeinbgm" then
      if host.fadeDefaultBgm then host:fadeDefaultBgm() end
      i = i + 1
    else
      i = i + 1
    end
  end
  host._scriptLoaded = loaded
  host._scriptCmp = result
  host._scriptPause = nil
  return said
end

return Script
