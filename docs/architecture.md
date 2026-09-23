# Architecture

How the pieces fit, and why they are arranged this way. `decisions.md` carries
the divergences from the specification and the measurements behind them.

## The shape

```
                      shell.json entry          ~/.local/state/omaquest/
                      (settings only)           save.json · chronicle.json
                            ▲                            ▲
                            │                            │ the only writer
   ┌────────────────┐       │            ┌───────────────┴────────────────┐
   │ BarWidget.qml  │───────┴───────────▶│          Service.qml           │
   │  one per       │  bar.shell         │  one per session               │
   │  monitor       │  .serviceFor(id)   │  sensors · timers · dispatch   │
   └───────┬────────┘                    └───────────────┬────────────────┘
           │ Loader                                      │
           ▼                                             ▼
   ┌────────────────┐                     ┌──────────────────────────────┐
   │   Panel.qml    │  game.dispatch(e)   │   game/World.js              │
   │  six tabs      │────────────────────▶│   apply(state, event, now)   │
   │  components/*  │◀────────────────────│   → { state, effects }       │
   └────────────────┘  game.world         └──────────────┬───────────────┘
                                                         │ asks
                                          ┌──────────────▼───────────────┐
                                          │  game/Rules.js               │
                                          │  numbers, no state, no Qt    │
                                          └──────────────────────────────┘
```

## Why the service owns everything

The bar mounts a widget **per monitor**. A hero that lived in the widget would
be one hero per screen, each with its own save file, racing the others to write
it. `Service.qml` is mounted once for the session, owns the state, and is the
only thing that writes to disk. Widgets and panels read from it and send events
back.

`keepLoaded: true` in the manifest means that instance survives a plugin
hot-reload — which is why editing `Service.qml` during development needs a full
`omarchy-restart-shell` and editing a view does not.

## Why the rules have no Qt in them

`game/Rules.js`, `World.js`, `Migrations.js` and `Chronicle.js` are plain
JavaScript libraries. They never touch a QML type, a file, or a clock they were
not handed. That is what makes `node tests/rules.test.js` possible: 99 tests
over the shipped code, with no shell, no compositor and no display.

It is also why the arena could be measured and rebalanced (`tools/balance.js`)
rather than guessed at.

- **`Rules.js`** answers questions about numbers. Given a hero, how much health?
  Given a tier and a hero, what enemy? It holds no state and mutates nothing.
- **`World.js`** is the only place state changes. `apply(state, event, now)`
  returns a new state and a list of **effects** — `save`, `chronicle`, `notify`,
  `anim`. Effects are data, not calls: World says a notification is warranted,
  and the service decides whether today's budget allows it.
- **`Migrations.js`** runs on every load. It is less about version steps (there
  is one schema so far) than about `sanitize`, which is what guarantees the rest
  of the code can do arithmetic on what it read: every number through `num`,
  every enum checked against the rule set, every list bounded, unknown keys
  dropped, derived fields re-derived rather than trusted.
- **`Chronicle.js`** turns an entry into a sentence at render time. An entry
  stores a type, a seed and a few ids; the words come from the dictionary. That
  is why the chronicle rewrites itself in Portuguese when the panel language
  changes, and why 300 entries are a few kilobytes.

## Time

Nothing runs in the background to make the game progress.

- **Health and energy regenerate lazily.** Both carry the moment they were last
  correct and are caught up when read. A week with the machine off works the
  same as a week with it on.
- **An expedition stores an end time and a seed.** The result is computed from
  the seed whenever anyone collects it, so late and on time are the same
  journey.
- **The day rolls over on the minute tick**, and the rollover is written
  immediately rather than on the five-second debounce, because a machine that
  shuts down in those five seconds would come back to a day it had spent.

## Budget

| Timer | Interval | What it does |
|---|---|---|
| world tick | 60 s | Catch up health and energy, one session minute, music, expiring bosses, the weekend guardian, a due expedition, the day rolling over |
| compositor debounce | 1 s, single-shot | Fold a burst of window events into one pass |
| theme debounce | 2 s, single-shot | One event for a theme change, however many colours moved |
| save debounce | 5 s, single-shot | At most one write every five seconds |
| coredumps | 15 min | If `coredumpctl` is there |
| agent tokens | 15 min | Only if switched on |
| commits | 30 min | Only if switched on |

Nothing runs faster than the one-second debounce, and nothing runs at all with
no hero.

## Drawing

`components/PixelSprite.qml` draws a 1-bit grid as scene-graph rectangles, one
per horizontal run of lit cells rather than one per cell — which takes a 16×16
body from up to 256 items to about 25. Both frames of every layer are built
once and take turns being visible, so a frame change creates nothing and
rasterises nothing.

Nineteen grids cover five races, five class overlays and two effects. Walking,
fighting, being hurt, sleeping and cheering are the same two frames at a
different cadence, with a one-pixel offset, or with an effect laid over them.

## Reactivity

`Service.world` is a plain JavaScript object, reassigned whole after every
`apply`. QML cannot bind deeply into one, so the service also carries an
integer `revision` that it bumps on every change, and views read through it:

```qml
readonly property int revision: game ? game.revision : 0
readonly property var hero: { revision; return game ? game.hero() : null }
```

Simple, and impossible to get partially out of step — everything re-reads or
nothing does.
