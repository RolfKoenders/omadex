.pragma library

// Curates the raw PokeAPI /pokemon bulk list into a searchable index, and
// filters that cached index by keystroke. Both are pure and local — no
// network call ever happens on a keystroke. See tests/test_index_search.js.

var RESULT_LIMIT = 50

// Excluded because they add no value for checking type matchups: weaknesses
// depend only on type, so a variant is excluded once its type matches the
// form it's based on, even if its stats differ. Verified against the live
// PokeAPI index, not guessed. Not exhaustive; expand as needed.
var COSMETIC_FORM_EXCLUSIONS = [
  /^pikachu-.*-cap$/i,
  // Costume Pikachu that don't end in "-cap".
  /^pikachu-(cosplay|rock-star|belle|pop-star|phd|libre)$/i,
  // Let's Go partner Pokemon: same type as the base species, minor stat bump.
  /^(pikachu|eevee)-starter$/i,
  /-gmax$/i,
  // Minior's meteor and core color sets are each 7 cosmetic recolors of each
  // other; drop 6 of 7 in both sets.
  /^minior-(orange|yellow|green|blue|indigo|violet)(-meteor)?$/i,
  // Both surviving Minior forms are Rock/Flying regardless of the defense
  // difference between them, so keep only the meteor form.
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

// Alternate forms get raw ids >= 10000, not the National Dex number a
// player would type. Derive it locally as the lowest raw id sharing this
// form's first hyphen segment, run before exclusion so an excluded entry
// can still donate a number. Falls back to the form's own id if no donor.
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
