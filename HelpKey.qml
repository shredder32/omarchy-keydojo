import QtQuick
import qs.Commons

// A small "key: what it does" hint, e.g. [Tab] hint.
Row {
  id: help

  property string key: ""
  property string label: ""
  property real size: Style.font.bodySmall
  property color foreground: Color.menu.text

  spacing: Style.space(8)

  KeyCap {
    anchors.verticalCenter: parent.verticalCenter
    text: help.key
    size: help.size
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: help.label
    color: Util.alpha(help.foreground, 0.7)
    font.family: Style.font.family
    font.pixelSize: help.size
  }
}
