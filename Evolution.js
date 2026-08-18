.pragma library

// Pure evolution-chain logic: locating a species within a fetched chain and
// turning PokeAPI's raw trigger fields into readable text. Fully
// self-contained (a local titleCase rather than importing PokemonDetail.js's
// near-identical helper) — plain Node has no QML module resolution, so pure
// modules duplicate small formatting helpers instead of cross-importing.
// See tests/test_evolution.js.

function titleCase(name) {
  var words = String(name || "").split("-")
  for (var i = 0; i < words.length; i++) {
    words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
  }
  return words.join(" ")
}

function chainIdFromUrl(url) {
  var match = /\/evolution-chain\/(\d+)\/?$/.exec(String(url || ""))
  return match ? parseInt(match[1], 10) : 0
}

// Common cases get clean text; anything else (the ~11 exotic triggers, or a
// modifier this doesn't specifically handle, like a required move or
// location) falls back to a humanized version of the trigger's own name.
// A deliberate v1 simplification, not an exhaustive mapping of every field
// PokeAPI exposes.
function describeTrigger(detail) {
  if (!detail || !detail.trigger) return ""
  var trigger = detail.trigger.name

  if (trigger === "level-up") {
    if (detail.min_level) return "Level " + detail.min_level
    // No own parens: the caller already wraps this in "Evolves into X (...)".
    if (detail.time_of_day === "day") return "Level up, day"
    if (detail.time_of_day === "night") return "Level up, night"
    if (detail.min_happiness) return "High friendship"
    return "Level up"
  }
  if (trigger === "use-item") {
    return detail.item ? titleCase(detail.item.name) : "Use an item"
  }
  if (trigger === "trade") {
    return detail.held_item ? "Trade holding " + titleCase(detail.held_item.name) : "Trade"
  }
  return titleCase(trigger || "other")
}

// spriteId for a species name, resolved against the curated index (the same
// shape IndexSearch.curateIndex produces). Defensive: evolution targets
// should always be real curated-index entries, but never assume — falls
// back to 0 (EvolutionNode.qml treats that as "no sprite available").
function spriteIdFor(name, cachedEntries) {
  var entries = Array.isArray(cachedEntries) ? cachedEntries : []
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].name === name) return entries[i].spriteId
  }
  return 0
}

// Finds speciesName in chain and returns its immediate neighbors only, not
// the full multi-stage/branching tree — kept deliberately compact for the
// popup's tight vertical space. A branch with more than one evolution_details
// entry (different version groups reaching the same species) uses the first.
function neighborsFor(chain, speciesName, cachedEntries) {
  function walk(node, parentName) {
    if (node.species.name === speciesName) {
      var to = []
      for (var i = 0; i < node.evolves_to.length; i++) {
        var child = node.evolves_to[i]
        to.push({
          name: child.species.name,
          label: titleCase(child.species.name),
          spriteId: spriteIdFor(child.species.name, cachedEntries),
          condition: describeTrigger(child.evolution_details[0])
        })
      }
      return {
        // node.evolution_details (not the parent's) describes how this
        // node itself evolved from its parent — the label for the from arrow.
        from: parentName ? {
          name: parentName,
          label: titleCase(parentName),
          spriteId: spriteIdFor(parentName, cachedEntries),
          condition: describeTrigger(node.evolution_details[0])
        } : null,
        to: to
      }
    }
    for (var j = 0; j < node.evolves_to.length; j++) {
      var found = walk(node.evolves_to[j], node.species.name)
      if (found) return found
    }
    return null
  }
  return walk(chain, null)
}

// True only if no node anywhere in chain has more than one evolves_to
// entry — i.e. the whole family is a single path with no branch point,
// computed once per chain rather than per lookup.
function isLinear(chain) {
  if (chain.evolves_to.length > 1) return false
  for (var i = 0; i < chain.evolves_to.length; i++) {
    if (!isLinear(chain.evolves_to[i])) return false
  }
  return true
}

// Walks a (by definition, for a linear chain) single-path chain root to
// leaf. condition on entry i (i>0) is that node's own evolution_details —
// the transition into it, not out of it. The root has no condition.
function flattenLinear(chain, cachedEntries) {
  var path = []
  var node = chain
  var condition = ""
  while (node) {
    path.push({
      name: node.species.name,
      label: titleCase(node.species.name),
      spriteId: spriteIdFor(node.species.name, cachedEntries),
      condition: condition
    })
    if (node.evolves_to.length === 0) break
    var child = node.evolves_to[0]
    condition = describeTrigger(child.evolution_details[0])
    node = child
  }
  return path
}

// Entry point Dex.qml calls. Linear families (the common case, at most 3
// stages in practice) get their full chain rendered as one strip; branching
// families (Eevee-shaped) keep the immediate-neighbors-only treatment,
// since fully flattening a tree with multiple branch points doesn't fit a
// single horizontal strip.
function chainFor(chain, speciesName, cachedEntries) {
  if (isLinear(chain)) {
    var path = flattenLinear(chain, cachedEntries)
    var currentIndex = -1
    for (var i = 0; i < path.length; i++) {
      if (path[i].name === speciesName) { currentIndex = i; break }
    }
    if (currentIndex === -1) return null
    return { linear: true, path: path, currentIndex: currentIndex }
  }
  var neighbors = neighborsFor(chain, speciesName, cachedEntries)
  if (!neighbors) return null
  return { linear: false, from: neighbors.from, to: neighbors.to }
}
