-- The mod's own settings: the rows on this mod's page in the mod manager,
-- and typed readers for them.
--
-- WHY NOT THE OPTIONS MENU.  The engine gives a render pipeline a row on
-- the main OPTIONS menu for free (label + ladder + persistence), and the
-- WEATHER row is exactly that -- so the one setting the player changes
-- often is one button press from where they already are.  Everything here
-- is a set-once preference (quality, accessibility, whether battles get
-- weather), and putting seven more rows on the main menu to sit unused
-- would be worse for the player than a page in the manager they visit
-- once.  Dramatic Shape's ModSetting mirrors its two onto both menus
-- because they are per-scene settings; these are not.
--
-- Every read goes through mod.options:get, which falls back to the row's
-- declared default, so a fresh install with nothing persisted reads the
-- same values as a configured one and no caller ever needs a `or`.

local V = ...
local mod = V.mod
local Types = V.require("Types")

local Settings = {}

-- Row order is page order.  Choice values are the stored ones; the first
-- element of each pair is what the row shows.
Settings.SCHEMA = {
  {
    key = "quality", label = "GRAPHICS QUALITY", type = "choice", default = "auto",
    choices = { { "AUTO", "auto" }, { "MAX", "max" }, { "HIGH", "high" },
                { "MEDIUM", "medium" }, { "LOW", "low" },
                { "POTATO", "potato" } },
    help = "Sets the overall balance between visual quality and performance. AUTO is recommended for most players and adjusts Weather FX workload to help hold your chosen frame-rate target; MAX through POTATO stay fixed; manual tiers stay exact. The advanced performance settings can override individual areas without changing this master choice.",
  },
  {
    key = "autoPerformance", label = "AUTO ADJUSTMENT", type = "choice", default = "balanced",
    choices = { { "BALANCED", "balanced" }, { "AGGRESSIVE", "aggressive" }, { "OFF", "off" } },
    help = "Used only when GRAPHICS QUALITY is AUTO. BALANCED changes quality gradually, AGGRESSIVE reacts sooner on weak devices, and OFF stops automatic adjustments. Manual graphics-quality levels are never changed by this setting.",
  },
  {
    key = "performanceTarget", label = "TARGET FRAME RATE", type = "choice", default = "60",
    choices = { { "60 FPS", "60" }, { "50 FPS", "50" }, { "40 FPS", "40" }, { "30 FPS", "30" } },
    help = "Sets the frame-rate goal used by automatic performance tuning. A lower target allows Weather FX to keep more visual detail before reducing workload. This does not change game speed, weather duration, or animation timing.",
  },
  {
    key = "textureDetail", label = "TEXTURE DETAIL", type = "choice", default = "quality",
    choices = { { "FOLLOW QUALITY", "quality" }, { "FULL", "full" }, { "HIGH", "high" },
                { "MEDIUM", "medium" }, { "LOW", "low" }, { "MINIMUM", "minimum" } },
    help = "Controls the resolution of Weather FX generated textures, including fog, water, ice, foam, and ripple detail. Lower settings reduce memory and texture-processing cost. FOLLOW QUALITY lets the master graphics setting choose.",
  },
  {
    key = "reflectionDetail", label = "WATER REFLECTIONS", type = "choice", default = "quality",
    choices = { { "FOLLOW QUALITY", "quality" }, { "FULL", "full" }, { "SKY + SUN/MOON", "sky" }, { "SIMPLE", "simple" } },
    help = "Controls how much reflected detail appears on enhanced 3D water. FULL includes nearby world reflections; SKY + SUN/MOON keeps sky and celestial reflections; SIMPLE keeps animated water without reflection processing. FOLLOW QUALITY lets the master graphics setting choose.",
  },
  {
    key = "effectDistance", label = "EFFECT DISTANCE", type = "choice", default = "quality",
    choices = { { "FOLLOW QUALITY", "quality" }, { "FAR", "far" }, { "MEDIUM", "medium" }, { "NEAR", "near" }, { "MINIMUM", "minimum" } },
    help = "Controls how far from the player detailed 3D weather effects are drawn. Lower settings reduce distant visual work while keeping the actual storm and weather system active in the world. FOLLOW QUALITY lets the master graphics setting choose.",
  },
  {
    key = "simulationDetail", label = "BACKGROUND DETAIL", type = "choice", default = "quality",
    choices = { { "FOLLOW QUALITY", "quality" }, { "FULL", "full" }, { "BALANCED", "balanced" }, { "LIGHT", "light" }, { "MINIMUM", "minimum" } },
    help = "Controls how often slower background weather calculations update. Lower settings reduce processor use for distant clouds, local climate, and environmental checks while keeping important nearby weather responsive. FOLLOW QUALITY lets the master graphics setting choose.",
  },
  {
    -- ALWAYS <WEATHER>: the "always snow", "always rain" switch, on the
    -- page a player can reach without a text editor.  `force` in
    -- config.lua does the same job for a folder install; this is the same
    -- setting for the .modpkg case, which is the one that has caught us
    -- out three times now.
    --
    -- ONE ROW RATHER THAN TWENTY SWITCHES, because these are mutually
    -- exclusive by nature: "always snow" and "always rain" cannot both be
    -- true, and twenty independent toggles would let a player set that and
    -- then wonder which one won.  A single-select row cannot express the
    -- contradiction in the first place.
    --
    -- The choices are built from the catalogue below, so adding a weather
    -- type adds its rung here with no second list to keep in step.
    key = "always", label = "WEATHER MODE", type = "choice", default = "auto",
    choices = nil,          -- filled in below
    help = "Chooses the active overworld weather. AUTO lets Weather FX change weather naturally, OFF disables Weather FX weather, and CYCLE rotates weather only while WEATHER FRONTS is OFF. When WEATHER FRONTS is ON, fronts own world weather and CYCLE is suspended. Choosing any named weather makes that condition authoritative and automatically turns WEATHER FRONTS OFF.",
  },
  {
    key = "intensity", label = "WEATHER STRENGTH", type = "choice", default = "normal",
    choices = { { "SOFT", "soft" }, { "NORMAL", "normal" },
                { "HEAVY", "heavy" }, { "AUTO", "auto" } },
    help = "Controls the overall strength of active weather. SOFT = 45%, NORMAL = 100%, and HEAVY = 150% for precipitation and debris; AUTO lets each weather naturally grow and ease over time. Fog has its own separate density setting.",
  },
  {
    key = "rainIntensity", label = "RAIN AMOUNT", type = "choice", default = "100",
    choices = {
      { "OFF", "off" }, { "25%", "25" }, { "50%", "50" }, { "75%", "75" },
      { "100%", "100" }, { "125%", "125" }, { "150%", "150" }, { "200%", "200" },
    },
    help = "Controls the amount of falling rain. OFF removes raindrops but leaves the storm itself, including clouds, wind, lightning, and lighting. Percentage choices change rain density only and combine with WEATHER STRENGTH.",
  },
  {
    key = "snowIntensity", label = "SNOW AMOUNT", type = "choice", default = "100",
    choices = {
      { "OFF", "off" },
      { "10%", "10" },
      { "25%", "25" },
      { "50%", "50" },
      { "75%", "75" },
      { "100%", "100" },
      { "125%", "125" },
      { "150%", "150" },
      { "200%", "200" },
      { "250%", "250" },
      { "300%", "300" },
      { "400%", "400" },
      { "500%", "500" },
    },
    help = "Controls the amount of falling snow. OFF removes snowflakes but leaves the rest of the cold-weather effects active. Higher percentages increase snowfall within the selected graphics and particle limits and combine with WEATHER STRENGTH.",
  },
  {
    key = "snowAccumulation", label = "SNOW ACCUMULATION", type = "choice", default = "on",
    choices = { { "ON", "on" }, { "OFF", "off" } },
    help = "Turns persistent ground snow and footprints on or off without changing falling snow or the active weather. OFF immediately removes existing Weather FX snow banks and prevents new accumulation. ON starts accumulation again from a clean field using the normal snowfall buildup rate.",
  },
  {
    key = "weatherRenderDistance", label = "3D PRECIP DISTANCE", type = "choice", default = "100",
    choices = { { "25%", "25" }, { "50%", "50" }, { "75%", "75" }, { "100%", "100" } },
    help = "Sets the reach of 3D falling rain, snow, hail, sand, and similar precipitation as a percentage of the active voxel render distance. 100% requests the full live render distance; lower values intentionally shorten precipitation for performance. EFFECT DISTANCE and active graphics-quality limits can still cap expensive distant detail, so this is the precipitation-specific distance control rather than a second global distance setting.",
  },
  {
    -- Separate from INTENSITY so players can keep storms heavy without a
    -- thick fog bank (or the reverse). Multiplies fog/veil channels only.
    key = "fogIntensity", label = "FOG DENSITY", type = "choice", default = "100",
    choices = {
      { "OFF", "off" },
      { "10%", "10" },
      { "25%", "25" },
      { "50%", "50" },
      { "100%", "100" },
      { "150%", "150" },
      { "200%", "200" },
      { "250%", "250" },
      { "300%", "300" },
      { "350%", "350" },
      { "400%", "400" },
      { "450%", "450" },
      { "500%", "500" },
    },
    help = "Controls fog and haze density. OFF removes Weather FX fog, low percentages create light mist, and high percentages can create a heavy whiteout. This does not change rain or snow amounts.",
  },
  {
    key = "sandIntensity", label = "SANDSTORM DENSITY", type = "choice", default = "100",
    choices = {
      { "OFF", "off" },
      { "10%", "10" },
      { "25%", "25" },
      { "50%", "50" },
      { "100%", "100" },
      { "150%", "150" },
      { "200%", "200" },
      { "250%", "250" },
      { "300%", "300" },
      { "350%", "350" },
      { "400%", "400" },
      { "450%", "450" },
      { "500%", "500" },
    },
    help = "Controls sandstorm particles and sand haze. OFF removes the sand effect; higher percentages make the storm visually denser without changing its duration or the particle limit.",
  },
  {
    key = "dustIntensity", label = "DUST DENSITY", type = "choice", default = "100",
    choices = {
      { "OFF", "off" },
      { "10%", "10" },
      { "25%", "25" },
      { "50%", "50" },
      { "100%", "100" },
      { "150%", "150" },
      { "200%", "200" },
      { "250%", "250" },
      { "300%", "300" },
      { "350%", "350" },
      { "400%", "400" },
      { "450%", "450" },
      { "500%", "500" },
    },
    help = "Controls dust-storm particles and dust haze. OFF removes the dust effect; higher percentages make the storm visually denser without changing its duration or the particle limit.",
  },
  {
    -- Snow, hail, sleet, sandstorm and ashfall are the weathers Kanto has
    -- no obvious business having, so the built-in region bias suppresses
    -- them hard away from the few maps that argue for them.  That was
    -- tuned for plausibility and it made them effectively invisible: a
    -- player could run AUTO for hours and never see snow.  This row is the
    -- dial between "plausible" and "I would like to see the thing I
    -- installed", and it defaults to the middle rather than to realism.
    key = "exotic", label = "RARE WEATHER", type = "choice", default = "normal",
    choices = { { "OFF", "off" }, { "RARE", "rare" },
                { "NORMAL", "normal" }, { "OFTEN", "often" } },
    help = "Controls how often unusual weather such as snow, hail, sleet, sandstorms, dust storms, and ashfall appears outside places that naturally favor it. OFF removes those conditions from automatic weather; RARE is the most conservative setting.",
  },
  {
    key = "speed", label = "WEATHER DURATION", type = "choice", default = "normal",
    choices = { { "NORMAL", "normal" }, { "2X", "2x" },
                { "4X", "4x" }, { "10X", "10x" }, { "20X", "20x" } },
    help = "Controls how long weather lasts before it expires. NORMAL uses the intended duration; 2X, 4X, 10X, and 20X make weather end that many times sooner. This does not speed up the game, particles, wind, clouds, or weather transitions.",
  },
  {
    key = "daytime", label = "DAY / NIGHT CYCLE", type = "choice", default = "on",
    choices = { { "ON", "on" }, { "OFF", "off" } },
    help = "Turns Weather FX day/night lighting and time-based weather behavior on or off. OFF leaves time-of-day presentation to the game or another compatible mod instead of applying Weather FX day/night changes.",
  },
  {
    -- Seasons were left out of the first design because Gen 1/2 have none
    -- and the region bias already answers "where does it snow".  Players
    -- still asked for a calendar, so this is the opt-in layer on top: four
    -- seasons, a hemisphere flip, and seasonal weight multipliers on AUTO.
    key = "seasons", label = "SEASONS", type = "choice", default = "on",
    choices = { { "ON", "on" }, { "OFF", "off" } },
    help = "Turns the four-season calendar on or off. When enabled, seasons influence automatic weather and seasonal visuals, such as more winter snow and stronger summer sun. The active season follows the selected time source and hemisphere.",
  },
  {
    key = "clouds", label = "3D CLOUDS", type = "choice", default = "on",
    choices = { { "ON", "on" }, { "OFF", "off" } },
    help = "Shows or hides Weather FX 3D cloud banks when a compatible 3D world is active. Turning clouds off does not stop rain, snow, hail, lightning, or other weather systems.",
  },
  {
    key = "cloudHeight", label = "CLOUD HEIGHT", type = "choice", default = "raised",
    choices = { { "HIGH", "raised" }, { "LOW", "original" } },
    help = "Sets the height of Weather FX 3D cloud banks. HIGH uses the raised cloud deck; LOW uses the original lower height. Rain origins, lightning tops, and tornado attachment points move with the selected cloud height.",
  },
  {
    key = "cloudDensity", label = "CLOUD DENSITY", type = "choice", default = "normal",
    choices = { { "LOW", "low" }, { "NORMAL", "normal" }, { "HIGH", "high" }, { "VERY HIGH", "veryhigh" } },
    help = "Controls how densely Weather FX fills the 3D sky with cloud banks. NORMAL exactly preserves the authored weather coverage. LOW opens more sky gaps, while HIGH and VERY HIGH fill more cloud cells and puffs without changing precipitation amount, weather timing, or cloud movement.",
  },
  {
    key = "cloudBankStyle", label = "CLOUD BANK STYLE", type = "choice", default = "volumetric",
    choices = { { "VOLUMETRIC", "volumetric" }, { "BLOCKY", "blocky" } },
    help = "Chooses the shape of Weather FX 3D cloud banks. VOLUMETRIC keeps the rounded atmospheric bank. BLOCKY uses flat, shallow, slightly translucent rectangular cloud tiles with a voxel/pixel silhouette while preserving the same cloud height, density, wind drift, fronts, rain origins, lightning and tornado attachment points.",
  },
  {
    key = "waterStyle", label = "WATER RENDERING", type = "choice", default = "weatherfx",
    choices = { { "ENHANCED", "weatherfx" }, { "ORIGINAL", "original" } },
    help = "Chooses the 3D water renderer. ENHANCED uses Weather FX waves, tides, ripples, freezing and ice, while ORIGINAL returns water presentation to the active 3D world mod. Changing this does not turn weather on or off.",
  },
  {
    key = "leafColor", label = "LEAF COLOR", type = "choice", default = "seasonal",
    choices = {
      { "SEASONAL", "seasonal" },
      { "GREEN", "green" },
      { "YELLOW", "yellow" },
      { "ORANGE", "orange" },
      { "BROWN", "brown" },
    },
    help = "Controls the color of 3D wind-blown leaves. SEASONAL follows the active season; the other choices keep the selected color all year.",
  },
  {
    key = "snowShape", label = "SNOWFLAKE STYLE", type = "choice", default = "flake",
    choices = { { "FLAKE", "flake" }, { "BALL", "ball" } },
    help = "Chooses the shape of 3D snow particles. FLAKE uses six-arm snowflakes and BALL uses soft round snow particles. This changes appearance only, not snowfall amount or speed.",
  },
  {
    key = "hemisphere", label = "SEASON HEMISPHERE", type = "choice",
    default = "northern",
    choices = { { "NORTH", "northern" }, { "SOUTH", "southern" } },
    help = "Chooses which seasonal calendar to use. NORTH uses northern-hemisphere seasons and SOUTH reverses them so December falls in summer. This only matters while SEASONS is on.",
  },
  {
    key = "seasonNotify", label = "SEASON NOTICES", type = "choice",
    default = "on",
    choices = { { "ON", "on" }, { "OFF", "off" } },
    help = "Shows or hides the short season/location notice when entering a map or when the season changes. This does not change the season itself.",
  },
  {
    key = "battles", label = "BATTLE WEATHER", type = "choice", default = "subtle",
    choices = { { "OFF", "off" }, { "SUBTLE", "subtle" }, { "FULL", "full" } },
    help = "Controls battle weather visuals in one place. OFF hides rain, sand, snow, fog, and other Weather FX battle presentation; SUBTLE keeps it lighter so menus remain easy to read; FULL uses the complete visual presentation. WEATHER RULES separately controls battle mechanics.",
  },
  {
    key = "battleDamage", label = "WEATHER RULES", type = "choice",
    default = "on",
    choices = { { "ON", "on" }, { "OFF", "off" } },
    help = "Turns Weather FX battle rules on or off. These rules can include weather damage, type power changes, accuracy changes, Solar Beam behavior, terrain interactions, abilities, and held-item interactions when supported.",
  },
{
    -- The one house rule with a menu row. `terrain` deliberately has none:
    -- it only fires on named maps and contradicts nothing, so it is a config
    -- decision rather than a thing to flip mid-run. Amplified changes how
    -- every primal sky and every sandstorm hits, which is exactly the kind
    -- of thing a player wants to try, dislike, and turn off without editing
    -- a file.
    --
    -- AUTO defers to config.lua (off unless the file says otherwise), so the
    -- row adds a way to answer without taking the file's answer away.
    key = "amplified", label = "AMPLIFIED RULES", type = "choice", default = "auto",
    choices = { { "DEFAULT", "auto" }, { "OFF", "off" }, { "ON", "on" } },
    help = "Optional stronger battle-weather rules. ON makes harsh sun, heavy rain, sandstorms, and hail provide larger battle bonuses than the normal rules; OFF keeps the standard behavior. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "lightning", label = "LIGHTNING", type = "choice", default = "full",
    choices = { { "OFF", "off" }, { "SOFT", "soft" }, { "FULL", "full" } },
    help = "Controls lightning presentation. FULL uses the complete bolt and flash effect, SOFT keeps a gentler glow with less abrupt flashing, and OFF disables Weather FX lightning presentation.",
  },
  {
    key = "weather2dLightning", label = "2D WEATHER LIGHTNING", type = "choice", default = "2d",
    choices = { { "2D BOLTS", "2d" }, { "3D BOLTS", "3d" } },
    help = "Chooses the lightning-bolt style only while WEATHER RENDERING is set to 2D OVERLAY. 2D BOLTS keeps the classic screen-space strike. 3D BOLTS keeps the 2D rain, snow, fog, and other weather overlays but renders lightning as depth-tested world-space bolts when a compatible voxel host is active. 3D weather keeps its normal world-space lightning regardless of this setting.",
  },
  {
    key = "lightningFlash", label = "FLASH BRIGHTNESS", type = "choice", default = "normal",
    choices = { { "OFF", "off" }, { "LOW", "low" }, { "NORMAL", "normal" }, { "HIGH", "high" } },
    help = "Controls only the brightness of the world-light flash caused by lightning. OFF keeps bolts, timing, and thunder but removes the bright flash; LOW, NORMAL, and HIGH change flash brightness without changing strike frequency.",
  },
  {
    key = "lightningFrequency", label = "LIGHTNING FREQUENCY", type = "choice", default = "normal",
    choices = { { "RARE", "rare" }, { "LOW", "low" }, { "NORMAL", "normal" }, { "HIGH", "high" }, { "EXTREME", "extreme" } },
    help = "Controls how often lightning opportunities occur during lightning-capable storms. NORMAL exactly preserves Weather FX's authored strike timing. This changes strike frequency only; bolt quality, flash brightness, thunder volume, and character-strike chance remain separate controls.",
  },
  {
    key = "stormDarkness", label = "STORM DARKNESS", type = "choice", default = "normal",
    choices = { { "OFF", "off" }, { "LOW", "low" }, { "NORMAL", "normal" }, { "HIGH", "high" } },
    help = "Controls how strongly storms darken the Weather FX sky and screen grading. OFF keeps precipitation and clouds without extra storm darkening; LOW is gentler, NORMAL is standard, and HIGH is more dramatic.",
  },
  {
    -- AROUND is the safe default: it uses the documented render.letterbox
    -- hook and cannot contend with anything.  BEHIND additionally patches
    -- BattleState.draw to replace the battle's white field, which is the
    -- only engine internal this mod touches -- opt-in, and it stands down
    -- when another mod is staging battles or SGB colour mode is on.
    key = "backdrops", label = "BACKGROUNDS", type = "choice", default = "around",
    choices = { { "OFF", "off" }, { "AROUND", "around" }, { "BEHIND", "behind" } },
    help = "Controls Weather FX battle scenery. OFF disables it, AROUND fills the side areas around the battle, and BEHIND also places the scenery behind the battlers. This changes presentation only.",
  },
  {
    key = "sfx", label = "WEATHER VOLUME", type = "choice", default = "medium",
    choices = { { "OFF", "off" }, { "LOW", "low" },
                { "MEDIUM", "medium" }, { "HIGH", "high" } },
    help = "Controls the main Weather FX sound volume for rain and storm beds, wind, thunder, and other weather ambience. OFF mutes Weather FX weather sounds; LOW, MEDIUM, and HIGH change their overall loudness.",
  },
  {
    key = "splash", label = "RAIN SPLASHES", type = "choice", default = "on",
    choices = { { "ON", "on" }, { "OFF", "off" } },
    help = "Shows or hides the small splash effects created when rain hits the ground or water. Turning splashes off does not reduce rainfall.",
  },
  {
    key = "indoors", label = "INDOOR LIGHTING", type = "choice", default = "tint",
    choices = { { "OFF", "off" }, { "TINT", "tint" } },
    help = "Controls whether outdoor storm darkness and lightning glow can tint indoor scenes. OFF keeps indoor scenes unaffected by outside storms; TINT allows the indoor lighting response. Rain never falls indoors.",
  },
  {
    -- OFF by default, and the row itself says why.  This is the only
    -- setting in the mod that MOVES THE PLAYER, and a warp does not know
    -- what the story expects: even restricted to places already visited,
    -- being carried mid-errand can strand you without the HM you set out
    -- with, or drop you the wrong side of a gate you have not opened from
    -- that direction.  None of that is fixable here, because "where the
    -- player is supposed to be right now" is a fact only the story knows.
    key = "tornado", label = "TORNADOES", type = "choice", default = "off",
    choices = { { "OFF", "off" }, { "ON", "on" } },
    help = "Turns tornado events on or off during Gale. In 3D, tornadoes roam, become waterspouts over live water, and any mature funnel can pick you up if you walk into it. In 2D, relocation-only tornadoes lock the camera, sweep you off-screen, black out for the real map transfer, then sweep you in from the left and drop you before exiting. Destinations must be visited and escape-safe.",
  },
  {
    key = "tornadoPickup", label = "CARRY CHANCE", type = "choice", default = "normal",
    choices = { { "OFF", "off" }, { "RARE", "rare" }, { "NORMAL", "normal" }, { "FREQUENT", "frequent" } },
    help = "Controls tornado relocation chance. In 3D this controls whether a newly formed eligible tornado actively approaches you; direct physical contact with any mature funnel can still trigger pickup. In 2D it controls whether a relocation-only Gale tornado event occurs at all; if no carry is selected, no 2D tornado is shown.",
  },
  {
    key = "tornadoDuration", label = "TORNADO DURATION", type = "choice", default = "normal",
    choices = { { "SHORT", "short" }, { "NORMAL", "normal" }, { "LONG", "long" } },
    help = "Controls how long a mature roaming 3D tornado remains before naturally dissipating. NORMAL exactly preserves the current authored duration. This does not change cloud descent, formation speed, waterspout conversion, pickup safety, transfer timing, or the final rope-back-to-cloud animation.",
  },
  {
    -- 2D = original Weather FX overlays (fog, rain particles, etc.).
    -- 3D = Dramaless/Potato voxel-pass weather when that host is running.
    -- AUTO = 3D when the host is available, otherwise 2D.
    key = "present", label = "WEATHER RENDERING", type = "choice", default = "auto",
    choices = { { "AUTO", "auto" }, { "2D OVERLAY", "2d" }, { "3D WORLD", "3d" } },
    help = "Chooses how overworld weather is drawn. AUTO uses 3D weather in compatible 3D or first-person views and 2D weather otherwise; 2D OVERLAY forces the classic overlay; 3D WORLD forces the 3D presentation when supported. Battles keep their own weather presentation.",
  },
  {
    key = "pauseMenuWeather", label = "PAUSE MENU WEATHER", type = "choice", default = "animated",
    choices = { { "ANIMATED", "animated" }, { "FROZEN", "frozen" } },
    help = "Controls Weather FX while the START/pause menu and its pause submenus are open. ANIMATED keeps visible weather moving. FROZEN keeps the current weather visible but pauses Weather FX animation until you return to gameplay; weather simulation and scheduling continue in the background.",
  },
  {
    key = "screenEffects", label = "WEATHER SCREEN EFFECTS", type = "choice", default = "full",
    choices = { { "FULL", "full" }, { "REDUCED", "reduced" }, { "OFF", "off" } },
    help = "Controls camera-sized weather flashes, grading, psychic wash, compatibility veils, and glare. FULL exactly preserves the current presentation, REDUCED halves these screen effects, and OFF removes them. World-space rain, snow, clouds, tornadoes, lightning bolts, thunder, fog banks, and physical 3D lighting remain active.",
  },
  {
    key = "celestialRendering", label = "CELESTIAL RENDERING", type = "choice", default = "match",
    choices = { { "MATCH WEATHER", "match" }, { "2D SKY", "2d" }, { "3D WORLD", "3d" } },
    help = "Chooses how the sun, moon, stars, planets, constellations, and other celestial objects are presented in voxel overworlds. MATCH WEATHER follows WEATHER RENDERING. 2D SKY keeps the screen-space celestial style but now projects it from the real voxel camera direction so the sun and moon stay fixed in the world instead of following the camera. 3D WORLD keeps the full world-space celestial system even when WEATHER RENDERING is set to 2D OVERLAY.",
  },
  {
    key = "nightSkyBrightness", label = "NIGHT SKY BRIGHTNESS", type = "choice", default = "normal",
    choices = { { "LOW", "low" }, { "NORMAL", "normal" }, { "HIGH", "high" } },
    help = "Controls the overall visibility of stars, planets, constellations, and the Milky Way while preserving their relative brightness hierarchy. NORMAL exactly preserves the current night sky. This does not brighten the sun, moon, aurora, meteors, clouds, or objects hidden behind weather and world geometry.",
  },
  {
    key = "transitionSpeed", label = "CHANGE SPEED", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "QUICK", "quick" },
                { "NATURAL", "natural" }, { "SLOW", "slow" } },
    help = "Controls how quickly natural weather builds, changes, and clears. QUICK shortens the transition, NATURAL uses the tuned pace, and SLOW makes changes more gradual. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "fronts", label = "WEATHER FRONTS", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Turns large regional weather fronts on or off. ON gives fronts authority over automatic/CYCLE weather, so CYCLE pauses until fronts are turned OFF. Choosing a named WEATHER automatically turns fronts OFF so the player's explicit weather cannot be replaced. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "frontStrength", label = "FRONT REACH", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "GENTLE", "gentle" },
                { "NATURAL", "natural" }, { "STRONG", "strong" }, { "MAX", "max" } },
    help = "Controls how far regional weather tends to continue across neighboring areas. Higher settings make the same weather system persist across more of the connected world. This does not increase particle counts. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "mesoscale", label = "LOCAL WEATHER", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Turns smaller local variations inside a regional weather system on or off. ON allows moving rain bands, cloud breaks, fog pockets, and locally stronger or weaker weather; OFF keeps regional weather more uniform. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "mesoscaleStrength", label = "LOCAL VARIATION", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "SUBTLE", "subtle" },
                { "NATURAL", "natural" }, { "STRONG", "strong" } },
    help = "Controls how different nearby parts of the same weather system can become. SUBTLE keeps local changes small, NATURAL uses the tuned amount, and STRONG creates more noticeable local variation. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "windIntensity", label = "WIND STRENGTH", type = "choice", default = "100",
    choices = { { "25%", "25" }, { "50%", "50" }, { "75%", "75" }, { "100%", "100" },
                { "125%", "125" }, { "150%", "150" }, { "200%", "200" } },
    help = "Controls the strength of Weather FX wind. It affects gust force, precipitation drift, cloud and fog movement, leaves and debris, and wind sound response. Whether wind can affect player walking is controlled separately.",
  },
  {
    key = "windWalk", label = "WIND & WALKING", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Allows strong headwinds and tailwinds to slightly affect walking speed. Bike and Surf speed are unchanged. OFF makes wind visual and audible only; DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "puddles", label = "WET GROUND", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "OFF", "off" }, { "LOW", "low" }, { "NORMAL", "on" }, { "HIGH", "high" } },
    help = "Controls the visible amount of rain wetness and puddling. NORMAL uses the same wet-ground strength as the previous ON setting, LOW is gentler, HIGH is stronger, and OFF removes the visible wet-ground response without changing rainfall or surface simulation. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "rainbows", label = "RAINBOWS", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Allows rainbows to appear after rain when the sun, clouds, and viewing conditions line up. They form and fade gradually and are blocked by normal world depth. OFF disables them; DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "godRays", label = "SUN RAYS & GLARE", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Controls bright sun rays and glare when looking toward an unobstructed sun. OFF removes the ray/glare effect while leaving the sun itself visible. Buildings and other world geometry can still block the effect.",
  },
  {
    key = "npcLightning", label = "CHARACTER STRIKES", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Allows lightning to occasionally strike visible non-player characters for the temporary visual strike effect. It does not change the character's permanent data or start a battle. OFF prevents these character strikes; DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "npcStrikeChance", label = "STRIKE CHANCE", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "5%", "5" }, { "10%", "10" },
                { "20%", "20" }, { "35%", "35" }, { "50%", "50" } },
    help = "Controls how often an eligible lightning strike targets a visible non-player character. This only applies while CHARACTER STRIKES is enabled. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "tornadoFrequency", label = "TORNADO FREQUENCY", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "RARE", "rare" },
                { "NORMAL", "normal" }, { "OFTEN", "often" }, { "EXTREME", "extreme" } },
    help = "Controls how often Gale gets a tornado opportunity. At the normal/default rate, 2D Gale checks every 90 seconds and has the configured carry chance (10% at NORMAL CARRY CHANCE) to start a relocation tornado. Higher settings check more often. In 3D it also shortens the interval between additional roaming tornado opportunities. The hard maximum active-tornado cap and CARRY CHANCE remain separate.",
  },
  {
    key = "celestialEvents", label = "SPECIAL EVENTS", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Turns special sky events on or off, including eclipses, shooting stars, meteor showers, unusual moon events, and seasonal aurora. Normal sun, moon, stars, and lunar phases remain when this is off. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "smoothSky", label = "SMOOTH SKY", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Turns Weather FX's smooth sky gradient on or off in supported 3D views. OFF leaves the active world renderer's normal sky presentation in control. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "celestialMotion", label = "SUN & MOON MOTION", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Controls whether the sun and moon move smoothly between game-clock updates. OFF allows their position to step with the underlying clock; ON interpolates the motion. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "timeSource", label = "TIME SOURCE", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "AUTO", "auto" }, { "SYSTEM", "system" },
                { "GAME CYCLE", "cycle" }, { "OFF", "off" } },
    help = "Chooses where Weather FX gets its clock. AUTO uses the best available game clock, SYSTEM uses the device clock, GAME CYCLE uses Weather FX's simulated day, and OFF disables Weather FX clock publishing. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "dayLength", label = "DAY LENGTH", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "12 MIN", "12" }, { "24 MIN", "24" },
                { "48 MIN", "48" }, { "96 MIN", "96" } },
    help = "Sets how many real minutes one full simulated day lasts when TIME SOURCE is GAME CYCLE. Shorter values make the day/night cycle advance faster. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "seasonLength", label = "SEASON LENGTH", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "5 DAYS", "5" }, { "15 DAYS", "15" },
                { "30 DAYS", "30" }, { "60 DAYS", "60" } },
    help = "Sets the number of simulated days in each season. Shorter values make spring, summer, autumn, and winter change more often. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "indoorAudio", label = "INDOOR VOLUME", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "MAX MUFFLE", "muted" }, { "QUIET", "quiet" },
                { "NATURAL", "natural" }, { "LOUD", "loud" } },
    help = "Controls how much outdoor weather can be heard from inside buildings. Building attenuation is capped at 60%, so even MAX MUFFLE keeps at least 40% of the outdoor distance-adjusted weather volume. QUIET, NATURAL, and LOUD retain progressively more outside sound. WEATHER SFX OFF is the separate full-mute control. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "thunderAudio", label = "THUNDER SOUNDS", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Turns thunder sounds on or off. Lightning can remain visible when thunder sounds are disabled. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "thunderVolume", label = "THUNDER VOLUME", type = "choice", default = "100",
    choices = { { "25%", "25" }, { "50%", "50" }, { "75%", "75" }, { "100%", "100" },
                { "125%", "125" }, { "150%", "150" } },
    help = "Controls thunder loudness without changing lightning frequency or strike timing. Distance fading and indoor muffling still apply. THUNDER SOUNDS remains the master on/off control.",
  },
  {
    key = "windAudio", label = "WIND SOUNDS", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Turns wind ambience on or off for gust-heavy weather. This does not disable physical wind, cloud movement, precipitation drift, or wind effects on walking. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "weatherEncounters", label = "WEATHER ENCOUNTER", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Allows natural weather to influence which wild Pokémon are more likely to appear and can also affect fishing. OFF restores the game's normal encounter selection. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "legendaryEvents", label = "LEGENDARY EVENTS", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Enables rare weather-linked legendary events. Gen 1 can feature Articuno, Zapdos, and Moltres; Gen 2-capable games can also feature Raikou, Entei, Suicune, Lugia, Ho-Oh, and Celebi. OFF disables these special events without removing ordinary weather. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "followerChip", label = "FOLLOWER DAMAGE", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "ON", "on" }, { "OFF", "off" } },
    help = "Allows supported overworld Pokémon followers to take slow weather damage from harmful conditions. This is separate from battle weather rules and, with the standard Weather FX setup, cannot faint a follower. DEFAULT uses Weather FX's installed setting.",
  },
  {
    key = "particleCap", label = "PARTICLE LIMIT", type = "choice", default = "config",
    choices = { { "DEFAULT", "config" }, { "FOLLOW QUALITY", "tier" },
                { "2,000", "2000" }, { "4,000", "4000" }, { "8,000", "8000" },
                { "12,000", "12000" }, { "20,000", "20000" } },
    help = "Adds an optional absolute limit to the number of live Weather FX particles after the selected graphics-quality rules are applied. FOLLOW QUALITY removes the extra limit; numbered choices set a maximum. DEFAULT uses Weather FX's installed setting.",
  },
  {
    -- The same switch as config.lua's `debugRain`, on the page a player
    -- can actually reach.  It is HERE and not only in the file because a
    -- .modpkg install has no editable config.lua at all -- so a debug
    -- switch that lived only in the file was unreachable for exactly the
    -- people most likely to need it.
    key = "debugRain", label = "TEST RAIN", type = "choice", default = "off",
    choices = { { "OFF", "off" }, { "ON", "on" } },
    help = "For testing only. ON forces heavy rain so you can quickly verify that Weather FX is drawing and updating; it can override normal weather selection while active. Turn it off after testing.",
  },
  {
    key = "debug", label = "DIAGNOSTICS", type = "choice", default = "off",
    choices = {
      { "OFF", "off" },
      { "SIMPLE", "simple" },
      { "FULL", "full" },
      { "3D", "3d" },
      { "ON", "on" },  -- alias of FULL (older saves / habit)
    },
    help = "Shows Weather FX diagnostic information on screen. SIMPLE shows the main status, FULL shows detailed weather and rendering information, and 3D focuses on the 3D weather connection. OFF hides diagnostics.",
  },
}

-- Real in-game submenu layout. The engine's public mod.options schema is kept
-- complete for persistence/fallback, while SettingsMenu presents these groups
-- as nested pages so the player never has to scroll a 50-row wall.
Settings.GROUPS = {
  { id="weather", label="WEATHER", help="Choose the active weather, its overall strength, duration, rendering mode, and indoor lighting response.",
    keys={"always","intensity","exotic","speed","present","pauseMenuWeather","screenEffects","indoors"} },
  { id="precipitation", label="PRECIPITATION", help="Adjust rain, snow, fog, sand, dust, splash effects, and snowflake appearance.",
    keys={"rainIntensity","snowIntensity","snowAccumulation","weatherRenderDistance","fogIntensity","sandIntensity","dustIntensity","splash","snowShape"} },
  { id="world", label="WORLD & CLOUDS", help="Control clouds, water, wind, wet ground, rainbows, and wind-blown leaves.",
    keys={"clouds","cloudHeight","cloudDensity","cloudBankStyle","waterStyle","windIntensity","windWalk","puddles","rainbows","leafColor"} },
  { id="behavior", label="WEATHER BEHAVIOR", help="Control how weather changes, travels between areas, and varies locally.",
    keys={"transitionSpeed","fronts","frontStrength","mesoscale","mesoscaleStrength"} },
  { id="storms", label="STORMS & TORNADO", help="Control lightning, storm darkness, character strikes, tornadoes, and tornado carrying.",
    keys={"lightning","weather2dLightning","lightningFlash","lightningFrequency","stormDarkness","npcLightning","npcStrikeChance","tornado","tornadoPickup","tornadoDuration","tornadoFrequency"} },
  { id="skytime", label="SKY & SEASONS", help="Control day/night, seasons, sun and moon motion, sky events, and sun-ray effects.",
    keys={"daytime","timeSource","dayLength","seasons","seasonLength","hemisphere","seasonNotify","godRays","celestialRendering","nightSkyBrightness","celestialEvents","smoothSky","celestialMotion"} },
  { id="sound", label="SOUND", help="Control Weather FX volume plus indoor, thunder, and wind sound settings.",
    keys={"sfx","indoorAudio","thunderAudio","thunderVolume","windAudio"} },
  { id="wild", label="WILD POKEMON", help="Control weather-influenced encounters, legendary events, and follower weather damage.",
    keys={"weatherEncounters","legendaryEvents","followerChip"} },
  { id="battle", label="BATTLES", help="Control battle weather visuals, battle rules, stronger optional rules, and backgrounds.",
    keys={"battles","battleDamage","amplified","backdrops"} },
  { id="performance", label="PERFORMANCE", help="Control overall graphics quality and optional advanced performance limits.",
    keys={"quality","autoPerformance","performanceTarget","textureDetail","reflectionDetail","effectDistance","simulationDetail","particleCap"} },
  { id="testing", label="TESTING", help="Diagnostic tools for checking Weather FX behavior and 3D rendering status.",
    keys={"debugRain","debug"} },
}

function Settings.row(key)
  for _,row in ipairs(Settings.SCHEMA) do if row.key==key then return row end end
  return nil
end

function Settings.group(id)
  for _,g in ipairs(Settings.GROUPS) do if g.id==id then return g end end
  return nil
end

-- Build the ALWAYS row's choices from the weather catalogue.  Done here
-- rather than typed out so a new weather type appears on the row without
-- anyone remembering to add it -- the same reason the OPTIONS ladder is
-- built from Types.PINNED.
do
  for _, row in ipairs(Settings.SCHEMA) do
    if row.key == "always" then
      local choices = { { "OFF", "off" }, { "AUTO", "auto" }, { "CYCLE", "cycle" } }
      for _, id in ipairs(Types.PINNED) do
        local def = Types.get(id)
        if def and def.label then
          choices[#choices + 1] = { def.label, id }
        end
      end
      row.choices = choices
    end
  end
end

-- Allowed values / defaults for Settings.get (must exist before define runs).
local defaults = {}
local valid = {}

local function rebuildValid()
  -- ALWAYS choices from catalogue (safe even if Types loads late).
  for _, row in ipairs(Settings.SCHEMA) do
    if row.key == "always" then
      local choices = { { "OFF", "off" }, { "AUTO", "auto" }, { "CYCLE", "cycle" } }
      if Types and Types.PINNED then
        for _, id in ipairs(Types.PINNED) do
          local def = Types.get(id)
          if def and def.label then
            choices[#choices + 1] = { def.label, id }
          end
        end
      end
      row.choices = choices
    end
  end
  for _, row in ipairs(Settings.SCHEMA) do
    defaults[row.key] = row.default
    local set = {}
    -- label -> stored value (host UI may persist "OFF" instead of "off")
    local labels = {}
    -- Any case-compatible representation -> EXACT DECLARED STORED VALUE.
    -- This matters for WEATHER ids such as RAIN_LIGHT: returning rain_light
    -- makes Types.byId and the engine ladder reject a perfectly valid choice.
    local canonical = {}
    for _, choice in ipairs(row.choices or {}) do
      if type(choice) == "table" and choice[2] ~= nil then
        local val = choice[2]
        local text = tostring(val)
        set[val] = true
        set[text] = true
        set[text:lower()] = true
        set[text:upper()] = true
        canonical[text] = val
        canonical[text:lower()] = val
        canonical[text:upper()] = val
        if choice[1] ~= nil then
          labels[choice[1]] = val
          labels[tostring(choice[1])] = val
          labels[tostring(choice[1]):lower()] = val
          labels[tostring(choice[1]):upper()] = val
        end
      end
    end
    valid[row.key] = set
    valid[row.key .. "__labels"] = labels
    valid[row.key .. "__values"] = canonical
  end
end

rebuildValid()

Settings._optionRevision = tonumber(Settings._optionRevision) or 0
Settings._keyRevision = Settings._keyRevision or {}
Settings._lastChangedKey = Settings._lastChangedKey or nil
function Settings.optionRevision() return tonumber(Settings._optionRevision) or 0 end
function Settings.keyRevision(key) return tonumber(Settings._keyRevision and Settings._keyRevision[key]) or 0 end
function Settings.lastChangedKey() return Settings._lastChangedKey end

function Settings.define()
  -- Host option tables can be rebuilt more than once during boot/save restore.
  -- Do NOT throw away live mirrors when that happens: the custom OPTIONS
  -- submenu may have already changed a value while mod.options:get() is still
  -- backed by an older loader cache. Opening Mod Manager refreshes that cache,
  -- which used to make a setting appear to "wake up" only after visiting it.
  Settings._runtimeValues = Settings._runtimeValues or {}
  rebuildValid()
  if not mod or not mod.options or type(mod.options.define) ~= "function" then
    pcall(function() mod.log:warn("settings define skipped: mod.options unavailable") end)
    return nil
  end
  -- Build the host fallback list in the same professional category order as
  -- the in-game submenu. This keeps every player-facing surface consistent
  -- even on hosts that cannot open Weather FX's grouped screen.
  local rows, ordered, seen = {}, {}, {}
  for _, group in ipairs(Settings.GROUPS or {}) do
    for _, key in ipairs(group.keys or {}) do
      local row = Settings.row(key)
      if row and not seen[key] then ordered[#ordered + 1] = row; seen[key] = true end
    end
  end
  for _, row in ipairs(Settings.SCHEMA) do
    if row and row.key and not seen[row.key] then ordered[#ordered + 1] = row; seen[row.key] = true end
  end
  for _, row in ipairs(ordered) do
    if row and row.key and row.type and row.choices and #row.choices > 0 then
      rows[#rows + 1] = {
        key = row.key,
        label = row.label or row.key,
        type = row.type,
        default = row.default,
        choices = row.choices,
        help = row.help,
      }
    end
  end
  if #rows == 0 then
    pcall(function() mod.log:warn("settings define: SCHEMA produced 0 rows") end)
    return nil
  end
  local ok, result = pcall(function()
    return mod.options:define(rows)
  end)
  if not ok then
    pcall(function()
      mod.log:warn("settings define failed: %s", tostring(result))
    end)
    -- Fallback: register a minimal schema so the mod page is never empty.
    pcall(function()
      mod.options:define({
        {
          key = "quality", label = "QUALITY", type = "choice", default = "auto",
          choices = {
            { "AUTO", "auto" }, { "MAX", "max" }, { "HIGH", "high" },
            { "MEDIUM", "medium" }, { "LOW", "low" }, { "POTATO", "potato" },
          },
        },
        {
          key = "always", label = "WEATHER", type = "choice", default = "auto",
          choices = { { "OFF", "off" }, { "AUTO", "auto" }, { "CYCLE", "cycle" } },
        },
        {
          key = "rainIntensity", label = "RAIN INTENSITY", type = "choice", default = "100",
          choices = { { "OFF", "off" }, { "50%", "50" }, { "100%", "100" }, { "200%", "200" } },
        },
        {
          key = "snowIntensity", label = "SNOW INTENSITY", type = "choice", default = "100",
          choices = {
            { "OFF", "off" }, { "50%", "50" }, { "100%", "100" }, { "200%", "200" }, { "500%", "500" },
          },
        },
        {
          key = "snowAccumulation", label = "SNOW ACCUMULATION", type = "choice", default = "on",
          choices = { { "ON", "on" }, { "OFF", "off" } },
        },
        {
          key = "weatherRenderDistance", label = "3D PRECIP DISTANCE", type = "choice", default = "100",
          choices = { { "25%", "25" }, { "50%", "50" }, { "75%", "75" }, { "100%", "100" } },
        },
        {
          key = "fogIntensity", label = "FOG INTENSITY", type = "choice", default = "100",
          choices = {
            { "OFF", "off" }, { "100%", "100" }, { "300%", "300" }, { "500%", "500" },
          },
        },
        {
          key = "sandIntensity", label = "SAND INTENSITY", type = "choice", default = "100",
          choices = {
            { "OFF", "off" }, { "100%", "100" }, { "300%", "300" }, { "500%", "500" },
          },
        },
        {
          key = "dustIntensity", label = "DUST INTENSITY", type = "choice", default = "100",
          choices = {
            { "OFF", "off" }, { "100%", "100" }, { "300%", "300" }, { "500%", "500" },
          },
        },
        {
          key = "debug", label = "DEBUG HUD", type = "choice", default = "off",
          choices = { { "OFF", "off" }, { "ON", "on" } },
        },
      })
    end)
    return nil
  end
  pcall(function()
    mod.log:info("Weather FX mod menu: %d options registered", #rows)
  end)
  Settings._defined = true
  Settings._rowCount = #rows
  -- A define can make persisted values visible after an early Config load.
  -- Bump the revision so Config's player-facing overlay is re-applied once.
  Settings._optionRevision = (tonumber(Settings._optionRevision) or 0) + 1

  -- CURRENT HOST API: option changes are announced through mod.options_changed.
  -- Do not rely on an options:set method existing; current Gen1Recomp exposes
  -- define/get and emits the event after the persisted value has changed.
  pcall(function()
    if Settings._optionsEventBound then return end
    if not (mod.events and type(mod.events.on) == "function") then return end
    mod.events:on("mod.options_changed", function(payload)
      if Settings.handleOptionChanged then Settings.handleOptionChanged(payload) end
    end)
    Settings._optionsEventBound = true
  end)

  -- Compatibility fallback for older/forked hosts that still expose set().
  pcall(function()
    if Settings._optionsEventBound then return end
    if not mod.options or Settings._optionsSetWrapped then return end
    local rawSet = mod.options.set
    if type(rawSet) ~= "function" then return end
    Settings._optionsRawSet = rawSet
    mod.options.set = function(self, key, value, ...)
      local ret = rawSet(self, key, value, ...)
      if Settings.handleOptionChanged then
        Settings.handleOptionChanged({ mod = mod.id, key = key, value = value })
      end
      return ret
    end
    Settings._optionsSetWrapped = true
  end)
  return result
end

function Settings.beginFrame()
  -- Most option reads are repeated by several independent presentation,
  -- simulation and audio paths in the same rendered frame. Cache only within
  -- that frame; handleOptionChanged invalidates an edited key immediately.
  Settings._frameSerial=(tonumber(Settings._frameSerial) or 0)+1
  Settings._frameValues=Settings._frameValues or {}
  Settings._frameStamps=Settings._frameStamps or {}
  return Settings._frameSerial
end

function Settings.get(key)
  local serial=tonumber(Settings._frameSerial) or 0
  local stamps=Settings._frameStamps
  local values=Settings._frameValues
  if serial>0 and stamps and values and stamps[key]==serial then return values[key] end

  local runtime=Settings._runtimeValues and Settings._runtimeValues[key]
  local ok,value
  if runtime~=nil then ok,value=true,runtime else ok,value=pcall(function() return mod.options:get(key) end) end
  local allowed=valid[key]
  local result
  if not ok or value==nil then
    result=defaults[key]
  elseif allowed and allowed[value] then
    result=value
    if type(value)=="string" then
      local labels=valid[key.."__labels"]
      local lo,up=value:lower(),value:upper()
      if labels then result=labels[value] or labels[lo] or labels[up] or result end
      if result==value then
        local canonical=valid[key.."__values"]
        if canonical then
          local mapped=canonical[value] or canonical[lo] or canonical[up]
          if mapped~=nil then result=mapped end
        end
      end
    end
  elseif type(value)=="string" then
    local labels=valid[key.."__labels"]
    if labels then result=labels[value] or labels[value:lower()] or labels[value:upper()] end
    if result==nil then result=defaults[key] end
  else
    result=defaults[key]
  end

  if serial>0 then
    Settings._frameValues=values or {}; Settings._frameStamps=stamps or {}
    Settings._frameValues[key]=result; Settings._frameStamps[key]=serial
  end
  return result
end


-- Overworld presentation: "2d" | "3d" | "auto"
function Settings.presentMode()
  return Settings.get("present") or "auto"
end

-- Celestial presentation is independently selectable from precipitation/weather.
-- This lets players keep classic 2D weather cards while retaining the true
-- world-space 3D sun/moon/stars/planets. MATCH preserves historical behavior.
function Settings.celestialPresentMode()
  return Settings.get("celestialRendering") or "match"
end

function Settings.use3dCelestial()
  if Settings.isFirstPerson and Settings.isFirstPerson() then return true end
  -- 8.2.8: full 3D weather always includes the world-space celestial vault.
  -- CELESTIAL RENDERING remains an independent override only while weather is
  -- explicitly 2D, where players may still opt into 3D sun/moon/stars.
  if Settings.force3dPresent and Settings.force3dPresent() then return true end
  local m=Settings.celestialPresentMode()
  if m=="3d" then return true end
  if m=="2d" then return false end
  return Settings.allow3dPresent and Settings.allow3dPresent() or Settings.presentMode()~="2d"
end

function Settings.use2dCelestial()
  return not Settings.use3dCelestial()
end

-- Connected hydrosphere ownership. ORIGINAL is deliberately a hard visual /
-- gameplay presentation handoff to the voxel host rather than a cosmetic skin:
-- hidden Weather FX ice must never leave the player walking on apparently
-- liquid native water. The thermal simulation may keep progressing internally
-- so switching back does not require rebuilding world state from scratch.
function Settings.waterStyle()
  return Settings.get("waterStyle") or "weatherfx"
end
function Settings.weatherFxWaterEnabled()
  return Settings.waterStyle() ~= "original"
end

-- Detect host first-person (Dramaless / Potato "1ST" mode).
-- Cached module pointer; engaged() is polled every call.
Settings._fpMod = nil
Settings._fpTried = false
function Settings.resolveFirstPersonMod()
  if Settings._fpTried and Settings._fpMod then return Settings._fpMod end
  Settings._fpTried = true
  pcall(function()
    if not (mod and mod.find) then return end
    local hosts = {
      "BATTLE_ART_VOXEL_FORK", "DRAMATIC_SHAPE", "DRAMALESS_SHAPE",
      "Gen2Recomped-DramaticShapes",
      "potato_voxel", "POTATO_VOXEL", "PotatoVoxel",
      "STADIUM2_OVERWORLD_MODELS",
    }
    for i = 1, #hosts do
      local ok, host = pcall(mod.find, mod, hosts[i])
      if ok and host then
        local req = host.require
        local owner = host
        if type(req) ~= "function" then
          local lib = host.exports and host.exports.lib
          if lib and type(lib.require) == "function" then req, owner = lib.require, lib end
        end
        if type(req) == "function" then
          local ok2, FP = pcall(req, owner, "FirstPerson")
          if not ok2 or type(FP) ~= "table" then
            ok2, FP = pcall(req, "FirstPerson")
          end
          if ok2 and type(FP) == "table" then
            Settings._fpMod = FP
            break
          end
        end
      end
    end
  end)
  return Settings._fpMod
end

function Settings.isFirstPerson()
  local FP = Settings.resolveFirstPersonMod()
  if type(FP) ~= "table" then return false end
  if type(FP.engaged) == "function" then
    local ok, e = pcall(FP.engaged)
    if ok and e then return true end
  elseif FP.engaged == true then
    return true
  end
  -- Soft fallback: card blend / hide player are FPV signals on Dramaless.
  if type(FP.cardBlend) == "function" then
    local ok, b = pcall(FP.cardBlend)
    if ok and type(b) == "number" and b > 0.45 then return true end
  end
  if type(FP.hidePlayer) == "function" then
    local ok, h = pcall(FP.hidePlayer)
    if ok and h then return true end
  end
  return false
end

-- Enter (true) or exit (false) host first-person. Used so Anime Realism battles
-- can force a third-person overworld camera for the fight, then restore FPV.
-- Tries several FirstPerson APIs used across Dramaless / Potato / Stadium forks.
function Settings.setFirstPersonEngaged(want)
  want = want and true or false
  local FP = Settings.resolveFirstPersonMod()
  if type(FP) ~= "table" then return false end
  -- VERIFY, DO NOT ASSUME.
  --
  -- This used to be `return ok and (res ~= false)` -- "it did not throw, so it
  -- worked". Almost every setter here returns nil, and nil ~= false, so the
  -- FIRST candidate that merely EXISTS reported success and the chain stopped.
  --
  -- That is exactly how a host with, say, a `setEngaged(self, want)` method
  -- silently swallows a `setEngaged(want)` call: no error, no effect, and this
  -- function returns true. The Anime Realism battle switch then believed it had
  -- dropped first person when it had not, which is why the check looked like it
  -- was not running.
  --
  -- Now every attempt is checked against the host's own reported state, and the
  -- chain keeps trying until the state actually changes.
  local function try(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok = pcall(fn, ...)
    if not ok then return false end
    local now = Settings.isFirstPerson()
    return (now and true or false) == want
  end
  -- Preferred explicit APIs
  if try(FP.setEngaged, want) then return true end
  if try(FP.setEngaged, FP, want) then return true end
  if want then
    if try(FP.engage) or try(FP.engage, FP) then return true end
    if try(FP.enable) or try(FP.enable, FP) then return true end
    if try(FP.enter) or try(FP.enter, FP) then return true end
  else
    if try(FP.disengage) or try(FP.disengage, FP) then return true end
    if try(FP.disable) or try(FP.disable, FP) then return true end
    if try(FP.exit) or try(FP.exit, FP) then return true end
  end
  if try(FP.setEnabled, want) or try(FP.setEnabled, FP, want) then return true end
  if try(FP.setActive, want) or try(FP.setActive, FP, want) then return true end
  if try(FP.set, want) or try(FP.set, FP, want) then return true end
  if type(FP.setMode) == "function" then
    local mode = want and "first" or "third"
    if try(FP.setMode, mode) or try(FP.setMode, FP, mode) then return true end
    mode = want and "1st" or "3rd"
    if try(FP.setMode, mode) or try(FP.setMode, FP, mode) then return true end
    mode = want and "fpv" or "third"
    if try(FP.setMode, mode) or try(FP.setMode, FP, mode) then return true end
  end
  -- Direct field writes (some hosts poll these every frame)
  local wrote = false
  for _, key in ipairs({ "engaged", "active", "enabled", "on", "fpv" }) do
    if FP[key] ~= nil then
      pcall(function() FP[key] = want end)
      wrote = true
    end
  end
  if wrote then return true end
  return false
end

-- True when the player wants the original Weather FX 2D overlays forced.
-- First-person always overrides: FPV must use 3D weather.
function Settings.force2dPresent()
  if Settings.isFirstPerson and Settings.isFirstPerson() then return false end
  return Settings.presentMode() == "2d"
end

-- True when the player explicitly requires the 3D presentation. First-person
-- is also authoritative 3D by design. Unlike allow3dPresent(), AUTO is not
-- included here: AUTO may still use 2D as a safety fallback if a 3D family or
-- host pass fails, while explicit 3D must never stack the flat 2D compositor
-- over a healthy voxel atmosphere.
function Settings.force3dPresent()
  if Settings.isFirstPerson and Settings.isFirstPerson() then return true end
  return Settings.presentMode() == "3d"
end

-- DEBUG HUD tier.  "on" is kept as an alias of "full" so older saves and
-- muscle memory still work.
function Settings.debugHudMode(config)
  -- Folder installs historically exposed config.debug/config.debugRain before
  -- the mod-manager row existed. Keep those real: either one forces FULL.
  if config and config.get then
    local ok, cfg = pcall(config.get)
    if ok and cfg and (cfg.debug or cfg.debugRain) then return "full" end
  end
  local v = Settings.get("debug")
  if v == "on" then return "full" end
  if v == "simple" or v == "full" or v == "3d" then return v end
  return "off"
end

function Settings.debugHudOn(config)
  return Settings.debugHudMode(config) ~= "off"
end



-- True when the player allows 3D (auto or explicit 3d).
-- First-person always forces 3D weather presentation.
function Settings.allow3dPresent()
  if Settings.isFirstPerson and Settings.isFirstPerson() then return true end
  local m = Settings.presentMode()
  return m == "3d" or m == "auto"
end

-- The weather the WEATHER row is pinning, or nil.  Same pin as the OPTIONS
-- weather ladder when they are in sync. Validated against the catalogue.
function Settings.alwaysWeather()
  local v = Settings._runtimeAlways
  if v == nil then v = Settings.get("always") end
  if not v or v == "off" or v == "auto" or v == "cycle" then return nil end
  if not Types.byId[v] then return nil end
  return v
end

-- Hard-disable authority shared by 2D, 3D, audio, lightning and cloud passes.
-- This is intentionally distinct from AUTO: OFF means no Weather FX weather.
function Settings.weatherDisabled()
  local v = Settings._runtimeAlways
  if v == nil then v = Settings.get("always") end
  return tostring(v or ""):lower() == "off"
end

-- A named WEATHER selection is a direct player authority.  Fronts are a
-- competing weather authority, so the two are intentionally mutually exclusive:
-- choosing RAIN/STORM/SNOW/etc. turns WEATHER FRONTS off instead of leaving a
-- hidden front simulation able to replace the player's explicit choice later.
function Settings.manualWeatherSelected()
  local v = Settings._runtimeAlways
  if v == nil then v = Settings.get("always") end
  if not v then return nil end
  local lo=tostring(v):lower()
  if lo=="off" or lo=="auto" or lo=="cycle" then return nil end
  local d=Types.byId and Types.byId[v] or nil
  if not d and Types.get then
    local ok,res=pcall(Types.get,v)
    if ok and res and res.id and tostring(res.id):upper()==tostring(v):upper() then d=res end
  end
  return d and (d.id or v) or nil
end

-- Persist a dependent option change without requiring the host to expose a
-- public options:set() method.  Current Gen1Recomp stores mod options in the
-- save backing table; older/forked hosts may also expose set(). Runtime mirrors
-- are updated synchronously so Config.get() sees the new authority this frame.
local function persistDependentOption(key,value)
  Settings._runtimeValues=Settings._runtimeValues or {}
  Settings._runtimeValues[key]=value
  if Settings._frameStamps then Settings._frameStamps[key]=nil end
  Settings._optionRevision=(tonumber(Settings._optionRevision) or 0)+1
  Settings._keyRevision=Settings._keyRevision or {}
  Settings._keyRevision[key]=(tonumber(Settings._keyRevision[key]) or 0)+1

  pcall(function()
    local Game=package.loaded["src.core.Game"]
    if not Game then local ok,g=pcall(require,"src.core.Game");if ok then Game=g end end
    local opts=Game and Game.save and Game.save.options
    if opts then
      opts.modOptions=opts.modOptions or {}
      opts.modOptions[mod.id]=opts.modOptions[mod.id] or {}
      opts.modOptions[mod.id][key]=value
    end
    local loader=Game and Game.mods
    if loader then
      loader.modOptions=loader.modOptions or {}
      loader.modOptions[mod.id]=loader.modOptions[mod.id] or {}
      loader.modOptions[mod.id][key]=value
      if loader.loader then
        loader.loader.modOptions=loader.loader.modOptions or {}
        loader.loader.modOptions[mod.id]=loader.loader.modOptions[mod.id] or {}
        loader.loader.modOptions[mod.id][key]=value
      end
    end
  end)

  pcall(function()
    local raw=Settings._optionsRawSet
    if type(raw)=="function" then raw(mod.options,key,value) end
  end)
  return true
end

function Settings.disableFrontsForManualWeather()
  if not Settings.manualWeatherSelected() then return false end
  if tostring(Settings.get("fronts") or ""):lower() ~= "off" then
    persistDependentOption("fronts","off")
  else
    Settings._runtimeValues=Settings._runtimeValues or {}
    Settings._runtimeValues.fronts="off"
  end
  return true
end

-- OPTIONS ladder levels: OFF=0, AUTO=1, CYCLE=2, named weather thereafter.
function Settings.ladderLevelForWeather(id)
  local State = V.require("WeatherState")
  if id == false then return 0 end
  if id == nil then return 1 end
  local text=tostring(id)
  local lo=text:lower()
  if lo == "off" then return 0 end
  if lo == "auto" then return 1 end
  if lo == "cycle" then return 2 end
  for i, rung in ipairs(State.LEVEL_IDS or {}) do
    if rung == id or tostring(rung):upper() == text:upper() then return i - 1 end
  end
  return 1
end

function Settings.weatherIdForLadderLevel(level)
  local State = V.require("WeatherState")
  local rung = State.LEVEL_IDS and State.LEVEL_IDS[(tonumber(level) or 0) + 1]
  if rung == false or rung == nil then return "off" end
  if rung == "AUTO" then return "auto" end
  if rung == "CYCLE" then return "cycle" end
  return rung
end

-- Write the shared WEATHER value without re-entering options:set recursion.
-- Both player-facing selectors (the engine OPTIONS ladder and the Weather FX
-- Mod Manager row) are views of this one value.  Mirroring only the persisted
-- backing store is not enough because Settings.get() intentionally prefers the
-- live runtime cache; keep every cache/save surface synchronized in the same
-- call so neither menu can display or reassert a stale weather on the next
-- frame.
Settings._writingAlways = false
function Settings.writeAlwaysOption(value, game)
  value = value or "off"
  Settings._runtimeValues = Settings._runtimeValues or {}
  Settings._runtimeValues.always = value
  Settings._runtimeAlways = value
  if Settings._frameStamps then Settings._frameStamps.always = nil end

  pcall(function()
    local G = game or package.loaded["src.core.Game"]
    if not G then local ok,g=pcall(require,"src.core.Game"); if ok then G=g end end
    local opts = G and G.save and G.save.options
    if opts then
      opts.modOptions = opts.modOptions or {}
      opts.modOptions[mod.id] = opts.modOptions[mod.id] or {}
      opts.modOptions[mod.id].always = value
    end
    local loader = G and G.mods
    if loader then
      loader.modOptions = loader.modOptions or {}
      loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
      loader.modOptions[mod.id].always = value
      if loader.loader then
        loader.loader.modOptions = loader.loader.modOptions or {}
        loader.loader.modOptions[mod.id] = loader.loader.modOptions[mod.id] or {}
        loader.loader.modOptions[mod.id].always = value
      end
    end
  end)

  if Settings._writingAlways then return value end
  Settings._writingAlways = true
  pcall(function()
    local raw = Settings._optionsRawSet
    if type(raw) == "function" then
      raw(mod.options, "always", value)
    elseif mod and mod.options and type(mod.options.set) == "function" then
      mod.options:set("always", value)
    end
  end)
  Settings._writingAlways = false
  return value
end

-- Push mod-menu WEATHER → OPTIONS pipeline ladder.
function Settings.pushWeatherToLadder(value)
  if Settings._syncingWeather then return nil end
  Settings._syncingWeather = true
  local level=nil
  pcall(function()
    local id = value
    if type(id) == "string" then
      local labels = valid["always__labels"]
      if labels and labels[id] then id = labels[id] end
      id = tostring(id)
      if id:lower() == "off" then id = "off" end
    end
    level = Settings.ladderLevelForWeather(id)
    -- Keep a pending authority until the engine reports this exact rung back.
    -- This is what makes OFF -> AUTO/named weather reversible even on hosts
    -- where the render pipeline's live module is temporarily unavailable.
    Settings._pendingLadderLevel = level
    Settings._pendingLadderPin = id
    local Game = package.loaded["src.core.Game"] or (function()
      local ok, g = pcall(require, "src.core.Game"); return ok and g or nil
    end)()
    local opts = Game and Game.save and Game.save.options or nil
    if opts then
      opts.pipelines = opts.pipelines or {}
      opts.pipelines.weather = level
    end
    local P = package.loaded["src.render.Pipelines"]
    if not P then
      local ok, modP = pcall(require, "src.render.Pipelines")
      if ok then P = modP end
    end
    if P then
      local observed=nil
      if type(P.level)=="function" then
        local okRead,cur=pcall(P.level,"weather")
        if okRead then observed=tonumber(cur) end
      end
      -- Re-applying the SAME pipeline rung is not harmless on every host: some
      -- render-pipeline implementations rebuild/invalidate the stage when
      -- setLevel is called. A repeated mod.options_changed broadcast could then
      -- visibly restart classic 2D rain/snow every few seconds. Stable authority
      -- is therefore read-only; only a genuinely different rung is pushed.
      if observed==level then
        Settings._pendingLadderLevel=nil;Settings._pendingLadderPin=nil
      elseif type(P.setLevel) == "function" then
        local okSet=pcall(P.setLevel,"weather",level)
        if okSet and opts and type(P.syncOptions) == "function" then pcall(P.syncOptions, opts) end
        if okSet then
          if type(P.level)=="function" then
            local okRead,cur=pcall(P.level,"weather")
            if okRead and tonumber(cur)==level then Settings._pendingLadderLevel=nil;Settings._pendingLadderPin=nil end
          else
            -- setLevel itself is the host's live authority on older/test hosts.
            Settings._pendingLadderLevel=nil;Settings._pendingLadderPin=nil
          end
        end
      end
    end
    Settings._lastLadderLevel = level
    Settings._lastMenuPin = (id == "off" or not id) and "off" or id
  end)
  Settings._syncingWeather = false
  return level
end

-- Reconcile a player menu request before the WeatherState tick. Pipelines.update
-- is allowed to tick a record at rung 0 on current hosts; applying the pending
-- rung here means the same frame can become render-eligible again. The return
-- value is also used as State.update's level so runtime state cannot be pinned
-- OFF merely because a stale engine/save mirror lagged behind one frame.
function Settings.reconcileWeatherLadder(P, opts, currentLevel)
  local wanted=Settings._pendingLadderLevel
  if wanted==nil then return currentLevel end
  wanted=tonumber(wanted) or 0
  if opts then
    opts.pipelines=opts.pipelines or {}
    opts.pipelines.weather=wanted
  end
  local observed=tonumber(currentLevel)
  -- If the engine already reports the requested rung, reconciliation is done.
  -- Calling setLevel again can invalidate/recreate a host pipeline and restart
  -- an otherwise continuous 2D weather effect.
  if observed==wanted then
    Settings._pendingLadderLevel=nil;Settings._pendingLadderPin=nil
    return wanted
  end
  if P and type(P.setLevel)=="function" then
    pcall(P.setLevel,"weather",wanted)
    if opts and type(P.syncOptions)=="function" then pcall(P.syncOptions,opts) end
    if type(P.level)=="function" then local ok,v=pcall(P.level,"weather");if ok then observed=tonumber(v) or observed end end
  end
  if observed==wanted then Settings._pendingLadderLevel=nil;Settings._pendingLadderPin=nil end
  return wanted
end

-- Pull OPTIONS ladder → Mod Manager WEATHER.  This is also the immediate
-- player-action path used by the OPTIONS row wrapper, so it updates the live
-- cache, persisted mod option, dependent FRONT authority and revision counters
-- in one place.
function Settings.syncWeatherFromLadder(level, game)
  level = tonumber(level) or 0
  if Settings._pendingLadderLevel ~= nil then
    local pending=tonumber(Settings._pendingLadderLevel) or 0
    if level==pending then
      Settings._pendingLadderLevel=nil;Settings._pendingLadderPin=nil
    else
      -- The Mod Manager edit is newer than this stale engine rung. Never mirror
      -- the stale rung back while reconciliation is still pending.
      return false
    end
  end
  if Settings._syncingWeather or Settings._menuPinDirty then
    -- Mod Manager just changed; its ladder push owns this frame. Runtime/cache
    -- mirrors were already updated synchronously by handleOptionChanged().
    Settings._menuPinDirty = false
    return false
  end

  local want = Settings.weatherIdForLadderLevel(level)
  local prior = Settings._runtimeAlways
  if prior == nil then prior = Settings.get("always") or "off" end

  -- Update BOTH runtime mirrors before any WeatherState OFF/forced-weather gate
  -- can inspect them. This is the critical fix for OPTIONS OFF -> AUTO/named.
  Settings._runtimeAlways = want
  Settings._runtimeValues = Settings._runtimeValues or {}
  Settings._runtimeValues.always = want
  if Settings._frameStamps then Settings._frameStamps.always = nil end

  if prior ~= want then
    Settings._optionRevision = (tonumber(Settings._optionRevision) or 0) + 1
    Settings._keyRevision = Settings._keyRevision or {}
    Settings._keyRevision.always = (tonumber(Settings._keyRevision.always) or 0) + 1
    Settings._lastChangedKey = "always"
  end

  -- A named selection made through the engine OPTIONS ladder has exactly the
  -- same authority as the Mod Manager WEATHER row.
  if want ~= "off" and want ~= "auto" and want ~= "cycle" then
    pcall(Settings.disableFrontsForManualWeather)
  end

  Settings._syncingWeather = true
  pcall(function()
    -- Persist only on an actual player/engine change. The climate tick calls
    -- this every frame; writing the options store every frame would turn a
    -- synchronization fix into needless save I/O and event traffic.
    if prior ~= want then Settings.writeAlwaysOption(want, game) end
    Settings._lastLadderLevel = level
    Settings._lastMenuPin = want
  end)
  Settings._syncingWeather = false
  return prior ~= want
end

-- Explicit OPTIONS-row action.  The row itself calls this immediately after
-- the engine changes its weather rung; State.update also calls the same mirror
-- as a safety net for hotkeys/hosts that change the pipeline outside the menu.
function Settings.handleWeatherLadderChanged(level, game)
  Settings._pendingLadderLevel = nil
  Settings._pendingLadderPin = nil
  Settings._menuPinDirty = false
  return Settings.syncWeatherFromLadder(level, game)
end

-- Poll the engine WEATHER ladder from an always-running host seam. OPTIONS-row
-- wrappers are useful for same-menu feedback, but they are not a safe sole
-- authority: UI mods and generation-specific option builders can copy/replace
-- the row and bypass our decorated step callback. render.hud calls this once per
-- frame, so a base OPTIONS WEATHER edit is observed even when the row wrapper
-- never ran. A pending Mod Manager edit still wins until its requested rung is
-- actually visible, preventing a stale ladder read from undoing the newer edit.
function Settings.pollWeatherLadder(game)
  local P = package.loaded["src.render.Pipelines"]
  if not P then
    local ok,p=pcall(require,"src.render.Pipelines")
    if ok then P=p end
  end
  if not P then return false end

  local opts=nil
  pcall(function()
    local G=game or package.loaded["src.core.Game"]
    if not G then local ok,g=pcall(require,"src.core.Game");if ok then G=g end end
    opts=G and G.save and G.save.options or nil
  end)

  local level=nil
  if type(P.level)=="function" then
    local ok,v=pcall(P.level,"weather")
    if ok then level=tonumber(v) end
  end
  if level==nil and opts and opts.pipelines then level=tonumber(opts.pipelines.weather) end
  if level==nil then return false end

  if Settings._pendingLadderLevel~=nil then
    local wanted=tonumber(Settings._pendingLadderLevel) or 0
    if level~=wanted then
      Settings.reconcileWeatherLadder(P,opts,level)
      return true
    end
    Settings._pendingLadderLevel=nil;Settings._pendingLadderPin=nil
  end

  local last=tonumber(Settings._lastLadderLevel)
  local want=Settings.weatherIdForLadderLevel(level)
  local live=Settings._runtimeAlways
  if live==nil then live=Settings.get("always") or "off" end
  if last~=level or tostring(live)~=tostring(want) then
    Settings.handleWeatherLadderChanged(level,game)
    return true
  end
  return false
end

function Settings.is(key, value)
  return Settings.get(key) == value
end

-- Handle a live mod-manager option change. Current Gen1Recomp emits this
-- after persistence, so Settings.get() sees the new value immediately.
function Settings.handleOptionChanged(payload)
  if type(payload) ~= "table" then return false end
  if payload.mod ~= nil and tostring(payload.mod) ~= tostring(mod.id) then return false end
  local key = tostring(payload.key or "")
  if key == "" then return false end
  if Settings._frameStamps then Settings._frameStamps[key]=nil end
  Settings._runtimeValues=Settings._runtimeValues or {}
  -- Keep the pre-event runtime authority so duplicate host broadcasts can be
  -- recognized before they bump revisions or touch the render-pipeline ladder.
  local priorRuntimeValue=Settings._runtimeValues[key]
  local priorWeatherValue=(key=="always") and Settings._runtimeAlways or nil
  local normalizedPayload=nil
  if payload.value~=nil then
    -- Normalize event payloads through the same declared choice map used by
    -- Settings.get(). Some host/custom menu paths report display labels (MAX)
    -- while others report stored values (max). Runtime consumers must see one
    -- canonical stored value immediately, regardless of which path changed it.
    local raw=payload.value
    local canonical=valid[key.."__values"]
    local labels=valid[key.."__labels"]
    local norm=raw
    if type(raw)=="string" then
      local lo,up=raw:lower(),raw:upper()
      if labels then norm=labels[raw] or labels[lo] or labels[up] or norm end
      if norm==raw and canonical then norm=canonical[raw] or canonical[lo] or canonical[up] or norm end
      -- 8.2.14 removed the former RAVE weather.  Old saves can still replay
      -- that persisted WEATHER choice during boot; migrate it to AUTO so the
      -- removed mode can never survive invisibly in the runtime mirror.
      if key=="always" and tostring(norm):upper()=="RAVE" then norm=defaults.always or "auto" end
    end
    Settings._runtimeValues[key]=norm
    normalizedPayload=norm
  end

  -- Current/forked hosts can rebroadcast persisted mod options during save or
  -- menu-cache refresh. For WEATHER, receiving the exact same canonical value
  -- is NOT a player edit and must be a strict no-op. In 8.1.88 each duplicate
  -- event called pushWeatherToLadder(), and hosts that rebuild a pipeline on
  -- setLevel() visibly restarted 2D weather from frame zero on every broadcast.
  if key=="always" and normalizedPayload~=nil then
    local prior=priorWeatherValue
    if prior==nil then prior=priorRuntimeValue end
    if prior~=nil and tostring(prior)==tostring(normalizedPayload) then
      Settings._runtimeAlways=normalizedPayload
      return false
    end
  end

  Settings._optionRevision = (tonumber(Settings._optionRevision) or 0) + 1
  Settings._keyRevision=Settings._keyRevision or {}
  Settings._keyRevision[key]=(tonumber(Settings._keyRevision[key]) or 0)+1
  Settings._lastChangedKey=key

  if key == "always" and not Settings._syncingWeather and not Settings._writingAlways then
    Settings._menuPinDirty = true
    Settings._runtimeAlways = Settings.get("always") or payload.value or "off"
    pcall(Settings.pushWeatherToLadder, Settings._runtimeAlways)
    -- Explicit named weather and moving fronts cannot both own the sky.  Make
    -- the player's named selection authoritative by turning fronts OFF now.
    pcall(Settings.disableFrontsForManualWeather)
  elseif key == "fronts" then
    -- If a named weather is still selected, an attempted FRONT=ON edit cannot
    -- silently steal authority back.  The player must return WEATHER to AUTO
    -- or CYCLE first, then enable fronts.
    pcall(Settings.disableFrontsForManualWeather)
  end


  -- WATER STYLE is a live renderer-ownership switch. Notify the 3D bridge
  -- immediately so ORIGINAL restores host wave uniforms even if the player is
  -- standing still and no subsequent Weather FX state transition occurs.
  if key == "waterStyle" then
    pcall(function()
      local A=V.require("DramalessAtmos")
      if A and A.onWaterStyleChanged then A.onWaterStyleChanged(Settings.get("waterStyle")) end
    end)
  end

  -- Returning to AUTO or changing its policy should not resume a stale tier
  -- from a much earlier play session. Start from the documented device-friendly
  -- tier, then let sustained load move it. Manual quality choices are immediate
  -- because every consumer resolves the live profile at call time.
  if key=="quality" or key=="autoPerformance" then
    pcall(function() local Q=V.require("Quality");if Q and Q.reset then Q.reset() end end)
  end

  return true
end

-- The debug-rain switch, from EITHER source.  Two places to set one thing
-- is normally a smell, but these two reach different people: the file is
-- for a folder install and a considered playthrough, the row is for a
-- packed .modpkg on a handheld with no text editor.
function Settings.debugRain(config)
  if config and config.get().debugRain then return true end
  return Settings.is("debugRain", "on")
end

-- ------- derived numbers the draw path wants

local INTENSITY = { soft = 0.45, normal = 1.0, heavy = 1.50 }
function Settings.intensity()
  local v = INTENSITY[Settings.get("intensity")]
  if v then return v end
  return 1                      -- "auto" scales per family instead; see below
end

-- Rainfall-only multiplier. Density/count only; fall-speed channels are separate.
local RAIN_INTENSITY = { off=0.0, ["25"]=0.25, ["50"]=0.50, ["75"]=0.75,
  ["100"]=1.00, ["125"]=1.25, ["150"]=1.50, ["200"]=2.00 }
function Settings.rainIntensity()
  local k=Settings.get("rainIntensity"); if k==nil then return 1 end
  local v=RAIN_INTENSITY[k] or RAIN_INTENSITY[tostring(k)]
  if v==nil and type(k)=="number" then v=RAIN_INTENSITY[tostring(math.floor(k))] end
  return v==nil and 1 or v
end
function Settings.rainOff() return Settings.rainIntensity() <= 0 end

-- Player-facing wind strength multiplier. This scales the gust channel only;
-- it never touches dt, particle fall speed, weather dwell time or game speed.
local WIND_INTENSITY = { ["25"]=0.25, ["50"]=0.50, ["75"]=0.75, ["100"]=1.00,
  ["125"]=1.25, ["150"]=1.50, ["200"]=2.00 }
function Settings.windIntensity() return WIND_INTENSITY[Settings.get("windIntensity")] or 1 end

local LIGHTNING_FLASH = { off=0.0, low=0.50, normal=1.00, high=1.35 }
function Settings.lightningFlashScale() return LIGHTNING_FLASH[Settings.get("lightningFlash")] or 1 end

-- Bolt presentation override for explicitly selected 2D overworld weather.
-- This does not change precipitation/fog/cloud presentation and is ignored by
-- the normal 3D-weather path. If no healthy voxel lightning pass exists, Draw
-- fails open to the classic 2D bolt so selecting 3D can never make strikes vanish.
function Settings.weather2dLightningMode()
  local v=tostring(Settings.get("weather2dLightning") or "2d"):lower()
  return v=="3d" and "3d" or "2d"
end

function Settings.wants3dLightningWith2dWeather()
  return Settings.force2dPresent and Settings.force2dPresent()
      and Settings.weather2dLightningMode()=="3d"
end

local LIGHTNING_FREQUENCY = { rare=0.45, low=0.70, normal=1.00, high=1.50, extreme=2.25 }
function Settings.lightningFrequencyScale() return LIGHTNING_FREQUENCY[Settings.get("lightningFrequency")] or 1 end

local SCREEN_EFFECTS = { off=0.0, reduced=0.50, full=1.00 }
function Settings.screenEffectsScale() return SCREEN_EFFECTS[Settings.get("screenEffects")] or 1 end


local TORNADO_DURATION = { short=0.50, normal=1.00, long=1.75 }
function Settings.tornadoDurationScale() return TORNADO_DURATION[Settings.get("tornadoDuration")] or 1 end

local NIGHT_SKY_BRIGHTNESS = { low=0.65, normal=1.00, high=1.30 }
function Settings.nightSkyBrightnessScale() return NIGHT_SKY_BRIGHTNESS[Settings.get("nightSkyBrightness")] or 1 end

local PUDDLE_AMOUNT = { off=0.0, low=0.50, on=1.00, high=1.35, config=1.00 }
function Settings.puddleAmountScale() return PUDDLE_AMOUNT[Settings.get("puddles")] or 1 end

local CLOUD_DENSITY = { low=0.72, normal=1.00, high=1.22, veryhigh=1.45 }
local CLOUD_GATE_BIAS = { low=0.14, normal=0.00, high=-0.08, veryhigh=-0.14 }
function Settings.cloudDensityScale() return CLOUD_DENSITY[Settings.get("cloudDensity")] or 1 end
function Settings.cloudDensityGateBias() return CLOUD_GATE_BIAS[Settings.get("cloudDensity")] or 0 end

function Settings.cloudBankStyle()
  return Settings.get("cloudBankStyle") == "blocky" and "blocky" or "volumetric"
end

local STORM_DARKNESS = { off=0.0, low=0.60, normal=1.00, high=1.35 }
function Settings.stormDarknessScale() return STORM_DARKNESS[Settings.get("stormDarkness")] or 1 end

local TORNADO_PICKUP = { off=0.0, rare=0.03, normal=0.10, frequent=0.25 }
function Settings.tornadoPickupChance() return TORNADO_PICKUP[Settings.get("tornadoPickup")] or 0.10 end

local THUNDER_VOLUME = { ["25"]=0.25, ["50"]=0.50, ["75"]=0.75, ["100"]=1.00,
  ["125"]=1.25, ["150"]=1.50 }
function Settings.thunderVolumeScale() return THUNDER_VOLUME[Settings.get("thunderVolume")] or 1 end

-- Snowfall-only multiplier. Unlike FOG INTENSITY this is deliberately linear:
-- the percentage printed in the menu is the actual snow-channel multiplier.
local SNOW_INTENSITY = {
  off=0.0, ["10"]=0.10, ["25"]=0.25, ["50"]=0.50, ["75"]=0.75,
  ["100"]=1.00, ["125"]=1.25, ["150"]=1.50, ["200"]=2.00,
  ["250"]=2.50, ["300"]=3.00, ["400"]=4.00, ["500"]=5.00,
  low=0.50, normal=1.00, high=1.50, max=5.00,
}
function Settings.snowIntensity()
  local k=Settings.get("snowIntensity")
  if k==nil then return 1 end
  local v=SNOW_INTENSITY[k] or SNOW_INTENSITY[tostring(k)]
  if v==nil and type(k)=="number" then v=SNOW_INTENSITY[tostring(math.floor(k))] end
  return v==nil and 1 or v
end
function Settings.snowOff()
  return Settings.snowIntensity() <= 0
end
function Settings.snowAccumulationEnabled()
  return Settings.get("snowAccumulation") ~= "off"
end
local WEATHER_RENDER_DISTANCE = { ["25"]=0.25, ["50"]=0.50, ["75"]=0.75, ["100"]=1.00 }
function Settings.weatherRenderDistanceScale()
  local k=Settings.get("weatherRenderDistance")
  local v=WEATHER_RENDER_DISTANCE[tostring(k or "100")] or 1.00
  if v<0.01 then v=0.01 elseif v>1.00 then v=1.00 end
  return v
end

-- Fog/veil only. Independent of INTENSITY so the two dials do not fight.
-- Nonlinear curve (not 1:1 with the label %): low end is a light mist,
-- 300% is intentionally extreme so you can get lost in it.
local FOG_INTENSITY = {
  off     = 0.00,
  ["10"]  = 0.06,
  ["25"]  = 0.12,
  ["50"]  = 0.35,
  ["100"] = 1.00,
  ["150"] = 2.25,
  ["200"] = 4.00,
  ["250"] = 6.50,
  ["300"] = 10.0,
  ["350"] = 12.5,
  ["400"] = 15.0,
  ["450"] = 17.5,
  ["500"] = 20.0,   -- maximum whiteout
  -- legacy keys
  low = 0.35, normal = 1.00, high = 2.25, max = 20.0,
}
function Settings.fogIntensity()
  local k = Settings.get("fogIntensity")
  if k == nil then return 1 end
  local v = FOG_INTENSITY[k]
  if v == nil then v = FOG_INTENSITY[tostring(k)] end
  -- Host UIs sometimes persist numeric choice values as numbers.
  if v == nil and type(k) == "number" then v = FOG_INTENSITY[tostring(math.floor(k))] end
  if v == nil then return 1 end
  return v
end

--- True when fog/veil should not draw at all.
function Settings.fogOff()
  return Settings.fogIntensity() <= 0
end

--- Cloud banks (3D sky). Default ON. OFF only hides clouds, not precipitation.
function Settings.cloudsOn()
  return Settings.get("clouds") ~= "off"
end

-- Strict-3D cloud altitude relative to the original pre-8.1.22 deck.
-- RAISED is the 8.1.22 default (150%); ORIGINAL is exactly 100%.
-- This is geometry/column height only and must never be used as a time scale.
function Settings.cloudHeightScale()
  return Settings.get("cloudHeight") == "original" and 1.0 or 1.5
end

function Settings.leafColor()
  local v = Settings.get("leafColor")
  if v == "yellow" or v == "orange" or v == "brown" or v == "green" then
    return v
  end
  -- SEASONAL is the default. Resolve lazily to avoid a Settings <-> Seasons
  -- load-time cycle: Seasons itself reads Settings for hemisphere/enabled.
  local season = "SPRING"
  local ok, Se = pcall(V.require, "Seasons")
  if ok and Se then
    if type(Se.current) == "function" then
      local ok2, id = pcall(Se.current)
      if ok2 and type(id) == "string" then season = id:upper() end
    elseif type(Se.id) == "string" then
      season = Se.id:upper()
    end
  end
  if season == "AUTUMN" then return "orange" end
  if season == "WINTER" then return "brown" end
  return "green"
end

function Settings.snowShape()
  if Settings.get("snowShape") == "ball" then return "ball" end
  return "flake"
end


-- Same extreme curve as FOG_INTENSITY (shared dial feel).
local SAND_DUST_INTENSITY = FOG_INTENSITY

local function intensityFromMap(map, keyName)
  local k = Settings.get(keyName)
  if k == nil then return 1 end
  local v = map[k]
  if v == nil then v = map[tostring(k)] end
  if v == nil and type(k) == "number" then v = map[tostring(math.floor(k))] end
  if v == nil then return 1 end
  return v
end

function Settings.sandIntensity()
  return intensityFromMap(SAND_DUST_INTENSITY, "sandIntensity")
end

function Settings.dustIntensity()
  return intensityFromMap(SAND_DUST_INTENSITY, "dustIntensity")
end

function Settings.sandOff()
  return Settings.sandIntensity() <= 0
end

function Settings.dustOff()
  return Settings.dustIntensity() <= 0
end

-- Map sand/dust intensity dial → remaining scene visibility (1 = clear, 0.25 = 25%).
-- Uses the menu % label so 500% is exactly 25% visibility.
local VIS_PCT = {
  off = 0, ["10"] = 10, ["25"] = 25, ["50"] = 50, ["100"] = 100,
  ["150"] = 150, ["200"] = 200, ["250"] = 250, ["300"] = 300,
  ["350"] = 350, ["400"] = 400, ["450"] = 450, ["500"] = 500,
  low = 50, normal = 100, high = 150, max = 500,
}

local function visibilityFromKey(keyName)
  local k = Settings.get(keyName)
  if k == nil then return 1.0 end
  local pct = VIS_PCT[k] or VIS_PCT[tostring(k)]
  if pct == nil and type(k) == "number" then pct = VIS_PCT[tostring(math.floor(k))] end
  if pct == nil then
    -- Fallback from intensity multiplier curve
    local mul = intensityFromMap(SAND_DUST_INTENSITY, keyName)
    if mul <= 0 then return 1.0 end
    return 1.0 - math.min(1.0, mul / 20.0) * 0.75
  end
  if pct <= 0 then return 1.0 end
  -- Linear: 0%→100% vis, 500%→25% vis
  return 1.0 - (pct / 500.0) * 0.75
end

function Settings.sandVisibility()
  return visibilityFromKey("sandIntensity")
end

function Settings.dustVisibility()
  return visibilityFromKey("dustIntensity")
end

-- Haze strength for dens/veil: 0 at OFF, 1 at 500% (25% visibility).
function Settings.sandHaze()
  return 1.0 - Settings.sandVisibility()
end

function Settings.dustHaze()
  return 1.0 - Settings.dustVisibility()
end

-- ------- AUTO intensity
--
-- Real weather is not a constant.  A downpour has heavier and lighter
-- minutes inside it, and a storm's strikes cluster and then go quiet.  On
-- the fixed settings this mod picks one number and holds it for the whole
-- spell, which is the single thing that most gives away that the sky is a
-- particle system.
--
-- AUTO fixes that WITHOUT touching the weather itself: the type still says
-- "heavy rain", the state machine still eases toward the same targets, and
-- only the final multiplier breathes.  So nothing downstream -- the battle
-- layer, the AUTO scheduler, the save -- can tell the difference.
--
-- EACH FAMILY GETS ITS OWN RHYTHM, which is the part that matters.  If one
-- oscillator drove everything, the rain, the fog and the lightning would
-- swell and fade in lockstep and read as the brightness being turned up
-- and down.  Five families on unrelated periods, with different phases,
-- never line up for long:
--
--   wet     rain and its splashes
--   frozen  snow
--   grain   hail, sand, blown debris
--   haze    fog banks and the flat veil
--   light   lightning strike rate
--
-- Two sines per family at incommensurable periods -- so the pattern does
-- not repeat on any timescale a player would notice -- mapped into the
-- configured min..max range.

local AUTO_FAMILIES = {
  wet    = { p1 = 37.0, p2 = 13.7, phase = 0.0 },
  frozen = { p1 = 43.0, p2 = 17.3, phase = 1.3 },
  grain  = { p1 = 29.0, p2 = 11.1, phase = 2.6 },
  haze   = { p1 = 61.0, p2 = 23.9, phase = 3.9 },
  light  = { p1 = 23.0, p2 =  8.3, phase = 5.2 },
}

Settings.AUTO_FAMILIES = AUTO_FAMILIES

-- Which family a channel belongs to.  Channels absent from this map do not
-- breathe at all -- deliberately: the grade channels (dim, cool, warm,
-- glare) drive a full-screen multiply, and a full-screen multiply that
-- pulses does not read as weather, it reads as a fault.
Settings.CHANNEL_FAMILY = {
  rain = "wet", splash = "wet",
  snow = "frozen",
  hail = "grain", sand = "grain", debris = "grain",
  fog = "haze", veil = "haze",
  strike = "light",
}

-- `t` is the weather clock in seconds.  Returns the multiplier for one
-- family, or 1 when AUTO is not selected -- so the caller needs no branch.
function Settings.autoScale(family, t, config)
  if Settings.get("intensity") ~= "auto" then return 1 end
  local f = AUTO_FAMILIES[family or ""]
  if not f then return 1 end
  local cfg = config and config.get().autoIntensity
  local lo = (cfg and cfg.min) or 0.5
  local hi = (cfg and cfg.max) or 1.4
  local rate = (cfg and cfg.seconds) or 1
  if rate <= 0 then rate = 1 end
  t = (tonumber(t) or 0) / rate
  -- 0.7/0.3 weighting: a long swell with a shorter ripple on top, rather
  -- than two equal waves, which would read as a beat frequency
  local a = math.sin((t / f.p1) * 2 * math.pi + f.phase) * 0.7
  local b = math.sin((t / f.p2) * 2 * math.pi + f.phase * 1.7) * 0.3
  local unit = (a + b + 1) * 0.5          -- -1..1 -> 0..1
  if unit < 0 then unit = 0 elseif unit > 1 then unit = 1 end
  return lo + (hi - lo) * unit
end

-- Weather lifetime multiplier. Values below 1 expire the current weather sooner.
-- This scalar is consumed only by dwell/lifetime scheduling; it must never be
-- used for particles, wind, clouds, audio, game time or transition animation.
local SPEED = { normal = 1.0, ["2x"] = 0.50, ["4x"] = 0.25,
                ["10x"] = 0.10, ["20x"] = 0.05 }
function Settings.speedScale()
  return SPEED[Settings.get("speed")] or 1
end
Settings.weatherLifetimeScale = Settings.speedScale

-- How much the region bias is allowed to suppress an out-of-place
-- weather.  1 means "no suppression at all"; the built-in bias multiplies
-- by 0.2, so this is blended against that rather than replacing it, which
-- keeps the geography meaningful at every setting except OFTEN.
local EXOTIC = { off = 0, rare = 1.0, normal = 3.0, often = 7.0 }
function Settings.exoticScale()
  local v = EXOTIC[Settings.get("exotic")]
  if v == nil then return 3.0 end
  return v
end

-- 0 = no weather in battle, 1 = the same as the overworld.
local BATTLE = { off = 0, subtle = 0.5, full = 1 }
function Settings.battleAnimOn()
  -- 8.1.97: BATTLE WEATHER is the single visual authority. The former
  -- WEATHER VISUALS row duplicated BATTLE WEATHER=OFF, so it is no longer
  -- player-facing. Keep this helper for existing runtime call sites.
  return Settings.battleScale() > 0
end

function Settings.battleDamageOn()
  local v = Settings.get("battleDamage")
  if v == "off" then return false end
  if v == "on" then return true end
  local legacy = nil
  pcall(function() legacy = mod.options:get("battlerules") end)
  if legacy == "off" then return false end
  return true
end

function Settings.battleScale()
  return BATTLE[Settings.get("battles")] or 0.5
end

function Settings.set(key, value)
  -- Soft write into live config for host-driven defaults (e.g. daytime off on Dramaless).
  pcall(function()
    local Config = V.require("Config")
    local c = Config.get()
    if not c then return end
    if key == "daytime" and c.time then
      c.time.source = (value == "off") and "off" or (c.time.source or "auto")
    end
  end)
end

return Settings
