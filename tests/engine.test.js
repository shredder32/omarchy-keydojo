// Runs the pure JS modules under node by stripping QML's .pragma/.import lines.
const fs = require("fs"), path = require("path"), vm = require("vm")
const root = path.join(__dirname, "..")
function load(file, extra) {
  const src = fs.readFileSync(path.join(root, file), "utf8").replace(/^\.(pragma|import).*$/gm, "")
  const ctx = Object.assign({}, extra)
  vm.createContext(ctx); vm.runInContext(src, ctx); return ctx
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
const missing = cards.list.filter(c => !(c.id in I18n.DESC_IT)).map(c => c.id)
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
