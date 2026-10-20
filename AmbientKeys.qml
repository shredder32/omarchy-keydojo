import QtQuick
import qs.Commons
import "Keymap.js" as Keymap

// Home-screen backdrop: a ghost keyboard tiled around the card. Every few
// seconds the keys of a move you already know light up where your fingers
// would go, its name fades in underneath, and the keys burst into pixels.
Item {
  id: ambient

  property bool running: false
  property var keymap: Keymap.emptyKeymap()
  property var modNames: ({})
  // [{ mods, code, text }]: the moves worth replaying, chosen by the host.
  property var combos: []
  // Area to keep clear, in this item's coordinates.
  property rect avoid: Qt.rect(0, 0, 0, 0)
  property color foreground: Color.menu.text
  property color accent: Color.accent

  readonly property real unit: Style.space(52)
  readonly property real gap: Math.max(2, unit * 0.12)
  readonly property color muted: Qt.hsla(accent.hslHue, accent.hslSaturation * 0.25, Math.max(0.55, accent.hslLightness), 1)

  // Keyboard geometry in key units: [xkb keycode, x, row y, width].
  readonly property var keys: {
    var k = []
    function add(code, x, y, w) { k.push([code, x, y, w || 1]) }
    add(9, 0, 0)
    for (var f = 0; f < 4; f++) { add(67 + f, 2 + f, 0); add(71 + f, 6.5 + f, 0) }
    add(75, 11, 0); add(76, 12, 0); add(95, 13, 0); add(96, 14, 0)
    add(107, 15.25, 0); add(110, 16.25, 0); add(119, 17.25, 0)
    add(49, 0, 1.25)
    for (var d = 0; d < 10; d++) add(10 + d, 1 + d, 1.25)
    add(20, 11, 1.25); add(21, 12, 1.25); add(22, 13, 1.25, 2)
    add(23, 0, 2.25, 1.5)
    for (var q = 0; q < 10; q++) add(24 + q, 1.5 + q, 2.25)
    add(34, 11.5, 2.25); add(35, 12.5, 2.25); add(36, 13.5, 2.25, 1.5)
    add(66, 0, 3.25, 1.75)
    for (var a = 0; a < 9; a++) add(38 + a, 1.75 + a, 3.25)
    add(47, 10.75, 3.25); add(48, 11.75, 3.25); add(51, 12.75, 3.25, 2.25)
    add(50, 0, 4.25, 2.25)
    for (var z = 0; z < 7; z++) add(52 + z, 2.25 + z, 4.25)
    add(59, 9.25, 4.25); add(60, 10.25, 4.25); add(61, 11.25, 4.25); add(62, 12.25, 4.25, 2.75)
    add(111, 16.25, 4.25)
    add(37, 0, 5.25, 1.25); add(133, 1.25, 5.25, 1.25); add(64, 2.5, 5.25, 1.25); add(65, 3.75, 5.25, 6.25)
    add(108, 10, 5.25, 1.25); add(134, 11.25, 5.25, 1.25); add(135, 12.5, 5.25, 1.25); add(105, 13.75, 5.25, 1.25)
    add(113, 15.25, 5.25); add(116, 16.25, 5.25); add(114, 17.25, 5.25)
    return k
  }
  readonly property var keyByCode: {
    var m = {}
    for (var i = 0; i < keys.length; i++) m[keys[i][0]] = keys[i]
    return m
  }
  readonly property var modCodes: ({ SUPER: 133, SHIFT: 50, CTRL: 37, ALT: 64 })
  readonly property real tileW: 18.25 * unit
  readonly property real tileH: 6.25 * unit
  readonly property real stepX: tileW + 2 * unit
  readonly property real stepY: tileH + 1.5 * unit

  function labelFor(code) {
    switch (code) {
      case 133: case 134: return modNames.SUPER || "Super"
      case 50: case 62: return modNames.SHIFT || "Shift"
      case 37: case 105: return modNames.CTRL || "Ctrl"
      case 64: return modNames.ALT || "Alt"
      case 108: return "AltGr"
      case 135: return "☰"
      case 66: return "Caps"
      case 65: return ""
      case 36: return "⏎"
    }
    return Keymap.labelForCode(code, keymap, "")
  }

  // Tile origins covering the area, every other row shifted half a tile.
  readonly property var tiles: {
    var out = []
    if (width <= 0 || height <= 0) return out
    var rows = Math.ceil(height / stepY) + 1
    var cols = Math.ceil(width / stepX) + 2
    var y0 = (height % stepY) / 2 - stepY / 2
    for (var r = 0; r < rows; r++) {
      var shift = r % 2 === 0 ? -stepX / 2 : 0
      for (var c = 0; c < cols; c++) out.push({ x: Math.round(shift + c * stepX), y: Math.round(y0 + r * stepY) })
    }
    return out
  }

  // ------------------------------------------------------------ ghost keyboard

  Item {
    id: ghost
    width: ambient.tileW
    height: ambient.tileH

    Repeater {
      model: ambient.keys
      Rectangle {
        required property var modelData
        x: modelData[1] * ambient.unit + ambient.gap / 2
        y: modelData[2] * ambient.unit + ambient.gap / 2
        width: modelData[3] * ambient.unit - ambient.gap
        height: ambient.unit - ambient.gap
        radius: Math.max(3, ambient.unit * 0.14)
        color: "transparent"
        border.width: 1
        border.color: Util.alpha(ambient.foreground, 0.08)

        Text {
          anchors.centerIn: parent
          text: ambient.labelFor(modelData[0])
          color: Util.alpha(ambient.foreground, 0.10)
          font.family: Style.font.family
          font.pixelSize: Math.round(ambient.unit * 0.32)
        }
      }
    }
  }

  Repeater {
    model: ambient.tiles
    ShaderEffectSource {
      required property var modelData
      x: modelData.x
      y: modelData.y
      width: ambient.tileW
      height: ambient.tileH
      sourceItem: ghost
      // The original only feeds the tiles; it is never drawn itself.
      hideSource: true
    }
  }

  // ------------------------------------------------------------ lit combo

  property var lit: []
  property var litLabel: ({ x: 0, y: 0, text: "" })
  property real litLevel: 0

  Repeater {
    model: ambient.lit
    Rectangle {
      required property var modelData
      x: modelData.x
      y: modelData.y
      width: modelData.w
      height: modelData.h
      radius: Math.max(3, ambient.unit * 0.14)
      color: Util.alpha(ambient.muted, 0.28 * ambient.litLevel)
      border.width: Math.max(1, ambient.unit * 0.06)
      border.color: Util.alpha(ambient.muted, 0.9 * ambient.litLevel)
      scale: 0.9 + 0.1 * ambient.litLevel

      Text {
        anchors.centerIn: parent
        text: modelData.label
        color: Util.alpha(ambient.muted, ambient.litLevel)
        font.family: Style.font.family
        font.pixelSize: Math.round(ambient.unit * 0.34)
        font.bold: true
      }
    }
  }

  Text {
    x: ambient.litLabel.x - width / 2
    y: ambient.litLabel.y
    text: ambient.litLabel.text
    color: Util.alpha(ambient.foreground, 0.55 * ambient.litLevel)
    font.family: Style.font.family
    font.pixelSize: Math.round(ambient.unit * 0.42)
  }

  SequentialAnimation {
    id: litAnim
    NumberAnimation { target: ambient; property: "litLevel"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
    PauseAnimation { duration: 1100 }
    ScriptAction { script: ambient.explode() }
    NumberAnimation { target: ambient; property: "litLevel"; to: 0; duration: 140 }
  }

  // ------------------------------------------------------------ pixel burst

  readonly property int poolSize: 420
  property int nextParticle: 0

  Repeater {
    id: particles
    model: ambient.poolSize

    Rectangle {
      id: px
      required property int index
      property real t: 1
      property real x0: 0
      property real y0: 0
      property real vx: 0
      property real vy: 0
      // Pixel size follows the key size so the burst stays chunky.
      readonly property real grid: Math.max(4, Math.round(ambient.unit / 8))

      width: index % 3 === 0 ? grid * 1.5 : grid
      height: width
      x: Math.round((x0 + vx * t) / grid) * grid
      y: Math.round((y0 + vy * t + ambient.unit * 6 * t * t) / grid) * grid
      color: index % 4 === 0 ? ambient.foreground : ambient.muted
      opacity: t >= 1 ? 0 : 0.9 * (1 - t * t)
      visible: t < 1

      function launch(cx, cy, w, h) {
        x0 = cx + (Math.random() - 0.5) * w
        y0 = cy + (Math.random() - 0.5) * h
        var angle = Math.random() * Math.PI * 2
        var speed = ambient.unit * (0.8 + Math.random() * 3)
        vx = Math.cos(angle) * speed
        vy = Math.sin(angle) * speed - ambient.unit * 1.5
        fly.duration = 1200 + Math.random() * 900
        fly.restart()
      }

      NumberAnimation { id: fly; target: px; property: "t"; from: 0; to: 1; easing.type: Easing.OutQuad }
    }
  }

  function explode() {
    for (var i = 0; i < lit.length; i++) {
      var k = lit[i]
      var count = Math.max(24, Math.min(80, Math.round(k.w * k.h / (unit * unit) * 28)))
      for (var n = 0; n < count; n++) {
        var p = particles.itemAt(nextParticle)
        nextParticle = (nextParticle + 1) % poolSize
        if (p) p.launch(k.x + k.w / 2, k.y + k.h / 2, k.w, k.h)
      }
    }
  }

  // ------------------------------------------------------------ choosing a move

  function overlapsAvoid(x, y, w, h) {
    var pad = unit * 0.5
    return x < avoid.x + avoid.width + pad && x + w > avoid.x - pad
        && y < avoid.y + avoid.height + pad && y + h > avoid.y - pad
  }

  function fire() {
    if (combos.length === 0 || tiles.length === 0) return
    for (var attempt = 0; attempt < 6; attempt++) {
      var combo = combos[Math.floor(Math.random() * combos.length)]
      var codes = combo.mods.map(function(m) { return ambient.modCodes[m] }).concat([combo.code])
      var shapes = codes.map(function(c) { return ambient.keyByCode[c] })
      if (shapes.some(function(s) { return !s })) continue

      var options = tiles.filter(function(t) {
        for (var i = 0; i < shapes.length; i++) {
          var kx = t.x + shapes[i][1] * unit, ky = t.y + shapes[i][2] * unit, kw = shapes[i][3] * unit
          if (kx < 0 || ky < 0 || kx + kw > width || ky + unit * 2 > height) return false
          if (overlapsAvoid(kx, ky, kw, unit * 2)) return false
        }
        return true
      })
      if (options.length === 0) continue

      var tile = options[Math.floor(Math.random() * options.length)]
      var rects = []
      var minX = 1e9, maxX = -1e9, maxY = -1e9
      for (var s = 0; s < shapes.length; s++) {
        var r = {
          x: tile.x + shapes[s][1] * unit + gap / 2,
          y: tile.y + shapes[s][2] * unit + gap / 2,
          w: shapes[s][3] * unit - gap,
          h: unit - gap,
          label: labelFor(codes[s])
        }
        rects.push(r)
        minX = Math.min(minX, r.x); maxX = Math.max(maxX, r.x + r.w); maxY = Math.max(maxY, r.y + r.h)
      }
      lit = rects
      litLabel = { x: (minX + maxX) / 2, y: maxY + unit * 0.35, text: combo.text }
      litAnim.restart()
      return
    }
  }

  Timer {
    id: cadence
    interval: 2600
    repeat: true
    running: ambient.running && ambient.combos.length > 0
    triggeredOnStart: true
    onTriggered: ambient.fire()
  }

  onRunningChanged: if (!running) { litAnim.stop(); litLevel = 0 }
}
