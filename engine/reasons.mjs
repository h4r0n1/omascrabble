// Structured result codes shared by the validator and the engine, with the
// French messages shown to players. Codes are stable identifiers (tests and
// saved games use them); messages are presentation.

export const REASON = Object.freeze({
  OK: "OK",
  NO_TILES: "NO_TILES",
  TOO_MANY_TILES: "TOO_MANY_TILES",
  BAD_PLACEMENT: "BAD_PLACEMENT",
  OUT_OF_BOUNDS: "OUT_OF_BOUNDS",
  CELL_OCCUPIED: "CELL_OCCUPIED",
  DUPLICATE_TILE: "DUPLICATE_TILE",
  DUPLICATE_POSITION: "DUPLICATE_POSITION",
  TILE_NOT_OWNED: "TILE_NOT_OWNED",
  JOKER_LETTER_MISSING: "JOKER_LETTER_MISSING",
  JOKER_LETTER_INVALID: "JOKER_LETTER_INVALID",
  NOT_A_JOKER: "NOT_A_JOKER",
  NOT_IN_LINE: "NOT_IN_LINE",
  GAP_IN_WORD: "GAP_IN_WORD",
  FIRST_MOVE_NOT_ON_CENTER: "FIRST_MOVE_NOT_ON_CENTER",
  NOT_CONNECTED: "NOT_CONNECTED",
  SINGLE_LETTER: "SINGLE_LETTER",
  INVALID_WORD: "INVALID_WORD",
  INVALID_CROSS_WORD: "INVALID_CROSS_WORD",
  DICTIONARY_UNAVAILABLE: "DICTIONARY_UNAVAILABLE",
  // Engine-level outcomes.
  GAME_OVER: "GAME_OVER",
  NOT_YOUR_TURN: "NOT_YOUR_TURN",
  UNKNOWN_ACTION: "UNKNOWN_ACTION",
  BAG_TOO_SMALL: "BAG_TOO_SMALL",
  NOTHING_TO_EXCHANGE: "NOTHING_TO_EXCHANGE",
  NO_PENDING_MOVE: "NO_PENDING_MOVE",
  CHALLENGE_PENDING: "CHALLENGE_PENDING",
  TIME_NOT_EXPIRED: "TIME_NOT_EXPIRED",
  BAD_PLAYER: "BAD_PLAYER"
})

// Developer-facing English text for logs and tests. Players see the
// interface catalogs ("reason.<CODE>"), which translate these codes.
const MESSAGES = {
  OK: "Valid move",
  NO_TILES: "Place at least one tile.",
  TOO_MANY_TILES: "More tiles than the rack holds.",
  BAD_PLACEMENT: "Invalid placement.",
  OUT_OF_BOUNDS: "Square off the board.",
  CELL_OCCUPIED: "Square already taken.",
  DUPLICATE_TILE: "Same tile used twice.",
  DUPLICATE_POSITION: "Two tiles on one square.",
  TILE_NOT_OWNED: "Tile not on the player's rack.",
  JOKER_LETTER_MISSING: "Blank needs a letter.",
  JOKER_LETTER_INVALID: "Blank letter must be A-Z.",
  NOT_A_JOKER: "Only a blank takes a letter.",
  NOT_IN_LINE: "Tiles not in one line.",
  GAP_IN_WORD: "Gap between placed tiles.",
  FIRST_MOVE_NOT_ON_CENTER: "First word must cover the centre.",
  NOT_CONNECTED: "Word not connected.",
  SINGLE_LETTER: "No word of two letters or more.",
  INVALID_WORD: "Invalid word",
  INVALID_CROSS_WORD: "Invalid cross word",
  DICTIONARY_UNAVAILABLE: "Dictionary unavailable.",
  GAME_OVER: "Game over.",
  NOT_YOUR_TURN: "Not this player's turn.",
  UNKNOWN_ACTION: "Unknown action.",
  BAG_TOO_SMALL: "Bag too small to exchange.",
  NOTHING_TO_EXCHANGE: "Nothing to exchange.",
  NO_PENDING_MOVE: "No move to challenge.",
  CHALLENGE_PENDING: "Previous move can still be challenged.",
  TIME_NOT_EXPIRED: "Time has not run out.",
  BAD_PLAYER: "Unknown player."
}

export function messageFor(reason, detail) {
  const base = MESSAGES[reason] || "Invalid move"
  if ((reason === REASON.INVALID_WORD || reason === REASON.INVALID_CROSS_WORD) && detail && detail.length)
    return base + ": " + detail.join(", ")
  return base
}
