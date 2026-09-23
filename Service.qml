pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.Commons
import "components"
import "game/Rules.js" as Rules
import "game/World.js" as World
import "game/Migrations.js" as Migrations

// The world. One headless instance per session, created by the shell's plugin
// host with `createObject(null)`; `shell` and `manifest` are injected when the
// properties exist.
//
// The bar exists once per monitor, so the widget cannot be the thing that owns
// the hero — that would give you one save file per screen, racing each other.
// This service is mounted once, owns the state and is the only writer; panels
// read from it and dispatch events back.
//
// Everything that changes state goes through `dispatch`, which hands the event
// to World.apply and then runs whatever effects come back. Nothing else
// writes to `world`.
Item {
  id: root

  // Injected by the host when it mounts the plugin.
  property var shell: null
  property var manifest: null

  // Injected by the bar widget whenever its inline shell.json entry changes,
  // so the service answers to the same settings the panel shows.
  property var settings: ({})

  property bool initialized: false
  property bool loading: true

  // OMAQUEST_DEBUG=1 logs every Hyprland event the plugin sees, which is the
  // only way to find out what a compositor actually raises and with what
  // payload. Off unless asked for; nothing is logged in normal use.
  readonly property bool debugSensors: Quickshell.env("OMAQUEST_DEBUG") === "1"

  readonly property string version: manifest && manifest.version ? String(manifest.version) : "0.1.0"

  // The save, whole. Reassigned rather than mutated after every apply, so a
  // view binding on `game.world` re-reads without a signal per field.
  //
  // Named `world`, not `state`: every QML Item already has a `state`, and
  // shadowing it silently breaks the property it belongs to.
  property var world: null

  readonly property bool hasHero: !!world && !!world.hero

  // Bumped on every change. Views that read into `world` deeply bind to this
  // instead of trying to bind through a plain JS object.
  property int revision: 0

  signal changed()

  // ---- Where the game lives on disk. Nothing outside this directory is ever
  //      written, and the only thing read from it is the save.
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || ((Quickshell.env("HOME") || "") + "/.local/state")
  readonly property string stateDir: stateHome + "/omaquest"
  readonly property string savePath: stateDir + "/save.json"

  // A save is a few kilobytes by design; the tests hold a maximal one under
  // 64 KiB. Reading through `head -c` means a file that has become enormous by
  // any route costs a bounded read instead of the shell's memory.
  readonly property int maxStateBytes: 262144

  // The realm is the machine, and this is the only thing that decides which
  // kind: no battery is a fortress, and a fortress carries one more energy.
  readonly property bool hasBattery: UPower.displayDevice ? UPower.displayDevice.isPresent === true : false
  readonly property string realmType: hasBattery ? "caravan" : "fortress"

  // One bank for the whole plugin: nineteen small text reads at startup, then
  // every sprite in every panel and every bar draws from memory.
  property SpriteBank sprites: SpriteBank {}

  property I18n i18n: I18n {
    language: root.settings && root.settings.language ? String(root.settings.language) : "auto"
  }

  function t(key, vars) {
    return i18n.t(key, vars)
  }

  function applySettings(values) {
    root.settings = values || ({})
  }

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // ------------------------------------------------------------- dispatch

  function dispatch(event) {
    if (!root.world || !event) return
    var result = World.apply(root.world, event, Rules.nowSec())
    if (!result || result.state === root.world) return

    root.world = result.state
    runEffects(result.effects || [])
    root.revision += 1
    root.changed()
  }

  function runEffects(effects) {
    for (var i = 0; i < effects.length; i++) {
      var effect = effects[i]
      if (effect.type === "save") markDirty()
      else if (effect.type === "chronicle") appendChronicle(effect.entry)
      else if (effect.type === "notify") notify(effect.key, effect.params)
      else if (effect.type === "anim") playAnimation(effect.name, effect.ms)
    }
  }

  // ------------------------------------------------------------ animation

  // What the bar sprite is doing. Phase 2 draws it; until then it is the
  // value the widget's tooltip and the panel read.
  property string transientAnim: ""
  readonly property string heroAnim: {
    if (transientAnim) return transientAnim
    if (!hasHero) return "idle"
    if (strolling) return strollAnim
    if (world.expedition && !world.expedition.resolved) return "walk"
    if (world.arena) return "fight"
    if (idle) return "sleep"
    // Low on health is a posture, not a strobe. The flinch is `hurt`, and it
    // only ever arrives as a transient effect lasting under a second.
    if (Rules.num(world.hero.hp) < Rules.num(world.hero.hpMax) * 0.3) return "wounded"
    return "idle"
  }
  property bool idle: false

  function playAnimation(name, ms) {
    root.transientAnim = name
    animTimer.interval = Math.max(200, Rules.num(ms, 1000))
    animTimer.restart()
  }

  Timer {
    id: animTimer
    repeat: false
    onTriggered: root.transientAnim = ""
  }

  // --------------------------------------------------------- notifications

  // Two a day, ever, across every category — and each category is separately
  // switchable. Anything over budget is dropped in silence rather than queued:
  // a notification that arrives tomorrow about yesterday is worse than none.
  readonly property string notifyBin: (Quickshell.env("OMARCHY_PATH") || "") !== ""
    ? Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-notification-send"
    : "omarchy-notification-send"

  readonly property var notifySettingFor: ({
    "level_up": "notifyLevelUp",
    "boss_spawned": "notifyBoss",
    "expedition_done": "notifyExpedition",
    "quests_done": "notifyQuests"
  })

  function notify(key, params) {
    if (!root.world) return

    var settingKey = notifySettingFor[key]
    var defaultOn = key === "level_up" || key === "boss_spawned"
    if (!settingKey || setting(settingKey, defaultOn) !== true) return

    if (Rules.num(root.world.day.notificationsSent) >= Rules.MAX_NOTIFICATIONS_PER_DAY) return
    root.world.day.notificationsSent = Rules.num(root.world.day.notificationsSent) + 1
    markDirty()

    // argv, never a shell string, and never `notify-send`: the Omarchy
    // notification server drops anything whose app name is notify-send.
    Quickshell.execDetached([
      root.notifyBin,
      "--app-name", "omaquest",
      "-u", "low",
      "-g", String.fromCodePoint(0xF04E5),
      root.t("notify." + key + ".title", params),
      root.t("notify." + key + ".body", params)
    ])
  }

  // ------------------------------------------------------------- chronicle

  // Kept beside the save rather than in it, so a long history never slows a
  // save down, and pruned on every append so it cannot grow without bound.
  property var chronicle: []
  readonly property string chroniclePath: stateDir + "/chronicle.json"

  function appendChronicle(entry) {
    if (!entry) return
    var list = root.chronicle.slice()
    entry.ts = Rules.nowSec()
    list.push(entry)
    if (list.length > Rules.MAX_CHRONICLE_ENTRIES)
      list = list.slice(list.length - Rules.MAX_CHRONICLE_ENTRIES)
    root.chronicle = list
    chronicleDirty = true
    markDirty()
  }

  // ------------------------------------------------------------- persistence

  property bool dirty: false
  property bool chronicleDirty: false

  function markDirty() {
    if (root.loading) return
    root.dirty = true
    saveDebounce.restart()
  }

  // At most one write every five seconds, however many events land in between.
  Timer {
    id: saveDebounce
    interval: 5000
    repeat: false
    onTriggered: root.persist()
  }

  function persist() {
    if (!root.world || root.loading) return
    saveFile.setText(JSON.stringify(root.world, null, 2) + "\n")
    if (root.chronicleDirty) {
      chronicleFile.setText(JSON.stringify({ version: Rules.SCHEMA_VERSION, entries: root.chronicle }) + "\n")
      root.chronicleDirty = false
    }
    root.dirty = false
  }

  FileView {
    id: saveFile
    path: root.savePath
    preload: false
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: chronicleFile
    path: root.chroniclePath
    preload: false
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  // ---- Loading. Three steps, each one a process with a literal argv:
  //      make the directory, read the save, read the chronicle.
  Process {
    id: ensureDir
    command: ["mkdir", "-p", root.stateDir]
    running: true
    onExited: saveReader.running = true
  }

  Process {
    id: saveReader
    command: ["head", "-c", String(root.maxStateBytes), root.savePath]
    stdout: StdioCollector { id: saveOut }
    onExited: function (exitCode) {
      // A missing file is exit 1 with empty output, which is a new game, not
      // an error. A file that filled the read budget is one we refuse to
      // parse rather than one we truncate into nonsense.
      var text = exitCode === 0 ? saveOut.text : ""
      root.loadSave(text.length >= root.maxStateBytes ? null : text)
    }
  }

  Process {
    id: chronicleReader
    command: ["head", "-c", String(root.maxStateBytes), root.chroniclePath]
    stdout: StdioCollector { id: chronicleOut }
    onExited: function (exitCode) {
      root.loadChronicle(exitCode === 0 ? chronicleOut.text : "")
    }
  }

  // A save that cannot be read is never deleted — it is moved aside, so a bug
  // here costs a player a session rather than a hero.
  Process {
    id: quarantine
    property string source: ""
    property string target: ""
    command: ["mv", source, target]
  }

  function loadSave(text) {
    var parsed = null
    var broken = false

    if (text === null) {
      broken = true
    } else if (text && text.trim().length > 0) {
      try {
        parsed = JSON.parse(text)
      } catch (error) {
        broken = true
      }
      if (!broken) {
        // Noted before Migrations drops it, because dropping it is what owes
        // the player their energy back.
        root.arenaWasInterrupted = !!parsed.arena
        parsed = Migrations.run(parsed)
        if (!parsed) broken = true
      }
    }

    if (broken) {
      quarantine.source = root.savePath
      quarantine.target = root.stateDir + "/save.corrupt-" + Rules.nowSec() + ".json"
      quarantine.running = true
      parsed = null
    }

    root.world = parsed || Rules.newSave(Rules.nowSec())
    root.brokenSaveRecovered = broken
    chronicleReader.running = true
  }

  property bool brokenSaveRecovered: false
  property bool arenaWasInterrupted: false

  function loadChronicle(text) {
    var entries = []
    if (text && text.trim().length > 0) {
      try {
        var parsed = JSON.parse(text)
        if (parsed && Array.isArray(parsed.entries)) entries = parsed.entries
      } catch (error) {
        entries = []
      }
    }
    if (entries.length > Rules.MAX_CHRONICLE_ENTRIES)
      entries = entries.slice(entries.length - Rules.MAX_CHRONICLE_ENTRIES)
    root.chronicle = entries

    root.loading = false
    root.initialized = true

    if (root.brokenSaveRecovered) {
      appendChronicle({ type: "records_lost", p: {}, seed: Rules.nowSec() })
      root.brokenSaveRecovered = false
    }

    // A fight cannot survive the shell going away: there is no way to tell
    // whether the player walked out or the machine did, so the energy goes
    // back and the fight is dropped. Migrations already clears `arena` on
    // load; this returns what it cost.
    if (root.arenaWasInterrupted) {
      dispatch({ type: "cancel_fight", interrupted: true })
      root.arenaWasInterrupted = false
    }

    catchUp()
    primeSensors()
    uidProc.running = true
    coredumpProbe.running = true
    bardProbe.running = true
    root.revision += 1
    root.changed()
  }

  // The workspace the player is already on when the shell starts counts as
  // visited: they are looking at it. Without this, a session where nobody
  // switches workspace scores nothing for the one they spent the day in.
  function primeSensors() {
    if (!root.hasHero || root.focusedWorkspace <= 0) return
    if (root.pendingWorkspaces.indexOf(String(root.focusedWorkspace)) !== -1) return
    root.pendingWorkspaces.push(String(root.focusedWorkspace))
    hyprDebounce.restart()
  }


  // ================================================================ sensors
  //
  // Everything below reads a count or a state and nothing else. No window
  // title, no application name past the moment it is counted, no media
  // metadata, no file content. What reaches the save is numbers.
  //
  // Every accumulator here is bounded. A burst of window events, a runaway
  // process opening surfaces in a loop, a theme script flapping — none of them
  // can make this grow without limit, because the alternative is a plugin that
  // eats the shell's memory on someone else's bad day.

  // ---------------------------------------------------------------- Hyprland

  // Raw events arrive in bursts — opening a terminal raises several — so they
  // are folded into counters immediately and turned into game events once, a
  // second later. Folding rather than queueing is what makes the burst free:
  // there is no list to grow.
  property int pendingWindows: 0
  property int pendingTerminals: 0
  property var pendingWorkspaces: []
  property var pendingApps: []

  // Which applications have been seen today, kept in memory only and never
  // written: the save holds how many distinct applications were opened, not
  // which ones. Workspaces are the opposite case — they are numbers, and
  // `World` keeps them in the day precisely so that a shell restart cannot pay
  // for the same one twice.
  property var seenApps: ({})

  // Far above the daily caps of ten workspaces and fifteen applications, and
  // still a hard ceiling.
  readonly property int maxSeenPerDay: 256

  function noteSeen(set, key) {
    if (!key) return false
    if (set[key]) return false
    var count = 0
    for (var existing in set) { count += 1; if (count >= root.maxSeenPerDay) return false }
    set[key] = true
    return true
  }

  // `openwindow` carries ADDRESS,WORKSPACE,CLASS,TITLE. The title can contain
  // commas, so nothing past the class is trusted — and the class itself is
  // used to decide two things and then dropped.
  function classFromOpenWindow(data) {
    var parts = String(data || "").split(",")
    return parts.length >= 3 ? String(parts[2]).toLowerCase() : ""
  }

  function isTerminal(appClass) {
    return Rules.TERMINAL_CLASSES.indexOf(appClass) !== -1
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      root.rawEventsSeen += 1
      if (!root.initialized || !root.hasHero || !event || !event.name) return
      if (String(event.name) !== "openwindow") return

      // ADDRESS,WORKSPACE,CLASS,TITLE. Only the class is read, only to decide
      // whether this is a new application today and whether it is a terminal,
      // and it is dropped the moment those two questions are answered. The
      // title is never touched: it is the one field that carries what someone
      // is actually doing.
      var appClass = root.classFromOpenWindow(event.data)
      root.pendingWindows += 1
      if (appClass && root.pendingApps.indexOf(appClass) === -1 && root.pendingApps.length < 32)
        root.pendingApps.push(appClass)
      if (root.isTerminal(appClass)) root.pendingTerminals += 1
      hyprDebounce.restart()

      if (root.debugSensors) console.log("omaquest openwindow, terminal:", root.isTerminal(appClass))
    }
  }

  // Workspaces are read off the model rather than off the event stream.
  // Quickshell keeps `focusedWorkspace` current, and a property that already
  // tracks the answer beats matching an event name that differs between
  // Hyprland versions — `workspace` and `workspacev2` carry different payloads
  // and neither is what the shell's own widgets rely on.
  readonly property int focusedWorkspace: Hyprland.focusedWorkspace
    ? Rules.num(Hyprland.focusedWorkspace.id) : 0

  onFocusedWorkspaceChanged: {
    if (!root.initialized || !root.hasHero || root.focusedWorkspace <= 0) return
    var id = String(root.focusedWorkspace)
    if (root.pendingWorkspaces.indexOf(id) === -1 && root.pendingWorkspaces.length < 32)
      root.pendingWorkspaces.push(id)
    hyprDebounce.restart()
  }

  // One second, restarted by every event, so a burst is processed once.
  Timer {
    id: hyprDebounce
    interval: 1000
    repeat: false
    onTriggered: root.flushHyprland()
  }

  function flushHyprland() {
    if (!root.hasHero) return

    var workspaces = root.pendingWorkspaces
    var apps = root.pendingApps
    var windows = root.pendingWindows
    var terminals = root.pendingTerminals

    root.pendingWorkspaces = []
    root.pendingApps = []
    root.pendingWindows = 0
    root.pendingTerminals = 0

    // Dispatched unconditionally; World drops the ones the day has already
    // paid for.
    for (var w = 0; w < workspaces.length; w++)
      dispatch({ type: "workspace_discovered", workspace: parseInt(workspaces[w], 10) || 0 })

    for (var a = 0; a < apps.length; a++)
      if (root.noteSeen(root.seenApps, apps[a]))
        dispatch({ type: "app_discovered" })

    for (var t = 0; t < terminals; t++) dispatch({ type: "terminal_opened" })

    // One award per five windows, with the remainder carried rather than lost.
    root.windowRemainder += windows
    while (root.windowRemainder >= Rules.WINDOWS_PER_AWARD) {
      root.windowRemainder -= Rules.WINDOWS_PER_AWARD
      dispatch({ type: "windows_opened" })
    }
  }

  property int windowRemainder: 0

  // How many compositor events this session has seen at all. A count, never a
  // name — and the one number that tells a bug report whether the sensor is
  // wired up or the compositor is simply quiet.
  property int rawEventsSeen: 0

  // ------------------------------------------------------------------- rest

  // Two monitors, because they answer different questions. The short one only
  // decides whether the sprite should be asleep; the long one is what the game
  // calls a rest.
  IdleMonitor {
    enabled: true
    timeout: 60
    respectInhibitors: true
    onIsIdleChanged: root.idle = isIdle
  }

  property double idleSince: 0

  IdleMonitor {
    enabled: true
    timeout: Rules.REST_SECONDS
    respectInhibitors: true
    onIsIdleChanged: {
      if (isIdle) {
        root.idleSince = Rules.nowSec()
        return
      }
      if (root.idleSince <= 0) return
      var seconds = Rules.nowSec() - root.idleSince
      root.idleSince = 0
      if (root.hasHero && seconds >= Rules.REST_SECONDS)
        dispatch({ type: "rested", seconds: seconds })
    }
  }

  // ------------------------------------------------------------------ theme

  // A theme change repaints a dozen colours in a burst, and the point is the
  // change, not the colours — so it is debounced into one event and the
  // starting values are ignored.
  Connections {
    target: Color
    function onForegroundChanged() { root.noteThemeChange() }
    function onBackgroundChanged() { root.noteThemeChange() }
    function onAccentChanged() { root.noteThemeChange() }
  }

  function noteThemeChange() {
    if (!root.initialized || !root.hasHero) return
    themeDebounce.restart()
  }

  Timer {
    id: themeDebounce
    interval: 2000
    repeat: false
    onTriggered: if (root.hasHero) root.dispatch({ type: "theme_changed" })
  }

  // ------------------------------------------------------------------ music

  // Polled rather than watched: `playbackState` is the only thing read, and a
  // minute's resolution is all a ten-minute tick needs. Never the title, never
  // the artist.
  property int musicMinutes: 0

  readonly property bool anythingPlaying: {
    var players = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < players.length; i++)
      if (players[i] && players[i].playbackState === MprisPlaybackState.Playing) return true
    return false
  }

  // ---------------------------------------------------------------- weather

  // Only on a machine that has a battery. A fortress has no weather.
  property bool wasLow: false
  property bool fairToday: false

  readonly property real batteryLevel: hasBattery && UPower.displayDevice
    ? Rules.num(UPower.displayDevice.percentage) : 1
  readonly property bool charging: hasBattery && UPower.displayDevice
    ? UPower.displayDevice.state !== UPowerDeviceState.Discharging : true

  onBatteryLevelChanged: root.readWeather()
  onChargingChanged: root.readWeather()

  function readWeather() {
    if (!root.hasHero || !root.hasBattery) return

    if (!root.charging && root.batteryLevel < 0.20) root.wasLow = true

    // A storm is the whole arc: it ran down and then it was saved.
    if (root.charging && root.wasLow) {
      root.wasLow = false
      dispatch({ type: "storm" })
      return
    }

    if (root.charging && root.batteryLevel >= 0.99 && !root.fairToday) {
      root.fairToday = true
      dispatch({ type: "fair_weather" })
    }
  }


  // --------------------------------------------------------------- crashes

  // A program crashing on this machine becomes a boss. What is read is the
  // journal's own index of core dumps — the time, the owning uid and the path
  // of the executable — and what is kept is the executable's basename. Never
  // the core file, never the command line, never the backtrace.
  //
  // Fifteen minutes apart, and only if `coredumpctl` exists at all: without
  // systemd there are simply no crash bosses, and nothing complains.

  property int currentUid: -1
  readonly property int coredumpBudget: 65536

  Process {
    id: uidProc
    command: ["id", "-u"]
    stdout: StdioCollector { id: uidOut }
    onExited: function (exitCode) {
      root.currentUid = exitCode === 0 ? parseInt(String(uidOut.text).trim(), 10) : -1
      if (root.initialized) coredumpPoll.triggered()
    }
  }

  // Whether the sensor can work at all is decided once, by asking the binary
  // for its version, and never by reading a poll's exit code.
  //
  // That distinction is the whole point: `coredumpctl list` exits **1** with
  // "No coredumps found." on **stderr** when there is simply nothing to
  // report, which is the normal case every fifteen minutes on a machine that
  // is behaving. Retiring the sensor on a non-zero exit therefore switched
  // crash bosses off permanently the first quiet quarter of an hour — and it
  // did, on this machine, before this existed.
  //
  // The probe also runs on every startup rather than trusting the save, so a
  // sensor that was wrongly retired by an older version comes back.
  Process {
    id: coredumpProbe
    command: ["coredumpctl", "--version"]
    onExited: function (exitCode) {
      if (!root.world || !root.world.sensors) return
      var available = exitCode === 0
      if (root.world.sensors.coredumpAvailable !== available) {
        root.world.sensors.coredumpAvailable = available
        markDirty()
      }
      root.revision += 1
    }
  }

  Process {
    id: coredumpProc
    command: ["coredumpctl", "list", "--json=short", "--no-pager", "--since", "@" + String(root.coredumpSince)]
    stdout: StdioCollector { id: coredumpOut; waitForEnd: true }
    onExited: function () { root.readCoredumps(String(coredumpOut.text || "")) }
  }

  property double coredumpSince: 0

  Timer {
    id: coredumpPoll
    interval: 900000       // fifteen minutes
    repeat: true
    running: root.initialized && root.hasHero && root.coredumpAvailable
    triggeredOnStart: true
    onTriggered: {
      if (!root.hasHero || coredumpProc.running || root.currentUid < 0) return
      root.coredumpSince = Math.max(0, Rules.num(root.world.sensors.lastCoredumpCheck, Rules.nowSec()))
      coredumpProc.running = true
    }
  }

  readonly property bool coredumpAvailable: root.world && root.world.sensors
    ? root.world.sensors.coredumpAvailable !== false : true

  property string coredumpDebug: ""

  function readCoredumps(text) {
    if (!root.hasHero) return

    var trimmed = text.trim()
    root.coredumpDebug = "since=" + String(root.coredumpSince) + " uid=" + String(root.currentUid)
      + " bytes=" + String(trimmed.length) + " head=" + trimmed.slice(0, 40)

    // Anything that is not a JSON array means there was nothing to report.
    // The exit code is deliberately ignored here: `coredumpctl list` exits 1
    // with "No coredumps found." on stderr for the ordinary quiet case, and a
    // sensor that retires on that retires within the hour. Availability is
    // decided by the probe above, once, and nowhere else.
    if (trimmed.indexOf("[") !== 0) {
      root.world.sensors.lastCoredumpCheck = Rules.nowSec()
      markDirty()
      return
    }

    if (trimmed.length > root.coredumpBudget) trimmed = ""

    var records = []
    try {
      var parsed = JSON.parse(trimmed)
      if (Array.isArray(parsed)) records = parsed
    } catch (error) {
      records = []
    }

    var entries = []
    var since = root.coredumpSince
    for (var i = 0; i < records.length && entries.length < 32; i++) {
      var record = records[i]
      if (!record) continue
      // Somebody else's crash is not this hero's problem.
      if (Rules.num(record.uid, -1) !== root.currentUid) continue

      // The journal reports microseconds since the epoch.
      var at = Math.floor(Rules.num(record.time) / 1000000)
      if (at <= since) continue

      var exe = String(record.exe || "")
      var comm = exe.slice(exe.lastIndexOf("/") + 1)
      if (!comm) continue
      entries.push({ comm: comm, at: at })
    }

    root.coredumpDebug += " records=" + String(records.length) + " new=" + String(entries.length)
    root.world.sensors.lastCoredumpCheck = Rules.nowSec()
    markDirty()

    if (entries.length) dispatch({ type: "coredumps", entries: entries })
  }


  // ---------------------------------------------------- arcane sensors (opt-in)
  //
  // Both are off by default and both read counts. They exist because a
  // developer's day has two things in it that the compositor cannot see, and
  // neither is worth turning on without being asked.

  // ---- Agents. The files under agents/usage are what `omarchy agent
  //      usage-update` regenerates; they are mode 0600 and contain text fields
  //      (help strings, status lines) that are never read. What is taken is a
  //      token total, and the difference since last time becomes experience.
  readonly property string agentUsageDir: stateHome + "/omarchy/agents/usage"
  readonly property bool sensorAgents: setting("sensorAgents", false) === true

  Process {
    id: agentsList
    command: ["ls", "-1", root.agentUsageDir]
    stdout: StdioCollector { id: agentsOut; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode !== 0) return
      var names = String(agentsOut.text || "").split("\n")
      var files = []
      for (var i = 0; i < names.length && files.length < 16; i++) {
        var name = names[i].trim()
        if (name.length > 0 && name.lastIndexOf(".json") === name.length - 5) files.push(name)
      }
      root.agentFiles = files
      root.agentTotal = 0
      root.agentPending = files.length
      if (files.length === 0) return
      agentReader.index = 0
      agentReader.start()
    }
  }

  property var agentFiles: []
  property double agentTotal: 0
  property int agentPending: 0

  // One file at a time through one bounded read, rather than sixteen processes
  // at once.
  Process {
    id: agentReader
    property int index: 0
    function start() {
      if (index >= root.agentFiles.length) { root.finishAgents(); return }
      running = true
    }
    command: ["head", "-c", "65536", root.agentUsageDir + "/" + (root.agentFiles[index] || "")]
    stdout: StdioCollector { id: agentFileOut; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) root.agentTotal += root.tokensIn(String(agentFileOut.text || ""))
      agentReader.index += 1
      agentReader.start()
    }
  }

  // Each agent writes its own shape. `todayTotalTokens` when it is there, and
  // otherwise the numbers under `modelUsage`. Anything else contributes zero
  // rather than raising.
  function tokensIn(text) {
    if (!text) return 0
    try {
      var parsed = JSON.parse(text)
      if (!parsed || typeof parsed !== "object") return 0

      var today = Number(parsed.todayTotalTokens)
      if (isFinite(today) && today > 0) return today

      var total = 0
      var usage = parsed.modelUsage
      if (usage && typeof usage === "object") {
        for (var model in usage) {
          var counts = usage[model]
          if (!counts || typeof counts !== "object") continue
          for (var field in counts) {
            var value = Number(counts[field])
            if (isFinite(value) && value > 0) total += value
          }
        }
      }
      return total
    } catch (error) {
      return 0
    }
  }

  function finishAgents() {
    if (!root.hasHero || !root.sensorAgents) return

    var previous = Rules.num(root.world.sensors.lastAgentTokens)
    var now = Math.floor(root.agentTotal)
    root.world.sensors.lastAgentTokens = now
    markDirty()

    // A total that went down means the files were rotated; take the new number
    // as the baseline rather than paying for the whole of it again.
    if (previous <= 0 || now < previous) return

    var ticks = Math.floor((now - previous) / Rules.TOKENS_PER_ARCANE_TICK)
    for (var i = 0; i < Math.min(ticks, 20); i++) dispatch({ type: "arcane_tick" })
  }

  Timer {
    interval: 900000      // fifteen minutes, the rate the files are rewritten at
    repeat: true
    running: root.initialized && root.hasHero && root.sensorAgents
    triggeredOnStart: true
    onTriggered: if (!agentsList.running && !agentReader.running) agentsList.running = true
  }

  // ---- Commits. `git rev-list --count` and nothing else: never a message,
  //      never a file name, never the name of the repository.
  readonly property bool sensorGit: setting("sensorGit", false) === true
  readonly property string workDir: (Quickshell.env("HOME") || "") + "/Work"

  Process {
    id: repoList
    command: ["find", root.workDir, "-maxdepth", "2", "-name", ".git", "-type", "d"]
    stdout: StdioCollector { id: repoOut; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode !== 0) { root.world.sensors.lastGitCheck = Rules.nowSec(); markDirty(); return }
      var lines = String(repoOut.text || "").split("\n")
      var repos = []
      // Thirty repositories is already generous; past that this would be
      // spawning processes for minutes.
      for (var i = 0; i < lines.length && repos.length < 30; i++) {
        var line = lines[i].trim()
        if (line.length > 5) repos.push(line.slice(0, line.length - 5))
      }
      root.repos = repos
      root.commitTotal = 0
      commitCounter.index = 0
      commitCounter.start()
    }
  }

  property var repos: []
  property int commitTotal: 0
  property string gitSince: ""

  Process {
    id: commitCounter
    property int index: 0
    function start() {
      if (index >= root.repos.length) { root.finishCommits(); return }
      running = true
    }
    command: ["git", "-C", root.repos[index] || "", "rev-list", "--count",
              "--since=" + root.gitSince, "HEAD"]
    stdout: StdioCollector { id: commitOut; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        var count = parseInt(String(commitOut.text).trim(), 10)
        if (isFinite(count) && count > 0) root.commitTotal += Math.min(count, 100)
      }
      commitCounter.index += 1
      commitCounter.start()
    }
  }

  function finishCommits() {
    if (!root.hasHero) return
    root.world.sensors.lastGitCheck = Rules.nowSec()
    markDirty()
    for (var i = 0; i < Math.min(root.commitTotal, 20); i++) dispatch({ type: "commit" })
  }

  Timer {
    interval: 1800000     // half an hour
    repeat: true
    running: root.initialized && root.hasHero && root.sensorGit
    triggeredOnStart: true
    onTriggered: {
      if (repoList.running || commitCounter.running) return
      var since = Rules.num(root.world.sensors.lastGitCheck)
      // First run looks back an hour rather than at the whole history.
      root.gitSince = "@" + String(since > 0 ? since : Rules.nowSec() - 3600)
      repoList.running = true
    }
  }

  // ------------------------------------------------------------------- bard
  //
  // The only path to a language model in the whole plugin, and it is a button.
  // Nothing here runs without a click, the click launches the user's own agent
  // with their own quota, and the plugin does not read the answer — it watches
  // one file for it.

  readonly property bool bardEnabled: setting("bardEnabled", false) === true
  readonly property string bardDir: stateDir + "/bard"
  readonly property string bardToday: bardDir + "/" + Rules.localDate(Rules.nowSec()) + ".md"

  property bool bardAvailable: false
  property string bardText: ""
  readonly property bool bardUsedToday: bardText.length > 0

  Process {
    id: bardProbe
    command: ["which", "omarchy"]
    onExited: function (exitCode) { root.bardAvailable = exitCode === 0 }
  }

  // Watched rather than polled, so the card appears the moment the agent saves
  // without the panel being reopened.
  FileView {
    id: bardFile
    path: root.bardToday
    watchChanges: true
    printErrors: false
    onLoaded: root.bardText = String(text() || "").slice(0, 8192)
    onLoadFailed: root.bardText = ""
    onFileChanged: reload()
  }

  function askTheBard() {
    if (!root.bardEnabled || !root.bardAvailable || !root.hasHero || root.bardUsedToday) return

    // argv, and the prompt is the plugin's own sentence with the language and
    // the paths filled in — no value from anywhere else reaches it.
    Quickshell.execDetached(["mkdir", "-p", root.bardDir])
    Quickshell.execDetached(["omarchy", "agent", "prompt", root.t("bard.prompt", {
      save: root.savePath,
      chronicle: root.chroniclePath,
      out: root.bardToday,
      language: i18n.code
    })])
  }

  // ------------------------------------------------------------- the stroll

  // The hero walking across the bottom of the screen, because somebody asked.
  // The walk itself is never written down: if the shell goes away halfway,
  // nothing happened. Only arriving with something is an event.
  property bool strolling: false
  property real strollProgress: 0

  readonly property bool canStroll: hasHero && !strolling
    && World.canStroll(root.world, Rules.nowSec())

  // Whether this one will turn anything up. Walking is free and unlimited;
  // finding something is not, and the panel says so rather than pretending.
  readonly property bool strollPays: hasHero && World.strollPays(root.world, Rules.nowSec())

  // At the far end of the walk, before turning for home, the hero does
  // whatever their calling does — which looks like six different things
  // because the gear overlay is what carries it. The thresholds are the same
  // three legs StrollWindow lays the journey out in.
  readonly property real strollTurnStart: 0.42
  readonly property real strollTurnEnd: 0.58

  readonly property string strollAnim:
    strollProgress > strollTurnStart && strollProgress < strollTurnEnd ? "flourish" : "walk"

  function startStroll() {
    if (!canStroll) return
    root.strollProgress = 0
    root.strolling = true
    strollAnimation.restart()
  }

  NumberAnimation {
    id: strollAnimation
    target: root
    property: "strollProgress"
    from: 0
    to: 1
    duration: Rules.STROLL_SECONDS * 1000
    // Linear: the hero walks at a steady pace and stops for the flourish
    // because the flourish says so, not because an easing curve slowed them
    // down in the middle of a straight line.
    easing.type: Easing.Linear
    onFinished: {
      root.strolling = false
      root.strollProgress = 0
      root.dispatch({ type: "stroll_found" })
    }
  }

  // A monitor being powered off, locked or unplugged destroys the stroll's
  // layer surface while QML still believes the window is visible — the hero
  // keeps walking somewhere that no longer exists, and the animation's
  // finished handler never runs. Dropping visibility for a beat after the
  // output list settles makes Quickshell map a fresh surface.
  //
  // Learned from Omagotchi, which hit it first and left a comment about it.
  property bool screensReady: true

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.screensReady = false
      screensSettle.restart()
    }
  }

  Timer {
    id: screensSettle
    interval: 1000
    repeat: false
    onTriggered: root.screensReady = true
  }

  StrollWindow {
    game: root
    progress: root.strollProgress
    tint: Color.foreground
  }

  // ------------------------------------------------------------ catching up

  // Run once on load and then on every tick: the parts of the world that
  // depend on how much time has passed rather than on anything happening.
  function catchUp() {
    if (!root.world) return
    var now = Rules.nowSec()
    var touched = false

    if (root.world.hero) {
      var regenerated = Rules.regen(root.world.hero, root.world.realm, now)
      if (JSON.stringify(regenerated) !== JSON.stringify(root.world.hero)) {
        root.world.hero = regenerated
        touched = true
      }
    }

    // An expedition that came due while nobody was looking — including while
    // the machine was off. Checked before the day rolls over, so a journey
    // that ended yesterday still pays into yesterday's counters.
    if (root.world.expedition && !root.world.expedition.resolved
        && Rules.num(root.world.expedition.endsAt) <= now) {
      dispatch({ type: "resolve_expedition" })
      touched = false
    }

    var today = Rules.localDate(now)
    if (root.world.day && root.world.day.date !== today) {
      // The day's sets live in memory, not in the save, so the rollover has to
      // clear them here as well as in World.
      root.seenApps = ({})
      root.windowRemainder = 0
      root.musicMinutes = 0
      root.fairToday = false
      dispatch({ type: "day_rollover", date: today })
      // Written at once rather than on the five-second debounce: crossing
      // midnight re-rolls the day's quests, and a machine that shuts down in
      // those five seconds would come back to a day it had already spent.
      persist()
      touched = false     // dispatch already told everyone
    }

    if (touched) {
      root.revision += 1
      root.changed()
      markDirty()
    }
  }

  // One minute, and nothing in the plugin runs faster except the one-second
  // debounce on a burst of window events. Cheap: a clock read, a date
  // comparison, and arithmetic on numbers already in memory.
  Timer {
    id: worldTick
    interval: 60000
    repeat: true
    running: root.initialized
    onTriggered: root.minute()
  }

  function minute() {
    catchUp()
    if (!root.hasHero) return

    // Bosses that have run out of time, and the weekend guardian arriving or
    // leaving. Cheap: a pass over at most three entries.
    dispatch({ type: "check_threats", date: Rules.localDate(Rules.nowSec()) })

    // A minute at the machine. Idle minutes are not session minutes — the game
    // counts being there, not the machine being on.
    if (!root.idle) {
      var before = Rules.num(root.world.day.counters.sessionMin)
      dispatch({ type: "session_tick", minutes: 1 })
      var after = Rules.num(root.world.day.counters.sessionMin)
      if (Math.floor(after / Rules.SESSION_MINUTES_PER_MILESTONE)
          > Math.floor(before / Rules.SESSION_MINUTES_PER_MILESTONE))
        dispatch({ type: "session_milestone" })
    }

    if (root.anythingPlaying) {
      root.musicMinutes += 1
      if (root.musicMinutes >= Rules.MUSIC_MINUTES_PER_TICK) {
        root.musicMinutes = 0
        dispatch({ type: "music_tick" })
      }
    }
  }

  // ---------------------------------------------------------------- queries

  // Everything a panel needs to draw the hero, caught up to this instant
  // rather than to whenever the last event happened.
  function hero() {
    if (!root.world || !root.world.hero) return null
    return Rules.regen(root.world.hero, root.world.realm, Rules.nowSec())
  }

  function xpProgress() {
    var h = root.world && root.world.hero ? root.world.hero : null
    if (!h) return { xp: 0, needed: 1, fraction: 0 }
    var needed = Rules.xpToNext(h.level)
    if (!isFinite(needed)) return { xp: 0, needed: 0, fraction: 1 }
    return { xp: Rules.num(h.xp), needed: needed, fraction: Math.min(1, Rules.num(h.xp) / needed) }
  }

  // What `omarchy-shell f360c4.omaquest status` answers with. Counts and
  // levels only — the same thing the panel shows.
  function publicStatus() {
    var h = hero()
    if (!h) return { ready: root.initialized, hero: null }
    return {
      ready: true,
      hero: {
        name: h.name, race: h.race, cls: h.cls, level: h.level,
        title: h.title, hp: h.hp, hpMax: h.hpMax,
        energy: h.energy, energyMax: h.energyMax, gold: h.gold
      },
      realm: root.world.realm,
      // Counts and states, never a name. Enough for a bug report to say
      // whether a sensor is wired up or the desktop is simply quiet.
      sensors: {
        compositorEvents: root.rawEventsSeen,
        workspace: root.focusedWorkspace,
        idle: root.idle,
        playing: root.anythingPlaying,
        battery: root.hasBattery,
        strolling: root.strolling,
        strollProgress: Math.round(root.strollProgress * 100) / 100,
        canStroll: root.canStroll,
        screensReady: root.screensReady,
        coredump: root.coredumpDebug,
        workspacesToday: Rules.num(root.world.day.counters.workspaces),
        appsToday: Rules.num(root.world.day.counters.apps),
        sessionMinutes: Rules.num(root.world.day.counters.sessionMin)
      },
      bosses: (root.world.bosses || []).length,
      day: root.world.day ? root.world.day.date : "",
      today: Rules.localDate(Rules.nowSec()),
      streak: root.world.streak ? root.world.streak.count : 0,
      expedition: !root.world.expedition ? "none"
        : (root.world.expedition.resolved ? "waiting to be collected" : "on the road")
    }
  }

  // ------------------------------------------------------------------ hero

  function createHero(name, race, cls) {
    dispatch({
      type: "create_hero",
      name: name,
      race: race,
      cls: cls,
      realmName: Quickshell.env("HOSTNAME") || "",
      realmType: root.realmType
    })
    persist()
  }

  Component.onDestruction: {
    // A pending debounce would otherwise lose the last few seconds of play on
    // a shell restart.
    if (root.dirty) persist()
  }
}
