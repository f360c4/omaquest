.pragma library
.import "Rules.js" as Rules

// The only place game state changes.
//
// `apply(state, event, now)` returns `{ state, effects }`: a new state object
// and a list of things the service should do about it (notify, write a
// chronicle line, play an animation, save). It never mutates the state it is
// given and never touches Qt, a file or a clock it was not handed — which is
// what makes the whole rule set testable under node.
//
// Effects are data, not calls. The service decides whether a notification is
// allowed today; World only says one is warranted.
//
// `.import` rather than Qt.include: Qt.include was removed in Qt 6.

"use strict"

// ---------------------------------------------------------------- utilities

// A structural clone deep enough for the save, which is JSON by definition.
function clone(value) {
  if (value === null || typeof value !== "object") return value
  if (Array.isArray(value)) {
    var list = []
    for (var i = 0; i < value.length; i++) list.push(clone(value[i]))
    return list
  }
  var out = {}
  for (var key in value) out[key] = clone(value[key])
  return out
}

function effectChronicle(type, params, seed) {
  return { type: "chronicle", entry: { type: String(type), p: params || {}, seed: Rules.num(seed, 0) } }
}

function effectNotify(key, params) {
  return { type: "notify", key: String(key), params: params || {} }
}

function effectAnim(name, ms) {
  return { type: "anim", name: String(name), ms: Rules.num(ms, 1000) }
}

// ------------------------------------------------------------------- apply

function apply(state, event, now) {
  var at = Rules.num(now, Rules.nowSec())

  if (!state || typeof state !== "object") return { state: state, effects: [] }

  var type = event && event.type ? String(event.type) : ""
  var next = clone(state)

  switch (type) {
    case "create_hero": return createHero(next, event, at)
    case "mark_seen": return markSeen(next, event, at)
    case "set_realm_name": return setRealmName(next, event, at)
    case "day_rollover": return rollOverDay(next, event, at)
    case "session_tick": return sessionTick(next, event, at)
    case "coredumps": return coredumps(next, event, at)
    case "check_threats": return checkThreats(next, event, at)
    case "start_fight": return startFight(next, event, at)
    case "fight_action": return fightAction(next, event, at)
    case "flee": return flee(next, event, at)
    case "cancel_fight": return cancelFight(next, event, at)
    case "start_expedition": return startExpedition(next, event, at)
    case "resolve_expedition": return resolveExpedition(next, event, at)
    case "collect_expedition": return collectExpedition(next, event, at)
    case "craft": return craft(next, event, at)
    case "equip": return equip(next, event, at)
    case "unequip": return unequip(next, event, at)
    case "buy_material": return buyMaterial(next, event, at)
    case "buy_potion": return buyPotion(next, event, at)
    case "drink": return drink(next, event, at)
    case "sell_item": return sellItem(next, event, at)
    case "change_class": return changeClass(next, event, at)
    case "rebirth": return rebirth(next, event, at)
    case "stroll_found": return strollFound(next, event, at)
    default: break
  }

  // Everything else needs a hero to happen to.
  if (!next.hero) return { state: state, effects: [] }

  if (type === "workspace_discovered") {
    // Decided here rather than in the service, because "already seen today" is
    // a rule about the day and the day is what gets saved. The service used to
    // keep this in memory, so every shell restart paid for the workspace the
    // player happened to be on.
    var id = Math.floor(Rules.num(event.workspace))
    if (id <= 0) return { state: state, effects: [] }
    if (!Array.isArray(next.day.workspaceIds)) next.day.workspaceIds = []
    if (next.day.workspaceIds.indexOf(id) !== -1) return { state: state, effects: [] }
    if (next.day.workspaceIds.length >= Rules.MAX_WORKSPACE_IDS) return { state: state, effects: [] }
    next.day.workspaceIds.push(id)
    return passive(next, event, at)
  }

  if (Rules.PASSIVE[type]) return passive(next, event, at)

  return { state: state, effects: [] }
}

// -------------------------------------------------------------- lifecycle

function createHero(state, event, at) {
  var effects = []
  var realmType = event.realmType === "fortress" ? "fortress" : "caravan"

  state.realm = {
    name: String(event.realmName || "").slice(0, 32) || "realm",
    type: realmType
  }
  state.hero = Rules.newHero(event.name, event.race, event.cls, at)
  state.hero.energyMax = Rules.energyMax(state.hero, state.realm)
  state.hero.energy = state.hero.energyMax
  state.createdAt = at
  state.day = Rules.newDay(Rules.localDate(at))

  effects.push(effectChronicle("born", {
    name: state.hero.name, race: state.hero.race, cls: state.hero.cls, realm: state.realm.name
  }, Rules.hash(state.hero.name + at)))
  effects.push({ type: "save" })

  return { state: state, effects: effects }
}

function setRealmName(state, event, at) {
  if (!state.realm) state.realm = { name: "realm", type: "caravan" }
  var name = String(event.name || "").slice(0, 32)
  if (!name) return { state: state, effects: [] }
  state.realm.name = name
  return { state: state, effects: [{ type: "save" }] }
}

// The accent dot on the bar clears when the player has actually looked at the
// thing it was pointing at.
function markSeen(state, event, at) {
  var what = String(event.what || "")
  var touched = false

  if (what === "bosses" || what === "all") {
    for (var i = 0; i < (state.bosses || []).length; i++) {
      if (!state.bosses[i].seen) { state.bosses[i].seen = true; touched = true }
    }
  }
  if ((what === "expedition" || what === "all") && state.expedition
      && state.expedition.resolved && !state.expedition.seen) {
    state.expedition.seen = true
    touched = true
  }
  return { state: state, effects: touched ? [{ type: "save" }] : [] }
}

// ---------------------------------------------------------- the minute tick

// One minute of the player being at the machine. Deliberately silent: it pays
// no experience and writes no chronicle line, because sixty of those an hour
// would bury everything that actually happened. What it does is feed the
// counters that quests read, and tell the caller when enough minutes have
// piled up to be worth a milestone.
function sessionTick(state, event, at) {
  if (!state.hero) return { state: state, effects: [] }

  var minutes = Math.max(1, Math.min(120, Math.floor(Rules.num(event.minutes, 1))))
  state.day.counters.sessionMin = Rules.num(state.day.counters.sessionMin) + minutes

  var effects = advanceQuests(state, at)
  effects.push({ type: "save" })
  return { state: state, effects: effects }
}

// ------------------------------------------------------------- passive XP

// Every sensor event lands here. The counter always moves; the XP is paid only
// while the day's cap for that sensor has room, so a busy morning does not
// spend the whole day's progression and a quiet afternoon still counts toward
// a quest.
function passive(state, event, at) {
  var spec = Rules.PASSIVE[event.type]
  var effects = []
  var day = state.day
  var counters = day.counters

  var counterKey = spec.counter
  counters[counterKey] = Rules.num(counters[counterKey]) + 1

  // Some events carry a second counter that quests and achievements read.
  if (event.type === "windows_opened")
    counters.windows = Rules.num(counters.windows) + Rules.WINDOWS_PER_AWARD
  if (event.type === "music_tick")
    counters.musicMinutes = Rules.num(counters.musicMinutes) + Rules.MUSIC_MINUTES_PER_TICK
  if (event.type === "storm") counters.storms = Rules.num(counters.storms) + 1
  if (event.type === "fair_weather") counters.fair = Rules.num(counters.fair) + 1

  var paid = Rules.num(counters[counterKey]) <= spec.cap
  var gained = 0
  if (paid) {
    gained = Rules.awardXp(state.hero, spec.xp, spec.domain, state.streak ? state.streak.count : 0, false)
    day.xpByDomain[spec.domain] = Rules.num(day.xpByDomain[spec.domain]) + gained
    counters.passiveXp = Rules.num(counters.passiveXp) + gained
  }

  effects.push(effectChronicle(event.type, chronicleParams(state, event),
    Rules.hash(event.type + at + counters[counterKey])))

  if (gained > 0) effects = effects.concat(grantXp(state, gained, at))

  effects = effects.concat(passiveExtras(state, event, at))
  effects = effects.concat(dailyAchievements(state))
  effects = effects.concat(advanceQuests(state, at))

  effects.push({ type: "save" })
  return { state: state, effects: effects }
}

// What a few sensor events do beyond paying experience.
function passiveExtras(state, event, at) {
  var effects = []
  var hero = state.hero

  if (event.type === "rested") {
    // Resting returns a point of energy, at most once an hour so that a day of
    // stepping away from the desk cannot refill the bar over and over.
    var maxEnergy = Rules.energyMax(hero, state.realm)
    if (at - Rules.num(hero.lastRestEnergyAt) >= Rules.REST_ENERGY_COOLDOWN
        && Rules.num(hero.energy) < maxEnergy) {
      hero.energy = Rules.num(hero.energy) + 1
      hero.energyUpdatedAt = at
      hero.lastRestEnergyAt = at
    }

    // A long rest heals outright. Being away from the machine is the one thing
    // in this game that fixes everything, which is the joke and also the point.
    if (Rules.num(event.seconds) >= Rules.DEEP_REST_SECONDS) {
      hero.hpMax = Rules.hpMax(hero)
      hero.hp = hero.hpMax
      hero.hpUpdatedAt = at
      hero.faintedUntil = 0
    }
  }

  if (event.type === "theme_changed" && Rules.num(event.roll, Math.random()) < 0.30) {
    // A theme crystal, three times out of ten. The roll is passed in so a test
    // can pin it.
    hero.materials.crystal = Rules.num(hero.materials.crystal) + 1
  }

  if (event.type === "session_milestone") {
    hero.materials.oil = Rules.num(hero.materials.oil) + 1
  }

  return effects
}

// Only ids and numbers ever reach a chronicle entry. No window class, no app
// name, no repository — the chronicle is written from counts.
function chronicleParams(state, event) {
  var params = { name: state.hero.name, realm: state.realm ? state.realm.name : "" }
  if (event.type === "workspace_discovered") params.n = Rules.num(event.workspace)
  if (event.type === "session_milestone") params.hours = Math.round(Rules.num(state.day.counters.sessionMin) / 60)
  return params
}

// ------------------------------------------------------------------- XP

function grantXp(state, amount, at) {
  var effects = []
  var hero = state.hero
  var gained = Math.max(0, Math.round(Rules.num(amount)))
  if (gained <= 0) return effects

  state.stats.totalXp = Rules.num(state.stats.totalXp) + gained

  if (Rules.num(hero.level) >= Rules.MAX_LEVEL) return effects

  var result = Rules.levelUps(hero.level, Rules.num(hero.xp) + gained)
  hero.xp = result.xp

  if (result.gained > 0) {
    hero.level = result.level
    hero.attrs = Rules.attrsFor(hero.race, hero.cls, hero.level)
    hero.title = Rules.titleFor(hero.level)

    // Levelling up heals the difference rather than the whole bar: the hero
    // gets tougher, not rescued from a fight they were losing.
    var previousMax = Rules.num(hero.hpMax)
    hero.hpMax = Rules.hpMax(hero)
    hero.hp = Math.min(hero.hpMax, Rules.num(hero.hp) + Math.max(0, hero.hpMax - previousMax))

    effects.push(effectChronicle("level_up", {
      name: hero.name, level: hero.level, title: hero.title
    }, Rules.hash(hero.name + hero.level)))
    effects.push(effectNotify("level_up", { name: hero.name, level: hero.level, title: hero.title }))
    effects.push(effectAnim("cheer", 10000))
    effects.push({ type: "sound", name: "level_up.wav" })

    if (hero.level >= Rules.MAX_LEVEL) effects = effects.concat(grantAchievement(state, "myth"))
  }
  return effects
}

// ------------------------------------------------------------------ quests

// Quests read the day's counters rather than being incremented by each event,
// so a counter corrected by a migration or a rollover cannot leave a quest
// claiming progress the day never had.
function advanceQuests(state, at) {
  var effects = []
  var quests = state.day.quests || []
  var counters = state.day.counters
  var completedNow = 0

  for (var i = 0; i < quests.length; i++) {
    var quest = quests[i]
    if (quest.done) continue
    quest.progress = Math.min(Rules.num(quest.target), Rules.num(counters[quest.counter]))
    if (quest.progress >= Rules.num(quest.target)) {
      quest.done = true
      completedNow += 1
      state.hero.gold = Rules.num(state.hero.gold) + Rules.QUEST_GOLD
      effects.push(effectChronicle("quest_done",
        { name: state.hero.name, quest: quest.id }, Rules.hash(quest.id + state.day.date)))
      effects = effects.concat(grantXp(state,
        Rules.awardXp(state.hero, Rules.QUEST_XP, "nature", state.streak.count, false), at))
    }
  }

  if (completedNow > 0 && !state.day.sealEarned && allQuestsDone(quests)) {
    state.day.sealEarned = true
    state.streak.count = Rules.num(state.streak.count) + 1
    state.streak.lastSealDate = state.day.date
    state.streak.missedDays = 0
    effects.push(effectChronicle("seal_earned",
      { name: state.hero.name, streak: state.streak.count }, Rules.hash("seal" + state.day.date)))
    effects.push(effectNotify("quests_done", { name: state.hero.name, streak: state.streak.count }))
    if (state.streak.count >= 7) effects = effects.concat(grantAchievement(state, "constant"))
  }
  return effects
}

function allQuestsDone(quests) {
  if (!quests || !quests.length) return false
  for (var i = 0; i < quests.length; i++) if (!quests[i].done) return false
  return true
}

// ------------------------------------------------------------ achievements

function grantAchievement(state, id) {
  if (!state.achievements) state.achievements = []
  if (Rules.ACHIEVEMENTS.indexOf(id) === -1) return []
  if (state.achievements.indexOf(id) !== -1) return []
  state.achievements.push(id)
  return [effectChronicle("achievement",
    { name: state.hero ? state.hero.name : "", achievement: id }, Rules.hash("ach" + id))]
}

// The ones a day's counters can prove on their own. The rest are granted where
// they happen — in the arena, at the forge, on the road.
function dailyAchievements(state) {
  var counters = state.day.counters
  var effects = []
  if (Rules.num(counters.workspaces) >= 10) effects = effects.concat(grantAchievement(state, "explorer"))
  if (Rules.num(counters.musicMinutes) >= 120) effects = effects.concat(grantAchievement(state, "melomaniac"))
  if (Rules.num(counters.themes) >= 5) effects = effects.concat(grantAchievement(state, "chameleon"))
  if (Rules.num(counters.sessionMin) >= 480) effects = effects.concat(grantAchievement(state, "marathon"))

  var collected = 0
  for (var key in state.hero.materials) if (Rules.num(state.hero.materials[key]) > 0) collected += 1
  if (collected >= Rules.MATERIALS.length) effects = effects.concat(grantAchievement(state, "collector"))

  return effects
}


// ==================================================================== arena

// ---- Threats. Three kinds, and every one of them is optional: the arena is
//      somewhere to spend two minutes, never somewhere you have to go.
//
// A boss comes from a program on this machine crashing. A guardian turns up at
// the weekend, so that someone whose machine never crashes still has something
// to fight. Three wanderers are drawn from the date, so the list is never
// empty and is the same all day.

function bossLabel(boss) {
  return { comm: boss.comm, epithet: boss.epithet }
}

// A coredump becomes a boss. The same executable crashing again does not stack
// up a second boss — it makes the one that is there angrier, which is both
// better as a game and the only way a crash loop cannot flood the list.
function coredumps(state, event, at) {
  var effects = []
  if (!state.hero) return { state: state, effects: [] }

  var entries = Array.isArray(event.entries) ? event.entries : []
  // Bounded: a machine that crashed two hundred times between polls still
  // costs one pass over a short list.
  var considered = Math.min(entries.length, 32)

  for (var i = 0; i < considered; i++) {
    var comm = String(entries[i] && entries[i].comm ? entries[i].comm : "").slice(0, 32)
    if (!comm) continue

    var existing = null
    for (var b = 0; b < state.bosses.length; b++)
      if (state.bosses[b].kind === "crash" && state.bosses[b].comm === comm) existing = state.bosses[b]

    if (existing) {
      if (existing.tier >= Rules.BOSS_MAX_TIER) continue
      existing.tier += 1
      existing.hpMax = Math.round(existing.hpMax * (1 + Rules.BOSS_GROWTH))
      existing.hp = existing.hpMax
      existing.expiresAt = at + Rules.BOSS_LIFETIME_SECONDS
      existing.seen = false
      effects.push(effectChronicle("boss_grew", { boss: bossLabel(existing) },
        Rules.hash("grew" + comm + at)))
      continue
    }

    // Three at a time. A fourth pushes the oldest back into the dark rather
    // than growing the list.
    if (state.bosses.length >= Rules.MAX_ACTIVE_BOSSES) {
      var oldestIndex = 0
      for (var o = 1; o < state.bosses.length; o++)
        if (Rules.num(state.bosses[o].spawnedAt) < Rules.num(state.bosses[oldestIndex].spawnedAt)) oldestIndex = o
      var retreating = state.bosses.splice(oldestIndex, 1)[0]
      effects.push(effectChronicle("boss_retreated", { boss: bossLabel(retreating) },
        Rules.hash("retreat" + retreating.comm)))
    }

    var spawnedAt = Rules.num(entries[i].at, at)
    var boss = {
      id: "b" + Rules.hash(comm + spawnedAt).toString(36).slice(0, 8),
      kind: "crash",
      comm: comm,
      epithet: Rules.bossEpithet(comm, spawnedAt),
      tier: 3,
      hp: 1, hpMax: 1,
      spawnedAt: spawnedAt,
      expiresAt: spawnedAt + Rules.BOSS_LIFETIME_SECONDS,
      seen: false
    }
    var stats = Rules.bossStats(boss.tier, state.hero)
    boss.hp = stats.hp
    boss.hpMax = stats.hpMax

    state.bosses.push(boss)
    effects.push(effectChronicle("boss_spawned", { boss: bossLabel(boss) },
      Rules.hash("spawn" + comm + spawnedAt)))
    effects.push(effectNotify("boss_spawned", { boss: bossLabel(boss) }))
  }

  if (effects.length) effects.push({ type: "save" })
  return { state: state, effects: effects }
}

// Run on every tick: retire what has run out of time, and keep the weekend
// guardian in step with the calendar.
function checkThreats(state, event, at) {
  var effects = []
  if (!state.hero) return { state: state, effects: [] }

  var kept = []
  for (var i = 0; i < state.bosses.length; i++) {
    var boss = state.bosses[i]
    if (boss.kind === "crash" && Rules.num(boss.expiresAt) <= at) {
      effects.push(effectChronicle("boss_retreated", { boss: bossLabel(boss) },
        Rules.hash("expire" + boss.comm)))
      continue
    }
    kept.push(boss)
  }
  state.bosses = kept

  var today = String(event.date || Rules.localDate(at))
  var week = Rules.isoWeekKey(today)
  var guardian = null
  for (var g = 0; g < state.bosses.length; g++)
    if (state.bosses[g].kind === "guardian") guardian = state.bosses[g]

  if (Rules.isWeekend(today)) {
    if (!guardian || state.day.guardianWeek !== week) {
      if (guardian) state.bosses.splice(state.bosses.indexOf(guardian), 1)
      var tier = Rules.clamp(2 + Math.floor(Rules.num(state.hero.level) / 15), 2, 3)
      var stats = Rules.bossStats(tier, state.hero)
      state.bosses.push({
        id: "guardian-" + week,
        kind: "guardian",
        comm: "",
        epithet: Rules.hash(week) % Rules.BOSS_EPITHETS,
        tier: tier,
        hp: stats.hp, hpMax: stats.hpMax,
        spawnedAt: at,
        // Retired by the Monday check rather than by a timestamp, so a machine
        // left off all weekend still finds it gone on Monday.
        expiresAt: at + Rules.BOSS_LIFETIME_SECONDS,
        seen: false
      })
      state.day.guardianWeek = week
      effects.push(effectChronicle("guardian_arrived", {}, Rules.hash("guardian" + week)))
      effects.push(effectNotify("boss_spawned", { boss: { comm: "", epithet: 0 } }))
    }
  } else if (guardian) {
    state.bosses.splice(state.bosses.indexOf(guardian), 1)
    effects.push(effectChronicle("guardian_left", {}, Rules.hash("guardian_gone" + week)))
  }

  if (effects.length) effects.push({ type: "save" })
  return { state: state, effects: effects }
}

// ---- A fight.

function threatById(state, kind, id) {
  if (kind === "wanderer") {
    var list = Rules.wanderers(state.day.date, state.hero.level)
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }
  for (var b = 0; b < state.bosses.length; b++) if (state.bosses[b].id === id) return state.bosses[b]
  return null
}

function startFight(state, event, at) {
  if (!state.hero || state.arena) return { state: state, effects: [] }
  if (state.expedition && !state.expedition.resolved) return { state: state, effects: [] }

  var hero = Rules.regen(state.hero, state.realm, at)
  if (Rules.num(hero.energy) < 1) return { state: state, effects: [] }
  if (Rules.num(hero.faintedUntil) > at) return { state: state, effects: [] }

  var kind = String(event.kind || "wanderer")
  var threat = threatById(state, kind, String(event.id || ""))
  if (!threat) return { state: state, effects: [] }

  hero.energy = Rules.num(hero.energy) - 1
  hero.energyUpdatedAt = at
  state.hero = hero

  var enemy
  if (kind === "wanderer") {
    enemy = Rules.enemyFor(threat.kind, threat.tier, hero)
  } else {
    enemy = Rules.bossStats(threat.tier, hero)
    enemy.kind = threat.kind === "guardian" ? "boss_guardian" : "boss_daemon"
    // A boss keeps the health it has left between fights, so a near miss is
    // progress rather than a reset.
    enemy.hp = Math.max(1, Math.min(enemy.hpMax, Rules.num(threat.hp, enemy.hpMax)))
  }

  state.arena = {
    kind: kind,
    id: String(event.id || ""),
    enemy: enemy,
    enemyHp: enemy.hp,
    heroHp: Rules.num(hero.hp),
    turn: 0,
    cooldown: 0,
    enemySkipTurns: 0,
    dodgeNext: false,
    critNext: false,
    log: [],
    outcome: "ongoing"
  }

  state.stats.fights = Rules.num(state.stats.fights) + 1
  if (kind !== "wanderer") state.day.counters.bossFights = Rules.num(state.day.counters.bossFights) + 1

  return { state: state, effects: [{ type: "anim", name: "fight", ms: 1000 }, { type: "save" }] }
}

// The log holds the last four exchanges and no more: it is a panel element,
// not a history, and an unbounded one would grow for as long as a fight lasts.
var MAX_LOG_LINES = 4

function pushLog(arena, lines) {
  for (var i = 0; i < lines.length; i++) arena.log.push(lines[i])
  if (arena.log.length > MAX_LOG_LINES) arena.log = arena.log.slice(arena.log.length - MAX_LOG_LINES)
}

function fightAction(state, event, at) {
  var arena = state.arena
  if (!arena || arena.outcome !== "ongoing") return { state: state, effects: [] }

  var action = String(event.action || "attack")
  if (action !== "attack" && action !== "skill" && action !== "defend") action = "attack"
  if (action === "skill" && Rules.num(arena.cooldown) > 0) action = "attack"

  var random = typeof event.random === "function" ? event.random : Math.random
  var before = Rules.num(arena.heroHp)
  var step = Rules.combatRound(state.hero, arena, action, random)

  arena.heroHp = step.heroHp
  arena.enemyHp = step.enemyHp
  arena.turn = step.turn
  arena.cooldown = step.cooldown
  arena.enemySkipTurns = step.enemySkipTurns
  arena.dodgeNext = step.dodgeNext
  arena.critNext = step.critNext
  arena.outcome = step.outcome
  pushLog(arena, step.log)

  var effects = [{ type: "save" }]

  // The hero's health follows the fight, so closing the panel mid-fight and
  // reopening it shows the same wounds.
  state.hero.hp = Rules.clamp(arena.heroHp, 0, Rules.hpMax(state.hero))
  state.hero.hpUpdatedAt = at

  if (step.outcome === "won") effects = effects.concat(winFight(state, at, random))
  else if (step.outcome === "lost") effects = effects.concat(loseFight(state, at))
  else if (step.heroHp < before) {
    // A flinch, on the blow that landed — not a state that lasts as long as
    // the health bar is low. Half a second and done.
    effects.push({ type: "anim", name: "hurt", ms: 500 })
    effects.push({ type: "sound", name: "hurt.wav" })
  }

  for (var l = 0; l < step.log.length; l++) {
    if (step.log[l].key === "hit_crit") effects.push({ type: "sound", name: "crit.wav" })
    else if (step.log[l].key === "hit") effects.push({ type: "sound", name: "hit.wav" })
  }

  return { state: state, effects: effects }
}

function winFight(state, at, random) {
  var arena = state.arena
  var effects = []
  var isBoss = arena.kind !== "wanderer"

  var loot = Rules.combatRewards(state.hero, arena.enemy, state.streak.count, random)
  state.hero.gold = Rules.num(state.hero.gold) + loot.gold
  for (var material in loot.materials)
    state.hero.materials[material] = Rules.num(state.hero.materials[material]) + loot.materials[material]
  if (loot.item && state.hero.chest.length < 60) state.hero.chest.push(loot.item)

  state.day.counters.arenaWins = Rules.num(state.day.counters.arenaWins) + 1

  if (isBoss) {
    state.stats.bossKills = Rules.num(state.stats.bossKills) + 1
    var defeated = null
    for (var b = 0; b < state.bosses.length; b++) if (state.bosses[b].id === arena.id) defeated = state.bosses[b]
    if (defeated) {
      state.bosses.splice(state.bosses.indexOf(defeated), 1)
      effects.push(effectChronicle("boss_defeated", { boss: bossLabel(defeated) },
        Rules.hash("kill" + defeated.id + at)))
      effects = effects.concat(grantAchievement(state,
        defeated.kind === "guardian" ? "guardian_slayer" : "survivor"))
    }
  } else {
    effects.push(effectChronicle("arena_won", { enemy: arena.enemy.kind }, Rules.hash("won" + at)))
  }

  effects = effects.concat(grantAchievement(state, "first_blood"))
  effects = effects.concat(grantXp(state, loot.xp, at))
  effects = effects.concat(advanceQuests(state, at))

  var collected = 0
  for (var key in state.hero.materials) if (Rules.num(state.hero.materials[key]) > 0) collected += 1
  if (collected >= Rules.MATERIALS.length) effects = effects.concat(grantAchievement(state, "collector"))

  effects.push({ type: "anim", name: "cheer", ms: 4000 })
  effects.push({ type: "sound", name: "victory.wav" })
  effects.push({ type: "save" })
  return effects
}

// Losing costs progress, never achievement.
//
// A quarter of the experience you had built toward the level you are on, and
// nothing else: no gold, no material, no item, and never a level. You cannot
// be knocked back to a title you already earned, and `stats.totalXp` — which
// the feats read — does not move. What you lose is an afternoon, which is
// enough for the arena to mean something and little enough that nobody stops
// opening it.
var DEFEAT_XP_LOSS = 0.25

function loseFight(state, at) {
  state.hero.hp = 0
  state.hero.hpUpdatedAt = at
  state.hero.faintedUntil = at + Rules.TAVERN_SECONDS

  var lost = Math.floor(Rules.num(state.hero.xp) * DEFEAT_XP_LOSS)
  state.hero.xp = Math.max(0, Rules.num(state.hero.xp) - lost)

  var effects = [effectChronicle(lost > 0 ? "arena_lost_xp" : "arena_lost",
    { xp: lost }, Rules.hash("lost" + at))]
  effects.push({ type: "sound", name: "defeat.wav" })
  effects.push({ type: "save" })
  return effects
}

// Leaving a fight. The energy is already spent — that is what makes fleeing a
// decision rather than a free look at the enemy's health.
function flee(state, event, at) {
  if (!state.arena) return { state: state, effects: [] }
  state.arena = null
  return { state: state, effects: [effectChronicle("arena_fled", {}, Rules.hash("fled" + at)), { type: "save" }] }
}

// A fight does not survive the shell restarting: there is no way to tell
// whether the player walked away or the machine did, so the energy goes back
// and the fight is dropped.
//
// `interrupted` exists because the load path has already dropped the fight by
// the time this runs — `Migrations.sanitize` clears `arena` on principle, so
// that a half-written one cannot reach a view — and dropping it is exactly
// what owes the player their energy back. Without the flag this returned
// early and quietly kept the point.
function cancelFight(state, event, at) {
  if (!state.arena && event.interrupted !== true) return { state: state, effects: [] }
  state.arena = null
  var maxEnergy = Rules.energyMax(state.hero, state.realm)
  state.hero.energy = Math.min(maxEnergy, Rules.num(state.hero.energy) + 1)
  state.hero.energyUpdatedAt = at
  return { state: state, effects: [{ type: "save" }] }
}


// =============================================================== expedition

// An expedition is the one part of the game that runs while nobody is
// watching, and the only one that has to survive the machine being off. It
// keeps an end time and a seed, and nothing else: the result is computed from
// the seed whenever someone gets round to collecting it, so a laptop closed
// mid-journey and opened a week later finds exactly the result it would have
// found on time.
function startExpedition(state, event, at) {
  if (!state.hero || state.expedition || state.arena) return { state: state, effects: [] }

  var hero = Rules.regen(state.hero, state.realm, at)
  if (Rules.num(hero.energy) < 1) return { state: state, effects: [] }
  if (Rules.num(hero.faintedUntil) > at) return { state: state, effects: [] }

  var destinations = Rules.destinations(state.day.date, hero)
  var chosen = null
  for (var i = 0; i < destinations.length; i++)
    if (destinations[i].id === String(event.destId || "")) chosen = destinations[i]
  if (!chosen) return { state: state, effects: [] }

  hero.energy = Rules.num(hero.energy) - 1
  hero.energyUpdatedAt = at
  state.hero = hero

  var endsAt = at + chosen.minutes * 60
  state.expedition = {
    destId: chosen.id,
    place: chosen.place,
    startedAt: at,
    endsAt: endsAt,
    // Seeded from when it ends, so the result is fixed the moment it leaves
    // and cannot be re-rolled by collecting it at a different time.
    seed: Rules.hash(chosen.id + "|" + chosen.place + "|" + endsAt),
    resolved: false,
    seen: false,
    result: null
  }

  return {
    state: state,
    effects: [
      effectChronicle("expedition_started", { name: hero.name, place: chosen.place },
        Rules.hash("depart" + endsAt)),
      { type: "save" }
    ]
  }
}

// Called by the tick and on load. Idempotent: resolving an already-resolved
// expedition does nothing, so a boot that races the tick cannot pay twice.
function resolveExpedition(state, event, at) {
  var expedition = state.expedition
  if (!expedition || expedition.resolved) return { state: state, effects: [] }
  if (Rules.num(expedition.endsAt) > at) return { state: state, effects: [] }

  var result = Rules.resolveExpedition(expedition, state.hero, state.streak.count)
  expedition.resolved = true
  expedition.seen = false
  expedition.result = result

  return {
    state: state,
    effects: [
      effectChronicle("expedition_returned",
        { name: state.hero.name, place: expedition.place }, Rules.hash("return" + expedition.endsAt)),
      effectNotify("expedition_done", { name: state.hero.name, place: expedition.place }),
      { type: "save" }
    ]
  }
}

// Collecting is what actually hands the loot over, so that coming back to a
// finished expedition is something the player does rather than something that
// happened to them while they were away.
function collectExpedition(state, event, at) {
  var expedition = state.expedition
  if (!expedition || !expedition.resolved || !expedition.result) return { state: state, effects: [] }

  var result = expedition.result
  state.hero.gold = Rules.num(state.hero.gold) + Rules.num(result.gold)
  for (var material in result.materials)
    state.hero.materials[material] = Rules.num(state.hero.materials[material]) + Rules.num(result.materials[material])
  if (result.item && state.hero.chest.length < 60) state.hero.chest.push(result.item)

  state.day.counters.expeditions = Rules.num(state.day.counters.expeditions) + 1
  state.stats.expeditions = Rules.num(state.stats.expeditions) + 1
  state.expedition = null

  var effects = grantXp(state, Rules.num(result.xp), at)
  effects = effects.concat(advanceQuests(state, at))
  if (Rules.num(state.stats.expeditions) >= 10)
    effects = effects.concat(grantAchievement(state, "traveller"))
  effects.push({ type: "save" })
  return { state: state, effects: effects }
}

// ==================================================================== forge

function craft(state, event, at) {
  if (!state.hero) return { state: state, effects: [] }

  var recipe = Rules.recipeById(String(event.recipe || ""))
  if (!recipe || !Rules.canCraft(state.hero, recipe)) return { state: state, effects: [] }

  var cost = Rules.costFor(state.hero, recipe)
  for (var key in cost) state.hero.materials[key] = Rules.num(state.hero.materials[key]) - cost[key]

  // Straight into the chest, not onto the hero: equipping is a separate
  // decision, and forging a worse item should never take a better one off.
  if (state.hero.chest.length < 60) state.hero.chest.push(recipe.id)

  state.day.counters.forged = Rules.num(state.day.counters.forged) + 1
  state.stats.forged = Rules.num(state.stats.forged) + 1

  var effects = [effectChronicle("forged", { name: state.hero.name, item: recipe.id },
    Rules.hash("forge" + recipe.id + at))]
  effects = effects.concat(advanceQuests(state, at))
  if (Rules.num(state.stats.forged) >= 5) effects = effects.concat(grantAchievement(state, "smith"))
  effects.push({ type: "save" })
  return { state: state, effects: effects }
}

// Equipping swaps: whatever was in the slot goes back to the chest. Nothing is
// ever destroyed, so trying a different sword costs nothing.
function equip(state, event, at) {
  if (!state.hero) return { state: state, effects: [] }

  var id = String(event.item || "")
  var recipe = Rules.recipeById(id)
  if (!recipe) return { state: state, effects: [] }

  var index = state.hero.chest.indexOf(id)
  if (index === -1) return { state: state, effects: [] }
  state.hero.chest.splice(index, 1)

  var previous = state.hero.equipment[recipe.slot]
  state.hero.equipment[recipe.slot] = id
  if (previous) state.hero.chest.push(previous)

  // Armour changes the maximum, so the current value has to be brought back
  // inside it — upward as well as downward, so a better breastplate is felt
  // straight away rather than on the next heal.
  var previousMax = Rules.num(state.hero.hpMax)
  state.hero.hpMax = Rules.hpMax(state.hero)
  state.hero.hp = Rules.clamp(
    Rules.num(state.hero.hp) + Math.max(0, state.hero.hpMax - previousMax), 0, state.hero.hpMax)
  state.hero.hpUpdatedAt = at

  return { state: state, effects: [{ type: "save" }] }
}


// =================================================================== stroll

// Whether the hero can go out at all. Only the three things that mean they are
// genuinely somewhere else: mid-fight, away on an expedition, or face down in
// the tavern. Everything else is yes, as often as asked — a walk is something
// you watch because you felt like it, and a button that says "not now" to that
// is a button that annoys.
function canStroll(state, at) {
  if (!state || !state.hero) return false
  if (state.arena) return false
  if (state.expedition && !state.expedition.resolved) return false
  if (Rules.num(state.hero.faintedUntil) > at) return false
  return true
}

// Whether this particular walk will turn anything up. Separate from whether it
// can happen at all, because a free walk that always pays a material is a
// material printer. The tenth walk of the morning still happens; it just comes
// back empty, which is what a tenth walk should do.
function strollPays(state, at) {
  if (!canStroll(state, at)) return false
  if (Rules.num(state.day.counters.strolls) >= Rules.MAX_STROLL_FINDS_PER_DAY) return false
  return at - Rules.num(state.hero.lastStrollAt) >= Rules.STROLL_FIND_COOLDOWN
}

// The walk itself lives entirely in the service and is never written down: if
// the shell goes away mid-stroll, nothing happened, which costs the player
// nothing and cannot be turned into a way of farming one. Only arriving is an
// event, and only arriving is paid for.
function strollFound(state, event, at) {
  if (!state.hero) return { state: state, effects: [] }

  // The walk happened either way; this only decides whether it was worth
  // anything. A walk that pays nothing writes no chronicle line either —
  // "went out, came back" is not news.
  if (!strollPays(state, at)) return { state: state, effects: [] }

  state.hero.lastStrollAt = at
  state.day.counters.strolls = Rules.num(state.day.counters.strolls) + 1

  var random = Rules.rng(Rules.hash("stroll" + at))
  var material = Rules.pick(random, ["iron", "wood", "feather"])
  var gold = Rules.randInt(random, 3, 9)

  state.hero.materials[material] = Rules.num(state.hero.materials[material]) + 1
  state.hero.gold = Rules.num(state.hero.gold) + gold

  // `material`, not `item`: Chronicle.expand translates the two through
  // different dictionary namespaces, and iron is not a recipe.
  var effects = [effectChronicle("strolled",
    { name: state.hero.name, material: material, gold: gold }, Rules.hash("stroll" + at))]
  effects.push({ type: "sound", name: "found.wav" })
  effects = effects.concat(advanceQuests(state, at))
  effects.push({ type: "save" })
  return { state: state, effects: effects, found: { material: material, gold: gold } }
}

// Taking something off. A slot you can put things into but not take things
// out of is a one-way door, and armour that raises the maximum has to be
// allowed to lower it again.
function unequip(state, event, at) {
  if (!state.hero) return { state: state, effects: [] }

  var slot = String(event.slot || "")
  if (Rules.SLOTS.indexOf(slot) === -1) return { state: state, effects: [] }

  var worn = state.hero.equipment[slot]
  if (!worn) return { state: state, effects: [] }

  state.hero.equipment[slot] = null
  if (state.hero.chest.length < 60) state.hero.chest.push(worn)

  state.hero.hpMax = Rules.hpMax(state.hero)
  state.hero.hp = Rules.clamp(Rules.num(state.hero.hp), 1, state.hero.hpMax)
  state.hero.hpUpdatedAt = at

  return { state: state, effects: [{ type: "save" }] }
}

// ================================================================ merchant

function buyMaterial(state, event, at) {
  if (!state.hero) return { state: state, effects: [] }

  var stock = Rules.merchantStock(state.day.date)
  var offer = null
  for (var i = 0; i < stock.length; i++) if (stock[i].id === String(event.offer || "")) offer = stock[i]
  if (!offer) return { state: state, effects: [] }
  if (Rules.num(state.hero.gold) < offer.gold) return { state: state, effects: [] }

  state.hero.gold = Rules.num(state.hero.gold) - offer.gold
  state.hero.materials[offer.material] = Rules.num(state.hero.materials[offer.material]) + offer.count

  var effects = [effectChronicle("bought",
    { name: state.hero.name, material: offer.material, gold: offer.gold },
    Rules.hash("buy" + offer.id + at))]
  effects = effects.concat(dailyAchievements(state))
  effects.push({ type: "save" })
  return { state: state, effects: effects }
}

function buyPotion(state, event, at) {
  if (!state.hero) return { state: state, effects: [] }

  var id = String(event.potion || "")
  var spec = Rules.potionSpec(id)
  if (!spec) return { state: state, effects: [] }
  if (Rules.num(state.hero.gold) < spec.price) return { state: state, effects: [] }
  if (Rules.num(state.hero.potions[id]) >= Rules.MAX_POTIONS) return { state: state, effects: [] }

  state.hero.gold = Rules.num(state.hero.gold) - spec.price
  state.hero.potions[id] = Rules.num(state.hero.potions[id]) + 1

  return { state: state, effects: [{ type: "save" }] }
}

// Drinking works mid-fight, which is the only reason to carry one. The arena's
// health and the hero's are the same number while a fight is on, so both move
// together or the next round undoes it.
function drink(state, event, at) {
  if (!state.hero) return { state: state, effects: [] }

  var id = String(event.potion || "")
  var spec = Rules.potionSpec(id)
  if (!spec) return { state: state, effects: [] }
  if (Rules.num(state.hero.potions[id]) <= 0) return { state: state, effects: [] }

  var hero = Rules.regen(state.hero, state.realm, at)
  var maxHp = Rules.hpMax(hero)
  var maxEnergy = Rules.energyMax(hero, state.realm)

  var wasFainted = Rules.num(hero.faintedUntil) > at
  var healed = 0
  var restored = 0

  if (spec.heals > 0) {
    if (wasFainted && spec.wakes) {
      hero.faintedUntil = 0
      hero.hp = 0
    } else if (Rules.num(hero.hp) >= maxHp) {
      // Nothing to heal and nothing to wake from: keep the potion.
      return { state: state, effects: [] }
    }
    var before = Rules.num(hero.hp)
    hero.hp = Math.min(maxHp, before + Math.round(maxHp * spec.heals))
    hero.hpUpdatedAt = at
    healed = hero.hp - before
  }

  if (spec.energy > 0) {
    if (Rules.num(hero.energy) >= maxEnergy) return { state: state, effects: [] }
    hero.energy = Math.min(maxEnergy, Rules.num(hero.energy) + spec.energy)
    hero.energyUpdatedAt = at
    restored = spec.energy
  }

  hero.potions[id] = Rules.num(hero.potions[id]) - 1
  state.hero = hero

  // A fight in progress reads its own copy of the hero's health, so it has to
  // be told, or the next exchange overwrites what was just drunk.
  if (state.arena) state.arena.heroHp = Rules.num(hero.hp)

  return {
    state: state,
    effects: [
      effectChronicle("drank", { name: hero.name, potion: id, heal: healed, energy: restored },
        Rules.hash("drink" + id + at)),
      { type: "save" }
    ]
  }
}

// Only what is in the chest. What the hero is wearing has to be taken off
// first, which is one click and stops a misclick selling the sword you are
// holding.
function sellItem(state, event, at) {
  if (!state.hero) return { state: state, effects: [] }

  var id = String(event.item || "")
  var recipe = Rules.recipeById(id)
  if (!recipe) return { state: state, effects: [] }

  var index = state.hero.chest.indexOf(id)
  if (index === -1) return { state: state, effects: [] }
  state.hero.chest.splice(index, 1)

  var gold = Rules.itemValue(recipe)
  state.hero.gold = Rules.num(state.hero.gold) + gold

  return {
    state: state,
    effects: [
      effectChronicle("sold", { name: state.hero.name, item: id, gold: gold },
        Rules.hash("sell" + id + at)),
      { type: "save" }
    ]
  }
}

// ================================================================== changes

// Changing calling costs gold and keeps the level: the class is a lens on
// where experience comes from, and nobody should have to start again because
// they stopped writing code and started listening to music.
var CLASS_CHANGE_GOLD = 100

function changeClass(state, event, at) {
  if (!state.hero) return { state: state, effects: [] }

  var next = String(event.cls || "")
  if (!Rules.CLASSES[next] || next === state.hero.cls) return { state: state, effects: [] }
  if (Rules.num(state.hero.gold) < CLASS_CHANGE_GOLD) return { state: state, effects: [] }

  state.hero.gold = Rules.num(state.hero.gold) - CLASS_CHANGE_GOLD
  state.hero.cls = next
  // Attributes are derived from race, class and level, so they re-derive here
  // rather than being migrated point by point.
  state.hero.attrs = Rules.attrsFor(state.hero.race, next, state.hero.level)

  var previousMax = Rules.num(state.hero.hpMax)
  state.hero.hpMax = Rules.hpMax(state.hero)
  state.hero.hp = Rules.clamp(
    Rules.num(state.hero.hp) + Math.max(0, state.hero.hpMax - previousMax), 1, state.hero.hpMax)
  state.hero.hpUpdatedAt = at

  return {
    state: state,
    effects: [
      effectChronicle("class_changed", { name: state.hero.name, cls: next },
        Rules.hash("class" + next + at)),
      { type: "save" }
    ]
  }
}

// Starting over. Level, experience and equipment go; the chronicle, the
// materials and the feats stay, because those are the record of having been
// here and nothing should be able to take that back.
function rebirth(state, event, at) {
  if (!state.hero) return { state: state, effects: [] }

  var race = Rules.RACES[event.race] ? String(event.race) : state.hero.race
  var cls = Rules.CLASSES[event.cls] ? String(event.cls) : state.hero.cls
  var name = String(event.name || state.hero.name).slice(0, 24) || state.hero.name

  var kept = {
    materials: state.hero.materials,
    gold: Rules.num(state.hero.gold),
    chest: []
  }

  state.hero = Rules.newHero(name, race, cls, at)
  state.hero.materials = kept.materials
  state.hero.gold = kept.gold
  state.hero.chest = kept.chest
  state.hero.energyMax = Rules.energyMax(state.hero, state.realm)
  state.hero.energy = state.hero.energyMax

  // A fight or a journey belonging to the previous life does not carry over.
  state.arena = null
  state.expedition = null

  return {
    state: state,
    effects: [
      effectChronicle("reborn", { name: name, race: race, cls: cls, realm: state.realm.name },
        Rules.hash("reborn" + at)),
      { type: "save" }
    ]
  }
}

// --------------------------------------------------------------- day change

// Called by the service's tick when the local date has moved. Closing a day is
// the only place the streak can be lost, and it is lost gently: two missed
// days are forgiven, the third resets the count.
function rollOverDay(state, event, at) {
  var effects = []
  var nextDate = String(event.date || Rules.localDate(at))
  if (!state.day || state.day.date === nextDate) return { state: state, effects: [] }

  if (!state.day.sealEarned) {
    state.streak.missedDays = Rules.num(state.streak.missedDays) + 1
    if (state.streak.missedDays >= Rules.STREAK_GRACE_DAYS && Rules.num(state.streak.count) > 0) {
      state.streak.count = 0
      effects.push(effectChronicle("streak_lost",
        { name: state.hero ? state.hero.name : "" }, Rules.hash("streak" + nextDate)))
    }
  }

  state.stats.sessionMinTotal = Rules.num(state.stats.sessionMinTotal) + Rules.num(state.day.counters.sessionMin)
  state.day = Rules.newDay(nextDate)

  effects.push({ type: "save" })
  return { state: state, effects: effects }
}

// node only; QML reads these as properties of the imported namespace.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    apply: apply, clone: clone, grantXp: grantXp, advanceQuests: advanceQuests,
    grantAchievement: grantAchievement, dailyAchievements: dailyAchievements,
    rollOverDay: rollOverDay, allQuestsDone: allQuestsDone,
    DEFEAT_XP_LOSS: DEFEAT_XP_LOSS,
    sessionTick: sessionTick, passiveExtras: passiveExtras,
    coredumps: coredumps, checkThreats: checkThreats, startFight: startFight,
    fightAction: fightAction, flee: flee, cancelFight: cancelFight,
    threatById: threatById, MAX_LOG_LINES: MAX_LOG_LINES,
    startExpedition: startExpedition, resolveExpedition: resolveExpedition,
    collectExpedition: collectExpedition, craft: craft, equip: equip, unequip: unequip,
    changeClass: changeClass, rebirth: rebirth, CLASS_CHANGE_GOLD: CLASS_CHANGE_GOLD,
    canStroll: canStroll, strollPays: strollPays, strollFound: strollFound,
    buyMaterial: buyMaterial, buyPotion: buyPotion, drink: drink, sellItem: sellItem
  }
}
