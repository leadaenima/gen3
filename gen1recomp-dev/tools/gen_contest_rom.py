#!/usr/bin/env python3
"""Bake pokeruby contest_moves / opponents / strings into Lua tables."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(r"C:\Users\Feces\Desktop\pokeruby-master\pokeruby-master")
OUT = Path(__file__).resolve().parents[1] / "src" / "data" / "contest_rom.lua"


def parse_defines(path: Path, prefix: str) -> dict[str, int]:
    out: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(rf"#define\s+({re.escape(prefix)}\w+)\s+(.+)", line)
        if not m:
            continue
        name, val = m.group(1), m.group(2).strip()
        val = val.split("//")[0].strip()
        if val.startswith("("):
            continue
        try:
            out[name] = int(val, 0)
        except ValueError:
            if val in out:
                out[name] = out[val]
    return out


def parse_enum(path: Path, start_name: str) -> dict[str, int]:
    text = path.read_text(encoding="utf-8", errors="replace")
    m = re.search(rf"enum\s*\{{([^}}]*?{start_name}[^}}]*)\}}", text, re.S)
    if not m:
        raise SystemExit(f"enum {start_name} not found in {path}")
    n = 0
    out: dict[str, int] = {}
    for raw in m.group(1).split(","):
        raw = raw.strip()
        if not raw or raw.startswith("//"):
            continue
        raw = raw.split("//")[0].strip()
        if "=" in raw:
            name, val = [p.strip() for p in raw.split("=", 1)]
            n = int(val, 0)
            out[name] = n
            n += 1
        else:
            out[raw] = n
            n += 1
    return out


def lua_str(s: str) -> str:
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{s}"'


def english_macros(path: Path, prefix: str) -> dict[str, str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    block = text
    m = re.search(r"#if defined\(ENGLISH\)(.*?)#elif defined\(GERMAN\)", text, re.S)
    if m:
        block = m.group(1)
    out: dict[str, str] = {}
    for m in re.finditer(
        rf'#define\s+({re.escape(prefix)}\w+)\s+"([^"]*)"', block
    ):
        out[m.group(1)] = m.group(2)
    return out


def main() -> None:
    moves = parse_defines(ROOT / "include" / "constants" / "moves.h", "MOVE_")
    species = parse_defines(ROOT / "include" / "constants" / "species.h", "SPECIES_")
    gfx = parse_defines(
        ROOT / "include" / "constants" / "event_objects.h", "OBJ_EVENT_GFX_"
    )
    contest_h = ROOT / "include" / "contest.h"
    effects = parse_enum(contest_h, "CONTEST_EFFECT_HIGHLY_APPEALING")
    combos = parse_enum(contest_h, "COMBO_STARTER_RAIN_DANCE")
    cats = {
        "CONTEST_CATEGORY_COOL": 0,
        "CONTEST_CATEGORY_BEAUTY": 1,
        "CONTEST_CATEGORY_CUTE": 2,
        "CONTEST_CATEGORY_SMART": 3,
        "CONTEST_CATEGORY_TOUGH": 4,
    }
    ranks = {
        "CONTEST_RANK_NORMAL": 0,
        "CONTEST_RANK_SUPER": 1,
        "CONTEST_RANK_HYPER": 2,
        "CONTEST_RANK_MASTER": 3,
    }
    names = {**moves, **species, **gfx, **effects, **combos, **cats, **ranks, "TRUE": 1, "FALSE": 0}

    def resolve(tok: str) -> int:
        tok = tok.strip()
        if tok in names:
            return names[tok]
        return int(tok, 0)

    move_rows: list[tuple[int, int, int, list[int]]] = []
    cm = (ROOT / "src" / "data" / "contest_moves.h").read_text(
        encoding="utf-8", errors="replace"
    )
    body = cm.split("gContestMoves[] = {", 1)[1].split("};", 1)[0]
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        inner = line[1 : line.index("}")]
        parts = inner.split(",", 2)
        effect = resolve(parts[0])
        cat = resolve(parts[1])
        rest = parts[2]
        starter_s, combo_s = rest.split("{", 1)
        starter = resolve(starter_s.replace(",", "").strip() or "0")
        combo_inner = combo_s.split("}", 1)[0]
        combo = [resolve(x) for x in combo_inner.split(",") if x.strip()]
        while len(combo) < 4:
            combo.append(0)
        move_rows.append((effect, cat, starter, combo[:4]))

    effect_rows: list[tuple[int, int, int]] = []
    eb = cm.split("gContestEffects[] = {", 1)[1].split("};", 1)[0]
    for line in eb.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        inner = line[1 : line.index("}")]
        a, b, c = [x.strip() for x in inner.split(",")]
        effect_rows.append((int(a, 0), int(b, 0), int(c, 0)))

    nicks = english_macros(
        ROOT / "src" / "data" / "contest_opponents.h", "CONTEST_OPPONENT_NICKNAME_"
    )
    ots = english_macros(
        ROOT / "src" / "data" / "contest_opponents.h", "CONTEST_OPPONENT_OTNAME_"
    )
    names.update({k: k for k in list(nicks) + list(ots)})

    opp_text = (ROOT / "src" / "data" / "contest_opponents.h").read_text(
        encoding="utf-8", errors="replace"
    )
    opp_body = opp_text.split("gContestOpponents[] = {", 1)[1].rsplit("};", 1)[0]
    opponents: list[dict] = []
    for block in re.split(r"\[CONTEST_OPPONENT_\w+\]\s*=\s*\{", opp_body):
        block = block.strip()
        if ".species" not in block:
            continue

        def field(name: str, default: str = "0") -> str:
            m = re.search(rf"\.{name}\s*=\s*([^,\n]+)", block)
            return (m.group(1) if m else default).strip()

        def boolf(name: str) -> int:
            return 1 if "TRUE" in field(name, "FALSE") else 0

        nick_tok = field("nickname").replace("_(", "").replace(")", "")
        ot_tok = field("trainerName").replace("_(", "").replace(")", "")
        moves_m = re.search(r"\.moves\s*=\s*\{([^}]+)\}", block)
        move_ids = [resolve(x) for x in moves_m.group(1).split(",") if x.strip()]
        while len(move_ids) < 4:
            move_ids.append(0)
        opponents.append(
            {
                "species": resolve(field("species")),
                "nick": nicks.get(nick_tok, nick_tok.strip('"')),
                "trainer": ots.get(ot_tok, ot_tok.strip('"')),
                "gfx": resolve(field("trainerGfxId")),
                "rank": resolve(field("whichRank")),
                "cool_pool": boolf("aiPool_Cool"),
                "beauty_pool": boolf("aiPool_Beauty"),
                "cute_pool": boolf("aiPool_Cute"),
                "smart_pool": boolf("aiPool_Smart"),
                "tough_pool": boolf("aiPool_Tough"),
                "moves": move_ids[:4],
                "cool": int(field("cool"), 0),
                "beauty": int(field("beauty"), 0),
                "cute": int(field("cute"), 0),
                "smart": int(field("smart"), 0),
                "tough": int(field("tough"), 0),
                "sheen": int(field("sheen"), 0),
            }
        )

    en = (ROOT / "src" / "data" / "text" / "contest_en.h").read_text(
        encoding="utf-8", errors="replace"
    )

    def cstr(name: str) -> str:
        m = re.search(
            rf'const u8 {name}\[\] = _\("((?:\\.|[^"\\])*)"', en
        )
        if not m:
            return ""
        s = m.group(1)
        s = s.replace("{PAUSE 60}", "").replace("\\n", "\n")
        s = re.sub(r"\{STR_VAR_(\d)\}", r"$\1", s)
        return s.strip()

    desc_names = [
        "ContestString_DescHighlyAppealing",
        "ContestString_DescStartled1",
        "ContestString_DescGreatLock",
        "ContestString_DescRepeatable",
        "ContestString_DescStartled2",
        "ContestString_DescStartled3",
        "ContestString_DescStartled4",
        "ContestString_DescStartled5",
        "ContestString_DescStartled6",
        "ContestString_DescStartled7",
        "ContestString_DescStartled8",
        "ContestString_DescStartled9",
        "ContestString_DescStartled10",
        "ContestString_DescStartled11",
        "ContestString_DescStartled12",
        "ContestString_DescStartled13",
        "ContestString_DescAttentionShift",
        "ContestString_DescStartled14",
        "ContestString_DescJamOthersMissTurn",
        "ContestString_DescStartled15",
        "ContestString_DescStartled16",
        "ContestString_DescStartled17",
        "ContestString_DescStartled18",
        "ContestString_DescStartled19",
        "ContestString_DescStartled20",
        "ContestString_DescNervousOne",
        "ContestString_DescNervousAllAfter",
        "ContestString_DescConditionWorseBefore",
        "ContestString_DescStartled21",
        "ContestString_DescGreatWhenFirst",
        "ContestString_DescGreatWhenLast",
        "ContestString_DescAppealGoodBeforeAll",
        "ContestString_DescAppealGoodBeforeOne",
        "ContestString_DescBetterWhenLater",
        "ContestString_DescAffectedByTiming",
        "ContestString_DescBetterWhenSameType",
        "ContestString_DescBetterWhenDiffType",
        "ContestString_DescAffectedByFront",
        "ContestString_DescConditionUp",
        "ContestString_DescAffectedByCondition",
        "ContestString_DescAppealEarlier",
        "ContestString_DescAppealLater",
        "ContestString_DescRandomOrderEasier",
        "ContestString_DescRandomOrder",
        "ContestString_DescAnyExcitement",
        "ContestString_DescStartled22",
        "ContestString_DescScaleWithExcitement",
        "ContestString_DescStopExcitement",
    ]
    descs = [cstr(n) for n in desc_names]

    result_keys = [
        ("MORE_CONSCIOUS", "ContestString_MoreConscious"),
        ("NO_APPEAL", "ContestString_NoAppeal"),
        ("SETTLE_DOWN", "ContestString_SettleDown"),
        ("OBLIVIOUS_TO_OTHERS", "ContestString_ObliviousToOthers"),
        ("LESS_AWARE", "ContestString_LessAware"),
        ("STOPPED_CARING", "ContestString_StoppedCaring"),
        ("STARTLE_ATTEMPT", "ContestString_StartleAttempt"),
        ("DAZZLE_ATTEMPT", "ContestString_DazzleAttempt"),
        ("JUDGE_LOOK_AWAY2", "ContestString_JudgeLookAway2"),
        ("UNNERVE_ATTEMPT", "ContestString_UnnerveAttempt"),
        ("NERVOUS", "ContestString_Nervous"),
        ("UNNERVE_WAITING", "ContestString_UnnerveWaiting"),
        ("TAUNT_WELL", "ContestString_TauntWell"),
        ("REGAINED_FORM", "ContestString_RegainedForm"),
        ("JAM_WELL", "ContestString_JamWell"),
        ("HUSTLE_STANDOUT", "ContestString_HustleStandout"),
        ("WORK_HARD_UNNOTICED", "ContestString_WorkHardUnnoticed"),
        ("WORK_BEFORE", "ContestString_WorkBefore"),
        ("APPEAL_NOT_WELL", "ContestString_AppealNotWell"),
        ("WORK_PRECEDING", "ContestString_WorkPreceding"),
        ("APPEAL_NOT_WELL2", "ContestString_AppealNotWell2"),
        ("APPEAL_NOT_SHOWN_WELL", "ContestString_AppealNotShownWell"),
        ("APPEAL_SLIGHTLY_WELL", "ContestString_AppealSlightlyWell"),
        ("APPEAL_PRETTY_WELL", "ContestString_AppealPrettyWell"),
        ("APPEAL_EXCELLENTLY", "ContestString_AppealExcellently"),
        ("APPEAL_DUD", "ContestString_AppealDud"),
        ("APPEAL_NOT_VERY_WELL", "ContestString_AppealNotVeryWell"),
        ("APPEAL_SLIGHTLY_WELL2", "ContestString_AppealSlightlyWell2"),
        ("APPEAL_PRETTY_WELL2", "ContestString_AppealPrettyWell2"),
        ("APPEAL_VERY_WELL", "ContestString_AppealVeryWell"),
        ("APPEAL_EXCELLENTLY2", "ContestString_AppealExcellently2"),
        ("SAME_TYPE_GOOD", "ContestString_SameTypeGood"),
        ("DIFF_TYPE_GOOD", "ContestString_DiffTypeGood"),
        ("STOOD_OUT_AS_MUCH", "ContestString_StoodOutAsMuch"),
        ("NOT_AS_WELL", "ContestString_NotAsWell"),
        ("CONDITION_ROSE", "ContestString_ConditionRose"),
        ("HOT_STATUS", "ContestString_HotStatus"),
        ("MOVE_UP_LINE", "ContestString_MoveUpLine"),
        ("MOVE_BACK_LINE", "ContestString_MoveBackLine"),
        ("SCRAMBLE_ORDER", "ContestString_ScrambleOrder"),
        ("JUDGE_EXPECTANTLY2", "ContestString_JudgeExpectantly2"),
        ("WENT_OVER_WELL", "ContestString_WentOverWell"),
        ("WENT_OVER_VERY_WELL", "ContestString_WentOverVeryWell"),
        ("APPEAL_COMBO_EXCELLENTLY", "ContestString_AppealComboExcellently"),
        ("AVERT_GAZE", "ContestString_AvertGaze"),
        ("AVOID_SEEING", "ContestString_AvoidSeeing"),
        ("NOT_FAZED", "ContestString_NotFazed"),
        ("LITTLE_DISTRACTED", "ContestString_LittleDistracted"),
        ("ATTEMPT_STARTLE", "ContestString_AttemptStartle"),
        ("LOOKED_DOWN", "ContestString_LookedDown"),
        ("TURNED_BACK", "ContestString_TurnedBack"),
        ("UTTER_CRY", "ContestString_UtterCry"),
        ("LEAPT_UP", "ContestString_LeaptUp"),
        ("TRIPPED_OVER", "ContestString_TrippedOver"),
        ("MESSED_UP2", "ContestString_MessedUp2"),
        ("FAILED_TARGET_NERVOUS", "ContestString_FailedTargetNervous"),
        ("FAILED_ANYONE_NERVOUS", "ContestString_FailedAnyoneNervous"),
        ("IGNORED", "ContestString_Ignored"),
        ("NO_CONDITION_IMPROVE", "ContestString_NoConditionImprove"),
        ("BAD_CONDITION_WEAK_APPEAL", "ContestString_BadConditionWeakAppeal"),
        ("UNAFFECTED", "ContestString_Unaffected"),
        ("ATTRACTED_ATTENTION", "ContestString_AttractedAttention"),
        ("DISAPPOINTED_REPEAT", "ContestString_DissapointedRepeat"),
        ("WENT_OVER_GREAT", "ContestString_WentOverGreat"),
        ("DIDNT_GO_WELL", "ContestString_DidntGoWell"),
        ("GOT_CROWD_GOING", "ContestString_GotCrowdGoing"),
        ("CANT_APPEAL_NEXT_TURN", "ContestString_CantAppealNextTurn"),
        ("TOO_NERVOUS", "ContestString_TooNervous"),
        ("APPEALED_WITH", "gText_MonAppealedWithMove"),
    ]
    result_map = {k: cstr(n) for k, n in result_keys}

    lines = [
        "-- Generated from pokeruby contest_moves.h / contest_opponents.h / contest_en.h.",
        "-- Mechanics tables only; no Nintendo graphics.",
        "return {",
        "  moves = {",
    ]
    for e, c, s, combo in move_rows:
        lines.append(
            f"    {{e={e},c={c},s={s},m={{{combo[0]},{combo[1]},{combo[2]},{combo[3]}}}}},"
        )
    lines.append("  },")
    lines.append("  effects = {")
    for t, a, j in effect_rows:
        lines.append(f"    {{t={t},a={a},j={j}}},")
    lines.append("  },")
    lines.append("  opponents = {")
    pools = ("cool_pool", "beauty_pool", "cute_pool", "smart_pool", "tough_pool")
    for o in opponents:
        mv = ",".join(str(x) for x in o["moves"])
        pool = ",".join(str(o[p]) for p in pools)
        lines.append(
            "    {species=%d,nick=%s,trainer=%s,gfx=%d,rank=%d,"
            "pool={%s},moves={%s},cool=%d,beauty=%d,cute=%d,smart=%d,"
            "tough=%d,sheen=%d},"
            % (
                o["species"],
                lua_str(o["nick"]),
                lua_str(o["trainer"]),
                o["gfx"],
                o["rank"],
                pool,
                mv,
                o["cool"],
                o["beauty"],
                o["cute"],
                o["smart"],
                o["tough"],
                o["sheen"],
            )
        )
    lines.append("  },")
    lines.append("  descriptions = {")
    for d in descs:
        lines.append(f"    {lua_str(d)},")
    lines.append("  },")
    lines.append("  strings = {")
    for k, v in result_map.items():
        lines.append(f"    {k} = {lua_str(v)},")
    lines.append("  },")
    lines.append("}")
    lines.append("")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {OUT} moves={len(move_rows)} effects={len(effect_rows)} opp={len(opponents)}")


if __name__ == "__main__":
    main()
