import QtQuick
import qs.Commons

// A chunky keyboard key. `lit` presses it down; `tone` tints it for feedback.
Item {
  id: cap

  property string text: ""
  property bool lit: false
  property string tone: ""
  property real size: Style.font.heading
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color good: "#7bd88f"
  property color bad: Color.urgent

  readonly property real depth: Math.max(3, Math.round(size * 0.28))
  readonly property color toneColor: tone === "good" ? good : tone === "bad" ? bad : tone === "accent" || lit ? accent : foreground
  readonly property bool tinted: tone !== "" || lit

  implicitHeight: Math.round(size * 2.5)
  implicitWidth: Math.max(implicitHeight * 1.05, label.implicitWidth + size * 1.4)

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: cap.depth
    radius: Math.max(4, Style.cornerRadius)
    color: Util.alpha(cap.toneColor, cap.tinted ? 0.55 : 0.22)
  }

  Rectangle {
    id: face
    width: parent.width
    height: parent.height - cap.depth
    y: cap.lit ? cap.depth * 0.7 : 0
    radius: Math.max(4, Style.cornerRadius)
    color: Qt.tint(Color.menu.background, Util.alpha(cap.toneColor, cap.tinted ? 0.26 : 0.09))
    border.width: Math.max(1, Math.round(cap.size / 14))
    border.color: Util.alpha(cap.toneColor, cap.tinted ? 0.95 : 0.35)

    Behavior on y { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
    Behavior on color { ColorAnimation { duration: 140 } }

    Text {
      id: label
      anchors.centerIn: parent
      text: cap.text
      textFormat: Text.PlainText
      color: cap.tinted ? cap.toneColor : cap.foreground
      font.family: Style.font.family
      font.pixelSize: cap.size
      font.bold: true
    }
  }
}
