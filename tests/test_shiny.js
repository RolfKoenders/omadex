#!/usr/bin/env node
// Unit tests for Shiny.js. Run: node tests/test_shiny.js

const fs = require("fs");
const path = require("path");

function load(name) {
  const source = fs.readFileSync(path.join(__dirname, "..", name), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
  const names = [...source.matchAll(/^function\s+([A-Za-z0-9_]+)/gm)].map((m) => m[1]);
  const constants = [...source.matchAll(/^var\s+([A-Z][A-Z0-9_]*)/gm)].map((m) => m[1]);
  return new Function(`${source}\nreturn {${[...names, ...constants].join(",")}};`)();
}

const Shiny = load("Shiny.js");

let failures = 0;
let checks = 0;

function eq(label, actual, expected) {
  checks++;
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) {
    failures++;
    console.log(`  FAIL ${label}\n       got      ${JSON.stringify(actual)}` +
                `\n       expected ${JSON.stringify(expected)}`);
  }
}

function section(title, body) {
  console.log(title);
  const before = failures;
  body();
  console.log(before === failures ? "  ok" : "  ^^ failures above");
}

section("rollShiny: 0 is always inside the odds", () => {
  eq("hits", Shiny.rollShiny(0), true);
});

section("rollShiny: just under SHINY_CHANCE hits", () => {
  eq("hits", Shiny.rollShiny(Shiny.SHINY_CHANCE - 0.0001), true);
});

section("rollShiny: exactly SHINY_CHANCE does not hit (Math.random() is [0,1))", () => {
  eq("no hit", Shiny.rollShiny(Shiny.SHINY_CHANCE), false);
});

section("rollShiny: comfortably above SHINY_CHANCE does not hit", () => {
  eq("no hit", Shiny.rollShiny(Shiny.SHINY_CHANCE + 0.0001), false);
  eq("no hit", Shiny.rollShiny(0.5), false);
  eq("no hit, upper bound", Shiny.rollShiny(0.999999), false);
});

console.log();
if (failures) {
  console.log(`FAILED: ${failures} of ${checks} checks`);
  process.exit(1);
}
console.log(`all ${checks} checks passed`);
