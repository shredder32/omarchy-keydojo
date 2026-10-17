.pragma library

// Physical key resolution. Hyprland matches Omarchy's digit and -/= binds by
// keycode (code:10..21) and everything else by the keysym on the base level of
// the active layout, so a combo is identified by keycode and labelled with
// whatever the user's layout prints on that key.

// US positions for keys Omarchy binds by keycode.
var KEYCODE_BOUND = {
  "1": 10, "2": 11, "3": 12, "4": 13, "5": 14, "6": 15, "7": 16, "8": 17, "9": 18, "0": 19,
  "MINUS": 20, "EQUAL": 21
}

// Fallback US keymap used when xkbcli is unavailable.
var US = {
  "ESCAPE": 9, "1": 10, "2": 11, "3": 12, "4": 13, "5": 14, "6": 15, "7": 16, "8": 17, "9": 18, "0": 19,
  "MINUS": 20, "EQUAL": 21, "BACKSPACE": 22, "TAB": 23,
  "Q": 24, "W": 25, "E": 26, "R": 27, "T": 28, "Y": 29, "U": 30, "I": 31, "O": 32, "P": 33,
  "BRACKETLEFT": 34, "BRACKETRIGHT": 35, "RETURN": 36,
  "A": 38, "S": 39, "D": 40, "F": 41, "G": 42, "H": 43, "J": 44, "K": 45, "L": 46,
  "SEMICOLON": 47, "APOSTROPHE": 48, "GRAVE": 49, "BACKSLASH": 51,
  "Z": 52, "X": 53, "C": 54, "V": 55, "B": 56, "N": 57, "M": 58,
  "COMMA": 59, "PERIOD": 60, "SLASH": 61, "SPACE": 65,
  "F1": 67, "F2": 68, "F3": 69, "F4": 70, "F5": 71, "F6": 72, "F7": 73, "F8": 74, "F9": 75, "F10": 76,
  "F11": 95, "F12": 96, "PRINT": 107, "HOME": 110, "UP": 111, "PRIOR": 112, "LEFT": 113,
  "RIGHT": 114, "END": 115, "DOWN": 116, "NEXT": 117, "INSERT": 118, "DELETE": 119,
  "F13": 191, "F14": 192, "F15": 193
}

var GLYPHS = {
  apostrophe: "'", grave: "`", igrave: "ì", egrave: "è", eacute: "é", ograve: "ò", agrave: "à",
  ugrave: "ù", plus: "+", minus: "-", equal: "=", comma: ",", period: ".", slash: "/",
  backslash: "\\", less: "<", bracketleft: "[", bracketright: "]", semicolon: ";",
  ssharp: "ß", numbersign: "#", dead_circumflex: "^", dead_acute: "´", dead_grave: "`",
  Return: "Enter", space: "Space", Escape: "Esc", Tab: "Tab", BackSpace: "⌫", Delete: "Del",
  Home: "Home", End: "End", Print: "PrtSc", Left: "←", Right: "→", Up: "↑", Down: "↓",
  Prior: "PgUp", Next: "PgDn", Insert: "Ins"
}

var MOD_ORDER = ["SUPER", "SHIFT", "CTRL", "ALT"]
var MOD_ALIASES = { "SUPER": "SUPER", "MOD4": "SUPER", "WIN": "SUPER", "META": "SUPER",
  "SHIFT": "SHIFT", "CTRL": "CTRL", "CONTROL": "CTRL", "ALT": "ALT", "MOD1": "ALT" }
var MOD_LABELS = { "SUPER": "Super", "SHIFT": "Shift", "CTRL": "Ctrl", "ALT": "Alt" }

function prettySym(sym) {
  if (!sym) return "?"
  if (GLYPHS[sym] !== undefined) return GLYPHS[sym]
  if (sym.length === 1) return sym.toUpperCase()
  return sym
}

// Parses `xkbcli compile-keymap` output into code<->symbol tables.
function parseXkb(text) {
  var codeByName = {}
  var symByName = {}
  var source = String(text || "")
  var symStart = source.indexOf("xkb_symbols")
  var codesPart = symStart === -1 ? source : source.slice(0, symStart)
  var symsPart = symStart === -1 ? "" : source.slice(symStart)
  var m
  var codeRe = /<([A-Za-z0-9_+-]+)>\s*=\s*([0-9]+)\s*;/g
  while ((m = codeRe.exec(codesPart)) !== null) codeByName[m[1]] = parseInt(m[2])
  // Entries span one or several lines: `key <AE01> { [ 1, exclam ] };` or
  // `key <FK09> {\n type= "...",\n symbols[1]= [ F9, ... ]\n };`
  var keyRe = /key\s*<([A-Za-z0-9_+-]+)>\s*\{([\s\S]*?)\};/g
  while ((m = keyRe.exec(symsPart)) !== null) {
    var body = m[2].replace(/symbols\[[^\]]*\]\s*=/g, "")
    var first = /\[\s*([^,\s\]]+)/.exec(body)
    if (first && symByName[m[1]] === undefined) symByName[m[1]] = first[1]
  }
  var map = { codeToSym: {}, symToCode: {}, loaded: false }
  for (var name in codeByName) {
    var code = codeByName[name]
    var sym = symByName[name]
    if (!sym || sym === "NoSymbol") continue
    map.codeToSym[code] = sym
    var upper = sym.toUpperCase()
    if (map.symToCode[upper] === undefined || code < map.symToCode[upper]) map.symToCode[upper] = code
    map.loaded = true
  }
  return map
}

function emptyKeymap() {
  return { codeToSym: {}, symToCode: {}, loaded: false }
}

// Returns { code, label } for a key name as printed by `omarchy menu
// keybindings --print`, or null when the key cannot be typed on this layout.
function resolveKey(keyName, keymap) {
  var upper = String(keyName).toUpperCase()
  var code
  if (KEYCODE_BOUND[upper] !== undefined) code = KEYCODE_BOUND[upper]
  else if (keymap.loaded) code = keymap.symToCode[upper]
  else code = US[upper]
  if (code === undefined) return null
  return { code: code, label: labelForCode(code, keymap, keyName) }
}

function labelForCode(code, keymap, fallbackName) {
  var sym = keymap.codeToSym[code]
  if (sym) return prettySym(sym)
  for (var name in US) if (US[name] === code) return prettySym(name.length === 1 ? name : name.charAt(0) + name.slice(1).toLowerCase())
  return fallbackName ? String(fallbackName) : ("#" + code)
}

function normalizeMods(tokens) {
  var set = {}
  for (var i = 0; i < tokens.length; i++) {
    var alias = MOD_ALIASES[String(tokens[i]).toUpperCase()]
    if (!alias) return null
    set[alias] = true
  }
  return MOD_ORDER.filter(function(m) { return set[m] })
}

function comboId(mods, code) {
  return mods.join("+") + "|" + code
}

function modLabel(mod) {
  return MOD_LABELS[mod] || mod
}
