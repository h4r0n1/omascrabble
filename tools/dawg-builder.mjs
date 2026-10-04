// Build-time helpers on top of dictionary/dawg-builder.mjs.

import { DAWG_FORMAT, DAWG_VERSION, checksumEdges } from "../dictionary/dawg.mjs"
export { DawgBuilder } from "../dictionary/dawg-builder.mjs"

export function encodeDawgFile(packed, alphabet, tierBits, meta) {
  const header = Object.assign({}, meta, {
    format: DAWG_FORMAT,
    version: DAWG_VERSION,
    alphabet: alphabet,
    letterBits: packed.letterBits,
    tierBits: tierBits,
    edges: packed.edges.length,
    root: packed.root,
    words: packed.words,
    checksum: checksumEdges(packed.edges)
  })
  // The file format is little-endian whatever machine builds it.
  const bytes = Buffer.alloc(packed.edges.length * 4)
  for (let i = 0; i < packed.edges.length; i++) bytes.writeUInt32LE(packed.edges[i], i * 4)
  return JSON.stringify(header) + "\n" + bytes.toString("base64") + "\n"
}
