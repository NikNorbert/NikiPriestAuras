# Changelog

All notable changes to NikiPriestAuras are documented here.

## [Unreleased]

## [1.8.17] - 2026-08-30

### Fixed

- Fixed the complete addon load failure caused by exceeding Vanilla Lua's
  200-active-local-variable limit after the slash-command update.
- Reduced the main chunk to 189 top-level locals so future small additions
  have safe headroom below the client limit.

## [1.8.16] - 2026-08-30

### Changed

- Reduced the public slash-command interface to `/npa`, `/npa show`,
  `/npa hide`, `/npa set`, `/npa reset` and `/npa test`.
- `/npa hide` now persistently disables all addon visuals, including the
  player-frame shield counter, while `/npa show` restores them.
- Removed legacy movement, opacity, proc, aura-test, long-name and shield-debug
  slash-command aliases; those options remain available in `/npa set` where
  applicable.

## [1.8.15] - 2026-08-30

### Added

- Added a localized checkbox in the Aura section of `/npa set` for disabling
  the animated `Enlightened` screen aura independently of its reminder icon.

## [1.8.14] - 2026-08-30

### Added

- Added `Power Word: Shield` durability numbers to the original Blizzard
  player frame while retaining the existing pfUI display.
- Added a localized `/npa set` selector for choosing the pfUI or original
  Blizzard player frame.

### Changed

- Shield-display switching now immediately restores the native health text on
  the previously selected player frame.

## [1.8.13] - 2026-08-30

### Added

- Added automatic English settings localization for every client locale except
  `ruRU`, which keeps the existing Russian interface.
- Added repository screenshots for the complete custom reminder artwork set and
  the settings window.

### Changed

- Reworked the GitHub README as a complete English project page with updated
  installation, configuration, screenshot and release instructions.

## [1.8.12] - 2026-08-30

### Changed

- Extended the subtle amber undertone through roughly the lower half of the
  custom `Inner Fire` flame, with an irregular translucent fade that keeps the
  artwork predominantly pearl white.

## [1.8.11] - 2026-08-30

### Changed

- Refined the custom `Inner Fire` reminder with more realistic translucent
  chemical-flame detail and a restrained amber-orange heat gradient at its
  base, while keeping the upper flame pearl white.

## [1.8.10] - 2026-08-30

### Changed

- Shifted the custom `Inner Fire` reminder to a predominantly pearl-white holy
  flame, retaining blue only in its translucent shadows and a thin lavender
  outer glow.

## [1.8.9] - 2026-08-30

### Changed

- Reworked the custom `Inner Fire` reminder into the shared white, icy-blue and
  restrained violet holy-magic palette used by the other reminder artwork.
- The new realistic flame texture uses additive blending, removing its black
  background in game while preserving the soft outer glow.

## [1.8.8] - 2026-08-30

### Fixed

- `Searing Light` animation no longer freezes or restarts while the player is
  moving.
- Proc detection now prefers the stable Vanilla `GetPlayerBuff` API and keeps
  the extended `UnitBuff` spell-id check as a fallback.
- Animation timing now uses the game clock to avoid movement callbacks from
  overwriting the Vanilla global elapsed-time argument.

### Current feature set

- Independent settings and drag positions for icons, `Enlightened` aura and
  `Searing Light` proc.
- Configurable icon spacing, element size/opacity and proc animation speed.
- Custom or original reminder textures.
- pfUI `Power Word: Shield` durability display with recast and absorb tracking.
- Smooth `Weakened Soul` warning, animated `Enlightened` aura and proc
  screen-edge glow.
- Automatic hiding during taxi travel.
