import QtQuick
import QtQuick.Shapes

// A glossy orb with two pill eyes, modelled on the Grok Bot notch concept.
// The eyes morph between shapes per mood, a soft radial glow carries the
// state colour, and a small badge on the upper left says what it's doing.
// mood: idle | thinking | working | upload | restart | waiting | done | error | sleep
// Pointer: eyes follow the cursor; 3 quick pokes annoy it, 6 (or shaking
// the cursor over it) make it dizzy.
// faceStyle: "orb" (plain ball) | "cat" (ears, nose, whiskers, tail)
//            | "dog" (floppy ears, snout, tongue, eye patch, wagging tail)
//            | "hamster" (round ears, golden cap, stuffed cheeks, buck teeth)
// accessory: one name or a list — hat, cowboy, crown, party, bow, headphones,
//            helmet, mask, glasses, shades
Item {
  id: face

  property string mood: "idle"
  property string faceStyle: "orb"
  readonly property bool cat: faceStyle === "cat"
  readonly property bool dog: faceStyle === "dog"
  readonly property bool hamster: faceStyle === "hamster"
  readonly property bool animal: cat || dog || hamster
  readonly property color furDark: Qt.tint(body.base, "#A07A4A2A")   // dog ears / patch
  property var accessory: []
  readonly property var gear: Array.isArray(accessory) ? accessory : accessory ? [accessory] : []
  function wears(n) { return gear.indexOf(n) >= 0 }
  // "errorStale" = an old error: drawn like "error" but holds still.
  // A pointer reaction (annoyed | dizzy) briefly overrides the mood's look.
  property string reaction: ""
  property string forceReaction: ""
  onForceReactionChanged: if (forceReaction) react(forceReaction)
  property bool interactive: true
  readonly property string look: reaction !== "" ? reaction : mood === "errorStale" ? "error" : mood
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
    "done": "#3DD68C", "error": "#FF4D4D", "idle": "#9FB3C8", "sleep": "#6B7280",
    "upload": "#3CC8E0", "restart": "#E879F9"
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
  property real earFlick: 0            // cat: one ear twitches (deg)
  property real tailWag: 0             // cat: tail swing (deg)
  property real spinDeg: 0             // restart: full turns
  property real gazeX: 0               // pointer gaze, lazily sprung
  property real gazeY: 0
  Behavior on gazeX { SpringAnimation { spring: 2.2; damping: 0.32 } }
  Behavior on gazeY { SpringAnimation { spring: 2.2; damping: 0.32 } }
  property real dizzyPhase: 0
  readonly property real wobX: look === "dizzy" ? Math.sin(dizzyPhase) * size * 0.05 : 0
  readonly property real wobDeg: look === "dizzy" ? Math.sin(dizzyPhase) * 9 : 0
  readonly property real turn: tiltDeg + spinDeg + wobDeg

  implicitWidth: size
  implicitHeight: size

  function settle() {
    bobY = 0; lookX = 0; tiltDeg = 0; shakeX = 0; eyeOpen = 1
    lookY = look === "waiting" ? -size * 0.04 : look === "thinking" ? -size * 0.03
      : look === "upload" ? -size * 0.06 : 0
  }
  onLookChanged: settle()
  onMoodChanged: {
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
    x: face.shakeX + face.wobX
    y: face.bobY
    rotation: face.turn
    z: 0
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

    // ----------------------------------------------------------- cat ears
    // Children with negative z draw beneath the body, so the ears poke out
    // from behind the ball and ride along with every transform.
    Repeater {
      model: face.cat ? 2 : 0
      Item {
        id: ear
        required property int index
        readonly property real side: index === 0 ? -1 : 1
        readonly property real s: face.size
        function px(x) { return side < 0 ? x * s : s - x * s }
        // Ears fold back when angry, droop when asleep, perk up when it needs you.
        readonly property real pose: face.look === "error" || face.look === "annoyed" ? 26
          : face.look === "sleep" || face.look === "dizzy" ? 16
          : face.look === "waiting" ? -6 : 0
        z: -1
        width: s; height: s
        transform: Rotation {
          origin.x: ear.px(0.24); origin.y: ear.s * 0.2
          angle: ear.side * (ear.pose + (ear.index === 1 ? face.earFlick : 0))
          Behavior on angle { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
        }
        Shape {
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: Qt.lighter(body.base, 1.05)
            strokeColor: fillColor
            strokeWidth: ear.s * 0.07
            joinStyle: ShapePath.RoundJoin
            startX: ear.px(0.04); startY: ear.s * 0.36
            PathLine { x: ear.px(0.10); y: -ear.s * 0.10 }
            PathLine { x: ear.px(0.44); y: ear.s * 0.05 }
            PathLine { x: ear.px(0.04); y: ear.s * 0.36 }
          }
          ShapePath {
            fillColor: Qt.tint(body.base, "#80FF8FA8")
            strokeColor: "transparent"
            startX: ear.px(0.11); startY: ear.s * 0.20
            PathLine { x: ear.px(0.14); y: -ear.s * 0.01 }
            PathLine { x: ear.px(0.31); y: ear.s * 0.09 }
            PathLine { x: ear.px(0.11); y: ear.s * 0.20 }
          }
        }
      }
    }

    // ------------------------------------------------------ cat / dog tail
    Shape {
      id: tail
      visible: (face.cat || face.dog) && !face.mini
      z: -2
      width: face.size; height: face.size
      preferredRendererType: Shape.CurveRenderer
      transform: Rotation {
        origin.x: face.size * 0.8; origin.y: face.size * 0.86
        angle: face.tailWag + (face.look === "sleep" ? 38 : 0)
        Behavior on angle { enabled: face.look === "sleep"; NumberAnimation { duration: 500 } }
      }
      ShapePath {
        fillColor: "transparent"
        strokeColor: face.dog ? face.furDark : Qt.darker(body.base, 1.12)
        strokeWidth: face.size * (face.dog ? 0.15 : 0.13)
        capStyle: ShapePath.RoundCap
        startX: face.size * 0.78; startY: face.size * 0.86
        // Dog: short stubby tail up; cat: long curl.
        PathQuad {
          x: face.size * (face.dog ? 1.06 : 1.14); y: face.size * (face.dog ? 0.52 : 0.3)
          controlX: face.size * (face.dog ? 1.1 : 1.28); controlY: face.size * (face.dog ? 0.86 : 0.92)
        }
      }
    }

    // ------------------------------------------------------- hamster ears
    Repeater {
      model: face.hamster ? 2 : 0
      Rectangle {
        id: hEar
        required property int index
        readonly property real side: index === 0 ? -1 : 1
        z: -1
        width: face.size * 0.34; height: width; radius: width / 2
        x: face.size * (index === 0 ? 0.04 : 0.62)
        y: -face.size * 0.08
        color: Qt.tint(body.base, "#90D9893F")
        transform: Rotation {
          origin.x: face.size * 0.17; origin.y: face.size * 0.3
          angle: -hEar.side * ((face.look === "sleep" || face.look === "annoyed" ? 20 : 0) + (hEar.index === 1 ? face.earFlick : 0))
          Behavior on angle { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
        }
        Rectangle {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -parent.height * 0.04
          width: parent.width * 0.56; height: width; radius: width / 2
          color: "#F6A6B9"
        }
      }
    }
    // Hamster: golden cap over the top of the head, white face below.
    Shape {
      visible: face.hamster
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: Qt.tint(body.base, "#B0E39A4E")
        strokeColor: "transparent"
        startX: face.size * 0.03; startY: face.size * 0.33
        PathArc { x: face.size * 0.97; y: face.size * 0.33; radiusX: face.size * 0.5; radiusY: face.size * 0.5; direction: PathArc.Clockwise }
        PathQuad { x: face.size * 0.03; y: face.size * 0.33; controlX: face.size * 0.5; controlY: face.size * 0.26 }
      }
    }
    // Dog: a darker patch around one eye.
    Rectangle {
      visible: face.dog
      // Rides along with the eye it circles.
      x: face.size * 0.52 + face.lookX + face.gazeX; y: face.size * 0.22 + face.lookY + face.gazeY
      width: face.size * 0.3; height: face.size * 0.3
      radius: width / 2
      rotation: 20
      color: face.furDark
      opacity: 0.8
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
      anchors.horizontalCenterOffset: face.lookX + face.gazeX
      anchors.verticalCenterOffset: face.lookY + face.gazeY + (face.look === "sleep" ? face.size * 0.08 : face.size * 0.02)
        - (face.animal ? face.size * 0.06 : 0)
      width: face.size * 0.46
      height: face.size * 0.36

      // Eye centres in this item: x = size*0.1 / width - size*0.1, y = height/2.
      // Hero mask sits under the pupils, with white holes behind them.
      Rectangle {
        visible: face.wears("mask")
        anchors.centerIn: parent
        width: eyes.width + face.size * 0.3; height: face.size * 0.28
        radius: height / 2
        color: "#1E1E26"
        Repeater {
          model: 2
          Rectangle {
            required property int index
            width: face.size * 0.2; height: face.size * 0.22; radius: width / 2
            x: (index === 0 ? face.size * 0.25 : parent.width - face.size * 0.25) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
          }
        }
      }

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
            visible: face.look !== "done" && face.look !== "dizzy"
            readonly property real w: face.look === "error" ? face.size * 0.2
              : face.look === "sleep" || face.look === "restart" ? face.size * 0.17
              : face.look === "annoyed" ? face.size * 0.17 : face.size * 0.13
            readonly property real h: face.look === "error" ? face.size * 0.075
              : face.look === "sleep" || face.look === "restart" ? face.size * 0.05
              : face.look === "annoyed" ? face.size * 0.11
              : face.look === "waiting" ? face.size * 0.33
              : face.look === "working" ? face.size * 0.27 : face.size * 0.3
            width: w
            height: Math.max(face.size * 0.045, h * face.eyeOpen)
            radius: Math.min(width, height) / 2
            color: face.eyeColor
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on radius { NumberAnimation { duration: 200 } }
            // Cat: a tiny catchlight so the slit reads as an eye.
            Rectangle {
              visible: face.animal && !face.mini && pill.height > face.size * 0.15
              x: pill.width * 0.5; y: pill.height * 0.18
              width: Math.max(1.5, face.size * 0.045); height: width; radius: width / 2
              color: "white"; opacity: 0.85
            }
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

          // Dizzy: spinning spiral eyes.
          Canvas {
            id: spiral
            anchors.centerIn: parent
            visible: face.look === "dizzy"
            width: face.size * 0.24
            height: width
            onPaint: {
              var ctx = getContext("2d"), c = width / 2
              ctx.reset()
              ctx.lineWidth = Math.max(1.2, face.size * 0.035)
              ctx.lineCap = "round"
              ctx.strokeStyle = face.eyeColor
              ctx.beginPath()
              for (var i = 0; i <= 50; i++) {
                var t = i / 50, a = t * 2.3 * 2 * Math.PI, r = t * (c - ctx.lineWidth)
                if (i === 0) ctx.moveTo(c, c)
                else ctx.lineTo(c + Math.cos(a) * r, c + Math.sin(a) * r)
              }
              ctx.stroke()
            }
            onVisibleChanged: requestPaint()
            Component.onCompleted: requestPaint()
            RotationAnimation on rotation {
              running: face.run && spiral.visible
              loops: Animation.Infinite
              from: 0; to: eyeSlot.index === 0 ? 360 : -360
              duration: 900
            }
          }

          // Annoyed: brows slanting down to the middle.
          Rectangle {
            visible: face.look === "annoyed"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -face.size * 0.13
            width: face.size * 0.22
            height: Math.max(1.5, face.size * 0.05)
            radius: height / 2
            rotation: eyeSlot.index === 0 ? 22 : -22
            color: face.eyeColor
          }
        }
      }

      // Glasses / shades over the eyes.
      Repeater {
        model: face.wears("glasses") || face.wears("shades") ? 2 : 0
        Rectangle {
          required property int index
          readonly property bool dark: face.wears("shades")
          width: face.size * (dark ? 0.3 : 0.27); height: dark ? width * 0.78 : width
          radius: dark ? height * 0.4 : width / 2
          x: (index === 0 ? face.size * 0.1 : eyes.width - face.size * 0.1) - width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: dark ? "#16161C" : Qt.alpha("#BFE3FF", 0.18)
          border.width: Math.max(1, face.size * 0.035)
          border.color: "#1A1A1F"
          Rectangle {
            visible: parent.dark
            x: parent.width * 0.2; y: parent.height * 0.2
            width: parent.width * 0.3; height: Math.max(1, parent.height * 0.14); radius: height / 2
            rotation: -20; color: "white"; opacity: 0.55
          }
        }
      }
      Rectangle {
        visible: face.wears("glasses") || face.wears("shades")
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -face.size * 0.02
        width: eyes.width - face.size * 0.3; height: Math.max(1, face.size * 0.035)
        color: "#1A1A1F"
      }
    }
  }

  // ---------------------------------------------------------- dog ears
  // Outside the muzzle so they stay put on the head while the face looks around.
  Item {
    id: dogEars
    visible: face.dog
    x: body.x; y: body.y
    width: face.size; height: face.size
    rotation: face.turn
    transform: Scale {
      origin.x: dogEars.width / 2; origin.y: dogEars.height
      xScale: face.squashX; yScale: face.squashY
    }
    // Dog: floppy ears hanging over the sides of the head.
    Repeater {
      model: face.dog ? 2 : 0
      Rectangle {
        id: dEar
        required property int index
        readonly property real side: index === 0 ? -1 : 1
        width: face.size * 0.28; height: face.size * 0.5
        radius: width / 2
        x: index === 0 ? -face.size * 0.1 : face.size * 0.82
        y: face.size * 0.02
        color: face.furDark
        transform: Rotation {
          origin.x: face.size * 0.14; origin.y: 0
          // Perk up when it needs you, flop when sad or asleep.
          angle: dEar.side * (-14 + (face.look === "waiting" ? -26 : face.look === "sleep" || face.look === "error" ? 10 : 0)
            - (dEar.index === 1 ? face.earFlick : 0))
          Behavior on angle { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }
        }
      }
    }
  }

  // ------------------------------------------------------------- muzzle
  // Nose, mouth, whiskers and cheeks follow the eyes' gaze (a bit less, for
  // depth) so the whole face turns together.
  Item {
    id: muzzle
    visible: face.animal
    x: body.x; y: body.y
    width: face.size; height: face.size
    rotation: face.turn
    transform: [
      Translate {
        x: (face.lookX + face.gazeX) * 0.8
        y: (face.lookY + face.gazeY) * 0.6
      },
      Scale {
        origin.x: muzzle.width / 2; origin.y: muzzle.height
        xScale: face.squashX; yScale: face.squashY
      }
    ]
    // Hamster: stuffed cheeks (they puff up while it works).
    Repeater {
      model: face.hamster ? 2 : 0
      Rectangle {
        required property int index
        width: face.size * 0.3; height: face.size * 0.24
        radius: height / 2
        x: index === 0 ? face.size * 0.02 : face.size * 0.68
        y: face.size * 0.58
        color: "#FFF6EE"
        scale: face.look === "working" || face.look === "upload" ? 1.18 : 1
        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.5; height: parent.height * 0.45; radius: height / 2
          color: "#FF9AB0"; opacity: 0.55
        }
      }
    }
    // Dog: pale snout under the nose.
    Rectangle {
      visible: face.dog
      x: face.size * 0.29; y: face.size * 0.54
      width: face.size * 0.42; height: face.size * 0.3
      radius: height / 2
      color: "white"; opacity: 0.6
    }
    // Dog: tongue out when busy or happy.
    Rectangle {
      visible: face.dog && (face.look === "done" || face.look === "working" || face.look === "upload")
      x: face.size * 0.455; y: face.size * 0.69
      width: face.size * 0.09; height: face.size * 0.13
      radius: width / 2
      color: "#F0708C"
    }
    // Dog: big black nose.
    Rectangle {
      visible: face.dog
      x: face.size * 0.41; y: face.size * 0.55
      width: face.size * 0.18; height: face.size * 0.11
      radius: height / 2
      color: "#1F1F24"
      Rectangle { x: parent.width * 0.22; y: parent.height * 0.18; width: parent.width * 0.26; height: parent.height * 0.28; radius: height / 2; color: "white"; opacity: 0.5 }
    }
    // Hamster: tiny pink nose + buck teeth.
    Rectangle {
      visible: face.hamster
      x: face.size * 0.465; y: face.size * 0.58
      width: face.size * 0.07; height: face.size * 0.055
      radius: height / 2
      color: "#F28CA6"
    }
    Row {
      visible: face.hamster && !face.mini
      x: face.size * 0.45; y: face.size * 0.685
      spacing: face.size * 0.005
      Repeater {
        model: 2
        Rectangle {
          width: face.size * 0.048; height: face.size * 0.07
          radius: width * 0.3
          color: "white"
          border.width: Math.max(0.8, face.size * 0.012); border.color: "#B8BEC8"
        }
      }
    }
    // Cat: pink nose.
    Shape {
      visible: face.cat
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "#F28CA6"
        strokeColor: fillColor
        strokeWidth: face.size * 0.03
        joinStyle: ShapePath.RoundJoin
        startX: face.size * 0.45; startY: face.size * 0.6
        PathLine { x: face.size * 0.55; y: face.size * 0.6 }
        PathLine { x: face.size * 0.5; y: face.size * 0.66 }
        PathLine { x: face.size * 0.45; y: face.size * 0.6 }
      }
    }
    // ω mouth (a frown when it errors) and whiskers.
    Canvas {
      id: whiskers
      visible: !face.mini
      anchors.centerIn: parent
      width: face.size * 1.7; height: face.size
      readonly property bool frown: face.look === "error" || face.look === "annoyed"
      readonly property string kind: face.faceStyle
      onFrownChanged: requestPaint()
      onKindChanged: requestPaint()
      onVisibleChanged: requestPaint()
      Component.onCompleted: requestPaint()
      onPaint: {
        var ctx = getContext("2d"), s = face.size, ox = (width - s) / 2
        ctx.reset()
        ctx.lineCap = "round"
        ctx.strokeStyle = face.eyeColor
        ctx.lineWidth = Math.max(1, s * 0.035)
        ctx.beginPath()
        if (kind === "dog") {
          // Line down from the nose, then a smile (or frown) either side.
          var my = frown ? 0.74 : 0.7
          ctx.moveTo(ox + s * 0.5, s * 0.64); ctx.lineTo(ox + s * 0.5, s * 0.69)
          ctx.moveTo(ox + s * 0.4, s * (frown ? 0.76 : 0.68))
          ctx.quadraticCurveTo(ox + s * 0.45, s * my + (frown ? -s * 0.05 : s * 0.04), ox + s * 0.5, s * 0.69)
          ctx.quadraticCurveTo(ox + s * 0.55, s * my + (frown ? -s * 0.05 : s * 0.04), ox + s * 0.6, s * (frown ? 0.76 : 0.68))
          ctx.stroke()
          return
        }
        if (kind === "hamster") {
          ctx.moveTo(ox + s * 0.44, s * 0.66)
          ctx.quadraticCurveTo(ox + s * 0.47, s * 0.69, ox + s * 0.5, s * 0.64)
          ctx.quadraticCurveTo(ox + s * 0.53, s * 0.69, ox + s * 0.56, s * 0.66)
          ctx.stroke()
          ctx.strokeStyle = "#A7AFBA"
          ctx.lineWidth = Math.max(1, s * 0.018)
          ctx.beginPath()
          for (var j = -1; j <= 1; j += 2) {
            ctx.moveTo(ox + s * 0.36, s * (0.64 + j * 0.02)); ctx.lineTo(ox + s * 0.1, s * (0.62 + j * 0.06))
            ctx.moveTo(ox + s * 0.64, s * (0.64 + j * 0.02)); ctx.lineTo(ox + s * 0.9, s * (0.62 + j * 0.06))
          }
          ctx.stroke()
          return
        }
        if (frown) {
          ctx.moveTo(ox + s * 0.42, s * 0.76)
          ctx.quadraticCurveTo(ox + s * 0.5, s * 0.68, ox + s * 0.58, s * 0.76)
        } else {
          ctx.moveTo(ox + s * 0.4, s * 0.69)
          ctx.quadraticCurveTo(ox + s * 0.45, s * 0.76, ox + s * 0.5, s * 0.67)
          ctx.quadraticCurveTo(ox + s * 0.55, s * 0.76, ox + s * 0.6, s * 0.69)
        }
        ctx.stroke()
        ctx.strokeStyle = "#8A93A0"
        ctx.lineWidth = Math.max(1, s * 0.022)
        ctx.beginPath()
        for (var i = -1; i <= 1; i++) {
          ctx.moveTo(ox + s * 0.3, s * (0.64 + i * 0.04))
          ctx.lineTo(ox - s * 0.12, s * (0.6 + i * 0.1))
          ctx.moveTo(ox + s * 0.7, s * (0.64 + i * 0.04))
          ctx.lineTo(ox + s * 1.12, s * (0.6 + i * 0.1))
        }
        ctx.stroke()
      }
    }
  }

  // ------------------------------------------------------------ head gear
  // Same transforms as the body so hats ride along with bobs and tilts.
  Item {
    id: gearTop
    readonly property real s: face.size
    visible: face.gear.length > 0
    x: body.x; y: body.y
    width: s; height: s
    rotation: face.turn
    transform: Scale {
      origin.x: gearTop.width / 2; origin.y: gearTop.height
      xScale: face.squashX; yScale: face.squashY
    }

    // Astronaut helmet: a glass bubble around the whole head.
    Rectangle {
      visible: face.wears("helmet")
      anchors.centerIn: parent
      width: gearTop.s * 1.36; height: width; radius: width / 2
      color: Qt.alpha("#BFE3FF", 0.14)
      border.width: Math.max(1.5, gearTop.s * 0.05)
      border.color: "#DDE3EA"
      Rectangle {
        x: parent.width * 0.2; y: parent.height * 0.12
        width: parent.width * 0.26; height: Math.max(1.5, parent.width * 0.06); radius: height / 2
        rotation: -35; color: "white"; opacity: 0.7
      }
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: -height * 0.35
        width: parent.width * 0.62; height: gearTop.s * 0.14; radius: height / 2
        color: "#C9D1DB"; border.width: 1; border.color: "#8E99A6"
      }
    }

    // Headphones: a band over the top and two cups.
    Shape {
      visible: face.wears("headphones")
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "transparent"
        strokeColor: "#2A2A32"
        strokeWidth: gearTop.s * 0.08
        capStyle: ShapePath.RoundCap
        startX: gearTop.s * 0.02; startY: gearTop.s * 0.48
        PathArc { x: gearTop.s * 0.98; y: gearTop.s * 0.48; radiusX: gearTop.s * 0.5; radiusY: gearTop.s * 0.56 }
      }
    }
    Repeater {
      model: face.wears("headphones") ? 2 : 0
      Rectangle {
        required property int index
        width: gearTop.s * 0.2; height: gearTop.s * 0.36; radius: width * 0.45
        x: index === 0 ? -gearTop.s * 0.08 : gearTop.s * 0.88
        y: gearTop.s * 0.34
        color: "#2A2A32"
        border.width: Math.max(1, gearTop.s * 0.03)
        border.color: Qt.darker(face.glowColor, 1.1)
      }
    }

    // Top hat.
    Item {
      visible: face.wears("hat")
      width: gearTop.s * 0.8; height: gearTop.s * 0.52
      x: gearTop.s * 0.1; y: gearTop.s * 0.12 - height
      rotation: -9
      transformOrigin: Item.Bottom
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: gearTop.s * 0.06
        width: parent.width * 0.62; height: parent.height * 0.86; radius: gearTop.s * 0.05
        gradient: Gradient {
          GradientStop { position: 0.0; color: "#34343E" }
          GradientStop { position: 1.0; color: "#16161B" }
        }
        Rectangle {
          anchors.bottom: parent.bottom; anchors.bottomMargin: parent.height * 0.08
          width: parent.width; height: parent.height * 0.18
          color: "#D2463C"
        }
      }
      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width; height: gearTop.s * 0.1; radius: height / 2
        color: "#1C1C22"
      }
    }

    // Cowboy hat: dented crown, band, wide brim curling up at the ends.
    Shape {
      visible: face.wears("cowboy")
      anchors.fill: parent
      rotation: -7
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: "#6B4424"
        strokeWidth: gearTop.s * 0.03
        joinStyle: ShapePath.RoundJoin
        fillGradient: LinearGradient {
          y1: -gearTop.s * 0.36; y2: gearTop.s * 0.08
          GradientStop { position: 0; color: "#C68A4E" }
          GradientStop { position: 1; color: "#94602F" }
        }
        startX: gearTop.s * 0.24; startY: gearTop.s * 0.06
        PathLine { x: gearTop.s * 0.28; y: -gearTop.s * 0.28 }
        PathQuad { x: gearTop.s * 0.5; y: -gearTop.s * 0.24; controlX: gearTop.s * 0.38; controlY: -gearTop.s * 0.4 }
        PathQuad { x: gearTop.s * 0.72; y: -gearTop.s * 0.28; controlX: gearTop.s * 0.62; controlY: -gearTop.s * 0.4 }
        PathLine { x: gearTop.s * 0.76; y: gearTop.s * 0.06 }
        PathLine { x: gearTop.s * 0.24; y: gearTop.s * 0.06 }
      }
      ShapePath {
        strokeColor: "#3A2414"
        strokeWidth: gearTop.s * 0.07
        capStyle: ShapePath.FlatCap
        fillColor: "transparent"
        startX: gearTop.s * 0.255; startY: -gearTop.s * 0.02
        PathLine { x: gearTop.s * 0.745; y: -gearTop.s * 0.02 }
      }
      ShapePath {
        strokeColor: "#6B4424"
        strokeWidth: gearTop.s * 0.03
        joinStyle: ShapePath.RoundJoin
        fillColor: "#A86E38"
        startX: -gearTop.s * 0.16; startY: -gearTop.s * 0.06
        PathQuad { x: gearTop.s * 1.16; y: -gearTop.s * 0.06; controlX: gearTop.s * 0.5; controlY: gearTop.s * 0.34 }
        PathQuad { x: -gearTop.s * 0.16; y: -gearTop.s * 0.06; controlX: gearTop.s * 0.5; controlY: gearTop.s * 0.14 }
      }
    }

    // Crown.
    Shape {
      visible: face.wears("crown")
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: "#B8860B"
        strokeWidth: gearTop.s * 0.04
        joinStyle: ShapePath.RoundJoin
        fillGradient: LinearGradient {
          y1: -gearTop.s * 0.24; y2: gearTop.s * 0.1
          GradientStop { position: 0; color: "#FFE680" }
          GradientStop { position: 1; color: "#E0A91B" }
        }
        startX: gearTop.s * 0.24; startY: gearTop.s * 0.1
        PathLine { x: gearTop.s * 0.22; y: -gearTop.s * 0.22 }
        PathLine { x: gearTop.s * 0.37; y: -gearTop.s * 0.06 }
        PathLine { x: gearTop.s * 0.5; y: -gearTop.s * 0.27 }
        PathLine { x: gearTop.s * 0.63; y: -gearTop.s * 0.06 }
        PathLine { x: gearTop.s * 0.78; y: -gearTop.s * 0.22 }
        PathLine { x: gearTop.s * 0.76; y: gearTop.s * 0.1 }
        PathLine { x: gearTop.s * 0.24; y: gearTop.s * 0.1 }
      }
    }
    Rectangle {
      visible: face.wears("crown")
      x: gearTop.s * 0.45; y: -gearTop.s * 0.04
      width: gearTop.s * 0.1; height: width; radius: width / 2
      color: "#E5364B"
    }

    // Party cone with a pompom.
    Item {
      visible: face.wears("party")
      width: gearTop.s; height: gearTop.s
      rotation: 12
      transformOrigin: Item.Center
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: "#5B3FD9"
          strokeWidth: gearTop.s * 0.03
          joinStyle: ShapePath.RoundJoin
          fillGradient: LinearGradient {
            x1: gearTop.s * 0.35; x2: gearTop.s * 0.65
            GradientStop { position: 0; color: "#8B6CF6" }
            GradientStop { position: 0.5; color: "#EC6FB3" }
            GradientStop { position: 1; color: "#8B6CF6" }
          }
          startX: gearTop.s * 0.32; startY: gearTop.s * 0.08
          PathLine { x: gearTop.s * 0.5; y: -gearTop.s * 0.42 }
          PathLine { x: gearTop.s * 0.68; y: gearTop.s * 0.08 }
          PathLine { x: gearTop.s * 0.32; y: gearTop.s * 0.08 }
        }
      }
      Rectangle {
        x: gearTop.s * 0.43; y: -gearTop.s * 0.5
        width: gearTop.s * 0.14; height: width; radius: width / 2
        color: "#F2C94C"
      }
    }

    // Bow on the side of the head.
    Item {
      visible: face.wears("bow")
      x: gearTop.s * 0.62; y: -gearTop.s * 0.02
      width: gearTop.s * 0.36; height: gearTop.s * 0.24
      rotation: 18
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          fillColor: "#FF6FA8"
          strokeColor: "#D94A86"
          strokeWidth: gearTop.s * 0.025
          joinStyle: ShapePath.RoundJoin
          startX: gearTop.s * 0.18; startY: gearTop.s * 0.12
          PathLine { x: 0; y: 0 }
          PathLine { x: 0; y: gearTop.s * 0.24 }
          PathLine { x: gearTop.s * 0.18; y: gearTop.s * 0.12 }
          PathLine { x: gearTop.s * 0.36; y: 0 }
          PathLine { x: gearTop.s * 0.36; y: gearTop.s * 0.24 }
          PathLine { x: gearTop.s * 0.18; y: gearTop.s * 0.12 }
        }
      }
      Rectangle {
        anchors.centerIn: parent
        width: gearTop.s * 0.09; height: width; radius: width / 2
        color: "#D94A86"
      }
    }
  }

  // ------------------------------------------------------- dizzy / annoyed
  Item {
    id: stars
    visible: face.look === "dizzy"
    x: body.x; y: body.y - face.size * 0.14
    width: face.size; height: face.size * 0.3
    property real orbit: 0
    NumberAnimation on orbit {
      running: face.run && stars.visible
      from: 0; to: 2 * Math.PI; duration: 1100; loops: Animation.Infinite
    }
    Repeater {
      model: 3
      Text {
        required property int index
        readonly property real a: stars.orbit + index * 2 * Math.PI / 3
        text: "✦"
        color: index === 1 ? "#FFB020" : "#FFC83D"
        style: Text.Outline; styleColor: "#7A4B00"
        font.pixelSize: face.size * (face.mini ? 0.3 : 0.26)
        x: stars.width / 2 + Math.cos(a) * face.size * 0.44 - width / 2
        y: stars.height / 2 + Math.sin(a) * face.size * 0.1 - height / 2
        scale: 0.75 + 0.3 * Math.sin(a)
      }
    }
  }
  // Anime anger mark on the forehead.
  Canvas {
    id: anger
    visible: face.look === "annoyed" && !face.mini
    x: body.x + face.size * 0.68; y: body.y - face.size * 0.04
    width: face.size * 0.3; height: width
    onPaint: {
      var ctx = getContext("2d"), w = width, g = w * 0.12
      ctx.reset()
      ctx.lineWidth = Math.max(1.5, face.size * 0.045)
      ctx.lineCap = "round"
      ctx.strokeStyle = "#FF4D4D"
      ctx.beginPath()
      // four little brackets facing the centre
      ctx.moveTo(w / 2 - g, g); ctx.quadraticCurveTo(w / 2 - g, w / 2 - g, g, w / 2 - g)
      ctx.moveTo(w / 2 + g, g); ctx.quadraticCurveTo(w / 2 + g, w / 2 - g, w - g, w / 2 - g)
      ctx.moveTo(w / 2 - g, w - g); ctx.quadraticCurveTo(w / 2 - g, w / 2 + g, g, w / 2 + g)
      ctx.moveTo(w / 2 + g, w - g); ctx.quadraticCurveTo(w / 2 + g, w / 2 + g, w - g, w / 2 + g)
      ctx.stroke()
    }
    onVisibleChanged: requestPaint()
    Component.onCompleted: requestPaint()
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
          || face.look === "done" || face.look === "error" || face.look === "upload" || face.look === "restart")
    width: dotOnly ? face.size * 0.2 : face.size * 0.4
    height: width
    radius: width / 2
    x: body.x + (dotOnly ? face.size * 0.08 : -face.size * 0.08)
    y: body.y + (dotOnly ? face.size * 0.1 : -face.size * 0.04)
    color: face.look === "working" ? "#2F7BFF"
      : face.look === "thinking" ? "#7C4DFF"
      : face.look === "waiting" ? "#F5A524"
      : face.look === "upload" ? "#12A4C0"
      : face.look === "restart" ? "#C026D3"
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
      id: badgeGlyph
      anchors.centerIn: parent
      visible: face.look === "waiting" || face.look === "done" || face.look === "upload" || face.look === "restart"
      text: ({ "waiting": "!", "done": "✓", "upload": "↑", "restart": "↻" })[face.look] || ""
      color: "white"
      font.pixelSize: badge.width * 0.66
      font.bold: true
      // Upload: the arrow keeps lifting off; restart: the arrow turns.
      SequentialAnimation on anchors.verticalCenterOffset {
        running: face.run && face.look === "upload" && badge.visible
        loops: Animation.Infinite
        onStopped: badgeGlyph.anchors.verticalCenterOffset = 0
        NumberAnimation { from: badge.width * 0.18; to: -badge.width * 0.18; duration: 520; easing.type: Easing.OutQuad }
        PauseAnimation { duration: 180 }
      }
      RotationAnimation on rotation {
        running: face.run && face.look === "restart" && badge.visible
        loops: Animation.Infinite
        from: 0; to: 360; duration: 900
        onStopped: badgeGlyph.rotation = 0
      }
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
    || mood === "upload" || mood === "restart"
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

  // Upload: little hops, eyes up at where the files are going.
  SequentialAnimation {
    running: face.run && face.look === "upload"
    loops: Animation.Infinite
    onStopped: face.bobY = 0
    NumberAnimation { target: face; property: "bobY"; to: -face.size * 0.1; duration: 260; easing.type: Easing.OutQuad }
    NumberAnimation { target: face; property: "bobY"; to: 0; duration: 260; easing.type: Easing.InQuad }
    PauseAnimation { duration: 420 }
  }

  // Restart: eyes shut, a full spin, a beat, again.
  SequentialAnimation {
    running: face.run && face.look === "restart"
    loops: Animation.Infinite
    onStopped: face.spinDeg = 0
    NumberAnimation { target: face; property: "spinDeg"; from: 0; to: 360; duration: 800; easing.type: Easing.InOutBack }
    PauseAnimation { duration: 600 }
  }

  // Dizzy: the head wobbles in circles.
  NumberAnimation on dizzyPhase {
    running: face.run && face.look === "dizzy"
    from: 0; to: 2 * Math.PI; duration: 700; loops: Animation.Infinite
  }

  // Annoyed: turns its head away with a huff.
  SequentialAnimation {
    running: face.run && face.look === "annoyed"
    loops: Animation.Infinite
    onStopped: { face.tiltDeg = 0; face.shakeX = 0 }
    NumberAnimation { target: face; property: "tiltDeg"; to: -12; duration: 200; easing.type: Easing.OutBack }
    NumberAnimation { target: face; property: "shakeX"; to: face.size * 0.05; duration: 50 }
    NumberAnimation { target: face; property: "shakeX"; to: -face.size * 0.05; duration: 70 }
    NumberAnimation { target: face; property: "shakeX"; to: 0; duration: 50 }
    PauseAnimation { duration: 4000 }
  }

  // ------------------------------------------------------------- pointer
  property int pokes: 0
  property int shakes: 0
  property real lastPX: 0
  property int lastDir: 0
  function react(kind) {
    if (reaction === "dizzy" && kind === "annoyed") return
    reaction = kind
    reactTimer.interval = kind === "dizzy" ? 2800 : 2200
    reactTimer.restart()
    squashAnim.restart()
  }
  Timer { id: reactTimer; onTriggered: face.reaction = "" }
  Timer { id: pokeReset; interval: 1300; onTriggered: face.pokes = 0 }
  Timer { id: shakeReset; interval: 900; onTriggered: face.shakes = 0 }

  HoverHandler {
    enabled: face.interactive && face.run
    margin: face.size * 1.2
    onHoveredChanged: if (!hovered) { face.gazeX = 0; face.gazeY = 0; face.lastDir = 0 }
    onPointChanged: {
      if (!hovered) return
      var p = point.position, c = face.size / 2, k = face.size * 0.1, n = face.size * 1.6
      face.gazeX = Math.max(-k, Math.min(k, (p.x - body.x - c) / n * k))
      face.gazeY = Math.max(-k * 0.7, Math.min(k * 0.7, (p.y - body.y - c) / n * k))
      // Count direction reversals of a fast back-and-forth: that's shaking it.
      var dx = p.x - face.lastPX
      if (Math.abs(dx) > face.size * 0.12) {
        var dir = dx > 0 ? 1 : -1
        if (face.lastDir && dir !== face.lastDir) {
          face.shakes++
          shakeReset.restart()
          if (face.shakes >= 6) { face.shakes = 0; face.react("dizzy") }
        }
        face.lastDir = dir
        face.lastPX = p.x
      }
    }
  }
  TapHandler {
    enabled: face.interactive && face.run
    onTapped: {
      face.pokes++
      pokeReset.restart()
      pokeAnim.restart()
      if (face.pokes >= 6) { face.pokes = 0; face.react("dizzy") }
      else if (face.pokes >= 3) face.react("annoyed")
    }
  }
  // A poke: quick squish and a blink.
  SequentialAnimation {
    id: pokeAnim
    ParallelAnimation {
      NumberAnimation { target: face; property: "squashX"; to: 1.14; duration: 70 }
      NumberAnimation { target: face; property: "squashY"; to: 0.84; duration: 70 }
      NumberAnimation { target: face; property: "eyeOpen"; to: 0.1; duration: 70 }
    }
    ParallelAnimation {
      NumberAnimation { target: face; property: "squashX"; to: 1; duration: 320; easing.type: Easing.OutElastic }
      NumberAnimation { target: face; property: "squashY"; to: 1; duration: 320; easing.type: Easing.OutElastic }
      NumberAnimation { target: face; property: "eyeOpen"; to: 1; duration: 160 }
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

  // Cat: tail swishes while working / celebrating.
  SequentialAnimation {
    running: face.run && (face.cat || face.dog) && !face.mini && (face.look === "working" || face.look === "done")
    loops: Animation.Infinite
    onStopped: face.tailWag = 0
    // Dogs wag fast and happy, cats swish slowly.
    NumberAnimation { target: face; property: "tailWag"; to: face.dog ? -22 : -18; duration: face.dog ? 130 : 380; easing.type: Easing.InOutSine }
    NumberAnimation { target: face; property: "tailWag"; to: face.dog ? 16 : 10; duration: face.dog ? 130 : 380; easing.type: Easing.InOutSine }
    PauseAnimation { duration: face.look === "done" ? 0 : 500 }
  }
  SequentialAnimation {
    id: earAnim
    NumberAnimation { target: face; property: "earFlick"; to: 18; duration: 70 }
    NumberAnimation { target: face; property: "earFlick"; to: 0; duration: 160; easing.type: Easing.OutBack }
  }

  // Blink every few seconds while awake.
  Timer {
    running: face.run && (face.look === "idle" || face.look === "thinking" || face.look === "working" || face.look === "waiting")
    repeat: true
    interval: 2800 + Math.random() * 1500
    onTriggered: {
      interval = 2200 + Math.random() * 3400
      blinkAnim.restart()
      if (face.animal && Math.random() < 0.35) earAnim.restart()
    }
  }
  SequentialAnimation {
    id: blinkAnim
    NumberAnimation { target: face; property: "eyeOpen"; to: 0.08; duration: 70 }
    NumberAnimation { target: face; property: "eyeOpen"; to: 1; duration: 120 }
  }
}
