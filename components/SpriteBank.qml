pragma ComponentBehavior: Bound

import QtQml
import QtQuick
import Quickshell.Io

// Loads every sprite grid once and answers `grid(name)` from memory.
//
// Sprites are 16x16 text grids of `X` and `.` under assets/sprites/, listed in
// index.json. Text rather than PNG because this plugin runs unsandboxed inside
// the shell, and a repository whose every asset is reviewable in a diff is
// worth more than the few bytes a binary would save.
//
// One instance, owned by Service.qml and handed to the views — a `pragma
// Singleton` would need a qmldir inside the plugin and would outlive the
// hot-reload that is supposed to pick up an edited sprite.
QtObject {
  id: root

  // Resolved against this file's own URL, so it works from the repository and
  // from the installed plugin directory alike. FileView takes a path, not a
  // URL, hence the prefix strip — the same thing I18n.qml does.
  function assetPath(name) {
    return Qt.resolvedUrl("../assets/sprites/" + name + ".txt").toString().replace(/^file:\/\//, "")
  }

  readonly property string indexPath: Qt.resolvedUrl("../assets/sprites/index.json").toString().replace(/^file:\/\//, "")

  property var names: []
  property var cache: ({})

  // Bumped when a grid arrives, so a Canvas bound to it repaints as the bank
  // fills in rather than staying blank until something else changes.
  property int revision: 0

  readonly property bool ready: names.length > 0 && revision > 0

  // A grid is 16 lines of 16 characters. Anything else is dropped rather than
  // drawn: a half-written file during a hot-reload should render nothing, not
  // a corrupted hero.
  readonly property int size: 16

  // A grid is stored as horizontal runs of lit cells, not as a bitmap, because
  // that is what gets drawn: one rectangle per run instead of one per cell
  // turns a 16x16 body from up to 256 items into about 25.
  function runsFor(rows) {
    var runs = []
    for (var y = 0; y < rows.length; y++) {
      var row = rows[y]
      var x = 0
      while (x < row.length) {
        if (row.charAt(x) !== "X") { x += 1; continue }
        var start = x
        while (x < row.length && row.charAt(x) === "X") x += 1
        runs.push({ x: start, y: y, w: x - start })
      }
    }
    return runs
  }

  function parseGrid(text) {
    if (!text) return null
    var lines = String(text).split("\n")
    var rows = []
    for (var i = 0; i < lines.length && rows.length < root.size; i++) {
      var line = lines[i]
      if (line.length === 0) continue
      if (line.length !== root.size) return null
      if (!/^[X.]+$/.test(line)) return null
      rows.push(line)
    }
    return rows.length === root.size ? rows : null
  }

  function grid(name) {
    if (!name) return null
    var found = root.cache[name]
    return found === undefined ? null : found
  }

  function has(name) {
    return !!grid(name)
  }

  // ---- Name resolution, with the fallbacks the sprite sheet is designed
  //      around: only `idle_a` and `idle_b` exist per body, and every other
  //      animation is built from them. A missing `b` frame falls back to `a`,
  //      and a missing animation falls back to idle, so adding a new
  //      animation later is a matter of adding files.
  function resolve(set, anim, frame) {
    if (!set) return null
    var candidates = [
      set + "_" + anim + "_" + frame,
      set + "_" + anim + "_a",
      set + "_idle_" + frame,
      set + "_idle_a",
      set + "_a"
    ]
    for (var i = 0; i < candidates.length; i++)
      if (root.has(candidates[i])) return root.grid(candidates[i])
    return null
  }

  function store(name, rows) {
    if (!rows) return
    var next = ({})
    for (var key in root.cache) next[key] = root.cache[key]
    next[name] = { rows: rows, runs: runsFor(rows) }
    root.cache = next
    root.revision += 1
  }

  // The runs of a resolved grid, or an empty list — which is what a Repeater
  // wants, rather than null.
  function runs(set, anim, frame) {
    var found = resolve(set, anim, frame)
    return found ? found.runs : []
  }

  property FileView indexFile: FileView {
    path: root.indexPath
    watchChanges: false
    printErrors: true
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.names = Array.isArray(parsed) ? parsed : []
      } catch (error) {
        console.warn("Omaquest SpriteBank: cannot parse index.json:", error)
        root.names = []
      }
    }
    onLoadFailed: root.names = []
  }

  // One FileView per grid, created once the index names them. Nineteen small
  // reads at startup and then nothing: `watchChanges` is off, because a sprite
  // edit already reloads the whole plugin.
  property Instantiator loader: Instantiator {
    model: root.names

    delegate: FileView {
      required property string modelData
      path: root.assetPath(modelData)
      watchChanges: false
      printErrors: false
      onLoaded: root.store(modelData, root.parseGrid(text()))
    }
  }
}
