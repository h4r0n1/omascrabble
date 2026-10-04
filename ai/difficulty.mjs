// DifficultyProfile: what separates a beginner from a champion. Every profile
// plays by the same rules with the same tiles and the same information (its
// own rack, the board, the unseen-tile counts); they differ only in how much
// vocabulary they use, how far they search and how they judge a move.

export const DIFFICULTIES = Object.freeze(["beginner", "casual", "expert", "champion"])

export const DIFFICULTY_LABELS = Object.freeze({
  beginner: "Débutant",
  casual: "Casual",
  expert: "Expert",
  champion: "Champion"
})

const PROFILES = {
  // Small vocabulary, short words, no strategy, regular slips.
  beginner: {
    id: "beginner",
    minTier: 3,             // only very common words
    maxTilesPreferred: 4,   // favours short plays
    candidatePool: 10,
    pick: "weighted",       // random among the pool, weighted towards mid scores
    mistakeRate: 0.2,
    leaveWeight: 0,
    defenseWeight: 0,
    premiumWeight: 0,
    exchangeWillingness: 0,
    simulation: null,
    endgame: "none",
    challengeAccuracy: 0.45,
    falseChallengeRate: 0.08,
    thinkMs: [700, 1500]
  },
  // Decent scores, moderate vocabulary, some sense of the board.
  casual: {
    id: "casual",
    minTier: 2,
    maxTilesPreferred: 7,
    candidatePool: 6,
    pick: "top-random",
    mistakeRate: 0.08,
    leaveWeight: 0.35,
    defenseWeight: 0.2,
    premiumWeight: 0.5,
    exchangeWillingness: 0.4,
    simulation: null,
    endgame: "basic",
    challengeAccuracy: 0.8,
    falseChallengeRate: 0.03,
    thinkMs: [800, 1800]
  },
  // Full vocabulary, rack leave, premium-square play, threat awareness.
  expert: {
    id: "expert",
    minTier: 0,
    maxTilesPreferred: 7,
    candidatePool: 3,
    pick: "best",
    mistakeRate: 0.02,
    leaveWeight: 1,
    defenseWeight: 1,
    premiumWeight: 1,
    exchangeWillingness: 1,
    simulation: null,
    endgame: "basic",
    challengeAccuracy: 1,
    falseChallengeRate: 0,
    thinkMs: [900, 2200]
  },
  // Expert judgement plus a look-ahead: each top candidate is tested against
  // sampled opponent racks drawn from the unseen tiles (no peeking), and the
  // endgame is searched exactly once the bag is empty.
  champion: {
    id: "champion",
    minTier: 0,
    maxTilesPreferred: 7,
    candidatePool: 10,
    pick: "best",
    mistakeRate: 0,
    leaveWeight: 1,
    defenseWeight: 1.2,
    premiumWeight: 1,
    exchangeWillingness: 1,
    simulation: { candidates: 8, samples: 10, replyWeight: 0.9 },
    endgame: "search",
    challengeAccuracy: 1,
    falseChallengeRate: 0,
    thinkMs: [1000, 4000]
  }
}

// Personalities tilt the judgement without changing the strength much.
export const PERSONALITIES = Object.freeze({
  balanced: { label: "Équilibré", leave: 1, defense: 1, premium: 1 },
  aggressive: { label: "Offensif", leave: 0.7, defense: 0.5, premium: 1.4 },
  cautious: { label: "Prudent", leave: 1.2, defense: 1.6, premium: 0.8 }
})

// thinkingScale stretches the time the AI takes (the "thinking time"
// setting): 0.5 = brisk, 1 = normal, 2 = deliberate.
export function profileFor(difficulty, options) {
  const base = PROFILES[difficulty] || PROFILES.casual
  const personality = PERSONALITIES[options && options.personality] || PERSONALITIES.balanced
  const scale = options && Number.isFinite(options.thinkingScale) ? Math.max(0.25, Math.min(3, options.thinkingScale)) : 1
  return Object.assign({}, base, {
    leaveWeight: base.leaveWeight * personality.leave,
    defenseWeight: base.defenseWeight * personality.defense,
    premiumWeight: base.premiumWeight * personality.premium,
    thinkMs: [Math.round(base.thinkMs[0] * scale), Math.round(base.thinkMs[1] * scale)],
    personality: options && PERSONALITIES[options.personality] ? options.personality : "balanced"
  })
}
