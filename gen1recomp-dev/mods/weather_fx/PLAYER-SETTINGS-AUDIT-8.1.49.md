# Weather FX 8.1.49 — Full Player Settings Audit

## Scope

This audit treats a setting as a player feature, not merely a schema entry. It checks the menu location, label, value choices, description, live write/persistence path, downstream behavior contracts, and player-visible presentation where the setting has a visual effect.

## Menu architecture

- **68/68** player settings accounted for.
- **11** top-level Weather FX categories.
- Maximum Weather FX depth: **root → category → setting**.
- No submenu contains another settings submenu.
- Every category has an explanatory description.
- Every setting has an explanatory description.
- Long labels were checked against the real Gen1Recomp row renderer; player labels/values fit without requiring unexplained abbreviations.

## Complete setting interaction gate

The exhaustive player-settings suite drives every selectable value through `SettingsMenu.applyOption`, which uses the same save-backed persistence/live-change path as the in-game menu. The audited working tree produced:

- `tests/player_settings_8149_complete_test.lua`: **2020 passed / 0 failed**.
- `tests/settings_runtime_test.lua`: **648 / 648**.
- `tests/settings_advanced_pipeline_test.lua`: **39 / 39**.
- `tests/settings_menu_test.lua`: **32 / 32**.
- `tests/settings_description_complete_test.lua`: **1693 / 1693**.
- `tests/settings_live_chain_test.lua`: **17 / 17**.
- `tools/test_settings_runtime.py`: **245 / 245**.
- complete bounded player-settings program set: **49 / 49 programs**.

A separate real Gen1Recomp host driver loaded Weather FX in Pokémon Yellow and exercised every selectable value in all 68 settings through the loaded mod's own settings API: **314/314 choices passed** for write/readback/save-backed state.

## Real UI visual audit

Using the exact Gen1Recomp 0.2.53 Linux runtime and the user's qualified Pokémon Yellow test ROM, the audit opened the Weather FX root plus every category and captured every one of the 68 setting rows. The row-by-row sweep verified the setting name, current/alternate value presentation, page ownership and help access.

That sweep exposed one integration defect that code-level tests did not: a premium UI skin read `description`/`desc` instead of only `help`, so its always-visible explanation panel could fall back to generic copy. 8.1.49 fixes this by publishing the same authoritative text through all three fields. The real UI was rerun after the repair.

## Real gameplay visual audit

Real Yellow gameplay framebuffer comparisons were captured for settings whose effect can be directly seen in a deterministic short run. These include:

- weather-strength differences;
- 2D versus 3D weather presentation;
- storm-darkness OFF versus HIGH;
- diagnostics OFF versus FULL;
- rain amount changes;
- settled snow OFF versus 500%;
- settled sand OFF versus 500%.

The settled particle probes confirmed the visual toggles are not merely menu state: snow changed from **0 active particles at OFF to 100,000 at 500%**, and sand changed from **0 at OFF to 43,200 at 500%** in the controlled live scene.

## Functional coverage beyond visible particles

The bounded executable audit additionally exercises precipitation virtualization, fog, clouds, fronts, local weather, wind/player interaction, water rendering handoff, rainbows, lightning, NPC strikes, tornado formation/carry safety, day/night, seasons, celestial events, sun rays, battle weather, encounters, legendary events, follower damage, audio authority/indoor muffling, graphics quality and performance controls.

This distinction matters: encounter rules, battle damage rules, frame-rate targets, background-simulation cadence and audio switches cannot all be proven by comparing two screenshots. Their authoritative runtime state/effect paths are therefore tested directly, while their menu rows are still visually inspected in the live game.

## Audio boundary

The test container has no working ALSA/Pulse playback device. Audio settings pass their engine/runtime tests and real menu persistence/readback, including master weather volume, indoor weather audio, thunder enable/volume and wind sounds, but this audit does **not** claim a human listening test from the container.

## Runtime preservation

8.1.49 is built directly from exact 8.1.48. The release delta gate permits runtime differences only in `lib/Settings.lua` and `lib/SettingsMenu.lua`; all other runtime/assets must remain byte-identical to the 8.1.48 runtime baseline before the package can freeze.

## Verdict

The player settings system is release-qualified when the final 8.1.49 runtime-freeze, full inherited suite and exact-package integrity gates all pass. The audit intentionally separates **visual evidence**, **real-host setting persistence**, and **executable system behavior** rather than claiming that a screenshot can prove nonvisual gameplay/audio/performance semantics.
