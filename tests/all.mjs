// Every test suite, imported statically so the list works under Node and
// under the QML engine alike. Add new suites here.

import * as board from "./board.test.mjs"
import * as scoring from "./scoring.test.mjs"
import * as bag from "./bag.test.mjs"
import * as validation from "./validation.test.mjs"
import * as endgame from "./endgame.test.mjs"
import * as serializer from "./serializer.test.mjs"
import * as dictionary from "./dictionary.test.mjs"
import * as ai from "./ai.test.mjs"
import * as aiplayer from "./aiplayer.test.mjs"
import * as stats from "./stats.test.mjs"
import * as settings from "./settings.test.mjs"
import * as i18n from "./i18n.test.mjs"
import * as online from "./online.test.mjs"

export const SUITES = [board, scoring, bag, validation, endgame, serializer, dictionary, ai, aiplayer, stats, settings, i18n, online]
