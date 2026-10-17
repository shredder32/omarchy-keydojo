import QtQuick
import qs.Commons
import "Keymap.js" as Keymap

// A key combination drawn as keycaps: Super + Shift + Enter.
Row {
  id: combo

  property var mods: []
  // Optional per-language modifier labels; falls back to Super/Shift/Ctrl/Alt.
  property var modNames: ({})
  property string keyLabel: ""
  property bool hideKey: false
  property bool hideAll: false
  property string tone: ""
  property real size: Style.font.heading
  property color foreground: Color.menu.text

  readonly property var parts: {
    var list = (mods || []).map(function(m) { return combo.modNames[m] || Keymap.modLabel(m) })
    list.push(hideKey || hideAll ? "?" : keyLabel)
    if (hideAll) return list.map(function() { return "?" })
    return list
  }

  spacing: Math.round(size * 0.45)

  Repeater {
    model: combo.parts

    Row {
      required property int index
      required property string modelData
      spacing: combo.spacing

      Text {
        visible: index > 0
        anchors.verticalCenter: parent.verticalCenter
        text: "+"
        color: Util.alpha(combo.foreground, 0.5)
        font.family: Style.font.family
        font.pixelSize: combo.size
      }

      KeyCap {
        text: modelData
        size: combo.size
        tone: combo.tone
      }
    }
  }
}
