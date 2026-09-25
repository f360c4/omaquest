"use strict"

// Unit tests for game/*.js under plain node. No Qt, no shell, no QML.
//
// The game files are QML JavaScript libraries: they open with `.pragma
// library` and pull each other in with `.import "X.js" as X`, neither of which
// node can parse. `load()` below strips those two directives and evaluates the
// rest with the named imports supplied as arguments, which is exactly what the
// QML engine does — so the code under test is the shipped code, byte for byte
// apart from its two header lines.

const fs = require("fs")
const path = require("path")

const GAME_DIR = path.join(__dirname, "..", "game")

const loaded = new Map()

function load(name) {
  if (loaded.has(name)) return loaded.get(name)

  const source = fs.readFileSync(path.join(GAME_DIR, name), "utf8")
  const importNames = []
  const body = source
    .split("\n")
    .map((line) => {
      const directive = line.match(/^\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/)
      if (directive) {
        importNames.push([directive[1], directive[2]])
        return ""
      }
      return /^\.pragma\s+library\s*$/.test(line) ? "" : line
    })
    .join("\n")

  const module = { exports: {} }
  const args = importNames.map(([file]) => load(file))
  // eslint-disable-next-line no-new-func
  const factory = new Function(...importNames.map(([, alias]) => alias), "module", body)
  factory(...args, module)

  loaded.set(name, module.exports)
  return module.exports
}

const Rules = load("Rules.js")
const World = load("World.js")
const Migrations = load("Migrations.js")
const Chronicle = load("Chronicle.js")

// ------------------------------------------------------------------ harness

let passed = 0
const failures = []

function test(name, fn) {
  try {
    fn()
    passed += 1
  } catch (error) {
    failures.push({ name, error })
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message || "assertion failed")
}

function assertEqual(actual, expected, message) {
  if (actual !== expected)
    throw new Error(`${message || "not equal"}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
}

function assertBetween(actual, low, high, message) {
  if (!(actual >= low && actual <= high))
    throw new Error(`${message || "out of range"}: ${actual} not in [${low}, ${high}]`)
}

// ---------------------------------------------------------------- fixtures

const T0 = 1758580000

function heroOf(race = "human", cls = "warrior", level = 1) {
  const hero = Rules.newHero("Tester", race, cls, T0)
  if (level > 1) {
    hero.level = level
    hero.attrs = Rules.attrsFor(race, cls, level)
    hero.hpMax = Rules.hpMax(hero)
    hero.hp = hero.hpMax
  }
  return hero
}

function freshState(race = "human", cls = "warrior") {
  const created = World.apply(Rules.newSave(T0), {
    type: "create_hero", name: "Tester", race, cls, realmName: "testrealm", realmType: "caravan"
  }, T0)
  return created.state
}

// ------------------------------------------------------------ progression

test("xpToNext is strictly increasing up to the cap", () => {
  let previous = 0
  for (let level = 1; level < Rules.MAX_LEVEL; level++) {
    const needed = Rules.xpToNext(level)
    assert(needed > previous, `level ${level}: ${needed} <= ${previous}`)
    previous = needed
  }
  assertEqual(Rules.xpToNext(Rules.MAX_LEVEL), Infinity, "the cap needs no next level")
})

test("the documented total XP per level lands where the design says", () => {
  const totals = {}
  let total = 0
  for (let level = 1; level < Rules.MAX_LEVEL; level++) {
    total += Rules.xpToNext(level)
    totals[level + 1] = total
  }
  // 02-game-design.md: level 5 ~985, level 10 ~5.1k, level 20 ~25k, level 30 ~62k.
  assertBetween(totals[5], 900, 1100, "level 5")
  assertBetween(totals[10], 4600, 5600, "level 10")
  assertBetween(totals[20], 23000, 27000, "level 20")
  assertBetween(totals[30], 57000, 67000, "level 30")
})

test("titles change exactly at the documented levels", () => {
  const expected = {
    1: "novice", 4: "novice", 5: "adventurer", 9: "adventurer", 10: "veteran",
    14: "veteran", 15: "champion", 19: "champion", 20: "hero", 24: "hero",
    25: "legend", 29: "legend", 30: "myth"
  }
  for (const level of Object.keys(expected))
    assertEqual(Rules.titleFor(Number(level)), expected[level], `level ${level}`)
})

test("levelling grants the primary every level and a secondary every other one", () => {
  for (const cls of Rules.CLASS_IDS) {
    const spec = Rules.CLASSES[cls]
    const first = Rules.attrsFor("human", cls, 1)
    const tenth = Rules.attrsFor("human", cls, 10)
    assertEqual(tenth[spec.primary] - first[spec.primary], 9, `${cls} primary at level 10`)

    let secondaryGain = 0
    for (const attr of Rules.ATTRS) if (attr !== spec.primary) secondaryGain += tenth[attr] - first[attr]
    assertEqual(secondaryGain, 4, `${cls} secondary points at level 10`)
  }
})

test("race bonuses are applied once, at every level", () => {
  assertEqual(Rules.attrsFor("dwarf", "mage", 1).vit, Rules.BASE_ATTR + 2, "dwarf vit")
  assertEqual(Rules.attrsFor("elf", "mage", 1).agi, Rules.BASE_ATTR + 2, "elf agi")
  assertEqual(Rules.attrsFor("orc", "mage", 1).str, Rules.BASE_ATTR + 2, "orc str")
  assertEqual(Rules.attrsFor("automaton", "mage", 1).wis, Rules.BASE_ATTR + 2 + 0, "automaton wis")
  assertEqual(Rules.attrsFor("human", "mage", 1).wis, Rules.BASE_ATTR, "human has no attribute bonus")
  assertEqual(Rules.attrsFor("dwarf", "mage", 20).vit - Rules.attrsFor("human", "mage", 20).vit, 2, "still +2 at 20")
})

test("levelUps consumes exactly the XP the curve asks for", () => {
  const needed = Rules.xpToNext(1) + Rules.xpToNext(2)
  const result = Rules.levelUps(1, needed + 5)
  assertEqual(result.level, 3, "two levels")
  assertEqual(result.gained, 2, "reported gains")
  assertEqual(result.xp, 5, "the remainder carries")
})

test("XP stops moving the bar at the cap", () => {
  const result = Rules.levelUps(Rules.MAX_LEVEL, 999999)
  assertEqual(result.level, Rules.MAX_LEVEL, "no level 31")
  assertEqual(result.xp, 0, "no dangling bar")
})

// --------------------------------------------------------------- multipliers

test("the class lens multiplies its own domain and nothing else", () => {
  const mage = heroOf("dwarf", "mage")
  assertEqual(Rules.awardXp(mage, 10, "arcane", 0, false), 15, "arcane through a mage")
  assertEqual(Rules.awardXp(mage, 10, "combat", 0, false), 10, "combat through a mage")
})

test("the archer looks through two lenses, and neither is as strong as one", () => {
  const archer = heroOf("dwarf", "archer")
  assertEqual(Rules.awardXp(archer, 100, "exploration", 0, false), 125, "exploration")
  assertEqual(Rules.awardXp(archer, 100, "combat", 0, false), 125, "combat")
  assertEqual(Rules.awardXp(archer, 100, "nature", 0, false), 100, "and nothing else")

  const rogue = heroOf("dwarf", "rogue")
  assert(Rules.awardXp(rogue, 100, "exploration", 0, false) > Rules.awardXp(archer, 100, "exploration", 0, false),
    "a specialist still beats the ranger at their own domain")
})

test("every class has a lens, a primary, a skill and a rotation constant", () => {
  for (const cls of Rules.CLASS_IDS) {
    const spec = Rules.CLASSES[cls]
    assert(!!spec, `${cls} exists`)
    assert(spec.lens && Object.keys(spec.lens).length > 0, `${cls} has a lens`)
    for (const domain of Object.keys(spec.lens))
      assert(Rules.DOMAINS.indexOf(domain) !== -1, `${cls} lens names a real domain: ${domain}`)
    assert(Rules.ATTRS.indexOf(spec.primary) !== -1, `${cls} has a real primary`)
    assert(!!spec.skill && spec.skill.cooldown > 0, `${cls} has a skill`)
    assert(!!spec.combat && spec.combat.power > 0, `${cls} has a rotation constant`)
    assertEqual(spec.secondaries.length, 4, `${cls} rotates four secondaries`)
  }
})

test("a human gets ten percent more of everything", () => {
  const human = heroOf("human", "warrior")
  const dwarf = heroOf("dwarf", "warrior")
  assertEqual(Rules.awardXp(human, 100, "nature", 0, false), 110, "human")
  assertEqual(Rules.awardXp(dwarf, 100, "nature", 0, false), 100, "dwarf")
})

test("an orc gets a quarter more from bosses only", () => {
  const orc = heroOf("orc", "druid")
  assertEqual(Rules.awardXp(orc, 100, "combat", 0, true), 125, "boss")
  assertEqual(Rules.awardXp(orc, 100, "combat", 0, false), 100, "not a boss")
})

test("the streak bonus grows by one percent a day and stops at twenty", () => {
  const hero = heroOf("dwarf", "warrior")
  assertEqual(Rules.awardXp(hero, 100, "nature", 0, false), 100, "no streak")
  assertEqual(Rules.awardXp(hero, 100, "nature", 10, false), 110, "ten days")
  assertEqual(Rules.awardXp(hero, 100, "nature", 20, false), 120, "twenty days")
  assertEqual(Rules.awardXp(hero, 100, "nature", 400, false), 120, "capped")
})

// ------------------------------------------------------------- regeneration

test("regeneration never passes the maximum", () => {
  const hero = heroOf("dwarf", "warrior", 5)
  hero.hp = 1
  hero.hpUpdatedAt = T0
  const healed = Rules.regen(hero, { type: "caravan" }, T0 + 86400 * 30)
  assertEqual(healed.hp, healed.hpMax, "a month heals to full, not past it")
  assertEqual(healed.energy, healed.energyMax, "and energy with it")
})

test("health regenerates at the published rate an hour", () => {
  // Read from the rule rather than written out again here: a test that
  // repeats the constant only proves the constant was typed twice.
  const hero = heroOf("human", "warrior")
  hero.hp = 1
  hero.hpUpdatedAt = T0
  const after = Rules.regen(hero, { type: "caravan" }, T0 + 3600)
  assertEqual(after.hp, 1 + Math.floor(after.hpMax * Rules.HP_REGEN_PER_HOUR), "one hour")
})

test("energy regenerates every two hours, and faster for an automaton", () => {
  const human = heroOf("human", "warrior")
  human.energy = 0
  human.energyUpdatedAt = T0
  assertEqual(Rules.regen(human, { type: "caravan" }, T0 + 7200).energy, 1, "human, two hours")
  assertEqual(Rules.regen(human, { type: "caravan" }, T0 + 7199).energy, 0, "not a second early")

  const automaton = heroOf("automaton", "warrior")
  automaton.energy = 0
  automaton.energyUpdatedAt = T0
  assertEqual(Rules.regen(automaton, { type: "caravan" }, T0 + 5400).energy, 1, "automaton, ninety minutes")
})

test("a partial energy interval is never lost to rounding", () => {
  const hero = heroOf("human", "warrior")
  hero.energy = 0
  hero.energyUpdatedAt = T0

  // Read every ten minutes for four hours: the reads must not reset the clock.
  let current = hero
  for (let step = 1; step <= 24; step++) current = Rules.regen(current, { type: "caravan" }, T0 + step * 600)
  assertEqual(current.energy, 2, "four hours is two points, however often it is read")
})

test("a fortress realm carries one more point of energy", () => {
  const hero = heroOf("human", "warrior")
  assertEqual(Rules.energyMax(hero, { type: "fortress" }), 6, "fortress")
  assertEqual(Rules.energyMax(hero, { type: "caravan" }), 5, "caravan")
})

test("the tavern brings a fainted hero back at half health", () => {
  const hero = heroOf("human", "warrior")
  hero.hp = 0
  hero.hpUpdatedAt = T0
  hero.faintedUntil = T0 + Rules.TAVERN_SECONDS

  assertEqual(Rules.regen(hero, { type: "caravan" }, T0 + 60).hp, 0, "still out cold")
  const awake = Rules.regen(hero, { type: "caravan" }, T0 + Rules.TAVERN_SECONDS + 1)
  assertEqual(awake.faintedUntil, 0, "no longer fainted")
  assertBetween(awake.hp, Math.round(awake.hpMax * 0.5), awake.hpMax, "back at half or better")
})

// -------------------------------------------------------------------- combat

test("a thousand fights per tier and level end inside twelve turns", () => {
  let worst = 0
  for (let tier = 1; tier <= 3; tier++) {
    for (let level = 1; level <= Rules.MAX_LEVEL; level++) {
      const hero = heroOf("human", "warrior", level)
      for (let round = 0; round < 12; round++) {
        const random = Rules.rng(tier * 100000 + level * 1000 + round)
        const enemy = Rules.enemyFor("slime", tier, hero)
        let fight = {
          enemy, enemyHp: enemy.hp, heroHp: hero.hpMax, turn: 0,
          cooldown: 0, enemySkipTurns: 0, dodgeNext: false, critNext: false
        }
        let turns = 0
        while (turns < 40) {
          const step = Rules.combatRound(hero, fight, turns % 4 === 0 ? "skill" : "attack", random)
          fight = Object.assign({}, fight, step)
          turns += 1
          if (step.outcome !== "ongoing") break
        }
        assert(turns <= 12, `tier ${tier} level ${level}: ${turns} turns`)
        worst = Math.max(worst, turns)
      }
    }
  }
  assert(worst >= 3, `fights should not be over instantly (worst was ${worst})`)
})

test("a stealthed rogue both dodges and lands the next hit as a critical", () => {
  const hero = heroOf("human", "rogue", 10)
  const enemy = Rules.enemyFor("goblin", 2, hero)
  const opening = {
    enemy, enemyHp: enemy.hp, heroHp: hero.hpMax, turn: 0,
    cooldown: 0, enemySkipTurns: 0, dodgeNext: false, critNext: false
  }

  const stealth = Rules.combatRound(hero, opening, "skill", Rules.rng(3))
  assertEqual(stealth.heroHp, opening.heroHp, "the promised dodge was kept this round")
  assert(stealth.critNext, "and the critical is still owed")

  const strike = Rules.combatRound(hero, Object.assign({}, opening, stealth), "attack", Rules.rng(3))
  assert(strike.log.some((line) => line.key === "hit_crit"), "the next hit crits")
  assert(!strike.critNext, "and the promise is spent")
})

test("a fight cannot be stalled past the twelve turn budget", () => {
  // A bard healing on every skill turn and defending otherwise is the worst
  // case: without the pressure ramp this ran to 61 turns.
  for (const cls of Rules.CLASS_IDS) {
    for (const level of [1, 10, 30]) {
      const hero = heroOf("human", cls, level)
      const random = Rules.rng(level * 31 + cls.length)
      const enemy = Rules.enemyFor("goblin", 3, hero)
      let fight = {
        enemy, enemyHp: enemy.hp, heroHp: hero.hpMax, turn: 0,
        cooldown: 0, enemySkipTurns: 0, dodgeNext: false, critNext: false
      }
      let turns = 0
      for (; turns < 100; turns++) {
        const step = Rules.combatRound(hero, fight, fight.cooldown <= 0 ? "skill" : "defend", random)
        fight = Object.assign({}, fight, step)
        if (step.outcome !== "ongoing") break
      }
      assert(turns + 1 <= 12, `${cls} at level ${level} stalled for ${turns + 1} turns`)
    }
  }
})

test("every class can win and can lose at every stage of the game", () => {
  // The band itself (55-85%) is checked across the whole tier/level grid by
  // tools/balance.js, which is also what calibrates CLASSES[*].combat.power.
  // Here the guarantee is the one a save depends on: no class is ever locked
  // out of the arena, and none of them is ever safe in it.
  for (const cls of Rules.CLASS_IDS) {
    for (const [tier, level] of [[1, 1], [2, 10], [3, 20], [3, 30]]) {
      const hero = heroOf("human", cls, level)
      let wins = 0
      const trials = 200
      for (let round = 0; round < trials; round++) {
        const random = Rules.rng(round * 7919 + tier * 104729 + level * 31)
        const enemy = Rules.enemyFor("goblin", tier, hero)
        let fight = {
          enemy, enemyHp: enemy.hp, heroHp: hero.hpMax, turn: 0,
          cooldown: 0, enemySkipTurns: 0, dodgeNext: false, critNext: false
        }
        for (let turns = 0; turns < 40; turns++) {
          const lowHealth = fight.heroHp < hero.hpMax * 0.25
          const action = fight.cooldown <= 0 ? "skill" : (lowHealth ? "defend" : "attack")
          const step = Rules.combatRound(hero, fight, action, random)
          fight = Object.assign({}, fight, step)
          if (step.outcome === "won") { wins += 1; break }
          if (step.outcome === "lost") break
        }
      }
      const rate = wins / trials
      assertBetween(rate, 0.35, 0.99, `${cls} tier ${tier} level ${level}`)
    }
  }
})

test("every class skill does something and then goes on cooldown", () => {
  for (const cls of Rules.CLASS_IDS) {
    const hero = heroOf("human", cls, 10)
    const random = Rules.rng(42)
    const enemy = Rules.enemyFor("golem", 3, hero)
    const before = {
      enemy, enemyHp: enemy.hp, heroHp: Math.round(hero.hpMax / 2), turn: 0,
      cooldown: 0, enemySkipTurns: 0, dodgeNext: false, critNext: false
    }
    const after = Rules.combatRound(hero, before, "skill", random)
    assertEqual(after.cooldown, Rules.CLASSES[cls].skill.cooldown, `${cls} cooldown`)
    assert(after.log.length > 0, `${cls} logged nothing`)

    // Some effects are already spent by the time the round returns — roots
    // skips the enemy's half of this same round, stealth's dodge is consumed
    // by the swing it was bought for — so the log counts as evidence too.
    const changed = after.enemyHp < before.enemyHp
      || after.heroHp > before.heroHp
      || after.enemySkipTurns > 0
      || after.dodgeNext || after.critNext
      || after.log.some((line) => line.key === "enemy_rooted" || line.key === "dodge")
    assert(changed, `${cls} skill had no effect`)
  }
})

test("damage never drops below one, however armoured the target", () => {
  const hero = heroOf("human", "bard", 1)
  const random = Rules.rng(1)
  const enemy = Rules.enemyFor("golem", Rules.BOSS_MAX_TIER, hero)
  enemy.def = 999
  const step = Rules.combatRound(hero, {
    enemy, enemyHp: enemy.hp, heroHp: hero.hpMax, turn: 0,
    cooldown: 0, enemySkipTurns: 0, dodgeNext: false, critNext: false
  }, "attack", random)
  assert(enemy.hp - step.enemyHp >= 1, "a hit always lands for at least one")
})

test("dodge and crit stay inside their ceilings", () => {
  const nimble = { str: 5, agi: 99, wis: 5, vit: 5, cha: 5 }
  assertEqual(Rules.dodgeChance(nimble), 0.40, "dodge cap")
  assertEqual(Rules.critChance(nimble), 0.30, "crit cap")
  assert(Rules.skillPower(heroOf("human", "bard", 30), Rules.attrsFor("human", "bard", 30)) <= 1.45, "skill power cap")
})

test("boss rewards beat wanderer rewards and always drop a core", () => {
  const hero = heroOf("human", "warrior", 10)
  const boss = Rules.bossStats(3, hero)
  const bossLoot = Rules.combatRewards(hero, boss, 0, Rules.rng(5))
  const wandererLoot = Rules.combatRewards(hero, Rules.enemyFor("slime", 3, hero), 0, Rules.rng(5))
  assert(bossLoot.xp > wandererLoot.xp, "boss XP")
  assertEqual(bossLoot.materials.core, 1, "core fragment")
})


// -------------------------------------------------------------------- arena

function fixedRandom(values) {
  let index = 0
  return () => values[index++ % values.length]
}

test("a crash becomes a boss named after the executable", () => {
  const state = freshState("human", "warrior")
  const result = World.apply(state, {
    type: "coredumps", entries: [{ comm: "ghostty", at: T0 }]
  }, T0)

  assertEqual(result.state.bosses.length, 1, "one boss")
  assertEqual(result.state.bosses[0].comm, "ghostty", "named after the executable")
  assertEqual(result.state.bosses[0].kind, "crash", "a crash boss")
  assertEqual(result.state.bosses[0].tier, 3, "tier three")
  assert(!result.state.bosses[0].seen, "unseen, so the bar can mark it")
  assert(result.effects.some((e) => e.type === "notify" && e.key === "boss_spawned"), "notified")
})

test("the same executable crashing again grows the boss instead of adding one", () => {
  let state = World.apply(freshState(), { type: "coredumps", entries: [{ comm: "firefox", at: T0 }] }, T0).state
  const firstHealth = state.bosses[0].hpMax

  const result = World.apply(state, { type: "coredumps", entries: [{ comm: "firefox", at: T0 + 60 }] }, T0 + 60)
  assertEqual(result.state.bosses.length, 1, "still one boss")
  assertEqual(result.state.bosses[0].tier, 4, "a tier angrier")
  assert(result.state.bosses[0].hpMax > firstHealth, "and tougher")
  assert(result.effects.some((e) => e.type === "chronicle" && e.entry.type === "boss_grew"), "recorded")
})

test("a boss cannot grow past the maximum tier", () => {
  let state = freshState()
  for (let i = 0; i < 10; i++)
    state = World.apply(state, { type: "coredumps", entries: [{ comm: "chromium", at: T0 + i }] }, T0 + i).state
  assertEqual(state.bosses.length, 1, "one boss")
  assertEqual(state.bosses[0].tier, Rules.BOSS_MAX_TIER, "capped")
})

test("a crash loop cannot grow the boss list", () => {
  let state = freshState()
  const entries = []
  for (let i = 0; i < 500; i++) entries.push({ comm: "crasher" + i, at: T0 + i })
  state = World.apply(state, { type: "coredumps", entries }, T0).state
  assert(state.bosses.length <= Rules.MAX_ACTIVE_BOSSES, `${state.bosses.length} bosses survived a crash loop`)
})

test("a boss that has run out of time retreats without a penalty", () => {
  let state = World.apply(freshState(), { type: "coredumps", entries: [{ comm: "old", at: T0 }] }, T0).state
  const goldBefore = state.hero.gold

  const later = T0 + Rules.BOSS_LIFETIME_SECONDS + 1
  const result = World.apply(state, { type: "check_threats", date: "2026-09-30" }, later)
  assertEqual(result.state.bosses.length, 0, "gone")
  assertEqual(result.state.hero.gold, goldBefore, "and it cost nothing")
  assert(result.effects.some((e) => e.type === "chronicle" && e.entry.type === "boss_retreated"), "recorded")
})

test("a guardian arrives at the weekend and is gone by Monday", () => {
  let state = freshState()

  state = World.apply(state, { type: "check_threats", date: "2026-09-26" }, T0).state
  const guardians = state.bosses.filter((b) => b.kind === "guardian")
  assertEqual(guardians.length, 1, "saturday")

  // Sunday is the same week, so the same guardian stays rather than a second
  // one arriving.
  state = World.apply(state, { type: "check_threats", date: "2026-09-27" }, T0).state
  assertEqual(state.bosses.filter((b) => b.kind === "guardian").length, 1, "sunday, still one")

  state = World.apply(state, { type: "check_threats", date: "2026-09-28" }, T0).state
  assertEqual(state.bosses.filter((b) => b.kind === "guardian").length, 0, "monday")
})

test("starting a fight costs a point of energy", () => {
  const state = freshState("human", "warrior")
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  const before = state.hero.energy

  const result = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0)
  assertEqual(result.state.hero.energy, before - 1, "one energy")
  assert(!!result.state.arena, "a fight is on")
  assertEqual(result.state.arena.outcome, "ongoing", "ongoing")
})

test("a fight cannot start without energy, and nothing is spent trying", () => {
  const state = freshState()
  state.hero.energy = 0
  state.hero.energyUpdatedAt = T0
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]

  const result = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0)
  assertEqual(result.state.arena, null, "no fight")
  assertEqual(result.state.hero.energy, 0, "still nothing spent")
})

test("a fainted hero cannot be sent back into the arena", () => {
  const state = freshState()
  state.hero.faintedUntil = T0 + Rules.TAVERN_SECONDS
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  assertEqual(World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state.arena, null,
    "still in the tavern")
})

test("a fight cannot start while an expedition is out", () => {
  const state = freshState()
  state.expedition = { destId: "long", startedAt: T0, endsAt: T0 + 28800, seed: 1, resolved: false, seen: false, result: null }
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  assertEqual(World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state.arena, null,
    "the hero is elsewhere")
})

test("winning pays experience, gold and loot, and takes nothing back", () => {
  let state = freshState("human", "warrior", )
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state
  state.arena.enemyHp = 1

  const goldBefore = state.hero.gold
  const result = World.apply(state, { type: "fight_action", action: "attack", random: fixedRandom([0.9, 0.5]) }, T0)

  assertEqual(result.state.arena.outcome, "won", "won")
  assert(result.state.hero.gold > goldBefore, "paid")
  assertEqual(result.state.day.counters.arenaWins, 1, "counted")
  assert(result.state.achievements.indexOf("first_blood") !== -1, "first blood")
})

test("losing costs progress, never achievement", () => {
  let state = freshState("human", "warrior")
  state.hero.level = 9
  state.hero.attrs = Rules.attrsFor("human", "warrior", 9)
  state.hero.xp = 400
  state.stats.totalXp = 9000
  state.hero.gold = 250
  state.hero.materials.core = 3
  state.hero.chest = ["iron_sword"]
  state.hero.equipment.weapon = "rune_blade"
  state.achievements = ["first_blood", "survivor"]

  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state
  state.arena.heroHp = 1
  state.arena.enemy.atk = 9999

  const result = World.apply(state, { type: "fight_action", action: "attack", random: fixedRandom([0.99, 0.99]) }, T0)
  assertEqual(result.state.arena.outcome, "lost", "lost")

  // What it costs.
  assertEqual(result.state.hero.xp, 400 - Math.floor(400 * World.DEFEAT_XP_LOSS), "a quarter of the progress")

  // What it never costs.
  assertEqual(result.state.hero.level, 9, "never a level")
  assertEqual(result.state.hero.title, state.hero.title, "never a title")
  assertEqual(result.state.hero.gold, 250, "never gold")
  assertEqual(result.state.hero.materials.core, 3, "never materials")
  assertEqual(result.state.hero.chest.length, 1, "never an item")
  assertEqual(result.state.hero.equipment.weapon, "rune_blade", "never what is worn")
  assertEqual(JSON.stringify(result.state.achievements), JSON.stringify(["first_blood", "survivor"]), "never a feat")
  assertEqual(result.state.stats.totalXp, 9000, "and never the lifetime record the feats read")
})

test("a defeat records what it cost, where the defeat is", () => {
  let state = freshState("human", "warrior")
  state.hero.xp = 240
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state
  state.arena.heroHp = 1
  state.arena.enemy.atk = 9999

  const result = World.apply(state, { type: "fight_action", action: "attack", random: fixedRandom([0.99, 0.99]) }, T0)
  assertEqual(result.state.arena.xpLost, 60, "the fight knows what it took")
  assertEqual(result.state.hero.xp, 180, "and the hero agrees")
})

test("a win records what it brought, where the win is", () => {
  let state = freshState("human", "warrior")
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state
  state.arena.enemyHp = 1

  const result = World.apply(state, { type: "fight_action", action: "attack", random: fixedRandom([0.9, 0.5]) }, T0)
  assert(!!result.state.arena.loot, "the fight knows what it gave")
  assert(Rules.num(result.state.arena.loot.xp) > 0, "experience")
  assert(Rules.num(result.state.arena.loot.gold) > 0, "gold")
})

test("losing at the very start of a level cannot go below zero", () => {
  let state = freshState()
  state.hero.xp = 0
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state
  state.arena.heroHp = 1
  state.arena.enemy.atk = 9999

  const result = World.apply(state, { type: "fight_action", action: "attack", random: fixedRandom([0.99, 0.99]) }, T0)
  assertEqual(result.state.hero.xp, 0, "zero, not negative")
  assertEqual(result.state.hero.level, state.hero.level, "and still the same level")
})

test("the tavern is still the only other cost", () => {
  let state = freshState("human", "bard")
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state
  state.arena.heroHp = 1
  state.arena.enemy.atk = 9999

  const result = World.apply(state, { type: "fight_action", action: "attack", random: fixedRandom([0.99, 0.99]) }, T0)
  assertEqual(result.state.hero.faintedUntil, T0 + Rules.TAVERN_SECONDS, "half an hour in the tavern")
})

test("the fight log never grows past four lines", () => {
  let state = freshState("human", "druid", )
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state

  const random = Rules.rng(9)
  for (let turn = 0; turn < 30 && state.arena && state.arena.outcome === "ongoing"; turn++) {
    state = World.apply(state, { type: "fight_action", action: "defend", random }, T0).state
    assert(state.arena.log.length <= World.MAX_LOG_LINES, `log grew to ${state.arena.log.length}`)
  }
})

test("fleeing ends the fight and does not refund the energy", () => {
  let state = freshState()
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state
  const energy = state.hero.energy

  const result = World.apply(state, { type: "flee" }, T0)
  assertEqual(result.state.arena, null, "over")
  assertEqual(result.state.hero.energy, energy, "the energy stays spent")
})

test("a restart cancels the fight and gives the energy back", () => {
  let state = freshState()
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  const energyBefore = state.hero.energy
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state

  const result = World.apply(state, { type: "cancel_fight" }, T0)
  assertEqual(result.state.arena, null, "dropped")
  assertEqual(result.state.hero.energy, energyBefore, "refunded")
})

test("the energy comes back after a restart even though the load dropped the fight", () => {
  // The real path: Migrations clears `arena` on load, so by the time the
  // service cancels the fight there is nothing left to see. The refund has to
  // happen anyway, which is what `interrupted` is for.
  let state = freshState()
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  const energyBefore = state.hero.energy
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state
  assertEqual(state.hero.energy, energyBefore - 1, "spent")

  const loaded = Migrations.run(JSON.parse(JSON.stringify(state)))
  assertEqual(loaded.arena, null, "the load dropped the fight")
  assertEqual(loaded.hero.energy, energyBefore - 1, "and the energy is still spent")

  const result = World.apply(loaded, { type: "cancel_fight", interrupted: true }, Rules.nowSec())
  assertEqual(result.state.hero.energy, energyBefore, "refunded")
})

test("beating a boss removes it and records the deed", () => {
  let state = World.apply(freshState("human", "warrior"), {
    type: "coredumps", entries: [{ comm: "ghostty", at: T0 }]
  }, T0).state
  const bossId = state.bosses[0].id

  state = World.apply(state, { type: "start_fight", kind: "crash", id: bossId }, T0).state
  assert(!!state.arena, "the fight started")
  state.arena.enemyHp = 1

  const result = World.apply(state, { type: "fight_action", action: "attack", random: fixedRandom([0.9, 0.5]) }, T0)
  assertEqual(result.state.bosses.length, 0, "gone")
  assertEqual(result.state.stats.bossKills, 1, "counted")
  assert(result.state.achievements.indexOf("survivor") !== -1, "survivor")
  assertEqual(result.state.hero.materials.core, 1, "a core fragment")
})

test("a boss keeps the health it has left between fights", () => {
  let state = World.apply(freshState(), { type: "coredumps", entries: [{ comm: "wounded", at: T0 }] }, T0).state
  state.bosses[0].hp = 5

  state = World.apply(state, { type: "start_fight", kind: "crash", id: state.bosses[0].id }, T0).state
  assertEqual(state.arena.enemyHp, 5, "picks up where it left off")
})

test("a boss name from the machine is bounded, on the way in and on the way back", () => {
  // The executable's basename is the only string the plugin ever takes from
  // outside and keeps. It is bounded where it enters and bounded again where
  // it is loaded, and the chronicle renders it as plain text, never as markup.
  const hostile = "<script>".repeat(40)

  // Dated now, not at the fixture epoch: a load drops a boss whose seven days
  // have run out, which is correct and would otherwise hide what is under test.
  const now = Rules.nowSec()
  const state = World.apply(freshState(), { type: "coredumps", entries: [{ comm: hostile, at: now }] }, now).state
  assertEqual(state.bosses[0].comm.length, 32, "bounded on the way in")

  const round = Migrations.run(JSON.parse(JSON.stringify(state)))
  assertEqual(round.bosses.length, 1, "a live boss survives a load")
  assertEqual(round.bosses[0].comm.length, 32, "and is still bounded")
})

// -------------------------------------------------------------------- forge

test("every recipe is craftable with enough materials", () => {
  for (const recipe of Rules.RECIPES) {
    const hero = heroOf("human", "warrior")
    for (const key of Rules.MATERIALS) hero.materials[key] = 99
    assert(Rules.canCraft(hero, recipe), `${recipe.id} should be craftable`)
  }
})

test("a dwarf pays one material less per line, never below one", () => {
  for (const recipe of Rules.RECIPES) {
    const dwarf = heroOf("dwarf", "warrior")
    const human = heroOf("human", "warrior")
    const dwarfCost = Rules.costFor(dwarf, recipe)
    const humanCost = Rules.costFor(human, recipe)
    for (const key of Object.keys(recipe.cost)) {
      assertEqual(humanCost[key], recipe.cost[key], `${recipe.id} human ${key}`)
      assertEqual(dwarfCost[key], Math.max(1, recipe.cost[key] - 1), `${recipe.id} dwarf ${key}`)
      assert(dwarfCost[key] >= 1, `${recipe.id} ${key} went below one`)
    }
  }
})

test("equipment changes what a hit is worth", () => {
  const bare = heroOf("human", "warrior", 5)
  const armed = heroOf("human", "warrior", 5)
  armed.equipment.weapon = "core_sword"
  assert(Rules.equipmentStats(armed).damage > Rules.equipmentStats(bare).damage, "damage")
  assertEqual(Rules.effectiveAttrs(armed).str - Rules.effectiveAttrs(bare).str, 1, "core sword strength")
  assert(Rules.hpMax(armed) === Rules.hpMax(bare), "a weapon is not health")
})

test("an unknown equipped id contributes nothing instead of breaking", () => {
  const hero = heroOf("human", "warrior")
  hero.equipment.weapon = "sword_from_the_future"
  assertEqual(Rules.equipmentStats(hero).damage, 0, "unknown item")
  assert(isFinite(Rules.hpMax(hero)), "health stays a number")
})


// --------------------------------------------------------------- expedition

test("launching an expedition costs a point of energy and sets an end time", () => {
  const state = freshState("human", "druid")
  const destination = Rules.destinations(state.day.date, state.hero)[0]
  const energy = state.hero.energy

  const result = World.apply(state, { type: "start_expedition", destId: destination.id }, T0)
  assertEqual(result.state.hero.energy, energy - 1, "one energy")
  assertEqual(result.state.expedition.destId, destination.id, "the chosen destination")
  assertEqual(result.state.expedition.endsAt, T0 + destination.minutes * 60, "ends when it should")
  assert(!result.state.expedition.resolved, "still out")
})

test("only one expedition at a time, and never during a fight", () => {
  let state = freshState()
  const destination = Rules.destinations(state.day.date, state.hero)[0]
  state = World.apply(state, { type: "start_expedition", destId: destination.id }, T0).state
  const endsAt = state.expedition.endsAt

  state = World.apply(state, { type: "start_expedition", destId: destination.id }, T0).state
  assertEqual(state.expedition.endsAt, endsAt, "the second launch changed nothing")

  let fighting = freshState()
  const wanderer = Rules.wanderers(fighting.day.date, fighting.hero.level)[0]
  fighting = World.apply(fighting, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state
  fighting = World.apply(fighting, { type: "start_expedition", destId: destination.id }, T0).state
  assertEqual(fighting.expedition, null, "not while swinging a sword")
})

test("an expedition does not resolve before it is due", () => {
  let state = freshState()
  const destination = Rules.destinations(state.day.date, state.hero)[0]
  state = World.apply(state, { type: "start_expedition", destId: destination.id }, T0).state

  state = World.apply(state, { type: "resolve_expedition" }, state.expedition.endsAt - 1).state
  assert(!state.expedition.resolved, "one second early is early")

  state = World.apply(state, { type: "resolve_expedition" }, state.expedition.endsAt).state
  assert(state.expedition.resolved, "on time")
})

test("resolving twice pays once", () => {
  let state = freshState()
  const destination = Rules.destinations(state.day.date, state.hero)[0]
  state = World.apply(state, { type: "start_expedition", destId: destination.id }, T0).state
  const due = state.expedition.endsAt

  state = World.apply(state, { type: "resolve_expedition" }, due).state
  const first = JSON.stringify(state.expedition.result)

  const again = World.apply(state, { type: "resolve_expedition" }, due + 10000)
  assertEqual(again.effects.length, 0, "nothing happened the second time")
  assertEqual(JSON.stringify(again.state.expedition.result), first, "and the result is the same one")
})

test("a machine that was off finds the result it would have found on time", () => {
  // The whole design of the thing: only an end time and a seed are stored, and
  // the result comes out of the seed whenever anyone gets round to it.
  let onTime = freshState("human", "druid")
  const destination = Rules.destinations(onTime.day.date, onTime.hero)[0]
  onTime = World.apply(onTime, { type: "start_expedition", destId: destination.id }, T0).state
  const due = onTime.expedition.endsAt
  onTime = World.apply(onTime, { type: "resolve_expedition" }, due).state

  let late = freshState("human", "druid")
  late = World.apply(late, { type: "start_expedition", destId: destination.id }, T0).state
  late = World.apply(late, { type: "resolve_expedition" }, due + 86400 * 7).state

  assertEqual(JSON.stringify(late.expedition.result), JSON.stringify(onTime.expedition.result),
    "a week late is the same journey")
})

test("collecting hands over the loot and frees the hero", () => {
  let state = freshState("human", "druid")
  const destination = Rules.destinations(state.day.date, state.hero)[0]
  state = World.apply(state, { type: "start_expedition", destId: destination.id }, T0).state
  state = World.apply(state, { type: "resolve_expedition" }, state.expedition.endsAt).state

  const loot = state.expedition.result
  const goldBefore = state.hero.gold
  const ironBefore = state.hero.materials.iron

  const result = World.apply(state, { type: "collect_expedition" }, state.expedition.endsAt)
  assertEqual(result.state.expedition, null, "home")
  assertEqual(result.state.hero.gold, goldBefore + loot.gold, "gold")
  assertEqual(result.state.hero.materials.iron, ironBefore + (loot.materials.iron || 0), "materials")
  assertEqual(result.state.day.counters.expeditions, 1, "counted for the quest")
  assertEqual(result.state.stats.expeditions, 1, "and for the feat")
})

test("collecting an expedition that is still out does nothing", () => {
  let state = freshState()
  const destination = Rules.destinations(state.day.date, state.hero)[0]
  state = World.apply(state, { type: "start_expedition", destId: destination.id }, T0).state
  const goldBefore = state.hero.gold

  const result = World.apply(state, { type: "collect_expedition" }, T0)
  assert(!!result.state.expedition, "still out")
  assertEqual(result.state.hero.gold, goldBefore, "and nothing was paid")
})

// -------------------------------------------------------------------- forge

test("forging spends the materials and puts the item in the chest", () => {
  let state = freshState("human", "warrior")
  const recipe = Rules.RECIPES[0]
  for (const key of Rules.MATERIALS) state.hero.materials[key] = 9

  const result = World.apply(state, { type: "craft", recipe: recipe.id }, T0)
  const cost = Rules.costFor(state.hero, recipe)
  for (const key of Object.keys(cost))
    assertEqual(result.state.hero.materials[key], 9 - cost[key], `${key} spent`)
  assert(result.state.hero.chest.indexOf(recipe.id) !== -1, "in the chest")
  assertEqual(result.state.hero.equipment.weapon, null, "and not worn without being asked")
})

test("forging without the materials changes nothing", () => {
  const state = freshState()
  const before = JSON.stringify(state)
  const result = World.apply(state, { type: "craft", recipe: "core_sword" }, T0)
  assertEqual(JSON.stringify(result.state), before, "untouched")
})

test("a dwarf can forge what a human cannot, with the same materials", () => {
  const recipe = Rules.recipeById("iron_sword")
  const dwarf = freshState("dwarf", "warrior")
  const human = freshState("human", "warrior")
  for (const hero of [dwarf.hero, human.hero]) {
    hero.materials.iron = 2
    hero.materials.wood = 1
  }
  assert(Rules.canCraft(dwarf.hero, recipe), "the dwarf pays one less per line")
  assert(!Rules.canCraft(human.hero, recipe), "and the human does not")
})

test("equipping swaps rather than destroys", () => {
  let state = freshState("human", "warrior")
  state.hero.chest = ["iron_sword", "core_sword"]

  state = World.apply(state, { type: "equip", item: "iron_sword" }, T0).state
  assertEqual(state.hero.equipment.weapon, "iron_sword", "worn")
  assertEqual(state.hero.chest.indexOf("iron_sword"), -1, "out of the chest")

  state = World.apply(state, { type: "equip", item: "core_sword" }, T0).state
  assertEqual(state.hero.equipment.weapon, "core_sword", "swapped")
  assert(state.hero.chest.indexOf("iron_sword") !== -1, "the old one went back to the chest")
})

test("every class attacks with its own primary attribute", () => {
  // One rule for six classes: your primary is your power. Reading damage off
  // Strength specifically left five of the six dealing the same damage at 30
  // as at 1, and left nobody able to explain why a mage's attack scaled with
  // muscle.
  for (const cls of Rules.CLASS_IDS) {
    const primary = Rules.CLASSES[cls].primary
    const low = heroOf("human", cls, 1)
    const high = heroOf("human", cls, 20)

    assert(Rules.attackValue(high) > Rules.attackValue(low), `${cls} gets stronger`)

    // Raising the primary by hand raises the attack; raising anything else
    // does not.
    for (const attr of Rules.ATTRS) {
      const bumped = heroOf("human", cls, 10)
      bumped.attrs[attr] += 5
      const moved = Rules.attackValue(bumped) > Rules.attackValue(heroOf("human", cls, 10))
      assertEqual(moved, attr === primary, `${cls}: ${attr} should ${attr === primary ? "" : "not "}move attack`)
    }
  }
})

test("defence comes from armour and from nowhere else", () => {
  const bare = heroOf("human", "warrior", 10)
  assertEqual(Rules.defenseValue(bare), 0, "no armour, no defence")

  for (const attr of Rules.ATTRS) {
    const bumped = heroOf("human", "warrior", 10)
    bumped.attrs[attr] += 10
    assertEqual(Rules.defenseValue(bumped), 0, `${attr} is not defence`)
  }

  const armoured = heroOf("human", "warrior", 10)
  armoured.equipment.armor = "plated_mail"
  assertEqual(Rules.defenseValue(armoured), Rules.recipeById("plated_mail").stats.defense, "armour is")
})

test("the sheet's explanation of an attribute matches what it does", () => {
  for (const cls of Rules.CLASS_IDS) {
    const hero = heroOf("human", cls, 12)
    const primary = Rules.CLASSES[cls].primary

    assertEqual(Rules.attrReadout(hero, primary).key, "power", `${cls} primary reads as power`)
    assertEqual(Rules.attrReadout(hero, primary).value, Rules.attackValue(hero), `${cls} primary shows the attack`)

    if (primary !== "vit") assertEqual(Rules.attrReadout(hero, "vit").key, "health", `${cls} vit`)
    if (primary !== "agi") assertEqual(Rules.attrReadout(hero, "agi").key, "evasion", `${cls} agi`)
    if (primary !== "cha") assertEqual(Rules.attrReadout(hero, "cha").key, "fortune", `${cls} cha`)

    // Whatever is neither the primary nor one of those three does nothing for
    // this hero, and the sheet says so rather than implying otherwise.
    for (const attr of ["str", "wis"])
      if (attr !== primary) assertEqual(Rules.attrReadout(hero, attr).key, "idle", `${cls} ${attr}`)
  }
})

test("gear bonuses are reported separately from levelled attributes", () => {
  const hero = heroOf("human", "warrior", 10)
  assertEqual(Rules.attrFromGear(hero, "str"), 0, "nothing worn")

  hero.equipment.weapon = "core_sword"
  assertEqual(Rules.attrFromGear(hero, "str"), 1, "the core sword's point of Strength")
  assertEqual(Rules.effectiveAttrs(hero).str, hero.attrs.str + 1, "and it counts")
})

test("taking something off returns it and lowers what it raised", () => {
  let state = freshState("human", "druid")
  state.hero.chest = ["plated_mail"]
  state = World.apply(state, { type: "equip", item: "plated_mail" }, T0).state

  const withArmour = state.hero.hpMax
  assertEqual(state.hero.chest.length, 0, "out of the chest")

  state = World.apply(state, { type: "unequip", slot: "armor" }, T0).state
  assertEqual(state.hero.equipment.armor, null, "off")
  assertEqual(state.hero.chest.indexOf("plated_mail"), 0, "back in the chest")
  assert(state.hero.hpMax < withArmour, "and the health it added is gone")
  assert(state.hero.hp >= 1, "without ever leaving the hero on zero")
})

test("taking off an empty slot does nothing", () => {
  const state = freshState()
  const before = JSON.stringify(state)
  assertEqual(JSON.stringify(World.apply(state, { type: "unequip", slot: "amulet" }, T0).state), before, "untouched")
})

test("equipping something not in the chest does nothing", () => {
  const state = freshState()
  const result = World.apply(state, { type: "equip", item: "core_aegis" }, T0)
  assertEqual(result.state.hero.equipment.armor, null, "not worn")
})

test("armour raises the maximum and gives the difference straight away", () => {
  let state = freshState("human", "warrior")
  state.hero.chest = ["plated_mail"]
  const before = { hp: state.hero.hp, hpMax: state.hero.hpMax }

  state = World.apply(state, { type: "equip", item: "plated_mail" }, T0).state
  assert(state.hero.hpMax > before.hpMax, "the maximum went up")
  assertEqual(state.hero.hp - before.hp, state.hero.hpMax - before.hpMax, "and so did the current value")
  assert(state.hero.hp <= state.hero.hpMax, "without passing it")
})

test("a weapon changes what a fight is worth, and a test can see it", () => {
  const bare = heroOf("human", "mage", 10)
  const armed = heroOf("human", "mage", 10)
  armed.equipment.weapon = "core_sword"

  const bareEnemy = Rules.enemyFor("goblin", 2, bare)
  const armedEnemy = Rules.enemyFor("goblin", 2, armed)
  // The enemy is built against the hero, so a better weapon buys a bigger
  // enemy rather than an easier fight — which is the design, and worth
  // pinning so a later change to enemyFor cannot quietly invert it.
  assert(armedEnemy.hp > bareEnemy.hp, "the enemy grew with the hero")
})

// ------------------------------------------------------- deterministic days

test("the same date always draws the same quests, wanderers and destinations", () => {
  const hero = heroOf("elf", "rogue")
  for (const date of ["2026-09-22", "2026-01-01", "2026-12-31"]) {
    assertEqual(JSON.stringify(Rules.dailyQuests(date)), JSON.stringify(Rules.dailyQuests(date)), date)
    assertEqual(JSON.stringify(Rules.wanderers(date, 5)), JSON.stringify(Rules.wanderers(date, 5)), date)
    assertEqual(JSON.stringify(Rules.destinations(date, hero)), JSON.stringify(Rules.destinations(date, hero)), date)
  }
})

test("different dates draw different quests", () => {
  const a = JSON.stringify(Rules.dailyQuests("2026-09-22"))
  const b = JSON.stringify(Rules.dailyQuests("2026-09-23"))
  assert(a !== b, "two days in a row drew the same three quests")
})

test("a day always offers three distinct quests", () => {
  for (let day = 0; day < 400; day++) {
    const date = Rules.localDate(T0 + day * 86400)
    const quests = Rules.dailyQuests(date)
    assertEqual(quests.length, Rules.QUESTS_PER_DAY, date)
    const ids = quests.map((q) => q.id)
    assertEqual(new Set(ids).size, ids.length, `${date} drew a duplicate`)
    for (const quest of quests) assert(quest.target > 0, `${date} ${quest.id} has no target`)
  }
})

test("an elf's expeditions are fifteen percent shorter", () => {
  const elf = Rules.destinations("2026-09-22", heroOf("elf", "rogue"))
  const human = Rules.destinations("2026-09-22", heroOf("human", "rogue"))
  for (let i = 0; i < human.length; i++)
    assertEqual(elf[i].minutes, Math.round(human[i].minutes * 0.85), `destination ${i}`)
})

test("an expedition resolves the same way however late it is collected", () => {
  const hero = heroOf("human", "druid", 5)
  const expedition = { destId: "long", startedAt: T0, endsAt: T0 + 28800, seed: 123456 }
  const first = Rules.resolveExpedition(expedition, hero, 0)
  const second = Rules.resolveExpedition(expedition, hero, 0)
  assertEqual(JSON.stringify(first), JSON.stringify(second), "same seed, same result")
  assert(first.xp > 0 && first.gold > 0, "an expedition is always worth something")
  assert(Object.keys(first.materials).length > 0, "and always brings materials back")
})

test("a longer expedition is worth more than a shorter one", () => {
  const hero = heroOf("human", "druid", 5)
  const short = Rules.resolveExpedition({ destId: "short", seed: 7 }, hero, 0)
  const long = Rules.resolveExpedition({ destId: "long", seed: 7 }, hero, 0)
  assert(long.xp > short.xp, "XP")
  assert(long.gold > short.gold, "gold")
})

test("the ISO week key is one value across a whole weekend", () => {
  assertEqual(Rules.isoWeekKey("2026-09-26"), Rules.isoWeekKey("2026-09-27"), "saturday and sunday")
  assert(Rules.isWeekend("2026-09-26"), "saturday")
  assert(Rules.isWeekend("2026-09-27"), "sunday")
  assert(!Rules.isWeekend("2026-09-28"), "monday")
})

// --------------------------------------------------------------------- world

test("creating a hero writes a birth line and nothing else about the machine", () => {
  const result = World.apply(Rules.newSave(T0), {
    type: "create_hero", name: "Luiz", race: "dwarf", cls: "mage",
    realmName: "fortaleza", realmType: "fortress"
  }, T0)

  assertEqual(result.state.hero.name, "Luiz", "name")
  assertEqual(result.state.hero.race, "dwarf", "race")
  assertEqual(result.state.hero.energyMax, 6, "a fortress hero starts with six")
  assertEqual(result.state.hero.energy, 6, "and starts full")

  const chronicles = result.effects.filter((e) => e.type === "chronicle")
  assertEqual(chronicles.length, 1, "one line")
  assertEqual(chronicles[0].entry.type, "born", "born")
})

test("World never mutates the state it is handed", () => {
  const before = freshState()
  const snapshot = JSON.stringify(before)
  World.apply(before, { type: "workspace_discovered", workspace: 3 }, T0)
  World.apply(before, { type: "theme_changed" }, T0)
  assertEqual(JSON.stringify(before), snapshot, "the input changed under us")
})

test("an event with no hero yet is ignored rather than crashing", () => {
  const empty = Rules.newSave(T0)
  const result = World.apply(empty, { type: "workspace_discovered", workspace: 1 }, T0)
  assertEqual(result.effects.length, 0, "nothing happened")
  assertEqual(result.state.hero, null, "still no hero")
})

test("an unknown event type changes nothing", () => {
  const state = freshState()
  const result = World.apply(state, { type: "definitely_not_a_real_event" }, T0)
  assertEqual(JSON.stringify(result.state), JSON.stringify(state), "state untouched")
  assertEqual(result.effects.length, 0, "no effects")
})

test("passive XP stops at the daily cap while the counter keeps counting", () => {
  let state = freshState("dwarf", "warrior")
  const cap = Rules.PASSIVE.workspace_discovered.cap

  // Workspaces are numbered from one; zero is not a workspace.
  for (let i = 1; i <= cap + 8; i++)
    state = World.apply(state, { type: "workspace_discovered", workspace: i }, T0).state

  assertEqual(state.day.counters.workspaces, cap + 8, "the counter counts everything")
  assertEqual(state.day.xpByDomain.exploration, cap * Rules.PASSIVE.workspace_discovered.xp, "XP stops at the cap")
})

test("a workspace is paid for once a day, however often the shell restarts", () => {
  // The day remembers which workspaces it paid for, on disk. It used to be an
  // in-memory set in the service, which a shell restart cleared — so every
  // restart paid again for whichever workspace the player was sitting on, and
  // ten restarts in a morning bought the Explorer feat outright.
  let state = freshState("dwarf", "warrior")

  state = World.apply(state, { type: "workspace_discovered", workspace: 1 }, T0).state
  assertEqual(state.day.counters.workspaces, 1, "counted once")

  for (let restart = 0; restart < 10; restart++)
    state = World.apply(state, { type: "workspace_discovered", workspace: 1 }, T0).state
  assertEqual(state.day.counters.workspaces, 1, "and only once")

  state = World.apply(state, { type: "workspace_discovered", workspace: 2 }, T0).state
  assertEqual(state.day.counters.workspaces, 2, "a different workspace does count")

  // And it survives the round trip, which is the whole point.
  const loaded = Migrations.run(JSON.parse(JSON.stringify(state)))
  const after = World.apply(loaded, { type: "workspace_discovered", workspace: 1 }, T0)
  assertEqual(after.state.day.counters.workspaces, 2, "still remembered after a load")
  assertEqual(after.effects.length, 0, "and nothing happened")
})

test("a new day forgets which workspaces were paid for", () => {
  let state = freshState()
  state = World.apply(state, { type: "workspace_discovered", workspace: 1 }, T0).state
  state = World.apply(state, { type: "day_rollover", date: "2026-10-09" }, T0).state
  assertEqual(state.day.workspaceIds.length, 0, "a clean slate")

  state = World.apply(state, { type: "workspace_discovered", workspace: 1 }, T0).state
  assertEqual(state.day.counters.workspaces, 1, "and the same workspace counts again")
})

test("the list of paid workspaces cannot grow without bound", () => {
  let state = freshState()
  for (let i = 1; i <= 500; i++)
    state = World.apply(state, { type: "workspace_discovered", workspace: i }, T0).state
  assert(state.day.workspaceIds.length <= Rules.MAX_WORKSPACE_IDS,
    `${state.day.workspaceIds.length} ids survived`)
})

test("the counter keeps counting past the cap so quests and feats still land", () => {
  let state = freshState("dwarf", "warrior")
  for (let i = 0; i < 12; i++) state = World.apply(state, { type: "theme_changed" }, T0).state
  assertEqual(state.day.counters.themes, 12, "twelve theme changes")
  assert(state.achievements.indexOf("chameleon") !== -1, "five in a day is a feat")
})

test("nothing a sensor reports is written into the save as text", () => {
  let state = freshState()
  state = World.apply(state, { type: "app_discovered", appClass: "org.mozilla.firefox" }, T0).state
  state = World.apply(state, { type: "terminal_opened", appClass: "com.mitchellh.ghostty" }, T0).state
  state = World.apply(state, { type: "commit", repo: "/home/f3/Work/secret-project" }, T0).state

  const serialized = JSON.stringify(state)
  for (const leak of ["firefox", "ghostty", "secret-project", "mozilla", "Work"])
    assert(serialized.indexOf(leak) === -1, `the save leaked "${leak}"`)
})

test("enough XP levels the hero up and says so once", () => {
  let state = freshState("dwarf", "warrior")
  state.hero.xp = Rules.xpToNext(1) - 1

  const result = World.apply(state, { type: "theme_changed" }, T0)
  assertEqual(result.state.hero.level, 2, "level two")
  assertEqual(result.state.hero.title, "novice", "still a novice at two")
  assertEqual(result.effects.filter((e) => e.type === "notify" && e.key === "level_up").length, 1, "one notification")
  assert(result.effects.some((e) => e.type === "anim" && e.name === "cheer"), "and a cheer")
})

test("levelling up adds the health it gained, not a full heal", () => {
  let state = freshState("dwarf", "warrior")
  state.hero.hp = 5
  state.hero.xp = Rules.xpToNext(1) - 1
  const after = World.apply(state, { type: "theme_changed" }, T0).state
  assert(after.hero.hp > 5, "some health came with the level")
  assert(after.hero.hp < after.hero.hpMax, "but it was not a rescue")
})

test("finishing the day's quests earns the Seal and moves the streak once", () => {
  let state = freshState("dwarf", "warrior")
  // Drive the quests the day actually drew, whatever they are.
  for (const quest of state.day.quests) state.day.counters[quest.counter] = quest.target

  const result = World.apply(state, { type: "theme_changed" }, T0)
  assert(result.state.day.sealEarned, "seal")
  assertEqual(result.state.streak.count, 1, "streak moved once")
  assertEqual(result.effects.filter((e) => e.type === "chronicle" && e.entry.type === "seal_earned").length, 1, "one line")

  const again = World.apply(result.state, { type: "theme_changed" }, T0)
  assertEqual(again.state.streak.count, 1, "and only once")
})

test("the streak survives two missed days and falls on the third", () => {
  let state = freshState()
  state.streak = { count: 4, lastSealDate: "2026-09-21", missedDays: 0 }

  state = World.apply(state, { type: "day_rollover", date: "2026-09-23" }, T0).state
  assertEqual(state.streak.count, 4, "one missed day is forgiven")
  state = World.apply(state, { type: "day_rollover", date: "2026-09-24" }, T0).state
  assertEqual(state.streak.count, 4, "two missed days are forgiven")
  state = World.apply(state, { type: "day_rollover", date: "2026-09-25" }, T0).state
  assertEqual(state.streak.count, 0, "the third resets it")
})

test("a day that earned its Seal costs the streak nothing", () => {
  let state = freshState()
  state.streak = { count: 4, lastSealDate: state.day.date, missedDays: 0 }
  state.day.sealEarned = true
  state = World.apply(state, { type: "day_rollover", date: "2026-10-01" }, T0).state
  assertEqual(state.streak.count, 4, "streak kept")
  assertEqual(state.streak.missedDays, 0, "nothing missed")
})

test("a new day clears the counters and draws new quests", () => {
  let state = freshState()
  state = World.apply(state, { type: "workspace_discovered", workspace: 1 }, T0).state
  assert(state.day.counters.workspaces > 0, "something happened today")

  const rolled = World.apply(state, { type: "day_rollover", date: "2026-10-05" }, T0).state
  assertEqual(rolled.day.date, "2026-10-05", "the date moved")
  assertEqual(rolled.day.counters.workspaces, 0, "counters cleared")
  assertEqual(rolled.day.notificationsSent, 0, "the notification budget is new too")
  assertEqual(JSON.stringify(rolled.day.quests.map((q) => q.id)),
    JSON.stringify(Rules.dailyQuests("2026-10-05").map((q) => q.id)), "the new day's quests")
})

test("marking things seen clears the accent dot and nothing else", () => {
  let state = freshState()
  state.bosses = [{ id: "b1", kind: "crash", comm: "ghostty", epithet: 3, tier: 3, hp: 60, hpMax: 60, spawnedAt: T0, expiresAt: T0 + 86400, seen: false }]
  const result = World.apply(state, { type: "mark_seen", what: "bosses" }, T0)
  assert(result.state.bosses[0].seen, "seen")
  assertEqual(result.state.hero.xp, state.hero.xp, "looking at something is not progress")
})

// ------------------------------------------------------------------- stroll

test("the hero goes out whenever asked, as often as asked", () => {
  let state = freshState()
  assert(World.canStroll(state, T0), "first")

  // Ten walks in a row, all of them allowed.
  for (let i = 0; i < 10; i++) {
    state = World.apply(state, { type: "stroll_found" }, T0 + i).state
    assert(World.canStroll(state, T0 + i), `walk ${i + 1} refused`)
  }
})

test("only the first few walks of a day bring anything back", () => {
  let state = freshState()
  const gold = state.hero.gold

  // Spread far enough apart to clear the cooldown each time.
  let at = T0
  for (let i = 0; i < Rules.MAX_STROLL_FINDS_PER_DAY; i++) {
    assert(World.strollPays(state, at), `find ${i + 1} should pay`)
    state = World.apply(state, { type: "stroll_found" }, at).state
    at += Rules.STROLL_FIND_COOLDOWN
  }

  assert(!World.strollPays(state, at), "the fourth find is not paid")
  assert(World.canStroll(state, at), "but the walk still happens")

  const afterEmpty = World.apply(state, { type: "stroll_found" }, at)
  assertEqual(afterEmpty.effects.length, 0, "and it is not even worth a chronicle line")
  assertEqual(afterEmpty.state.hero.gold, state.hero.gold, "nor any gold")
  assert(state.hero.gold > gold, "while the paid ones were worth something")
})

test("two walks in quick succession pay once", () => {
  let state = freshState()
  state = World.apply(state, { type: "stroll_found" }, T0).state
  const gold = state.hero.gold

  const soon = World.apply(state, { type: "stroll_found" }, T0 + 60)
  assertEqual(soon.state.hero.gold, gold, "an hour and a half between finds")
  assert(World.canStroll(soon.state, T0 + 60), "and the walk is still allowed")
})

test("a hero who is somewhere else does not go for a walk", () => {
  const fighting = freshState()
  const wanderer = Rules.wanderers(fighting.day.date, fighting.hero.level)[0]
  const inArena = World.apply(fighting, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state
  assert(!World.canStroll(inArena, T0), "not mid-fight")

  const away = freshState()
  away.expedition = { destId: "long", startedAt: T0, endsAt: T0 + 28800, seed: 1, resolved: false, seen: false, result: null }
  assert(!World.canStroll(away, T0), "not while away")

  const down = freshState()
  down.hero.faintedUntil = T0 + Rules.TAVERN_SECONDS
  assert(!World.canStroll(down, T0), "not from the tavern")
})

// ----------------------------------------------------------------- merchant

test("the merchant offers the same three things all day, and different ones tomorrow", () => {
  for (const date of ["2026-09-22", "2026-10-01"]) {
    assertEqual(JSON.stringify(Rules.merchantStock(date)), JSON.stringify(Rules.merchantStock(date)), date)
    const stock = Rules.merchantStock(date)
    assertEqual(stock.length, Rules.MERCHANT_OFFERS, "three offers")
    const materials = stock.map((o) => o.material)
    assertEqual(new Set(materials).size, materials.length, "no duplicates")
    for (const offer of stock) {
      assert(Rules.MATERIALS.indexOf(offer.material) !== -1, "a real material")
      assert(offer.count > 0 && offer.gold > 0, "a real price")
    }
  }
  assert(JSON.stringify(Rules.merchantStock("2026-09-22")) !== JSON.stringify(Rules.merchantStock("2026-09-23")),
    "two days running offered exactly the same thing")
})

test("buying spends the gold and hands over the materials", () => {
  const state = freshState()
  const offer = Rules.merchantStock(state.day.date)[0]
  state.hero.gold = offer.gold + 5
  const before = state.hero.materials[offer.material]

  const result = World.apply(state, { type: "buy_material", offer: offer.id }, T0)
  assertEqual(result.state.hero.gold, 5, "paid")
  assertEqual(result.state.hero.materials[offer.material], before + offer.count, "delivered")
})

test("buying without the gold changes nothing", () => {
  const state = freshState()
  const offer = Rules.merchantStock(state.day.date)[0]
  state.hero.gold = offer.gold - 1
  const before = JSON.stringify(state)
  assertEqual(JSON.stringify(World.apply(state, { type: "buy_material", offer: offer.id }, T0).state), before,
    "untouched")
})

test("selling takes from the chest, pays by tier, and never touches what is worn", () => {
  let state = freshState("human", "warrior")
  state.hero.chest = ["iron_sword", "core_sword"]
  state.hero.equipment.weapon = "rune_blade"
  const gold = state.hero.gold

  state = World.apply(state, { type: "sell_item", item: "core_sword" }, T0).state
  assertEqual(state.hero.chest.length, 1, "out of the chest")
  assertEqual(state.hero.gold, gold + Rules.SELL_PER_TIER * 3, "paid by tier")

  // The worn blade is not in the chest, so selling it does nothing.
  const worn = World.apply(state, { type: "sell_item", item: "rune_blade" }, T0)
  assertEqual(worn.state.hero.equipment.weapon, "rune_blade", "still worn")
  assertEqual(worn.state.hero.gold, state.hero.gold, "and nothing was paid for it")
})

test("the feat board reads the same numbers the events that grant them read", () => {
  // The board is a second opinion on every feat, and a second opinion is only
  // worth having while it agrees: a bar that fills to 10/10 without the feat
  // arriving is worse than no bar.
  const state = freshState("human", "warrior")
  state.day.counters.workspaces = 7
  state.day.counters.sessionMin = 480
  state.stats.forged = 3
  state.streak.count = 2
  state.hero.level = 9

  const board = Rules.achievementBoard(state)
  const by = id => board.find(f => f.id === id)

  assertEqual(board.length, Rules.ACHIEVEMENTS.length, "every feat is on it")
  assertEqual(by("explorer").progress, 7, "workspaces come from the day")
  assertEqual(by("explorer").target, 10, "and the rule says ten")
  assertEqual(by("smith").progress, 3, "forging counts for a life")
  assertEqual(by("constant").progress, 2, "the streak is read as it stands")
  assertEqual(by("myth").target, Rules.MAX_LEVEL, "the ceiling is the ceiling")
  assertEqual(by("first_blood").target, 0, "nothing to count on a first win")

  // Six materials held at once, which is the whole of that one.
  for (const m of Rules.MATERIALS) state.hero.materials[m] = 1
  assertEqual(Rules.achievementBoard(state).find(f => f.id === "collector").progress, 6,
    "one of each")

  // A day's counter rolls over at midnight; a feat earned does not roll back.
  state.achievements = ["explorer"]
  state.day.counters.workspaces = 0
  const earned = Rules.achievementBoard(state).find(f => f.id === "explorer")
  assertEqual(earned.done, true, "still earned")
  assertEqual(earned.progress, earned.target, "and still reads full")
  assertEqual(Rules.achievementBoard(state)[0].done, true, "earned ones sort first")
})

test("a win pays a breather, and never past full", () => {
  // Set up a fight one blow from won, at a chosen share of health.
  //
  // The assertion is on the fight, not on the hero: the same win can also
  // carry a level, and a level raises the maximum and the health with it. The
  // first version of this test read `hero.hp` afterwards and failed on a
  // number that was right for a reason it had not accounted for.
  function onePunchFrom(share) {
    let state = freshState("human", "warrior")
    const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
    state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state

    const top = Rules.hpMax(state.hero)
    const hp = Math.max(1, Math.round(top * share))
    state.hero.hp = hp
    state.arena.heroHp = hp
    state.arena.enemyHp = 1

    const after = World.apply(state, { type: "fight_action", action: "attack" }, T0).state
    return { before: hp, top: top, arena: after.arena }
  }

  const hurt = onePunchFrom(0.3)
  assertEqual(hurt.arena.outcome, "won", "the enemy had one point left")
  assertEqual(hurt.arena.healed, Math.round(hurt.top * Rules.WIN_HEAL), "the published share")
  assertEqual(hurt.arena.heroHp, hurt.before + hurt.arena.healed, "and it landed on the hero")

  const brimming = onePunchFrom(0.99)
  assertEqual(brimming.arena.heroHp, brimming.top, "capped at full, never past it")
  assertEqual(brimming.arena.healed, brimming.top - brimming.before, "only what was missing")
})

test("every calling has a weapon noun, in every dictionary", () => {
  // The three weapon recipes are templates now, so a class without a noun
  // renders "Iron {weapon}" in the forge and nobody finds out until they play
  // that class.
  const fs = require("fs")
  const path = require("path")
  const dir = path.join(__dirname, "..", "i18n")

  for (const file of fs.readdirSync(dir).filter((f) => f.endsWith(".json"))) {
    const dict = JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"))

    for (const cls of Rules.CLASS_IDS) {
      const key = Rules.weaponNoun({ cls: cls })
      assertEqual(key, "weapon.noun." + cls, "the key is built from the calling")
      if (!dict[key]) throw new Error(`${file}: no weapon noun for ${cls}`)
    }

    // And the templates have somewhere to put it.
    for (const recipe of Rules.RECIPES.filter((r) => r.slot === Rules.WEAPON_SLOT)) {
      const template = dict[Rules.itemNameKey(recipe.id)]
      if (!template || template.indexOf("{weapon}") === -1)
        throw new Error(`${file}: ${recipe.id} does not name the weapon`)
    }
  }

  // An unknown or missing calling still names something rather than crashing.
  assertEqual(Rules.weaponNoun(null), "weapon.noun.warrior", "a default")
  assertEqual(Rules.weaponNoun({ cls: "nonsense" }), "weapon.noun.warrior", "and for nonsense")
})

test("a stronger enemy is worth more experience than a weaker one", () => {
  // The whole reason to pick the hard one off the list.
  const hero = freshState("human", "warrior").hero
  const random = Rules.rng(1)
  const xp = (tier, boss) =>
    Rules.combatRewards(hero, Rules.enemyFor("goblin", tier, hero, boss), 0, random).xp

  const t1 = xp(1, false), t2 = xp(2, false), t3 = xp(3, false), boss = xp(4, true)
  if (!(t1 < t2 && t2 < t3 && t3 < boss))
    throw new Error(`experience does not rise with tier: ${t1}, ${t2}, ${t3}, boss ${boss}`)

  // And the gap is worth crossing, not a rounding difference.
  if (t3 < t1 * 2) throw new Error(`tier 3 pays ${t3} against tier 1 at ${t1}: not worth the risk`)
})

test("a second copy survives selling the first, and the count is conserved", () => {
  // The chest is a list with repeats, and the panel now prints how many of a
  // thing is in it. That number is only worth printing if the events keep it
  // honest: selling one of two has to leave one, and wearing one of two has
  // to leave one rather than swallowing both.
  let state = freshState("human", "warrior")
  state.hero.chest = ["iron_sword", "iron_sword", "core_sword"]
  state.hero.equipment.weapon = null

  const count = id => state.hero.chest.filter(x => x === id).length

  state = World.apply(state, { type: "sell_item", item: "iron_sword" }, T0).state
  assertEqual(count("iron_sword"), 1, "one sold, one left")

  state = World.apply(state, { type: "equip", item: "iron_sword" }, T0).state
  assertEqual(state.hero.equipment.weapon, "iron_sword", "worn")
  assertEqual(count("iron_sword"), 0, "and taken out of the chest, not copied")

  // Swapping puts the old one back, so nothing is destroyed by a change of mind.
  state = World.apply(state, { type: "equip", item: "core_sword" }, T0).state
  assertEqual(count("iron_sword"), 1, "the old blade came back")
  assertEqual(count("core_sword"), 0, "and the new one left the chest")

  state = World.apply(state, { type: "unequip", slot: "weapon" }, T0).state
  assertEqual(count("core_sword"), 1, "taking it off puts it back")
  assertEqual(state.hero.chest.length, 2, "two blades, which is what we started the swap with")
})

test("selling something back is worth less than buying its materials again", () => {
  // The merchant is not a laundry: a loop of forge, sell, buy, forge has to
  // lose money or it is an infinite one.
  for (const recipe of Rules.RECIPES) {
    let materialCost = 0
    for (const key of Object.keys(recipe.cost))
      materialCost += Rules.MATERIAL_PRICE[key] * recipe.cost[key]
    assert(Rules.itemValue(recipe) < materialCost,
      `${recipe.id} sells for ${Rules.itemValue(recipe)} but its materials cost ${materialCost}`)
  }
})

// ------------------------------------------------------------------ potions

test("a draught buys time: it heals, and it gets you off the tavern floor", () => {
  let state = freshState("human", "warrior")
  state.hero.potions.healing_draught = 1
  state.hero.hp = 0
  state.hero.hpUpdatedAt = T0
  state.hero.faintedUntil = T0 + Rules.TAVERN_SECONDS

  const result = World.apply(state, { type: "drink", potion: "healing_draught" }, T0)
  assertEqual(result.state.hero.faintedUntil, 0, "on your feet")
  assert(result.state.hero.hp > 0, "and healed")
  assertEqual(result.state.hero.potions.healing_draught, 0, "and it is gone")
})

test("a flask returns a point of energy and never more than the maximum", () => {
  let state = freshState()
  state.hero.potions.travellers_flask = 2
  state.hero.energy = 1
  state.hero.energyUpdatedAt = T0

  state = World.apply(state, { type: "drink", potion: "travellers_flask" }, T0).state
  assertEqual(state.hero.energy, 2, "one point")

  state.hero.energy = state.hero.energyMax
  const full = World.apply(state, { type: "drink", potion: "travellers_flask" }, T0)
  assertEqual(full.state.hero.potions.travellers_flask, state.hero.potions.travellers_flask,
    "a full hero keeps the flask rather than wasting it")
})

test("drinking at full health wastes nothing", () => {
  let state = freshState()
  state.hero.potions.healing_draught = 1
  state.hero.hp = state.hero.hpMax
  state.hero.hpUpdatedAt = T0

  const result = World.apply(state, { type: "drink", potion: "healing_draught" }, T0)
  assertEqual(result.state.hero.potions.healing_draught, 1, "kept")
  assertEqual(result.effects.length, 0, "and nothing happened")
})

test("drinking mid-fight moves the health the fight is reading", () => {
  let state = freshState("human", "warrior")
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state

  state.arena.heroHp = 5
  state.hero.hp = 5
  state.hero.hpUpdatedAt = T0
  state.hero.potions.healing_draught = 1

  const result = World.apply(state, { type: "drink", potion: "healing_draught" }, T0)
  assert(result.state.arena.heroHp > 5, "the fight sees it")
  assertEqual(result.state.arena.heroHp, result.state.hero.hp, "and agrees with the hero")
})

test("drinking what you do not have does nothing", () => {
  const state = freshState()
  const before = JSON.stringify(state)
  assertEqual(JSON.stringify(World.apply(state, { type: "drink", potion: "healing_draught" }, T0).state),
    before, "untouched")
})

test("potions cost gold and stack no higher than they should", () => {
  let state = freshState()
  state.hero.gold = 10000

  for (let i = 0; i < Rules.MAX_POTIONS + 3; i++)
    state = World.apply(state, { type: "buy_potion", potion: "healing_draught" }, T0).state

  assertEqual(state.hero.potions.healing_draught, Rules.MAX_POTIONS, "capped")
  assertEqual(state.hero.gold, 10000 - Rules.MAX_POTIONS * Rules.POTION_SPEC.healing_draught.price,
    "and paid for exactly what was delivered")
})

test("a potion survives a load", () => {
  let state = freshState()
  state.hero.potions.travellers_flask = 3
  const loaded = Migrations.run(JSON.parse(JSON.stringify(state)))
  assertEqual(loaded.hero.potions.travellers_flask, 3, "kept")

  const silly = freshState()
  silly.hero.potions = { travellers_flask: 999, unobtainium: 4 }
  const clean = Migrations.run(JSON.parse(JSON.stringify(silly)))
  assertEqual(clean.hero.potions.travellers_flask, Rules.MAX_POTIONS, "clamped")
  assertEqual(clean.hero.potions.unobtainium, undefined, "and nothing invented")
})

// ------------------------------------------------------ changing and starting over

test("changing class costs gold, keeps the level, and re-derives the attributes", () => {
  let state = freshState("human", "warrior")
  state.hero.level = 10
  state.hero.attrs = Rules.attrsFor("human", "warrior", 10)
  state.hero.gold = 150

  const result = World.apply(state, { type: "change_class", cls: "mage" }, T0)
  assertEqual(result.state.hero.cls, "mage", "changed")
  assertEqual(result.state.hero.level, 10, "level kept")
  assertEqual(result.state.hero.gold, 50, "a hundred gold")
  assertEqual(JSON.stringify(result.state.hero.attrs),
    JSON.stringify(Rules.attrsFor("human", "mage", 10)), "attributes re-derived")
})

test("changing class without the gold changes nothing", () => {
  const state = freshState("human", "warrior")
  state.hero.gold = 99
  const result = World.apply(state, { type: "change_class", cls: "mage" }, T0)
  assertEqual(result.state.hero.cls, "warrior", "unchanged")
  assertEqual(result.state.hero.gold, 99, "and the gold stays")
})

test("rebirth keeps what cannot be earned again", () => {
  let state = freshState("human", "warrior")
  state.hero.level = 12
  state.hero.gold = 300
  state.hero.materials.core = 4
  state.hero.equipment.weapon = "core_sword"
  state.achievements = ["first_blood", "survivor"]

  const result = World.apply(state, { type: "rebirth", race: "elf", cls: "bard" }, T0)
  assertEqual(result.state.hero.level, 1, "level one again")
  assertEqual(result.state.hero.xp, 0, "no experience")
  assertEqual(result.state.hero.race, "elf", "a different people")
  assertEqual(result.state.hero.cls, "bard", "a different calling")
  assertEqual(result.state.hero.equipment.weapon, null, "nothing worn")
  assertEqual(result.state.hero.materials.core, 4, "materials kept")
  assertEqual(result.state.hero.gold, 300, "gold kept")
  assertEqual(JSON.stringify(result.state.achievements), JSON.stringify(["first_blood", "survivor"]),
    "feats kept: they are the record of having been here")
})

test("rebirth drops a fight and a journey belonging to the old life", () => {
  let state = freshState()
  const wanderer = Rules.wanderers(state.day.date, state.hero.level)[0]
  state = World.apply(state, { type: "start_fight", kind: "wanderer", id: wanderer.id }, T0).state

  const result = World.apply(state, { type: "rebirth", race: "orc", cls: "druid" }, T0)
  assertEqual(result.state.arena, null, "no fight")
  assertEqual(result.state.expedition, null, "no journey")
})

test("every achievement in the list can actually be reached", () => {
  // A feat nobody can earn is worse than no feat: it sits in the list for ever
  // looking like something the player has missed.
  const granted = new Set()
  const source = fs.readFileSync(path.join(GAME_DIR, "World.js"), "utf8")
  for (const id of Rules.ACHIEVEMENTS)
    if (source.indexOf('"' + id + '"') !== -1) granted.add(id)

  const missing = Rules.ACHIEVEMENTS.filter((id) => !granted.has(id))
  assertEqual(missing.join(", "), "", "no feat is unreachable")
})

// ---------------------------------------------------------------- migrations

test("a fresh save survives a round trip through the migration chain", () => {
  const state = freshState("orc", "druid")
  const round = Migrations.run(JSON.parse(JSON.stringify(state)))
  assertEqual(round.hero.name, state.hero.name, "name")
  assertEqual(round.hero.race, "orc", "race")
  assertEqual(round.hero.cls, "druid", "class")
  assertEqual(round.version, Rules.SCHEMA_VERSION, "version stamped")
})

test("a save with no version is brought up to the current one", () => {
  const state = freshState()
  delete state.version
  assertEqual(Migrations.run(JSON.parse(JSON.stringify(state))).version, Rules.SCHEMA_VERSION, "stamped")
})

test("nonsense in a save is replaced rather than propagated", () => {
  const broken = {
    version: 1,
    hero: {
      name: "x".repeat(500), race: "dragon", cls: "necromancer", level: 9999,
      xp: -5, gold: NaN, hp: "lots", energy: 1e30,
      attrs: { str: 999, agi: 999, wis: 999, vit: 999, cha: 999 },
      equipment: { weapon: "excalibur", armor: null, amulet: null },
      chest: new Array(500).fill("iron_sword"),
      materials: { iron: -3, unobtainium: 10 }
    },
    realm: { name: "y".repeat(500), type: "spaceship" },
    day: { date: "not-a-date", counters: { workspaces: -1 }, quests: "nope" },
    streak: { count: -4, missedDays: 1e9 },
    bosses: new Array(50).fill({ id: "b", kind: "meteor", comm: "z".repeat(500), tier: 99, expiresAt: 2e10 }),
    achievements: ["first_blood", "first_blood", "being_cool"],
    stats: { totalXp: "many" }
  }

  const clean = Migrations.run(broken)

  assert(clean.hero.name.length <= 24, "name bounded")
  assertEqual(clean.hero.race, Rules.RACE_IDS[0], "unknown race falls back")
  assertEqual(clean.hero.cls, Rules.CLASS_IDS[0], "unknown class falls back")
  assertEqual(clean.hero.level, Rules.MAX_LEVEL, "level clamped to the cap")
  assertEqual(clean.hero.gold, 0, "NaN gold became zero")
  assert(isFinite(clean.hero.hp) && clean.hero.hp >= 0, "health is a number")
  assert(clean.hero.energy <= clean.hero.energyMax, "energy clamped")
  assertEqual(JSON.stringify(clean.hero.attrs), JSON.stringify(Rules.attrsFor(clean.hero.race, clean.hero.cls, clean.hero.level)),
    "attributes are derived, not taken from disk")
  assertEqual(clean.hero.equipment.weapon, null, "unknown equipment dropped")
  assert(clean.hero.chest.length <= 60, "chest bounded")
  assertEqual(clean.hero.materials.unobtainium, undefined, "unknown material dropped")
  assertEqual(clean.hero.materials.iron, 0, "negative material floored")
  assert(clean.realm.name.length <= 32, "realm name bounded")
  assertEqual(clean.realm.type, "caravan", "unknown realm type falls back")
  assert(/^\d{4}-\d{2}-\d{2}$/.test(clean.day.date), "the day has a real date")
  assertEqual(clean.day.quests.length, Rules.QUESTS_PER_DAY, "quests redrawn")
  assertEqual(clean.streak.count, 0, "negative streak floored")
  assert(clean.bosses.length <= Rules.MAX_ACTIVE_BOSSES, "bosses bounded")
  for (const boss of clean.bosses) {
    assert(boss.comm.length <= 32, "boss name bounded")
    assert(boss.tier <= Rules.BOSS_MAX_TIER, "boss tier clamped")
  }
  assertEqual(JSON.stringify(clean.achievements), JSON.stringify(["first_blood"]), "unknown and duplicate feats dropped")
  assertEqual(clean.stats.totalXp, 0, "unparseable stats become zero")
  assertEqual(clean.arena, null, "a fight never survives a load")
})

test("an expired boss is not carried across a load", () => {
  const state = freshState()
  state.bosses = [
    { id: "old", kind: "crash", comm: "a", tier: 3, hp: 1, hpMax: 1, spawnedAt: 0, expiresAt: 1, seen: true },
    { id: "live", kind: "crash", comm: "b", tier: 3, hp: 1, hpMax: 1, spawnedAt: 0, expiresAt: Rules.nowSec() + 86400, seen: false }
  ]
  const clean = Migrations.run(JSON.parse(JSON.stringify(state)))
  assertEqual(clean.bosses.length, 1, "one survivor")
  assertEqual(clean.bosses[0].id, "live", "the right one")
})

test("a save is never larger than the state directory budget", () => {
  let state = freshState("dwarf", "warrior")
  for (const key of Rules.MATERIALS) state.hero.materials[key] = 999
  state.hero.chest = new Array(60).fill("core_sword")
  state.achievements = Rules.ACHIEVEMENTS.slice()
  state.bosses = new Array(Rules.MAX_ACTIVE_BOSSES).fill(null).map((_, i) => ({
    id: "b" + i, kind: "crash", comm: "x".repeat(32), epithet: 1, tier: 4,
    hp: 99, hpMax: 99, spawnedAt: T0, expiresAt: T0 + 86400, seen: false
  }))
  const bytes = Buffer.byteLength(JSON.stringify(Migrations.run(state), null, 2))
  assert(bytes < 65536, `a maximal save is ${bytes} bytes, over the 64 KiB design budget`)
})

// ----------------------------------------------------------------- chronicle

test("a chronicle line is picked by seed and never changes", () => {
  const dictionary = {
    "chron.born.0": "zero {name}", "chron.born.1": "one {name}", "chron.born.2": "two {name}",
    "race.dwarf.name": "Dwarf", "class.mage.name": "Mage"
  }
  const t = (key, vars) => {
    const text = dictionary[key]
    if (text === undefined) return key
    if (!vars) return text
    return String(text).replace(/\{(\w+)\}/g, (match, name) => (vars[name] !== undefined ? String(vars[name]) : match))
  }

  const state = freshState("dwarf", "mage")
  assertEqual(Chronicle.variantCount(t, "born"), 3, "three variants found")

  for (const seed of [0, 1, 2, 3, 99, 918273]) {
    const entry = { ts: T0, type: "born", seed, p: { name: "Luiz" } }
    const first = Chronicle.render(entry, t, state)
    assertEqual(Chronicle.render(entry, t, state), first, "stable across renders")
    assert(first.indexOf("Luiz") !== -1, "the name is substituted")
    assert(first.indexOf("{") === -1, "no placeholder left behind")
  }
})

test("ids inside an entry are translated, not printed raw", () => {
  const dictionary = { "chron.born.0": "{race} {cls}", "race.orc.name": "Orc", "class.druid.name": "Druid" }
  const t = (key, vars) => {
    const text = dictionary[key]
    if (text === undefined) return key
    if (!vars) return text
    return String(text).replace(/\{(\w+)\}/g, (m, n) => (vars[n] !== undefined ? String(vars[n]) : m))
  }
  const line = Chronicle.render({ ts: T0, type: "born", seed: 0, p: { race: "orc", cls: "druid" } }, t, freshState("orc", "druid"))
  assertEqual(line, "Orc Druid", "translated")
})

test("the day's routine is summarised, not recited, and counts agree with its nouns", () => {
  const dictionary = {
    "digest.workspace_discovered.one": "1 province crossed",
    "digest.workspace_discovered.other": "{n} provinces crossed",
    "digest.rested.one": "1 rest",
    "digest.rested.other": "{n} rests",
    "chron.level_up.0": "level {level}"
  }
  const t = (key, vars) => {
    const text = dictionary[key]
    if (text === undefined) return key
    if (!vars) return text
    return String(text).replace(/\{(\w+)\}/g, (m, n) => (vars[n] !== undefined ? String(vars[n]) : m))
  }

  const now = T0
  const entries = []
  for (let i = 0; i < 14; i++) entries.push({ ts: now, type: "workspace_discovered", seed: i, p: {} })
  entries.push({ ts: now, type: "rested", seed: 1, p: {} })
  entries.push({ ts: now, type: "level_up", seed: 2, p: { level: 9 } })

  const days = Chronicle.groupByDay(entries, now)
  assertEqual(days.length, 1, "one day")
  assertEqual(days[0].notable.length, 1, "only the level-up is told properly")
  assertEqual(days[0].counts.workspace_discovered, 14, "the rest are counted")

  const summary = Chronicle.summarise(days[0], t)
  assertEqual(summary, "14 provinces crossed · 1 rest", "plural where it should be, singular where it should be")
})

test("the chronicle never shows more days than it promises", () => {
  const now = T0
  const entries = []
  for (let day = 0; day < 40; day++)
    entries.push({ ts: now - day * 86400, type: "level_up", seed: day, p: { level: day } })

  const days = Chronicle.groupByDay(entries, now)
  assert(days.length <= Chronicle.MAX_DAYS_SHOWN, `${days.length} days would be an archive, not a chronicle`)
})

test("grouping puts the newest day first and labels today and yesterday", () => {
  const now = T0
  const entries = [
    { ts: now - 86400 * 2, type: "born", seed: 1, p: {} },
    { ts: now - 86400, type: "rested", seed: 2, p: {} },
    { ts: now, type: "rested", seed: 3, p: {} }
  ]
  const groups = Chronicle.groupByDay(entries, now)
  assertEqual(groups.length, 3, "three days")
  assertEqual(groups[0].labelKey, "ui.today", "today first")
  assertEqual(groups[1].labelKey, "ui.yesterday", "then yesterday")
  assertEqual(groups[2].labelKey, "", "then a plain date")
})

// -------------------------------------------------------------------- report

if (failures.length) {
  for (const failure of failures) console.error(`FAIL  ${failure.name}\n      ${failure.error.message}`)
  console.error(`\n${passed} passed, ${failures.length} failed`)
  process.exit(1)
}
console.log(`${passed} passed`)
