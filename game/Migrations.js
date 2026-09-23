.pragma library
.import "Rules.js" as Rules

// Save-file versioning, and the shape check every load goes through.
//
// The plugin is installed from git and updated by hand (`omarchy plugin
// update`), so a player can jump several versions at once or stay behind for
// months. Every load therefore runs the migration chain and then `sanitize`,
// which is what actually guarantees the rest of the code can do arithmetic on
// what it reads: unknown keys are dropped, enums are checked against the rule
// set, and every number goes through `num`.
//
// A save that cannot be understood is never deleted. The service renames it
// and starts fresh; `sanitize` is for saves that are merely wrong, not absent.

"use strict"

// Each entry migrates from its index to the next version. Empty for now —
// v1 is the first shipped schema — but the chain is here so that adding one
// later is a push rather than a redesign.
var STEPS = []

function run(save) {
  if (!save || typeof save !== "object") return null

  var version = Rules.num(save.version, 0)
  while (version < Rules.SCHEMA_VERSION) {
    var step = STEPS[version]
    if (typeof step !== "function") {
      // No path from this version. Stamping it and sanitizing is still better
      // than discarding a hero: sanitize drops whatever no longer fits.
      break
    }
    save = step(save)
    version = Rules.num(save.version, version + 1)
  }
  save.version = Rules.SCHEMA_VERSION
  return sanitize(save)
}

// ------------------------------------------------------------------ shape

function pickEnum(value, allowed, fallback) {
  var v = String(value)
  return allowed.indexOf(v) !== -1 ? v : fallback
}

function sanitizeMaterials(raw) {
  var out = {}
  for (var i = 0; i < Rules.MATERIALS.length; i++) {
    var key = Rules.MATERIALS[i]
    out[key] = Math.max(0, Math.floor(Rules.num(raw ? raw[key] : 0)))
  }
  return out
}

function sanitizeEquipment(raw) {
  var out = {}
  for (var i = 0; i < Rules.SLOTS.length; i++) {
    var slot = Rules.SLOTS[i]
    var id = raw ? raw[slot] : null
    out[slot] = Rules.recipeById(id) ? id : null
  }
  return out
}

function sanitizeChest(raw) {
  var out = []
  var list = Array.isArray(raw) ? raw : []
  // Capped: a chest is a list the player reads, and an unbounded one is both a
  // scrolling problem and a way for a corrupted save to grow without limit.
  for (var i = 0; i < list.length && out.length < 60; i++)
    if (Rules.recipeById(list[i])) out.push(String(list[i]))
  return out
}

function sanitizeHero(raw, now) {
  if (!raw || typeof raw !== "object") return null

  var race = pickEnum(raw.race, Rules.RACE_IDS, Rules.RACE_IDS[0])
  // `cls`, not `class`: the save mirrors the field names the rules use, and
  // `class` is a reserved word in the JavaScript these files are written in.
  var cls = pickEnum(raw.cls !== undefined ? raw.cls : raw["class"], Rules.CLASS_IDS, Rules.CLASS_IDS[0])
  var level = Rules.clamp(Math.floor(Rules.num(raw.level, 1)), 1, Rules.MAX_LEVEL)

  var hero = {
    name: String(raw.name || "").slice(0, 24) || "Hero",
    race: race,
    cls: cls,
    level: level,
    xp: Math.max(0, Math.floor(Rules.num(raw.xp))),
    gold: Math.max(0, Math.floor(Rules.num(raw.gold))),
    hp: Math.max(0, Math.floor(Rules.num(raw.hp))),
    hpMax: 1,
    hpUpdatedAt: Math.max(0, Math.floor(Rules.num(raw.hpUpdatedAt, now))),
    energy: Math.max(0, Math.floor(Rules.num(raw.energy))),
    energyMax: Rules.ENERGY_MAX_DEFAULT,
    energyUpdatedAt: Math.max(0, Math.floor(Rules.num(raw.energyUpdatedAt, now))),
    lastRestEnergyAt: Math.max(0, Math.floor(Rules.num(raw.lastRestEnergyAt))),
    lastStrollAt: Math.max(0, Math.floor(Rules.num(raw.lastStrollAt))),
    faintedUntil: Math.max(0, Math.floor(Rules.num(raw.faintedUntil))),
    // Derived, never trusted from disk: a hand-edited attribute block would
    // otherwise be a free stat sheet.
    attrs: Rules.attrsFor(race, cls, level),
    equipment: sanitizeEquipment(raw.equipment),
    chest: sanitizeChest(raw.chest),
    materials: sanitizeMaterials(raw.materials),
    title: Rules.titleFor(level)
  }

  hero.hpMax = Rules.hpMax(hero)
  hero.hp = Rules.clamp(hero.hp, 0, hero.hpMax)
  // xp is capped to what the next level needs, so an edited save levels up on
  // the next award rather than sitting on a bar past its own end.
  var needed = Rules.xpToNext(hero.level)
  if (isFinite(needed)) hero.xp = Math.min(hero.xp, needed - 1)
  else hero.xp = 0

  return hero
}

function sanitizeCounters(raw) {
  var out = Rules.newCounters()
  for (var key in out) out[key] = Math.max(0, Math.floor(Rules.num(raw ? raw[key] : 0)))
  return out
}

function sanitizeQuests(raw, dateString) {
  var fresh = Rules.dailyQuests(dateString)
  if (!Array.isArray(raw)) return fresh

  // The day's quests are drawn from the date, so the pool is authoritative;
  // only progress and the done flag are carried over from disk.
  for (var i = 0; i < fresh.length; i++) {
    for (var j = 0; j < raw.length; j++) {
      if (raw[j] && raw[j].id === fresh[i].id) {
        fresh[i].progress = Rules.clamp(Math.floor(Rules.num(raw[j].progress)), 0, fresh[i].target)
        fresh[i].done = raw[j].done === true
        break
      }
    }
  }
  return fresh
}

function sanitizeDay(raw, now) {
  var today = Rules.localDate(now)
  var date = raw && /^\d{4}-\d{2}-\d{2}$/.test(String(raw.date)) ? String(raw.date) : today
  var day = Rules.newDay(date)

  day.counters = sanitizeCounters(raw ? raw.counters : null)
  day.quests = sanitizeQuests(raw ? raw.quests : null, date)
  var ids = raw && Array.isArray(raw.workspaceIds) ? raw.workspaceIds : []
  day.workspaceIds = []
  for (var w = 0; w < ids.length && day.workspaceIds.length < Rules.MAX_WORKSPACE_IDS; w++) {
    var id = Math.floor(Rules.num(ids[w]))
    if (id > 0 && day.workspaceIds.indexOf(id) === -1) day.workspaceIds.push(id)
  }

  day.sealEarned = !!(raw && raw.sealEarned)
  day.notificationsSent = Rules.clamp(Math.floor(Rules.num(raw ? raw.notificationsSent : 0)), 0, 99)
  day.guardianWeek = raw && raw.guardianWeek ? String(raw.guardianWeek).slice(0, 16) : ""

  for (var i = 0; i < Rules.DOMAINS.length; i++) {
    var domain = Rules.DOMAINS[i]
    day.xpByDomain[domain] = Math.max(0, Math.floor(Rules.num(raw && raw.xpByDomain ? raw.xpByDomain[domain] : 0)))
  }
  return day
}

function sanitizeBosses(raw, now) {
  var out = []
  var list = Array.isArray(raw) ? raw : []
  for (var i = 0; i < list.length && out.length < Rules.MAX_ACTIVE_BOSSES; i++) {
    var boss = list[i]
    if (!boss || typeof boss !== "object") continue
    var expires = Math.floor(Rules.num(boss.expiresAt))
    if (expires <= now) continue
    out.push({
      id: String(boss.id || ("b" + i)).slice(0, 16),
      kind: pickEnum(boss.kind, ["crash", "guardian"], "crash"),
      // The executable's basename, and the only string the plugin ever takes
      // from outside and keeps. Bounded here so a pathological name cannot
      // grow the save.
      comm: String(boss.comm || "").slice(0, 32),
      epithet: Rules.clamp(Math.floor(Rules.num(boss.epithet)), 0, Rules.BOSS_EPITHETS - 1),
      tier: Rules.clamp(Math.floor(Rules.num(boss.tier, 3)), 1, Rules.BOSS_MAX_TIER),
      hp: Math.max(1, Math.floor(Rules.num(boss.hp, 1))),
      hpMax: Math.max(1, Math.floor(Rules.num(boss.hpMax, 1))),
      spawnedAt: Math.max(0, Math.floor(Rules.num(boss.spawnedAt))),
      expiresAt: expires,
      seen: boss.seen === true
    })
  }
  return out
}

function sanitizeExpedition(raw) {
  if (!raw || typeof raw !== "object") return null
  var spec = Rules.expeditionSpec(raw.destId)
  return {
    destId: spec.id,
    place: String(raw.place || "").slice(0, 32),
    startedAt: Math.max(0, Math.floor(Rules.num(raw.startedAt))),
    endsAt: Math.max(0, Math.floor(Rules.num(raw.endsAt))),
    seed: Math.floor(Rules.num(raw.seed)) >>> 0,
    resolved: raw.resolved === true,
    seen: raw.seen === true,
    result: raw.resolved === true && raw.result && typeof raw.result === "object" ? raw.result : null
  }
}

function sanitizeAchievements(raw) {
  var out = []
  var list = Array.isArray(raw) ? raw : []
  for (var i = 0; i < list.length; i++) {
    var id = String(list[i])
    if (Rules.ACHIEVEMENTS.indexOf(id) !== -1 && out.indexOf(id) === -1) out.push(id)
  }
  return out
}

function sanitize(raw) {
  var now = Rules.nowSec()
  var fresh = Rules.newSave(now)

  var out = {
    version: Rules.SCHEMA_VERSION,
    createdAt: Math.max(0, Math.floor(Rules.num(raw.createdAt, now))),
    hero: sanitizeHero(raw.hero, now),
    realm: {
      name: String(raw.realm && raw.realm.name ? raw.realm.name : "").slice(0, 32),
      type: pickEnum(raw.realm ? raw.realm.type : "", ["fortress", "caravan"], "caravan")
    },
    day: sanitizeDay(raw.day, now),
    streak: {
      count: Math.max(0, Math.floor(Rules.num(raw.streak ? raw.streak.count : 0))),
      lastSealDate: raw.streak && /^\d{4}-\d{2}-\d{2}$/.test(String(raw.streak.lastSealDate))
        ? String(raw.streak.lastSealDate) : "",
      missedDays: Rules.clamp(Math.floor(Rules.num(raw.streak ? raw.streak.missedDays : 0)), 0, 999)
    },
    bosses: sanitizeBosses(raw.bosses, now),
    expedition: sanitizeExpedition(raw.expedition),
    // A fight in progress does not survive a restart: the service returns the
    // energy and drops it, so there is nothing to carry across here.
    arena: null,
    achievements: sanitizeAchievements(raw.achievements),
    sensors: {
      lastCoredumpCheck: Math.max(0, Math.floor(Rules.num(raw.sensors ? raw.sensors.lastCoredumpCheck : now, now))),
      lastGitCheck: Math.max(0, Math.floor(Rules.num(raw.sensors ? raw.sensors.lastGitCheck : 0))),
      lastAgentTokens: Math.max(0, Math.floor(Rules.num(raw.sensors ? raw.sensors.lastAgentTokens : 0))),
      hasBattery: !!(raw.sensors && raw.sensors.hasBattery),
      coredumpAvailable: raw.sensors ? raw.sensors.coredumpAvailable !== false : true
    },
    stats: {
      totalXp: Math.max(0, Math.floor(Rules.num(raw.stats ? raw.stats.totalXp : 0))),
      fights: Math.max(0, Math.floor(Rules.num(raw.stats ? raw.stats.fights : 0))),
      bossKills: Math.max(0, Math.floor(Rules.num(raw.stats ? raw.stats.bossKills : 0))),
      expeditions: Math.max(0, Math.floor(Rules.num(raw.stats ? raw.stats.expeditions : 0))),
      forged: Math.max(0, Math.floor(Rules.num(raw.stats ? raw.stats.forged : 0))),
      sessionMinTotal: Math.max(0, Math.floor(Rules.num(raw.stats ? raw.stats.sessionMinTotal : 0)))
    }
  }

  if (out.hero) {
    // Only known once the realm is: a fortress carries one more point.
    out.hero.energyMax = Rules.energyMax(out.hero, out.realm)
    out.hero.energy = Rules.clamp(out.hero.energy, 0, out.hero.energyMax)
  }
  if (!out.realm.name) out.realm.name = fresh.realm.name
  return out
}

// node only; QML reads these as properties of the imported namespace.
if (typeof module !== "undefined" && module.exports) {
  module.exports = { run: run, sanitize: sanitize, STEPS: STEPS }
}
