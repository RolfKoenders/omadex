# Quickdex

## Project overview

This repository is an Omarchy Quickshell plugin for looking up Pokemon
stats, types, and defensive weaknesses from the desktop bar. It is pure
QML/JavaScript, with no companion process. Data comes from PokeAPI
(`https://pokeapi.co`), a free, unauthenticated REST API, called directly
from QML via the JS engine's built-in `XMLHttpRequest`.

Canonical public repository: `https://github.com/RolfKoenders/quickdex`.

The full v1 product spec is filed as a PRD at
`https://github.com/RolfKoenders/quickdex/issues/1`. Read it before making
scope decisions.

## Local development

For local development, symlink the checkout into the plugins directory
instead of installing a release:

```bash
ln -sfn "$PWD" ~/.config/omarchy/plugins/quickdex
omarchy restart shell
omarchy plugin enable quickdex
```

Quickshell caches compiled QML/JS at `~/.cache/quickshell/qmlcache`. This
cache does not always invalidate correctly for files reached through a
symlink, so if an edit does not seem to take effect after a restart, clear
it and restart again:

```bash
rm -rf ~/.cache/quickshell/qmlcache
omarchy restart shell
```

## Architecture map

- `Dex.qml`: owner of the search index, the type chart, and per-Pokemon
  detail: cache, fetch, and derived state. A plain child property of
  `Panel.qml` (`property Dex dex: Dex {}`), not a manifest `service`; v1
  has one entry point, so there is no second surface to share state
  through. Promoting it to a real `service` is the only change a future v2
  (team calculator) needs to reuse this data layer.
- `Panel.qml`: bar button, popup, search field, and keyboard cursor. Owns
  UI/keyboard concerns only.
- `ResultRow.qml`: one search-result row plus its inline expansion.
- `DetailView.qml`: stat/type/ability/weakness/evolution content for the
  currently expanded Pokemon.
- `TypeBadge.qml`, `EvolutionNode.qml`: small reusable presentational
  pieces, not full rows — a colored type chip and one sprite+label+
  condition node in an evolution chain strip, respectively.
- `TypeMatchups.js`, `IndexSearch.js`, `PokemonDetail.js`,
  `CacheValidation.js`, `Recents.js`, `Evolution.js`: pure `.pragma
  library` modules, no QML types, no side effects, no Node-only APIs.
  Each is directly unit-tested by loading it under plain Node after
  stripping the pragma line (see `tests/test_*.js`). Prefer extending
  these over adding logic to `Dex.qml`.
- `PokeApi.js`: thin, dumb `XMLHttpRequest` transport. Deliberately has no
  caching/validation/curation logic of its own. `Dex.qml` is the only
  caller and owns everything above this layer.

Keep transport, caching, curation/projection logic, and UI policy
separate: each concern lives in its own file, not folded into `Dex.qml`
or `Panel.qml`.

## Coding conventions

- Keep the four pure JS modules side-effect free and compatible with the
  QML JavaScript engine. Do not add Node-only APIs to production modules.
  The same source runs under both Node (tests) and the real QML engine.
- When one pure module needs another (e.g. `PokemonDetail` needs
  `TypeMatchups`), pass it as an explicit function parameter, never a QML
  `import`. Plain Node has no QML module resolution.
- Validate external JSON shapes before indexing or rendering them
  (`CacheValidation.js`). PokeAPI is trusted but its schema can still
  return nulls/missing fields the caching layer must not choke on.
- Use `Style` and `Color` tokens in QML, never hardcoded colors. Every
  `Text` must set `textFormat: Text.PlainText` and an explicit
  `font.family`, enforced by `tests/test_qml_style.py`.
- Every fetch/cache callback that can race a newer user action (selecting
  a different Pokemon before the previous lookup settles) must check
  `pendingSlug` still matches before mutating state. See `Dex.qml`.
- The `types.json` type-chart cache is always merged in memory and written
  as a whole object, never read-modify-written per lookup. Two overlapping
  fetches for different types would otherwise race the file and silently
  drop a key, turning a real immunity into a false neutral.
- Search-as-you-type must never make a network call: it filters the
  already-cached index locally. Only an explicit selection triggers a
  detail fetch, and only once per Pokemon (permanent cache).
- Use argument arrays for `Process`; do not introduce shell interpolation
  for URLs or paths (the artwork-download `curl` call in `Dex.qml` is the
  one place this matters).

## Verification

Run the checks relevant to the files changed. Before handing off a broad
change, run the full suite:

```bash
node tests/test_type_matchups.js
node tests/test_index_search.js
node tests/test_pokemon_detail.js
node tests/test_cache_validation.js
python3 tests/test_qml_style.py
```

When available, also run `qmllint -I $OMARCHY_PATH/shell`, `qmlformat`,
and `omarchy plugin validate .`. Do not make tests depend on internet
access. All PokeAPI data used by tests is trimmed-but-real fixtures
under `tests/fixtures/`, not live requests.

## Releases

Bump `manifest.json`'s `version` (semver: patch for fixes, minor for
features) as part of any user-facing feature PR. `.github/workflows/release.yml`
watches pushes to `main` and publishes a tagged GitHub release with
auto-generated notes the moment it sees a version that isn't tagged yet —
nothing else to do once the bump lands. This is not a blocking CI check:
plenty of legitimate PRs (docs, CI, refactors) shouldn't bump the version,
and the workflow itself no-ops cleanly when nothing changed.

## Code review rules

- Flag any code path that fetches per-keystroke during search. The index
  must always be filtered locally from cache.
- Flag any per-Pokemon or per-type cache write that isn't gated by the
  `pendingSlug` check, or that read-modify-writes `types.json` instead of
  merging in memory first.
- Flag any new alternate-form number derivation that adds a network
  request. See `IndexSearch.js`'s donor-based derivation, which is
  deliberately a local, free computation.
- Flag raw PokeAPI response data written to logs or IPC output without
  going through the display-projection layer first.
