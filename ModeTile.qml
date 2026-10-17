import QtQuick
import qs.Commons

// One game mode on the home screen.
Item {
  id: tile

  property int number: 1
  property string icon: ""
  property string title: ""
  property string subtitle: ""
  property string lockText: ""
  property bool locked: false
  property bool selected: false
  property string badge: ""
  property color foreground: Color.menu.text
  property color accent: Color.accent

  signal activated()

  Rectangle {
    id: body
    width: parent.width
    height: parent.height
    y: tile.selected ? -Style.space(6) : 0
    radius: Math.max(6, Style.cornerRadius)
    color: tile.selected ? Util.alpha(tile.accent, 0.14) : Util.alpha(tile.foreground, 0.04)
    border.width: tile.selected ? Math.max(2, Style.space(2)) : 1
    border.color: tile.selected ? tile.accent : Util.alpha(tile.foreground, 0.16)
    opacity: tile.locked ? 0.55 : 1

    Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
    Behavior on color { ColorAnimation { duration: 160 } }

    Text {
      x: Style.space(10)
      y: Style.space(8)
      text: tile.number
      color: Util.alpha(tile.foreground, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Rectangle {
      visible: tile.badge !== "" && !tile.locked
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(8)
      height: Style.space(22)
      width: Math.max(height, badgeText.implicitWidth + Style.space(12))
      radius: height / 2
      color: tile.accent

      Text {
        id: badgeText
        anchors.centerIn: parent
        text: tile.badge
        color: Color.menu.background
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    Column {
      anchors.centerIn: parent
      width: parent.width - Style.space(20)
      spacing: Style.space(8)

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: tile.locked ? "󰌾" : tile.icon
        color: tile.selected && !tile.locked ? tile.accent : tile.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.displayLarge * 1.25
        scale: tile.selected && !tile.locked ? 1.12 : 1
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: tile.title
        color: tile.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: tile.locked ? tile.lockText : tile.subtitle
        color: Util.alpha(tile.foreground, 0.65)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        maximumLineCount: 3
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: tile.locked ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: tile.activated()
  }
}
