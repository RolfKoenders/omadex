.pragma library

// Standard Pokemon type colors, the same palette used across the games and
// every major reference site. Intentionally hardcoded rather than derived
// from Style/Color: a type's color is part of its identity, not UI chrome
// that should shift with the user's Omarchy theme.
var TYPE_COLORS = {
  normal: "#A8A878", fire: "#F08030", water: "#6890F0", electric: "#F8D030",
  grass: "#78C850", ice: "#98D8D8", fighting: "#C03028", poison: "#A040A0",
  ground: "#E0C068", flying: "#A890F0", psychic: "#F85888", bug: "#A8B820",
  rock: "#B8A038", ghost: "#705898", dragon: "#7038F8", dark: "#705848",
  steel: "#B8B8D0", fairy: "#EE99AC"
}

function colorFor(typeName) {
  return TYPE_COLORS[String(typeName || "").toLowerCase()] || "#8a8a9a"
}
