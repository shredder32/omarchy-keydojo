.pragma library

// Real-desktop missions. Each step names the card it trains and a matcher fed
// with raw Hyprland events (name, data). Every run cleans up after itself, and
// none asks for anything destructive (close all, lock, power).

var BROWSER = /chrom|brave|firefox|zen|vivaldi|edge|librewolf|helium|qutebrowser/i
var FILES = /nautilus|thunar|dolphin|nemo|pcmanfm|files|yazi/i
var IGNORED_LAYERS = /^(keydojo|omarchy-bar|omarchy-osd|omarchy-notifications|omarchy-background|hyprpaper|swww|selection)/

function parts(data) { return String(data || "").split(",") }

function opened(match) {
  return function(name, data, ctx, slot) {
    if (name !== "openwindow") return false
    var p = parts(data)
    var cls = p[2] || ""
    if (!match(cls)) return false
    ctx[slot || "win"] = p[0]
    // A new window takes focus right away; that is not the user moving focus.
    ctx.focused = p[0]
    return true
  }
}

var openTerminal = opened(function(cls) { return !BROWSER.test(cls) && !FILES.test(cls) })
var openFiles = opened(function(cls) { return FILES.test(cls) })

function closedOurs(name, data, ctx) {
  if (name !== "closewindow") return false
  var addr = parts(data)[0]
  if (addr !== ctx.win && addr !== ctx.win2) return false
  if (addr === ctx.win) ctx.win = ""
  else ctx.win2 = ""
  return true
}

function fullscreen(on) {
  return function(name, data) { return name === "fullscreen" && String(data) === (on ? "1" : "0") }
}

function floating(on) {
  return function(name, data, ctx) {
    var p = parts(data)
    return name === "changefloatingmode" && p[0] === ctx.win && p[1] === (on ? "1" : "0")
  }
}

function popped(on) {
  return function(name, data, ctx) {
    var p = parts(data)
    if (p[0] !== ctx.win) return false
    return (name === "pin" || name === "changefloatingmode") && p[1] === (on ? "1" : "0")
  }
}

function movedTo(slot) {
  return function(name, data, ctx) {
    var p = parts(data)
    return name === "movewindowv2" && p[0] === ctx.win && String(p[1]) === String(ctx[slot])
  }
}

function switchedTo(slot) {
  return function(name, data, ctx) {
    return name === "workspacev2" && String(parts(data)[0]) === String(ctx[slot])
  }
}

function toScratchpad(name, data, ctx) {
  var p = parts(data)
  return name === "movewindowv2" && p[0] === ctx.win && /scratchpad/.test(p[2] || "")
}

function scratchpad(shown) {
  return function(name, data) {
    if (name !== "activespecialv2" && name !== "activespecial") return false
    var visible = /scratchpad/.test(String(data))
    return visible === shown
  }
}

function focusedOther(name, data, ctx) {
  if (name !== "activewindowv2") return false
  var addr = parts(data)[0]
  if (!addr || addr === ctx.focused) return false
  var ours = addr === ctx.win || addr === ctx.win2
  if (ours) ctx.focused = addr
  return ours
}

function group(on) {
  return function(name, data) { return name === "togglegroup" && parts(data)[0] === (on ? "1" : "0") }
}

function layerOpened(pattern) {
  return function(name, data, ctx) {
    if (name !== "openlayer") return false
    var ns = String(data)
    if (IGNORED_LAYERS.test(ns)) return false
    if (pattern && !pattern.test(ns)) return false
    ctx.layer = ns
    return true
  }
}

function layerClosed(name, data, ctx) {
  return name === "closelayer" && String(data) === ctx.layer
}

// `n` names a ctx slot holding the workspace number for family cards.
var RUNS = [
  { id: "first-day", tier: 0, steps: [
    { card: "Terminal", match: openTerminal },
    { card: "Full screen", match: fullscreen(true) },
    { card: "Full screen", text: "step_unfullscreen", match: fullscreen(false) },
    { card: "Toggle window floating/tiling", match: floating(true) },
    { card: "Toggle window floating/tiling", text: "step_retile", match: floating(false) },
    { card: "Close window", match: closedOurs }
  ] },
  { id: "menus", tier: 0, steps: [
    { card: "Omarchy menu", match: layerOpened(null) },
    { text: "closeWithEsc", match: layerClosed },
    { card: "Keybindings", match: layerOpened(null) },
    { text: "closeWithEsc", match: layerClosed },
    { card: "Apps menu", match: layerOpened(null) },
    { text: "closeWithEsc", match: layerClosed }
  ] },
  { id: "moving-day", tier: 1, steps: [
    { card: "Terminal", match: openTerminal },
    { card: "Move window silently to workspace #", n: "target", match: movedTo("target") },
    { card: "Switch to workspace #", n: "target", match: switchedTo("target") },
    { card: "Former workspace", match: switchedTo("origin") },
    { card: "Former workspace", text: "step_formerAgain", match: switchedTo("target") },
    { card: "Close window", match: closedOurs },
    { card: "Switch to workspace #", n: "origin", match: switchedTo("origin") }
  ] },
  { id: "follow-me", tier: 1, steps: [
    { card: "Terminal", match: openTerminal },
    { card: "Move window to workspace #", n: "target", match: movedTo("target") },
    { card: "Close window", match: closedOurs },
    { card: "Switch to workspace #", n: "origin", match: switchedTo("origin") }
  ] },
  { id: "scratchpad", tier: 1, steps: [
    { card: "Terminal", match: openTerminal },
    { card: "Move window to scratchpad", match: toScratchpad },
    { card: "Toggle scratchpad", match: scratchpad(true) },
    { card: "Toggle scratchpad", text: "step_hideScratch", match: scratchpad(false) },
    { card: "Toggle scratchpad", text: "step_showScratch", match: scratchpad(true) },
    { card: "Close window", match: closedOurs }
  ] },
  { id: "two-windows", tier: 2, steps: [
    { card: "Terminal", match: openTerminal },
    { card: "File manager", match: function(n, d, ctx) { return openFiles(n, d, ctx, "win2") } },
    { card: "Focus on left window", match: focusedOther },
    { card: "Focus on right window", match: focusedOther },
    { card: "Toggle window grouping", match: group(true) },
    { card: "Toggle window grouping", text: "step_ungroup", match: group(false) },
    { card: "Close window", match: closedOurs },
    { card: "Close window", text: "step_closeOther", match: closedOurs }
  ] },
  { id: "pop-out", tier: 2, steps: [
    { card: "Terminal", match: openTerminal },
    { card: "Pop window out (float & pin)", match: popped(true) },
    { card: "Pop window out (float & pin)", text: "step_popBack", match: popped(false) },
    { card: "Full width", match: fullscreen(true) },
    { card: "Full width", text: "step_unfullwidth", match: fullscreen(false) },
    { card: "Close window", match: closedOurs }
  ] },
  { id: "toolbox", tier: 3, steps: [
    { card: "Emojis", match: layerOpened(/emoji/) },
    { text: "closeWithEsc", match: layerClosed },
    { card: "Clipboard manager", match: layerOpened(/clipboard/) },
    { text: "closeWithEsc", match: layerClosed },
    { card: "Capture menu", match: layerOpened(null) },
    { text: "closeWithEsc", match: layerClosed }
  ] }
]

// Mission step and run titles live in I18n.js under the same keys
// (`step_*`, and `run_*` from the run id with dashes as underscores).
function runTitleKey(run) {
  return "run_" + run.id.replace(/-/g, "_")
}

function available(cardsById, maxTier) {
  return RUNS.filter(function(run) {
    if (run.tier > maxTier) return false
    for (var i = 0; i < run.steps.length; i++)
      if (run.steps[i].card && !cardsById[run.steps[i].card]) return false
    return true
  })
}

// Picks the least-played run; ties go to the earliest (easiest) one.
function pick(runs, played) {
  var best = null
  for (var i = 0; i < runs.length; i++) {
    var count = played[runs[i].id] || 0
    if (!best || count < (played[best.id] || 0)) best = runs[i]
  }
  return best
}

function newContext(originWs, occupied) {
  var target = 0
  for (var n = 2; n <= 9 && !target; n++) if (n !== originWs && occupied.indexOf(n) === -1) target = n
  if (!target) target = originWs === 9 ? 8 : 9
  return { win: "", win2: "", focused: "", layer: "", origin: originWs > 0 && originWs <= 10 ? originWs : 1, target: target }
}
