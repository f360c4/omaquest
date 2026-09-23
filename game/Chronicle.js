.pragma library
.import "Rules.js" as Rules

// Turning a chronicle entry into a sentence.
//
// An entry stores a type, a seed and a handful of ids and numbers — never a
// sentence. The text is built at render time from the dictionary, which is why
// the chronicle rewrites itself in Portuguese when the panel language changes
// and why the save stays small. The seed picks which of a type's variants is
// used, so the same line reads the same on every opening without storing
// which one it was.

"use strict"

// How many `chron.<type>.<n>` variants a dictionary offers, found by probing.
// `t` returns the key itself for a miss, which is the signal this relies on.
var MAX_VARIANTS = 6

function variantCount(t, type) {
  for (var i = 0; i < MAX_VARIANTS; i++) {
    var key = "chron." + type + "." + i
    if (t(key) === key) return i
  }
  return MAX_VARIANTS
}

// Params that every line may use, whether or not its own entry carried them.
function baseParams(state) {
  return {
    name: state && state.hero ? state.hero.name : "",
    realm: state && state.realm ? state.realm.name : ""
  }
}

// Ids inside `p` are dictionary keys, not text. Expanding them here is what
// keeps "dwarf" out of a Portuguese sentence.
function expand(t, params) {
  var out = {}
  for (var key in params) out[key] = params[key]

  if (out.race !== undefined) out.race = t("race." + out.race + ".name")
  if (out.cls !== undefined) out.cls = t("class." + out.cls + ".name")
  if (out.title !== undefined) out.title = t("title." + out.title)
  if (out.quest !== undefined) out.quest = t("quest." + out.quest + ".name")
  if (out.achievement !== undefined) out.achievement = t("achievement." + out.achievement + ".name")
  if (out.item !== undefined) out.item = t("item." + out.item + ".name")
  if (out.material !== undefined) out.material = t("material." + out.material)
  if (out.place !== undefined) out.place = t("dest." + out.place)
  if (out.enemy !== undefined) out.enemy = t("enemy." + out.enemy + ".name")

  // A boss is its executable's basename plus an epithet drawn by seed. The
  // basename is the one piece of outside text in the whole game, so it is
  // bounded and inserted as plain text, never as a key.
  if (out.boss !== undefined && typeof out.boss === "object" && out.boss) {
    var comm = String(out.boss.comm || "").slice(0, 32)
    var label = comm ? comm.charAt(0).toUpperCase() + comm.slice(1) : t("enemy.boss_daemon.name")
    out.boss = t("boss.pattern", {
      comm: label,
      epithet: t("boss.epithet." + Rules.clamp(Rules.num(out.boss.epithet), 0, Rules.BOSS_EPITHETS - 1))
    })
  }
  return out
}

function render(entry, t, state) {
  if (!entry || !t) return ""
  var type = String(entry.type || "")
  var count = variantCount(t, type)
  if (count <= 0) return t("chron." + type + ".0")

  var variant = Math.abs(Rules.num(entry.seed)) % count
  var params = baseParams(state)
  for (var key in (entry.p || {})) params[key] = entry.p[key]

  return t("chron." + type + "." + variant, expand(t, params))
}

// ---- What is worth a line of its own, and what is worth a number.
//
// A day at a machine raises dozens of small events — a workspace crossed, an
// application opened, ten minutes of music. Printed one per line they bury the
// two things that actually happened, and the chronicle stops being something
// anyone reads. So the routine ones are counted and summarised in a single
// line, and the rest are told properly.
// Listed rather than keyed, because the order a day's summary is read in
// should be the same every day — and a set walked newest-first would order it
// by whichever happened last.
var ROUTINE_ORDER = [
  "workspace_discovered", "app_discovered", "windows_opened", "terminal_opened",
  "music_tick", "theme_changed", "rested", "session_milestone",
  "arcane_tick", "commit"
]

var ROUTINE = {}
for (var r = 0; r < ROUTINE_ORDER.length; r++) ROUTINE[ROUTINE_ORDER[r]] = true

// Enough history to look back over without the panel becoming an archive.
var MAX_DAYS_SHOWN = 10

function digest(entries) {
  var notable = []
  var counts = {}

  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    var type = String(entry.type || "")
    if (!ROUTINE[type]) { notable.push(entry); continue }
    counts[type] = (counts[type] || 0) + 1
  }

  var order = []
  for (var o = 0; o < ROUTINE_ORDER.length; o++)
    if (counts[ROUTINE_ORDER[o]]) order.push(ROUTINE_ORDER[o])

  return { notable: notable, counts: counts, order: order }
}

// The one-line summary of a day's routine, already translated.
//
// Two keys per entry, `.one` and `.other`, because "1 portais arcanos" is
// wrong in Portuguese and "1 arcane portals" is wrong in English, and this is
// the one place in the plugin where a number and a noun meet.
function summarise(day, t) {
  var parts = []
  for (var i = 0; i < day.order.length; i++) {
    var type = day.order[i]
    var n = day.counts[type]
    parts.push(t("digest." + type + (n === 1 ? ".one" : ".other"), { n: n }))
  }
  return parts.join(" · ")
}

// Entries newest first, grouped into { date, label, entries[] } for the view.
// `label` is a dictionary key for today and yesterday and a plain date
// otherwise, so the header follows the panel language too.
function groupByDay(entries, now) {
  var at = Rules.num(now, Rules.nowSec())
  var today = Rules.localDate(at)
  var yesterday = Rules.localDate(at - 86400)

  var order = []
  var byDate = {}

  for (var i = entries.length - 1; i >= 0; i--) {
    var entry = entries[i]
    var date = Rules.localDate(Rules.num(entry.ts))
    if (!byDate[date]) {
      byDate[date] = { date: date, labelKey: date === today ? "ui.today" : (date === yesterday ? "ui.yesterday" : ""), entries: [] }
      order.push(byDate[date])
    }
    byDate[date].entries.push(entry)
  }

  // Newest first, and only as far back as anyone is going to scroll.
  var trimmed = order.slice(0, MAX_DAYS_SHOWN)
  for (var d = 0; d < trimmed.length; d++) {
    var summary = digest(trimmed[d].entries)
    trimmed[d].notable = summary.notable
    trimmed[d].counts = summary.counts
    trimmed[d].order = summary.order
  }
  return trimmed
}

// node only; QML reads these as properties of the imported namespace.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    render: render, groupByDay: groupByDay, variantCount: variantCount, expand: expand,
    digest: digest, summarise: summarise, ROUTINE: ROUTINE,
    ROUTINE_ORDER: ROUTINE_ORDER, MAX_DAYS_SHOWN: MAX_DAYS_SHOWN
  }
}
