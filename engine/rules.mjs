// Rulesets. Everything a tournament organiser or a house rule might change
// lives here, so the engine reads a value instead of hard-coding it.
//
// normalizeRules() is the only way rules enter the engine: it fills defaults,
// clamps numbers and drops unknown values, so a saved game or a settings file
// cannot smuggle in an inconsistent ruleset.

export const VALIDATION = Object.freeze({
  IMMEDIATE: "immediate", // invalid words are refused when played
  CHALLENGE: "challenge"  // moves stand until an opponent challenges them
})

export const CHALLENGE_PENALTY = Object.freeze({
  NONE: "none",           // a failed challenge costs nothing
  POINTS: "points",       // the challenger loses `penaltyPoints`
  LOSE_TURN: "lose_turn"  // the challenger loses their turn ("double challenge")
})

export const TIMEOUT_POLICY = Object.freeze({
  END_GAME: "end_game",   // the game stops when a clock reaches zero
  PENALTY: "penalty"      // play continues; overtime costs points at the end
})

export const DEFAULT_RULES = Object.freeze({
  id: "fr-classic",
  tileset: "fr-classic",
  rackSize: 7,
  bingoTiles: 7,
  bingoBonus: 50,
  minWordLength: 2,
  exchangeMinBag: 7,
  validation: VALIDATION.IMMEDIATE,
  challenge: Object.freeze({ penalty: CHALLENGE_PENALTY.NONE, penaltyPoints: 10 }),
  endGame: Object.freeze({
    scorelessRounds: 3,   // the game ends after this many full rounds without a score
    outBonus: true,       // whoever goes out adds the others' remaining tiles
    remainingPenalty: true
  }),
  time: Object.freeze({
    totalMs: 0,           // per player; 0 = no clock
    onTimeout: TIMEOUT_POLICY.END_GAME,
    overtimePenaltyPerMinute: 10
  })
})

function pickInt(value, fallback, min, max) {
  const n = Number(value)
  if (!Number.isFinite(n)) return fallback
  return Math.max(min, Math.min(max, Math.round(n)))
}

function pickEnum(value, allowed, fallback) {
  const values = Object.keys(allowed).map(function(k) { return allowed[k] })
  return values.indexOf(value) !== -1 ? value : fallback
}

function pickBool(value, fallback) {
  return typeof value === "boolean" ? value : fallback
}

export function normalizeRules(input) {
  const src = input && typeof input === "object" ? input : {}
  const d = DEFAULT_RULES
  const challenge = src.challenge && typeof src.challenge === "object" ? src.challenge : {}
  const endGame = src.endGame && typeof src.endGame === "object" ? src.endGame : {}
  const time = src.time && typeof src.time === "object" ? src.time : {}
  const rackSize = pickInt(src.rackSize, d.rackSize, 1, 10)
  return {
    id: typeof src.id === "string" && src.id ? src.id.slice(0, 64) : d.id,
    tileset: typeof src.tileset === "string" && src.tileset ? src.tileset.slice(0, 64) : d.tileset,
    rackSize: rackSize,
    bingoTiles: pickInt(src.bingoTiles, Math.min(d.bingoTiles, rackSize), 1, rackSize),
    bingoBonus: pickInt(src.bingoBonus, d.bingoBonus, 0, 1000),
    minWordLength: pickInt(src.minWordLength, d.minWordLength, 2, 15),
    exchangeMinBag: pickInt(src.exchangeMinBag, d.exchangeMinBag, 0, 100),
    validation: pickEnum(src.validation, VALIDATION, d.validation),
    challenge: {
      penalty: pickEnum(challenge.penalty, CHALLENGE_PENALTY, d.challenge.penalty),
      penaltyPoints: pickInt(challenge.penaltyPoints, d.challenge.penaltyPoints, 0, 1000)
    },
    endGame: {
      scorelessRounds: pickInt(endGame.scorelessRounds, d.endGame.scorelessRounds, 1, 20),
      outBonus: pickBool(endGame.outBonus, d.endGame.outBonus),
      remainingPenalty: pickBool(endGame.remainingPenalty, d.endGame.remainingPenalty)
    },
    time: {
      totalMs: pickInt(time.totalMs, d.time.totalMs, 0, 24 * 3600 * 1000),
      onTimeout: pickEnum(time.onTimeout, TIMEOUT_POLICY, d.time.onTimeout),
      overtimePenaltyPerMinute: pickInt(time.overtimePenaltyPerMinute, d.time.overtimePenaltyPerMinute, 0, 1000)
    }
  }
}

export function hasClock(rules) {
  return rules.time.totalMs > 0
}
