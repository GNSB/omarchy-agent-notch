import QtQuick
import Quickshell
import Quickshell.Io

// The notch's full-size companion: conversations on the left, the open chat in
// the middle and a git inspector on the right that follows the repo the chat
// works in. A second tab holds the repo browser and a file checksum tool.
//
// It reads everything through `n` (the Notch root): agents, transcripts, the
// draft's attachments and agent/model/folder picks are shared with the notch.
Scope {
  id: cw

  property var n: null
  property bool open: false
  signal closeRequested()

  property string selected: ""          // chat key; "" = new chat
  property int tab: 0                   // 0 chat · 1 git & checksum
  property bool inspector: true
  property bool dirMenu: false

  readonly property string font: n ? n.fontFamily : "Noto Sans"
  readonly property color accent: n ? n.claudeColor : "#E0784F"
  readonly property color card: n ? n.cardColor : "#18181B"
  readonly property string tools: n ? n.toolsBin : ""

  // Every agent on the board, newest first; only reassigned when it changes
  // so the list's faces aren't rebuilt every second.
  property var rows: []
  function rebuild() {
    if (!n) return
    var out = []
    for (var i = 0; i < n.agentList.count; i++) {
      var d = n.snapshot(n.agentList.get(i).key)
      if (d) { d.prev = ""; out.push(d) }
    }
    out.sort(function (a, b) { return b.updated - a.updated })
    rows = n.same(rows, out)
  }
  Timer { interval: 1000; repeat: true; running: win.visible; triggeredOnStart: true; onTriggered: cw.rebuild() }
  readonly property var current: {
    for (var i = 0; i < rows.length; i++) if (rows[i].key === selected) return rows[i]
    return null
  }
  readonly property string currentMood: current ? n.moodFor(current.state, current.updated) : "idle"
  readonly property bool busy: ["working", "thinking", "upload", "restart"].indexOf(currentMood) >= 0
  readonly property string chatDir: current ? (current.cwd || "~") : (n ? n.askDir : "~")

  function short(p) { return n ? String(p || "").replace(n.home, "~") : p }
  function clean(s) { return n ? n.dropSpoken(s) : String(s || "") }
  // "[attached image: …]" lines → thumbnails; the rest is the message.
  function images(q) {
    return String(q || "").split("\n").filter(function (l) { return /^\[attached image: .*\]$/.test(l) })
      .map(function (l) { return l.slice(17, -1) })
  }
  function bodyOf(q) {
    return String(q || "").split("\n").filter(function (l) { return !/^\[attached image: .*\]$/.test(l) }).join("\n").trim()
  }

  // ------------------------------------------------------------ transcript
  property var turns: []
  FileView {
    id: chatFile
    path: cw.n && cw.selected !== "" && cw.selected.indexOf("demo") < 0
      ? cw.n.home + "/.local/state/myzk-agents/chats/" + cw.selected.split(":").join("-").split("/").join("_") + ".json"
      : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { cw.turns = JSON.parse(text()) || [] } catch (e) { cw.turns = [] } }
    onLoadFailed: cw.turns = []
  }
  onSelectedChanged: { if (selected === "") turns = []; pendingPrompt = ""; follow() }

  // ------------------------------------------------------------ git model
  property var git: ({})               // agent-notch-tools git DIR
  property var remotes: []
  property var related: []
  property var repos: []
  property string asked: ""
  property bool gitBusy: false
  property real gitAt: 0
  property int ticks: 0

  function focusRepo(dir) {
    var d = String(dir || "~")
    if (d === cw.asked && cw.git.root) return
    cw.asked = d
    cw.refreshGit(false)
  }
  function refreshGit(silent) {
    if (cw.asked === "") return
    if (!silent) cw.gitBusy = true
    gitProc.command = [cw.tools, "git", cw.asked]
    gitProc.running = false
    gitProc.running = true
  }
  // Points the inspector at the open chat: its cwd if that's a repo, else the
  // repo its transcript touched the most.
  function follow() {
    if (!cw.n) return
    var d = cw.current
    if (!d) { cw.related = []; cw.focusRepo(cw.chatDir); return }
    followProc.command = [cw.tools, "follow", d.cwd || "~", "--id", d.ident, "--id", d.session || d.ident]
    followProc.running = false
    followProc.running = true
  }

  Process {
    id: gitProc
    stdout: StdioCollector {
      onStreamFinished: {
        var g = {}
        try { g = JSON.parse(text) || {} } catch (e) { }
        var newRoot = g.root !== cw.git.root
        cw.git = g
        cw.gitBusy = false
        cw.gitAt = Date.now() / 1000
        if (newRoot) cw.remotes = (g.remotes || []).map(function (r) { return { name: r.name, url: r.url, ok: null, note: "…" } })
        if (g.root && (newRoot || cw.ticks % 20 === 0)) { remotesProc.running = false; remotesProc.command = [cw.tools, "remotes", g.root]; remotesProc.running = true }
      }
    }
  }
  Process {
    id: remotesProc
    stdout: StdioCollector { onStreamFinished: { try { cw.remotes = JSON.parse(text) || [] } catch (e) { } } }
  }
  Process {
    id: followProc
    stdout: StdioCollector {
      onStreamFinished: {
        var f = {}
        try { f = JSON.parse(text) || {} } catch (e) { }
        cw.related = f.related || []
        cw.focusRepo(f.root || cw.chatDir)
      }
    }
  }
  Process {
    id: reposProc
    stdout: StdioCollector { onStreamFinished: { try { cw.repos = JSON.parse(text) || [] } catch (e) { } } }
  }
  // Live while the window is on screen: status every 3 s, remotes every minute.
  Timer {
    interval: 3000
    repeat: true
    running: win.visible && !!cw.git.root
    onTriggered: { cw.ticks++; if (!gitProc.running) cw.refreshGit(true) }
  }

  // ------------------------------------------------------------ checksum
  property string sumFile: ""
  property var sums: []
  property string sumError: ""
  Process {
    id: sumProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var r = JSON.parse(text)
          if (r.file === cw.sumFile.replace(/^~/, cw.n.home) || r.file === cw.sumFile) { cw.sums = r.sums || []; cw.sumError = r.error || "" }
        } catch (e) { }
      }
    }
  }
  function checksum(path) {
    cw.sumFile = String(path || "").trim()
    cw.sums = []
    cw.sumError = ""
    if (cw.sumFile === "") return
    sumProc.running = false
    sumProc.command = [cw.tools, "checksum", cw.sumFile]
    sumProc.running = true
  }
  Process {
    id: pickProc
    command: ["zenity", "--file-selection", "--title=Checksum"]
    stdout: StdioCollector { onStreamFinished: { var p = String(text).trim(); if (p) { sumPath.text = p; cw.checksum(p) } } }
  }

  onOpenChanged: if (open && n) {
    n.loadDirs()
    n.rescan()
    reposProc.command = [cw.tools, "repos"].concat(n.projectDirs)
    reposProc.running = true
    follow()
    focusLater.restart()
  }
  Timer { id: focusLater; interval: 120; onTriggered: composerEdit.forceActiveFocus() }

  // The backend echoes the sent prompt back as `task`, clipped to 90 chars for the
  // sidebar/notch labels. Keep the full text here so the chat bubble doesn't show
  // that clipped version while the reply is still in flight.
  property string pendingPrompt: ""

  function submit() {
    var t = composerEdit.text
    if (t.trim() === "" && cw.n.attachments.length === 0) return
    if (cw.current) {
      if (cw.n.replyTo(cw.current, t)) { cw.pendingPrompt = t; composerEdit.text = "" }
    } else {
      var k = cw.n.startChat(t, cw.n.askAgent, cw.n.askDir)
      if (k !== "") { composerEdit.text = ""; cw.selected = k; cw.pendingPrompt = t }
    }
  }

  // ------------------------------------------------------------ pieces
  component Pill: Rectangle {
    id: pl
    property string label: ""
    property bool on: false
    property color tone: cw.accent
    property bool clickable: true
    signal picked()
    height: 26
    width: plLbl.implicitWidth + 20
    radius: 13
    color: on ? Qt.alpha(tone, 0.24) : plMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
    border.width: 1
    border.color: on ? Qt.alpha(tone, 0.7) : "transparent"
    Behavior on color { ColorAnimation { duration: 150 } }
    Text {
      id: plLbl
      anchors.centerIn: parent
      text: pl.label
      color: pl.on ? Qt.lighter(pl.tone, 1.25) : "#AEB3BC"
      font.family: cw.font
      font.pixelSize: 11
      font.weight: Font.Medium
    }
    MouseArea {
      id: plMouse
      anchors.fill: parent
      enabled: pl.clickable
      hoverEnabled: pl.clickable
      cursorShape: pl.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: pl.picked()
    }
  }

  component Card: Rectangle {
    id: cd
    property string title: ""
    default property alias content: cdCol.data
    width: parent ? parent.width : 300
    height: cdCol.implicitHeight + 28
    radius: 18
    color: Qt.rgba(1, 1, 1, 0.04)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.06)
    Column {
      id: cdCol
      x: 14; y: 14
      width: parent.width - 28
      spacing: 8
      Text {
        text: cd.title.toUpperCase()
        color: "#7C7F88"
        font.family: cw.font
        font.pixelSize: 10
        font.weight: Font.Bold
        font.letterSpacing: 0.8
      }
    }
  }

  component Label: Text {
    color: "#C9CDD4"
    font.family: cw.font
    font.pixelSize: 12
    elide: Text.ElideRight
  }

  // Branch / changes / connections / history for the focused repo.
  component GitPanel: Column {
    id: gp
    property int commitLimit: 8
    spacing: 10
    readonly property var g: cw.git

    Card {
      visible: !gp.g.root
      title: "Git"
      Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: cw.gitBusy ? cw.n.tr("git.looking") : cw.n.tr("git.notRepo", { dir: cw.short(cw.asked) })
        color: "#8A8D96"
      }
    }

    Card {
      visible: !!gp.g.root
      title: cw.n.tr("git.repo")
      Item {
        width: parent.width
        height: 24
        Label {
          anchors.left: parent.left
          anchors.right: reload.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: cw.short(gp.g.root)
          elide: Text.ElideMiddle
          color: "#F2F3F5"
          font.weight: Font.DemiBold
        }
        Rectangle {
          id: reload
          anchors.right: parent.right
          width: 24; height: 24; radius: 12
          color: rlMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
          Text {
            anchors.centerIn: parent
            text: "⟳"; color: "#E4E6EA"; font.pixelSize: 13
            RotationAnimation on rotation { running: cw.gitBusy; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
          }
          MouseArea { id: rlMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cw.refreshGit(false) }
        }
      }
      Label {
        visible: cw.gitAt > 0
        text: cw.n.tr("git.live", { s: Math.max(0, Math.floor(cw.n.now - cw.gitAt)) })
        color: "#6B7280"
        font.pixelSize: 10
      }
      Flow {
        width: parent.width
        spacing: 6
        Pill { label: "⑂ " + (gp.g.branch || "?"); on: true; clickable: false }
        Pill { visible: !!gp.g.head; label: "# " + gp.g.head; clickable: false }
        Pill { visible: !!gp.g.sync; label: "⇅ " + gp.g.sync; on: true; tone: "#F5B544"; clickable: false }
      }
      Label { visible: !!gp.g.tracking; text: cw.n.tr("git.tracks", { b: gp.g.tracking }); color: "#8A8D96"; font.pixelSize: 11 }
    }

    Card {
      visible: !!gp.g.root
      readonly property var files: gp.g.files || []
      title: files.length === 0 ? cw.n.tr("git.tree") : cw.n.tr("git.changes") + " · " + files.length
      Label { visible: parent.parent.files.length === 0; text: "✓  " + cw.n.tr("git.clean"); color: "#3DD68C" }
      Repeater {
        model: (gp.g.files || []).slice(0, gp.commitLimit + 4)
        Row {
          required property var modelData
          spacing: 8
          readonly property color tone: modelData.code.indexOf("?") >= 0 ? "#8B93A1" : modelData.code.indexOf("D") >= 0 ? "#FF6B6B"
            : modelData.code.indexOf("A") >= 0 ? "#3DD68C" : "#F5B544"
          Rectangle {
            width: 24; height: 16; radius: 4
            color: Qt.alpha(parent.tone, 0.2)
            Text { anchors.centerIn: parent; text: modelData.code; color: parent.parent.tone; font.family: "monospace"; font.pixelSize: 10; font.bold: true }
          }
          Label { width: gp.width - 28 - 24 - 8 - 4; text: modelData.path; font.family: "monospace"; font.pixelSize: 11; elide: Text.ElideMiddle }
        }
      }
      Label {
        visible: (gp.g.files || []).length > gp.commitLimit + 4
        text: "+ " + ((gp.g.files || []).length - gp.commitLimit - 4) + " " + cw.n.tr("git.more")
        color: "#8A8D96"; font.pixelSize: 11
      }
    }

    Card {
      visible: !!gp.g.root
      title: cw.n.tr("git.remotes")
      Label { visible: cw.remotes.length === 0; text: cw.n.tr("git.noRemotes"); color: "#8A8D96" }
      Repeater {
        model: cw.remotes
        Column {
          required property var modelData
          width: gp.width - 28
          spacing: 2
          Item {
            width: parent.width
            height: 16
            Rectangle {
              id: rdot
              anchors.verticalCenter: parent.verticalCenter
              width: 7; height: 7; radius: 3.5
              color: modelData.ok === null || modelData.ok === undefined ? "#F5B544" : modelData.ok ? "#3DD68C" : "#FF6B6B"
            }
            Label { anchors.left: rdot.right; anchors.leftMargin: 7; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: "#F2F3F5"; font.weight: Font.DemiBold }
            Label {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width * 0.55
              horizontalAlignment: Text.AlignRight
              text: modelData.ok === true ? cw.n.tr("git.connected") : (modelData.note || "")
              color: modelData.ok === false ? "#FF6B6B" : "#8A8D96"
              font.pixelSize: 10
            }
          }
          Label { width: parent.width; text: modelData.url; font.family: "monospace"; font.pixelSize: 10; color: "#7C7F88"; elide: Text.ElideMiddle }
        }
      }
    }

    Card {
      visible: !!gp.g.root
      title: cw.n.tr("git.history")
      Repeater {
        model: (gp.g.commits || []).slice(0, gp.commitLimit)
        Row {
          required property var modelData
          spacing: 8
          Text { text: modelData.hash; color: cw.accent; font.family: "monospace"; font.pixelSize: 10; topPadding: 2 }
          Column {
            width: gp.width - 28 - 60
            spacing: 1
            Label { width: parent.width; text: modelData.subject; wrapMode: Text.Wrap; maximumLineCount: 2 }
            Label { width: parent.width; text: modelData.author + " · " + modelData.date; color: "#6B7280"; font.pixelSize: 10 }
          }
        }
      }
    }
  }

  // ================================================================ window
  FloatingWindow {
    id: win
    visible: cw.open
    title: "Agent Notch"
    color: "#0E0E11"
    implicitWidth: 1180
    implicitHeight: 740
    minimumSize: Qt.size(980, 600)
    onVisibleChanged: if (!visible && cw.open) cw.closeRequested()

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: cw.card }
        GradientStop { position: 1; color: "#0E0E11" }
      }
    }

    // ------------------------------------------------------------ sidebar
    Rectangle {
      id: sidebar
      width: 260
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      color: Qt.rgba(0, 0, 0, 0.35)

      Column {
        id: sideTop
        x: 14; y: 16
        width: parent.width - 28
        spacing: 12

        Rectangle {
          width: parent.width
          height: 40
          radius: 20
          color: cw.selected === "" ? Qt.alpha(cw.accent, 0.24) : ncMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.06)
          border.width: 1
          border.color: cw.selected === "" ? Qt.alpha(cw.accent, 0.7) : "transparent"
          Text {
            anchors.verticalCenter: parent.verticalCenter
            x: 16
            text: "✎   " + cw.n.tr("client.newChat")
            color: cw.selected === "" ? Qt.lighter(cw.accent, 1.25) : "#E4E6EA"
            font.family: cw.font; font.pixelSize: 13; font.weight: Font.DemiBold
          }
          MouseArea { id: ncMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: { cw.selected = ""; cw.n.askModel = "auto"; cw.tab = 0; composerEdit.forceActiveFocus() } }
        }

        Text {
          leftPadding: 6
          text: cw.n.tr("client.conversations").toUpperCase()
          color: "#6B7280"; font.family: cw.font; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.8
        }
      }

      ListView {
        anchors.top: sideTop.bottom
        anchors.topMargin: 6
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 10
        clip: true
        spacing: 2
        model: cw.rows
        delegate: Rectangle {
          id: rowItem
          required property var modelData
          readonly property bool on: cw.selected === modelData.key
          readonly property string mood: cw.n.moodFor(modelData.state, modelData.updated)
          width: ListView.view.width
          height: 50
          radius: 14
          color: on ? Qt.rgba(1, 1, 1, 0.1) : rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
          AgentFace {
            id: rowFace
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            mini: true
            size: 22
            interactive: false
            live: ["working", "thinking", "upload", "restart", "waiting"].indexOf(rowItem.mood) >= 0
            tint: cw.n.idColor(modelData.agent, modelData.ident)
            faceStyle: cw.n.faceStyleFor(modelData.agent)
            accessory: cw.n.accessoryFor(modelData.agent, modelData.ident)
            mood: rowItem.mood
          }
          Column {
            anchors.left: rowFace.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Label {
              width: parent.width
              text: modelData.task || cw.n.displayName(modelData.agent, modelData.name)
              color: "#F2F3F5"; font.weight: Font.DemiBold
            }
            Label {
              width: parent.width
              text: cw.short(modelData.cwd || "~") + " · " + cw.n.ago(modelData.updated)
              color: cw.n.stateColor[rowItem.mood] || "#8A8D96"; font.pixelSize: 10
            }
          }
          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function (ev) {
              if (ev.button === Qt.MiddleButton) { cw.n.forget(modelData.agent, modelData.ident); if (rowItem.on) cw.selected = ""; return }
              cw.selected = modelData.key; cw.tab = 0
            }
          }
        }
      }
    }

    Rectangle { x: sidebar.width; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.07) }

    // ------------------------------------------------------------ main
    Item {
      id: main
      x: sidebar.width + 1
      width: parent.width - x
      height: parent.height

      // tabs
      Item {
        id: topBar
        width: parent.width
        height: 56
        Row {
          x: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          Pill { label: "💬  " + cw.n.tr("client.chat"); on: cw.tab === 0; onPicked: cw.tab = 0 }
          Pill { label: "⑂  " + cw.n.tr("client.tools"); on: cw.tab === 1; onPicked: cw.tab = 1 }
        }
        Pill {
          visible: cw.tab === 0
          anchors.right: parent.right
          anchors.rightMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          label: cw.n.tr("client.inspector")
          on: cw.inspector
          onPicked: cw.inspector = !cw.inspector
        }
      }

      // ======================================================== chat tab
      Item {
        id: chatTab
        visible: cw.tab === 0
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        width: parent.width

        Item {
          id: chatArea
          width: parent.width - (cw.inspector ? inspectorPane.width + 1 : 0)
          height: parent.height

          // header of the open chat
          Item {
            id: chatHead
            visible: !!cw.current
            width: parent.width
            height: visible ? 40 : 0
            Row {
              x: 24
              anchors.verticalCenter: parent.verticalCenter
              spacing: 8
              Text {
                width: Math.min(implicitWidth, chatHead.width - 48 - headBtns.width - 110)
                elide: Text.ElideRight
                text: cw.current ? cw.n.displayName(cw.current.agent, cw.current.name) : ""
                color: "#F2F3F5"; font.family: cw.font; font.pixelSize: 14; font.weight: Font.DemiBold
              }
              Rectangle {
                visible: !!(cw.current && cw.current.model)
                anchors.verticalCenter: parent.verticalCenter
                height: 20; width: mbl.implicitWidth + 14; radius: 10
                color: cw.current && cw.current.route === "fallback" ? Qt.alpha("#F5A524", 0.2) : Qt.rgba(1, 1, 1, 0.08)
                Text {
                  id: mbl
                  anchors.centerIn: parent
                  text: cw.current && cw.current.model ? "⑂ " + cw.n.capitalize(cw.current.model) + (cw.current.route ? " · " + cw.n.routeLabel(cw.current.route) : "") : ""
                  color: cw.current && cw.current.route === "fallback" ? "#F5A524" : "#9AA0AA"
                  font.family: cw.font; font.pixelSize: 10; font.weight: Font.DemiBold
                }
              }
            }
            Row {
              id: headBtns
              anchors.right: parent.right
              anchors.rightMargin: 20
              anchors.verticalCenter: parent.verticalCenter
              spacing: 6
              Pill { label: "▸ " + cw.n.tr("client.terminal"); onPicked: cw.n.openTerminal(cw.current) }
              Pill {
                label: cw.n.tr("answer.close"); tone: "#FF6B6B"
                onPicked: { cw.n.forget(cw.current.agent, cw.current.ident); cw.selected = "" }
              }
            }
          }

          // welcome (new chat)
          Column {
            visible: !cw.current
            anchors.horizontalCenter: parent.horizontalCenter
            y: (composer.y - height) / 2
            spacing: 12
            AgentFace {
              anchors.horizontalCenter: parent.horizontalCenter
              size: 60
              glowAlways: true
              live: win.visible && !cw.current
              tint: cw.n.orbTint("claude", "")
              faceStyle: cw.n.faceStyleFor("claude")
              accessory: cw.n.accessoryFor("claude", "")
              mood: composerEdit.text.length > 0 ? "thinking" : "idle"
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: cw.n.tr("ask.placeholder", { name: cw.n.agentName(cw.n.askAgent) })
              color: "#F2F3F5"; font.family: cw.font; font.pixelSize: 22; font.weight: Font.DemiBold
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: cw.n.tr("client.workingIn", { dir: cw.n.askDir })
              color: "#7C7F88"; font.family: cw.font; font.pixelSize: 12
            }
          }

          // transcript
          Flickable {
            id: talk
            visible: !!cw.current
            anchors.top: chatHead.bottom
            anchors.bottom: composer.top
            width: parent.width
            contentHeight: talkCol.implicitHeight + 40
            clip: true
            onContentHeightChanged: if (contentHeight > height) contentY = contentHeight - height
            Column {
              id: talkCol
              x: 24; y: 16
              width: talk.width - 48
              spacing: 16

              Repeater {
                model: cw.turns
                Column {
                  required property var modelData
                  width: talkCol.width
                  spacing: 16
                  UserBubble { maxW: talkCol.width; q: modelData.q }
                  AgentBubble { maxW: talkCol.width; body: cw.clean(modelData.a); error: !!modelData.error }
                }
              }
              UserBubble { maxW: talkCol.width; visible: cw.busy && !!cw.current && !!cw.current.task; q: cw.pendingPrompt || (cw.current ? cw.current.task : "") }
              AgentBubble {
                maxW: talkCol.width
                visible: cw.busy
                live: true
                body: "_" + cw.n.tr("answer.busy", { name: cw.current ? cw.n.agentName(cw.current.agent) : "" }) + "_  "
                  + (cw.current ? cw.current.detail || "" : "")
                dim: true
              }
              // sessions from before transcripts existed, or terminal sessions: last turn only
              UserBubble { maxW: talkCol.width; visible: !cw.busy && cw.turns.length === 0 && !!cw.current && !!cw.current.task; q: cw.current ? cw.current.task : "" }
              AgentBubble {
                maxW: talkCol.width
                visible: !cw.busy && cw.turns.length === 0 && !!cw.current
                body: !cw.current ? "" : cw.current.answer ? cw.clean(cw.current.answer) : (cw.current.detail || cw.n.tr("client.noAnswer"))
                dim: !!cw.current && !cw.current.answer
              }
            }
          }

          // composer
          Item {
            id: composer
            anchors.bottom: parent.bottom
            width: parent.width
            height: terminalOnly ? 76 : composerCol.implicitHeight + 28
            readonly property bool terminalOnly: !!cw.current && cw.current.source !== "notch"

            // Terminal sessions belong to their terminal: resuming them headless
            // here would run a second process on the same conversation.
            Rectangle {
              visible: composer.terminalOnly
              x: 20; y: 8
              width: parent.width - 40
              height: 56
              radius: 20
              color: Qt.rgba(1, 1, 1, 0.06)
              Text {
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                text: "▸  " + cw.n.tr("client.termOnly")
                color: "#8A8D96"; font.family: cw.font; font.pixelSize: 12
              }
              Row {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Pill { label: cw.n.tr("client.openTerminal"); onPicked: cw.n.openTerminal(cw.current) }
                Pill {
                  label: cw.n.tr("client.newHere"); on: true
                  onPicked: {
                    var i = cw.n.askDirs.indexOf(cw.short(cw.current.cwd))
                    if (i >= 0) cw.n.askDirIndex = i
                    cw.selected = ""
                    composerEdit.forceActiveFocus()
                  }
                }
              }
            }

            Column {
              id: composerCol
              visible: !composer.terminalOnly
              x: 20; y: 6
              width: parent.width - 40
              spacing: 8

              // attachments
              Flow {
                width: parent.width
                spacing: 8
                visible: cw.n.attachments.length > 0
                Repeater {
                  model: cw.n.attachments
                  Item {
                    required property string modelData
                    width: 54; height: 54
                    Rectangle {
                      anchors.fill: parent; radius: 10; clip: true
                      color: Qt.rgba(1, 1, 1, 0.06); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.15)
                      Image { anchors.fill: parent; anchors.margins: 1; source: "file://" + modelData; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 108 }
                    }
                    Rectangle {
                      x: parent.width - 11; y: -5; width: 16; height: 16; radius: 8; color: Qt.rgba(0, 0, 0, 0.85)
                      Text { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 8 }
                      MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor
                        onClicked: cw.n.attachments = cw.n.attachments.filter(function (p) { return p !== modelData }) }
                    }
                  }
                }
              }

              // pickers
              Flow {
                width: parent.width
                spacing: 5
                Repeater {
                  model: cw.current ? [] : cw.n.chatAgents
                  Pill {
                    required property var modelData
                    label: modelData.name
                    on: cw.n.askAgent === modelData.id
                    onPicked: cw.n.askAgent = modelData.id
                  }
                }
                Pill {
                  visible: !cw.current
                  label: "📁  " + cw.n.askDir + "  ▾"
                  tone: "#8B93A1"
                  on: cw.dirMenu
                  onPicked: cw.dirMenu = !cw.dirMenu
                }
              }
              Flow {
                width: parent.width
                spacing: 5
                Repeater {
                  model: cw.n.modelChoices(cw.current ? cw.current.agent : cw.n.askAgent)
                  Pill {
                    required property string modelData
                    label: modelData === "auto" ? "Auto" : cw.n.capitalize(modelData)
                    tone: "#8B93A1"
                    on: (cw.current ? cw.n.chatModel(cw.current.key) : cw.n.askModel) === modelData
                    onPicked: { if (cw.current) cw.n.setChatModel(cw.current.key, modelData); else cw.n.askModel = modelData }
                  }
                }
              }

              Rectangle {
                width: parent.width
                height: Math.max(48, composerFlick.height + 22)
                radius: 24
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: composerEdit.activeFocus ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.06)

                Flickable {
                  id: composerFlick
                  x: 18
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 18 - 52
                  height: Math.max(20, Math.min(composerEdit.contentHeight, 140))
                  contentHeight: composerEdit.contentHeight
                  clip: true
                  interactive: contentHeight > height
                  TextEdit {
                    id: composerEdit
                    width: composerFlick.width
                    wrapMode: TextEdit.Wrap
                    color: "#F2F3F5"
                    selectionColor: "#3B8BFF"
                    selectedTextColor: "white"
                    font.family: cw.font
                    font.pixelSize: 14
                    enabled: !(cw.busy && cw.current)
                    onCursorRectangleChanged: {
                      if (cursorRectangle.y + cursorRectangle.height > composerFlick.contentY + composerFlick.height)
                        composerFlick.contentY = cursorRectangle.y + cursorRectangle.height - composerFlick.height
                    }
                    Keys.onPressed: function (event) {
                      if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) { cw.n.pasteInto(composerEdit); event.accepted = true }
                      else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) { cw.submit(); event.accepted = true }
                      else if (event.key === Qt.Key_Escape) { cw.dirMenu = false; event.accepted = true }
                    }
                  }
                  Text {
                    visible: composerEdit.text.length === 0
                    text: cw.busy && cw.current ? cw.n.tr("answer.busy", { name: cw.n.agentName(cw.current.agent) })
                      : cw.current ? cw.n.tr("answer.reply", { name: cw.n.agentName(cw.current.agent) }) : cw.n.tr("client.message")
                    color: "#6E717A"; font.family: cw.font; font.pixelSize: 14
                  }
                }

                Rectangle {
                  id: sendBtn
                  readonly property bool ready: (composerEdit.text.trim().length > 0 || cw.n.attachments.length > 0) && !(cw.busy && cw.current)
                  anchors.right: parent.right
                  anchors.rightMargin: 8
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: 7
                  width: 34; height: 34; radius: 17
                  color: ready ? "#F4F4F5" : Qt.rgba(1, 1, 1, 0.12)
                  scale: sendMouse.pressed ? 0.88 : 1
                  Behavior on color { ColorAnimation { duration: 160 } }
                  Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                  Text { anchors.centerIn: parent; text: "↑"; color: sendBtn.ready ? "#111113" : "#8A8D96"; font.pixelSize: 17; font.bold: true }
                  MouseArea { id: sendMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cw.submit() }
                }
              }
              Text {
                width: parent.width
                elide: Text.ElideRight
                text: cw.n.tr("client.hint")
                color: "#5B5E66"; font.family: cw.font; font.pixelSize: 10
              }
            }
          }

          // folder menu
          Rectangle {
            visible: cw.dirMenu && !cw.current
            x: 20
            anchors.bottom: composer.top
            anchors.bottomMargin: 4
            width: 320
            height: Math.min(dirList.contentHeight + 16, 320)
            radius: 18
            color: cw.card
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.1)
            z: 10
            ListView {
              id: dirList
              anchors.fill: parent
              anchors.margins: 8
              clip: true
              model: cw.n.askDirs
              delegate: Rectangle {
                required property string modelData
                required property int index
                width: ListView.view.width
                height: 30
                radius: 10
                color: index === cw.n.askDirIndex ? Qt.alpha(cw.accent, 0.22) : dMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                Label { x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 24; text: modelData }
                MouseArea { id: dMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: { cw.n.askDirIndex = index; cw.dirMenu = false; cw.follow(); composerEdit.forceActiveFocus() } }
              }
            }
          }
        }

        // git inspector
        Rectangle {
          id: inspectorPane
          visible: cw.inspector
          anchors.right: parent.right
          width: 320
          height: parent.height
          color: Qt.rgba(0, 0, 0, 0.18)
          Rectangle { width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.07) }
          Flickable {
            anchors.fill: parent
            anchors.margins: 14
            contentHeight: inspCol.implicitHeight
            clip: true
            Column {
              id: inspCol
              width: parent.width
              spacing: 10
              Flow {
                width: parent.width
                spacing: 5
                visible: cw.related.length > 1 || (cw.related.length > 0 && !!cw.git.root && cw.short(cw.git.root) !== cw.related[0])
                Text {
                  width: parent.width
                  text: cw.n.tr("git.related", { n: cw.related.length })
                  color: "#7C7F88"; font.family: cw.font; font.pixelSize: 10; font.weight: Font.Bold
                }
                Repeater {
                  model: cw.related
                  Pill {
                    required property string modelData
                    label: modelData.split("/").pop()
                    on: cw.short(cw.git.root) === modelData
                    onPicked: cw.focusRepo(modelData)
                  }
                }
              }
              GitPanel { width: parent.width }
            }
          }
        }
      }

      // ======================================================== tools tab
      Flickable {
        visible: cw.tab === 1
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: toolsRow.implicitHeight + 40
        clip: true
        Row {
          id: toolsRow
          x: 20; y: 4
          spacing: 16
          Column {
            width: main.width - 40 - 16 - 360
            spacing: 10
            Card {
              title: cw.n.tr("git.repo")
              Flow {
                width: parent.width
                spacing: 5
                Repeater {
                  model: cw.repos
                  Pill {
                    required property string modelData
                    label: modelData.split("/").pop()
                    on: cw.short(cw.git.root) === modelData
                    onPicked: cw.focusRepo(modelData)
                  }
                }
              }
            }
            GitPanel { width: parent.width; commitLimit: 40 }
          }
          Column {
            width: 360
            spacing: 10
            Card {
              title: "Checksum"
              Rectangle {
                width: parent.width
                height: 34
                radius: 17
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: sumPath.activeFocus ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                TextInput {
                  id: sumPath
                  x: 14
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 28
                  clip: true
                  color: "#F2F3F5"; font.family: cw.font; font.pixelSize: 12
                  selectionColor: "#3B8BFF"
                  onAccepted: cw.checksum(text)
                }
                Text {
                  x: 14
                  anchors.verticalCenter: parent.verticalCenter
                  visible: sumPath.text.length === 0
                  text: cw.n.tr("sum.path")
                  color: "#6E717A"; font.family: cw.font; font.pixelSize: 12
                }
              }
              Row {
                spacing: 6
                Pill { label: "📄  " + cw.n.tr("sum.choose"); onPicked: { pickProc.running = false; pickProc.running = true } }
                Pill { label: cw.n.tr("sum.compute"); on: true; onPicked: cw.checksum(sumPath.text) }
              }
              Label { visible: cw.sumError !== ""; width: parent.width; wrapMode: Text.Wrap; text: cw.sumError; color: "#FF6B6B" }
              Repeater {
                model: cw.sums
                Column {
                  required property var modelData
                  width: parent.width
                  spacing: 1
                  Text { text: modelData.algo; color: "#8A8D96"; font.family: cw.font; font.pixelSize: 10; font.weight: Font.DemiBold }
                  TextEdit {
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    text: modelData.value
                    color: "#E4E6EA"; font.family: "monospace"; font.pixelSize: 10
                    selectionColor: "#3B8BFF"
                  }
                }
              }
              Rectangle {
                visible: cw.sums.length > 0
                width: parent.width
                height: 34
                radius: 17
                color: Qt.rgba(1, 1, 1, 0.06)
                TextInput {
                  id: expected
                  x: 14
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 28
                  clip: true
                  color: "#F2F3F5"; font.family: "monospace"; font.pixelSize: 11
                  selectionColor: "#3B8BFF"
                }
                Text {
                  x: 14
                  anchors.verticalCenter: parent.verticalCenter
                  visible: expected.text.length === 0
                  text: cw.n.tr("sum.expected")
                  color: "#6E717A"; font.family: cw.font; font.pixelSize: 12
                }
              }
              Text {
                readonly property string e: expected.text.trim().toLowerCase()
                readonly property bool ok: cw.sums.some(function (s) { return s.value === e })
                visible: cw.sums.length > 0 && e !== ""
                text: ok ? "✓  " + cw.n.tr("sum.match") : "✕  " + cw.n.tr("sum.nomatch")
                color: ok ? "#3DD68C" : "#FF6B6B"
                font.family: cw.font; font.pixelSize: 12; font.weight: Font.DemiBold
              }
            }
          }
        }
      }
    }
  }

  // Chat bubbles -------------------------------------------------------
  component UserBubble: Item {
    id: ubb
    property string q: ""
    property real maxW: 600
    readonly property var imgs: cw.images(q)
    readonly property string body: cw.bodyOf(q)
    width: maxW
    height: visible ? ubCol.implicitHeight : 0
    Column {
      id: ubCol
      anchors.right: parent.right
      spacing: 8
      Row {
        anchors.right: parent.right
        spacing: 6
        visible: ubb.imgs.length > 0
        Repeater {
          model: ubb.imgs
          Rectangle {
            required property string modelData
            width: 72; height: 72; radius: 10; clip: true
            color: Qt.rgba(1, 1, 1, 0.06)
            Image { anchors.fill: parent; source: "file://" + modelData; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 144 }
          }
        }
      }
      Rectangle {
        anchors.right: parent.right
        visible: ubb.body !== ""
        width: Math.min(ubMeasure.implicitWidth + 2, ubb.maxW * 0.72) + 28
        height: ubText.height + 20
        radius: 18
        color: Qt.alpha(cw.accent, 0.22)
        Text { id: ubMeasure; visible: false; text: ubb.body; font.family: cw.font; font.pixelSize: 13 }
        TextEdit {
          id: ubText
          x: 14; y: 10
          width: parent.width - 28
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          text: ubb.body
          color: "#F2F3F5"; font.family: cw.font; font.pixelSize: 13
          selectionColor: "#3B8BFF"
        }
      }
    }
  }

  component AgentBubble: Item {
    id: abb
    property string body: ""
    property bool error: false
    property bool dim: false
    property bool live: false
    property real maxW: 600
    width: maxW
    height: visible ? Math.max(30, abText.height + 20) : 0
    AgentFace {
      id: abFace
      size: 24
      mini: true
      interactive: false
      live: abb.live && abb.visible
      tint: cw.current ? cw.n.orbTint(cw.current.agent, cw.current.ident) : "#E4ECF5"
      faceStyle: cw.n.faceStyleFor(cw.current ? cw.current.agent : "claude")
      accessory: cw.n.accessoryFor(cw.current ? cw.current.agent : "claude", cw.current ? cw.current.ident : "")
      mood: abb.live ? cw.currentMood : abb.error ? "error" : "idle"
    }
    Rectangle {
      x: 36
      width: abb.maxW - 36 - 40
      height: abText.height + 20
      radius: 18
      color: Qt.rgba(1, 1, 1, 0.06)
      TextEdit {
        id: abText
        x: 14; y: 10
        width: parent.width - 28
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.MarkdownText
        text: abb.body
        color: abb.error ? "#FF8A8A" : abb.dim ? "#8A8D96" : "#E4E6EA"
        font.family: cw.font
        font.pixelSize: 14
        selectionColor: "#3B8BFF"
        onLinkActivated: function (link) { Qt.openUrlExternally(link) }
      }
    }
  }
}
