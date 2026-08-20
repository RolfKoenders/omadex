.pragma library

// Whether a lookup rolls shiny for this viewing. Pure and dependency-free:
// takes the random draw as a parameter instead of calling Math.random()
// itself, so it's deterministically testable. See tests/test_shiny.js.

var SHINY_CHANCE = 1 / 100

function rollShiny(randomValue) {
  return randomValue < SHINY_CHANCE
}
