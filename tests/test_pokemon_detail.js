#!/usr/bin/env node
// Unit tests for PokemonDetail.js. Run: node tests/test_pokemon_detail.js

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
const PokemonDetail = load("PokemonDetail.js");

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
  ghost: fixture("type-ghost.json")
};

section("Pikachu (single type, no hidden-ability surprises)", () => {
  const detail = PokemonDetail.projectDetail(fixture("pokemon-pikachu.json"), chart, TypeMatchups);
  eq("dexNumberPadded", detail.dexNumberPadded, "#025");
  eq("speciesName", detail.speciesName, "pikachu");
  eq("height decimetres -> metres", detail.heightM, 0.4);
  eq("weight hectograms -> kilograms", detail.weightKg, 6);
  eq("types", detail.types, ["electric"]);
  eq("shinySpriteUrl extracted from official-artwork.front_shiny",
     detail.shinySpriteUrl,
     "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/shiny/25.png");
  eq("abilities with hidden flag",
     detail.abilities, [
       { label: "Static", hidden: false },
       { label: "Lightning Rod", hidden: true }
     ]);
  eq("stat count", detail.stats.length, 6);
  eq("hp stat", detail.stats[0], { key: "hp", label: "HP", value: 35 });
});

section("Charizard (dual type, weaknesses delegated to TypeMatchups via injection)", () => {
  const detail = PokemonDetail.projectDetail(fixture("pokemon-charizard.json"), chart, TypeMatchups);
  eq("dexNumberPadded", detail.dexNumberPadded, "#006");
  eq("speciesName", detail.speciesName, "charizard");
  eq("types in slot order", detail.types, ["fire", "flying"]);
  eq("weaknesses match calling TypeMatchups directly on the same types",
     detail.weaknesses, TypeMatchups.weaknesses(["fire", "flying"], chart));
  eq("x4 weak to rock, proving the injected module actually ran",
     detail.weaknesses.x4, ["rock"]);
});

section("Golurk (multiple non-hidden abilities plus one hidden)", () => {
  const detail = PokemonDetail.projectDetail(fixture("pokemon-golurk.json"), chart, TypeMatchups);
  eq("dexNumberPadded", detail.dexNumberPadded, "#623");
  eq("speciesName", detail.speciesName, "golurk");
  eq("height decimetres -> metres", detail.heightM, 2.8);
  eq("weight hectograms -> kilograms", detail.weightKg, 330);
  eq("abilities", detail.abilities, [
    { label: "Iron Fist", hidden: false },
    { label: "Klutz", hidden: false },
    { label: "No Guard", hidden: true }
  ]);
  eq("immune to electric, fighting, and normal, proving the injected module actually ran",
     detail.weaknesses.immune, ["electric", "fighting", "normal"]);
  eq("no front_shiny in this fixture: shinySpriteUrl falls back to empty",
     detail.shinySpriteUrl, "");
});

console.log();
if (failures) {
  console.log(`FAILED: ${failures} of ${checks} checks`);
  process.exit(1);
}
console.log(`all ${checks} checks passed`);
