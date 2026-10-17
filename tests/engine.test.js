// Runs the pure JS modules under node by stripping QML's .pragma/.import lines.
const fs = require("fs"), path = require("path"), vm = require("vm")
const root = path.join(__dirname, "..")
// Resolves `.import "x.js" as Name` relative to the importing file.
function load(file, extra) {
  const full = path.join(root, file)
  const src = fs.readFileSync(full, "utf8")
  const ctx = Object.assign({}, extra)
  for (const m of src.matchAll(/^\.import "([^"]+)" as (\w+)/gm)) {
    if (!(m[2] in ctx)) ctx[m[2]] = load(path.join(path.dirname(file), m[1]), extra)
  }
  vm.createContext(ctx); vm.runInContext(src.replace(/^\.(pragma|import).*$/gm, ""), ctx); return ctx
}
const Keymap = load("Keymap.js")
const Engine = load("Engine.js", { Keymap })
const I18n = load("I18n.js")
const [printFile, xkbFile] = process.argv.slice(2)
const keymap = Keymap.parseXkb(fs.readFileSync(xkbFile, "utf8"))
const parsed = Engine.parseBindings(fs.readFileSync(printFile, "utf8"), keymap)
const cards = Engine.buildCards(parsed.bindings)
console.log("bindings", parsed.bindings.length, "cards", cards.list.length, "skipped", parsed.skipped)
for (let t = 0; t < Engine.TIERS.length; t++) {
  const list = cards.list.filter(c => c.tier === t)
  console.log(`\n[${t}] ${Engine.TIERS[t]} (${list.length})`)
  for (const c of list) console.log("   ", I18n.desc("it", c.id, c.family ? c.members[0].n : null).padEnd(48),
    c.members.map(m => m.mods.map(Keymap.modLabel).concat(m.label).join("+")).slice(0, 3).join("  |  "))
}
const missing = cards.list.filter(c => !(c.id in I18n.TABLES.it.DESC)).map(c => c.id)
console.log("\nuntranslated:", missing)
// progress simulation
const p = Engine.newProgress()
for (const c of Engine.newCards(cards, p, 50)) Engine.grade(p, c.id, true, "learn")
console.log("learned", Engine.learnedCount(cards, p), "belt", Engine.belt(cards, p))
for (let i = 0; i < 3; i++) for (const c of cards.list.filter(c => c.tier === 0)) Engine.grade(p, c.id, true, "recall")
console.log("after recall belt", Engine.belt(cards, p), JSON.stringify(Engine.tierStats(cards, p, 1)))
const q = Engine.makeQuestion(cards.list[0])
console.log("options", Engine.recognizeOptions(cards, p, q).map(o => o.card.id))

// Spacing + speed: level 3 needs the move to be due and answered fast.
{
  const p = Engine.newProgress()
  const id = "Terminal"
  Engine.grade(p, id, true, "learn")
  Engine.grade(p, id, true, "recall", true)
  const early = Engine.grade(p, id, true, "recall", true)
  console.assert(early.early && early.level === 2, "not due yet -> stays at 2", early)
  p.cards[id].due = Date.now() - 1
  const slow = Engine.grade(p, id, true, "recall", false)
  console.assert(slow.slow && slow.level === 2, "due but slow -> stays at 2", slow)
  p.cards[id].due = Date.now() - 1
  const ok = Engine.grade(p, id, true, "recall", true)
  console.assert(ok.levelUp && ok.level === 3, "due and fast -> mastered", ok)
  console.log("spacing/speed rules:", early.level, slow.level, ok.level)
}

// Recognize distractors: known and confusable first.
{
  const p = Engine.newProgress()
  for (const c of cards.list.filter(c => c.tier === 0)) Engine.grade(p, c.id, true, "learn")
  const show = (desc) => {
    const card = cards.byId[desc]
    const q = { card, member: card.members[0] }
    const opts = Engine.recognizeOptions(cards, p, q)
    console.log(desc.padEnd(14), "→", opts.map(o => `${o.card.id} (${o.member.mods.map(Keymap.modLabel).concat(o.member.label).join("+")})`).join(" | "))
  }
  console.log("\nwhite belt, basics known:")
  show("Browser"); show("Terminal"); show("Close window")
  for (const c of cards.list.filter(c => c.tier <= 1)) p.cards[c.id] = { lvl: 3, due: 0, right: 3, wrong: 0 }
  console.log("orange belt:", Engine.belt(cards, p) >= 2 ? "yes" : "no (belt " + Engine.belt(cards, p) + ")")
  for (const c of cards.list.filter(c => c.tier <= 2)) p.cards[c.id] = { lvl: 3, due: 0, right: 3, wrong: 0 }
  console.log("belt now", Engine.belt(cards, p))
  show("Browser"); show("Terminal")
}

// Translations: every language has every UI key and every binding description.
{
  const Missions = load("Missions.js")
  const keys = new Set(Object.keys(I18n.TABLES.en.STRINGS))
  for (const run of Missions.RUNS) {
    keys.add(Missions.runTitleKey(run))
    for (const step of run.steps) if (step.text) keys.add(step.text)
  }
  const descKeys = Object.keys(I18n.TABLES.it.DESC)
  const missing = []
  for (const lang of I18n.LANGS) {
    const table = I18n.TABLES[lang]
    for (const k of keys) if (!(k in table.STRINGS)) missing.push(`${lang}:${k}`)
    if (lang !== "en") for (const k of descKeys) if (!(k in table.DESC)) missing.push(`${lang}:desc:${k}`)
    for (const k of Object.keys(table.STRINGS)) if (!keys.has(k)) missing.push(`${lang}:extra:${k}`)
  }
  console.assert(missing.length === 0, "translation gaps", missing)
  console.log("translations:", I18n.LANGS.join("+"), keys.size, "keys,", descKeys.length, "descriptions,", missing.length ? "GAPS " + missing.join(" ") : "complete")
  for (const lang of I18n.LANGS) console.log("  " + lang.padEnd(3), I18n.t(lang, "nextBelt", I18n.t(lang, "belt_yellow"), 9, 11, I18n.t(lang, "tier_basics")), "|", I18n.desc(lang, "Switch to workspace #", 3))
  console.log("defaults:", ["it_IT","de_DE","ja_JP","en_US"].map(l => l + "→" + I18n.defaultLang(l, "")).join(" "), "| en_US+de →", I18n.defaultLang("en_US", "de"), "| en_US+jp →", I18n.defaultLang("en_US", "jp"))
}
