import { readFileSync } from "node:fs"
import { runBench } from "./bench-movegen.mjs"
runBench(readFileSync(new URL("../dictionary/data/open-fr.dawg", import.meta.url), "utf8"), console.log)
