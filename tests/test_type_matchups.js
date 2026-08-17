#!/usr/bin/env node
// Unit tests for TypeMatchups.js. Run: node tests/test_type_matchups.js

const fs = require("fs");
const path = require("path");

function load(name) {
  const source = fs.readFileSync(path.join(__dirname, "..", name), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
  const names = [...source.matchAll(/^function\s+([A-Za-z0-9_]+)/gm)].map((m) => m[1]);
  const constants = [...source.matchAll(/^var\s+([A-Z][A-Z0-9_]*)/gm)].map((m) => m[1]);
  return new Function(`${source}\nreturn {${[...names, ...constants].join(",")}};`)();
}

function fixture(name) {
  return JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8"));
}

const TypeMatchups = load("TypeMatchups.js");

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

const chart = {
  electric: fixture("type-electric.json"),
  fire: fixture("type-fire.json"),
  flying: fixture("type-flying.json"),
  rock: fixture("type-rock.json"),
  ground: fixture("type-ground.json"),
  ghost: fixture("type-ghost.json"),
  grass: fixture("type-grass.json"),
  steel: fixture("type-steel.json")
};

section("single-type baseline (Pikachu, Electric)", () => {
  const w = TypeMatchups.weaknesses(["electric"], chart);
  eq("weak x2 to ground", w.x2, ["ground"]);
  eq("resists x0.5 electric/flying/steel",
     w.x0_5, ["electric", "flying", "steel"]);
  eq("no x4, x0.25, or immune", { x4: w.x4, x0_25: w.x0_25, immune: w.immune },
     { x4: [], x0_25: [], immune: [] });
});

section("dual-type multiplication (Charizard, Fire/Flying)", () => {
  const w = TypeMatchups.weaknesses(["fire", "flying"], chart);
  // Rock deals double damage to both Fire and Flying: 2 * 2 = 4.
  eq("x4 weak to rock", w.x4, ["rock"]);
  // Electric and Water each deal double to exactly one of Fire/Flying and
  // are neutral against the other: 2 * 1 = 2.
  eq("x2 weak to electric and water", w.x2, ["electric", "water"]);
  // Fire and Flying both resist Bug (0.5 * 0.5) and both resist Grass
  // (0.5 * 0.5) — real Charizard trivia, not a coincidence.
  eq("x0.25 resists bug and grass", w.x0_25, ["bug", "grass"]);
  // Fire is immune to nothing itself, but Flying is immune to Ground (0x);
  // Fire takes double from Ground (2x) — combined 2 * 0 = 0, immune overall.
  // This is the real Charizard/Earthquake interaction, not a coincidence.
  eq("immune to ground", w.immune, ["ground"]);
});

section("immunity dominates regardless of the other type (Golurk, Ground/Ghost, vs Electric)", () => {
  const w = TypeMatchups.weaknesses(["ground", "ghost"], chart);
  // Ground is immune to Electric (0x); Ghost has no relation to Electric (1x,
  // neutral). The combined multiplier must be exactly 0, not 1 — proving the
  // zero propagates through multiplication rather than being overridden.
  // Ghost's own immunity to Fighting and Normal carries through the same way
  // (Ground is neutral to both, so it doesn't cancel Ghost's immunity).
  eq("immune to electric, fighting, and normal",
     w.immune, ["electric", "fighting", "normal"]);
  eq("electric does not also appear as a weakness or resistance",
     w.x2.concat(w.x0_5).indexOf("electric"), -1);
});

section("x0.25 dual resist (Ferrothorn-shaped Steel/Grass, vs Grass)", () => {
  const w = TypeMatchups.weaknesses(["steel", "grass"], chart);
  // Steel resists Grass (0.5x) and Grass resists itself (0.5x): 0.5 * 0.5 = 0.25.
  eq("resists x0.25 grass", w.x0_25, ["grass"]);
});

section("production-shape chart: only the Pokemon's own defending type(s), nothing else", () => {
  // This is the actual shape Dex.qml produces — it only ever fetches the
  // looked-up Pokemon's own type(s), never the full 18-type universe. A
  // chart broader than that (like the shared `chart` above, which every
  // other section in this file uses) can hide a bug where the attacking
  // types checked were wrongly derived from the chart's own keys instead
  // of the fixed type list — that exact bug shipped and was only caught by
  // live-testing against the real API, not by these tests as first written.
  const minimalChart = { electric: fixture("type-electric.json") };
  const w = TypeMatchups.weaknesses(["electric"], minimalChart);
  eq("still finds the x2 weakness to ground even though 'ground' " +
     "is not a key in the chart", w.x2, ["ground"]);
  eq("still finds the x0.5 resistances", w.x0_5, ["electric", "flying", "steel"]);
});

console.log();
if (failures) {
  console.log(`FAILED: ${failures} of ${checks} checks`);
  process.exit(1);
}
console.log(`all ${checks} checks passed`);
