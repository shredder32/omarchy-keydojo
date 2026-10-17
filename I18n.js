.pragma library
.import "lang/en.js" as En
.import "lang/it.js" as It
.import "lang/es.js" as Es
.import "lang/fr.js" as Fr
.import "lang/de.js" as De
.import "lang/ja.js" as Ja

// One file per language in lang/. English is the source; any key a language
// leaves out falls back to English. To add a language, copy lang/en.js,
// translate it, and list it here.

var TABLES = { en: En, it: It, es: Es, fr: Fr, de: De, ja: Ja }
var LANGS = ["en", "it", "es", "fr", "de", "ja"]

// Keyboard layouts that hint at a language when the locale doesn't match one.
var LAYOUT_LANGS = { it: "it", es: "es", latam: "es", fr: "fr", be: "fr", de: "de", at: "de", ch: "de", jp: "ja" }

function table(lang) {
  return TABLES[lang] || En
}

function t(lang, key) {
  var strings = table(lang).STRINGS
  var s = strings[key] !== undefined ? strings[key] : (En.STRINGS[key] !== undefined ? En.STRINGS[key] : key)
  for (var i = 2; i < arguments.length; i++) s = s.split("%" + (i - 1)).join(String(arguments[i]))
  return s
}

// Translates a binding description; families get their number filled in.
function desc(lang, template, n) {
  var names = table(lang).DESC
  var text = names[template] !== undefined ? names[template] : template
  if (n !== null && n !== undefined) text = text.split("#").join(String(n))
  return text
}

function langName(lang) {
  return table(lang).NAME
}

function nextLang(lang) {
  return LANGS[(LANGS.indexOf(lang) + 1) % LANGS.length]
}

function defaultLang(localeName, layout) {
  var code = String(localeName || "").slice(0, 2)
  if (TABLES[code] && code !== "en") return code
  var fromLayout = LAYOUT_LANGS[String(layout || "").split(",")[0]]
  if (fromLayout) return fromLayout
  return TABLES[code] ? code : "en"
}
