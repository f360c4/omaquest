# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-09-23

First release. The hero, the chronicle, the arena, expeditions, the forge and
the settings all landed in one go, because a plugin installed from git is
updated by hand and a half-finished one would have stranded whoever tried it.

### Added
- Plugin skeleton: manifest, headless service, bar widget and panel. The plugin
  loads in `omarchy-shell`, sits in the bar and opens a panel that closes on Esc
  and switches with Tab.
- English and Brazilian Portuguese dictionaries, with the loader carried over
  from Omacall.
- `tools/lint.sh` and `tools/check-i18n.sh`.
- The rule set: `game/Rules.js`, `game/World.js`, `game/Migrations.js` and
  `game/Chronicle.js`, as pure JavaScript with no Qt in it, plus 58 tests that
  run under plain node.
- The save: `~/.local/state/omaquest/save.json` and `chronicle.json`, written
  atomically and at most once every five seconds. Health and energy regenerate
  by elapsed time on read, so a week with the machine off works.
- A save that cannot be parsed is moved aside rather than deleted, and the
  chronicle records that it happened.
- Onboarding (name, race, class) and the hero sheet.
- `omarchy-shell f360c4.omaquest status` reports the hero as JSON.
- `tools/balance.js`, which measures the arena and calibrates it.
- The hero, drawn. Nineteen 1-bit text grids under `assets/sprites/`, five
  races over five classes, tinted with the bar's own foreground so a theme
  change recolours them live. Six animations — idle, walk, fight, hurt, sleep,
  cheer — built procedurally from two frames per body.
- The sprite in the bar at 16 pixels, on the hero sheet at 64, and on every
  onboarding card at 48, so all twenty-five race and class combinations can be
  seen before choosing one.
- An optional `Lv N` beside the sprite on horizontal bars, and a tooltip with
  health and energy.
- `tools/check-sprites.sh` and `tools/sprite-preview.sh`.
- The realm is the machine. Workspaces visited, applications and terminals
  opened, windows, music playing, theme changes, rest and time at the keyboard
  all become experience and a line in the chronicle. On a laptop, the battery
  becomes weather.
- The Chronicle tab, grouped by day, written from the dictionary at render time
  so it changes language with the panel.
- Tabs in the panel, and a right click on the bar that opens the chronicle
  directly. `omarchy-shell f360c4.omaquest tab <name>` does the same.
- `status` reports sensor counts, so a bug report can tell a broken sensor from
  a quiet desktop.
- The Arena. A program crashing on your machine becomes a boss named after it;
  crashing again makes that boss angrier rather than adding a second. A
  Guardian turns up at the weekend so that a machine which never crashes still
  has something to fight, and three wanderers are drawn from the date so the
  list is never empty.
- Turn-based fights: attack, your class's skill, defend, flee. Four buttons, a
  four-line log, and no clock — the enemy moves when you do. Losing costs
  nothing but half an hour in the tavern: no experience, gold or item is ever
  taken back.
- Nine more sprites, for the bestiary and the Guardian.
- Expeditions. Three destinations a day, drawn from the date; the hero walks
  the bar while away. Only an end time and a seed are stored, so closing the
  laptop mid-journey and opening it a week later finds the result it would have
  found on time.
- The Forge. Nine recipes across weapon, armour and amulet; a dwarf pays one
  material less per line. A new item goes to the chest, and equipping swaps
  rather than destroys, so trying something costs nothing.
- Today's three quests with live progress on the hero sheet, the Seal, and what
  is worn.

### Fixed
- Every shell restart paid experience again for the workspace you were sitting
  on. The day's counted workspaces are now part of the save.

### Changed
- The combat, health and skill formulas from the specification, which do not
  survive measurement. See `docs/decisions.md`.
