import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui
import "Engine.js" as Engine
import "Keymap.js" as Keymap
import "I18n.js" as I18n
import "Missions.js" as Missions

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "io.github.shredder32.keydojo"
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/keydojo"

  // ------------------------------------------------------------ theme

  readonly property color fg: Color.menu.text
  readonly property color bg: Color.menu.background
  readonly property color accent: Color.accent
  readonly property color good: "#7bd88f"
  readonly property color bad: Color.urgent
  readonly property string font: Style.font.family
  readonly property int radius: Math.max(6, Style.cornerRadius)

  // ------------------------------------------------------------ state

  property bool opened: false
  property string screen: "loading"
  property string lang: I18n.defaultLang(Qt.locale().name)
  property var progress: Engine.newProgress()
  property bool progressReady: false
  property var keymap: Keymap.emptyKeymap()
  property var cards: null
  property var skipped: []
  // Bumped after every progress mutation so derived bindings re-evaluate.
  property int revision: 0
  property string layoutHint: ""
  property var heldMods: ({})
  property int homeSel: 0
  property string homeMessage: ""

  // Session
  property string mode: ""
  property var queue: []
  property int qIndex: 0
  property int qTotal: 0
  property var question: null
  property string phase: ""
  property bool hintShown: false
  property int attempts: 0
  property double askedAt: 0
  property bool inputLocked: false
  property string feedbackKind: ""
  property string feedbackText: ""
  property var pressed: null
  property var recent: []
  property int sCorrect: 0
  property int sAnswered: 0
  property int sXp: 0
  property int sLevelUps: 0
  property int sBeltBefore: 0
  property var sModesBefore: []
  property bool beltUp: false
  property var newModes: []
  property var options: []
  property int optSel: 0
  property int optChosen: -1

  // Blitz
  property real timeLeft: 60
  property int score: 0
  property int mult: 1
  property int streakCount: 0
  property bool newRecord: false

  // Missions
  property var missionRun: null
  property var missionCtx: ({})
  property int missionStep: 0
  property bool missionHint: false
  property int missionClean: 0
  property bool missionFlash: false

  readonly property var learnModes: Engine.MODES
  readonly property int belt: { root.revision; return root.cards ? Engine.belt(root.cards, root.progress) : 0 }
  readonly property int learned: { root.revision; return root.cards ? Engine.learnedCount(root.cards, root.progress) : 0 }
  readonly property int totalCards: root.cards ? root.cards.list.length : 0
  readonly property var tierNow: {
    root.revision
    if (!root.cards || root.belt >= Engine.TIERS.length) return null
    return Engine.tierStats(root.cards, root.progress, root.belt)
  }
  // Ticks while open so "due now" counts stay honest.
  property double clock: Date.now()
  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.clock = Date.now()
  }
  readonly property int dueNow: { root.revision; root.clock; return root.cards ? Engine.dueCards(root.cards, root.progress).length : 0 }
  readonly property double nextDue: { root.revision; root.clock; return root.cards ? Engine.nextDueIn(root.cards, root.progress) : -1 }

  function duration(ms) {
    var min = Math.max(1, Math.round(ms / 60000))
    if (min < 60) return root.tr("minutes", min)
    var h = Math.round(min / 60)
    if (h < 24) return root.tr("hours", h)
    return root.tr("days", Math.round(h / 24))
  }

  readonly property string reviewLine: {
    if (root.learned === 0) return ""
    if (root.dueNow > 0) return root.tr("dueNow", root.dueNow)
    return root.nextDue > 0 ? root.tr("nextReview", root.duration(root.nextDue)) : ""
  }

  readonly property var upNext: {
    root.revision
    return root.cards ? Engine.newCards(root.cards, root.progress, 6) : []
  }
  readonly property var modeStates: {
    root.revision
    var out = []
    for (var i = 0; i < Engine.MODES.length; i++) {
      var m = Engine.MODES[i]
      var unlocked = root.cards ? Engine.modeUnlocked(m, root.cards, root.progress) : i === 0
      var lockText = m.rule.belt !== undefined ? root.tr("lock_belt", root.beltName(m.rule.belt).toLowerCase()) : root.tr("lock_learned", m.rule.learned)
      out.push({ unlocked: unlocked, lockText: lockText })
    }
    return out
  }

  readonly property bool missionVisible: opened && (screen === "mission" || screen === "missionDone")
  readonly property bool capturing: opened && !missionVisible

  function tr() {
    return I18n.t.apply(null, [root.lang].concat(Array.prototype.slice.call(arguments)))
  }

  function beltName(i) { return tr("belt_" + Engine.BELTS[Math.min(i, Engine.BELTS.length - 1)]) }
  function tierName(i) { return tr("tier_" + Engine.TIERS[Math.min(i, Engine.TIERS.length - 1)]) }
  function modeName(i) { return tr("mode_" + Engine.MODES[i].id) }
  function modeIndex(id) { return Engine.MODES.map(function(m) { return m.id }).indexOf(id) }

  function questionText(q) {
    if (!q) return ""
    return I18n.desc(root.lang, q.card.id, q.card.family ? q.member.n : null)
  }

  // ------------------------------------------------------------ lifecycle

  function open(payloadJson) {
    root.clock = Date.now()
    root.opened = true
    root.heldMods = ({})
    root.homeMessage = ""
    if (root.screen !== "loading") root.screen = "home"
    keymapProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    blitzTimer.stop()
    root.opened = false
    if (root.screen !== "loading") root.screen = "home"
    root.saveProgress()
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  onCapturingChanged: root.setCapture(root.capturing)
  Component.onDestruction: if (root.capturing) root.setCapture(false)

  // While capturing, Hyprland sits in an empty submap so every combo reaches
  // the overlay. Super+Ctrl+Alt+Esc inside it is the way out if anything
  // goes wrong, and bin/keydojo-guard resets it if the overlay vanishes.
  readonly property string captureScript: [
    'if ! hyprctl binds -j | jq -e \'any(.[]; .submap == "keydojo")\' >/dev/null 2>&1; then',
    '  hyprctl eval "hl.define_submap(\\"keydojo\\", function() hl.bind(\\"SUPER + CTRL + ALT + ESCAPE\\", function() hl.dispatch(hl.dsp.submap(\\"reset\\")); hl.exec_cmd(\\"omarchy-shell shell hide $1\\") end) end)" >/dev/null',
    'fi',
    'hyprctl dispatch \'hl.dsp.submap("keydojo")\' >/dev/null',
    'setsid -f bash "$2" >/dev/null 2>&1'
  ].join("\n")

  function setCapture(on) {
    if (on) Quickshell.execDetached(["bash", "-c", root.captureScript, "keydojo", root.pluginId, root.pluginDir + "/bin/keydojo-guard"])
    else Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("reset")'])
  }

  // ------------------------------------------------------------ data

  Process {
    id: keymapProc
    command: ["bash", root.pluginDir + "/bin/keydojo-keymap"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.keymap = Keymap.parseXkb(text)
        var layout = /keydojo-layout: (\S+)/.exec(text)
        root.layoutHint = layout ? layout[1] : ""
        root.pickDefaultLang()
        bindsProc.running = true
      }
    }
  }

  Process {
    id: bindsProc
    command: ["bash", "-c", 'PATH="$1/bin:$PATH" omarchy-menu-keybindings --print', "keydojo", root.omarchyPath]
    stdout: StdioCollector {
      onStreamFinished: root.loadBindings(text)
    }
  }

  function loadBindings(text) {
    var parsed = Engine.parseBindings(text, root.keymap)
    if (parsed.bindings.length === 0 && root.cards) return
    root.cards = Engine.buildCards(parsed.bindings)
    root.skipped = parsed.skipped
    root.revision++
    if (root.screen === "loading") root.screen = "home"
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
    running: true
    onExited: progressFile.path = root.stateDir + "/progress.json"
  }

  FileView {
    id: progressFile
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyProgress(Engine.loadProgress(text()))
    onLoadFailed: root.applyProgress(Engine.newProgress())
  }

  function applyProgress(p) {
    if (root.progressReady) return
    root.progress = p
    if (p.lang === "it" || p.lang === "en") root.lang = p.lang
    else root.pickDefaultLang()
    root.progressReady = true
    root.revision++
  }

  // No saved choice yet: Italian when either the locale or the keyboard is.
  function pickDefaultLang() {
    if (root.progress.lang === "it" || root.progress.lang === "en") return
    root.lang = I18n.defaultLang(Qt.locale().name) === "it" || root.layoutHint.indexOf("it") === 0 ? "it" : "en"
  }

  function saveProgress() {
    if (!root.progressReady) return
    progressFile.setText(JSON.stringify(root.progress) + "\n")
  }

  // ------------------------------------------------------------ keys

  function modForKey(key) {
    if (key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R) return "SUPER"
    if (key === Qt.Key_Shift) return "SHIFT"
    if (key === Qt.Key_Control) return "CTRL"
    if (key === Qt.Key_Alt || key === Qt.Key_AltGr) return "ALT"
    return ""
  }

  function modsFrom(modifiers) {
    var out = []
    if (modifiers & Qt.MetaModifier) out.push("SUPER")
    if (modifiers & Qt.ShiftModifier) out.push("SHIFT")
    if (modifiers & Qt.ControlModifier) out.push("CTRL")
    if (modifiers & Qt.AltModifier) out.push("ALT")
    return out
  }

  // The modifier monitor follows what the event says is held, so a key
  // released while Keydojo was closed does not stay lit.
  function syncHeld(modifiers, extra, released) {
    var next = ({})
    var mods = root.modsFrom(modifiers)
    for (var i = 0; i < mods.length; i++) next[mods[i]] = true
    if (extra) next[extra] = true
    if (released) delete next[released]
    root.heldMods = next
  }

  function onKey(event) {
    if (event.isAutoRepeat) return
    var mod = root.modForKey(event.key)
    root.syncHeld(event.modifiers, mod, "")
    if (mod) return
    var mods = root.modsFrom(event.modifiers)
    var code = event.nativeScanCode
    var plain = mods.length === 0
    var combo = Keymap.comboId(mods, code)
    var label = Keymap.labelForCode(code, root.keymap, event.text)

    if (root.screen === "home") root.homeKey(event.key, plain)
    else if (root.screen === "quiz") root.quizKey(event.key, plain, combo, mods, label)
    else if (root.screen === "recognize") root.recognizeKey(event.key, plain)
    else if (root.screen === "summary") {
      if (plain && event.key === Qt.Key_Escape) root.goHome()
      else if (plain && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) root.startMode(root.homeSel)
    } else if (root.screen === "missionIntro") {
      if (plain && event.key === Qt.Key_Escape) root.goHome()
      else if (plain && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) root.startMission()
    } else if (plain && event.key === Qt.Key_Escape) root.dismiss()
  }

  function homeKey(key, plain) {
    if (!plain) return
    if (key === Qt.Key_Escape) root.dismiss()
    else if (key === Qt.Key_Left || key === Qt.Key_Up) root.homeSel = (root.homeSel + Engine.MODES.length - 1) % Engine.MODES.length
    else if (key === Qt.Key_Right || key === Qt.Key_Down || key === Qt.Key_Tab) root.homeSel = (root.homeSel + 1) % Engine.MODES.length
    else if (key >= Qt.Key_1 && key <= Qt.Key_5) { root.homeSel = key - Qt.Key_1; root.startMode(root.homeSel) }
    else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) root.startMode(root.homeSel)
    else if (key === Qt.Key_L) {
      root.lang = root.lang === "it" ? "en" : "it"
      root.progress.lang = root.lang
      root.saveProgress()
    }
  }

  function goHome() {
    blitzTimer.stop()
    advanceTimer.stop()
    root.question = null
    root.screen = "home"
  }

  // ------------------------------------------------------------ sessions

  function startMode(index) {
    if (!root.cards) return
    if (!root.modeStates[index].unlocked) { tileShake.restart(); return }
    var m = Engine.MODES[index]
    root.homeMessage = ""
    root.mode = m.id
    root.sCorrect = 0
    root.sAnswered = 0
    root.sXp = 0
    root.sLevelUps = 0
    root.sBeltBefore = root.belt
    root.sModesBefore = root.modeStates.map(function(s) { return s.unlocked })
    root.recent = []
    root.qIndex = 0
    root.question = null

    if (m.id === "missions") { root.prepareMission(); return }
    if (m.id === "learn") {
      var fresh = Engine.newCards(root.cards, root.progress, 5)
      if (fresh.length === 0) { root.homeMessage = root.tr("nothingNew"); root.screen = "home"; return }
      root.queue = fresh.map(function(c) { return { card: c, phase: "intro" } })
        .concat(Engine.shuffle(fresh).map(function(c) { return { card: c, phase: "ask" } }))
      root.qTotal = root.queue.length
    } else if (root.learned === 0) {
      root.homeMessage = root.tr("needLearned")
      return
    } else if (m.id === "blitz") {
      root.qTotal = 0
      root.score = 0
      root.mult = 1
      root.streakCount = 0
      root.timeLeft = 60
      blitzTimer.start()
    } else {
      root.qTotal = m.id === "recognize" ? 8 : 10
    }
    root.screen = m.id === "recognize" ? "recognize" : "quiz"
    root.nextQuestion()
  }

  function nextQuestion() {
    root.feedbackKind = ""
    root.feedbackText = ""
    root.pressed = null
    root.hintShown = false
    root.attempts = 0
    root.inputLocked = false
    root.optChosen = -1
    if (root.mode === "blitz" ? root.timeLeft <= 0 : root.qIndex >= root.qTotal) { root.finishSession(); return }

    var card, ph = "ask"
    if (root.mode === "learn") {
      card = root.queue[root.qIndex].card
      ph = root.queue[root.qIndex].phase
    } else {
      card = Engine.pickReview(root.cards, root.progress, root.recent)
    }
    if (!card) { root.finishSession(); return }
    root.recent = root.recent.concat([card.id]).slice(-3)
    var q = Engine.makeQuestion(card)
    if (root.mode === "recognize") {
      root.options = Engine.recognizeOptions(root.cards, root.progress, q)
      root.optSel = 0
    }
    root.question = q
    root.phase = ph
    root.askedAt = Date.now()
    root.qIndex++
  }

  function advance(ms) {
    root.inputLocked = true
    advanceTimer.interval = ms
    advanceTimer.restart()
  }

  Timer {
    id: advanceTimer
    onTriggered: root.nextQuestion()
  }

  function grade(gradeMode, correct, fast) {
    var r = Engine.grade(root.progress, root.question.card.id, correct, gradeMode, fast)
    root.sXp += r.xp
    if (r.levelUp) root.sLevelUps++
    root.revision++
    root.saveProgress()
    return r
  }

  function describeCombo(combo) {
    var hit = root.cards.byCombo[combo]
    if (!hit) return root.tr("notBound")
    return root.tr("thatWas", I18n.desc(root.lang, hit.card.id, hit.card.family ? hit.member.n : null))
  }

  function markGood(xp, result) {
    root.feedbackKind = "good"
    var note = result && result.slow ? root.tr("slowNote") : result && result.early ? root.tr("earlyNote") : ""
    root.feedbackText = root.tr("correct") + (xp > 0 ? "  +" + xp + " XP" : "") + (note ? "  ·  " + note : "")
    pop.restart()
  }

  function markBad(combo, extra) {
    root.feedbackKind = "bad"
    root.feedbackText = root.describeCombo(combo) + (extra ? " · " + extra : "")
    shake.restart()
  }

  function quizKey(key, plain, combo, mods, label) {
    if (!root.question) return
    var ok = Engine.isCorrect(root.question, combo)
    if (plain && key === Qt.Key_Escape) { root.goHome(); return }
    if (root.inputLocked) return
    if (!ok && plain && key === Qt.Key_Tab && root.phase === "ask" && root.mode !== "blitz") { root.hintShown = true; return }
    if (!ok && plain && (key === Qt.Key_Return || key === Qt.Key_Enter) && root.phase === "ask" && root.mode !== "blitz") {
      root.attempts++
      root.sAnswered++
      root.grade(root.mode === "learn" ? "learn" : "recall", false)
      root.feedbackKind = "bad"
      root.feedbackText = root.tr("nowYou")
      root.phase = "retry"
      return
    }
    root.pressed = { mods: mods, label: label }

    if (root.phase === "intro") {
      if (ok) { var r = root.grade("learn", true, false); root.markGood(r.xp); root.advance(700) }
      else root.markBad(combo, root.tr("pressIt"))
      return
    }
    if (root.phase === "retry" || root.phase === "reveal") {
      if (ok) { root.markGood(0); root.advance(450) }
      else root.markBad(combo, root.tr("nowYou"))
      return
    }

    if (ok) {
      var helped = root.hintShown || root.attempts > 0
      var fast = !helped && Date.now() - root.askedAt < Engine.FAST_MS
      var gm = helped ? "learn" : (root.mode === "learn" ? "recognize" : root.mode)
      var res = root.grade(gm, true, fast)
      if (!helped) root.sCorrect++
      if (root.attempts === 0) root.sAnswered++
      if (root.mode === "blitz") {
        root.streakCount++
        root.mult = Math.min(5, 1 + Math.floor(root.streakCount / 3))
        root.score += 10 * root.mult
      }
      root.markGood(res.xp, root.mode === "blitz" ? null : res)
      root.advance(root.mode === "blitz" ? 300 : (res.slow || res.early ? 1400 : 700))
      return
    }

    root.attempts++
    if (root.attempts === 1) root.sAnswered++
    if (root.mode === "blitz") {
      root.streakCount = 0
      root.mult = 1
      root.grade("blitz", false)
      root.markBad(combo)
      root.phase = "reveal"
      root.advance(1200)
      return
    }
    if (root.mode === "recall" && root.attempts === 1) {
      root.hintShown = true
      root.markBad(combo, root.tr("hint"))
      return
    }
    root.grade(root.mode === "learn" ? "learn" : "recall", false)
    root.markBad(combo, root.tr("nowYou"))
    root.phase = "retry"
  }

  function recognizeKey(key, plain) {
    if (!plain) return
    if (key === Qt.Key_Escape) { root.goHome(); return }
    if (root.inputLocked) return
    if (key >= Qt.Key_1 && key <= Qt.Key_4) root.chooseOption(key - Qt.Key_1)
    // Options sit in a 2x2 grid: left/right move along a row, up/down switch rows.
    else if (key === Qt.Key_Left) root.optSel = root.optSel % 2 === 0 ? root.optSel + 1 : root.optSel - 1
    else if (key === Qt.Key_Right) root.optSel = root.optSel % 2 === 1 ? root.optSel - 1 : root.optSel + 1
    else if (key === Qt.Key_Up || key === Qt.Key_Down) root.optSel = (root.optSel + 2) % 4
    else if (key === Qt.Key_Tab) root.optSel = (root.optSel + 1) % 4
    else if (key === Qt.Key_Return || key === Qt.Key_Enter) root.chooseOption(root.optSel)
  }

  function chooseOption(i) {
    if (root.inputLocked || i < 0 || i >= root.options.length) return
    root.optChosen = i
    root.optSel = i
    root.sAnswered++
    var ok = root.options[i].card.id === root.question.card.id
    var r = root.grade("recognize", ok, Date.now() - root.askedAt < Engine.FAST_MS)
    if (ok) { root.sCorrect++; root.markGood(r.xp) }
    else { root.feedbackKind = "bad"; root.feedbackText = root.tr("wrong"); shake.restart() }
    root.advance(ok ? 750 : 1600)
  }

  Timer {
    id: blitzTimer
    interval: 100
    repeat: true
    onTriggered: {
      root.timeLeft = Math.max(0, root.timeLeft - 0.1)
      if (root.timeLeft <= 0) {
        stop()
        advanceTimer.stop()
        root.inputLocked = true
        root.feedbackKind = ""
        root.feedbackText = root.tr("blitzOver")
        finishTimer.restart()
      }
    }
  }

  Timer {
    id: finishTimer
    interval: 900
    onTriggered: root.finishSession()
  }

  function finishSession() {
    blitzTimer.stop()
    advanceTimer.stop()
    root.newRecord = false
    if (root.mode === "blitz" && root.score > (root.progress.bestBlitz || 0)) {
      root.progress.bestBlitz = root.score
      root.newRecord = true
    }
    root.progress.sessions = (root.progress.sessions || 0) + 1
    root.revision++
    root.saveProgress()
    root.beltUp = root.belt > root.sBeltBefore
    var unlocked = []
    for (var i = 0; i < root.modeStates.length; i++)
      if (root.modeStates[i].unlocked && !root.sModesBefore[i]) unlocked.push(root.modeName(i))
    root.newModes = unlocked
    root.question = null
    root.screen = "summary"
    if (root.beltUp || root.newRecord) Qt.callLater(function() { confetti.burst() })
  }

  // ------------------------------------------------------------ missions

  function prepareMission() {
    var runs = Missions.available(root.cards.byId, Engine.unlockedTier(root.cards, root.progress))
    if (runs.length === 0) { root.homeMessage = root.tr("missionNone"); root.screen = "home"; return }
    root.missionRun = Missions.pick(runs, root.progress.missions || {})
    root.screen = "missionIntro"
  }

  function startMission() {
    var focused = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    var occupied = Hyprland.workspaces.values.map(function(w) { return w.id })
    root.missionCtx = Missions.newContext(focused, occupied)
    root.missionStep = 0
    root.missionHint = false
    root.missionClean = 0
    root.screen = "mission"
    hintTimer.restart()
  }

  function stepCard(step) {
    return step && step.card ? root.cards.byId[step.card] : null
  }

  function stepMember(step) {
    var card = root.stepCard(step)
    if (!card) return null
    if (!card.family) return card.members[0]
    var n = root.missionCtx[step.n]
    for (var i = 0; i < card.members.length; i++) if (card.members[i].n === n) return card.members[i]
    return card.members[0]
  }

  function stepText(step) {
    if (!step) return ""
    if (step.text) return Missions.stepText(root.lang, step.text) || root.tr(step.text)
    var card = root.stepCard(step)
    return I18n.desc(root.lang, card.id, card.family ? root.missionCtx[step.n] : null)
  }

  readonly property var currentStep: root.missionRun && root.missionStep < root.missionRun.steps.length ? root.missionRun.steps[root.missionStep] : null

  Connections {
    target: Hyprland
    enabled: root.screen === "mission"
    function onRawEvent(event) {
      var step = root.currentStep
      if (!step || !event) return
      if (step.match(String(event.name), String(event.data), root.missionCtx)) root.completeStep(true)
    }
  }

  Timer {
    id: hintTimer
    interval: 15000
    onTriggered: root.missionHint = true
  }

  function completeStep(done) {
    var step = root.currentStep
    if (done && step && step.card && !root.missionHint) {
      Engine.grade(root.progress, step.card, true, "blitz", true)
      root.missionClean++
    }
    root.missionFlash = done
    flashTimer.restart()
    root.missionStep++
    root.missionHint = false
    hintTimer.restart()
    if (root.missionStep >= root.missionRun.steps.length) root.finishMission()
  }

  Timer {
    id: flashTimer
    interval: 600
    onTriggered: root.missionFlash = false
  }

  function finishMission() {
    hintTimer.stop()
    var played = root.progress.missions || {}
    played[root.missionRun.id] = (played[root.missionRun.id] || 0) + 1
    root.progress.missions = played
    root.progress.missionsDone = (root.progress.missionsDone || 0) + 1
    var xp = 30 + root.missionClean * 10
    root.progress.xp = (root.progress.xp || 0) + xp
    root.sXp = xp
    root.revision++
    root.saveProgress()
    root.screen = "missionDone"
    missionDoneTimer.restart()
  }

  Timer {
    id: missionDoneTimer
    interval: 2200
    onTriggered: if (root.screen === "missionDone") root.finishSession()
  }

  function quitMission() {
    hintTimer.stop()
    root.saveProgress()
    root.screen = "home"
  }

  // ------------------------------------------------------------ main overlay

  PanelWindow {
    id: panel
    visible: root.opened && !root.missionVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "keydojo"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.menu.background, 0.72)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Confetti {
      id: confetti
      anchors.fill: parent
      z: 10
    }

    BorderSurface {
      id: card
      width: Math.min(panel.width - Style.space(48), Style.space(1000))
      height: Math.min(panel.height - Style.space(48), Style.space(660))
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: shakeOffset
      radius: Style.cornerRadius
      color: root.bg
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.space(28)

      property real shakeOffset: 0

      SequentialAnimation {
        id: shake
        NumberAnimation { target: card; property: "shakeOffset"; to: -14; duration: 50 }
        NumberAnimation { target: card; property: "shakeOffset"; to: 12; duration: 60 }
        NumberAnimation { target: card; property: "shakeOffset"; to: -8; duration: 60 }
        NumberAnimation { target: card; property: "shakeOffset"; to: 4; duration: 60 }
        NumberAnimation { target: card; property: "shakeOffset"; to: 0; duration: 50 }
      }

      MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.onKey(event); event.accepted = true }
        Keys.onReleased: function(event) {
          root.syncHeld(event.modifiers, "", root.modForKey(event.key))
          event.accepted = true
        }
      }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // ---------------------------------------------------- header

        Item {
          id: header
          width: parent.width
          height: Style.space(40)

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(12)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰌌"
              color: root.accent
              font.family: root.font
              font.pixelSize: Style.font.displayLarge
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              Text {
                text: "KEYDOJO"
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.display
                font.bold: true
                font.letterSpacing: Style.space(4)
              }
              Text {
                text: root.tr("tagline")
                color: Util.alpha(root.fg, 0.55)
                font.family: root.font
                font.pixelSize: Style.font.caption
              }
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(16)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: { root.revision; return (root.progress.xp || 0) + " XP" }
              color: root.fg
              font.family: root.font
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Belt {
              anchors.verticalCenter: parent.verticalCenter
              index: root.belt
              tails: false
              label: root.beltName(root.belt)
            }
          }
        }

        // ---------------------------------------------------- loading

        Text {
          anchors.centerIn: parent
          visible: root.screen === "loading"
          text: root.tr("loading")
          color: Util.alpha(root.fg, 0.7)
          font.family: root.font
          font.pixelSize: Style.font.heading
        }

        // ---------------------------------------------------- home

        Item {
          id: home
          visible: root.screen === "home"
          anchors.fill: parent
          anchors.topMargin: header.height + Style.space(22)

          Column {
            width: parent.width
            spacing: Style.space(18)

            // Belt ladder: each belt after white is earned by clearing a tier.
            Column {
              width: parent.width
              spacing: Style.space(8)

              Row {
                id: ladder
                width: parent.width
                spacing: Style.space(6)
                readonly property real segment: (width - spacing * (Engine.BELTS.length - 1)) / Engine.BELTS.length

                Repeater {
                  model: Engine.BELTS.length
                  Column {
                    required property int index
                    width: ladder.segment
                    spacing: Style.space(4)

                    Rectangle {
                      width: parent.width
                      height: index === root.belt ? Style.space(14) : Style.space(10)
                      anchors.horizontalCenter: parent.horizontalCenter
                      radius: height / 2
                      color: Engine.BELT_COLORS[index]
                      opacity: index <= root.belt ? 1 : 0.18
                      border.width: index === root.belt ? 2 : (index === 7 ? 1 : 0)
                      border.color: index === root.belt ? root.accent : Util.alpha(root.fg, 0.4)
                      Behavior on height { NumberAnimation { duration: 200 } }
                    }

                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      text: index === 0 ? "" : root.tierName(index - 1)
                      color: Util.alpha(root.fg, index <= root.belt ? 0.75 : 0.4)
                      font.family: root.font
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }
              }

              Text {
                width: parent.width
                text: root.tierNow
                  ? root.tr("nextBelt", root.beltName(root.belt + 1), root.tierNow.needed, root.tierNow.total, root.tierName(root.belt))
                  : root.tr("allBelts")
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.subtitle
                wrapMode: Text.WordWrap
              }

              Rectangle {
                width: parent.width
                height: Style.space(8)
                radius: height / 2
                color: Util.alpha(root.fg, 0.08)
                visible: root.tierNow !== null

                Rectangle {
                  height: parent.height
                  radius: height / 2
                  color: root.accent
                  width: root.tierNow && root.tierNow.needed > 0 ? parent.width * Math.min(1, root.tierNow.mastered / root.tierNow.needed) : 0
                  Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                }
              }
            }

            Text {
              visible: root.reviewLine !== ""
              text: (root.dueNow > 0 ? "󰑓  " : "󰔟  ") + root.reviewLine
              color: root.dueNow > 0 ? root.accent : Util.alpha(root.fg, 0.6)
              font.family: root.font
              font.pixelSize: Style.font.subtitle
            }

            Text {
              text: root.tr("chooseMode").toUpperCase()
              color: Util.alpha(root.fg, 0.5)
              font.family: root.font
              font.pixelSize: Style.font.caption
              font.letterSpacing: Style.space(2)
            }

            Row {
              id: tiles
              width: parent.width
              spacing: Style.space(12)
              property real offset: 0

              SequentialAnimation {
                id: tileShake
                NumberAnimation { target: tiles; property: "offset"; to: -8; duration: 50 }
                NumberAnimation { target: tiles; property: "offset"; to: 8; duration: 60 }
                NumberAnimation { target: tiles; property: "offset"; to: 0; duration: 50 }
              }

              Repeater {
                model: Engine.MODES.length
                ModeTile {
                  required property int index
                  // Shake via a transform: setting x would fight the Row's layout.
                  transform: Translate { x: index === root.homeSel ? tiles.offset : 0 }
                  width: (tiles.width - tiles.spacing * (Engine.MODES.length - 1)) / Engine.MODES.length
                  height: Style.space(190)
                  number: index + 1
                  icon: Engine.MODES[index].icon
                  title: root.modeName(index)
                  subtitle: root.tr("mode_" + Engine.MODES[index].id + "_d")
                  lockText: root.modeStates[index].lockText
                  locked: !root.modeStates[index].unlocked
                  selected: index === root.homeSel
                  badge: Engine.MODES[index].id === "recall" && root.dueNow > 0 && root.modeStates[index].unlocked ? String(root.dueNow) : ""
                  onActivated: { root.homeSel = index; root.startMode(index) }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(10)
              topPadding: Style.space(10)
              visible: root.upNext.length > 0

              Text {
                text: root.tr("upNext").toUpperCase()
                color: Util.alpha(root.fg, 0.5)
                font.family: root.font
                font.pixelSize: Style.font.caption
                font.letterSpacing: Style.space(2)
              }

              Flow {
                width: parent.width
                spacing: Style.space(10)
                Repeater {
                  model: root.upNext
                  Rectangle {
                    required property var modelData
                    width: chipText.implicitWidth + Style.space(22)
                    height: chipText.implicitHeight + Style.space(12)
                    radius: height / 2
                    color: Util.alpha(root.fg, 0.05)
                    border.width: 1
                    border.color: Util.alpha(root.fg, 0.14)
                    Text {
                      id: chipText
                      anchors.centerIn: parent
                      text: I18n.desc(root.lang, modelData.id, modelData.family ? modelData.members[0].n : null)
                      color: Util.alpha(root.fg, 0.8)
                      font.family: root.font
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: root.homeMessage !== ""
              text: root.homeMessage
              color: root.accent
              font.family: root.font
              font.pixelSize: Style.font.subtitle
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Column {
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: Style.space(6)

            Text {
              visible: root.skipped.length > 0
              text: root.tr("unreachable", root.skipped.length)
              color: Util.alpha(root.fg, 0.4)
              font.family: root.font
              font.pixelSize: Style.font.caption
            }

            Item {
              width: parent.width
              height: helpText.implicitHeight

              Text {
                id: helpText
                text: root.tr("homeHelp")
                color: Util.alpha(root.fg, 0.55)
                font.family: root.font
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                anchors.right: parent.right
                text: root.tr("known", root.learned, root.totalCards)
                color: Util.alpha(root.fg, 0.75)
                font.family: root.font
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        // ---------------------------------------------------- quiz

        Item {
          id: quiz
          visible: root.screen === "quiz"
          anchors.fill: parent
          anchors.topMargin: header.height + Style.space(18)

          // Meta: which mode and where you are. Small on purpose.
          Item {
            id: quizTop
            width: parent.width
            height: Style.space(26)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.mode ? root.modeName(root.modeIndex(root.mode)) + (root.question ? "  ·  " + root.tierName(root.question.card.tier) : "") : ""
              color: Util.alpha(root.fg, 0.7)
              font.family: root.font
              font.pixelSize: Style.font.subtitle
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(16)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.mode === "blitz" && root.mult > 1
                text: root.tr("combo", root.mult)
                color: "#f2994a"
                font.family: root.font
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.mode === "blitz"
                  ? Math.ceil(root.timeLeft) + " s  ·  " + root.tr("blitzScore") + " " + root.score
                  : root.tr("qCount", Math.max(1, root.qIndex), root.qTotal)
                color: Util.alpha(root.fg, 0.7)
                font.family: root.font
                font.pixelSize: Style.font.subtitle
              }
            }
          }

          Rectangle {
            id: quizBar
            anchors.top: quizTop.bottom
            anchors.topMargin: Style.space(6)
            width: parent.width
            height: Style.space(4)
            radius: height / 2
            color: Util.alpha(root.fg, 0.08)

            Rectangle {
              height: parent.height
              radius: height / 2
              color: root.mode === "blitz" && root.timeLeft < 10 ? root.bad : root.accent
              width: parent.width * (root.mode === "blitz"
                ? root.timeLeft / 60
                : (root.qTotal > 0 ? Math.max(0, root.qIndex - 1) / root.qTotal : 0))
              Behavior on width { NumberAnimation { duration: 250 } }
            }
          }

          // Main block: instruction → action → keys → what to do now.
          Column {
            id: quizBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Style.space(-6)
            spacing: Style.space(16)

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.tr("instPress")
              color: root.accent
              font.family: root.font
              font.pixelSize: Math.round(Style.font.heading * 1.25)
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.questionText(root.question)
              color: root.fg
              font.family: root.font
              font.pixelSize: Math.round(Style.font.displayLarge * 1.45)
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Item {
              width: parent.width
              height: Style.space(92)

              Combo {
                id: targetCombo
                anchors.centerIn: parent
                size: Style.font.display
                visible: root.question !== null && (root.phase !== "ask" || root.hintShown)
                mods: root.question ? root.question.member.mods : []
                keyLabel: root.question ? root.question.member.label : ""
                hideKey: root.phase === "ask" && root.hintShown
                tone: root.feedbackKind === "good" ? "good" : root.phase === "intro" ? "accent" : ""

                SequentialAnimation {
                  id: pop
                  NumberAnimation { target: targetCombo; property: "scale"; to: 1.12; duration: 90; easing.type: Easing.OutQuad }
                  NumberAnimation { target: targetCombo; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutBack }
                }
              }

              KeyCap {
                anchors.centerIn: parent
                visible: !targetCombo.visible && root.feedbackKind !== "good"
                text: "?"
                size: Style.font.display
              }

              Text {
                anchors.centerIn: parent
                visible: !targetCombo.visible && root.feedbackKind === "good"
                text: "󰄬"
                color: root.good
                font.family: root.font
                font.pixelSize: Style.font.displayLarge * 2
              }
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: {
                if (root.feedbackText !== "") return (root.feedbackKind === "good" ? "󰄬  " : root.feedbackKind === "bad" ? "󰅖  " : "") + root.feedbackText
                if (root.phase === "intro") return root.tr("ctaIntro")
                if (root.phase === "retry" || root.phase === "reveal") return root.tr("ctaRetry")
                if (root.mode === "blitz") return root.tr("ctaBlitz")
                if (root.hintShown) return root.tr("ctaHint")
                return root.tr("ctaAsk")
              }
              color: root.feedbackKind === "good" ? root.good : root.feedbackKind === "bad" ? root.bad : root.fg
              font.family: root.font
              font.pixelSize: Math.round(Style.font.heading * 1.15)
              font.bold: root.feedbackKind !== ""
              wrapMode: Text.WordWrap
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(10)
              visible: root.feedbackKind === "bad" && root.pressed !== null

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.tr("youPressed")
                color: Util.alpha(root.fg, 0.6)
                font.family: root.font
                font.pixelSize: Style.font.body
              }

              Combo {
                size: Style.font.body
                tone: "bad"
                mods: root.pressed ? root.pressed.mods : []
                keyLabel: root.pressed ? root.pressed.label : ""
              }
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(28)
              visible: root.phase === "ask" && root.mode !== "blitz" && root.feedbackKind !== "good"

              HelpKey { key: "Tab"; label: root.tr("helpHint"); visible: !root.hintShown }
              HelpKey { key: root.tr("keyEnter"); label: root.tr("helpSkip") }
            }
          }

          Item {
            anchors.bottom: parent.bottom
            width: parent.width
            height: monitor.height

            Row {
              id: monitor
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.tr("keysHeld")
                color: Util.alpha(root.fg, 0.5)
                font.family: root.font
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: Keymap.MOD_ORDER
                KeyCap {
                  required property string modelData
                  size: Style.font.bodySmall
                  text: Keymap.modLabel(modelData)
                  lit: root.heldMods[modelData] === true
                }
              }
            }

            HelpKey {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              key: "Esc"
              label: root.tr("helpBack")
            }
          }
        }

        // ---------------------------------------------------- recognize

        Item {
          id: recognize
          visible: root.screen === "recognize"
          anchors.fill: parent
          anchors.topMargin: header.height + Style.space(18)

          Item {
            id: recTop
            width: parent.width
            height: Style.space(26)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.tr("mode_recognize")
              color: Util.alpha(root.fg, 0.7)
              font.family: root.font
              font.pixelSize: Style.font.subtitle
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.tr("qCount", Math.max(1, root.qIndex), root.qTotal)
              color: Util.alpha(root.fg, 0.7)
              font.family: root.font
              font.pixelSize: Style.font.subtitle
            }
          }

          Rectangle {
            id: recBar
            anchors.top: recTop.bottom
            anchors.topMargin: Style.space(6)
            width: parent.width
            height: Style.space(4)
            radius: height / 2
            color: Util.alpha(root.fg, 0.08)

            Rectangle {
              height: parent.height
              radius: height / 2
              color: root.accent
              width: parent.width * (root.qTotal > 0 ? Math.max(0, root.qIndex - 1) / root.qTotal : 0)
              Behavior on width { NumberAnimation { duration: 250 } }
            }
          }

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(18)

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.tr("instRecognize")
              color: root.accent
              font.family: root.font
              font.pixelSize: Math.round(Style.font.heading * 1.25)
            }

            Combo {
              anchors.horizontalCenter: parent.horizontalCenter
              size: Style.font.display
              mods: root.question ? root.question.member.mods : []
              keyLabel: root.question ? root.question.member.label : ""
              tone: root.feedbackKind === "good" ? "good" : ""
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.feedbackText !== ""
                ? (root.feedbackKind === "good" ? "󰄬  " : "󰅖  ") + root.feedbackText
                : root.tr("ctaRecognize")
              color: root.feedbackKind === "good" ? root.good : root.feedbackKind === "bad" ? root.bad : root.fg
              font.family: root.font
              font.pixelSize: Math.round(Style.font.heading * 1.15)
              font.bold: root.feedbackKind !== ""
            }

            Grid {
              id: optGrid
              width: parent.width
              columns: 2
              spacing: Style.space(12)

              Repeater {
                model: root.options
                Rectangle {
                  required property int index
                  required property var modelData
                  readonly property bool isAnswer: root.question !== null && modelData.card.id === root.question.card.id
                  readonly property bool revealed: root.optChosen !== -1
                  width: (optGrid.width - optGrid.spacing) / 2
                  height: Style.space(68)
                  radius: root.radius
                  color: revealed && isAnswer ? Util.alpha(root.good, 0.22)
                       : revealed && index === root.optChosen ? Util.alpha(root.bad, 0.22)
                       : index === root.optSel ? Util.alpha(root.accent, 0.12) : Util.alpha(root.fg, 0.04)
                  border.width: index === root.optSel ? 2 : 1
                  border.color: revealed && isAnswer ? root.good : index === root.optSel ? root.accent : Util.alpha(root.fg, 0.16)
                  Behavior on color { ColorAnimation { duration: 150 } }

                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Style.space(14)
                    width: parent.width - Style.space(28)
                    spacing: Style.space(14)

                    KeyCap {
                      anchors.verticalCenter: parent.verticalCenter
                      size: Style.font.body
                      text: index + 1
                      lit: index === root.optSel && !parent.parent.revealed
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - Style.space(70)
                      text: root.questionText(modelData)
                      color: root.fg
                      font.family: root.font
                      font.pixelSize: Style.font.heading
                      wrapMode: Text.WordWrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.chooseOption(index)
                  }
                }
              }
            }
          }

          HelpKey {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            key: "Esc"
            label: root.tr("helpBack")
          }
        }

        // ---------------------------------------------------- summary

        Item {
          id: summary
          visible: root.screen === "summary"
          anchors.fill: parent
          anchors.topMargin: header.height + Style.space(30)

          Column {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            spacing: Style.space(16)

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.mode === "blitz" ? root.tr("blitzOver") : root.mode === "missions" ? root.tr("missionDone") : root.tr("summary")
              color: root.fg
              font.family: root.font
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              visible: root.mode !== "missions"
              text: root.mode === "blitz"
                ? root.tr("blitzScore") + " " + root.score + "   ·   " + root.tr("blitzBest", root.progress.bestBlitz || 0)
                : root.tr("summaryScore", root.sCorrect, root.sAnswered)
              color: root.accent
              font.family: root.font
              font.pixelSize: Style.font.display
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.mode === "missions"
                ? root.tr("missionXp", root.sXp, root.missionClean)
                : root.tr("xpGained", root.sXp) + (root.sLevelUps > 0 ? "   ·   " + root.tr("levelUps", root.sLevelUps) : "")
              color: root.fg
              font.family: root.font
              font.pixelSize: Style.font.heading
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              visible: root.newRecord
              text: "󰓏 " + root.tr("newRecord")
              color: "#f2c94c"
              font.family: root.font
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Column {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.beltUp
              spacing: Style.space(10)

              Belt {
                anchors.horizontalCenter: parent.horizontalCenter
                index: root.belt
                unit: Style.space(14)
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.tr("beltUp", root.beltName(root.belt))
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.display
                font.bold: true
              }
            }

            Text {
              width: summary.width
              horizontalAlignment: Text.AlignHCenter
              visible: root.mode !== "blitz" && root.tierNow !== null && !root.beltUp
              text: root.tierNow ? root.tr("goalLeft", Math.max(0, root.tierNow.needed - root.tierNow.mastered), root.beltName(root.belt + 1).toLowerCase()) : ""
              color: root.accent
              font.family: root.font
              font.pixelSize: Style.font.heading
            }

            Text {
              width: summary.width
              horizontalAlignment: Text.AlignHCenter
              visible: root.reviewLine !== ""
              text: root.reviewLine
              color: Util.alpha(root.fg, 0.65)
              font.family: root.font
              font.pixelSize: Style.font.subtitle
            }

            Repeater {
              model: root.newModes
              Text {
                required property string modelData
                width: summary.width
                horizontalAlignment: Text.AlignHCenter
                text: "󰌿 " + root.tr("unlockedMode", modelData)
                color: root.accent
                font.family: root.font
                font.pixelSize: Style.font.heading
              }
            }
          }

          Text {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.tr("continueHelp")
            color: Util.alpha(root.fg, 0.55)
            font.family: root.font
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---------------------------------------------------- mission intro

        Item {
          visible: root.screen === "missionIntro"
          anchors.fill: parent
          anchors.topMargin: header.height + Style.space(26)

          Column {
            width: parent.width
            spacing: Style.space(14)

            Text {
              text: "󰓾  " + root.tr("missionTitle") + " · " + (root.missionRun ? Missions.runTitle(root.lang, root.missionRun) : "")
              color: root.accent
              font.family: root.font
              font.pixelSize: Style.font.display
              font.bold: true
            }

            Text {
              width: parent.width
              text: root.tr("missionIntro")
              color: root.fg
              font.family: root.font
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
            }

            Column {
              spacing: Style.space(6)
              topPadding: Style.space(6)
              Repeater {
                model: root.missionRun ? root.missionRun.steps : []
                Text {
                  required property int index
                  required property var modelData
                  text: (index + 1) + ".  " + root.stepText(modelData)
                  color: Util.alpha(root.fg, 0.8)
                  font.family: root.font
                  font.pixelSize: Style.font.subtitle
                }
              }
            }
          }

          Column {
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: Style.space(4)
            Text {
              text: root.tr("emergency")
              color: Util.alpha(root.fg, 0.4)
              font.family: root.font
              font.pixelSize: Style.font.caption
            }
            Text {
              text: root.tr("missionStart")
              color: Util.alpha(root.fg, 0.55)
              font.family: root.font
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ mission banner

  PanelWindow {
    id: banner
    visible: root.missionVisible
    anchors { top: true }
    margins { top: Style.gapsOut * 6 }
    implicitWidth: Style.space(640)
    implicitHeight: bannerBox.height
    color: "transparent"
    WlrLayershell.namespace: "keydojo-mission"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    BorderSurface {
      id: bannerBox
      width: parent.width
      height: bannerColumn.implicitHeight + Style.space(36)
      radius: Style.cornerRadius
      color: root.missionFlash ? Qt.tint(root.bg, Util.alpha(root.good, 0.25)) : root.bg
      borderSpec: Border.surfaceSpec("menu", "border", root.missionFlash ? root.good : root.accent, Math.max(1, Style.space(2)))
      padding: Style.space(18)
      Behavior on color { ColorAnimation { duration: 200 } }

      Column {
        id: bannerColumn
        x: bannerBox.contentLeftInset
        y: bannerBox.contentTopInset
        width: parent.width - bannerBox.contentLeftInset - bannerBox.contentRightInset
        spacing: Style.space(10)

        Item {
          width: parent.width
          height: stepLabel.implicitHeight
          visible: root.screen === "mission"

          Text {
            id: stepLabel
            text: "󰓾 " + (root.missionRun ? Missions.runTitle(root.lang, root.missionRun) : "") + " · "
              + root.tr("missionStep", Math.min(root.missionStep + 1, root.missionRun ? root.missionRun.steps.length : 1), root.missionRun ? root.missionRun.steps.length : 1)
            color: root.accent
            font.family: root.font
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Row {
            anchors.right: parent.right
            spacing: Style.space(14)
            Repeater {
              model: [
                { label: root.tr("missionHint"), act: "hint" },
                { label: root.tr("missionSkip"), act: "skip" },
                { label: root.tr("missionQuit"), act: "quit" }
              ]
              Text {
                required property var modelData
                text: modelData.label
                color: Util.alpha(root.fg, area.containsMouse ? 1 : 0.6)
                font.family: root.font
                font.pixelSize: Style.font.bodySmall
                font.underline: area.containsMouse
                MouseArea {
                  id: area
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modelData.act === "hint") root.missionHint = true
                    else if (modelData.act === "skip") root.completeStep(false)
                    else root.quitMission()
                  }
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          text: root.screen === "missionDone" ? "󰄬  " + root.tr("missionDone") : root.stepText(root.currentStep)
          color: root.screen === "missionDone" ? root.good : root.fg
          font.family: root.font
          font.pixelSize: Style.font.display
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Combo {
          visible: root.screen === "mission" && root.missionHint
          size: Style.font.body
          mods: { var m = root.stepMember(root.currentStep); return m ? m.mods : [] }
          keyLabel: { var m = root.stepMember(root.currentStep); return m ? m.label : "Esc" }
        }
      }
    }
  }
}
