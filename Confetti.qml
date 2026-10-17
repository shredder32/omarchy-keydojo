import QtQuick

// Belt-up celebration. Call burst() to rain a handful of pieces.
Item {
  id: confetti

  property var colors: ["#f2c94c", "#f2994a", "#6fcf97", "#56a8f2", "#a974e8", "#eb5757"]
  property int pieces: 70

  function burst() {
    for (var i = 0; i < repeater.count; i++) repeater.itemAt(i).fall()
  }

  Repeater {
    id: repeater
    model: confetti.pieces

    Rectangle {
      id: piece
      required property int index
      width: 6 + (index % 4) * 2
      height: width * 1.6
      color: confetti.colors[index % confetti.colors.length]
      opacity: 0
      radius: 1

      function fall() {
        x = Math.random() * confetti.width
        y = -40 - Math.random() * confetti.height * 0.4
        rotation = Math.random() * 360
        drop.to = confetti.height + 40
        drop.duration = 1600 + Math.random() * 1400
        spin.to = rotation + (Math.random() < 0.5 ? -1 : 1) * (360 + Math.random() * 540)
        spin.duration = drop.duration
        sway.to = x + (Math.random() - 0.5) * 160
        sway.duration = drop.duration
        anim.restart()
      }

      ParallelAnimation {
        id: anim
        NumberAnimation { id: drop; target: piece; property: "y"; easing.type: Easing.InQuad }
        NumberAnimation { id: spin; target: piece; property: "rotation" }
        NumberAnimation { id: sway; target: piece; property: "x"; easing.type: Easing.InOutSine }
        SequentialAnimation {
          NumberAnimation { target: piece; property: "opacity"; to: 1; duration: 120 }
          PauseAnimation { duration: 1200 }
          NumberAnimation { target: piece; property: "opacity"; to: 0; duration: 600 }
        }
      }
    }
  }
}
