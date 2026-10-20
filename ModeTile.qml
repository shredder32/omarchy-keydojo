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
  property bool suggested: false
  property string suggestedText: ""
  property string badge: ""
  // How long the session is ("8 questions", "60 s"); empty hides it.
  property string meta: ""
  property bool calm: false
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color suggestColor: accent
  property color suggestInk: Color.menu.background

  signal activated()

  Rectangle {
    id: body
    width: parent.width
    height: parent.height
    y: tile.selected ? -Style.space(6) : 0
    radius: Math.max(6, Style.cornerRadius)
    // A locked tile fades its frame and icon only: the unlock requirement
    // stays as readable as any other description.
    color: tile.selected ? Util.alpha(tile.accent, 0.18)
      : tile.suggested && !tile.locked ? Util.alpha(tile.suggestColor, 0.1)
      : Util.alpha(tile.foreground, tile.locked ? 0.04 : 0.08)
    border.width: tile.selected || (tile.suggested && !tile.locked) ? Math.max(2, Style.space(2)) : 1
    border.color: tile.selected ? tile.accent
      : tile.suggested && !tile.locked ? tile.suggestColor
      : Util.alpha(tile.foreground, tile.locked ? 0.2 : 0.32)

    Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
    Behavior on color { ColorAnimation { duration: 160 } }

    Text {
      x: Style.space(10)
      y: Style.space(8)
      text: tile.number
      color: Util.alpha(tile.foreground, 0.6)
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

    // The suggested mode wears a filled tag across its top edge, pulsing
    // gently so a first glance lands on it.
    Rectangle {
      id: suggestTag
      visible: tile.suggested && !tile.locked
      anchors.horizontalCenter: parent.horizontalCenter
      y: -height / 2
      height: Style.space(30)
      width: Math.min(parent.width - Style.space(12), suggestRow.implicitWidth + Style.space(24))
      radius: height / 2
      color: tile.suggestColor

      SequentialAnimation on scale {
        running: suggestTag.visible && !tile.calm
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 1.08; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.08; to: 1; duration: 700; easing.type: Easing.InOutSine }
      }

      Row {
        id: suggestRow
        anchors.centerIn: parent
        spacing: Style.space(6)

        Text {
          text: "󰐊"
          color: tile.suggestInk
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          text: tile.suggestedText.toUpperCase()
          color: tile.suggestInk
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          font.letterSpacing: Style.space(1)
        }
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
        opacity: tile.locked ? 0.5 : 1
        font.family: Style.font.family
        font.pixelSize: Style.font.displayLarge * 1.25
        scale: tile.selected && !tile.locked ? 1.12 : 1
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: tile.title
        color: Util.alpha(tile.foreground, tile.locked ? 0.7 : 1)
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: tile.locked ? tile.lockText : tile.subtitle
        color: Util.alpha(tile.foreground, 0.88)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        maximumLineCount: 3
      }

      Text {
        width: parent.width
        visible: tile.meta !== "" && !tile.locked
        horizontalAlignment: Text.AlignHCenter
        text: "󱎫  " + tile.meta
        color: tile.suggested ? tile.suggestColor : Util.alpha(tile.foreground, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: tile.locked ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: tile.activated()
  }
}
