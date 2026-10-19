# Changes in this fork

Changes for WoW 3.3.5a on top of the
**Hypopheria Remaster** (TidyPlates 6.6.0 / Threat Plates 6.0).
Current version of this fork: **TidyPlates 6.11.0 / Threat Plates 6.5**.

Based on:

- Repository: <https://github.com/hypopheria2k/TidyPlates_3.3.5a>
  (itself based on bkader's TidyPlates_WoTLK)

This branch starts at hypopheria's commit `3ad7272` ("added colorpicker for
pets", 2026-05-05), the published Remaster version. Every
following commit contains one round of changes, so `git log -p` shows
exactly what changed. Later hypopheria commits (pet color fix, BG scanner,
chat bubble visibility) are not merged yet.

> Note: WoW 3.3.5a only picks up **new files** (new Lua files, new textures,
> new addon folders) after a full client restart. `/reload` is enough for
> changes to existing files.

## Performance

- Threat glow, combat state and crowd control are polled at 10 Hz instead of
  a full update of every plate on each `UNIT_THREAT_SITUATION_UPDATE`.
- Health updates are batched (at most one per plate and frame), delegate
  updates are queued per plate.
- On target change only the old and the new target get a full update.
- Threat Plates memoizes the style per unit; widget layout runs only on
  initialize.
- Debuff widget: no event-dropping throttle, early combat log filtering.
- Stacking (see below) runs in the TidyPlates update loop instead of a
  WeakAura scanning all WorldFrame children every 20 ms.
- Raid load (2026-10-08): debuff combat log events are coalesced per unit and
  frame, the API rescan only runs when the unit has a plate, aura tables are
  pooled. Damage correlation only runs on new entries and only records damage
  for names of plates without GUID. Threat events bring the state poll forward
  to at most 20 Hz instead of every frame. Tank target tracking is throttled
  to 4 Hz (a tank swap turns blue up to 0.25 s later), tank auras are
  re-checked per changed unit. An expired aura only updates its own plate.
- Threat Plates style memo keyed on "damaged yes/no" instead of time and
  health; unique units via a name index; health text cached per plate; the
  custom statusbar re-anchors only on layout changes; interrupt cooldowns
  read once per frame; cast timer text only on a new tenth; classic look sets
  fonts/anchors only when they differ.
- Stacking compares only x-neighbors (sorted) instead of all pairs.
- Fixes: aura list was a weak table with inverted cleanup (debuffs on
  non-targets vanished, expired lists leaked); auras of dead units are freed;
  `HideIn` watcher never restarted after its first pause; group cache skipped
  the last raid member; kick highlight flickered on every plate update; cast
  start color ignored the remaining cast time; recycled plates inherited the
  stacking offset; `threatWarning` compared as number; classic combo strip got
  an extra CENTER anchor; class icon not hidden without class info.
- Review after 6.9.0 (2026-10-16):
  - Crowd control no longer resets every plate: each CC applied or removed on
    any hostile unit ran a full `ForceUpdate` (all plates faded in again and
    lost their non-target castbars). The CC color now comes from the 10 Hz
    state poll, which is brought forward on CC events.
  - Debuff clock and bar redraw only what changed (full quarters when the
    hand enters the next one, hand anchored once, Show/Hide on transitions);
    the redraw interval follows the duration (1/360 of it, 4-30 per second).
  - `UNIT_AURA` of target, focus and mouseover is batched per frame together
    with the combat log events of the same unit; spell names and icons are
    cached per spell ID.
  - Plater border and Classic look are no longer updated twice per update
    (context + normal update); the other frame styles' parts are hidden only
    on a style switch; the gold style re-places level and skull only after
    a style reset (`extended.styleSerial`) or size change.

## Castbars

- Castbar stays enabled (`settings.castbar.enabled`); the CVar
  `showVKeyCastbar` is restored after ElvUI's nameplate module disables it.
- Castbars for non-target units, timed from `GetSpellInfo` cast times and
  stopped on success, failure, interrupt or death; enabled by default.
- Mouseover provides exact cast times and aura updates.
- Exact non-target castbars: at 5 Hz the cast watcher reads
  `UnitCastingInfo`/`UnitChannelInfo` of focus, focus target, target of
  target, pet target, `boss1-4`, `arena1-5` and the party/raid members'
  targets. Their plates get exact times, channels (the combat log has no
  channel start), pushback and the interruptible flag, and the bar ends as
  soon as the unit stops casting (stun, silence, juke).
- The target's cast continues on its plate after you switch targets (it is
  remembered with exact times instead of being dropped).
- Uninterruptible casts are learned per caster name and spell
  (`TidyPlatesData.CastShieldByCaster`) instead of per spell name, so one
  boss's uninterruptible Shadow Bolt no longer locks every mob's. Exact
  information from the client always wins over the learned value.

## GUID assignment (nameplates have no GUID in 3.3.5a)

Target and mouseover are authoritative (only for a plate with the unit's
name, so a plate that still looks like the target for a frame after a target
change keeps its GUID). Additionally, only when unique:

1. Focus, pet target, party/raid targets and `boss1-4`: match name, health,
   level and raid marker; unhurt NPCs are skipped (a same-named unhurt plate
   would match when the unit's own plate is not visible).
2. Raid markers: combat log flags and `GetRaidTargetIndex` map each marker to
   a GUID; the plate showing that marker gets it.
3. Fingerprint: a damaged plate that disappears is recognized again within
   30 s by name, level and plausible health.
4. Damage correlation: combat log damage matched to the health drop of
   exactly one plate within 0.35 s.

The debuff and crowd control widgets no longer write a GUID guessed from a
raid marker into the plate: their marker cache was never cleared, so a mark
moved to another mob showed the previous mob's debuffs and CC. The caches are
wiped on `RAID_TARGET_UPDATE` and used only when the plate's name matches.

## Colors and tank view

- Out of combat hostile = red. In combat: purple = own aggro, orange = losing
  aggro, yellow = about to pull, blue = other tank or crowd controlled,
  red = no aggro. Threat color wins over raid marker colors.
- `threat.alwaysTank` (default on): tank view on every spec.
- Tank detection rewritten for 3.3.5a (`UnitGroupRolesAssigned` returns
  booleans, raid members, per-plate updates).
- Blue (another tank holds the enemy) no longer needs someone targeting that
  enemy right now: its last known target is remembered until a newer
  observation, its death or the end of combat. Sources: target, mouseover,
  focus, pet and group targets, and auto attacks (melee/ranged swings and
  misses) of enemies on group members from the combat log, so AoE-tanked packs
  turn blue as soon as they hit the tank. Without any information a plate
  keeps its last color instead of turning red - also while an enemy has no
  target for a moment (casting, enraged, stunned, fleeing).
- Threat colors apply as soon as the player or any group member is in combat
  (e.g. the tank pulled before you are in combat). Only the color: alpha,
  scale, threat border and stacking still follow your own combat state.

## Plater look (profile "Plater")

- Crisp 1 px border around health and cast bar; white = target,
  grey = mouseover.
- Health text `4.3k (100%)`, name below the bar, small level at the top
  right, raid icon left of the bar, constant size (no threat scaling).
- Castbar below the bar: spell name left, remaining time right, dark
  background; the name is hidden while casting.
- Auras: 24x18 icons with border and large centered timer.
- Target indicators from NotPlater (Silver, Magneto, Golden, Epic, arrows,
  ...) and a blue target glow.

## Classic look (profile "Classic")

- Original Blizzard art: gold border with level box, elite dragon, mouseover
  highlight, castbar border (shield border for uninterruptible casts).
- The TidyPlates core records texture, tex coords and position of the
  original regions relative to the original health/cast bar when the first
  plate is created (`TidyPlates.BlizzardArt`); the widget scales them onto
  the bars.
- Look version 2 (modeled on the Classic Era client): the target's border
  and level box are desaturated and tinted yellow-green (optional soft glow),
  non-target plates are scaled to 75 %, slightly smaller level font, name
  truncated to bar width.
- Smooth size change (options "Smooth size change" and "Transition time",
  default on, 0.2 s): when you target or clear a target, the plate grows or
  shrinks smoothly to its new size instead of jumping. The TidyPlates core
  animates scale changes (`TidyPlates:SetScaleAnimation(seconds)`, smoothstep
  easing); newly shown plates take their size immediately. Pixel-sized
  borders are computed for the final size.
- Castbar like WoW Forever: attached under the bar, as wide as bar + level
  box, gold/yellow while your interrupt is ready, grey on cooldown, lock for
  uninterruptible casts; spell name and remaining time below.
- Castbar spark (option "Castbar spark", default on): the Blizzard castbar
  spark (`Interface\CastingBar\UI-CastingBar-Spark`, additive) glows at the
  end of the fill like on the ElvUI/Blizzard player castbar. It is anchored to
  the fill edge, so it moves without an own update.
- Target glow (options "Target: glow", "Color", "Glow size", "Glow around the
  castbar"; on in the profile "Classic"): a soft glow in the Blizzard UI gold
  (1 / 0.82 / 0, 90 %) around the target's frame and level box, brightest at
  the line and fading out over 5 units. Optionally it also surrounds the
  castbar while the target casts. Drawn as a nine-slice from a radial gradient
  (`Media/ClassicGlow.tga`, new file - needs a full client restart once).
  With the gold frame style the option keeps the Blizzard glow behind the plate.
- The level number is centered in its box: the font box reserves room for
  descenders that digits don't have, so it moves down by 15 % of the font size.
- Defaults of the profile "Classic": border size 1, glow size 5.
- Border styles that look like WoW Forever's nameplates (option "Style").
  Switching the style also sets its bar size, fonts and bar textures:
  - **Forever Modern** (default for new "Classic" profiles): 133 x 13 bar with
    own textures (`Media/Forever`, drawn by `tools/forever_textures.py`;
    new files - needs a full client restart once). Sizes follow Forever's
    default style "Thin"; where that didn't work on our plates the values
    were tuned in-game:
    - Health fill without dark shading at the top and bottom and with a soft
      left-to-right gradient (75 % to 100 % brightness; Forever's runs from
      about 53 %, which made the start of the bar and low-health bars look
      much darker).
    - Dark background with a thin gray rim right at the bar on every side
      (placed symmetrically; Forever's offsets leave the rim further out on
      the right and bottom), no shadow (it showed as a gray box on light
      ground). 30 % darkening of every non-target, gray line
      on mouseover.
    - Level box in the bar's style (same background and rim instead of
      Forever's gold-rimmed level indicator), 24 wide, as high as the bar
      including its rim, 4 units right of the bar.
    - Target: yellow line with a gold glow around bar and level box. Glow
      and line are separate layers: the glows lie below bar and box and
      merge in the gap, the lines lie above, so neither the bar
      nor the box covers them. Between the lines of bar and box, and between
      the bar and the castbar's kick line, stays a 1 unit seam.
    - Name in Friz Quadrata 12 and health text 10, both outlined (the health
      text keeps its configured format), name 2 above the bar centered over
      bar + box, health text right in the bar.
    - Castbar 6 high, 4 below the bar, as wide as bar + box, marbled fill
      tinted by the interrupt colors, background like the bar's, white line
      around it while your interrupt is ready; icon and
      spell name (10) below it. No extra golden glow around the castbar in
      this style (it lies in the bar's glow).
    - Auras left-aligned with the bar.
    - Options of the style (*Target*): "Target: color border" switches the
      line, "Target: glow" the glow, "Glow size" sets its reach (50-150 % of
      Forever's), "Border size" the line thickness (50-200 % in 25 % steps,
      one texture per step rendered with the same beveled corners; the
      gaps to the level box and the castbar grow with the line so the seams
      stay 1 unit wide). Glow color, line color and "Glow around the castbar"
      don't apply to this style and are greyed out.
    - No atlas region ends right at a neighbouring element (texture
      filtering let neighbours bleed in, e.g. a gray line below the castbar).
  - **Forever Classic**: classic gold border around a 104 x 10 bar, name and
    health text 10, name 4 above the border, castbar as tall as the bar in the
    classic castbar border 4 below.
  - **Simple**: the previous rounded line with level box.
- Aura stack counts sit in the bottom right corner of the icon (like WoW
  Forever) while the Classic look is on; the second aura row moves closer.
- Name above the bar, health text as in "Default", Plater-style auras above
  the name, interrupt castbar colors and stacking as in the Plater look.
- Quest icon (any profile, option `questIcon`): shown in front of the name of
  mobs that are an open kill objective in the quest log (matched by name via
  `QUEST_MONSTERS_KILLED`). Quests under collapsed quest log headers are
  included: the scan expands them while the quest log window is closed and
  collapses them again. Collect objectives are not detected.
- Combo points (classic frame): five separate segments with a 2 px gap, same
  colors as the original art (1 blue ... 5 red).
- Debuff timer on the aura icons (option "Show elapsed time", any look,
  default "Clock"): "Bar (grey)" greys out and darkens the elapsed part from
  the top with a golden edge; "Clock" draws a dark clock sector from 12 o'clock with a golden
  hand (built from rectangles and a triangle texture, because cooldown models
  are not drawn on nameplates in 3.3.5a).
- Aura icon style (option "Icon style" under *Widgets* → *Debuffs*, any profile):
  "Standard" (small original icons) or "Plater" (24x18 with 1 px border, large
  centered timer, stacks above). Without an explicit choice the Plater and
  Classic look use Plater icons, every other profile the standard ones.
- Threat line (*Widgets* → *Threat Line*) with Plater-style auras: sits above
  the top aura row (one or two rows, clear of stack counts above the icons) or
  in the first row's place without auras. The Plater and Classic layouts had
  moved the auras onto its position, so the icons covered name and bar.

## Stacking

Started as a port of the WeakAura *Cheeta - Enhanced Stacking Nameplate*.
Spacing is computed from bar size and name position. The current target stays
above its model and other plates move around it. The WeakAura's in-combat
hitbox trick is not included (it closed open windows). **Disable the
WeakAura** when using this, otherwise both move the plates.

- **Direct layout** (instead of the aura's step-by-step creeping, which took
  1-2 s for a tower of three): from the bottom up every plate gets the lowest
  free spot at or above its own position, the pinned target first; a plate
  overlapping the target from below is pushed up past it. The stacking order
  follows the shown height, so it stays stable while mobs move.
- **Soft movement** (option "Movement duration", default 0.5 s, replaces
  "Speed"): plates glide to their spot as a critically damped spring - soft
  start, soft stop, no overshoot, a new target mid-move keeps the momentum.
  Runs every frame and is frame rate independent; ~90 % of a move is done
  after the chosen duration.

- **Two columns** (option "Two stacks from", default 6): plates that overlap
  horizontally form a tower; from the threshold on they split into a left and
  a right column, the target stays pinned between them. Each plate stays on
  the side of the tower its mob is on and only moves outwards, never across
  its mob (columns may differ in height); it changes sides only once its mob
  is clearly on the other side. Offsets are applied with left/right clamp
  insets, so the mouseover area moves along.
- **Column style** (option "Column style", default "Staggered"): staggered =
  each side moves out as a whole only as far as needed for the sides to clear
  each other, so plates keep the horizontal offsets of their mobs and stay as
  close above them as possible; straight = the plates of a column are aligned.
- **Only engaged enemies** (option "Only stack engaged enemies",
  default on): in combat, plates of enemies not fighting me, my pet or my group stay
  in place and push nobody. Engaged = target/mouseover, threat glow, or a
  combat log exchange with us (by GUID; without GUID by name, and right after
  a pull the lowest plates on screen of that name). Out of combat everything
  stacks as before.
- **Room for castbars**: while an enemy casts, its castbar (with spell name
  and icon) below the plate is kept clear of the plate underneath.

## Commands and options

| Command | Effect |
|---|---|
| `/tptpplater` | Create/activate profile "Plater" (copy of the current profile) and reload |
| `/tptpplater reset` | Re-apply the Plater look to the profile and reload |
| `/tptpplater default` | Switch back to profile "Default" and reload |
| `/tptpclassic` / `reset` / `default` | Same for the Classic look (profile "Classic") |
| `/tptpclassic info` | Print the measured geometry of the original plate |
| `/tpprof on` / `off` | Toggle CPU profiling (then `/reload`) |
| `/tpprof fight` (or `kampf`) | Chat report after every fight (FPS, plates, CPU) |
| `/tpprof` | CPU report since the last start |
| `/tpprof log` / `clear` | Show / clear the saved fight and error log |

TPProf always saves every fight (≥ 5 s: date, zone, group, profile, FPS
min/avg, visible plates max/avg, Lua memory, enemy targets, top 15 CPU if
profiling is on) and every Lua error with time, zone and stack to `TPProfDB`
(`WTF\Account\<account>\SavedVariables\TPProf.lua`, written on `/reload` or
logout), so results can be read outside the game.

Options: `/tptp` → tab **Extensions** (German client: Erweiterungen) with the
sub-pages Plater look, Classic look, Castbar (interrupt colors), Stacking and
Quest icon. The Classic look page is grouped into General, Target,
Non-targets and Castbar. Profiles are switched via the regular profile dropdown; each look
page has a "Reset look" button (enabled only in the matching profile).

The regular size options keep working in the look profiles: changing the
health bar width/height in `Plater` or `Classic` (or the Classic frame style /
line size) recalculates the size-dependent positions (castbar, name, level,
spell icon, raid icon, auras; `TidyPlatesThreat:RelayoutLook`). "Reset look"
keeps your bar size. Profiles stay independent: `Plater` and `Classic` are
created once as a copy of `Default`, later changes do not carry over.

All texts of these additions are localized: English keys in
`Locales/enUS.lua`, German in `Locales/deDE.lua` (section "Fork
additions"); other clients fall back to English. TPProf has its own small
German table and prints English on non-German clients.

No `/reload` needed: the style files register builders
(`TidyPlatesThreat.StyleBuilders`); a profile change rebuilds all styles,
discards the widgets of every plate (recreated on the next update) and
redraws (`TidyPlatesThreat:ApplyProfileLive`). Option changes rebuild the
styles as well, so sizes and positions apply immediately.

## Credits

- Target indicator textures: [NotPlater](https://github.com/RichSteini/NotPlater)
  by RichSteini, MIT license (`TidyPlates_ThreatPlates/Media/NotPlater/LICENSE.txt`).
- Stacking algorithm: WeakAura *Enhanced Stacking Nameplate* by Cheeta
  (wago.io/AQdGXNEBH).
