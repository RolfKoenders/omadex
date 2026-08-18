.pragma library

// Pure list logic for the recently-viewed slug history. Ordering and
// resolution only — Dex.qml owns when a lookup counts as "viewed" and how
// the result gets persisted. See tests/test_recents.js.

var RECENTS_CAP = 10

// Moves slug to the front, deduping any existing occurrence, capped at
// RECENTS_CAP. Pure: returns a new array, never mutates slugs.
function bump(slugs, slug) {
  var next = [slug]
  var source = Array.isArray(slugs) ? slugs : []
  for (var i = 0; i < source.length; i++) {
    if (source[i] !== slug) next.push(source[i])
  }
  return next.slice(0, RECENTS_CAP)
}

// Resolves ordered slugs against the curated index (same shape
// IndexSearch.curateIndex produces) into row data ResultRow already knows
// how to render. A slug no longer present in the index is silently dropped
// rather than shown broken.
function resolveEntries(slugs, cachedEntries) {
  var byName = {}
  var entries = Array.isArray(cachedEntries) ? cachedEntries : []
  for (var i = 0; i < entries.length; i++) byName[entries[i].name] = entries[i]

  var resolved = []
  var source = Array.isArray(slugs) ? slugs : []
  for (var j = 0; j < source.length; j++) {
    var entry = byName[source[j]]
    if (entry) resolved.push(entry)
  }
  return resolved
}
