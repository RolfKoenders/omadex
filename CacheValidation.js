.pragma library

// Pure staleness and shape decisions for the on-disk caches. Tested against
// fixture JSON objects only — never against real files. See
// tests/test_cache_validation.js.

var INDEX_TTL_MS = 30 * 24 * 60 * 60 * 1000

function isIndexStale(fetchedAtMs, nowMs, ttlMs) {
  if (typeof fetchedAtMs !== "number" || !isFinite(fetchedAtMs)) return true
  return (nowMs - fetchedAtMs) > ttlMs
}

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function isStringArray(value) {
  if (!Array.isArray(value)) return false
  for (var i = 0; i < value.length; i++) {
    if (typeof value[i] !== "string") return false
  }
  return true
}

function isValidIndexShape(parsed) {
  if (!isPlainObject(parsed)) return false
  if (typeof parsed.fetchedAt !== "number") return false
  if (!Array.isArray(parsed.entries)) return false
  for (var i = 0; i < parsed.entries.length; i++) {
    var entry = parsed.entries[i]
    if (!isPlainObject(entry)) return false
    if (typeof entry.name !== "string") return false
    if (typeof entry.label !== "string") return false
    if (typeof entry.number !== "number") return false
    if (typeof entry.spriteId !== "number") return false
  }
  return true
}

function isValidDetailShape(parsed) {
  if (!isPlainObject(parsed)) return false
  if (typeof parsed.id !== "number") return false
  if (typeof parsed.label !== "string") return false
  if (typeof parsed.speciesName !== "string") return false
  if (typeof parsed.dexNumberPadded !== "string") return false
  if (typeof parsed.spriteUrl !== "string") return false
  if (typeof parsed.shinySpriteUrl !== "string") return false
  if (typeof parsed.heightM !== "number") return false
  if (typeof parsed.weightKg !== "number") return false
  if (!isStringArray(parsed.types) || parsed.types.length === 0) return false
  if (!Array.isArray(parsed.abilities)) return false
  if (!Array.isArray(parsed.stats)) return false
  if (!isPlainObject(parsed.weaknesses)) return false
  return true
}

function isValidEvolutionShape(parsed) {
  if (!isPlainObject(parsed)) return false
  if (!isPlainObject(parsed.chain)) return false
  if (!isPlainObject(parsed.chain.species) || typeof parsed.chain.species.name !== "string") return false
  return Array.isArray(parsed.chain.evolves_to)
}

function isValidRecentsShape(parsed) {
  if (!isPlainObject(parsed)) return false
  return isStringArray(parsed.slugs)
}

function isValidTypeChartShape(parsed) {
  if (!isPlainObject(parsed)) return false
  var typeNames = Object.keys(parsed)
  for (var i = 0; i < typeNames.length; i++) {
    var relations = parsed[typeNames[i]]
    if (!isPlainObject(relations)) return false
    if (!isStringArray(relations.double_damage_from)) return false
    if (!isStringArray(relations.half_damage_from)) return false
    if (!isStringArray(relations.no_damage_from)) return false
  }
  return true
}
