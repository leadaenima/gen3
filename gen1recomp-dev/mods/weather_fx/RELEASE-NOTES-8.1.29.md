# Weather FX 8.1.29 — Connected Flat-World Hydrosphere

8.1.29 is a major water-system rebuild on the live-qualified 8.1.28 World-Scale Realism baseline. It does **not** add more weather names and it makes no mountain/orographic assumptions. The world remains a flat voxel world whose weather character comes from buildings, forests, water, routes, shelter and long horizons.

## Connected 3D water
- Cartridge `isWaterCell` classification remains gameplay authority.
- Visible current/neighbor maps are stitched in canonical world space and four-neighbour water cells become coherent connected bodies.
- Body persistence follows real map+cell identity across root-map transitions, so unrelated maps cannot inherit each other's water state.
- Each body mask is greedily merged into large rectangles and rendered as one coherent mesh instead of exposing the old repeated per-tile water sheet.
- Voxel Realism still owns reflection, depth, sky/world reflection and shoreline terrain. Weather FX replaces only the visible water-surface geometry and fails open to the host draw list if replacement cannot be built.

## Living water physics
- Prevailing Weather FX wind rotates the host water wave trains in both world axes. Shader rebuilds are sector-hysteretic so gust jitter cannot cause compile thrash.
- Wave height responds to wind, body size and ice fraction.
- Rain creates world-space expanding ripple rings on liquid bodies. One shared pool is capped at 48 rings and rendered as one bounded batch.
- Lunar phase drives spring/neap tide strength: new/full moons are strongest, quarter moons weakest. Small inland ponds receive much smaller tides than large/boundary-connected water.
- Tide level returns to the host's normal recessed low-water plane rather than sinking below shoreline geometry and opening a void seam.

## Winter ice
- Water uses body-size thermal inertia and progressive freeze/thaw rather than an instant seasonal texture swap.
- Winter guarantees eventual freezing while local conditions and body size control how quickly it happens.
- Load-bearing ice is continuous, wave-free world geometry and remains depth-tested/lighting-aware.
- Gen1Recomp's documented `movement.collision` hook widens only a vanilla `tile` refusal on a cartridge water cell for the observed player when that body is load-bearing. Bounds/entity blocking remains untouched.
- Normal liquid water and Surf behavior are unchanged. A player already surfing cannot have open water turn into load-bearing ice underneath them.
- Ice cannot thaw out from under a non-Surfing player standing on it; thaw resumes normally once they return to land.
- SnowPack continues rejecting liquid water but can accumulate and create depth/footprints on load-bearing ice.

## Flat-world climate integration
- Frozen water sharply reduces evaporation/humidity contribution and water-fog affinity while retaining a colder local thermal signature.
- Water-related storm ambience follows the liquid fraction through the existing microclimate/acoustic stack.
- No mountain, slope, altitude or orographic weather model was introduced.

## Performance / quality contract
No particle count or visual-quality target is reduced. Connected-water geometry replaces many old surface quads with greedily merged body rectangles; ripple presentation is globally bounded; state persists by body rather than allocating an unbounded simulation grid; and wind shader direction recompiles only on meaningful prevailing-sector changes.
