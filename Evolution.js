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

// Finds speciesName in chain and returns its immediate neighbors only, not
// the full multi-stage/branching tree — kept deliberately compact for the
// popup's tight vertical space. A branch with more than one evolution_details
// entry (different version groups reaching the same species) uses the first.
function neighborsFor(chain, speciesName) {
  function walk(node, parentName) {
    if (node.species.name === speciesName) {
      var to = []
      for (var i = 0; i < node.evolves_to.length; i++) {
        var child = node.evolves_to[i]
        to.push({
          name: child.species.name,
          label: titleCase(child.species.name),
          condition: describeTrigger(child.evolution_details[0])
        })
      }
      return {
        from: parentName ? { name: parentName, label: titleCase(parentName) } : null,
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
