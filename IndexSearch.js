.pragma library

// Curates the raw PokeAPI /pokemon bulk list into a searchable index, and
// filters that cached index by keystroke. Both are pure and local — no
// network call ever happens on a keystroke. See tests/test_index_search.js.

var RESULT_LIMIT = 50

// Variants excluded from search because they add no value for THIS tool's
// purpose — checking type matchups. Weaknesses depend only on type, not
// stats, so a form whose type is identical to the one it's a variant of is
// excluded even when its stats differ slightly: it would show byte-for-byte
// identical weaknesses to the form it's cluttering search results next to.
// True cosmetic variants (identical stats AND type) are the simpler case of
// the same rule. Verified against the live PokeAPI index, not guessed — see
// the plan's build notes for the specific entries checked. This list is
// deliberately not exhaustive; expand it if a spot-check of a real curated
// index turns up more clutter.
var COSMETIC_FORM_EXCLUSIONS = [
  /^pikachu-.*-cap$/i,
  // Pokemon GO / event costume Pikachu — same stats/typing as base Pikachu,
  // but these don't end in "-cap" so the pattern above misses them.
  /^pikachu-(cosplay|rock-star|belle|pop-star|phd|libre)$/i,
  // Let's Go Pikachu/Eevee's special partner Pokemon: same type as the base
  // species (Electric, Normal respectively), only a minor stat bump — same
  // weakness profile as the regular form, so not worth a separate entry.
  /^(pikachu|eevee)-starter$/i,
  /-gmax$/i,
  // Minior's meteor shell colors, and its cracked-shell "core" colors, are
  // each a set of 7 cosmetic recolors of each other (identical stats and
  // typing within each set) — drop 6 of the 7 colors in both sets first.
  /^minior-(orange|yellow|green|blue|indigo|violet)(-meteor)?$/i,
  // Both surviving Minior forms (meteor and core "red") are Rock/Flying —
  // identical weakness profile despite the defense-stat difference between
  // them, so keep only the meteor form (the one actually encountered as a
  // wild Pokemon; core is a mid-battle break state, not a separate sighting).
  /^minior-red$/i,
  /^basculin-(blue|white)-striped$/i
]

function isCosmetic(name) {
  for (var i = 0; i < COSMETIC_FORM_EXCLUSIONS.length; i++) {
    if (COSMETIC_FORM_EXCLUSIONS[i].test(name)) return true
  }
  return false
}

function idFromUrl(url) {
  var match = /\/(\d+)\/?$/.exec(String(url || ""))
  return match ? parseInt(match[1], 10) : 0
}

function labelFromName(name) {
  var words = String(name || "").split("-")
  for (var i = 0; i < words.length; i++) {
    words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
  }
  return words.join(" ")
}

// Alternate forms get raw ids >= 10000, which isn't the National Dex number
// a player would type. Derive the real number locally by finding the lowest
// raw id among entries sharing this form's first hyphen segment — no extra
// network request. Must run before exclusion: a donor like
// "minior-red-meteor" can be the correct number source for a kept entry
// like "minior-red" even though the donor itself gets excluded from the
// index. Falls back to the form's own raw id if no donor is found.
function deriveNumbers(rawEntries) {
  var lowestByPrefix = {}
  for (var i = 0; i < rawEntries.length; i++) {
    var id = idFromUrl(rawEntries[i].url)
    var prefix = rawEntries[i].name.split("-")[0]
    if (id > 0 && id < 10000 && (lowestByPrefix[prefix] === undefined || id < lowestByPrefix[prefix])) {
      lowestByPrefix[prefix] = id
    }
  }
  var numbers = {}
  for (var j = 0; j < rawEntries.length; j++) {
    var entry = rawEntries[j]
    var rawId = idFromUrl(entry.url)
    if (rawId < 10000) {
      numbers[entry.name] = rawId
      continue
    }
    var donorPrefix = entry.name.split("-")[0]
    numbers[entry.name] = lowestByPrefix[donorPrefix] !== undefined
      ? lowestByPrefix[donorPrefix] : rawId
  }
  return numbers
}

function curateIndex(rawEntries) {
  var entries = Array.isArray(rawEntries) ? rawEntries : []
  var numbers = deriveNumbers(entries)
  var curated = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (!entry || typeof entry.name !== "string" || isCosmetic(entry.name)) continue
    curated.push({
      name: entry.name,
      label: labelFromName(entry.name),
      number: numbers[entry.name],
      spriteId: idFromUrl(entry.url)
    })
  }
  return curated
}

function filterIndex(index, query) {
  var needle = String(query || "").trim().toLowerCase()
  var entries = Array.isArray(index) ? index : []
  if (!needle) return []

  var matches = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (entry.name.toLowerCase().indexOf(needle) !== -1
        || entry.label.toLowerCase().indexOf(needle) !== -1
        || String(entry.number).indexOf(needle) !== -1) {
      matches.push(entry)
      if (matches.length >= RESULT_LIMIT) break
    }
  }
  return matches
}
