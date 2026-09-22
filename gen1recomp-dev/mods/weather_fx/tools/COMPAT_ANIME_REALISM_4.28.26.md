# Compat audit — Anime Realism 3.1.9 × Weather FX 4.28.26

## Pipeline ownership (no overlap of systems)

| System | Owner | WX when AR present |
|--------|--------|-------------------|
| Overworld weather / clouds / snow | Weather FX | unchanged |
| Field battle REACT / HUD / toasts | Anime Realism | untouched |
| BattleState.drawTextArea | Anime Realism | WX still uses battle:sayNext only |
| BattleState.draw field-art rectangle hijack | Weather FX normally | **disabled** when AR detected |
| battle.overlay weather particles | Weather FX | drawn **under** AR chrome |
| Weather announce | Weather FX via sayNext | **one short sky line** only |
| SpriteRenderer / mon sheets | Anime Realism | WX does not touch |
| Damage chip / ruleset | Weather FX (settings) | unchanged (no AR weather rules) |

## Code changes
1. `lib/Compat.lua` — detect `anime_realism`, battle profile
2. `BattleField.install` — chain-safe wrap + `uninstall`; skip hijack if AR
3. `battle.overlay` — weather then UI when AR (under UI)
4. `announce` — short single line when AR
5. `BattleDraw.draw` — particle scale ×0.55 when AR

## Static checks (this zip)
- [PASS] Compat.hasAnimeRealism
- [PASS] Compat.battleProfile
- [PASS] BF chain prevDraw
- [PASS] BF uninstall
- [PASS] skipFieldArtHijack
- [PASS] announce short
- [PASS] underUI order
- [PASS] sayNext only path
- [PASS] particleScale
- [PASS] Compat loaded
- [PASS] no SpriteRenderer in main battle path
- [PASS] BD no SpriteRenderer

## Manual smoke test
1. Load WX + anime_realism + voxel
2. Overworld snow/rain still runs
3. Start field battle — AR UI visible, weather thinner behind it
4. Weather text at most one short line via normal box
5. No crash on move / damage / end battle
