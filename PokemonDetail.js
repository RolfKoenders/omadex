.pragma library

// Raw PokeAPI /pokemon/{id-or-name} JSON in, display-ready fields out.
// TypeMatchups is passed in explicitly rather than imported, since plain
// Node (used by the tests) has no QML module resolution.

var STAT_LABELS = {
  "hp": "HP",
  "attack": "Attack",
  "defense": "Defense",
  "special-attack": "Sp. Atk",
  "special-defense": "Sp. Def",
  "speed": "Speed"
}

function labelFromName(name) {
  var words = String(name || "").split("-")
  for (var i = 0; i < words.length; i++) {
    words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
  }
  return words.join(" ")
}

function padNumber(id) {
  var text = String(id)
  while (text.length < 3) text = "0" + text
  return "#" + text
}

function spriteUrlFor(pokemon) {
  var sprites = pokemon.sprites || {}
  var official = sprites.other && sprites.other["official-artwork"]
    ? sprites.other["official-artwork"].front_default : null
  return official || sprites.front_default || ""
}

function projectDetail(pokemon, typeChart, matchups) {
  var types = []
  var rawTypes = Array.isArray(pokemon.types) ? pokemon.types.slice() : []
  rawTypes.sort(function(a, b) { return a.slot - b.slot })
  for (var i = 0; i < rawTypes.length; i++) {
    types.push(rawTypes[i].type.name)
  }

  var abilities = []
  var rawAbilities = Array.isArray(pokemon.abilities) ? pokemon.abilities : []
  for (var a = 0; a < rawAbilities.length; a++) {
    abilities.push({
      label: labelFromName(rawAbilities[a].ability.name),
      hidden: !!rawAbilities[a].is_hidden
    })
  }

  var stats = []
  var rawStats = Array.isArray(pokemon.stats) ? pokemon.stats : []
  for (var s = 0; s < rawStats.length; s++) {
    var key = rawStats[s].stat.name
    stats.push({ key: key, label: STAT_LABELS[key] || labelFromName(key), value: rawStats[s].base_stat })
  }

  return {
    id: pokemon.id,
    label: labelFromName(pokemon.name),
    speciesName: pokemon.species.name,
    dexNumberPadded: padNumber(pokemon.id),
    spriteUrl: spriteUrlFor(pokemon),
    heightM: pokemon.height / 10,
    weightKg: pokemon.weight / 10,
    types: types,
    abilities: abilities,
    stats: stats,
    weaknesses: matchups.weaknesses(types, typeChart)
  }
}
