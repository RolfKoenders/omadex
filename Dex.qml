import QtQuick
import Quickshell
import Quickshell.Io
import "IndexSearch.js" as IndexSearch
import "PokemonDetail.js" as PokemonDetail
import "TypeMatchups.js" as TypeMatchups
import "CacheValidation.js" as CacheValidation
import "PokeApi.js" as PokeApi
import "Recents.js" as Recents
import "Evolution.js" as Evolution

// Owner of the search index, type chart, and per-Pokemon detail: cache,
// fetch, and derived state. Panel.qml owns keyboard/UI concerns only.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string cacheDir: home + "/.config/omarchy/quickdex/cache"
  readonly property string indexPath: cacheDir + "/index.json"
  readonly property string typesPath: cacheDir + "/types.json"
  readonly property string recentsPath: cacheDir + "/recents.json"
  readonly property string evolutionCacheDir: cacheDir + "/evolution"

  // ------------------------------------------------------------ search

  // loading | error | ready
  property string indexPhase: "loading"
  property var cachedEntries: []
  property string query: ""

  readonly property var results: root.indexPhase === "ready"
    ? IndexSearch.filterIndex(root.cachedEntries, root.query) : []

  // ------------------------------------------------------------ recents

  property var recentSlugs: []

  readonly property var recentResults: Recents.resolveEntries(root.recentSlugs, root.cachedEntries)

  function markViewed(slug) {
    root.recentSlugs = Recents.bump(root.recentSlugs, slug)
    root.recentsFile.setText(JSON.stringify({ slugs: root.recentSlugs }))
  }

  property FileView recentsFile: FileView {
    path: root.recentsPath
    watchChanges: false
    printErrors: false
    atomicWrites: true
    onLoaded: root.onRecentsFileLoaded(text())
    // A missing file on first run is normal, not an error — nothing to do.
    onLoadFailed: {}
  }

  function onRecentsFileLoaded(text) {
    var parsed = null
    try { parsed = JSON.parse(text) } catch (err) { parsed = null }
    if (parsed && CacheValidation.isValidRecentsShape(parsed)) {
      root.recentSlugs = parsed.slugs
    }
  }

  // ------------------------------------------------------------ detail

  property string expandedSlug: ""
  // idle | loading | error | ready
  property string detailPhase: "idle"
  property var detail: null
  // Guards against a stale async callback overwriting state for a Pokemon
  // the user has already navigated away from.
  property string pendingSlug: ""

  readonly property string artworkPath: root.expandedSlug
    ? (root.cacheDir + "/pokemon/" + root.expandedSlug + ".png") : ""

  // idle | loading | error | ready
  property string evolutionPhase: "idle"
  property var evolutionNeighbors: null

  function selectPokemon(slug) {
    if (root.expandedSlug === slug) { root.collapse(); return }
    root.expandedSlug = slug
    root.pendingSlug = slug
    root.detail = null
    root.detailPhase = "loading"
    root.evolutionPhase = "loading"
    root.evolutionNeighbors = null
    root.detailCacheFile.path = root.cacheDir + "/pokemon/" + slug + ".json"
    root.detailCacheFile.reload()
  }

  function collapse() {
    root.expandedSlug = ""
    root.pendingSlug = ""
    root.detailPhase = "idle"
    root.detail = null
    root.evolutionPhase = "idle"
    root.evolutionNeighbors = null
  }

  // ------------------------------------------------------------ index cache

  property FileView indexFile: FileView {
    path: root.indexPath
    watchChanges: false
    printErrors: false
    atomicWrites: true
    onLoaded: root.onIndexFileLoaded(text())
    onLoadFailed: root.fetchAndCacheIndex()
  }

  function onIndexFileLoaded(text) {
    var parsed = null
    try { parsed = JSON.parse(text) } catch (err) { parsed = null }
    if (!parsed || !CacheValidation.isValidIndexShape(parsed)) {
      root.fetchAndCacheIndex()
      return
    }
    root.cachedEntries = parsed.entries
    root.indexPhase = "ready"
    if (CacheValidation.isIndexStale(parsed.fetchedAt, Date.now(), CacheValidation.INDEX_TTL_MS)) {
      root.refreshIndexInBackground()
    }
  }

  function fetchAndCacheIndex() {
    root.indexPhase = "loading"
    PokeApi.fetchIndex(function(rawEntries) {
      var curated = IndexSearch.curateIndex(rawEntries)
      root.cachedEntries = curated
      root.indexPhase = "ready"
      root.writeIndexCache(curated)
    }, function(message) {
      root.indexPhase = "error"
    })
  }

  // A background refresh failing must not disturb whatever is already
  // serving search results — only a first-ever fetch failure is a real error.
  function refreshIndexInBackground() {
    PokeApi.fetchIndex(function(rawEntries) {
      var curated = IndexSearch.curateIndex(rawEntries)
      root.cachedEntries = curated
      root.writeIndexCache(curated)
    }, function(message) {})
  }

  function writeIndexCache(entries) {
    root.indexFile.setText(JSON.stringify({ fetchedAt: Date.now(), entries: entries }))
  }

  // ------------------------------------------------------------ type chart

  property FileView typesFile: FileView {
    path: root.typesPath
    watchChanges: false
    printErrors: false
    atomicWrites: true
    onLoaded: root.onTypesFileLoaded(text())
    onLoadFailed: {}
  }

  function onTypesFileLoaded(text) {
    var parsed = null
    try { parsed = JSON.parse(text) } catch (err) { parsed = null }
    if (parsed && CacheValidation.isValidTypeChartShape(parsed)) {
      root.typeChart = parsed
    }
  }

  property var typeChart: ({})

  // Fetches only the types not already cached, then merges and writes the
  // whole chart back at once — never a partial read-modify-write, which
  // could otherwise race two overlapping lookups and silently drop a key.
  function ensureTypesLoaded(types, onReady) {
    var missing = []
    for (var i = 0; i < types.length; i++) {
      if (!root.typeChart[types[i]]) missing.push(types[i])
    }
    if (missing.length === 0) { onReady(); return }
    root.fetchMissingTypes(missing, onReady)
  }

  function fetchMissingTypes(missing, onReady) {
    var remaining = missing.length
    var merged = {}
    var hadError = false
    for (var i = 0; i < missing.length; i++) {
      root.fetchOneType(missing[i], function(name, relations) {
        merged[name] = relations
        remaining--
        if (remaining === 0) {
          root.applyTypeChartMerge(merged)
          if (!hadError) onReady()
        }
      }, function() {
        hadError = true
        remaining--
        if (remaining === 0) {
          root.applyTypeChartMerge(merged)
        }
      })
    }
  }

  // Takes the type name as a parameter so each callback captures its own
  // type rather than whatever the loop variable ended on.
  function fetchOneType(name, onDone, onError) {
    PokeApi.fetchType(name, function(relations) { onDone(name, relations) }, onError)
  }

  function applyTypeChartMerge(newEntries) {
    var merged = {}
    for (var key in root.typeChart) merged[key] = root.typeChart[key]
    for (var name in newEntries) merged[name] = newEntries[name]
    root.typeChart = merged
    root.typesFile.setText(JSON.stringify(merged))
  }

  // ------------------------------------------------------------ detail cache

  property FileView detailCacheFile: FileView {
    watchChanges: false
    printErrors: false
    atomicWrites: true
    onLoaded: root.onDetailFileLoaded(path, text())
    onLoadFailed: root.onDetailFileMissing(path)
  }

  function slugForPath(path) {
    var match = /\/([^/]+)\.json$/.exec(String(path || ""))
    return match ? match[1] : ""
  }

  function onDetailFileLoaded(path, text) {
    var slug = root.slugForPath(path)
    if (slug !== root.pendingSlug) return
    var parsed = null
    try { parsed = JSON.parse(text) } catch (err) { parsed = null }
    if (!parsed || !CacheValidation.isValidDetailShape(parsed)) {
      root.fetchDetailFromNetwork(slug)
      return
    }
    root.detail = parsed
    root.detailPhase = "ready"
    root.markViewed(slug)
    root.fetchEvolution(slug, parsed.speciesName)
    // Loaded from disk: artwork was already attempted on the original fetch.
  }

  function onDetailFileMissing(path) {
    var slug = root.slugForPath(path)
    if (slug !== root.pendingSlug) return
    root.fetchDetailFromNetwork(slug)
  }

  function fetchDetailFromNetwork(slug) {
    PokeApi.fetchPokemon(slug, function(raw) {
      if (slug !== root.pendingSlug) return
      var typeNames = []
      for (var i = 0; i < raw.types.length; i++) typeNames.push(raw.types[i].type.name)
      root.ensureTypesLoaded(typeNames, function() {
        if (slug !== root.pendingSlug) return
        var projected = PokemonDetail.projectDetail(raw, root.typeChart, TypeMatchups)
        root.detail = projected
        root.detailPhase = "ready"
        root.markViewed(slug)
        root.fetchEvolution(slug, projected.speciesName)
        root.writeDetailCache(slug, projected)
        root.downloadArtwork(slug, projected.spriteUrl)
      })
    }, function(message) {
      if (slug !== root.pendingSlug) return
      root.detailPhase = "error"
    })
  }

  function writeDetailCache(slug, projected) {
    // Only reached once pendingSlug still matches, so detailCacheFile.path
    // is still bound to this slug's own file.
    root.detailCacheFile.setText(JSON.stringify(projected))
  }

  // ------------------------------------------------------------ evolution

  // Rebound per selection like detailCacheFile, but keyed by evolution-chain
  // id rather than slug — several forms/stages of the same species share one
  // chain (Bulbasaur/Ivysaur/Venusaur all fetch and cache the same file
  // instead of the same chain three times over).
  property FileView evolutionCacheFile: FileView {
    watchChanges: false
    printErrors: false
    atomicWrites: true
    onLoaded: root.onEvolutionFileLoaded(text())
    onLoadFailed: root.onEvolutionFileMissing()
  }

  property string pendingSpeciesName: ""
  property int pendingChainId: 0
  // Which slug's request is currently bound to evolutionCacheFile — checked
  // by its onLoaded/onLoadFailed, since those can resolve after the user has
  // already navigated to a different Pokemon (same race pendingSlug guards
  // against elsewhere in this file, just at this file's own async boundary).
  property string evolutionRequestSlug: ""

  // The species lookup itself is never cached (small, only ever used to
  // find the chain id); only the chain response is cached, and by chain id.
  function fetchEvolution(slug, speciesName) {
    root.pendingSpeciesName = speciesName
    PokeApi.fetchSpecies(speciesName, function(species) {
      if (slug !== root.pendingSlug) return
      root.pendingChainId = Evolution.chainIdFromUrl(
        species.evolution_chain ? species.evolution_chain.url : "")
      root.evolutionRequestSlug = slug
      root.evolutionCacheFile.path = root.evolutionCacheDir + "/" + root.pendingChainId + ".json"
      root.evolutionCacheFile.reload()
    }, function(message) {
      if (slug !== root.pendingSlug) return
      root.evolutionPhase = "error"
    })
  }

  function onEvolutionFileLoaded(text) {
    if (root.evolutionRequestSlug !== root.pendingSlug) return
    var parsed = null
    try { parsed = JSON.parse(text) } catch (err) { parsed = null }
    if (!parsed || !CacheValidation.isValidEvolutionShape(parsed)) {
      root.fetchEvolutionChainFromNetwork()
      return
    }
    root.applyEvolutionChain(parsed)
  }

  function onEvolutionFileMissing() {
    if (root.evolutionRequestSlug !== root.pendingSlug) return
    root.fetchEvolutionChainFromNetwork()
  }

  function fetchEvolutionChainFromNetwork() {
    var slug = root.evolutionRequestSlug
    PokeApi.fetchEvolutionChain(root.pendingChainId, function(raw) {
      if (slug !== root.pendingSlug) return
      root.evolutionCacheFile.setText(JSON.stringify(raw))
      root.applyEvolutionChain(raw)
    }, function(message) {
      if (slug !== root.pendingSlug) return
      root.evolutionPhase = "error"
    })
  }

  function applyEvolutionChain(chainJson) {
    root.evolutionNeighbors = Evolution.neighborsFor(chainJson.chain, root.pendingSpeciesName)
    root.evolutionPhase = "ready"
  }

  // ------------------------------------------------------------ artwork

  // Best-effort local cache of the artwork bytes, only triggered on a fresh
  // fetch (never on a disk-cache hit), so a repeat lookup needs no network.
  property Process artworkProcess: Process {}

  function downloadArtwork(slug, url) {
    if (!url || root.artworkProcess.running) return
    var path = root.cacheDir + "/pokemon/" + slug + ".png"
    root.artworkProcess.command = ["curl", "-sf", "--create-dirs", "-o", path, url]
    root.artworkProcess.running = true
  }

  // ------------------------------------------------------------ startup

  // FileView does not create missing parent directories; this also covers
  // cacheDir itself since mkdir -p creates every missing ancestor.
  property Process cacheDirProcess: Process {
    command: ["mkdir", "-p", root.cacheDir + "/pokemon", root.evolutionCacheDir]
  }

  Component.onCompleted: root.cacheDirProcess.running = true
}
