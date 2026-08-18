#!/usr/bin/env node
// Unit tests for Recents.js. Run: node tests/test_recents.js

const fs = require("fs");
const path = require("path");

function load(name) {
  const source = fs.readFileSync(path.join(__dirname, "..", name), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
  const names = [...source.matchAll(/^function\s+([A-Za-z0-9_]+)/gm)].map((m) => m[1]);
  const constants = [...source.matchAll(/^var\s+([A-Z][A-Z0-9_]*)/gm)].map((m) => m[1]);
  return new Function(`${source}\nreturn {${[...names, ...constants].join(",")}};`)();
}

const Recents = load("Recents.js");

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

section("bump: adds to an empty list", () => {
  eq("first entry", Recents.bump([], "pikachu"), ["pikachu"]);
});

section("bump: moves to front, most recent first", () => {
  eq("newest goes first", Recents.bump(["pikachu", "charizard"], "eevee"),
     ["eevee", "pikachu", "charizard"]);
});

section("bump: dedupes instead of adding a duplicate", () => {
  eq("re-viewing an existing entry moves it to the front, no duplicate",
     Recents.bump(["pikachu", "charizard", "eevee"], "charizard"),
     ["charizard", "pikachu", "eevee"]);
});

section("bump: caps at RECENTS_CAP", () => {
  const full = [];
  for (let i = 0; i < Recents.RECENTS_CAP; i++) full.push("mon-" + i);
  const result = Recents.bump(full, "new-mon");
  eq("still capped after bumping a new entry in", result.length, Recents.RECENTS_CAP);
  eq("new entry is first", result[0], "new-mon");
  eq("oldest entry evicted", result.indexOf("mon-" + (Recents.RECENTS_CAP - 1)), -1);
});

const index = [
  { name: "pikachu", label: "Pikachu", number: 25, spriteId: 25 },
  { name: "charizard", label: "Charizard", number: 6, spriteId: 6 }
];

section("resolveEntries: resolves slugs against the curated index, in order", () => {
  eq("resolved in the given order", Recents.resolveEntries(["charizard", "pikachu"], index),
     [index[1], index[0]]);
});

section("resolveEntries: silently drops a slug no longer in the index", () => {
  eq("missing slug dropped, no error, no placeholder",
     Recents.resolveEntries(["pikachu", "not-in-index-anymore"], index), [index[0]]);
});

section("resolveEntries: empty slugs list resolves to an empty list", () => {
  eq("nothing viewed yet", Recents.resolveEntries([], index), []);
});

console.log();
if (failures) {
  console.log(`FAILED: ${failures} of ${checks} checks`);
  process.exit(1);
}
console.log(`all ${checks} checks passed`);
