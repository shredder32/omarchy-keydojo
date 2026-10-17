import QtQuick
import qs.Commons
import "Engine.js" as Engine

// A little martial-arts belt: a band with a knot and two tails.
Row {
  id: beltRow

  property int index: 0
  property string label: ""
  property real unit: Style.space(6)
  property bool tails: true

  readonly property color tone: Engine.BELT_COLORS[Math.min(index, Engine.BELT_COLORS.length - 1)]
  readonly property color edge: index === Engine.BELT_COLORS.length - 1 ? Util.alpha(Color.menu.text, 0.5) : Qt.darker(tone, 1.35)

  spacing: Style.space(8)

  Item {
    anchors.verticalCenter: parent.verticalCenter
    width: beltRow.unit * 8
    height: beltRow.unit * (beltRow.tails ? 4 : 3)

    // Band
    Rectangle {
      y: beltRow.unit * 0.9
      width: parent.width
      height: beltRow.unit * 1.2
      radius: beltRow.unit * 0.3
      color: beltRow.tone
      border.width: 1
      border.color: beltRow.edge
    }

    // Tails hanging from the knot
    Repeater {
      model: beltRow.tails ? [-1, 1] : []
      Rectangle {
        required property int modelData
        x: parent.width / 2 - width / 2 + modelData * beltRow.unit * 0.45
        y: beltRow.unit * 1.5
        width: beltRow.unit * 0.95
        height: beltRow.unit * 2.4
        radius: beltRow.unit * 0.2
        transformOrigin: Item.Top
        rotation: -modelData * 22
        color: beltRow.tone
        border.width: 1
        border.color: beltRow.edge
      }
    }

    // Knot
    Rectangle {
      x: parent.width / 2 - width / 2
      y: beltRow.unit * 0.65
      width: beltRow.unit * 1.7
      height: beltRow.unit * 1.7
      radius: beltRow.unit * 0.35
      color: beltRow.tone
      border.width: 1
      border.color: beltRow.edge
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    visible: beltRow.label !== ""
    text: beltRow.label
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }
}
