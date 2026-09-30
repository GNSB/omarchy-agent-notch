import QtQuick

// A pill with an agent's coloured face and name. The owner drives
// visibility/animation; this only draws and reports clicks.
Rectangle {
  id: chip

  property color c: "#AAAAAA"
  property string label: ""
  property string mood: "idle"
  property string faceStyle: "orb"
  property var accessory: []
  property string forceReaction: ""
  property bool focused: false
  property string fontFamily: "Noto Sans"
  property bool live: true
  property bool closable: false
  readonly property bool hovered: mouse.containsMouse

  signal activated()
  signal closeRequested()

  height: 38
  radius: height / 2
  color: Qt.alpha(c, focused ? 0.2 : 0.1)
  border.width: 1
  border.color: Qt.alpha(c, focused ? 0.7 : 0.28)
  Behavior on color { ColorAnimation { duration: 200 } }
  Behavior on border.color { ColorAnimation { duration: 200 } }

  AgentFace {
    id: face
    anchors.left: parent.left
    anchors.leftMargin: 9
    anchors.verticalCenter: parent.verticalCenter
    mini: true
    size: 21
    tint: chip.c
    mood: chip.mood
    faceStyle: chip.faceStyle
    accessory: chip.accessory
    forceReaction: chip.forceReaction
    live: chip.live && chip.opacity > 0.01
  }

  Text {
    anchors.left: face.right
    anchors.leftMargin: 9
    anchors.right: parent.right
    anchors.rightMargin: chip.closable && chip.hovered ? 32 : 12
    anchors.verticalCenter: parent.verticalCenter
    text: chip.label
    elide: Text.ElideRight
    color: Qt.lighter(chip.c, 1.25)
    font.family: chip.fontFamily
    font.pixelSize: 13
    font.weight: Font.Medium
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.activated()
  }

  // Remove from the notch (the conversation itself stays in Claude's history).
  Rectangle {
    anchors.right: parent.right
    anchors.rightMargin: 7
    anchors.verticalCenter: parent.verticalCenter
    width: 22; height: 22; radius: 11
    visible: chip.closable
    opacity: chip.hovered || xMouse.containsMouse ? 1 : 0
    scale: opacity > 0 ? (xMouse.containsMouse ? 1.12 : 1) : 0.6
    color: xMouse.containsMouse ? Qt.alpha(chip.c, 0.45) : Qt.rgba(1, 1, 1, 0.1)
    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
    Text { anchors.centerIn: parent; text: "✕"; color: "#F2F3F5"; font.pixelSize: 10 }
    MouseArea {
      id: xMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.closeRequested()
    }
  }
}
