#!/usr/bin/env node
// Unit tests for Evolution.js. Run: node tests/test_evolution.js

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

const Evolution = load("Evolution.js");

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

section("chainIdFromUrl", () => {
  eq("extracts the trailing id", Evolution.chainIdFromUrl("https://pokeapi.co/api/v2/evolution-chain/67/"), 67);
  eq("missing url returns 0", Evolution.chainIdFromUrl(""), 0);
  eq("garbage url returns 0", Evolution.chainIdFromUrl("not-a-url"), 0);
});

section("describeTrigger: level-up variants", () => {
  eq("plain level with a min_level", Evolution.describeTrigger({
    trigger: { name: "level-up" }, min_level: 16
  }), "Level 16");
  eq("time of day, no min_level, no parens of its own since the caller " +
     "already wraps this in \"Evolves into X (...)\"", Evolution.describeTrigger({
    trigger: { name: "level-up" }, time_of_day: "day"
  }), "Level up, day");
  eq("night", Evolution.describeTrigger({
    trigger: { name: "level-up" }, time_of_day: "night"
  }), "Level up, night");
  eq("friendship, no level/time modifier", Evolution.describeTrigger({
    trigger: { name: "level-up" }, min_happiness: 220
  }), "High friendship");
  eq("bare level-up with no modifiers", Evolution.describeTrigger({
    trigger: { name: "level-up" }
  }), "Level up");
});

section("describeTrigger: item and trade", () => {
  eq("use-item names the item", Evolution.describeTrigger({
    trigger: { name: "use-item" }, item: { name: "thunder-stone" }
  }), "Thunder Stone");
  eq("use-item with no item field", Evolution.describeTrigger({
    trigger: { name: "use-item" }
  }), "Use an item");
  eq("plain trade", Evolution.describeTrigger({ trigger: { name: "trade" } }), "Trade");
  eq("trade holding an item", Evolution.describeTrigger({
    trigger: { name: "trade" }, held_item: { name: "kings-rock" }
  }), "Trade holding Kings Rock");
});

section("describeTrigger: exotic triggers fall back to a humanized name", () => {
  eq("tower-of-darkness", Evolution.describeTrigger({ trigger: { name: "tower-of-darkness" } }),
     "Tower Of Darkness");
  eq("gimmighoul-coins", Evolution.describeTrigger({ trigger: { name: "gimmighoul-coins" } }),
     "Gimmighoul Coins");
  eq("missing detail entirely", Evolution.describeTrigger(undefined), "");
  eq("missing trigger field", Evolution.describeTrigger({}), "");
});

const linear = fixture("evolution-chain-linear.json").chain;
const branching = fixture("evolution-chain-branching.json").chain;

section("neighborsFor: root of a linear chain has no 'from'", () => {
  const result = Evolution.neighborsFor(linear, "charmander");
  eq("no from", result.from, null);
  eq("one evolution, with a level condition", result.to, [
    { name: "charmeleon", label: "Charmeleon", condition: "Level 16" }
  ]);
});

section("neighborsFor: middle of a linear chain has both from and to", () => {
  const result = Evolution.neighborsFor(linear, "charmeleon");
  eq("from charmander", result.from, { name: "charmander", label: "Charmander" });
  eq("to charizard at level 36", result.to, [
    { name: "charizard", label: "Charizard", condition: "Level 36" }
  ]);
});

section("neighborsFor: leaf of a linear chain has from and empty to", () => {
  const result = Evolution.neighborsFor(linear, "charizard");
  eq("from charmeleon", result.from, { name: "charmeleon", label: "Charmeleon" });
  eq("no further evolutions", result.to, []);
});

section("neighborsFor: species not present in the chain returns null", () => {
  eq("not found", Evolution.neighborsFor(linear, "bulbasaur"), null);
});

section("neighborsFor: a branching root lists every branch", () => {
  const result = Evolution.neighborsFor(branching, "eevee");
  eq("no from (eevee is the root)", result.from, null);
  eq("eight branches", result.to.length, 8);
  eq("vaporeon via water stone",
     result.to.find((e) => e.name === "vaporeon").condition, "Water Stone");
  eq("espeon via daytime level-up (time_of_day takes precedence over min_happiness)",
     result.to.find((e) => e.name === "espeon").condition, "Level up, day");
});

section("neighborsFor: a branch's own leaf has no to", () => {
  const result = Evolution.neighborsFor(branching, "vaporeon");
  eq("from eevee", result.from, { name: "eevee", label: "Eevee" });
  eq("no further evolutions", result.to, []);
});

console.log();
if (failures) {
  console.log(`FAILED: ${failures} of ${checks} checks`);
  process.exit(1);
}
console.log(`all ${checks} checks passed`);
