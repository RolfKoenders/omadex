.pragma library

// Defensive type-effectiveness math. Pure and dependency-free so it can be
// tested without a Quickshell runtime — see tests/test_type_matchups.js.

// Must NOT be derived from Object.keys(typeChart): in production typeChart
// only holds the Pokemon's own defending type(s), fetched lazily, so that
// would only ever check a type against itself and miss every real weakness.
var ALL_TYPES = [
  "normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison",
  "ground", "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark",
  "steel", "fairy"
]

// Dual-type combining is the product of both per-type multipliers, not an
// average or a max — an immunity (0x) on either type must zero the result.
function multiplierFor(attackingType, defendingTypes, typeChart) {
  var types = Array.isArray(defendingTypes) ? defendingTypes : []
  var result = 1
  for (var i = 0; i < types.length; i++) {
    var relations = typeChart[types[i]]
    if (!relations) continue
    if (relations.no_damage_from && relations.no_damage_from.indexOf(attackingType) !== -1) {
      result = result * 0
    } else if (relations.double_damage_from && relations.double_damage_from.indexOf(attackingType) !== -1) {
      result = result * 2
    } else if (relations.half_damage_from && relations.half_damage_from.indexOf(attackingType) !== -1) {
      result = result * 0.5
    }
  }
  return result
}

// Buckets every attacking type whose combined multiplier isn't neutral (1x).
// Neutral matchups are omitted entirely — the UI shows what to worry about
// or rely on, not a full 18-type grid.
function weaknesses(defendingTypes, typeChart) {
  var buckets = { x4: [], x2: [], x0_5: [], x0_25: [], immune: [] }
  for (var i = 0; i < ALL_TYPES.length; i++) {
    var attackingType = ALL_TYPES[i]
    var multiplier = multiplierFor(attackingType, defendingTypes, typeChart)
    if (multiplier === 4) buckets.x4.push(attackingType)
    else if (multiplier === 2) buckets.x2.push(attackingType)
    else if (multiplier === 0.5) buckets.x0_5.push(attackingType)
    else if (multiplier === 0.25) buckets.x0_25.push(attackingType)
    else if (multiplier === 0) buckets.immune.push(attackingType)
  }
  buckets.x4.sort()
  buckets.x2.sort()
  buckets.x0_5.sort()
  buckets.x0_25.sort()
  buckets.immune.sort()
  return buckets
}
