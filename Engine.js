.pragma library
.import "Keymap.js" as Keymap

// Pure game logic: turns `omarchy menu keybindings --print` into cards, sorts
// them into belts, and keeps the spaced-repetition progress object.

var TIERS = ["basics", "workspaces", "windows", "tools", "system", "apps", "master"]
var BELTS = ["white", "yellow", "orange", "green", "blue", "purple", "brown", "black"]
var BELT_COLORS = ["#f4f4f0", "#f2c94c", "#f2994a", "#6fcf97", "#56a8f2", "#a974e8", "#9a6b4f", "#1c1c1c"]

var MASTERED_LEVEL = 3
var CLEAR_RATIO = 0.8
var MAX_LEVEL = 5
// Review spacing per level, in minutes. The 30-minute check catches the
// early consolidation of a motor memory; later steps lean on sleep and spacing.
var INTERVALS = [0, 10, 30, 60 * 24, 60 * 24 * 3, 60 * 24 * 7]
// A move only counts as mastered when it comes out this fast.
var FAST_MS = 2500
var CLIMB_FREELY = 2

// `questions` and `seconds` set a session's length; the home tiles show them.
var LEARN_BATCH = 5
var MODES = [
  { id: "learn",     icon: "󰑴", rule: { learned: 0 } },
  { id: "recognize", icon: "󰈈", rule: { learned: 4 }, questions: 8 },
  { id: "recall",    icon: "󰌌", rule: { learned: 6 }, questions: 10 },
  { id: "blitz",     icon: "󱐋", rule: { belt: 1 }, seconds: 60 },
  { id: "missions",  icon: "󰓾", rule: { belt: 2 } }
]
// Recognize only shows the combo, so it can't carry a move past this level.
var RECOGNIZE_CAP = CLIMB_FREELY

var BASICS = /^(Terminal|Browser|File manager|Omarchy menu|Apps menu|Keybindings|Close window|Full screen|System menu|Lock system|Toggle window floating\/tiling)$/
var MASTER = /monitor|group|Expand window|Shrink window|webcam|window width|scaling|laptop display|mirroring|zoom|square aspect/i
var WINDOWS = /^(Focus on|Swap window|Toggle window split|Pop window out|Full width|Tiled full screen|Pseudo window|Close all windows|Reveal active window|Toggle workspace layout)/
var WORKSPACES = /workspace|scratchpad/i
var TOOLS = /Screenshot|Screenrecording|Color picker|Universal|Clipboard|Emojis|Capture menu|OCR|Theme menu|Background switcher|Calculator|Transcode|^Share$|dictation|Copy URL|Download Video/i
var SYSTEM = /notification|nightlight|idle|transparency|gaps|top bar|Bar panel|^Audio$|Bluetooth|Network|Display|Hardware|Activity|Show time|battery|Calendar|reminder|weather|Toggle menu|Passwords|vault/i
var APPS = /^(Tmux|Herdr|Agent|Editor|Music|Docker|Obsidian|Email|Signal|Browser \(private\)|File manager \(cwd\))$/

function classify(desc, mods) {
  if (BASICS.test(desc)) return 0
  if (MASTER.test(desc)) return 6
  if (WINDOWS.test(desc)) return 2
  if (WORKSPACES.test(desc)) return 1
  if (TOOLS.test(desc)) return 3
  if (SYSTEM.test(desc)) return 4
  if (APPS.test(desc)) return 5
  var hasSuper = mods.indexOf("SUPER") !== -1
  var hasShift = mods.indexOf("SHIFT") !== -1
  var hasCtrl = mods.indexOf("CTRL") !== -1
  if (hasSuper && hasShift && !hasCtrl) return 5
  return 6
}

// ------------------------------------------------------------ parsing

function parseBindings(text, keymap) {
  var out = []
  var seen = {}
  var skipped = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^\s*(.+?)\s+→\s+(.+?)\s*$/.exec(lines[i])
    if (!m) continue
    var left = m[1]
    var desc = m[2]
    var plus = left.lastIndexOf(" + ")
    var modText = plus === -1 ? "" : left.slice(0, plus)
    var keyName = (plus === -1 ? left : left.slice(plus + 3)).trim()
    if (/mouse|XF86|^code:/i.test(keyName)) continue
    var mods = Keymap.normalizeMods(modText ? modText.trim().split(/\s+/) : [])
    if (!mods) continue
    var key = Keymap.resolveKey(keyName, keymap)
    if (!key) { skipped.push(desc); continue }
    var combo = Keymap.comboId(mods, key.code)
    if (seen[combo]) continue
    seen[combo] = true
    out.push({ desc: desc, mods: mods, keyName: keyName, code: key.code, label: key.label, combo: combo })
  }
  return { bindings: out, skipped: skipped }
}

function buildCards(bindings) {
  var cards = []
  var byId = {}
  for (var i = 0; i < bindings.length; i++) {
    var b = bindings[i]
    var id = b.desc
    var n = null
    var fm = /^(.*\D)(\d+)$/.exec(b.desc)
    if (fm && /^[0-9]$/.test(b.keyName)) {
      id = fm[1] + "#"
      n = parseInt(fm[2])
    }
    var card = byId[id]
    if (!card) {
      card = { id: id, family: n !== null, tier: classify(b.desc, b.mods), members: [], order: cards.length }
      byId[id] = card
      cards.push(card)
    }
    card.members.push({ desc: b.desc, n: n, mods: b.mods, code: b.code, label: b.label, combo: b.combo })
  }
  for (var c = 0; c < cards.length; c++) {
    if (cards[c].family) cards[c].members.sort(function(a, b) { return a.n - b.n })
  }
  return { list: cards, byId: byId, byCombo: indexCombos(cards) }
}

function indexCombos(cards) {
  var idx = {}
  for (var i = 0; i < cards.length; i++)
    for (var j = 0; j < cards[i].members.length; j++)
      idx[cards[i].members[j].combo] = { card: cards[i], member: cards[i].members[j] }
  return idx
}

// A question is one card plus the member being asked. Families ask for a
// specific number; plain cards accept any of their combos.
function makeQuestion(card) {
  var member = card.family
    ? card.members[Math.floor(Math.random() * card.members.length)]
    : card.members[0]
  return { card: card, member: member }
}

function isCorrect(question, combo) {
  if (question.card.family) return question.member.combo === combo
  for (var i = 0; i < question.card.members.length; i++)
    if (question.card.members[i].combo === combo) return true
  return false
}

// ------------------------------------------------------------ progress

function newProgress() {
  return { version: 1, cards: {}, xp: 0, bestBlitz: 0, lang: "", missionsDone: 0, answered: 0 }
}

function loadProgress(text) {
  var p = newProgress()
  try {
    var raw = JSON.parse(text)
    if (raw && typeof raw === "object") for (var k in raw) p[k] = raw[k]
  } catch (e) {}
  if (!p.cards || typeof p.cards !== "object") p.cards = {}
  return p
}

function stateOf(progress, id) {
  return progress.cards[id] || { lvl: 0, due: 0, right: 0, wrong: 0 }
}

function level(progress, id) {
  return stateOf(progress, id).lvl
}

function dayKey(date) {
  var d = date || new Date()
  function pad(v) { return v < 10 ? "0" + v : "" + v }
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}


// Applies an answer. Returns { xp, levelUp, level, slow, early, due } for feedback.
// Levels 1-2 can be climbed in one sitting; above that a move must be due
// for review (spacing) and answered fast (automaticity).
function grade(progress, cardId, correct, mode, fast) {
  var now = Date.now()
  var s = stateOf(progress, cardId)
  s = { lvl: s.lvl, due: s.due, right: s.right, wrong: s.wrong }
  var before = s.lvl
  var slow = false
  var early = false
  if (correct) {
    s.right++
    if (mode === "learn") s.lvl = Math.max(s.lvl, 1)
    else if (mode === "recognize") { if (s.lvl < CLIMB_FREELY) s.lvl = Math.max(1, s.lvl + 1) }
    else if (s.lvl < CLIMB_FREELY) s.lvl = s.lvl + 1
    else if (now < s.due) early = true
    else if (!fast) slow = true
    else s.lvl = Math.min(MAX_LEVEL, s.lvl + 1)
  } else {
    s.wrong++
    if (mode === "recall") s.lvl = Math.max(1, s.lvl - 1)
  }
  if (s.lvl !== before || slow) s.due = now + INTERVALS[s.lvl] * 60000
  // A miss never pushes a review further out. Recall also drops the level,
  // so the move comes back in ten minutes and must climb again from there.
  if (!correct) s.due = Math.min(s.due || 0, now + INTERVALS[mode === "recall" ? Math.min(1, s.lvl) : s.lvl] * 60000)
  progress.cards[cardId] = s
  progress.answered = (progress.answered || 0) + 1
  var xp = correct ? 10 + (fast ? 5 : 0) : 0
  progress.xp = (progress.xp || 0) + xp
  return { xp: xp, levelUp: s.lvl > before, level: s.lvl, slow: slow, early: early, due: s.due }
}

// ------------------------------------------------------------ belts & unlocks

function tierStats(cards, progress, tier) {
  var total = 0, mastered = 0, learned = 0
  for (var i = 0; i < cards.list.length; i++) {
    var c = cards.list[i]
    if (c.tier !== tier) continue
    total++
    var lvl = level(progress, c.id)
    if (lvl >= 1) learned++
    if (lvl >= MASTERED_LEVEL) mastered++
  }
  var needed = Math.ceil(total * CLEAR_RATIO)
  return { total: total, learned: learned, mastered: mastered, needed: needed, cleared: mastered >= needed }
}

function belt(cards, progress) {
  var b = 0
  while (b < TIERS.length && tierStats(cards, progress, b).cleared) b++
  return b
}

function learnedCount(cards, progress) {
  var n = 0
  for (var i = 0; i < cards.list.length; i++) if (level(progress, cards.list[i].id) >= 1) n++
  return n
}

function masteredCount(cards, progress) {
  var n = 0
  for (var i = 0; i < cards.list.length; i++) if (level(progress, cards.list[i].id) >= MASTERED_LEVEL) n++
  return n
}

function modeUnlocked(mode, cards, progress) {
  if (mode.rule.belt !== undefined) return belt(cards, progress) >= mode.rule.belt
  return learnedCount(cards, progress) >= mode.rule.learned
}

function unlockedTier(cards, progress) {
  return Math.min(belt(cards, progress), TIERS.length - 1)
}

function newCards(cards, progress, limit) {
  var top = unlockedTier(cards, progress)
  var out = []
  for (var t = 0; t <= top && out.length < limit; t++)
    for (var i = 0; i < cards.list.length && out.length < limit; i++) {
      var c = cards.list[i]
      if (c.tier === t && level(progress, c.id) === 0) out.push(c)
    }
  return out
}

function learnedCards(cards, progress) {
  var top = unlockedTier(cards, progress)
  return cards.list.filter(function(c) { return c.tier <= top && level(progress, c.id) >= 1 })
}

// Learned moves an answer can level up right now: due for review, or still
// low enough to climb without waiting.
function climbableCards(cards, progress) {
  var now = Date.now()
  return learnedCards(cards, progress).filter(function(c) {
    var s = stateOf(progress, c.id)
    return s.lvl < CLIMB_FREELY || now >= s.due
  })
}

function dueCards(cards, progress) {
  var now = Date.now()
  return learnedCards(cards, progress).filter(function(c) { return now >= stateOf(progress, c.id).due })
}

// Milliseconds until the next learned move comes due, or -1 if none.
function nextDueIn(cards, progress) {
  var now = Date.now()
  var best = -1
  var pool = learnedCards(cards, progress)
  for (var i = 0; i < pool.length; i++) {
    var wait = stateOf(progress, pool[i].id).due - now
    if (wait > 0 && (best === -1 || wait < best)) best = wait
  }
  return best
}

// Moves due for review come first; with none due, any learned move.
// Weighted pick that favours low levels and overdue cards, skipping the last
// few cards asked so the same prompt does not repeat back to back.
function pickReview(cards, progress, recent) {
  var due = dueCards(cards, progress).filter(function(c) { return recent.indexOf(c.id) === -1 })
  var pool = due.length > 0 ? due : learnedCards(cards, progress)
  if (pool.length === 0) return null
  var avoid = pool.length > recent.length + 1 ? recent : recent.slice(-1)
  var now = Date.now()
  var weights = []
  var total = 0
  for (var i = 0; i < pool.length; i++) {
    var s = stateOf(progress, pool[i].id)
    var w = avoid.indexOf(pool[i].id) !== -1 ? 0 : (MAX_LEVEL + 1 - s.lvl) * (MAX_LEVEL + 1 - s.lvl) * (now >= s.due ? 3 : 1)
    weights.push(w)
    total += w
  }
  if (total <= 0) return pool[Math.floor(Math.random() * pool.length)]
  var r = Math.random() * total
  for (var j = 0; j < pool.length; j++) {
    r -= weights[j]
    if (r <= 0) return pool[j]
  }
  return pool[pool.length - 1]
}

function shuffle(list) {
  var a = list.slice()
  for (var i = a.length - 1; i > 0; i--) {
    var j = Math.floor(Math.random() * (i + 1))
    var t = a[i]; a[i] = a[j]; a[j] = t
  }
  return a
}

// How easy it is to mix up two combos: the same key under different
// modifiers is the classic trap, then the same modifiers on another key.
function similarity(a, b) {
  var score = 0
  var modsA = a.mods.join("+")
  var modsB = b.mods.join("+")
  var shared = a.mods.filter(function(m) { return b.mods.indexOf(m) !== -1 }).length
  var modDistance = a.mods.length + b.mods.length - 2 * shared
  if (a.code === b.code && modsA !== modsB) score += 3
  if (modsA === modsB && a.code !== b.code) score += 2
  if (modDistance === 1) score += 1
  return score
}

// For a family card, the member that looks most like the question.
function closestMember(card, member) {
  var best = card.members[0]
  var bestScore = -1
  for (var i = 0; i < card.members.length; i++) {
    var sc = similarity(member, card.members[i])
    if (sc > bestScore) { best = card.members[i]; bestScore = sc }
  }
  return { member: best, score: bestScore }
}

var UNKNOWN_DISTRACTORS_BELT = 2
var UNKNOWN_MIN_SIMILARITY = 2

// Four choices for "what does this combo do?". Wrong answers come from moves
// the player already knows, so none can be ruled out as "never seen it";
// among those the most confusable win. From the orange belt on, unknown moves
// join too, but only when they look a lot like the right combo.
function recognizeOptions(cards, progress, question) {
  var target = question.card
  var allowUnknown = belt(cards, progress) >= UNKNOWN_DISTRACTORS_BELT
  var scored = []
  for (var i = 0; i < cards.list.length; i++) {
    var c = cards.list[i]
    if (c.id === target.id) continue
    var close = closestMember(c, question.member)
    var known = level(progress, c.id) >= 1
    if (!known && !(allowUnknown && close.score >= UNKNOWN_MIN_SIMILARITY)) continue
    scored.push({ card: c, member: close.member, score: close.score + (c.tier === target.tier ? 0.5 : 0) + Math.random() * 0.6 })
  }
  scored.sort(function(a, b) { return b.score - a.score })

  var opts = [{ card: target, member: question.member }]
  for (var j = 0; j < scored.length && opts.length < 4; j++) opts.push({ card: scored[j].card, member: scored[j].member })

  // Too few known moves yet: top up with the most similar unknown ones.
  if (opts.length < 4) {
    var fill = cards.list
      .filter(function(c) { return opts.every(function(o) { return o.card.id !== c.id }) })
      .map(function(c) { var close = closestMember(c, question.member); return { card: c, member: close.member, score: close.score + Math.random() * 0.6 } })
      .sort(function(a, b) { return b.score - a.score })
    for (var k = 0; k < fill.length && opts.length < 4; k++) opts.push({ card: fill[k].card, member: fill[k].member })
  }
  return shuffle(opts)
}
