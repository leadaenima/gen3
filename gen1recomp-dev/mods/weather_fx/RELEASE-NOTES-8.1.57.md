# Weather FX 8.1.57 — 2D Gale Relocation Tornado

Built directly from exact Weather FX 8.1.56.

## What changed

- **2D Gale now has a tornado carry presentation.** In flat 2D Weather FX, an approved relocation tornado enters from the left side of the frame and travels continuously to the right.
- **Relocation-only by design.** A 2D tornado never spawns as ambient scenery, never roams the screen, and never appears just because Gale is active. Weather FX resolves the carry roll and a valid previously visited destination first. If either fails, nothing is drawn.
- **Visited-map safety is retained.** Destinations still use Tornado's existing escape-safe landing checks, exclude the current map, respect Surf requirements, and are restricted to maps already recorded as visited.
- **The tornado visibly takes the player.** Player movement is locked during the short event. The guarded map transfer fires while the funnel is covering the player near screen centre; the same funnel then continues off the right edge on the destination map.
- **GALE only.** STRONG WINDS, SANDSTORM, DUSTSTORM and other windy weather cannot create the 2D relocation tornado.
- **Player CARRY CHANCE applies.** OFF suppresses the event completely; other carry-chance settings control whether the relocation event is selected.
- **One animation clock.** Funnel animation is advanced only by Tornado.update. Draw.lua now only submits Funnel.draw, removing the historical simulation+compositor double tick.

## Preserved

The strict 3D world-space tornado system is unchanged: persistent roaming funnels, waterspouts, contact/seeker carry behavior, safe visited-map relocation and guarded landing rules remain intact. 8.1.56 battle precipitation handoff, 8.1.55 world-anchored snow motion and 8.1.54 GPU precipitation virtualization remain preserved.
