# Rising-Gods changes (branch `rising-gods`)

Local changes for WoW 3.3.5a on Rising-Gods, on top of the
**Hypopheria Remaster** (TidyPlates 6.6.0 / Threat Plates 6.0):

- Repository: <https://github.com/hypopheria2k/TidyPlates_3.3.5a>
  (itself based on bkader's TidyPlates_WoTLK)
- Forum thread: <https://www.rising-gods.de/forum/41-addons/871300-tidyplates-335a-remaster.html>

This branch starts at hypopheria's commit `3ad7272` ("added colorpicker for
pets", 2026-05-05), which is exactly the version that was installed. Every
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
- Target = soft glow (Blizzard glow texture, color configurable), name above
  the bar, health text as in "Default", Plater-style auras above the name,
  interrupt castbar colors and stacking as in the Plater look.

## Stacking

Ported from the WeakAura *Cheeta - Enhanced Stacking Nameplate* (same
formulas). Spacing is computed from bar size and name position. The current
target stays above its model and other plates move around it. The WeakAura's
in-combat hitbox trick is not included (it closed open windows). **Disable
the WeakAura** when using this, otherwise both move the plates.

## Commands and options

| Command | Effect |
|---|---|
| `/tptpplater` | Create/activate profile "Plater" (copy of the current profile) and reload |
| `/tptpplater reset` | Re-apply the Plater look to the profile and reload |
| `/tptpplater default` | Switch back to profile "Default" and reload |
| `/tptpclassic` / `reset` / `default` | Same for the Classic look (profile "Classic") |
| `/tptpclassic info` | Print the measured geometry of the original plate |
| `/tpprof on` / `off` | Toggle CPU profiling (then `/reload`) |
| `/tpprof kampf` | CPU report after every fight |
| `/tpprof` | CPU report since the last start |

Options: `/tptp` → tab **Plater** (border, border size, target indicator,
target glow, health text format, stacking, pin target, speed, tall boss fix,
Classic look toggle, target glow and color).

## Credits

- Target indicator textures: [NotPlater](https://github.com/RichSteini/NotPlater)
  by RichSteini, MIT license (`TidyPlates_ThreatPlates/Media/NotPlater/LICENSE.txt`).
- Stacking algorithm: WeakAura *Enhanced Stacking Nameplate* by Cheeta
  (wago.io/AQdGXNEBH).
