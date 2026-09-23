# Decisions

Divergences between the specification and the installed shell, and design calls
the spec left open. The rule is that the installed source wins; each entry says
what was found and what was done about it.

Environment these were verified against: Omarchy `4.0.0.alpha`,
`OMARCHY_PATH=/usr/share/omarchy`, Qt 6.11.2.

## Phase 0

### `OMARCHY_PATH` is `/usr/share/omarchy`, not `~/.local/share/omarchy`

The spec expected the shell source under `~/.local/share/omarchy/shell`. On this
install it is `/usr/share/omarchy/shell`. Every tool reads `$OMARCHY_PATH` and
falls back to `/usr/share/omarchy`, so neither layout is hardcoded.

### `qmllint` is not on `PATH`

`qt6-declarative` ships it at `/usr/lib/qt6/bin/qmllint` and does not link it
into `PATH`. `tools/lint.sh` looks it up there.

### `qmllint` cannot resolve `qs.Commons` without a synthesized root

`import qs.Commons` resolves by looking for `qs/Commons/qmldir` on an import
path. The shell ships the `qmldir` files but not the `qs` root — Quickshell
synthesizes that at runtime. `tools/lint.sh` builds one out of a symlink **in a
scratch directory**, not in the repository: `omarchy plugin validate` rejects a
plugin folder containing symlinks, and Omacall's `Makefile` puts its equivalent
`.qmllint/qs` inside the tree. Keeping it outside means the repository never has
a symlink to forget about.

### qmllint warnings that cannot be written away

The bar facade handed to third-party plugins (`PluginBarApi`) is typed
`QtObject`, and `Loader.item` is typed `QObject`. Every `bar.foreground`,
`Style.font.body` and `panelLoader.item.open()` is therefore a `missing-property`
warning no matter how it is written. The shell's own `omarchy.clock` plugin
carries 68 of them. `tools/lint.sh` prints the count and fails only on errors,
rather than printing "ok" over a wall of warnings.

### One `IpcHandler` warning per extra monitor, by design

The bar mounts one widget per monitor, and each one declares the plugin's
`IpcHandler`. The shell keeps the first and logs
`Handler was registered but will not be used because another handler is
registered for target f360c4.omaquest` for the rest. `omarchy.clock`,
`omarchy.network`, Omacall and every other panel plugin log the same line. This
is the documented pattern, so the warning stays.

### `BarIconButton` instead of a bare `WidgetButton`

The spec sketched the bar slot with `WidgetButton` and a hand-sized `Item`.
`qs.Ui.BarIconButton` already is that: it owns the icon slot, the optical
centering every other bar icon gets, and — relevant from Phase 2 — an
`iconComponent` hook that takes an arbitrary item in place of a glyph. The hero
sprite drops into that hook without the slot geometry changing.

### Third-party plugin ids starting with `omarchy.` are not actually rejected

The spec said `PluginRegistry.validateManifest` rejects them. The installed
source checks for an empty id, `/`, `..` and a leading `/`, and nothing else.
Harmless here — `f360c4.omaquest` is namespaced by author either way — but worth
not relying on.

### The dev tree *is* the plugin directory

`00-LEIA-PRIMEIRO.md` names `~/.config/omarchy/plugins/f360c4.omaquest/` as the
dev folder, and the shell's `inotifywait` watch on that directory means saving a
file reloads the plugin. The git repository therefore lives there directly
rather than being copied into place, and `omaquest-spec/` stays where it is.

## Facts verified on the machine, for the phases that need them

### `coredumpctl list --json=short`

Confirmed working. Each record is
`{"time":<µs since epoch>,"pid","uid","gid","sig","corefile","exe","size"}`.

- `time` is **microseconds**, not seconds — divide by 1e6.
- There is no `COMM` field. The boss name comes from `basename(exe)`, as the
  spec assumed.
- `--since "@<epoch seconds>"` is accepted, so no date formatting is needed.
- With nothing to report it prints `No coredumps found.` rather than an empty
  array, so the parser has to check that the output starts with `[`.
- `uid` is present on every record, so filtering to the current user is a field
  comparison rather than a second command.

### `omarchy agent prompt`

`/usr/share/omarchy/bin/omarchy-agent-prompt` is
`exec omarchy-agent [--inline] --prompt "$*"`. So
`["omarchy", "agent", "prompt", promptText]` is the right argv, and a bare
`omarchy agent` with no arguments launches an interactive agent — never run that
from the plugin.

### `~/.local/state/omarchy/agents/usage/*.json` has no single schema

Each agent writes its own shape. `codex.json` and `fireworks.json` carry
`todayTotalTokens`; `claude.json` does not, and only has
`modelUsage.<model>.{inputTokens,outputTokens,cacheReadInputTokens,…}`. The
arcane sensor prefers `todayTotalTokens` when it is a finite number and falls
back to summing the numeric fields under `modelUsage`; anything else reports the
sensor as unavailable instead of erroring. Every one of these files is mode
`0600` and contains text fields (`authHelpText`, `usageStatusText`) that are
never read.

### `omarchy-notification-send` flags

Confirmed from the script: `--app-name`, `-g/--glyph`, `-u/--urgency`,
`-i/--icon`, `--image`, `-r/--replace-id`, `-t/--expire-time`, `-p/--print-id`,
and `--exec <program> [args...]` last. Default `app_name` is `omarchy-action`
and default urgency is `low`.

## Phase 1

### `keepLoaded: true` means the service survives hot-reload

`shell.qml:_syncServices` keeps an existing service instance across a
`rescanPlugins` ("a kept instance outlives the rescan; hand it the fresh
manifest") and only re-injects `shell` and `manifest`. So saving `Service.qml`
reloads the QML for the widget and the panel but leaves the **old service
object running** — which looks exactly like the new code doing nothing. Editing
anything in `Service.qml` needs `omarchy-restart-shell`, not a rescan. Views
hot-reload normally.

### The save calls the hero's class `cls`, not `class`

`class` is a reserved word in the JavaScript these files are written in.
`Migrations.sanitizeHero` still reads a `class` key if it finds one, so a save
written by a hand-edit or an older sketch is not lost.

### `state` is `world` on the service

Every QML `Item` already has a `state` property (the string that drives QML
state machines). Declaring `property var state` shadows it, and qmllint calls
it out — but the damage is silent, because `state.hero` on a string is
`undefined` rather than an error. Named `world` throughout.

### Daily XP ceilings are counts of paid events

`02-game-design.md` gives each sensor a ceiling in a mix of units — "10 ws",
"15 apps", "20", "30". They are all expressed in `Rules.PASSIVE[*].cap` as a
number of events that are paid, derived from the XP ceiling where the spec gave
one. The counter keeps counting past the cap, so a quest asking for five theme
changes is still completable on a day where only three of them paid.

### The combat numbers in the spec do not survive measurement

This is the largest divergence in the project, and `tools/balance.js` is the
evidence. Running the spec's formulas as written:

| | measured |
|---|---|
| level 1 hero vs tier 1 enemy | **100%** win rate (2 turns to kill, 14 to be killed) |
| by level 16, win rate by class | **0%** (bard) to **71%** (rogue) |
| level 30 turns to kill | 3 (warrior) vs 11 (mage) |

Three causes, each fixed:

1. **`damage = 3 + Strength` gives nothing to a class that never raises
   Strength.** The class primary rises a point a level, so a level 30 warrior
   has 34 Strength and a level 30 mage has 8. Damage now carries a flat
   per-level term: `3 + Strength + level`.
2. **Charisma had no combat meaning at all**, which is why the bard — whose
   primary it is — lost every fight. `skillPower` now reads the class's *own*
   primary rather than Wisdom, so every class has a signature move that grows
   with the attribute that class actually raises. Wisdom keeps its meaning for
   the mage, whose primary it is.
3. **`hp = 12*tier + 2*level` and `atk = 2 + 2*tier + level/5` are fixed
   tables** that cannot track a hero whose classes diverge this hard. An enemy
   is now built against the hero who is about to fight it: it carries
   `TURNS_TO_KILL` turns of that hero's damage, including their skill rotation,
   and hits hard enough to end that hero in `TURNS_TO_DIE`. Tier is a light
   multiplier on top. Class then shows up as how a fight *feels* rather than
   whether it can be won, which is the right shape for a game whose first rule
   is that it never punishes.

Two further changes fell out of the measurements:

- `hpMax` moved from `20 + 4*Vigour + 2*level` to `20 + 3*Vigour + 3*level`. At
  four health a point, a level 30 druid had roughly twice a warrior's health.
- Fights could not terminate. A bard healing 30% of its health every fourth
  turn out-sustained the damage coming in indefinitely — measured at **61
  turns**. From `PRESSURE_TURN` on, everything the enemy lands hits harder each
  turn, so stalling loses rather than draws.

After all of it: the longest fight across every class, level and tier is
**12 turns**, exactly the design budget, and 33 of 40 class/tier/level cells
land inside the 55–85% band. The remaining seven sit a few points outside it; a
six-turn fight quantises hard, so one turn either way moves a cell by tens of
percent. `CLASSES[*].combat.power` are the output of `node tools/balance.js
--tune`, not hand-picked numbers, and re-running it after any change to damage,
health or the skills is the check.

### Two flags for stealth, not one

The spec grants the rogue "a guaranteed dodge on the enemy's next attack **and**
a critical on your next attack". Those are kept on different turns, so they are
`dodgeNext` and `critNext`; a single flag had the enemy's swing consume both.

## Phase 2

### The component is `PixelSprite`, because `Sprite` is taken

`QtQuick` exports a `Sprite` of its own — the frame descriptor for
`AnimatedSprite` and `SpriteSequence` — and it wins the name over a file of the
same name in the plugin's own directory. It is not an `Item`, so the collision
does not surface as "unknown type": it surfaces as
`Cannot assign to non-existent property "anchors"` in whichever file tried to
position one, and then as `Type OnboardingView unavailable` two frames up. The
component is `PixelSprite.qml`.

### Nineteen grids, not ninety

Only `idle_a` and `idle_b` exist per body. Walking, fighting, being hurt,
sleeping and cheering are those same two frames at a different cadence, with a
one-pixel offset, or with a generic effect grid (`fx_sleep`, `fx_cheer`) laid
over them — so five races times six animations times two frames is nineteen
files rather than sixty, and a new animation is a cadence and an offset rather
than ten more drawings.

`SpriteBank.resolve` walks `set_anim_frame` → `set_anim_a` → `set_idle_frame` →
`set_idle_a`, so a missing frame degrades instead of drawing nothing.

### Effect grids stay clear of the gear columns

Class overlays live in columns 0–3 and 13–15 between rows 1 and 14, which is
what lets one overlay sit on any of the five bodies. `fx_sleep` therefore uses
only rows 0–2 at the top right, and `fx_cheer` only the outermost rows, so a
sleeping mage's "z" never lands on their staff.

### Scene-graph rectangles, not a Canvas

`03-arquitetura-tecnica.md` sketched the renderer as a `Canvas` that fills one
rectangle per lit cell, with "PNG plus MultiEffect" as the approved fallback if
it proved costly. Neither is what shipped.

A Canvas rasterises an image and re-uploads a texture on every `requestPaint`,
and the bar's hero breathes every 900 ms for the entire session. Sprites are
therefore stored as **horizontal runs** of lit cells rather than as bitmaps —
which turns a 16x16 body from up to 256 rectangles into about 25 — and each run
is a `Rectangle` in the scene graph, which Qt batches. Both frames of every
layer are built once and take turns being `visible`, so a frame change creates
and destroys nothing; it is two property writes.

That also keeps the fallback unnecessary: no build step, no binary assets, and
`assets/sprites/*.txt` stays the only source of truth.

Measuring it was harder than fixing it, and worth writing down so the next
attempt does not repeat it.

On this machine — twelve bar plugins, one of which polls every two seconds —
`omarchy-shell` burns between 2.4% and 5.7% of a core across 45-second windows
with **the plugin disabled entirely**. A plugin-level A/B is therefore
meaningless at this granularity: one paired run read *lower* with Omaquest
enabled than without it.

The obvious tighter experiment, toggling the sprite's `playing` flag and
comparing, is worse: editing the file is what toggles it, and the resulting
hot-reload dominates the window it was supposed to measure. Samples came back
at 19%, 10%, 9% — all instrument, no signal.

So the honest position for now: the plugin's idle cost is below this shell's
noise floor, and the renderer change was made because rasterising for ever is
the wrong shape for a bar icon, not because a measurement demanded it. A real
number needs a quiet shell — Phase 7, on a bar carrying nothing else.

### The sprite bank is an object, not a singleton

`03-arquitetura-tecnica.md` suggested `pragma Singleton` with a `qmldir` inside
the plugin, and flagged hot-reload as the risk. It is the risk: a singleton
outlives the reload that is supposed to pick up an edited sprite. The bank is
an ordinary `QtObject` owned by `Service.qml` and handed to the views as
`game.sprites`, which is the fallback the spec itself allowed.

## Phase 3

### Workspaces are read off the model, not off the event stream

The spec has the workspace sensor matching a `workspace` raw event. Quickshell
does deliver raw events to a third-party service — `openwindow` arrives with
`ADDRESS,WORKSPACE,CLASS,TITLE` exactly as the shell's own idle service reads
it — but the workspace event name and payload differ between Hyprland versions
(`workspace` carries a name, `workspacev2` an id and a name), and none of the
shell's own widgets rely on either. `Hyprland.focusedWorkspace` already tracks
the answer, so the sensor watches that property instead and never has to guess
an event name.

The workspace the shell starts on is seeded as visited, because a session where
nobody switches workspace should not score zero for the one they spent the day
in.

### `hyprctl dispatch` takes Lua on this Hyprland, which cost an hour

`hyprctl dispatch workspace 3` fails with
`[string "return hl.dispatch(workspace 3)"]:1: ')' expected near '3'` — the
dispatcher argument is evaluated as Lua now. Every scripted workspace switch
used while building the sensor silently did nothing, which looked exactly like
a sensor that was not firing. The sensor was fine.

The lesson is the instrument, not the syntax: `status` now reports
`sensors.compositorEvents`, a count of compositor events seen this session, so
"the sensor is broken" and "the desktop is quiet" can be told apart without
guessing. Counts only — never an event name, never a window class.

### The minute tick is silent

`session_tick` pays no experience and writes no chronicle line. Sixty lines an
hour saying the player was still there would bury everything that actually
happened. It moves the counters that quests read; the milestone every four
hours is what gets written down.

### Nothing that accumulates is unbounded

A burst of compositor events is folded into counters as it arrives rather than
queued, so there is no list to grow; the pending application and workspace
lists are capped at 32 and the day's seen-sets at 256, far above the daily caps
of fifteen and ten. The chronicle is pruned to 300 entries on every append, the
chest to 60 items, active bosses to three, and every file read goes through
`head -c`.

This is deliberate, and it is the lesson from Omacall's marketplace review: the
finding that mattered there was an output queue that a same-user process could
grow without limit. There is no queue here to grow.

## Phase 4

### A crash grows the boss it already made, rather than adding another

The spec says a repeat crash of the same executable makes the existing boss
grow. That is also the only thing standing between a crash loop and a flooded
arena: a program failing two hundred times between polls raises the tier of one
boss, four times at most, and stops. The list caps at three regardless, and the
oldest retreats to make room. A test drives five hundred distinct crashing
executables through it and asserts the list never passes three.

### The core file is never opened

`coredumpctl list --json=short` is an index: time, pid, uid, signal, the path
of the executable, and the size of the dump. The plugin reads the timestamp,
checks the uid against its own, and takes the **basename** of `exe`. It never
runs `coredumpctl info`, `dump` or `debug`, so the core itself — which holds
whatever the program had in memory when it died — is never touched.

### An interrupted fight refunds its energy, and nearly did not

`Migrations.sanitize` clears `arena` on every load on principle: a half-written
fight object must not reach a view. But the service's "a restart cancels the
fight and returns the energy" ran *after* that, found no fight, and returned
early — quietly keeping the point it owed. The event now carries `interrupted`
so the refund happens on the strength of what the loader saw, and a test drives
the real path: start a fight, run the save through `Migrations`, cancel, assert
the energy came back.

### `qs.Ui.Button` has no disabled state

`interactive` belongs to `WidgetButton`, not to `Button`. A `Button` that
should not be clicked uses `Item.enabled`, which stops the click, plus an
explicit opacity, which is what makes it look stopped. Without the second half
it is a button that silently does nothing.

### Losing takes nothing

Worth stating as a rule rather than as an implementation detail, because it is
the one the whole design rests on: a lost fight costs the energy that was
already spent and half an hour in the tavern. No experience, no gold, no
material, no item. A test asserts each of those individually, so a later
"balance pass" cannot quietly introduce a penalty.

### The crash sensor switched itself off within the hour

Found by looking at a save rather than by a test, and it would have shipped.

`coredumpctl list` exits **1** and prints `No coredumps found.` on **stderr**
when there is nothing to report — which is the ordinary case every fifteen
minutes on a machine that is behaving. The poll collected stdout only, saw an
empty string and a non-zero exit, concluded the binary was missing, and set
`sensors.coredumpAvailable = false`. Permanently: `Migrations` preserves a
`false`, so crash bosses were off for good after the first quiet quarter of an
hour, on a machine where `coredumpctl` works perfectly.

Availability is now decided once, by `coredumpctl --version`, and nowhere else.
The poll ignores its own exit code entirely: anything that is not a JSON array
means there was nothing to report, which is all the poll needs to know. The
probe runs on every startup rather than trusting the save, so a sensor wrongly
retired by an older version comes back by itself.

The general rule this earns: **a sensor may not retire itself on the strength
of an exit code.** Absence of data and absence of a tool look identical from
there, and only one of them is permanent.

## Phase 5

### An expedition stores an end time and a seed, and nothing else

The result is computed from the seed whenever somebody gets round to
collecting it, which is what makes "close the laptop mid-journey and open it a
week later" work without any of the usual catch-up machinery. A test asserts
that resolving on time and resolving a week late produce byte-identical
results, and another that resolving twice pays once.

Resolution is checked on the minute tick **and** on load, before the day rolls
over, so a journey that ended yesterday still pays into yesterday's counters.

### Forging never wears what it made

A new item goes to the chest, not onto the hero. Equipping is a separate click,
and it swaps rather than destroys — whatever was in the slot goes back to the
chest. Trying a different sword costs nothing, which is the only way a forge
with nine recipes and no way to sell is worth opening twice.

### Every shell restart was paying for the workspace you were sitting on

The day's set of already-counted workspaces lived in memory in the service, and
`primeSensors` re-seeded the current workspace on every startup. So each
restart paid the experience again. Fifteen restarts while building Phase 4 put
this machine's counter on ten workspaces for the day and bought the Explorer
feat outright.

The set now lives in the save, as `day.workspaceIds` — integers only, bounded
at 32 — and World decides whether a workspace is new rather than the service.
"Already seen today" is a rule about the day, and the day is the thing that
gets written down. Three tests cover it: ten restarts on the same workspace
count once, a different workspace still counts, and a new day forgets.

Applications were never affected — `app_discovered` only fires on an
`openwindow` event, so a restart alone cannot raise one — and their classes
still never reach disk.

### Seeding a save by hand needs the shell dead first

The running shell owns the game and flushes on exit, so editing `save.json` and
then running `omarchy-restart-shell` loses the edit: the outgoing shell
persists what it had in memory over the top. That is correct behaviour and
cost three confusing test runs. To seed a save, `pkill -9` the shell first,
then edit, then restart.

## Phase 6

### "What this plugin reads" is in the panel, not only in the README

A plugin that runs unsandboxed inside someone's shell owes them that answer
where they are, in their own language, not in a file on a website they have to
go and find. The Settings tab carries the same list the README carries, and the
two have to be changed together.

### The Bard is the only path to a language model, and it is a button

Off by default. Hidden entirely — not disabled, hidden — when `omarchy` is not
installed, because a switch that cannot do anything is worse than no switch.
The click runs `["omarchy", "agent", "prompt", <text>]` as an argument vector
where the text is the plugin's own sentence with paths and a language code
filled in; no value from anywhere else reaches it. The plugin does not read the
answer back from the agent — it watches one file for it, and renders it as
plain text, because what a language model wrote into a file is a sentence and
not markup.

At most once a day, and nothing runs without the click. No token is ever spent
by the plugin deciding to spend one.

### Both arcane sensors read one number and spawn one process at a time

The agent sensor reads `todayTotalTokens` where an agent writes it and sums the
numeric fields under `modelUsage` where it does not; anything else contributes
zero rather than raising. Every file goes through `head -c 65536`, at most
sixteen of them, one at a time. The text fields those files carry — help
strings, status lines, an auth hint — are never read.

The git sensor runs `find` once and then `git rev-list --count` per repository
**sequentially**, at most thirty of them, because thirty repositories found in
`~/Work` would otherwise be thirty processes at once. A count above a hundred
in one window is clamped, and the whole poll can award at most twenty ticks, so
a repository with a scripted history cannot turn into an experience fountain.

### Rebirth keeps what cannot be earned again

Level, experience and equipment go. The chronicle, the materials, the gold and
the feats stay, because those are the record of having been here and nothing in
this game should be able to take that back. It is also the only action in the
plugin that asks before doing it, because it is the only one that clicking
again does not undo.

## After the first release

### Low health is a posture, not a strobe

`hurt` used to be the animation for *being* below 30% health, and it blinked at
120 ms for as long as that lasted — which on a bar widget means blinking at
somebody for half an hour while they work. Split in two:

- **`hurt`** is a flinch. It fires on the blow that lands, runs for 500 ms
  through the service's transient animation timer, and stops.
- **`wounded`** is the standing state. It does not blink at all: the body sits
  one pixel lower and breathes at 1500 ms instead of 900. At sixteen pixels
  across that reads as slumped, and it costs nothing to look at.

The general rule: a persistent state may change how a sprite *rests*, never
whether it is *visible*. Anything that blinks has to have an end.

### The archer has two lenses, not one

Adding a sixth class to five domains meant either doubling up a lens or
inventing a domain. Neither is right for a ranger, so the archer looks through
**two** domains at ×1.25 rather than one at ×1.5: it covers ground and fights
at the end of it, and is worse at both than the specialist would be. `CLASSES`
now carries a `lens` map rather than a single `domain`, which is what made that
expressible at all.

Volley fires twice, so the enemy's armour is paid for twice: strong against a
slime, poor against a golem. That is a bow.

### Nobody could find the stroll

Three separate reasons, all mine:

1. The button greys out while an expedition is away, and the reason was only in
   a tooltip. A greyed button with a hidden reason looks broken. The reason is
   now written next to it.
2. It drew on the **largest** output, not the focused one. On a two-monitor
   desk that is a coin flip, and losing it means the hero walks across the
   screen nobody is looking at. It now follows `Hyprland.focusedMonitor`.
3. At 48 pixels along the very bottom edge of a 1920-wide screen, over forty
   seconds, it is genuinely easy to miss. Now 64 pixels and 26 seconds.

It was working the whole time. `omarchy-shell f360c4.omaquest stroll` exists
now so it can go on a keybind — and so it can be tested without a click.

### A merchant, because gold had nowhere to go

Gold accumulated with one thing to spend it on (changing calling, once), while
the chest filled with whatever a better sword replaced. Three offers a day,
drawn from the date, and he will buy the old gear.

The point is not an economy: it is that being one iron short of a recipe should
be solvable by having fought, rather than by waiting for the right drop.

A test asserts that **selling an item back is worth less than its materials
cost**, so forge → sell → buy → forge loses money. It caught a real one on the
first run: the Core Sword sold for 114 against 112 of materials, which is a
loop that prints gold. Selling now pays 30 a tier instead of 38.

### `check-sprites` now checks the names the code asks for

It used to compare `index.json` against the directory, and the two agreed
perfectly about a sprite that had never been drawn. `boss_daemon_idle_a` and
`slime_idle_a` were both missing, so every crash boss and every slime rendered
as **empty space** — through four phases, with every check passing.

It now walks the race, class, effect and bestiary lists the code actually uses
and asserts each file exists. It found the second one by itself.

### The panel survives a plugin hot-reload too

`keepLoaded: true` keeps the service across a rescan, which was already
written down. It keeps the **panel** as well: editing a view and re-opening the
panel shows the old component. A `qmllint`-clean edit that appears to do
nothing is usually this. `omarchy-restart-shell`, not `rescanPlugins`.

### Walking is free; finding something is not

The stroll was capped at three a day with an hour and a half between them, and
the button greyed out in between. That is the wrong thing to ration: a walk is
something you watch because you felt like watching it, and a button that says
"not now" to that is a button that annoys.

Split in two. `canStroll` now only refuses the three states where the hero is
genuinely somewhere else — mid-fight, away on an expedition, face down in the
tavern — and says yes to everything else, as often as asked. `strollPays`
carries the old limit, so the tenth walk of the morning still happens and
simply comes back empty. An empty walk writes no chronicle line either: "went
out, came back" is not news.

The panel says which it will be, next to the button, rather than hiding it in a
tooltip.

### A flourish partway along, and why it looks like six things

A hero who only walks is a hero who is walking. Between 42% and 58% of the way
across, the sprite switches to `flourish`: fast frames, sparks, and the class
overlay pushed out in front. The overlay is what makes it read as six different
things — a sword thrust, a staff raised, a bow drawn, a lute struck — without a
single extra grid.

### `WlrLayer.Top`, not `Overlay`

Overlay draws above everything, including a fullscreen window, which is exactly
the moment nobody wants a small figure wandering across their video. Top keeps
the hero above ordinary windows and out of the way of anything fullscreen. It
is the layer Omagotchi's pet uses, for the same reason.

Worth saying plainly since it came up: **the hero does not climb anything.** It
walks the ground in a straight line and leaves. Climbing the edges of windows
is Omagotchi's behaviour — `RoamWindow.qml` has a `climb` action and a
`climbSpeed` — and it is not something this plugin does or should.

### Is it light? Measured, and the answer is "below the noise"

Asked directly, and worth writing down properly because two earlier attempts
produced numbers that were entirely instrument.

Three paired four-minute windows, plugin enabled against plugin disabled, on a
two-monitor desk carrying a dozen bar plugins:

| | with | without |
|---|---|---|
| round 1 | 8.45% | 9.16% |
| round 2 | 19.45% | 9.93% |
| round 3 | 5.42% | 10.04% |

And memory: 509 MB with, 517 MB without.

The shell swings by more between one window and the next than the plugin could
add. One pair came back **lower** with it enabled than without. The memory
delta is **negative**. Both instruments agree, and what they agree on is that
Omaquest cannot be resolved against the shell it runs inside.

So the honest claim is not a percentage, it is: **too small to measure against
a shell that uses half a gigabyte and a tenth of a core on its own.** What can
be stated exactly is the work — every timer, how often, and what it does — and
`tools/weight.sh` prints that from the source and fails if a new timer ever
runs faster than the budget allows.

A real percentage would need a bar carrying nothing else. That is worth doing
once, on a spare user account, before anyone claims a number in a README.

### Your primary attribute is your power, for every class

The old rule was the specification's: `damage = 3 + Strength`. Two separate
problems came out of it, and the second is the one that actually mattered.

The first was mechanical, and was patched early by adding a per-level term —
without it, five of the six classes dealt the same damage at level 30 as at
level 1, because they never raise Strength.

The second was that **nobody could explain it**. Asked directly: "Strength is
attack, but what about the mage — does it go up with intelligence?" There was
an answer, but it took a paragraph: the mage's basic attack does scale with
Strength, badly, and its real damage comes from Fireball, which scales with
Wisdom because Wisdom is the mage's primary. A rule that takes a paragraph is
not a rule, it is a defect with documentation.

So: **the class's own primary drives the attack and the skill**, for all six.
A warrior hits with Strength, a mage with Wisdom, a bard with Charisma. The
others each do exactly one thing, the same thing for everyone — Vigour is
health, Agility is dodging and criticals, Charisma is gold and rare finds.

And **defence is deliberately not an attribute**. It comes from armour and
nothing else, so it is shown under what you are wearing rather than in the
list of five. A test asserts that no attribute moves it.

What this cost: a recalibration (`node tools/balance.js --tune`), which came
back with constants within 2% of the old ones. The model got simpler and the
balance did not move.

### The sheet now says what each attribute is doing

Five numbers with no explanation is the shape of the question that started
this. Each attribute now carries a line derived from the rules themselves —
`Rules.attrReadout` — so the sheet cannot drift from what it is describing:

> Strength 14 · your attack · 27
> Wisdom 5 · nothing, for your calling

"Nothing, for your calling" is the honest answer for a warrior's Wisdom, and
writing it down is better than leaving somebody to work it out by levelling.

Gear bonuses are printed apart from levelled values — `14 +2` rather than a
16 nobody can account for.

### Gear has its own tab, and every option shows its delta

It used to be a list at the bottom of the Forge, nine recipes below the
materials, with no indication that scrolling was where equipping lived. Now it
is its own tab holding the attributes, what they add up to, and the three
slots — because "what does this change" is one question and those are its
three halves.

Each option shows the **difference** against what is worn right now, computed
by building the hero both ways and subtracting, so it cannot disagree with
what the click actually does. "+2 attack, -1 defence" is the decision; "+4
damage" is a fact you then have to do arithmetic on.

Taking something off is possible, which it was not: a slot you can fill but
not empty is a one-way door.

### Closing the panel forgets which tab was open

It used to come back wherever you left it, which sounds like continuity and is
not: opening the panel three hours later and landing on the Forge because that
is where you happened to be is the panel remembering something nobody asked it
to. It resets to the Hero sheet, which is what somebody opening this wants to
see. A fight in progress is the one exception, and `open` puts that back.

### Attributes describe the hero; gear is what the hero is carrying

The first attempt put the attributes in the Gear tab, on the theory that
"what does this change" wants the attribute and the item on one screen. That
was the wrong cut. The attributes describe **who the hero is** and belong on
the sheet about the hero; the Gear tab is the **inventory** — what you own and
what you can do with it.

What made the original problem go away was not putting them together, it was
each option showing its own delta. That stays.

### "nothing, for your calling" meant nothing to anybody

It was true and it was unreadable. Now the line names the class:

> Wisdom 5 · no effect for a Warrior

Concrete beats elegant. The same rewrite made the list of options include
**what is already worn**, marked `(equipped)` — a list of alternatives that
leaves out the thing you are comparing against is a list you cannot compare
against.

### Potions, because a decision mid-fight is a different decision

Gear is chosen once and then carried. A potion is chosen while something is
going wrong, which is a different kind of choice and the reason to have both.

Two, and only two. A **Healing Draught** returns half your health and gets you
off the tavern floor — what it really buys is the thirty minutes you would
otherwise wait. A **Traveller's Flask** returns one point of energy, which is
the thing that actually limits how much of the game a day holds, so it is
priced to be a decision rather than a habit.

Held as counts and capped at five: a stack of fifty is not a decision, it is a
buffer. Drinking at full health keeps the potion rather than wasting it, and
drinking mid-fight moves the health **the fight is reading** as well as the
hero's — the arena keeps its own copy, and without telling it the next
exchange would overwrite what was just drunk. There is a test for exactly that.

The merchant always carries both, unlike the three materials that rotate:
running out of draughts on the day you need one is not an interesting problem.
