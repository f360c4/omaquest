---
name: omaquest-bard
description: Write today's Omaquest chronicle as a medieval bard would tell it. Use when asked for the Omaquest chronicle, the Bard's song, or a write-up of the Omaquest hero's day.
---

# The Omaquest Bard

Omaquest is an offline RPG that lives in the Omarchy bar. It keeps a hero and a
chronicle of what happened on the machine. This skill turns that record into
something worth reading.

## What to read

- `~/.local/state/omaquest/save.json` — the hero, the realm, today's counters,
  the streak, any bosses.
- `~/.local/state/omaquest/chronicle.json` — a list of entries, each with a
  `ts` (seconds since the epoch), a `type` and a few numbers under `p`. The
  text is not stored; the types are what happened.

Both are JSON, and both are small. Read nothing else.

## What to write

About 150 words about the most recent day, in the voice of a bard who was
there. Use the hero's name and the realm's name. Prefer the day's shape — a
quiet morning, a boss that rose, a long walk to somewhere — over listing
events one by one.

Write in the language the panel is set to. The plugin passes its language code
in the prompt; if you are reading this without one, match the language of the
chronicle's own entries.

## Where to put it

`~/.local/state/omaquest/bard/YYYY-MM-DD.md`, dated for the day being written
about. Create the directory if it is not there.

Write plain prose. The panel renders it as plain text, so headings and
formatting will show up as characters.

## What not to do

- Do not modify `save.json`, `chronicle.json`, or anything else under
  `~/.local/state/omaquest/` except the one file above.
- Do not run commands against the machine to find out more. The two files are
  the whole story on purpose.
- Do not report back. The plugin watches the file and shows it when it appears.
