"use strict"

// Re-measures the arena and prints the numbers the design has to hold to.
//
// `node tools/balance.js`          report the current balance
// `node tools/balance.js --tune`   search for the per-class `combat.power`
//                                  constants in Rules.js and print them
//
// This exists because the combat formulas in the spec were written by hand and
// do not survive measurement: the first run of this script showed a 100% win
// rate at level 1 and a spread from 0% (bard) to 71% (rogue) by level 16. The
// constants in `CLASSES[*].combat` are the output of `--tune`, not a guess,
// and this script is how they get checked again after any change to damage,
// health or the skills.

const fs = require("fs")
const path = require("path")

const GAME_DIR = path.join(__dirname, "..", "game")
const loaded = new Map()

function load(name) {
  if (loaded.has(name)) return loaded.get(name)
  const source = fs.readFileSync(path.join(GAME_DIR, name), "utf8")
  const imports = []
  const body = source.split("\n").map((line) => {
    const directive = line.match(/^\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/)
    if (directive) { imports.push([directive[1], directive[2]]); return "" }
    return /^\.pragma\s+library\s*$/.test(line) ? "" : line
  }).join("\n")
  const module = { exports: {} }
  new Function(...imports.map(([, alias]) => alias), "module", body)(...imports.map(([file]) => load(file)), module)
  loaded.set(name, module.exports)
  return module.exports
}

const Rules = load("Rules.js")

// The pairings the design calls "the right tier at the right level".
const PAIRS = [[1, 1], [1, 4], [2, 8], [2, 12], [3, 16], [3, 20], [3, 25], [3, 30]]
const TRIALS = 800
const TARGET = 0.70
// A hair of slack on each end: a rate of exactly 0.55 must not fail on the
// float that `0.55 * 100` produces.
const BAND = [0.549, 0.851]

function heroOf(cls, level) {
  const hero = Rules.newHero("Tester", "human", cls, 0)
  hero.level = level
  hero.attrs = Rules.attrsFor("human", cls, level)
  hero.hpMax = Rules.hpMax(hero)
  hero.hp = hero.hpMax
  return hero
}

// The player the balance is tuned for: uses the skill whenever it is off
// cooldown, attacks otherwise, and defends when badly hurt. Not optimal play,
// but what someone clicking four buttons actually does.
function simulate(cls, level, tier, trials = TRIALS) {
  const hero = heroOf(cls, level)
  let wins = 0
  let turnsTotal = 0
  let longest = 0

  for (let round = 0; round < trials; round++) {
    const random = Rules.rng(round * 7919 + tier * 104729 + level * 31)
    const enemy = Rules.enemyFor("goblin", tier, hero)
    let fight = {
      enemy, enemyHp: enemy.hp, heroHp: hero.hpMax, turn: 0,
      cooldown: 0, enemySkipTurns: 0, dodgeNext: false, critNext: false
    }
    let turns = 0
    for (; turns < 60; turns++) {
      const lowHealth = fight.heroHp < hero.hpMax * 0.25
      const action = fight.cooldown <= 0 ? "skill" : (lowHealth ? "defend" : "attack")
      const step = Rules.combatRound(hero, fight, action, random)
      fight = Object.assign({}, fight, step)
      if (step.outcome === "won") { wins += 1; break }
      if (step.outcome === "lost") break
    }
    turnsTotal += turns + 1
    longest = Math.max(longest, turns + 1)
  }
  return { rate: wins / trials, turns: turnsTotal / trials, longest }
}

function report() {
  let worst = 0
  let outOfBand = 0

  console.log("Win rate and average turns, by class, at the tier the design pairs with the level.\n")
  console.log("            " + Rules.CLASS_IDS.map((c) => c.padStart(13)).join(""))

  for (const [tier, level] of PAIRS) {
    const cells = Rules.CLASS_IDS.map((cls) => {
      const s = simulate(cls, level, tier)
      worst = Math.max(worst, s.longest)
      if (s.rate < BAND[0] || s.rate > BAND[1]) outOfBand += 1
      const flag = (s.rate < BAND[0] || s.rate > BAND[1]) ? "!" : " "
      return `${(s.rate * 100).toFixed(0)}%/${s.turns.toFixed(1)}t${flag}`.padStart(13)
    })
    console.log(`tier ${tier} lv ${String(level).padEnd(2)} ${cells.join("")}`)
  }

  const cells = PAIRS.length * Rules.CLASS_IDS.length
  // Proportional, not a fixed count: the grid grows with every class added,
  // and a gate of "at most eight" silently got stricter when the archer
  // arrived and took it from forty cells to forty-eight.
  const allowed = Math.floor(cells * 0.25)

  console.log(`\nlongest fight seen: ${worst} turns (budget 12)`)
  console.log(`cells outside 55-85%: ${outOfBand} of ${cells} (at most ${allowed} allowed)`)

  // Not every cell lands in the band, and none of them has to: a six-turn
  // fight quantises hard, so one turn either way moves a cell by tens of
  // percent. The gate is that three quarters of the grid holds and that no
  // fight outruns its twelve-turn budget.
  return outOfBand <= allowed && worst <= 12
}

// `power` multiplies the enemy's health, so raising it makes the class's
// fights longer and its win rate lower. Bisect on the class's average win rate
// across every pairing.
function tune() {
  const out = {}
  for (const cls of Rules.CLASS_IDS) {
    let low = 0.3
    let high = 3.0
    for (let step = 0; step < 24; step++) {
      const mid = (low + high) / 2
      Rules.CLASSES[cls].combat.power = mid
      let total = 0
      for (const [tier, level] of PAIRS) total += simulate(cls, level, tier, 400).rate
      const average = total / PAIRS.length
      if (average > TARGET) low = mid
      else high = mid
    }
    out[cls] = Math.round(((low + high) / 2) * 1000) / 1000
    Rules.CLASSES[cls].combat.power = out[cls]
  }

  console.log("Calibrated CLASSES[*].combat.power — paste into game/Rules.js:\n")
  for (const cls of Rules.CLASS_IDS) console.log(`  ${cls.padEnd(9)} combat: { power: ${out[cls]} }`)
  console.log()
  return out
}

if (process.argv.indexOf("--tune") !== -1) {
  tune()
  console.log("--- with those constants applied ---\n")
}

process.exit(report() ? 0 : 1)
