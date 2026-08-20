#!/usr/bin/env node
// Unit tests for CacheValidation.js. Run: node tests/test_cache_validation.js

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

const CacheValidation = load("CacheValidation.js");

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

section("isIndexStale, fixed reference points (not real Date.now — deterministic)", () => {
  const fixedNow = 1700000000000;
  const fresh = fixture("cache-fresh-index.json"); // fetchedAt is 10 days before fixedNow
  const stale = fixture("cache-stale-index.json"); // fetchedAt is 40 days before fixedNow
  eq("10 days old, 30-day TTL: not stale",
     CacheValidation.isIndexStale(fresh.fetchedAt, fixedNow, CacheValidation.INDEX_TTL_MS), false);
  eq("40 days old, 30-day TTL: stale",
     CacheValidation.isIndexStale(stale.fetchedAt, fixedNow, CacheValidation.INDEX_TTL_MS), true);
});

section("isIndexStale, exact TTL boundary", () => {
  const ttl = 1000;
  eq("exactly at the TTL is not yet stale", CacheValidation.isIndexStale(0, 1000, ttl), false);
  eq("one ms past the TTL is stale", CacheValidation.isIndexStale(0, 1001, ttl), true);
  eq("missing/non-numeric fetchedAt is always stale",
     CacheValidation.isIndexStale(undefined, 1000, ttl), true);
});

section("isValidIndexShape", () => {
  eq("well-formed fresh fixture accepted",
     CacheValidation.isValidIndexShape(fixture("cache-fresh-index.json")), true);
  eq("well-formed stale fixture also accepted (shape, not freshness)",
     CacheValidation.isValidIndexShape(fixture("cache-stale-index.json")), true);
  eq("missing entries array rejected", CacheValidation.isValidIndexShape({ fetchedAt: 1 }), false);
  eq("entry missing a required field rejected",
     CacheValidation.isValidIndexShape({ fetchedAt: 1, entries: [{ name: "pikachu" }] }), false);
  eq("not an object rejected", CacheValidation.isValidIndexShape("nope"), false);
  eq("null rejected", CacheValidation.isValidIndexShape(null), false);
});

section("isValidDetailShape", () => {
  const valid = {
    id: 25, label: "Pikachu", speciesName: "pikachu", dexNumberPadded: "#025",
    spriteUrl: "https://example/x.png", shinySpriteUrl: "https://example/x-shiny.png",
    heightM: 0.4, weightKg: 6, types: ["electric"],
    abilities: [{ label: "Static", hidden: false }],
    stats: [{ key: "hp", label: "HP", value: 35 }],
    weaknesses: { x4: [], x2: ["ground"], x0_5: [], x0_25: [], immune: [] }
  };
  eq("well-formed detail accepted", CacheValidation.isValidDetailShape(valid), true);
  eq("missing speciesName rejected",
     CacheValidation.isValidDetailShape(Object.assign({}, valid, { speciesName: undefined })), false);
  eq("missing shinySpriteUrl rejected (old pre-shiny cache shape)",
     CacheValidation.isValidDetailShape(Object.assign({}, valid, { shinySpriteUrl: undefined })), false);
  eq("empty-string shinySpriteUrl accepted (no shiny art available for this Pokemon)",
     CacheValidation.isValidDetailShape(Object.assign({}, valid, { shinySpriteUrl: "" })), true);
  eq("empty types array rejected (every Pokemon has at least one type)",
     CacheValidation.isValidDetailShape(Object.assign({}, valid, { types: [] })), false);
  eq("wrong type for heightM rejected",
     CacheValidation.isValidDetailShape(Object.assign({}, valid, { heightM: "0.4" })), false);
  eq("missing weaknesses rejected",
     CacheValidation.isValidDetailShape(Object.assign({}, valid, { weaknesses: undefined })), false);
});

section("isValidEvolutionShape", () => {
  eq("well-formed linear fixture accepted",
     CacheValidation.isValidEvolutionShape(fixture("evolution-chain-linear.json")), true);
  eq("well-formed branching fixture accepted",
     CacheValidation.isValidEvolutionShape(fixture("evolution-chain-branching.json")), true);
  eq("missing chain rejected", CacheValidation.isValidEvolutionShape({}), false);
  eq("chain missing species rejected",
     CacheValidation.isValidEvolutionShape({ chain: { evolves_to: [] } }), false);
  eq("chain missing evolves_to array rejected",
     CacheValidation.isValidEvolutionShape({ chain: { species: { name: "eevee" } } }), false);
  eq("not an object rejected", CacheValidation.isValidEvolutionShape("nope"), false);
});

section("isValidRecentsShape", () => {
  eq("well-formed slugs list accepted",
     CacheValidation.isValidRecentsShape({ slugs: ["pikachu", "charizard"] }), true);
  eq("empty slugs list accepted (first run, nothing viewed yet)",
     CacheValidation.isValidRecentsShape({ slugs: [] }), true);
  eq("non-string entry rejected",
     CacheValidation.isValidRecentsShape({ slugs: ["pikachu", 25] }), false);
  eq("missing slugs rejected", CacheValidation.isValidRecentsShape({}), false);
  eq("not an object rejected", CacheValidation.isValidRecentsShape("nope"), false);
});

section("isValidTypeChartShape", () => {
  const valid = { electric: {
    double_damage_from: ["ground"], half_damage_from: ["electric"], no_damage_from: []
  } };
  eq("well-formed single-type chart accepted", CacheValidation.isValidTypeChartShape(valid), true);
  eq("empty chart is technically valid shape (just empty)",
     CacheValidation.isValidTypeChartShape({}), true);
  eq("relation with wrong-typed field rejected",
     CacheValidation.isValidTypeChartShape({ electric: { double_damage_from: "ground" } }), false);
  eq("not an object rejected", CacheValidation.isValidTypeChartShape([]), false);
});

console.log();
if (failures) {
  console.log(`FAILED: ${failures} of ${checks} checks`);
  process.exit(1);
}
console.log(`all ${checks} checks passed`);
