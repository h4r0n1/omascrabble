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

const NBSP = " "

const MESSAGES = {
  OK: "Coup valide",
  NO_TILES: "Posez au moins une lettre.",
  TOO_MANY_TILES: "Vous ne pouvez pas poser plus de lettres que votre chevalet n’en contient.",
  BAD_PLACEMENT: "Placement invalide.",
  OUT_OF_BOUNDS: "Cette case est hors du plateau.",
  CELL_OCCUPIED: "Cette case est déjà occupée.",
  DUPLICATE_TILE: "Le même jeton est utilisé deux fois.",
  DUPLICATE_POSITION: "Deux jetons sont posés sur la même case.",
  TILE_NOT_OWNED: "Ce jeton n’est pas sur votre chevalet.",
  JOKER_LETTER_MISSING: "Choisissez la lettre que représente le joker.",
  JOKER_LETTER_INVALID: "Un joker représente une lettre de A à Z.",
  NOT_A_JOKER: "Seul un joker peut représenter une autre lettre.",
  NOT_IN_LINE: "Les lettres doivent être sur une même ligne ou une même colonne.",
  GAP_IN_WORD: "Les lettres posées ne doivent pas laisser de trou.",
  FIRST_MOVE_NOT_ON_CENTER: "Le premier mot doit passer par l’étoile centrale.",
  NOT_CONNECTED: "Le mot doit toucher une lettre déjà posée.",
  SINGLE_LETTER: "Un mot compte au moins deux lettres.",
  INVALID_WORD: "Mot invalide",
  INVALID_CROSS_WORD: "Mot croisé invalide",
  DICTIONARY_UNAVAILABLE: "Le dictionnaire n’est pas disponible.",
  GAME_OVER: "La partie est terminée.",
  NOT_YOUR_TURN: "Ce n’est pas votre tour.",
  UNKNOWN_ACTION: "Action inconnue.",
  BAG_TOO_SMALL: "L’échange n’est possible que s’il reste au moins 7 lettres dans le sac.",
  NOTHING_TO_EXCHANGE: "Choisissez au moins une lettre à échanger.",
  NO_PENDING_MOVE: "Il n’y a aucun coup à contester.",
  CHALLENGE_PENDING: "Le coup précédent peut encore être contesté.",
  TIME_NOT_EXPIRED: "Le temps n’est pas écoulé.",
  BAD_PLAYER: "Joueur inconnu."
}

export function messageFor(reason, detail) {
  const base = MESSAGES[reason] || "Coup invalide"
  if ((reason === REASON.INVALID_WORD || reason === REASON.INVALID_CROSS_WORD) && detail && detail.length)
    return base + NBSP + ": " + detail.join(", ")
  if (reason === REASON.BAG_TOO_SMALL && Number.isInteger(detail))
    return "L’échange n’est possible que s’il reste au moins " + detail + " lettres dans le sac."
  return base
}
