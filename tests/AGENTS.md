# Test guidance

Tests are intentionally runnable on a clean checkout without pytest, npm
packages, or network access.

- JavaScript tests run directly with Node and load production QML-library
  JavaScript after stripping `.pragma library`, following the exact pattern
  in every `tests/test_*.js` file. Do not add a test framework dependency.
- All test data comes from `tests/fixtures/`. Never make a test depend on
  reaching the real PokeAPI. The fixtures are trimmed-but-real-shaped
  snapshots, not live data, and stay correct even if PokeAPI's content
  changes later.
- Prefer observable behavioral assertions over matching source text.
- `isIndexStale`/cache-validation tests use fixed epoch millisecond
  constants, never real `Date.now()`, so they stay deterministic regardless
  of when the suite runs.

When production behavior changes, update the smallest relevant test first,
then run the complete command list from the root `AGENTS.md` before handoff.
