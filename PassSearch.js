// Fuzzy matching and ranking for pass entry names. Pure functions so the
// overlay stays declarative and this file can be tested with node.

function parseEntries(raw) {
  var lines = String(raw || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.slice(-4) !== ".gpg") continue
    out.push(line.slice(0, -4))
  }
  out.sort(byName)
  return out
}

function byName(a, b) {
  var x = a.toLowerCase(), y = b.toLowerCase()
  return x < y ? -1 : (x > y ? 1 : 0)
}

function parseRecent(raw) {
  var lines = String(raw || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line && out.indexOf(line) < 0) out.push(line)
  }
  return out
}

// Subsequence match. Returns { score, positions } or null. Contiguous runs,
// word/segment starts and early matches score higher.
function fuzzyMatch(text, query) {
  var hay = text.toLowerCase()
  var needle = query.toLowerCase().replace(/\s+/g, "")
  if (!needle) return { score: 0, positions: [] }

  var direct = hay.indexOf(needle)
  if (direct >= 0) {
    var positions = []
    for (var d = 0; d < needle.length; d++) positions.push(direct + d)
    var boundary = direct === 0 || /[\/._@-]/.test(hay[direct - 1])
    return { score: 1000 - direct * 2 + (boundary ? 200 : 0) - hay.length * 0.1, positions: positions }
  }

  var pos = []
  var score = 0
  var h = 0
  var prev = -2
  for (var n = 0; n < needle.length; n++) {
    var c = needle[n]
    while (h < hay.length && hay[h] !== c) h++
    if (h >= hay.length) return null
    pos.push(h)
    if (h === prev + 1) score += 15
    if (h === 0 || /[\/._@-]/.test(hay[h - 1])) score += 10
    score -= (h - prev - 1) * 0.5
    prev = h
    h++
  }
  return { score: score - hay.length * 0.1, positions: pos }
}

// Ranked rows: { name, score, positions, recent }. With an empty query,
// recently used entries come first, then everything alphabetically.
function rank(entries, recent, query, limit) {
  var recentRank = {}
  for (var r = 0; r < recent.length; r++) recentRank[recent[r]] = r

  var rows = []
  var q = String(query || "").trim()
  for (var i = 0; i < entries.length; i++) {
    var name = entries[i]
    var m = fuzzyMatch(name, q)
    if (!m) continue
    var isRecent = recentRank.hasOwnProperty(name)
    var score = m.score + (isRecent ? 60 - Math.min(recentRank[name], 50) : 0)
    rows.push({ name: name, score: score, positions: m.positions, recent: isRecent })
  }

  if (!q) {
    rows.sort(function(a, b) {
      if (a.recent !== b.recent) return a.recent ? -1 : 1
      if (a.recent) return recentRank[a.name] - recentRank[b.name]
      return byName(a.name, b.name)
    })
  } else {
    rows.sort(function(a, b) { return (b.score - a.score) || byName(a.name, b.name) })
  }

  return rows.slice(0, limit || 200)
}

function escapeHtml(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// StyledText with matched characters coloured and bold.
function highlight(text, positions, offset, color) {
  if (!positions || positions.length === 0) return escapeHtml(text)
  var set = {}
  for (var i = 0; i < positions.length; i++) set[positions[i] - offset] = true
  var out = ""
  var open = false
  for (var c = 0; c < text.length; c++) {
    var on = !!set[c]
    if (on && !open) { out += "<b><font color=\"" + color + "\">"; open = true }
    if (!on && open) { out += "</font></b>"; open = false }
    out += escapeHtml(text[c])
  }
  if (open) out += "</font></b>"
  return out
}

if (typeof module !== "undefined") {
  module.exports = { parseEntries: parseEntries, parseRecent: parseRecent, fuzzyMatch: fuzzyMatch, rank: rank, highlight: highlight }
}
