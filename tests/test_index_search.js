#!/usr/bin/env node
// Unit tests for IndexSearch.js. Run: node tests/test_index_search.js

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

const IndexSearch = load("IndexSearch.js");

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

const raw = fixture("index-sample.json");
const curated = IndexSearch.curateIndex(raw);
const byName = {};
for (const entry of curated) byName[entry.name] = entry;

section("curation drops cosmetic-only variants (identical stats and type)", () => {
  eq("pikachu-cosplay excluded (identical stats to base Pikachu)",
     byName["pikachu-cosplay"], undefined);
  eq("pikachu-original-cap excluded", byName["pikachu-original-cap"], undefined);
  eq("charizard-gmax excluded", byName["charizard-gmax"], undefined);
  eq("basculin-blue-striped excluded", byName["basculin-blue-striped"], undefined);
  eq("minior-orange-meteor excluded (cosmetic twin of minior-red-meteor)",
     byName["minior-orange-meteor"], undefined);
  eq("minior-orange excluded (cosmetic twin of minior-red)",
     byName["minior-orange"], undefined);
});

section("curation also drops same-type stat-only variants (identical weakness profile)", () => {
  // Weaknesses depend only on type, not stats — a variant with the same
  // type as its base form would show byte-for-byte identical weaknesses,
  // so it's excluded even though its stats genuinely differ.
  eq("pikachu-starter excluded (same Electric type as base Pikachu, only HP differs)",
     byName["pikachu-starter"], undefined);
  eq("eevee-starter excluded (same Normal type as base Eevee, only HP differs)",
     byName["eevee-starter"], undefined);
  eq("minior-red excluded (same Rock/Flying type as minior-red-meteor, only defense differs)",
     byName["minior-red"], undefined);
});

section("curation keeps genuinely type-distinct forms", () => {
  eq("deoxys-attack kept as a distinct form", byName["deoxys-attack"] !== undefined, true);
  eq("minior-red-meteor kept (the one surviving Minior representative)",
     byName["minior-red-meteor"] !== undefined, true);
});

section("alternate-form number derivation (no extra network request)", () => {
  eq("deoxys-attack (raw id 10001) resolves to deoxys-normal's dex number",
     byName["deoxys-attack"].number, 386);
  eq("deoxys-defense also resolves to the same donor",
     byName["deoxys-defense"].number, 386);
  eq("urshifu-rapid-strike (raw id 10191, no bare 'urshifu' entry exists) " +
     "resolves via its sibling urshifu-single-strike",
     byName["urshifu-rapid-strike"].number, 892);
  eq("a base-form entry's own low raw id is its number",
     byName["pikachu"].number, 25);
});

section("number derivation runs before exclusion, using a synthetic case", () => {
  // An excluded sibling can still be the correct number donor for a form
  // that survives curation — the real fixture no longer has a case where
  // the lowest-id donor itself gets excluded (minior-red, the last such
  // example, was later excluded too as a same-type variant), so this is
  // exercised directly with fabricated data instead.
  const synthetic = [
    // Excluded (matches the -gmax$ pattern), but the only low-id ( < 10000)
    // entry sharing the "testmon" prefix.
    { name: "testmon-gmax", url: "https://pokeapi.co/api/v2/pokemon/500/" },
    // Kept (matches no exclusion pattern); its own raw id is >= 10000, so it
    // needs a donor — the only candidate is the excluded entry above.
    { name: "testmon-special", url: "https://pokeapi.co/api/v2/pokemon/10500/" }
  ];
  const result = IndexSearch.curateIndex(synthetic);
  eq("testmon-gmax is excluded", result.find((e) => e.name === "testmon-gmax"), undefined);
  eq("testmon-special resolves its number via the excluded donor",
     result.find((e) => e.name === "testmon-special").number, 500);
});

section("spriteId is the form's own raw id, not the derived shared number", () => {
  eq("deoxys-attack keeps its own sprite", byName["deoxys-attack"].spriteId, 10001);
  eq("deoxys-attack's number is still the shared dex number",
     byName["deoxys-attack"].number, 386);
});

section("filterIndex matches name, label, and number", () => {
  eq("substring match on name", IndexSearch.filterIndex(curated, "char").map((e) => e.name),
     ["charmander", "charmeleon", "charizard"]);
  // pikachu-starter is excluded from the index (same-type variant), so
  // only base Pikachu matches its own number now.
  eq("number match", IndexSearch.filterIndex(curated, "25").map((e) => e.name),
     ["pikachu"]);
  eq("number match on an entry with no same-number sibling in this fixture",
     IndexSearch.filterIndex(curated, "122").map((e) => e.name), ["mr-mime"]);
  eq("case-insensitive", IndexSearch.filterIndex(curated, "PIKA").map((e) => e.name),
     ["pikachu"]);
  eq("spaced query matches a hyphenated name via its label",
     IndexSearch.filterIndex(curated, "mr mime").map((e) => e.name), ["mr-mime"]);
  eq("no match returns an empty array", IndexSearch.filterIndex(curated, "zzz-nope"), []);
  eq("empty query returns an empty array (no browse-all mode)",
     IndexSearch.filterIndex(curated, ""), []);
});

section("filterIndex caps results at RESULT_LIMIT", () => {
  const big = [];
  for (let i = 0; i < 200; i++) {
    big.push({ name: "test-" + i, label: "Test " + i, number: i, spriteId: i });
  }
  eq("capped at 50", IndexSearch.filterIndex(big, "test").length, 50);
});

console.log();
if (failures) {
  console.log(`FAILED: ${failures} of ${checks} checks`);
  process.exit(1);
}
console.log(`all ${checks} checks passed`);
