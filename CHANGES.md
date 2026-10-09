# Changes in this fork

Changes for WoW 3.3.5a on top of the
**Hypopheria Remaster** (TidyPlates 6.6.0 / Threat Plates 6.0):

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

## Castbars

- Castbar stays enabled (`settings.castbar.enabled`); the CVar
  `showVKeyCastbar` is restored after ElvUI's nameplate module disables it.
- Castbars for non-target units, timed from `GetSpellInfo` cast times and
  stopped on success, failure, interrupt or death; enabled by default.
- Mouseover provides exact cast times and aura updates.

## GUID assignment (nameplates have no GUID in 3.3.5a)

Target and mouseover are authoritative. Additionally, only when unique:

1. Focus, pet target, party/raid targets and `boss1-4`: match name + health.
2. Raid markers: combat log flags and `GetRaidTargetIndex` map each marker to
   a GUID; the plate showing that marker gets it.
3. Fingerprint: a damaged plate that disappears is recognized again within
   30 s by name, level and plausible health.
4. Damage correlation: combat log damage matched to the health drop of
   exactly one plate within 0.35 s.

## Colors and tank view

- Out of combat hostile = red. In combat: purple = own aggro, orange = losing
  aggro, yellow = about to pull, blue = other tank or crowd controlled,
  red = no aggro. Threat color wins over raid marker colors.
- `threat.alwaysTank` (default on): tank view on every spec.
- Tank detection rewritten for 3.3.5a (`UnitGroupRolesAssigned` returns
  booleans, raid members, per-plate updates).

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
- Castbar like WoW Forever: attached under the bar, as wide as bar + level
  box, gold/yellow while your interrupt is ready, grey on cooldown, lock for
  uninterruptible casts; spell name and remaining time below.
- Name above the bar, health text as in "Default", Plater-style auras above
  the name, interrupt castbar colors and stacking as in the Plater look.
- Quest icon (any profile, option `questIcon`): shown in front of the name of
  mobs that are an open kill objective in the quest log (matched by name via
  `QUEST_MONSTERS_KILLED`). Collect objectives and quests under collapsed
  headers are not detected.
- Combo points (classic frame): five separate segments with a 2 px gap, same
  colors as the original art (1 blue ... 5 red).
- Debuff timer on the aura icons (option "Show elapsed time", any look,
  default "Clock"): "Bar (grey)" greys out and darkens the elapsed part from
  the top with a golden edge; "Clock" draws a dark clock sector from 12 o'clock with a golden
  hand (built from rectangles and a triangle texture, because cooldown models
  are not drawn on nameplates in 3.3.5a).

## Stacking

Ported from the WeakAura *Cheeta - Enhanced Stacking Nameplate* (same
formulas). Spacing is computed from bar size and name position. The current
target stays above its model and other plates move around it. The WeakAura's
in-combat hitbox trick is not included (it closed open windows). **Disable
the WeakAura** when using this, otherwise both move the plates.

- **Two columns** (option "Two stacks from", default 6): plates that overlap
  horizontally form a tower; from the threshold on they split into a left and
  a right column one plate width apart, the target stays pinned between them.
  Sides are sticky (no jumping while mobs move), offsets glide in and are
  applied with left/right clamp insets, so the mouseover area moves along.
- **Only engaged enemies** (option "Only stack engaged enemies",
  default on): in combat, plates of enemies not fighting me, my pet or my group stay
  in place and push nobody. Engaged = target/mouseover, threat glow, or a
  combat log exchange with us (by GUID; without GUID by name, and right after
  a pull the lowest plates on screen of that name). Out of combat everything
  stacks as before.

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
Quest icon. Profiles are switched via the regular profile dropdown; each look
page has a "Reset look" button (enabled only in the matching profile).

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
