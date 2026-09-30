import QtQuick
import QtQuick.Shapes

// A glossy orb with two pill eyes, modelled on the Grok Bot notch concept.
// The eyes morph between shapes per mood, a soft radial glow carries the
// state colour, and a small badge on the upper left says what it's doing.
// mood: idle | thinking | working | waiting | done | error | sleep
Item {
  id: face

  property string mood: "idle"
  // "errorStale" = an old error: drawn like "error" but holds still.
  readonly property string look: mood === "errorStale" ? "error" : mood
  property color tint: "#E9EEF5"
  property real size: 22
  property bool mini: false            // cluster/chip faces: no badge, small glow
  property bool showBadge: !mini
  property bool glowAlways: false      // keep a faint idle glow (the big faces)
  // Hidden faces (collapsed cluster while expanded, folded chips, …) must not
  // keep ticking: dozens of idle animations at 180 Hz starve the GUI thread.
  property bool live: true
  property bool waving: false          // little hands out, like the reel's hello
  readonly property bool run: live && visible && opacity > 0.01

  readonly property color glowColor: ({
    "errorStale": "#FF4D4D",
    "working": "#3B8BFF", "thinking": "#8B5CF6", "waiting": "#F5A524",
    "done": "#3DD68C", "error": "#FF4D4D", "idle": "#9FB3C8", "sleep": "#6B7280"
  })[mood] || "#9FB3C8"
  readonly property real glowStrength: mood === "sleep" ? 0
    : mood === "idle" ? (glowAlways ? 0.35 : 0)
    : mood === "errorStale" ? (mini ? 0.3 : 0.5)
    : mini ? 0.55 : 0.9
  readonly property color eyeColor: "#141418"
  readonly property bool errorish: look === "error"

  // Animated channels. Each mood's animation drives these; settle() puts
  // them back at rest when the mood changes.
  property real bobY: 0
  property real lookX: 0
  property real lookY: 0
  property real tiltDeg: 0
  property real shakeX: 0
  property real eyeOpen: 1
  property real squashX: 1
  property real squashY: 1
  property real breathe: 1

  implicitWidth: size
  implicitHeight: size

  function settle() {
    bobY = 0; lookX = 0; tiltDeg = 0; shakeX = 0; eyeOpen = 1
    lookY = look === "waiting" ? -size * 0.04 : mood === "thinking" ? -size * 0.03 : 0
  }
  onMoodChanged: {
    settle()
    if (mood !== "errorStale") squashAnim.restart()
    if (mood === "done") sparkles.burst()
  }
  Component.onCompleted: settle()

  // ------------------------------------------------------------------ glow
  Shape {
    id: glow
    anchors.centerIn: body
    width: face.size * (face.mini ? 2.2 : 2.7)
    height: width
    opacity: face.glowStrength * face.breathe
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 400 } }
    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillGradient: RadialGradient {
        centerX: glow.width / 2; centerY: glow.height / 2
        centerRadius: glow.width / 2
        focalX: glow.width / 2; focalY: glow.height / 2
        GradientStop { position: 0.0; color: Qt.alpha(face.glowColor, 0.9) }
        GradientStop { position: 0.32; color: Qt.alpha(face.glowColor, 0.45) }
        GradientStop { position: 0.62; color: Qt.alpha(face.glowColor, 0.12) }
        GradientStop { position: 1.0; color: Qt.alpha(face.glowColor, 0) }
      }
      PathAngleArc {
        centerX: glow.width / 2; centerY: glow.height / 2
        radiusX: glow.width / 2; radiusY: glow.height / 2
        startAngle: 0; sweepAngle: 360
      }
    }
  }

  // ------------------------------------------------------------------ body
  Rectangle {
    id: body
    width: face.size
    height: face.size
    radius: width / 2
    x: face.shakeX
    y: face.bobY
    rotation: face.tiltDeg
    opacity: face.look === "sleep" ? 0.72 : 1
    Behavior on opacity { NumberAnimation { duration: 400 } }

    readonly property color base: face.errorish ? Qt.tint(face.tint, "#90FF7A8A") : face.tint
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.lighter(body.base, 1.12) }
      GradientStop { position: 0.55; color: body.base }
      GradientStop { position: 1.0; color: Qt.darker(body.base, face.mini ? 1.12 : 1.28) }
    }

    transform: Scale {
      origin.x: body.width / 2
      origin.y: body.height
      xScale: face.squashX
      yScale: face.squashY
    }

    // Specular highlight so it reads as a glossy ball.
    Rectangle {
      x: parent.width * 0.18; y: parent.height * 0.1
      width: parent.width * 0.34; height: width * 0.62
      radius: height / 2
      rotation: -28
      color: "white"
      opacity: face.mini ? 0.35 : 0.5
    }

    // ------------------------------------------------------------- eyes
    Item {
      id: eyes
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: face.lookX
      anchors.verticalCenterOffset: face.lookY + (face.look === "sleep" ? face.size * 0.08 : face.size * 0.02)
      width: face.size * 0.46
      height: face.size * 0.36

      Repeater {
        model: 2
        Item {
          id: eyeSlot
          required property int index
          width: face.size * 0.2
          height: eyes.height
          x: index === 0 ? 0 : eyes.width - width

          // One pill that morphs: tall when awake, a dash when annoyed or
          // asleep, squeezed by eyeOpen for blinks.
          Rectangle {
            id: pill
            anchors.centerIn: parent
            visible: face.mood !== "done"
            readonly property real w: face.look === "error" ? face.size * 0.2
              : face.look === "sleep" ? face.size * 0.17 : face.size * 0.13
            readonly property real h: face.look === "error" ? face.size * 0.075
              : face.look === "sleep" ? face.size * 0.05
              : face.look === "waiting" ? face.size * 0.33
              : face.look === "working" ? face.size * 0.27 : face.size * 0.3
            width: w
            height: Math.max(face.size * 0.045, h * face.eyeOpen)
            radius: Math.min(width, height) / 2
            color: face.eyeColor
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on radius { NumberAnimation { duration: 200 } }
          }

          // Happy ^ eyes when a task finished.
          Canvas {
            anchors.centerIn: parent
            visible: face.look === "done"
            width: face.size * 0.22
            height: face.size * 0.15
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.lineWidth = Math.max(1.5, face.size * 0.075)
              ctx.lineCap = "round"
              ctx.lineJoin = "round"
              ctx.strokeStyle = face.eyeColor
              ctx.beginPath()
              ctx.moveTo(ctx.lineWidth, height - ctx.lineWidth / 2)
              ctx.lineTo(width / 2, ctx.lineWidth / 2)
              ctx.lineTo(width - ctx.lineWidth, height - ctx.lineWidth / 2)
              ctx.stroke()
            }
            onVisibleChanged: requestPaint()
            Component.onCompleted: requestPaint()
          }
        }
      }
    }
  }

  // ----------------------------------------------------------------- hands
  // Two small mitts that pop out beside the orb and wave (greeting / done).
  Repeater {
    model: 2
    Rectangle {
      id: hand
      required property int index
      readonly property real side: index === 0 ? -1 : 1
      property real wave: 0
      width: face.size * 0.24
      height: width
      radius: width / 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.lighter(face.tint, 1.1) }
        GradientStop { position: 1.0; color: Qt.darker(face.tint, 1.2) }
      }
      x: body.x + body.width / 2 - width / 2 + side * face.size * (0.66 + wave * 0.06)
      y: body.y + body.height * 0.6 - wave * face.size * 0.38
      scale: face.waving ? 1 : 0
      visible: scale > 0.01
      Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
      SequentialAnimation on wave {
        running: face.waving && face.run
        loops: Animation.Infinite
        PauseAnimation { duration: hand.index * 140 }
        NumberAnimation { to: 1; duration: 240; easing.type: Easing.OutQuad }
        NumberAnimation { to: 0.35; duration: 200; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1; duration: 200; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0; duration: 280; easing.type: Easing.InQuad }
        PauseAnimation { duration: 260 - hand.index * 140 }
      }
    }
  }

  // ----------------------------------------------------------------- badge
  // Upper-left status bubble, like the reel: typing dots while busy, a red
  // dot on error, "!" when it needs you, a tick when done.
  Rectangle {
    id: badge
    readonly property bool dotOnly: face.look === "error"
    readonly property bool shown: face.showBadge
      && (face.look === "working" || face.look === "thinking" || face.look === "waiting"
          || face.look === "done" || face.look === "error")
    width: dotOnly ? face.size * 0.2 : face.size * 0.4
    height: width
    radius: width / 2
    x: body.x + (dotOnly ? face.size * 0.08 : -face.size * 0.08)
    y: body.y + (dotOnly ? face.size * 0.1 : -face.size * 0.04)
    color: face.look === "working" ? "#2F7BFF"
      : face.look === "thinking" ? "#7C4DFF"
      : face.look === "waiting" ? "#F5A524"
      : face.look === "done" ? "#22C07A" : "#FF3B3B"
    border.width: dotOnly ? 0 : Math.max(1, face.size * 0.03)
    border.color: "#0B0B0D"
    scale: shown ? 1 : 0
    visible: scale > 0.01
    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
    Behavior on color { ColorAnimation { duration: 200 } }

    Row {
      anchors.centerIn: parent
      spacing: badge.width * 0.07
      visible: face.look === "working" || face.look === "thinking"
      Repeater {
        model: 3
        Rectangle {
          id: dot
          required property int index
          width: badge.width * 0.17
          height: width
          radius: width / 2
          color: "white"
          SequentialAnimation on y {
            running: face.run && dot.visible && badge.visible
            loops: Animation.Infinite
            PauseAnimation { duration: dot.index * 130 }
            NumberAnimation { from: 0; to: -badge.width * 0.12; duration: 220; easing.type: Easing.OutQuad }
            NumberAnimation { to: 0; duration: 220; easing.type: Easing.InQuad }
            PauseAnimation { duration: (2 - dot.index) * 130 + 260 }
          }
        }
      }
    }
    Text {
      anchors.centerIn: parent
      visible: face.look === "waiting" || face.look === "done"
      text: face.look === "waiting" ? "!" : "✓"
      color: "white"
      font.pixelSize: badge.width * 0.66
      font.bold: true
    }
  }

  // ------------------------------------------------------------ zZz sleep
  // A short puff of z's every few seconds, fired by a Timer (Timers don't
  // keep the render loop spinning; looping animations with pauses do).
  Timer {
    running: face.run && face.look === "sleep" && !face.mini
    repeat: true
    triggeredOnStart: true
    interval: 5200
    onTriggered: { for (var i = 0; i < zees.count; i++) zees.itemAt(i).puff() }
  }
  Repeater {
    id: zees
    model: face.mini ? 0 : 3
    Text {
      id: zee
      required property int index
      text: "z"
      color: "#AEB6C4"
      font.pixelSize: face.size * (0.22 + index * 0.07)
      font.bold: true
      x: face.size * 0.85
      opacity: 0
      visible: face.look === "sleep"
      function puff() { zAnim.restart() }
      SequentialAnimation {
        id: zAnim
        PauseAnimation { duration: zee.index * 450 }
        ParallelAnimation {
          NumberAnimation { target: zee; property: "y"; from: face.size * 0.15; to: -face.size * 0.6; duration: 1700 }
          NumberAnimation { target: zee; property: "x"; from: face.size * 0.8; to: face.size * 1.1; duration: 1700 }
          SequentialAnimation {
            NumberAnimation { target: zee; property: "opacity"; from: 0; to: 0.85; duration: 400 }
            NumberAnimation { target: zee; property: "opacity"; to: 0; duration: 1300 }
          }
        }
      }
    }
  }

  // ------------------------------------------------------- done sparkles
  Item {
    id: sparkles
    anchors.centerIn: body
    width: face.size; height: face.size
    function burst() { if (!face.mini) for (var i = 0; i < rep.count; i++) rep.itemAt(i).fly() }
    Repeater {
      id: rep
      model: 6
      Text {
        id: spark
        required property int index
        readonly property real ang: index * 2 * Math.PI / 6 - Math.PI / 2
        text: "✦"
        color: index % 2 ? "#FFD76E" : "#9BF2C6"
        font.pixelSize: face.size * 0.26
        x: sparkles.width / 2 - width / 2
        y: sparkles.height / 2 - height / 2
        opacity: 0
        function fly() { flyAnim.restart() }
        ParallelAnimation {
          id: flyAnim
          NumberAnimation { target: spark; property: "x"; duration: 750; easing.type: Easing.OutCubic
            from: sparkles.width / 2 - spark.width / 2; to: sparkles.width / 2 - spark.width / 2 + Math.cos(spark.ang) * face.size * 1.05 }
          NumberAnimation { target: spark; property: "y"; duration: 750; easing.type: Easing.OutCubic
            from: sparkles.height / 2 - spark.height / 2; to: sparkles.height / 2 - spark.height / 2 + Math.sin(spark.ang) * face.size * 1.05 }
          SequentialAnimation {
            NumberAnimation { target: spark; property: "opacity"; to: 1; duration: 120 }
            NumberAnimation { target: spark; property: "opacity"; to: 0; duration: 630 }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ animations

  // Squash & stretch whenever the mood changes — the "reaction".
  SequentialAnimation {
    id: squashAnim
    ParallelAnimation {
      NumberAnimation { target: face; property: "squashX"; to: 1.18; duration: 110; easing.type: Easing.OutQuad }
      NumberAnimation { target: face; property: "squashY"; to: 0.82; duration: 110; easing.type: Easing.OutQuad }
    }
    ParallelAnimation {
      NumberAnimation { target: face; property: "squashX"; to: 0.92; duration: 140; easing.type: Easing.InOutQuad }
      NumberAnimation { target: face; property: "squashY"; to: 1.1; duration: 140; easing.type: Easing.InOutQuad }
    }
    ParallelAnimation {
      NumberAnimation { target: face; property: "squashX"; to: 1; duration: 380; easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.4 }
      NumberAnimation { target: face; property: "squashY"; to: 1; duration: 380; easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.4 }
    }
  }

  // Glow breathing; faster when busy, urgent when it needs you. Calm moods
  // keep a static glow: any running animation makes the shell redraw every
  // frame (180 Hz), so idle faces must be truly still between blinks.
  readonly property bool busy: mood === "working" || mood === "thinking" || mood === "waiting" || mood === "error"
  SequentialAnimation {
    running: face.run && face.busy && face.glowStrength > 0
    loops: Animation.Infinite
    onStopped: face.breathe = 1
    NumberAnimation {
      target: face; property: "breathe"; to: 0.55; easing.type: Easing.InOutSine
      duration: face.look === "waiting" || face.look === "error" ? 600 : face.look === "working" ? 1100 : 1800
    }
    NumberAnimation {
      target: face; property: "breathe"; to: 1; easing.type: Easing.InOutSine
      duration: face.look === "waiting" || face.look === "error" ? 600 : face.look === "working" ? 1100 : 1800
    }
  }

  // Gentle float while thinking.
  SequentialAnimation {
    running: face.run && (face.look === "thinking")
    loops: Animation.Infinite
    onStopped: face.bobY = 0
    NumberAnimation { target: face; property: "bobY"; to: -face.size * 0.06; duration: 1400; easing.type: Easing.InOutSine }
    NumberAnimation { target: face; property: "bobY"; to: 0; duration: 1400; easing.type: Easing.InOutSine }
  }

  // Working: small focused nods.
  SequentialAnimation {
    running: face.run && (face.look === "working")
    loops: Animation.Infinite
    onStopped: face.bobY = 0
    NumberAnimation { target: face; property: "bobY"; to: -face.size * 0.08; duration: 240; easing.type: Easing.OutQuad }
    NumberAnimation { target: face; property: "bobY"; to: 0; duration: 300; easing.type: Easing.OutBounce }
    PauseAnimation { duration: 700 }
  }

  // Thinking: eyes wander.
  SequentialAnimation {
    running: face.run && (face.look === "thinking")
    loops: Animation.Infinite
    onStopped: face.lookX = 0
    NumberAnimation { target: face; property: "lookX"; to: -face.size * 0.08; duration: 380; easing.type: Easing.InOutQuad }
    PauseAnimation { duration: 600 }
    NumberAnimation { target: face; property: "lookX"; to: face.size * 0.08; duration: 520; easing.type: Easing.InOutQuad }
    PauseAnimation { duration: 600 }
    NumberAnimation { target: face; property: "lookX"; to: 0; duration: 300; easing.type: Easing.InOutQuad }
    PauseAnimation { duration: 800 }
  }

  // Waiting: impatient head tilt.
  SequentialAnimation {
    running: face.run && (face.look === "waiting")
    loops: Animation.Infinite
    onStopped: face.tiltDeg = 0
    NumberAnimation { target: face; property: "tiltDeg"; to: -11; duration: 220; easing.type: Easing.OutQuad }
    NumberAnimation { target: face; property: "tiltDeg"; to: 11; duration: 320; easing.type: Easing.InOutQuad }
    NumberAnimation { target: face; property: "tiltDeg"; to: 0; duration: 220; easing.type: Easing.InQuad }
    PauseAnimation { duration: 1300 }
  }

  // Error: shake, then glare.
  SequentialAnimation {
    running: face.run && (face.mood === "error")
    loops: Animation.Infinite
    onStopped: face.shakeX = 0
    NumberAnimation { target: face; property: "shakeX"; to: -face.size * 0.1; duration: 50 }
    NumberAnimation { target: face; property: "shakeX"; to: face.size * 0.1; duration: 90 }
    NumberAnimation { target: face; property: "shakeX"; to: -face.size * 0.07; duration: 80 }
    NumberAnimation { target: face; property: "shakeX"; to: face.size * 0.04; duration: 70 }
    NumberAnimation { target: face; property: "shakeX"; to: 0; duration: 60 }
    PauseAnimation { duration: 2800 }
  }

  // Blink every few seconds while awake.
  Timer {
    running: face.run && (face.look === "idle" || face.look === "thinking" || face.look === "working" || face.look === "waiting")
    repeat: true
    interval: 2800 + Math.random() * 1500
    onTriggered: {
      interval = 2200 + Math.random() * 3400
      blinkAnim.restart()
    }
  }
  SequentialAnimation {
    id: blinkAnim
    NumberAnimation { target: face; property: "eyeOpen"; to: 0.08; duration: 70 }
    NumberAnimation { target: face; property: "eyeOpen"; to: 1; duration: 120 }
  }
}
