# Weather FX 8.1.58 — Tornado Relocation Completion / Waterspout Contact

Built directly from exact Weather FX 8.1.57 (`dc0d295079cb17e645c7a3210b4639358162329859310202da0878c2dff74aa3`).

## What changed

### 2D GALE tornado
- Locks the source camera for the approach/sweep-off rather than allowing normal camera tracking.
- Hides the stationary world copy of the player and replays the actual player sprite inside the moving funnel.
- Sweeps player + funnel off the right edge, then holds a full blackout while the host performs the real map warp.
- Does not release blackout until the destination map id is live.
- Sweeps player + funnel in from the left on the destination, drops the player into normal play, then sends the tornado off the right edge.
- Keeps movement collision-locked for the owned sequence and restores the engine's original player-hide state afterward. Gen I uses `playerHidden`; Gen II preserves/restores its player-only `flyHidden` seam.

### Destination availability
- A visited outdoor map may now derive a landing from a real outdoor connection when Weather FX never observed that map and no safe remembered/Fly point exists.
- Derived cells must be inside the transition edge, non-warp, passable, surface-correct, and pass the same bounded escape flood proof as every other tornado landing.
- One other proven visited destination is sufficient. The former four-map gate prevented relocation without adding a safety proof.

### 3D tornado carry
- Pickup is followed by visible source-map departure, guarded real map transfer, destination-map arrival and gentle landing.
- Public `world:warpTo` receives an `onDone` completion callback; destination map identity is also checked before arrival presentation begins.
- A player who walks into any sufficiently formed ordinary funnel triggers the same guarded relocation, even if that tornado was not selected as the random seeker. The carry-chance setting still controls active hunting behavior.

### Waterspouts
- Tornado surface sampling now consults live map `isWaterCell` authority in addition to the flat interaction cache.
- 3D waterspouts use a broad blue-white contact patch with rotating surface annuli, a dense vertical spray collar and water-heavy ingested debris; the land dirt skirt is suppressed.
- 2D relocation over water uses visible surface rings and spray droplets around the funnel base.

## Safety / preservation
- Destination maps must still be already visited.
- Interior/cave maps and generic warp/door coordinates are still rejected.
- Water landings still require Surf and are revalidated after transfer; the emergency-return path remains.
- Tornadoes remain authored GALE-only in 2D.
- No ROM content is included.

### Live-frame blackout repair

The 2D relocation blackout is now reasserted from `render.hud`, after `Renderer:endFrame()`. The earlier weather-canvas blackout remains as a fallback, but the post-HUD pass is authoritative during map transfer so a newly loaded destination frame cannot overwrite the black screen. The overlay resets transform/scissor/shader state, fills the complete live framebuffer with opaque black, and restores graphics state afterward.
