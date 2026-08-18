.pragma library

// Thin, dumb XMLHttpRequest transport for PokeAPI. No caching or validation
// here; Dex.qml owns everything above this layer.

var BASE_URL = "https://pokeapi.co/api/v2"

function request(url, onDone, onError) {
  var xhr = new XMLHttpRequest()
  xhr.onreadystatechange = function() {
    if (xhr.readyState !== XMLHttpRequest.DONE) return
    if (xhr.status < 200 || xhr.status >= 300) {
      onError("HTTP " + xhr.status)
      return
    }
    try {
      onDone(JSON.parse(xhr.responseText))
    } catch (err) {
      onError("Invalid JSON from " + url)
    }
  }
  xhr.onerror = function() { onError("Network error requesting " + url) }
  xhr.open("GET", url)
  xhr.send()
}

// One bulk request for the whole name/number index. A large, fixed limit
// (rather than today's live count) avoids silently truncating results as
// new games/generations add more Pokemon over time.
function fetchIndex(onDone, onError) {
  request(BASE_URL + "/pokemon?limit=100000&offset=0", function(body) {
    onDone(Array.isArray(body.results) ? body.results : [])
  }, onError)
}

function fetchPokemon(nameOrId, onDone, onError) {
  request(BASE_URL + "/pokemon/" + encodeURIComponent(String(nameOrId)), onDone, onError)
}

// Only ever used transiently to find a species' evolution-chain id, so this
// is never cached to disk the way the chain itself is.
function fetchSpecies(nameOrId, onDone, onError) {
  request(BASE_URL + "/pokemon-species/" + encodeURIComponent(String(nameOrId)), onDone, onError)
}

function fetchEvolutionChain(chainId, onDone, onError) {
  request(BASE_URL + "/evolution-chain/" + encodeURIComponent(String(chainId)), onDone, onError)
}

// PokeAPI's damage_relations lists carry full {name, url} refs; extract just
// the name here rather than leaking the raw API shape into domain logic.
function namesOf(refs) {
  var names = []
  var list = Array.isArray(refs) ? refs : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && typeof list[i].name === "string") names.push(list[i].name)
  }
  return names
}

function fetchType(name, onDone, onError) {
  request(BASE_URL + "/type/" + encodeURIComponent(String(name)), function(body) {
    var relations = body.damage_relations || {}
    onDone({
      double_damage_from: namesOf(relations.double_damage_from),
      half_damage_from: namesOf(relations.half_damage_from),
      no_damage_from: namesOf(relations.no_damage_from)
    })
  }, onError)
}

// Row thumbnails use the small per-form sprite directly by id, bypassing a
// full /pokemon fetch — the bulk index already gives us the id for free.
function spriteUrlFor(spriteId) {
  return "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/" + spriteId + ".png"
}
