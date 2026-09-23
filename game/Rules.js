.pragma library

// Every rule the game has, as pure functions over plain objects.
//
// No Qt in here, on purpose: this file is the part worth testing, and under
// node (tests/rules.test.js) it is testable only if it never reaches for a
// QML type. `.pragma library` also makes QML share one stateless copy across
// the service and every panel instead of a copy per component.
//
// Nothing in this file mutates its arguments. World.js owns state changes;
// this file answers questions about numbers.

"use strict"

// ---------------------------------------------------------------- constants

var SCHEMA_VERSION = 1

var MAX_LEVEL = 30

// Domains an event can feed. A class multiplies exactly one of them.
var DOMAINS = ["exploration", "art", "nature", "combat", "arcane"]

var ATTRS = ["str", "agi", "wis", "vit", "cha"]

var BASE_ATTR = 5

// Bar and panel both treat an unknown race or class as the first entry rather
// than rendering nothing, so a save hand-edited into nonsense still opens.
var RACES = {
  human: { id: "human", bonus: {}, xpBonus: 0.10 },
  dwarf: { id: "dwarf", bonus: { vit: 2 }, craftDiscount: 1 },
  elf: { id: "elf", bonus: { agi: 2 }, expeditionSpeedup: 0.15 },
  orc: { id: "orc", bonus: { str: 2 }, bossXpBonus: 0.25 },
  automaton: { id: "automaton", bonus: { wis: 2 }, energyRegenSpeedup: 0.25 }
}

var RACE_IDS = ["human", "dwarf", "elf", "orc", "automaton"]

// `lens` is what a class multiplies, by domain. Five of the six look through
// exactly one at 1.5; the archer looks through two at 1.25, which is what
// makes a ranger a ranger rather than a second rogue.
//
// `secondaries` is the fixed rotation for the every-other-level point. Fixed
// rather than chosen, because a level-up that stops to ask a question is a
// level-up that interrupts, and this game does not interrupt.
var CLASS_LENS = 1.5
var RANGER_LENS = 1.25

var CLASSES = {
  warrior: {
    id: "warrior", lens: { combat: CLASS_LENS }, primary: "str",
    secondaries: ["vit", "agi", "cha", "wis"],
    skill: { id: "heavy_strike", cooldown: 3 },
    // `skillDamage`: what the skill lands relative to a plain hit, zero when it
    // spends the turn on something other than damage. `power` is measured by
    // tools/balance.js and covers everything else the skill is worth.
    combat: { power: 1.054, skillDamage: 2.0 }
  },
  rogue: {
    id: "rogue", lens: { exploration: CLASS_LENS }, primary: "agi",
    secondaries: ["str", "cha", "vit", "wis"],
    skill: { id: "stealth", cooldown: 3 },
    // `skillDamage`: what the skill lands relative to a plain hit, zero when it
    // spends the turn on something other than damage. `power` is measured by
    // tools/balance.js and covers everything else the skill is worth.
    combat: { power: 1.235, skillDamage: 0 }
  },
  bard: {
    id: "bard", lens: { art: CLASS_LENS }, primary: "cha",
    secondaries: ["agi", "wis", "vit", "str"],
    skill: { id: "song", cooldown: 3 },
    // `skillDamage`: what the skill lands relative to a plain hit, zero when it
    // spends the turn on something other than damage. `power` is measured by
    // tools/balance.js and covers everything else the skill is worth.
    combat: { power: 1.06, skillDamage: 0 }
  },
  druid: {
    id: "druid", lens: { nature: CLASS_LENS }, primary: "vit",
    secondaries: ["wis", "str", "cha", "agi"],
    skill: { id: "roots", cooldown: 4 },
    // `skillDamage`: what the skill lands relative to a plain hit, zero when it
    // spends the turn on something other than damage. `power` is measured by
    // tools/balance.js and covers everything else the skill is worth.
    combat: { power: 0.998, skillDamage: 0 }
  },
  archer: {
    // Two lenses instead of one: the ranger covers ground and fights at the
    // end of it, and is worse at both than the specialist would be.
    id: "archer", lens: { exploration: RANGER_LENS, combat: RANGER_LENS }, primary: "agi",
    secondaries: ["str", "vit", "wis", "cha"],
    skill: { id: "volley", cooldown: 3 },
    combat: { power: 0.95, skillDamage: 1.6 }
  },
  mage: {
    id: "mage", lens: { arcane: CLASS_LENS }, primary: "wis",
    secondaries: ["cha", "agi", "vit", "str"],
    skill: { id: "fireball", cooldown: 2 },
    // `skillDamage`: what the skill lands relative to a plain hit, zero when it
    // spends the turn on something other than damage. `power` is measured by
    // tools/balance.js and covers everything else the skill is worth.
    combat: { power: 1.119, skillDamage: 1.5 }
  }
}

var CLASS_IDS = ["warrior", "rogue", "bard", "druid", "mage", "archer"]

// Window classes that count as "a portal to the arcane". Matched
// case-insensitively against the Hyprland window class and never stored.
var TERMINAL_CLASSES = [
  "alacritty", "ghostty", "com.mitchellh.ghostty", "kitty", "foot", "footclient",
  "wezterm", "org.wezfurlong.wezterm", "org.omarchy.agent", "xterm", "st",
  "konsole", "gnome-terminal", "terminator", "tilix", "rio"
]

var MATERIALS = ["iron", "wood", "feather", "crystal", "oil", "core"]

var SLOTS = ["weapon", "armor", "amulet"]

// ---- Titles. Thresholds are read from the top down, so the order matters.
var TITLES = [
  { level: 30, id: "myth" },
  { level: 25, id: "legend" },
  { level: 20, id: "hero" },
  { level: 15, id: "champion" },
  { level: 10, id: "veteran" },
  { level: 5, id: "adventurer" },
  { level: 1, id: "novice" }
]

// ---- Passive XP. `xp` is the base award; `cap` is how many times a day the
// award is paid at all.
//
// The spec states the daily ceiling per sensor as a mix of "10 workspaces" and
// "20 XP". Both are expressed here as a count of paid events, derived from the
// XP ceiling where the spec gave one — a counter is what the save already
// keeps, and capping the count means the multipliers below still apply in
// full to every event that is paid, which is what the spec asks for
// ("the XP below is the base; the class lens, Human and the Seal apply after").
//
// Counters keep climbing past the cap: daily quests and achievements count
// what you did, not what you were paid for.
var PASSIVE = {
  workspace_discovered: { xp: 2, cap: 10, domain: "exploration", counter: "workspaces" },
  app_discovered: { xp: 3, cap: 15, domain: "exploration", counter: "apps" },
  windows_opened: { xp: 1, cap: 20, domain: "exploration", counter: "windowAwards" },
  terminal_opened: { xp: 2, cap: 10, domain: "arcane", counter: "terminals" },
  music_tick: { xp: 1, cap: 30, domain: "art", counter: "musicTicks" },
  theme_changed: { xp: 5, cap: 3, domain: "art", counter: "themes" },
  rested: { xp: 2, cap: 10, domain: "nature", counter: "rests" },
  session_milestone: { xp: 5, cap: 6, domain: "nature", counter: "milestones" },
  storm: { xp: 5, cap: 2, domain: "nature", counter: "weather" },
  fair_weather: { xp: 5, cap: 2, domain: "nature", counter: "weather" },
  arcane_tick: { xp: 1, cap: 30, domain: "arcane", counter: "arcaneTicks" },
  commit: { xp: 5, cap: 10, domain: "arcane", counter: "commits" }
}

// One `windows_opened` award per this many windows.
var WINDOWS_PER_AWARD = 5

// One `music_tick` per this many minutes of something playing.
var MUSIC_MINUTES_PER_TICK = 10

// One `session_milestone` per this many active (non-idle) minutes.
var SESSION_MINUTES_PER_MILESTONE = 240

// One `arcane_tick` per this many agent tokens.
var TOKENS_PER_ARCANE_TICK = 10000

// ---- Health and energy.
var HP_REGEN_PER_HOUR = 0.10
var ENERGY_REGEN_SECONDS = 7200        // one point every two hours
var ENERGY_MAX_DEFAULT = 5
var ENERGY_MAX_FORTRESS = 6
var REST_ENERGY_COOLDOWN = 3600        // a rest tops up energy at most hourly
var REST_SECONDS = 300                 // idle this long counts as a rest
var DEEP_REST_SECONDS = 900            // idle this long heals to full
var TAVERN_SECONDS = 1800              // fainted, then back at half health

// ---- The stroll. The only thing in the game that happens on the screen
// rather than in the panel, and the only one with no cost at all.
//
// Walking is unlimited: it is a thing you do because you felt like watching
// it, and a button that says "not now" to that is a button that annoys. What
// is rationed is **finding something** — otherwise a free walk that pays a
// material is a material printer. So the hero goes out whenever asked, and
// comes back with something at most three times a day.
var STROLL_SECONDS = 26
var STROLL_FIND_COOLDOWN = 5400        // an hour and a half between finds
var MAX_STROLL_FINDS_PER_DAY = 3

// ---- Arena.
var MAX_ACTIVE_BOSSES = 3
var BOSS_LIFETIME_SECONDS = 604800     // seven days, then it retreats
var BOSS_MAX_TIER = 4
var BOSS_GROWTH = 0.20
var BOSS_EPITHETS = 20
var WANDERERS_PER_DAY = 3
var ENEMY_KINDS = ["slime", "rat", "bat", "goblin", "skeleton", "wolf", "golem", "wraith"]
var ENEMY_TIER = { slime: 1, rat: 1, bat: 1, goblin: 2, skeleton: 2, wolf: 2, golem: 3, wraith: 3 }

// ---- Daily quests and the Seal.
var QUESTS_PER_DAY = 3
var QUEST_XP = 20
var QUEST_GOLD = 10
var STREAK_BONUS_PER_DAY = 0.01
var STREAK_BONUS_CAP = 0.20
var STREAK_GRACE_DAYS = 3              // the streak survives two missed days
var MAX_NOTIFICATIONS_PER_DAY = 2
var MAX_CHRONICLE_ENTRIES = 300
var MAX_WORKSPACE_IDS = 32

var QUEST_POOL = [
  { id: "visit_3_ws", counter: "workspaces", target: 3 },
  { id: "open_5_apps", counter: "apps", target: 5 },
  { id: "music_20", counter: "musicMinutes", target: 20 },
  { id: "rest_once", counter: "rests", target: 1 },
  { id: "session_2h", counter: "sessionMin", target: 120 },
  { id: "win_1", counter: "arenaWins", target: 1 },
  { id: "expedition_1", counter: "expeditions", target: 1 },
  { id: "forge_1", counter: "forged", target: 1 },
  { id: "theme_1", counter: "themes", target: 1 },
  { id: "terminals_3", counter: "terminals", target: 3 },
  { id: "boss_fight_1", counter: "bossFights", target: 1 },
  { id: "passive_30", counter: "passiveXp", target: 30 }
]

// ---- Expeditions. Destinations are drawn from this pool by the day's seed.
var EXPEDITIONS = [
  { id: "short", minutes: 30, risk: "low", xp: 8, gold: [5, 10], materials: [1, 1], itemChance: 0 },
  { id: "medium", minutes: 120, risk: "medium", xp: 25, gold: [15, 30], materials: [1, 2], itemChance: 0.10 },
  { id: "long", minutes: 480, risk: "high", xp: 60, gold: [40, 80], materials: [2, 3], itemChance: 0.25 }
]

var DESTINATIONS = [
  "hollow_mine", "glass_forest", "salt_marsh", "old_foundry", "singing_caves",
  "frozen_relay", "amber_steppe", "drowned_library", "ashen_ridge", "quiet_orchard"
]

var ENCOUNTER_CHANCE = 0.10

// ---- The forge. Costs are in materials; `stats` are added while equipped.
var RECIPES = [
  { id: "iron_sword", slot: "weapon", tier: 1, cost: { iron: 3, wood: 1 }, stats: { damage: 2 } },
  { id: "rune_blade", slot: "weapon", tier: 2, cost: { iron: 4, crystal: 2 }, stats: { damage: 4 } },
  { id: "core_sword", slot: "weapon", tier: 3, cost: { iron: 3, core: 1 }, stats: { damage: 6, str: 1 } },
  { id: "leather_vest", slot: "armor", tier: 1, cost: { wood: 3, feather: 1 }, stats: { defense: 1 } },
  { id: "plated_mail", slot: "armor", tier: 2, cost: { iron: 5, oil: 2 }, stats: { defense: 2, vit: 1 } },
  { id: "core_aegis", slot: "armor", tier: 3, cost: { iron: 4, core: 1 }, stats: { defense: 3, vit: 2 } },
  { id: "raven_charm", slot: "amulet", tier: 1, cost: { feather: 3, wood: 1 }, stats: { agi: 1 } },
  { id: "theme_prism", slot: "amulet", tier: 2, cost: { crystal: 4, oil: 1 }, stats: { cha: 1, goldBonus: 0.10 } },
  { id: "core_sigil", slot: "amulet", tier: 3, cost: { core: 1, crystal: 3 }, stats: { wis: 2, xpBonus: 0.05 } }
]

// ---- The merchant.
//
// Gold had nowhere to go: you could change calling once and that was it, while
// the chest filled with whatever a better sword replaced. So somebody passes
// through with three things to sell, drawn from the date like everything else
// that is "today's", and will take the old gear off your hands.
//
// The point is not an economy. It is that being one iron short of a recipe
// should be solvable by having fought, rather than by waiting for the right
// drop.
var MATERIAL_PRICE = {
  iron: 14, wood: 10, feather: 18, crystal: 26, oil: 20, core: 70
}

var MERCHANT_OFFERS = 3

// Selling returns gold rather than materials, and less than buying the same
// thing back would cost — the merchant is not a laundry.
var SELL_PER_TIER = 30

function itemValue(recipe) {
  if (!recipe) return 0
  return SELL_PER_TIER * clamp(num(recipe.tier, 1), 1, 3)
}

function merchantStock(dateString) {
  var random = rng(seedFromDate(dateString, "merchant"))
  var pool = sample(random, MATERIALS, MERCHANT_OFFERS)
  var out = []
  for (var i = 0; i < pool.length; i++) {
    var material = pool[i]
    // A core is rare enough that it comes one at a time; the rest come in
    // small handfuls so that buying one is a decision rather than a habit.
    var count = material === "core" ? 1 : randInt(random, 2, 4)
    out.push({
      id: "offer" + i,
      material: material,
      count: count,
      gold: Math.round(num(MATERIAL_PRICE[material], 15) * count * 1.15)
    })
  }
  return out
}

var ACHIEVEMENTS = [
  "first_blood", "survivor", "guardian_slayer", "marathon", "explorer", "melomaniac",
  "chameleon", "smith", "collector", "constant", "traveller", "myth"
]

// ---------------------------------------------------------------- utilities

// Anything read off disk goes through here before it is used in arithmetic. A
// NaN that reaches a health bar is a health bar that never renders again.
function num(value, fallback) {
  var n = Number(value)
  if (!isFinite(n)) return fallback === undefined ? 0 : fallback
  return n
}

function clamp(value, low, high) {
  if (value < low) return low
  if (value > high) return high
  return value
}

function nowSec() {
  return Math.floor(Date.now() / 1000)
}

// Local calendar date, not UTC: the game day turns over at the player's
// midnight, wherever they are.
function localDate(epochSeconds) {
  var d = new Date((epochSeconds === undefined ? nowSec() : epochSeconds) * 1000)
  var month = d.getMonth() + 1
  var day = d.getDate()
  return d.getFullYear() + "-" + (month < 10 ? "0" : "") + month + "-" + (day < 10 ? "0" : "") + day
}

function isWeekend(dateString) {
  var parts = String(dateString).split("-")
  var d = new Date(num(parts[0]), num(parts[1]) - 1, num(parts[2]))
  var day = d.getDay()
  return day === 0 || day === 6
}

// ISO week key, so the weekend Guardian is one creature per week rather than
// one per Saturday and another per Sunday.
function isoWeekKey(dateString) {
  var parts = String(dateString).split("-")
  var d = new Date(Date.UTC(num(parts[0]), num(parts[1]) - 1, num(parts[2])))
  var dayNumber = (d.getUTCDay() + 6) % 7
  d.setUTCDate(d.getUTCDate() - dayNumber + 3)
  var firstThursday = new Date(Date.UTC(d.getUTCFullYear(), 0, 4))
  var firstDayNumber = (firstThursday.getUTCDay() + 6) % 7
  firstThursday.setUTCDate(firstThursday.getUTCDate() - firstDayNumber + 3)
  var week = 1 + Math.round((d.getTime() - firstThursday.getTime()) / (7 * 86400000))
  return d.getUTCFullYear() + "-W" + (week < 10 ? "0" : "") + week
}

// mulberry32. Everything that has to look the same on two openings of the
// panel — today's quests, today's wanderers, an expedition's outcome — is
// drawn from one of these rather than from Math.random.
function rng(seed) {
  var state = num(seed) >>> 0
  return function () {
    state = (state + 0x6D2B79F5) >>> 0
    var t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// A stable 32-bit hash of a string, for seeding from a date or a name.
function hash(text) {
  var h = 2166136261 >>> 0
  var s = String(text)
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 16777619) >>> 0
  }
  return h >>> 0
}

function seedFromDate(dateString, salt) {
  return hash(String(dateString) + "|" + String(salt === undefined ? "" : salt))
}

function randInt(random, low, high) {
  return low + Math.floor(random() * (high - low + 1))
}

function pick(random, list) {
  return list[Math.floor(random() * list.length)]
}

// Draw `count` distinct entries, in the list's own order.
function sample(random, list, count) {
  var pool = list.slice()
  var out = []
  var wanted = Math.min(count, pool.length)
  for (var i = 0; i < wanted; i++) out.push(pool.splice(Math.floor(random() * pool.length), 1)[0])
  return out
}

function raceOf(hero) {
  return RACES[hero && hero.race] || RACES[RACE_IDS[0]]
}

function classOf(hero) {
  return CLASSES[hero && hero.cls] || CLASSES[CLASS_IDS[0]]
}

// ------------------------------------------------------------- progression

function xpToNext(level) {
  var l = clamp(Math.floor(num(level, 1)), 1, MAX_LEVEL)
  if (l >= MAX_LEVEL) return Infinity
  return Math.round(80 * Math.pow(l, 1.2))
}

function titleFor(level) {
  var l = num(level, 1)
  for (var i = 0; i < TITLES.length; i++) if (l >= TITLES[i].level) return TITLES[i].id
  return TITLES[TITLES.length - 1].id
}

// Attributes are derived from race and level rather than stored and
// incremented: a save that loses a level-up, or gains one from a migration,
// still ends up with the attributes its level says it should have.
function attrsFor(race, cls, level) {
  var out = {}
  for (var i = 0; i < ATTRS.length; i++) out[ATTRS[i]] = BASE_ATTR

  var raceSpec = RACES[race] || RACES[RACE_IDS[0]]
  for (var key in raceSpec.bonus) out[key] += raceSpec.bonus[key]

  var classSpec = CLASSES[cls] || CLASSES[CLASS_IDS[0]]
  var levels = clamp(Math.floor(num(level, 1)), 1, MAX_LEVEL)

  // One point in the primary per level gained, and one in the rotating
  // secondary every other level.
  out[classSpec.primary] += levels - 1
  var secondaryPoints = Math.floor((levels - 1) / 2)
  for (var n = 0; n < secondaryPoints; n++) {
    var attr = classSpec.secondaries[n % classSpec.secondaries.length]
    out[attr] += 1
  }
  return out
}

// The spec's `20 + 4*Vigor + 2*level` was measured and rebalanced: because the
// class primary rises by one a level, a level 30 druid reaches 34 Vigor while
// a warrior sits on 9, and at four health a point that is a hero with twice
// another hero's health. Three a point with three a level keeps Vigor clearly
// worth having without making one class a different game. See
// docs/decisions.md.
function hpMax(hero) {
  var attrs = hero && hero.attrs ? hero.attrs : attrsFor(hero && hero.race, hero && hero.cls, hero && hero.level)
  var bonus = equipmentStats(hero)
  return Math.max(1, Math.round(20 + 3 * (num(attrs.vit, BASE_ATTR) + num(bonus.vit)) + 3 * num(hero && hero.level, 1)))
}

function energyMax(hero, realm) {
  return realm && realm.type === "fortress" ? ENERGY_MAX_FORTRESS : ENERGY_MAX_DEFAULT
}

function energyRegenSeconds(hero) {
  var speedup = num(raceOf(hero).energyRegenSpeedup)
  return Math.round(ENERGY_REGEN_SECONDS * (1 - speedup))
}

// The total XP multiplier applied to a base award, given who the hero is and
// how long their streak is.
function xpMultiplier(hero, domain, streakCount, isBoss) {
  var multiplier = 1
  var lens = classOf(hero).lens
  if (lens && lens[domain]) multiplier *= lens[domain]

  multiplier *= 1 + num(raceOf(hero).xpBonus)
  if (isBoss) multiplier *= 1 + num(raceOf(hero).bossXpBonus)

  multiplier *= 1 + clamp(num(streakCount) * STREAK_BONUS_PER_DAY, 0, STREAK_BONUS_CAP)
  multiplier *= 1 + num(equipmentStats(hero).xpBonus)
  return multiplier
}

function awardXp(hero, baseXp, domain, streakCount, isBoss) {
  return Math.max(0, Math.round(num(baseXp) * xpMultiplier(hero, domain, streakCount, isBoss)))
}

// Levels gained by `xp`, as a count and the XP left over. Returns the input
// unchanged at the cap — overflow past level 30 is kept in stats.totalXp, not
// thrown away, but it stops moving the bar.
function levelUps(level, xp) {
  var lvl = clamp(Math.floor(num(level, 1)), 1, MAX_LEVEL)
  var pool = Math.max(0, num(xp))
  var gained = 0
  while (lvl < MAX_LEVEL) {
    var needed = xpToNext(lvl)
    if (pool < needed) break
    pool -= needed
    lvl += 1
    gained += 1
  }
  if (lvl >= MAX_LEVEL) pool = 0
  return { level: lvl, xp: pool, gained: gained }
}

// --------------------------------------------------------- lazy regeneration

// Health and energy are stored with the moment they were last correct, and
// caught up when they are read. Nothing has to run in the background for the
// hero to heal, and closing the laptop for a week works exactly as well as
// leaving it open.
function regen(hero, realm, now) {
  var at = num(now, nowSec())
  var out = cloneHero(hero)

  var maxHp = hpMax(out)
  var hpSince = Math.max(0, at - num(out.hpUpdatedAt, at))
  if (num(out.faintedUntil) > at) {
    // Out cold in the tavern: no trickle, one step back to half at the end.
    out.hp = 0
  } else {
    if (num(out.faintedUntil) > 0 && num(out.faintedUntil) <= at) {
      out.hp = Math.max(num(out.hp), Math.round(maxHp * 0.5))
      out.faintedUntil = 0
    }
    var healed = Math.floor(maxHp * HP_REGEN_PER_HOUR * (hpSince / 3600))
    if (healed > 0) out.hp = Math.min(maxHp, num(out.hp) + healed)
  }
  out.hp = clamp(num(out.hp), 0, maxHp)
  out.hpMax = maxHp
  out.hpUpdatedAt = at

  var maxEnergy = energyMax(out, realm)
  var perPoint = energyRegenSeconds(out)
  var energySince = Math.max(0, at - num(out.energyUpdatedAt, at))
  var points = Math.floor(energySince / perPoint)
  if (points > 0) {
    out.energy = Math.min(maxEnergy, num(out.energy) + points)
    // Keep the remainder, so a point is never lost to rounding on a read.
    out.energyUpdatedAt = num(out.energyUpdatedAt, at) + points * perPoint
  }
  if (num(out.energy) >= maxEnergy) out.energyUpdatedAt = at
  out.energy = clamp(num(out.energy), 0, maxEnergy)
  out.energyMax = maxEnergy

  return out
}

function cloneHero(hero) {
  var out = {}
  for (var key in hero) out[key] = hero[key]
  out.attrs = {}
  for (var attr in (hero && hero.attrs ? hero.attrs : {})) out.attrs[attr] = hero.attrs[attr]
  out.materials = {}
  for (var material in (hero && hero.materials ? hero.materials : {})) out.materials[material] = hero.materials[material]
  out.equipment = {}
  for (var slot in (hero && hero.equipment ? hero.equipment : {})) out.equipment[slot] = hero.equipment[slot]
  out.chest = (hero && hero.chest ? hero.chest : []).slice()
  return out
}

// ----------------------------------------------------------------- equipment

function recipeById(id) {
  for (var i = 0; i < RECIPES.length; i++) if (RECIPES[i].id === id) return RECIPES[i]
  return null
}

// Summed stats of everything equipped. Unknown ids contribute nothing, so a
// save naming an item from a future version degrades instead of breaking.
function equipmentStats(hero) {
  var out = { damage: 0, defense: 0, str: 0, agi: 0, wis: 0, vit: 0, cha: 0, goldBonus: 0, xpBonus: 0 }
  var equipment = hero && hero.equipment ? hero.equipment : {}
  for (var i = 0; i < SLOTS.length; i++) {
    var recipe = recipeById(equipment[SLOTS[i]])
    if (!recipe) continue
    for (var key in recipe.stats) out[key] = num(out[key]) + num(recipe.stats[key])
  }
  return out
}

// Attributes as they act in combat: the level curve plus whatever is worn.
function effectiveAttrs(hero) {
  var base = hero && hero.attrs ? hero.attrs : attrsFor(hero && hero.race, hero && hero.cls, hero && hero.level)
  var bonus = equipmentStats(hero)
  var out = {}
  for (var i = 0; i < ATTRS.length; i++) out[ATTRS[i]] = num(base[ATTRS[i]], BASE_ATTR) + num(bonus[ATTRS[i]])
  return out
}

// A dwarf pays one material less on every line of a recipe, never below one.
function costFor(hero, recipe) {
  var discount = num(raceOf(hero).craftDiscount)
  var out = {}
  for (var key in recipe.cost) out[key] = Math.max(1, num(recipe.cost[key]) - discount)
  return out
}

function canCraft(hero, recipe) {
  if (!recipe) return false
  var cost = costFor(hero, recipe)
  var have = hero && hero.materials ? hero.materials : {}
  for (var key in cost) if (num(have[key]) < cost[key]) return false
  return true
}

// -------------------------------------------------------------------- combat

// ---- An enemy is built against the hero who is about to fight it.
//
// The spec's `hp = 12*tier + 2*level` and `atk = 2 + 2*tier + level/5` were
// measured before being trusted, and they do not survive contact: a level 1
// hero wins 100% of the time, and past level 8 the win rate by class ran from
// 0% (bard) to 71% (rogue) — the spread came from the class primary rising a
// point a level, which is worth a great deal as Vigor or Agility and nothing
// at all as Charisma.
//
// Scaling against the hero instead of against a table closes that gap by
// construction: an enemy carries TURNS_TO_KILL turns of *this* hero's damage
// and hits hard enough to end *this* hero in TURNS_TO_DIE. Class then shows up
// as how a fight feels — the rogue dodges, the druid endures, the warrior ends
// it early — rather than as whether it can be won at all, which is the right
// shape for a game whose first rule is that it never punishes. Tier is the
// difficulty knob on top. See docs/decisions.md.
var TURNS_TO_KILL = 5.0
var TURNS_TO_DIE = 5.4
// Tier is a light knob, deliberately. Because the enemy is already built
// against this hero, the fight is a race between two near-equal processes and
// the outcome is violently sensitive to these: at 0.80/1.18 the measured win
// rate ran from 100% at tier 1 to 45% at tier 3.
var TIER_HP = [0, 1.00, 1.03, 1.06, 1.10]
var TIER_ATK = [0, 1.00, 1.02, 1.04, 1.07]

// A fight has to end. A bard healing 30% of its health every fourth turn, or a
// druid skipping the enemy's turn every fifth, can otherwise out-sustain the
// damage coming in forever — measured at 61 turns before this existed. From
// PRESSURE_TURN on, everything the enemy lands hits harder each turn, so
// stalling loses rather than drawing, and no fight can outrun the budget.
var PRESSURE_TURN = 6
var PRESSURE_PER_TURN = 1.00

// An enemy's every third turn is a special at one and a half times damage, and
// every second turn for a boss. `atk` is the number the formula below solves
// for, so the average has to be divided back out or every enemy hits for a
// sixth more than it was built to.
var ENEMY_SPECIAL_AVERAGE = (2 + 1.5) / 3
var BOSS_SPECIAL_AVERAGE = (1 + 1.5) / 2

function enemyFor(kind, tier, hero, boss) {
  var t = clamp(Math.floor(num(tier, 1)), 1, BOSS_MAX_TIER)
  var level = clamp(Math.floor(num(hero && hero.level, 1)), 1, MAX_LEVEL)
  var attrs = effectiveAttrs(hero)
  var gear = equipmentStats(hero)

  // What the hero lands in an average turn: the swing averages +1, and a
  // critical is half again on the share of turns it happens.
  var heroDamage = (3 + num(attrs.str) + level + num(gear.damage) + 1) * (1 + critChance(attrs) * 0.5)

  // Fold in the skill rotation. Over one cooldown cycle the hero spends
  // `cooldown` turns attacking and one on the skill, which lands
  // `skillDamage` times a plain hit — scaled by skillPower, which rises with
  // the class primary. Without this the warrior and the mage outgrow their own
  // enemies: measured, both reached a 100% win rate by level 25 purely
  // because their skill got stronger while the enemy did not.
  var classSpec = classOf(hero)
  var cooldown = classSpec.skill.cooldown
  heroDamage *= (cooldown + num(classSpec.combat.skillDamage) * skillPower(hero, attrs)) / (cooldown + 1)
  var hp = Math.max(4, Math.round(TURNS_TO_KILL * Math.max(1, heroDamage - t) * classSpec.combat.power * TIER_HP[t]))

  // And what it takes to end the hero on schedule, undoing on the way in
  // exactly what the hero will subtract: the dodge roll, the flat agility
  // reduction, and worn armour.
  var wanted = hpMax(hero) / TURNS_TO_DIE / (boss ? BOSS_SPECIAL_AVERAGE : ENEMY_SPECIAL_AVERAGE)
  var atk = Math.max(1, Math.round(
    (wanted / (1 - dodgeChance(attrs)) + Math.floor(num(attrs.agi) / 2) + num(gear.defense) - 1) * TIER_ATK[t]))

  return {
    kind: String(kind || "slime"),
    tier: t,
    hp: hp,
    hpMax: hp,
    atk: atk,
    def: t,
    boss: !!boss
  }
}

function dodgeChance(attrs) {
  return clamp(num(attrs.agi) * 0.02, 0, 0.40)
}

function critChance(attrs) {
  return clamp(0.05 + num(attrs.agi) * 0.01, 0, 0.30)
}

// A class's signature move scales with the attribute that class actually
// raises, not with Wisdom.
//
// The spec tied every skill to Wisdom, which leaves four of the five classes
// with a skill that never improves — and leaves Charisma, the bard's primary,
// worth nothing at all in a fight. Measured, the bard lost 100% of its fights
// at every level past 8. Reading the skill off the primary gives each class a
// move that grows with it and gives Charisma a reason to exist in the arena,
// while Wisdom keeps its meaning for the mage, whose primary it is.
// Capped, because the primary reaches 34 by level 30.
var SKILL_POWER_PER_POINT = 0.02
var SKILL_POWER_CAP = 1.45

function skillPower(hero, attrs) {
  var primary = classOf(hero).primary
  var points = Math.max(0, num(attrs[primary]) - BASE_ATTR)
  return Math.min(SKILL_POWER_CAP, 1 + points * SKILL_POWER_PER_POINT)
}

// One exchange. `action` is attack | skill | defend; fleeing is handled by the
// caller because it ends the fight without an exchange.
//
// `fight` is {hero, enemy, turn, cooldown, guardTurns, enemySkipTurns} and is
// returned changed, never mutated. `random` is injected so a test can pin it.
function combatRound(hero, fight, action, random) {
  var attrs = effectiveAttrs(hero)
  var gear = equipmentStats(hero)
  var classSpec = classOf(hero)
  var log = []

  var enemyHp = num(fight.enemyHp)
  var heroHp = num(fight.heroHp)
  var turn = num(fight.turn)
  var cooldown = num(fight.cooldown)
  var enemySkip = num(fight.enemySkipTurns)
  var guarded = false
  var dodgeNext = !!fight.dodgeNext
  var critNext = !!fight.critNext

  // Str plus the level itself: without the flat term a class that never
  // raises Str deals the same damage at 30 as it did at 1, and the enemy
  // curve leaves it behind entirely.
  var baseDamage = 3 + num(attrs.str) + num(hero && hero.level, 1) + num(gear.damage)
  var enemyDef = num(fight.enemy.def)

  if (action === "skill" && cooldown <= 0) {
    cooldown = classSpec.skill.cooldown
    var power = skillPower(hero, attrs)
    if (classSpec.skill.id === "heavy_strike") {
      var heavy = Math.max(1, Math.round((baseDamage * 2 * power) + randInt(random, 0, 2) - enemyDef))
      enemyHp -= heavy
      log.push({ key: "skill_heavy_strike", damage: heavy })
    } else if (classSpec.skill.id === "fireball") {
      // Ignores defence, which is what makes it worth a shorter cooldown.
      var fire = Math.max(1, Math.round(baseDamage * 1.5 * power) + randInt(random, 0, 2))
      enemyHp -= fire
      log.push({ key: "skill_fireball", damage: fire })
    } else if (classSpec.skill.id === "volley") {
      var firstShot = Math.max(1, Math.round(baseDamage * 0.8 * power) + randInt(random, 0, 1) - enemyDef)
      var secondShot = Math.max(1, Math.round(baseDamage * 0.8 * power) + randInt(random, 0, 1) - enemyDef)
      enemyHp -= firstShot + secondShot
      log.push({ key: "skill_volley", damage: firstShot + secondShot })
    } else if (classSpec.skill.id === "song") {
      var healed = Math.round(hpMax(hero) * 0.30 * power)
      heroHp = Math.min(hpMax(hero), heroHp + healed)
      log.push({ key: "skill_song", heal: healed })
    } else if (classSpec.skill.id === "roots") {
      enemySkip += 1
      log.push({ key: "skill_roots" })
    } else if (classSpec.skill.id === "stealth") {
      // Two separate promises, and they are kept on different turns: the dodge
      // is spent by the enemy later this round, the critical by the hero on
      // the next one. One flag would have the enemy's swing consume both.
      dodgeNext = true
      critNext = true
      log.push({ key: "skill_stealth" })
    }
  } else if (action === "defend") {
    guarded = true
    var mended = Math.round(hpMax(hero) * 0.10)
    heroHp = Math.min(hpMax(hero), heroHp + mended)
    log.push({ key: "defend", heal: mended })
  } else {
    // A plain attack, and what an unavailable skill falls back to rather than
    // spending the turn on nothing.
    var crit = critNext || random() < critChance(attrs)
    var damage = Math.max(1, baseDamage + randInt(random, 0, 2) - enemyDef)
    if (crit) damage = Math.round(damage * 1.5)
    enemyHp -= damage
    log.push({ key: crit ? "hit_crit" : "hit", damage: damage })
    critNext = false
  }

  turn += 1
  if (cooldown > 0 && action !== "skill") cooldown -= 1

  if (enemyHp <= 0) {
    return {
      heroHp: Math.max(0, heroHp), enemyHp: 0, turn: turn, cooldown: cooldown,
      enemySkipTurns: enemySkip, dodgeNext: dodgeNext, critNext: critNext,
      log: log, outcome: "won"
    }
  }

  // ---- The enemy's half of the exchange.
  if (enemySkip > 0) {
    enemySkip -= 1
    log.push({ key: "enemy_rooted" })
  } else {
    var special = fight.enemy.boss ? (turn % 2 === 0) : (turn % 3 === 0)
    var incoming = num(fight.enemy.atk) + randInt(random, 0, 2) - Math.floor(num(attrs.agi) / 2)
    if (special) incoming = Math.round(incoming * 1.5)
    incoming = Math.max(1, incoming - num(gear.defense))
    if (turn > PRESSURE_TURN)
      incoming = Math.round(incoming * (1 + PRESSURE_PER_TURN * (turn - PRESSURE_TURN)))

    // Stealth buys one guaranteed miss, on top of the normal dodge roll.
    if (dodgeNext || random() < dodgeChance(attrs)) {
      log.push({ key: "dodge" })
      dodgeNext = false
    } else {
      if (guarded) incoming = Math.max(1, Math.floor(incoming / 2))
      heroHp -= incoming
      log.push({ key: special ? "enemy_special" : "enemy_hit", damage: incoming })
    }
  }

  var outcome = heroHp <= 0 ? "lost" : "ongoing"
  return {
    heroHp: Math.max(0, heroHp), enemyHp: enemyHp, turn: turn, cooldown: cooldown,
    enemySkipTurns: enemySkip, dodgeNext: dodgeNext, critNext: critNext,
    log: log, outcome: outcome
  }
}

function combatRewards(hero, enemy, streakCount, random) {
  var tier = clamp(num(enemy.tier, 1), 1, BOSS_MAX_TIER)
  var isBoss = !!enemy.boss
  var attrs = effectiveAttrs(hero)
  var gear = equipmentStats(hero)

  var baseXp = isBoss ? 60 * tier : 15 + 5 * tier
  var goldBonus = 1 + Math.max(0, num(attrs.cha) - BASE_ATTR) * 0.04 + num(gear.goldBonus)
  var baseGold = isBoss ? 20 * tier : randInt(random, 5, 20) * tier

  var out = {
    xp: awardXp(hero, baseXp, "combat", streakCount, isBoss),
    gold: Math.round(baseGold * goldBonus),
    materials: {},
    item: null
  }

  if (isBoss) {
    out.materials.core = 1
  } else if (random() < 0.60) {
    var material = random() < 0.5 ? "iron" : "wood"
    out.materials[material] = 1
  }

  var rareChance = 0.05 + Math.max(0, num(attrs.cha) - BASE_ATTR) * 0.005
  if (random() < rareChance) {
    var affordable = []
    for (var i = 0; i < RECIPES.length; i++) if (RECIPES[i].tier <= tier) affordable.push(RECIPES[i].id)
    if (affordable.length) out.item = pick(random, affordable)
  }
  return out
}

// ------------------------------------------------------------ daily content

function dailyQuests(dateString) {
  var random = rng(seedFromDate(dateString, "quests"))
  var drawn = sample(random, QUEST_POOL, QUESTS_PER_DAY)
  var out = []
  for (var i = 0; i < drawn.length; i++)
    out.push({ id: drawn[i].id, counter: drawn[i].counter, progress: 0, target: drawn[i].target, done: false })
  return out
}

function wanderers(dateString, level) {
  var random = rng(seedFromDate(dateString, "wanderers"))
  var out = []
  for (var i = 0; i < WANDERERS_PER_DAY; i++) {
    var kind = pick(random, ENEMY_KINDS)
    // Tier follows the bestiary, nudged up once the hero outgrows it, so a
    // level 20 hero is not still being offered rats.
    var tier = clamp(ENEMY_TIER[kind] + Math.floor(num(level, 1) / 12), 1, 3)
    out.push({ id: "w" + i, kind: kind, tier: tier })
  }
  return out
}

function destinations(dateString, hero) {
  var random = rng(seedFromDate(dateString, "destinations"))
  var places = sample(random, DESTINATIONS, EXPEDITIONS.length)
  var speedup = num(raceOf(hero).expeditionSpeedup)
  var out = []
  for (var i = 0; i < EXPEDITIONS.length; i++) {
    var spec = EXPEDITIONS[i]
    out.push({
      id: spec.id,
      place: places[i],
      minutes: Math.max(1, Math.round(spec.minutes * (1 - speedup))),
      risk: spec.risk
    })
  }
  return out
}

function expeditionSpec(id) {
  for (var i = 0; i < EXPEDITIONS.length; i++) if (EXPEDITIONS[i].id === id) return EXPEDITIONS[i]
  return EXPEDITIONS[0]
}

// Deterministic in the expedition's own seed, so the result is the same
// whether it is collected on time, after a reboot, or a week later.
function resolveExpedition(expedition, hero, streakCount) {
  var spec = expeditionSpec(expedition && expedition.destId)
  var random = rng(num(expedition && expedition.seed))

  var result = {
    xp: awardXp(hero, spec.xp, "nature", streakCount, false),
    gold: randInt(random, spec.gold[0], spec.gold[1]),
    materials: {},
    item: null,
    encounter: false
  }

  var count = randInt(random, spec.materials[0], spec.materials[1])
  var pool = spec.risk === "high" ? MATERIALS : ["iron", "wood", "feather", "oil"]
  for (var i = 0; i < count; i++) {
    var material = pick(random, pool)
    result.materials[material] = num(result.materials[material]) + 1
  }

  if (spec.itemChance > 0 && random() < spec.itemChance) {
    var tierCap = spec.risk === "high" ? 3 : 2
    var affordable = []
    for (var r = 0; r < RECIPES.length; r++) if (RECIPES[r].tier <= tierCap) affordable.push(RECIPES[r].id)
    if (affordable.length) result.item = pick(random, affordable)
  }

  result.encounter = random() < ENCOUNTER_CHANCE
  return result
}

// ------------------------------------------------------------------- bosses

function bossEpithet(comm, spawnedAt) {
  return hash(String(comm) + "|" + String(spawnedAt)) % BOSS_EPITHETS
}

// A boss is a tiered enemy with a longer fight and a special every other turn.
// The extra health is modest on purpose: the tier multiplier already carries
// most of it, and a boss that takes twenty turns is a boss nobody finishes.
function bossStats(tier, hero) {
  var enemy = enemyFor("boss_daemon", tier, hero, true)
  enemy.hp = Math.round(enemy.hp * 1.45)
  enemy.hpMax = enemy.hp
  return enemy
}

// ---------------------------------------------------------------- new save

function newSave(now) {
  var at = num(now, nowSec())
  return {
    version: SCHEMA_VERSION,
    createdAt: at,
    hero: null,
    realm: { name: "", type: "caravan" },
    day: newDay(localDate(at)),
    streak: { count: 0, lastSealDate: "", missedDays: 0 },
    bosses: [],
    expedition: null,
    arena: null,
    achievements: [],
    sensors: {
      lastCoredumpCheck: at, lastGitCheck: 0, lastAgentTokens: 0,
      hasBattery: false, coredumpAvailable: true
    },
    stats: { totalXp: 0, fights: 0, bossKills: 0, expeditions: 0, forged: 0, sessionMinTotal: 0 }
  }
}

function newDay(dateString) {
  return {
    date: String(dateString),
    xpByDomain: { exploration: 0, art: 0, nature: 0, combat: 0, arcane: 0 },
    counters: newCounters(),
    quests: dailyQuests(dateString),
    // Which workspaces have already been paid for today. Numbers, and only
    // numbers — but they have to be on disk, because the alternative is an
    // in-memory set that a shell restart clears, which quietly pays for the
    // same workspace again every time the shell comes back.
    workspaceIds: [],
    sealEarned: false,
    notificationsSent: 0,
    guardianWeek: ""
  }
}

function newCounters() {
  return {
    workspaces: 0, apps: 0, windows: 0, windowAwards: 0, terminals: 0,
    musicMinutes: 0, musicTicks: 0, themes: 0, rests: 0, milestones: 0,
    sessionMin: 0, weather: 0, storms: 0, fair: 0, arenaWins: 0, bossFights: 0,
    expeditions: 0, forged: 0, commits: 0, arcaneTicks: 0, passiveXp: 0, strolls: 0
  }
}

function newHero(name, race, cls, now) {
  var at = num(now, nowSec())
  var safeRace = RACES[race] ? race : RACE_IDS[0]
  var safeClass = CLASSES[cls] ? cls : CLASS_IDS[0]
  var hero = {
    name: String(name || "").slice(0, 24) || "Hero",
    race: safeRace,
    cls: safeClass,
    level: 1, xp: 0, gold: 0,
    hp: 1, hpMax: 1, hpUpdatedAt: at,
    energy: ENERGY_MAX_DEFAULT, energyMax: ENERGY_MAX_DEFAULT, energyUpdatedAt: at,
    lastRestEnergyAt: 0,
    lastStrollAt: 0,
    faintedUntil: 0,
    attrs: attrsFor(safeRace, safeClass, 1),
    equipment: { weapon: null, armor: null, amulet: null },
    chest: [],
    materials: { iron: 0, wood: 0, feather: 0, crystal: 0, oil: 0, core: 0 },
    title: "novice"
  }
  hero.hpMax = hpMax(hero)
  hero.hp = hero.hpMax
  return hero
}

// node only; QML reads these as properties of the imported namespace.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    SCHEMA_VERSION: SCHEMA_VERSION, MAX_LEVEL: MAX_LEVEL, DOMAINS: DOMAINS, ATTRS: ATTRS,
    BASE_ATTR: BASE_ATTR, RACES: RACES, RACE_IDS: RACE_IDS, CLASSES: CLASSES, CLASS_IDS: CLASS_IDS,
    CLASS_LENS: CLASS_LENS, RANGER_LENS: RANGER_LENS, TERMINAL_CLASSES: TERMINAL_CLASSES, MATERIALS: MATERIALS, SLOTS: SLOTS,
    TITLES: TITLES, PASSIVE: PASSIVE, WINDOWS_PER_AWARD: WINDOWS_PER_AWARD,
    MUSIC_MINUTES_PER_TICK: MUSIC_MINUTES_PER_TICK,
    SESSION_MINUTES_PER_MILESTONE: SESSION_MINUTES_PER_MILESTONE,
    TOKENS_PER_ARCANE_TICK: TOKENS_PER_ARCANE_TICK,
    HP_REGEN_PER_HOUR: HP_REGEN_PER_HOUR, ENERGY_REGEN_SECONDS: ENERGY_REGEN_SECONDS,
    ENERGY_MAX_DEFAULT: ENERGY_MAX_DEFAULT, ENERGY_MAX_FORTRESS: ENERGY_MAX_FORTRESS,
    REST_ENERGY_COOLDOWN: REST_ENERGY_COOLDOWN, REST_SECONDS: REST_SECONDS,
    DEEP_REST_SECONDS: DEEP_REST_SECONDS, TAVERN_SECONDS: TAVERN_SECONDS, STROLL_SECONDS: STROLL_SECONDS,
    STROLL_FIND_COOLDOWN: STROLL_FIND_COOLDOWN,
    MAX_STROLL_FINDS_PER_DAY: MAX_STROLL_FINDS_PER_DAY,
    MAX_ACTIVE_BOSSES: MAX_ACTIVE_BOSSES, BOSS_LIFETIME_SECONDS: BOSS_LIFETIME_SECONDS,
    BOSS_MAX_TIER: BOSS_MAX_TIER, BOSS_GROWTH: BOSS_GROWTH, BOSS_EPITHETS: BOSS_EPITHETS,
    WANDERERS_PER_DAY: WANDERERS_PER_DAY, ENEMY_KINDS: ENEMY_KINDS, ENEMY_TIER: ENEMY_TIER,
    QUESTS_PER_DAY: QUESTS_PER_DAY, QUEST_XP: QUEST_XP, QUEST_GOLD: QUEST_GOLD,
    STREAK_BONUS_PER_DAY: STREAK_BONUS_PER_DAY, STREAK_BONUS_CAP: STREAK_BONUS_CAP,
    STREAK_GRACE_DAYS: STREAK_GRACE_DAYS,
    MAX_NOTIFICATIONS_PER_DAY: MAX_NOTIFICATIONS_PER_DAY,
    MAX_CHRONICLE_ENTRIES: MAX_CHRONICLE_ENTRIES, MAX_WORKSPACE_IDS: MAX_WORKSPACE_IDS, QUEST_POOL: QUEST_POOL,
    EXPEDITIONS: EXPEDITIONS, DESTINATIONS: DESTINATIONS, ENCOUNTER_CHANCE: ENCOUNTER_CHANCE,
    RECIPES: RECIPES, ACHIEVEMENTS: ACHIEVEMENTS,
    MATERIAL_PRICE: MATERIAL_PRICE, MERCHANT_OFFERS: MERCHANT_OFFERS,
    SELL_PER_TIER: SELL_PER_TIER, itemValue: itemValue, merchantStock: merchantStock,
    num: num, clamp: clamp, nowSec: nowSec, localDate: localDate, isWeekend: isWeekend,
    isoWeekKey: isoWeekKey, rng: rng, hash: hash, seedFromDate: seedFromDate,
    randInt: randInt, pick: pick, sample: sample, raceOf: raceOf, classOf: classOf,
    xpToNext: xpToNext, titleFor: titleFor, attrsFor: attrsFor, hpMax: hpMax,
    energyMax: energyMax, energyRegenSeconds: energyRegenSeconds,
    xpMultiplier: xpMultiplier, awardXp: awardXp, levelUps: levelUps, regen: regen,
    cloneHero: cloneHero, recipeById: recipeById, equipmentStats: equipmentStats,
    effectiveAttrs: effectiveAttrs, costFor: costFor, canCraft: canCraft,
    enemyFor: enemyFor, dodgeChance: dodgeChance, critChance: critChance,
    skillPower: skillPower, combatRound: combatRound, combatRewards: combatRewards,
    dailyQuests: dailyQuests, wanderers: wanderers, destinations: destinations,
    expeditionSpec: expeditionSpec, resolveExpedition: resolveExpedition,
    bossEpithet: bossEpithet, bossStats: bossStats,
    newSave: newSave, newDay: newDay, newCounters: newCounters, newHero: newHero
  }
}
