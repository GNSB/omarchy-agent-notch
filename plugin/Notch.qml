import QtQuick
import QtQuick.Shapes
import QtQuick.Particles
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Grok-Bot-style notch hanging under the bar on the main screen.
//
//   collapsed  focused agent's orb on the left, the other agents as a 2×2
//              cluster of coloured faces on the right — no text
//   expanded   (hover / click) focus card with a step "carousel" + one chip
//              per agent; clicking a chip focuses it
//   alert      peeks open by itself when an agent needs you, finishes or
//              fails: tinted glow card + stacked faces; click to dismiss
//   custom     face customisation panel (style, head gear, colour) with a
//              live preview; writes straight to config.json
//
// Data: ~/.local/state/myzk-agents/summary.json, written by myzk-agents
// (Claude Code hooks + Grok Bots reporting via `myzk-agents set`).
Item {
  id: root

  // A toggle pill for the customisation panel, optionally with a tiny face.
  component OptPill: Rectangle {
    id: pill
    property bool on: false
    property string label: ""
    property bool face: false
    property string faceStyleName: "orb"
    property var gear: []
    property color faceTint: "#EEF2F7"
    signal picked()
    height: 30
    width: pillRow.implicitWidth + 22
    radius: 15
    color: on ? Qt.alpha(root.claudeColor, 0.22) : pillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
    border.width: 1
    border.color: on ? Qt.alpha(root.claudeColor, 0.8) : Qt.rgba(1, 1, 1, 0.05)
    Behavior on color { ColorAnimation { duration: 150 } }
    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: 7
      AgentFace {
        visible: pill.face
        anchors.verticalCenter: parent.verticalCenter
        size: 17
        mini: true
        interactive: false
        live: false
        tint: pill.faceTint
        faceStyle: pill.faceStyleName
        accessory: pill.gear
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pill.label
        color: pill.on ? "white" : "#C9CDD4"
        font.family: root.fontFamily
        font.pixelSize: 12
      }
    }
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.picked()
    }
  }

  // Compact pill for pickers (agent / model / folder) and badges.
  component MiniPill: Rectangle {
    id: mp
    property bool on: false
    property string label: ""
    property color tone: root.claudeColor
    property bool clickable: true
    signal picked()
    height: 24
    width: mpLbl.implicitWidth + 18
    radius: 12
    color: on ? Qt.alpha(tone, 0.24) : mpMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
    border.width: 1
    border.color: on ? Qt.alpha(tone, 0.7) : "transparent"
    Behavior on color { ColorAnimation { duration: 150 } }
    Text {
      id: mpLbl
      anchors.centerIn: parent
      text: mp.label
      color: mp.on ? Qt.lighter(mp.tone, 1.25) : "#AEB3BC"
      font.family: root.fontFamily
      font.pixelSize: 11
      font.weight: Font.Medium
    }
    MouseArea {
      id: mpMouse
      anchors.fill: parent
      enabled: mp.clickable
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: mp.picked()
    }
  }

  // Which model ran a chat and how it was picked: "Sonnet · auto", amber on "fallback".
  component ModelBadge: Rectangle {
    id: mb
    property var d: null
    readonly property bool bad: !!(d && d.route === "fallback")
    visible: !!(d && d.model)
    height: 20
    width: mbLbl.implicitWidth + 14
    radius: 10
    color: bad ? Qt.alpha("#F5A524", 0.2) : Qt.rgba(1, 1, 1, 0.08)
    Text {
      id: mbLbl
      anchors.centerIn: parent
      text: mb.d && mb.d.model ? (mb.bad ? "⚠ " : "⑂ ") + root.capitalize(mb.d.model) + (mb.d.route ? " · " + root.routeLabel(mb.d.route) : "") : ""
      color: mb.bad ? "#F5A524" : "#9AA0AA"
      font.family: root.fontFamily
      font.pixelSize: 10
      font.weight: Font.DemiBold
    }
  }

  // Quiet footer: context fill of the focused session as a hairline, the
  // month's tokens as a whisper. Amber from 70 %, red from 90 %. The month
  // only gets a bar when monthlyTokenBudget is set in config.json.
  component UsageBars: Column {
    id: ub
    readonly property var u: root.usage
    readonly property bool hasSession: !!(u && u.session && u.session.pct !== null && u.session.pct !== undefined)
    readonly property bool hasMonth: !!(u && u.month && u.month.total > 0)
    visible: hasSession || hasMonth
    spacing: 5
    Repeater {
      model: [
        { show: ub.hasSession, label: root.tr("usage.session"),
          pct: ub.hasSession ? ub.u.session.pct : -1,
          trail: ub.hasSession ? root.fmtTokens(ub.u.session.tokens) + " · " + Math.round(ub.u.session.pct) + "%" : "" },
        { show: ub.hasMonth, label: root.tr("usage.month"),
          pct: ub.hasMonth && ub.u.month.budget > 0 && ub.u.month.pct !== null ? ub.u.month.pct : -1,
          trail: !ub.hasMonth ? "" : root.fmtTokens(ub.u.month.total)
            + (ub.u.month.budget > 0 && ub.u.month.pct !== null ? " · " + Math.round(ub.u.month.pct) + "%" : "") }
      ]
      Row {
        required property var modelData
        visible: modelData.show
        width: ub.width
        spacing: 8
        Text {
          width: 56
          text: modelData.label
          color: "#5E626B"
          font.family: root.fontFamily
          font.pixelSize: 10
        }
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 56 - 84 - 16
          height: 2
          radius: 1
          color: Qt.rgba(1, 1, 1, 0.06)
          Rectangle {
            visible: modelData.pct >= 0
            height: parent.height
            radius: 1
            width: Math.max(3, parent.width * Math.min(Math.max(modelData.pct / 100, 0), 1))
            color: modelData.pct >= 90 ? Qt.alpha("#FF6B6B", 0.85) : modelData.pct >= 70 ? Qt.alpha("#F5B544", 0.8) : Qt.rgba(1, 1, 1, 0.32)
            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
          }
        }
        Text {
          width: 84
          horizontalAlignment: Text.AlignRight
          text: modelData.trail
          color: "#5E626B"
          font.family: root.fontFamily
          font.pixelSize: 10
        }
      }
    }
  }

  // Pasted images as thumbnails; Ctrl+V again adds more, ✕ removes one.
  component AttachStrip: Flow {
    id: strip
    property real thumb: 44
    visible: root.attachments.length > 0
    spacing: 8
    Repeater {
      model: root.attachments
      Item {
        required property string modelData
        width: strip.thumb; height: strip.thumb
        Rectangle {
          anchors.fill: parent
          radius: 8
          color: Qt.rgba(1, 1, 1, 0.06)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.15)
          clip: true
          Image {
            anchors.fill: parent
            anchors.margins: 1
            source: "file://" + modelData
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: strip.thumb * 2
          }
        }
        Rectangle {
          x: parent.width - 11; y: -5
          width: 16; height: 16; radius: 8
          color: Qt.rgba(0, 0, 0, 0.85)
          Text { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 8 }
          MouseArea {
            anchors.fill: parent
            anchors.margins: -3
            cursorShape: Qt.PointingHandCursor
            onClicked: root.attachments = root.attachments.filter(function (p) { return p !== modelData })
          }
        }
      }
    }
    Text {
      height: strip.thumb
      verticalAlignment: Text.AlignVCenter
      text: root.attachments.length + " · " + root.tr("attach.more")
      color: "#6E717A"
      font.family: root.fontFamily
      font.pixelSize: 10
    }
  }

  // Injected by the shell host.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // ------------------------------------------------------------------ config
  // Settings live in ~/.config/agent-notch/config.json (live-reloaded);
  // UI text lives in i18n.json next to this file, overridable per key
  // through the config's "strings". See config.example.json.
  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: Quickshell.env("AGENT_NOTCH_CONFIG")
    || home + "/.config/agent-notch/config.json"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  property var cfg: ({})
  property var i18n: ({})
  function opt(key, fallback) { return cfg[key] !== undefined && cfg[key] !== null ? cfg[key] : fallback }
  // tr("alert.done", {who: "Claude"}) → config override, then language, then English.
  function tr(key, vars) {
    var strings = opt("strings", {})
    var lang = i18n[opt("language", "en")] || {}
    var t = strings[key] !== undefined ? strings[key]
      : lang[key] !== undefined ? lang[key] : ((i18n.en || {})[key] || key)
    t = String(t)
    if (vars) for (var k in vars) t = t.split("{" + k + "}").join(vars[k])
    return t.split("{name}").join(root.assistantName)
  }

  FileView {
    id: cfgFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.cfg = JSON.parse(text()) || {} }
      catch (e) { console.warn("agent-notch: bad config " + root.configPath + ": " + e); root.cfg = {} }
    }
    onLoadFailed: root.cfg = {}
  }
  FileView {
    path: root.pluginDir + "i18n.json"
    blockLoading: true
    printErrors: false
    onLoaded: { try { root.i18n = JSON.parse(text()) } catch (e) { root.i18n = {} } }
  }

  // ------------------------------------------------------------------ knobs
  // Defaults; override them in config.json rather than here.
  property string screenName: opt("screen", "")          // monitor name (hyprctl monitors); "" = first screen
  // "below": hangs under the bar (works with any layout).
  // "bar":   lives inside the bar like a Mac notch and only drops over
  //          windows when it opens — needs an empty bar center section.
  property string placement: opt("placement", "below")
  readonly property bool inBar: placement === "bar"
  property real topOffset: Style.bar.sizeHorizontal
  property int sleepAfter: opt("sleepAfter", 600)        // s idle before an orb dozes off
  property int doneGlow: opt("doneGlow", 90)             // s a finished agent stays happy
  property int alertMs: opt("alertMs", 7000)
  property int errorLoud: opt("errorLoud", 120)          // s an error keeps shaking before it settles
  property string fontFamily: opt("fontFamily", "Noto Sans")
  property color notchColor: opt("notchColor", "#000000")
  property color cardColor: opt("cardColor", "#18181B")
  property color claudeColor: opt("claudeColor", "#E0784F")
  property string assistantName: opt("assistantName", "Claude")
  property string grokName: opt("grokName", "Grok")
  property var projectDirs: opt("projectDirs", ["~/Projects/*"])
  property string terminalCmd: opt("terminal", "xdg-terminal-exec --app-id=org.omarchy.terminal")
  property string claudeCmd: opt("claudeCommand", "claude")
  property bool greetOnStart: opt("greetOnStart", true)
  // Face design: "orb", "cat", "dog" or "hamster". grokFaceStyle overrides it for Grok Bots.
  property string faceStyle: opt("faceStyle", "orb")
  property string grokFaceStyle: opt("grokFaceStyle", faceStyle)
  // Head gear: a name or list (hat, cowboy, crown, party, bow, headphones, helmet,
  // mask, glasses, shades). "accessories" maps a bot name to its own.
  property var accessory: opt("accessory", [])
  property var grokAccessory: opt("grokAccessory", accessory)
  property var accessories: opt("accessories", ({}))
  readonly property string backend: Quickshell.env("AGENT_NOTCH_BACKEND") || home + "/.local/bin/myzk-agents"
  readonly property string usageTool: home + "/.local/bin/claude-usage"
  readonly property string toolsBin: home + "/.local/bin/agent-notch-tools"
  // What tapping the pet in the focus card does: "chat" | "terminal" | "play".
  property string petTap: opt("petTap", "chat")

  readonly property int collapsedW: 300
  readonly property int collapsedH: inBar ? Style.bar.sizeHorizontal : 34
  readonly property int expandedW: 680
  readonly property int alertW: 600
  readonly property int greetW: 560
  readonly property int inputW: 640
  readonly property int answerW: 660
  readonly property int detectW: 640
  readonly property int alertH: 112
  readonly property int pad: 10

  // Grok Bots get the next unused colour as they first appear; Claude
  // sessions always wear Claude's terracotta.
  readonly property var palette: opt("palette", ["#35C2AE", "#8B6CF6", "#4C9AFF", "#EC6FB3", "#F2C94C",
    "#7ED957", "#F0544F", "#5AD1E6", "#C084FC", "#FF9F5A"])
  property var colorMap: ({})
  property int nextColor: 0
  readonly property var stateText: {
    var m = {}
    ;["idle", "thinking", "working", "upload", "restart", "waiting", "done", "error", "sleep", "errorStale"]
      .forEach(function (k) { m[k] = root.tr("state." + k) })
    return m
  }
  readonly property var stateColor: ({
    "idle": "#8B93A1", "thinking": "#A78BFA", "working": "#5B9DFF",
    "waiting": "#F5B544", "done": "#3DD68C", "error": "#FF6B6B", "sleep": "#6B7280",
    "errorStale": "#FF6B6B", "upload": "#3CC8E0", "restart": "#E879F9"
  })
  readonly property var rank: ({
    "waiting": 6, "error": 5, "errorStale": 1.5, "working": 4, "upload": 4, "restart": 3, "thinking": 3, "done": 2, "idle": 1, "sleep": 0
  })

  // ------------------------------------------------------------------ state
  // Demo mode (for recordings): read a separate board so real agents and
  // real Claude runs stay out of the video. See `demo` IPC.
  property bool demoMode: false
  readonly property string demoHome: home + "/.local/state/myzk-notch-demo"
  readonly property string stateFile: (demoMode ? demoHome : home + "/.local/state")
    + "/myzk-agents/summary.json"
  property real now: Date.now() / 1000
  property bool hovered: false
  property bool pinned: false
  property string pickedKey: ""          // chip the user clicked
  property string primaryKey: ""         // most relevant agent right now
  property string alertKey: ""
  property var hist: ({})                // key → previous step text
  property var lastStates: ({})
  property var clusterKeys: []          // top Grok Bots for the collapsed cluster
  property var grokOrder: []            // Grok keys in model order (stagger)
  property int count: 0
  property int claudeCount: 0
  property int grokCount: 0
  property int chatCount: 0             // assistant sessions + chats with other CLIs (not Grok Bots)
  property string grokMood: "idle"
  property string grokSummary: ""
  property bool grokOpen: false         // capsule unfolded
  property string mainClaudeKey: ""
  property var mainClaudeData: null

  readonly property string focusKey: pickedKey !== "" && indexOf(pickedKey) >= 0 ? pickedKey : primaryKey
  property var focusData: null
  property var alertData: null

  // Talking to the assistant from the notch.
  property bool inputOpen: false
  property string answerKey: ""
  property var answerData: null
  property var askDirs: ["~"]
  property int askDirIndex: 0
  readonly property string askDir: askDirs[askDirIndex] || "~"
  // Who answers the next new chat and with which model ("auto" = the router decides).
  property string askAgent: "claude"
  onAskAgentChanged: askModel = "auto"
  property string askModel: "auto"
  // Pasted images waiting to go out with the next message (shared with the client window).
  property var attachments: []
  // Closing the input keeps what you typed (and pasted); the orb wears a dot until you're back.
  readonly property bool hasDraft: attachments.length > 0 || promptEdit.text.trim().length > 0
  // A model picked for a chat sticks to it, across restarts: chat key → model.
  property var chatModels: ({})
  readonly property string chatModelsFile: (demoMode ? demoHome : home + "/.local/state") + "/myzk-agents/chat-models.json"

  // Coding agents installed on this machine (myzk-agents detect).
  property bool detectOpen: false
  property bool detecting: false
  property var detected: []
  // Every detected agent the notch can chat with; nothing hard-coded.
  readonly property var chatAgents: {
    var l = [{ id: "claude", name: root.assistantName }]
    for (var i = 0; i < detected.length; i++)
      if (detected[i].chat && detected[i].id !== "claude") l.push({ id: detected[i].id, name: detected[i].name })
    return l
  }
  function agentName(id) {
    for (var i = 0; i < chatAgents.length; i++) if (chatAgents[i].id === id) return chatAgents[i].name
    return id === "claude" ? root.assistantName : root.capitalize(id)
  }
  function modelChoices(agent) {
    for (var i = 0; i < detected.length; i++)
      if (detected[i].id === agent) return (detected[i].models || []).length ? ["auto"].concat(detected[i].models) : []
    return []
  }
  function chatModel(key) { return root.chatModels[key] || "auto" }
  function setChatModel(key, model) {
    var m = JSON.parse(JSON.stringify(root.chatModels))
    if (model === "auto") delete m[key]; else m[key] = model
    root.chatModels = m
    chatModelsView.setText(JSON.stringify(m, null, 2) + "\n")
  }
  function modelArgs(model) { return model && model !== "auto" ? ["--model", model] : [] }

  // Context of the focused session + tokens this month (claude-usage).
  property var usage: null
  property string usageKey: "-"
  property real usageStamp: 0

  property bool clientOpen: false

  // Greeting sequence (shell start / `greet` IPC).
  property bool greeting: false
  property real greetSpread: 0
  property real greetOrbScale: 0
  property bool greetWave: false
  property string greetMood: "sleep"

  // Customisation panel.
  property bool customOpen: false
  property string customTarget: "claude"      // claude | grok
  property int previewMoodIndex: 0
  readonly property int customW: 680
  readonly property var previewMoods: ["idle", "thinking", "working", "upload", "restart",
    "waiting", "done", "error", "sleep"]
  readonly property var gearNames: ["hat", "cowboy", "crown", "party", "helmet", "bow",
    "headphones", "mask", "glasses", "shades"]
  // One item per group: a single hat, a single thing over the eyes.
  readonly property var gearGroup: ({ "hat": "head", "cowboy": "head", "crown": "head", "party": "head",
    "helmet": "head", "mask": "eyes", "glasses": "eyes", "shades": "eyes" })
  function asList(v) { return Array.isArray(v) ? v : v ? [v] : [] }
  readonly property string customStyle: customTarget === "claude" ? faceStyle : grokFaceStyle
  readonly property var customGear: asList(customTarget === "claude" ? accessory : grokAccessory)

  function openCustom() {
    root.inputOpen = false
    root.answerKey = ""
    root.pinned = false
    root.customOpen = true
  }
  // Writes one key to config.json; the file watcher then reloads it.
  function saveOpt(key, value) {
    var c = JSON.parse(JSON.stringify(root.cfg || {}))
    c[key] = value
    root.cfg = c
    cfgFile.setText(JSON.stringify(c, null, 2) + "\n")
  }
  function setCustomStyle(st) { saveOpt(customTarget === "claude" ? "faceStyle" : "grokFaceStyle", st) }
  function toggleGear(n) {
    var cur = root.customGear.slice(), i = cur.indexOf(n)
    if (n === "") cur = []
    else if (i >= 0) cur.splice(i, 1)
    else {
      var g = root.gearGroup[n]
      if (g) cur = cur.filter(function (x) { return root.gearGroup[x] !== g })
      cur.push(n)
    }
    saveOpt(customTarget === "claude" ? "accessory" : "grokAccessory", cur)
  }

  readonly property string mode: greeting ? "greet"
    : customOpen ? "custom"
    : detectOpen ? "detect"
    : inputOpen ? "input"
    : answerData ? "answer"
    : (hovered || pinned) && count > 0 ? "expanded"
    : (alertData ? "alert" : "collapsed")

  function uuid4() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
      var r = Math.random() * 16 | 0
      return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16)
    })
  }

  function openInput() {
    var resuming = root.hasDraft          // back to a draft: keep its agent, model and folder
    if (!root.inputOpen && !resuming) root.askModel = "auto"
    root.customOpen = false
    root.detectOpen = false
    root.alertKey = ""
    root.answerKey = ""
    root.inputOpen = true
    dirsProc.running = true
    if (!root.detecting && root.detected.length === 0) root.rescan()
    focusLater.restart()
  }

  // Closing keeps the draft (text and pasted images); discardDraft() throws it away.
  function closeInput() { root.inputOpen = false }
  function discardDraft() {
    promptEdit.text = ""
    root.attachments = []
    root.inputOpen = false
  }

  // Prompt + "[attached image: …]" lines, the same contract the macOS client uses.
  function withAttachments(text) {
    var t = text.trim()
    if (root.attachments.length === 0) return t
    var out = (t === "" ? "Look at the attached image(s)." : t) + "\n\n"
      + root.attachments.map(function (p) { return "[attached image: " + p + "]" }).join("\n")
    root.attachments = []
    return out
  }

  // Ctrl+V: images on the clipboard become attachments; text pastes as usual.
  property var pasteTarget: null
  function pasteInto(target) {
    root.pasteTarget = target
    pasteProc.running = false
    pasteProc.running = true
  }

  function rescan() {
    if (root.detecting) return
    root.detecting = true
    detectProc.running = true
  }
  function openDetect() {
    root.alertKey = ""; root.answerKey = ""; root.inputOpen = false; root.customOpen = false
    root.pinned = false
    root.detectOpen = true
    root.rescan()
  }

  function runAsk(args, cwd) {
    Quickshell.execDetached(["bash", "-c", 'MYZK_NOTCH_CWD="$1"; shift; export MYZK_NOTCH_CWD; exec "$@"',
      "myzk-notch", cwd || "~", root.backend, "ask"].concat(args))
  }

  // Starts a chat (notch input or client window) and returns its key.
  function startChat(text, agent, dir) {
    var t = root.withAttachments(text)
    if (t === "") return ""
    var who = agent || "claude"
    if (root.demoMode) {
      Quickshell.execDetached(["bash", "-c",
        'XDG_STATE_HOME="$1" exec "$5" set claude demo-notch thinking --name "$2" --task "$3" --detail "$4"',
        "myzk-notch", root.demoHome, t.slice(0, 22), t, root.tr("thinking"), root.backend])
      return "claude:demo-notch"
    }
    var id = root.uuid4()
    var key = who + ":" + id
    if (root.askModel !== "auto") root.setChatModel(key, root.askModel)
    root.runAsk([t, "--id", id, "--agent", who].concat(root.modelArgs(root.askModel)), dir || root.askDir)
    root.askModel = "auto"
    return key
  }

  // Follow-up in an existing chat, with the model picked for it.
  function replyTo(d, text) {
    if (!d) return false
    var t = root.withAttachments(text)
    if (t === "") return false
    root.runAsk([t, "--resume", d.ident, "--agent", d.agent].concat(root.modelArgs(root.chatModel(d.key))),
      d.cwd || "~")
    return true
  }

  // New task: runs headless via myzk-agents; the hooks then show it live.
  function send() {
    if (promptEdit.text.trim() === "" && root.attachments.length === 0) return
    var who = root.chatAgents.some(function (a) { return a.id === root.askAgent }) ? root.askAgent : "claude"
    var key = root.startChat(promptEdit.text, who, root.askDir)
    if (key === "") return
    root.pickedKey = key
    sendFx.restart()
  }

  // Follow-up in the same conversation.
  function reply() {
    if (root.replyTo(root.answerData, replyInput.text)) replyInput.text = ""
  }

  function openTerminal(d) {
    if (!d) return
    var cmd = d.agent === "codex" ? "codex resume --last"
      : root.claudeCmd + " --resume " + (d.session || d.ident)
    Quickshell.execDetached(["bash", "-c",
      'cd "$1" 2>/dev/null; exec setsid uwsm-app -- $2 -e bash -lc "$3"',
      "myzk-notch", d.cwd || root.home, root.terminalCmd, cmd])
    root.answerKey = ""
  }

  // Tapping the pet: open its chat (or a new one), its terminal, or just play.
  function tapPet(d) {
    if (root.petTap === "terminal") root.openTerminal(d)
    else if (root.petTap === "play") return     // the face's own poke handles it
    else if (d && d.source === "notch") { root.pinned = false; root.answerKey = d.key }
    else { root.pinned = false; root.openInput() }
  }

  function openClient() {
    root.pinned = false
    root.clientOpen = true
  }

  // How the router picked the model, in the UI language ("reglas", "escalado ↑"…).
  function routeLabel(r) { var l = root.tr("route." + r); return l === "route." + r ? r : l }
  function capitalize(s) { s = String(s || ""); return s.charAt(0).toUpperCase() + s.slice(1) }
  function fmtTokens(n) {
    n = Number(n || 0)
    return n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1000 ? Math.floor(n / 1000) + "k" : String(n)
  }

  function greet() { greetSeq.restart() }

  // Drops an entry from the notch board only.
  function forget(agent, ident) {
    var key = agent + ":" + ident
    if (root.pickedKey === key) root.pickedKey = ""
    if (root.answerKey === key) root.answerKey = ""
    Quickshell.execDetached([root.backend, "rm", agent, ident])
  }

  // Claude sessions go by assistantName; the project only shows when there
  // are several of them to tell apart.
  function displayName(agent, name) {
    if (agent !== "claude") return name
    return root.claudeCount > 1 ? root.assistantName + " · " + name : root.assistantName
  }

  // Stable model: rows are updated in place so faces keep animating instead
  // of being rebuilt on every hook event.
  ListModel { id: agentModel }
  readonly property alias agentList: agentModel
  function loadDirs() { dirsProc.running = true }

  function moodFor(state, updated) {
    var age = root.now - (updated || 0)
    if (state === "done") return age < root.doneGlow ? "done" : (age > root.sleepAfter ? "sleep" : "idle")
    if (state === "idle") return age > root.sleepAfter ? "sleep" : "idle"
    if (state === "error" && age > root.errorLoud) return "errorStale"
    if (state === "restart" && age > 8) return "idle"
    return state || "idle"
  }

  function idColor(agent, ident) {
    if (agent === "claude") return root.claudeColor
    var assigned = root.colorMap[agent + ":" + ident]
    if (assigned) return assigned
    var h = 0
    for (var i = 0; i < ident.length; i++) h = (h * 31 + ident.charCodeAt(i)) >>> 0
    return root.palette[h % root.palette.length]
  }

  // Big orbs are pale like the reel's, warmed or cooled by the agent's colour.
  property string forceReaction: ""
  Timer { id: reactReset; interval: 200; onTriggered: root.forceReaction = "" }

  function accessoryFor(agent, ident) {
    if (ident && root.accessories[ident] !== undefined) return root.accessories[ident]
    return agent === "claude" ? root.accessory : root.grokAccessory
  }
  function faceStyleFor(agent) { return agent === "claude" ? root.faceStyle : root.grokFaceStyle }

  function orbTint(agent, ident) {
    return Qt.tint("#EEF2F7", Qt.alpha(root.idColor(agent, ident), agent === "claude" ? 0.28 : 0.16))
  }

  function indexOf(key) {
    for (var i = 0; i < agentModel.count; i++) if (agentModel.get(i).key === key) return i
    return -1
  }

  function snapshot(key) {
    var i = root.indexOf(key)
    if (i < 0) return null
    var r = agentModel.get(i)
    return {
      key: r.key, agent: r.agent, ident: r.ident, name: r.name, state: r.state,
      task: r.task, detail: r.detail, since: r.since, updated: r.updated,
      cwd: r.cwd, answer: r.answer, source: r.source,
      model: r.model, route: r.route, session: r.session,
      prev: root.hist[r.key] || ""
    }
  }

  function same(oldValue, newValue) {
    return JSON.stringify(oldValue) === JSON.stringify(newValue) ? oldValue : newValue
  }

  function ago(t) {
    var s = Math.max(0, Math.floor(root.now - (t || root.now)))
    if (s < 60) return s + "s"
    if (s < 3600) return Math.floor(s / 60) + "m"
    return Math.floor(s / 3600) + "h" + String(Math.floor(s % 3600 / 60)).padStart(2, "0")
  }

  function ingest(raw) {
    var map = {}
    try { map = JSON.parse(raw).agents || {} } catch (e) { map = {} }

    for (var i = agentModel.count - 1; i >= 0; i--)
      if (!(agentModel.get(i).key in map)) agentModel.remove(i)

    var states = {}
    for (var key in map) {
      var a = map[key]
      var row = {
        key: key, agent: String(a.agent || ""), ident: String(a.id || ""),
        name: String(a.name || a.id || ""), state: String(a.state || "idle"),
        task: String(a.task || ""), detail: String(a.detail || ""),
        cwd: String(a.cwd || ""), answer: String(a.answer || ""), source: String(a.source || ""),
        model: String(a.model || ""), route: String(a.route || ""), session: String(a.session || ""),
        since: Number(a.since || 0), updated: Number(a.updated || 0)
      }
      var idx = root.indexOf(key)
      if (idx < 0) {
        if (row.agent !== "claude" && !(key in root.colorMap))
          root.colorMap[key] = root.palette[root.nextColor++ % root.palette.length]
        agentModel.append(row)
      } else {
        var old = agentModel.get(idx)
        if (old.detail !== row.detail && old.detail !== "") root.hist[key] = old.detail
        for (var k in row) if (old[k] !== row[k]) agentModel.setProperty(idx, k, row[k])
      }
      states[key] = row.state
      var before = root.lastStates[key]
      if (before !== undefined && before !== row.state
          && (row.state === "waiting" || row.state === "done" || row.state === "error")) {
        root.alertKey = key
        alertTimer.restart()
      }
    }
    root.lastStates = states
    root.count = agentModel.count
    root.refresh()
  }

  // Recomputes everything that depends on time or ranking.
  function refresh() {
    var best = "", bestScore = -1
    var mainKey = "", mainScore = -1
    var grok = [], grokKeys = [], others = [], moodCount = {}
    var claudes = 0, chats = 0
    for (var i = 0; i < agentModel.count; i++) {
      var r = agentModel.get(i)
      var mood = root.moodFor(r.state, r.updated)
      var score = root.rank[mood] * 1e10 + r.updated
      if (score > bestScore) { bestScore = score; best = r.key }
      if (r.agent === "claude") {
        claudes++
        if (score > mainScore) { mainScore = score; mainKey = r.key }
      } else {
        others.push({ key: r.key, score: score })
        if (r.agent === "grok") {
          grok.push({ key: r.key, score: score, mood: mood })
          grokKeys.push(r.key)
          moodCount[mood] = (moodCount[mood] || 0) + 1
        } else chats++
      }
    }
    root.chatCount = claudes + chats
    if (best !== root.primaryKey) root.primaryKey = best
    if (mainKey !== root.mainClaudeKey) root.mainClaudeKey = mainKey
    root.claudeCount = claudes
    root.grokCount = grok.length
    if (JSON.stringify(grokKeys) !== JSON.stringify(root.grokOrder)) root.grokOrder = grokKeys

    grok.sort(function (x, y) { return y.score - x.score })
    root.grokMood = grok.length > 0 ? grok[0].mood : "idle"
    others.sort(function (x, y) { return y.score - x.score })
    var cluster = others.slice(0, 4).map(function (o) { return o.key })
    if (JSON.stringify(cluster) !== JSON.stringify(root.clusterKeys)) root.clusterKeys = cluster

    var parts = []
    moodCount.error = (moodCount.error || 0) + (moodCount.errorStale || 0)
    ;["waiting", "error", "working", "upload", "restart", "thinking", "done", "idle", "sleep"].forEach(function (m) {
      if (moodCount[m]) parts.push(moodCount[m] + " " + root.stateText[m])
    })
    root.grokSummary = parts.slice(0, 2).join(" · ")

    // Only reassign when something actually changed; rebuilding these every
    // second re-ran every binding hanging off them and caused a hitch.
    root.mainClaudeData = root.same(root.mainClaudeData, root.snapshot(root.mainClaudeKey))
    root.focusData = root.same(root.focusData, root.snapshot(root.focusKey))
    if (root.alertKey !== "" && root.indexOf(root.alertKey) < 0) root.alertKey = ""
    root.alertData = root.same(root.alertData, root.alertKey !== "" ? root.snapshot(root.alertKey) : null)
    if (root.answerKey !== "" && root.indexOf(root.answerKey) < 0) root.answerKey = ""
    root.answerData = root.same(root.answerData, root.answerKey !== "" ? root.snapshot(root.answerKey) : null)
  }

  onFocusKeyChanged: refresh()
  onAlertKeyChanged: refresh()
  onAnswerKeyChanged: refresh()

  // Keyboard/script control: `qs -p $OMARCHY_PATH/shell ipc call myzk.notch toggle`
  IpcHandler {
    target: "myzk.notch"
    function toggle(): void { root.pinned = !root.pinned; if (!root.pinned) root.pickedKey = "" }
    function grok(): void { if (!root.pinned) root.pinned = true; root.grokOpen = !root.grokOpen }
    function ask(): void { root.openInput() }
    function greet(): void { root.greet() }
    // Play a reaction on every visible face: annoyed | dizzy
    function react(kind: string): void { root.forceReaction = ""; root.forceReaction = kind; reactReset.restart() }
    function demo(on: bool): void {
      agentModel.clear()
      root.lastStates = {}
      root.hist = {}
      root.colorMap = {}
      root.nextColor = 0
      root.pickedKey = ""; root.alertKey = ""; root.answerKey = ""
      root.demoMode = on
    }
    function customize(): void { root.openCustom() }
    function agents(): void { root.openDetect() }
    function client(): void { root.clientOpen = !root.clientOpen }
    // Opens the client window on one conversation (key as in summary.json, e.g. "claude:UUID").
    function chat(key: string): void { clientWin.selected = key; clientWin.tab = 0; root.clientOpen = true }
    // Opens the client window on the Git & Checksum tab.
    function tools(): void { clientWin.tab = 1; root.clientOpen = true }
    function close(): void {
      root.customOpen = false; root.detectOpen = false; root.closeInput(); root.answerKey = ""; root.pinned = false
    }
    // Opens the most recent notch conversation.
    function last(): void {
      var best = "", t = 0
      for (var i = 0; i < agentModel.count; i++) {
        var r = agentModel.get(i)
        if (r.source === "notch" && r.updated > t) { t = r.updated; best = r.key }
      }
      if (best !== "") root.answerKey = best
    }
  }

  FileView {
    path: root.stateFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.ingest(text())
    onLoadFailed: root.ingest("{}")
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: { root.now = Date.now() / 1000; root.refresh(); root.refreshUsage() }
  }

  Process {
    id: dirsProc
    // Each entry is a glob; "~" expands to $HOME. Unquoted $p lets bash glob it.
    command: ["bash", "-c", 'for p in "$@"; do p="${p/#\\~/$HOME}"; for d in $p; do [ -d "$d" ] && echo "$d"; done; done',
      "dirs"].concat(root.projectDirs)
    stdout: StdioCollector {
      onStreamFinished: {
        var dirs = String(text).split("\n").filter(function (l) { return l.length > 0 })
          .map(function (l) { return l.replace(root.home, "~").replace(/\/$/, "") })
        root.askDirs = ["~"].concat(dirs)
        if (root.askDirIndex >= root.askDirs.length) root.askDirIndex = 0
      }
    }
  }

  Process {
    id: detectProc
    command: [root.backend, "detect"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.detected = JSON.parse(text) || [] } catch (e) { }
        root.detecting = false
      }
    }
    onExited: root.detecting = false
  }
  Component.onCompleted: rescanLater.start()
  Timer { id: rescanLater; interval: 4000; onTriggered: root.rescan() }

  // Usage of whichever Claude session is in front, refreshed while the notch is open.
  Process {
    id: usageProc
    stdout: StdioCollector {
      onStreamFinished: { try { var u = JSON.parse(text); if (u) root.usage = u } catch (e) { } }
    }
  }
  function refreshUsage() {
    if (root.mode === "collapsed" || root.mode === "custom" || root.mode === "greet" || usageProc.running) return
    var d = root.alertData || root.answerData || root.focusData
    var sid = d && d.agent === "claude" ? (d.session || d.ident) : ""
    if (sid === root.usageKey && root.now - root.usageStamp < 20) return
    root.usageKey = sid
    root.usageStamp = root.now
    usageProc.command = sid ? [root.usageTool, "--session", sid] : [root.usageTool]
    usageProc.running = true
  }
  onModeChanged: { if (mode !== "expanded") grokOpen = false; refreshUsage() }

  Process {
    id: pasteProc
    command: [root.toolsBin, "paste", (root.demoMode ? root.demoHome : root.home + "/.local/state") + "/myzk-agents/pastes"]
    stdout: StdioCollector {
      onStreamFinished: {
        var got = []
        try { got = JSON.parse(text) || [] } catch (e) { }
        if (got.length > 0) {
          root.attachments = root.attachments.concat(got.filter(function (p) { return root.attachments.indexOf(p) < 0 }))
        } else if (root.pasteTarget) {
          root.pasteTarget.paste()          // plain text: paste it normally
        }
        root.pasteTarget = null
      }
    }
  }

  FileView {
    id: chatModelsView
    path: root.chatModelsFile
    printErrors: false
    onLoaded: { try { root.chatModels = JSON.parse(text()) || {} } catch (e) { root.chatModels = {} } }
    onLoadFailed: root.chatModels = {}
  }

  ClientWindow {
    id: clientWin
    n: root
    open: root.clientOpen
    onCloseRequested: root.clientOpen = false
  }

  Timer {
    id: focusLater
    interval: 60
    onTriggered: promptEdit.forceActiveFocus()
  }

  // Send: the orb hops, the text lifts off, then the box folds away.
  SequentialAnimation {
    id: sendFx
    ScriptAction { script: inputOrb.mood = "working" }
    ParallelAnimation {
      NumberAnimation { target: promptFlick; property: "opacity"; to: 0; duration: 260; easing.type: Easing.InQuad }
      NumberAnimation { target: promptFlick; property: "anchors.topMargin"; to: -18; duration: 260; easing.type: Easing.InQuad }
    }
    PauseAnimation { duration: 180 }
    ScriptAction {
      script: {
        root.closeInput()
        promptFlick.opacity = 1
        promptFlick.anchors.topMargin = 16
        inputOrb.mood = Qt.binding(function () { return promptEdit.text.length > 0 ? "thinking" : "idle" })
      }
    }
  }

  Timer {
    interval: 900
    running: true
    onTriggered: if (root.greetOnStart) root.greet()
  }

  SequentialAnimation {
    id: greetSeq
    ScriptAction {
      script: {
        root.greetSpread = 0; root.greetOrbScale = 0; root.greetWave = false
        root.greetMood = "sleep"; root.greeting = true
      }
    }
    PauseAnimation { duration: 380 }
    ScriptAction { script: ringBurst.burst(70) }
    NumberAnimation { target: root; property: "greetOrbScale"; to: 1; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
    ScriptAction { script: root.greetMood = "idle" }
    PauseAnimation { duration: 300 }
    ScriptAction { script: root.greetWave = true }
    NumberAnimation { target: root; property: "greetSpread"; to: 1; duration: 1500; easing.type: Easing.InOutCubic }
    PauseAnimation { duration: 300 }
    ScriptAction { script: { root.greetWave = false; root.greetMood = "working" } }
    PauseAnimation { duration: 950 }
    ScriptAction { script: root.greeting = false }
  }

  Timer {
    id: alertTimer
    interval: root.alertMs
    onTriggered: root.alertKey = ""
  }

  Timer {
    id: leaveTimer
    interval: 260
    onTriggered: root.hovered = false
  }

  readonly property var targetScreen: {
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) if (list[i].name === root.screenName) return list[i]
    return list.length > 0 ? list[0] : null
  }

  // ------------------------------------------------------------------- UI
  PanelWindow {
    id: win
    screen: root.targetScreen
    visible: root.targetScreen !== null

    WlrLayershell.namespace: "myzk-notch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.mode === "input" ? WlrKeyboardFocus.Exclusive
      : root.mode === "answer" || root.mode === "detect" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // Fixed box (just wider than the expanded notch) so the surface never
    // resizes and the compositor redraws as little as possible; only the
    // notch itself takes input.
    anchors { top: true }
    implicitWidth: root.expandedW + 60
    implicitHeight: root.topOffset + 520
    mask: Region { item: notch }

    // Concave "ears" so the notch looks poured out of the bar.
    Repeater {
      model: 2
      Canvas {
        required property int index
        readonly property real r: 12
        width: r; height: r
        y: root.topOffset
        // In the bar the collapsed notch has no drip; the ears only join the
        // bar's edge once it opens past it.
        visible: !root.inBar || (root.mode !== "collapsed" && notch.height > root.topOffset + 6)
        x: index === 0 ? notch.x - r : notch.x + notch.width
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.fillStyle = root.notchColor
          ctx.beginPath()
          if (index === 0) {
            ctx.moveTo(0, 0); ctx.lineTo(r, 0); ctx.lineTo(r, r)
            ctx.arc(0, r, r, 0, -Math.PI / 2, true)
          } else {
            ctx.moveTo(r, 0); ctx.lineTo(0, 0); ctx.lineTo(0, r)
            ctx.arc(r, r, r, Math.PI, Math.PI * 1.5, false)
          }
          ctx.closePath()
          ctx.fill()
        }
        Component.onCompleted: requestPaint()
      }
    }

    Rectangle {
      id: notch
      anchors.horizontalCenter: parent.horizontalCenter
      y: root.inBar ? 0 : root.topOffset
      width: root.mode === "expanded" ? root.expandedW
        : root.mode === "alert" ? root.alertW
        : root.mode === "greet" ? root.greetW
        : root.mode === "input" ? root.inputW
        : root.mode === "custom" ? root.customW
        : root.mode === "detect" ? root.detectW
        : root.mode === "answer" ? root.answerW : root.collapsedW
      height: (root.mode === "expanded" ? expanded.implicitHeight + root.pad * 2
        : root.mode === "alert" ? root.alertH
        : root.mode === "greet" ? 136
        : root.mode === "input" ? inputView.cardH + root.pad * 2
        : root.mode === "custom" ? customView.cardH + root.pad * 2
        : root.mode === "detect" ? detectView.height + root.pad * 2
        : root.mode === "answer" ? answerView.height + root.pad * 2 : root.collapsedH) + usageFoot.room
      color: root.notchColor
      topLeftRadius: 0
      topRightRadius: 0
      bottomLeftRadius: root.mode === "collapsed" ? (root.inBar ? 10 : root.collapsedH / 2) : 30
      bottomRightRadius: bottomLeftRadius
      clip: true

      // Springy morph between the three shapes, like the reel.
      Behavior on width { SpringAnimation { spring: 3.2; damping: 0.3; epsilon: 0.3 } }
      Behavior on height { SpringAnimation { spring: 3.2; damping: 0.3; epsilon: 0.3 } }
      Behavior on bottomLeftRadius { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

      HoverHandler {
        onHoveredChanged: {
          if (hovered) { leaveTimer.stop(); root.hovered = true }
          else leaveTimer.restart()
        }
      }

      // Background click: pin/unpin the expanded view (chips sit above this).
      MouseArea {
        anchors.fill: parent
        onClicked: {
          if (root.mode === "alert") {
            if (root.alertData && root.alertData.answer) root.answerKey = root.alertKey
            root.alertKey = ""
            return
          }
          if (root.mode !== "expanded" && root.mode !== "collapsed") return
          root.pinned = !root.pinned
          if (!root.pinned) root.pickedKey = ""
        }
      }

      // Usage hairlines along the bottom of the open notch.
      UsageBars {
        id: usageFoot
        readonly property bool wanted: ["expanded", "alert", "input", "answer"].indexOf(root.mode) >= 0
        readonly property real room: wanted && visible ? implicitHeight + 12 : 0
        x: root.pad + 14
        width: notch.width - root.pad * 2 - 28
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.pad + 2
        opacity: wanted ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
      }

      // ============================================================ collapsed
      Item {
        id: collapsed
        anchors.fill: parent
        opacity: root.mode === "collapsed" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: root.mode === "collapsed" ? 260 : 90 } }

        AgentFace {
          id: mainOrb
          anchors.left: parent.left
          anchors.leftMargin: root.inBar ? 14 : 18
          anchors.verticalCenter: parent.verticalCenter
          size: root.inBar ? 17 : 21
          glowAlways: true
          tint: root.orbTint("claude", "")
          faceStyle: root.faceStyleFor("claude")
          accessory: root.accessoryFor("claude", "")
          forceReaction: root.forceReaction
          mood: root.mainClaudeData ? root.moodFor(root.mainClaudeData.state, root.mainClaudeData.updated) : "sleep"
        }

        MouseArea {
          anchors.fill: mainOrb
          anchors.margins: -8
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openInput()
        }

        // A draft is waiting: a dot, or how many images are pasted.
        Rectangle {
          visible: root.hasDraft
          x: mainOrb.x + mainOrb.width - 5
          y: mainOrb.y - 3
          width: Math.max(11, draftLbl.implicitWidth + 5); height: 11; radius: 5.5
          color: root.claudeColor
          Text {
            id: draftLbl
            anchors.centerIn: parent
            text: root.attachments.length > 0 ? String(root.attachments.length) : ""
            color: "#111113"
            font.pixelSize: 8
            font.bold: true
          }
        }

        Grid {
          anchors.right: parent.right
          anchors.rightMargin: root.inBar ? 14 : 18
          anchors.verticalCenter: parent.verticalCenter
          columns: 2
          spacing: 2
          Repeater {
            model: agentModel
            AgentFace {
              required property string key
              required property string agent
              required property string ident
              required property string state
              required property real updated
              visible: root.clusterKeys.indexOf(key) >= 0
              mini: true
              size: root.inBar ? 10 : 12
              tint: root.idColor(agent, ident)
              faceStyle: root.faceStyleFor(agent)
              accessory: root.accessoryFor(agent, ident)
              forceReaction: root.forceReaction
              mood: root.moodFor(state, updated)
            }
          }
        }
      }

      // ============================================================= expanded
      Row {
        id: expanded
        x: root.pad
        y: root.pad + (root.mode === "expanded" ? 0 : -12)
        spacing: 8
        opacity: root.mode === "expanded" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: root.mode === "expanded" ? 280 : 100; easing.type: Easing.InQuad } }
        Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

        readonly property real cardH: Math.max(128, chipCol.implicitHeight + 28)

        // ---------------------------------------------------- focus card
        Rectangle {
          id: focusCard
          width: 310
          height: expanded.cardH
          radius: 24
          color: root.cardColor
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.04)
          clip: true

          readonly property var d: root.focusData
          readonly property string mood: d ? root.moodFor(d.state, d.updated) : "sleep"

          AgentFace {
            id: bigOrb
            anchors.left: parent.left
            anchors.leftMargin: 26
            anchors.verticalCenter: parent.verticalCenter
            size: 62
            glowAlways: true
            tint: focusCard.d ? root.orbTint(focusCard.d.agent, focusCard.d.ident) : "#E4ECF5"
            faceStyle: root.faceStyleFor(focusCard.d ? focusCard.d.agent : "claude")
            accessory: root.accessoryFor(focusCard.d ? focusCard.d.agent : "claude", focusCard.d ? focusCard.d.ident : "")
            forceReaction: root.forceReaction
            mood: focusCard.mood
            onTapped: root.tapPet(focusCard.d)
          }

          // Step carousel: previous step dim above, current bright, the
          // overall task dim below — the reel's three-line menu.
          Column {
            id: steps
            anchors.left: bigOrb.right
            anchors.leftMargin: 22
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Text {
              width: parent.width
              text: focusCard.d
                ? (focusCard.d.agent === "claude" ? root.assistantName + " · " + focusCard.d.name : root.grokName + " · " + focusCard.d.name)
                : "Nadie trabajando"
              elide: Text.ElideRight
              color: "#7C7F88"
              font.family: root.fontFamily
              font.pixelSize: 11
            }

            Text {
              width: parent.width
              visible: text !== ""
              text: focusCard.d && focusCard.d.prev ? "✓  " + focusCard.d.prev : ""
              elide: Text.ElideRight
              color: "#6E717A"
              font.family: root.fontFamily
              font.pixelSize: 12
            }

            Text {
              id: currentStep
              width: parent.width
              text: focusCard.d ? "›  " + (focusCard.d.detail || root.stateText[focusCard.mood]) : ""
              elide: Text.ElideRight
              maximumLineCount: 2
              wrapMode: Text.Wrap
              color: "#F2F3F5"
              font.family: root.fontFamily
              font.pixelSize: 15
              font.weight: Font.Medium
              onTextChanged: stepIn.restart()
              NumberAnimation {
                id: stepIn
                target: currentStep; property: "opacity"
                from: 0.2; to: 1; duration: 320; easing.type: Easing.OutCubic
              }
            }

            Text {
              width: parent.width
              visible: !!(focusCard.d && focusCard.d.task)
              text: focusCard.d ? "◦  " + focusCard.d.task : ""
              elide: Text.ElideRight
              color: "#8A8D96"
              font.family: root.fontFamily
              font.pixelSize: 12
            }

            Row {
              spacing: 6
              Rectangle {
                visible: !!focusCard.d
                width: stateLabel.implicitWidth + 16
                height: stateLabel.implicitHeight + 6
                radius: height / 2
                color: Qt.alpha(root.stateColor[focusCard.mood], 0.14)
                Text {
                  id: stateLabel
                  anchors.centerIn: parent
                  text: focusCard.d ? root.stateText[focusCard.mood] + " · " + root.ago(focusCard.d.since) : ""
                  color: root.stateColor[focusCard.mood]
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  font.weight: Font.Medium
                }
              }
              ModelBadge { d: focusCard.d; anchors.verticalCenter: parent.verticalCenter }
            }
          }
        }

        // ----------------------------------------------------- chip card
        // the assistant sessions on top, then every Grok Bot folded into one
        // capsule; clicking it deals the bots out of the capsule one by one.
        Rectangle {
          id: chipCard
          width: root.expandedW - root.pad * 2 - focusCard.width - expanded.spacing
          height: expanded.cardH
          radius: 24
          color: root.cardColor
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.04)
          clip: true

          Column {
            id: chipCol
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 8

            // --------------------------------------------------- actions
            // Flow, not Row: with "View answer" showing, the buttons wrap
            // instead of spilling past the card.
            Flow {
              width: parent.width
              spacing: 6
              Rectangle {
                width: newLbl.implicitWidth + 22; height: 28; radius: 14
                color: newMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                Text { id: newLbl; anchors.centerIn: parent; text: root.tr("ask.button"); color: "#E4E6EA"; font.family: root.fontFamily; font.pixelSize: 12 }
                MouseArea { id: newMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: { root.pinned = false; root.openInput() } }
              }
              Rectangle {
                visible: !!(root.focusData && root.focusData.answer)
                width: ansLbl.implicitWidth + 22; height: 28; radius: 14
                color: ansMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                Text { id: ansLbl; anchors.centerIn: parent; text: root.tr("ask.viewAnswer"); color: "#E4E6EA"; font.family: root.fontFamily; font.pixelSize: 12 }
                MouseArea { id: ansMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: { root.pinned = false; root.answerKey = root.focusData.key } }
              }
              Rectangle {
                width: agLbl.implicitWidth + 22; height: 28; radius: 14
                color: agMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                Text { id: agLbl; anchors.centerIn: parent; text: "⌕  " + root.tr("detect.button"); color: "#E4E6EA"; font.family: root.fontFamily; font.pixelSize: 12 }
                MouseArea { id: agMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.openDetect() }
              }
              // Full-size client window: chats, transcript, git inspector.
              Rectangle {
                width: 28; height: 28; radius: 14
                color: cliMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                Text { anchors.centerIn: parent; text: "⤢"; color: "#E4E6EA"; font.family: root.fontFamily; font.pixelSize: 14 }
                MouseArea { id: cliMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.openClient() }
              }
              // Customise: icon only, it's the least used action.
              Rectangle {
                width: 28; height: 28; radius: 14
                color: custMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                Text { anchors.centerIn: parent; text: "⚙"; color: "#E4E6EA"; font.family: root.fontFamily; font.pixelSize: 14 }
                MouseArea { id: custMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.openCustom() }
              }
            }

            // ------------------------------------------------ the assistant chips
            Grid {
              width: parent.width
              columns: 2
              spacing: 8
              visible: root.chatCount > 0

              Repeater {
                model: agentModel
                AgentChip {
                  required property int index
                  required property string key
                  required property string agent
                  required property string ident
                  required property string name
                  required property string state
                  required property real updated
                  visible: agent !== "grok"
                  width: (chipCol.width - 8) / 2
                  c: root.idColor(agent, ident)
                  label: root.displayName(agent, name)
                  mood: root.moodFor(state, updated)
                  faceStyle: root.faceStyleFor(agent)
                  accessory: root.accessoryFor(agent, ident)
                  forceReaction: root.forceReaction
                  focused: key === root.focusKey
                  fontFamily: root.fontFamily
                  opacity: root.mode === "expanded" ? 1 : 0
                  scale: root.mode === "expanded" ? (hovered ? 1.04 : 1) : 0.85
                  Behavior on opacity { NumberAnimation { duration: 240 } }
                  Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                  onActivated: root.pickedKey = key
                  closable: true
                  onCloseRequested: root.forget(agent, ident)
                }
              }
            }

            // -------------------------------------------------- Grok capsule
            Rectangle {
              id: capsule
              visible: root.grokCount > 0
              width: parent.width
              height: 48
              radius: height / 2
              readonly property color tone: root.stateColor[root.grokMood]
              color: capMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05)
              border.width: 1
              border.color: root.grokOpen ? Qt.alpha(tone, 0.55) : Qt.rgba(1, 1, 1, 0.1)
              scale: capMouse.pressed ? 0.97 : (root.mode === "expanded" ? 1 : 0.85)
              opacity: root.mode === "expanded" ? 1 : 0
              Behavior on color { ColorAnimation { duration: 180 } }
              Behavior on border.color { ColorAnimation { duration: 260 } }
              Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
              Behavior on opacity { NumberAnimation { duration: 260 } }

              // The bots huddled inside; they fade to ghosts once dealt out.
              Row {
                id: capFaces
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: -9
                Repeater {
                  model: agentModel
                  AgentFace {
                    id: capFace
                    required property string key
                    required property string agent
                    required property string ident
                    required property string state
                    required property real updated
                    readonly property int order: root.grokOrder.indexOf(key)
                    visible: agent === "grok" && order < 6
                    mini: true
                    size: 24
                    tint: root.idColor(agent, ident)
                    faceStyle: root.faceStyleFor(agent)
                    accessory: root.accessoryFor(agent, ident)
                    forceReaction: root.forceReaction
                    mood: root.moodFor(state, updated)
                    opacity: root.grokOpen ? 0.22 : 1
                    Behavior on opacity {
                      SequentialAnimation {
                        PauseAnimation { duration: Math.max(0, capFace.order) * 50 }
                        NumberAnimation { duration: 220 }
                      }
                    }
                  }
                }
              }

              Column {
                anchors.left: capFaces.right
                anchors.leftMargin: 12
                anchors.right: chevron.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                  text: root.grokName + " Bots  ·  " + root.grokCount
                  color: "#F2F3F5"
                  font.family: root.fontFamily
                  font.pixelSize: 13
                  font.weight: Font.DemiBold
                }
                Text {
                  width: parent.width
                  text: root.grokSummary
                  elide: Text.ElideRight
                  color: capsule.tone
                  font.family: root.fontFamily
                  font.pixelSize: 11
                }
              }

              Text {
                id: chevron
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: "#C9CED6"
                font.pixelSize: 20
                rotation: root.grokOpen ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2 } }
              }

              MouseArea {
                id: capMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.grokOpen = !root.grokOpen
              }
            }

            // ------------------------------------------------- dealt-out bots
            Item {
              id: grokArea
              width: parent.width
              height: root.grokOpen ? grokGrid.implicitHeight : 0
              Behavior on height { SpringAnimation { spring: 3; damping: 0.34; epsilon: 0.3 } }

              Grid {
                id: grokGrid
                width: parent.width
                columns: 2
                spacing: 8

                Repeater {
                  model: agentModel
                  AgentChip {
                    id: gchip
                    required property string key
                    required property string agent
                    required property string ident
                    required property string name
                    required property string state
                    required property real updated
                    readonly property int order: root.grokOrder.indexOf(key)
                    visible: agent === "grok"
                    width: (chipCol.width - 8) / 2
                    c: root.idColor(agent, ident)
                    label: name
                    mood: root.moodFor(state, updated)
                    faceStyle: root.faceStyleFor(agent)
                    accessory: root.accessoryFor(agent, ident)
                    forceReaction: root.forceReaction
                    focused: key === root.focusKey
                    fontFamily: root.fontFamily
                    onActivated: root.pickedKey = key
                    closable: true
                    onCloseRequested: root.forget(agent, ident)

                    // 0 = tucked inside the capsule, 1 = in its slot.
                    property real t: root.grokOpen ? 1 : 0
                    Behavior on t {
                      SequentialAnimation {
                        PauseAnimation { duration: root.grokOpen ? 90 + Math.max(0, gchip.order) * 95 : 0 }
                        NumberAnimation { duration: root.grokOpen ? 620 : 280; easing.type: root.grokOpen ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.5 }
                      }
                    }
                    enabled: t > 0.6
                    live: t > 0.01
                    opacity: Math.min(1, t * 1.5)
                    scale: (0.3 + 0.7 * t) * (hovered ? 1.04 : 1)
                    rotation: (1 - t) * (order % 2 ? 14 : -14)
                    transform: Translate {
                      x: (1 - gchip.t) * (capFaces.x + capFaces.width / 2 - (gchip.x + gchip.width / 2))
                      y: (1 - gchip.t) * (capsule.y + capsule.height / 2 - (grokArea.y + gchip.y + gchip.height / 2))
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ================================================================ alert
      Row {
        id: alert
        x: root.pad
        y: root.pad
        spacing: 8
        opacity: root.mode === "alert" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: root.mode === "alert" ? 300 : 100 } }

        readonly property var d: root.alertData
        readonly property string mood: d ? root.moodFor(d.state, d.updated) : "idle"
        readonly property color tone: d ? (d.state === "error" ? "#FF5A36" : d.state === "waiting" ? "#F5A524" : "#2FD17F") : "#2FD17F"
        readonly property real cardH: root.alertH - root.pad * 2

        Rectangle {
          id: alertCard
          width: root.alertW - root.pad * 2 - (stack.visible ? stack.width + alert.spacing : 0)
          height: alert.cardH
          radius: 24
          color: root.cardColor
          clip: true

          // Warm/cool light pooling up from the bottom edge.
          Shape {
            anchors.fill: parent
            opacity: 0.85
            ShapePath {
              strokeColor: "transparent"
              strokeWidth: 0
              fillGradient: RadialGradient {
                centerX: alertCard.width / 2; centerY: alertCard.height * 1.35
                centerRadius: alertCard.width * 0.62
                focalX: alertCard.width / 2; focalY: alertCard.height * 1.35
                GradientStop { position: 0.0; color: Qt.alpha(alert.tone, 0.95) }
                GradientStop { position: 0.45; color: Qt.alpha(alert.tone, 0.35) }
                GradientStop { position: 1.0; color: Qt.alpha(alert.tone, 0) }
              }
              startX: 0; startY: 0
              PathLine { x: alertCard.width; y: 0 }
              PathLine { x: alertCard.width; y: alertCard.height }
              PathLine { x: 0; y: alertCard.height }
              PathLine { x: 0; y: 0 }
            }
          }

          // Faint rotating triangle behind the orb.
          Canvas {
            id: tri
            width: 84; height: 84
            anchors.verticalCenter: parent.verticalCenter
            x: 22
            opacity: 0.22
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.strokeStyle = alert.tone
              ctx.lineWidth = 1.2
              ctx.beginPath()
              for (var i = 0; i < 3; i++) {
                var a = -Math.PI / 2 + i * 2 * Math.PI / 3
                var px = width / 2 + Math.cos(a) * width * 0.44
                var py = height / 2 + Math.sin(a) * height * 0.44
                if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
              }
              ctx.closePath()
              ctx.stroke()
            }
            Connections { target: alert; function onToneChanged() { tri.requestPaint() } }
            Component.onCompleted: requestPaint()
            RotationAnimation on rotation {
              running: alert.visible
              loops: Animation.Infinite
              from: 0; to: 360; duration: 14000
            }
          }

          AgentFace {
            id: alertOrb
            anchors.horizontalCenter: tri.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            size: 50
            glowAlways: true
            tint: alert.d ? root.orbTint(alert.d.agent, alert.d.ident) : "#E4ECF5"
            faceStyle: root.faceStyleFor(alert.d ? alert.d.agent : "claude")
            accessory: root.accessoryFor(alert.d ? alert.d.agent : "claude", alert.d ? alert.d.ident : "")
            forceReaction: root.forceReaction
            mood: alert.mood
          }

          Column {
            anchors.left: tri.right
            anchors.leftMargin: 18
            anchors.right: closeBtn.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Text {
              width: parent.width
              text: !alert.d ? ""
                : root.tr(alert.d.state === "error" ? "alert.error" : alert.d.state === "waiting" ? "alert.waiting" : "alert.done",
                          {who: root.displayName(alert.d.agent, alert.d.name)})
              elide: Text.ElideRight
              color: "#F4F4F5"
              font.family: root.fontFamily
              font.pixelSize: 15
              font.weight: Font.Medium
            }
            Text {
              width: parent.width
              text: alert.d ? (alert.d.detail || alert.d.task) + (alert.d.answer ? root.tr("alert.tapAnswer") : "") : ""
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
              color: Qt.lighter(alert.tone, 1.2)
              font.family: root.fontFamily
              font.pixelSize: 12
            }
          }

          Rectangle {
            id: closeBtn
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 34; radius: 17
            color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
            Text {
              anchors.centerIn: parent
              text: "✕"
              color: "#D4D4D8"
              font.pixelSize: 13
            }
            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.alertKey = ""
            }
          }
        }

        // Everyone else, stacked like the reel's side column.
        Rectangle {
          id: stack
          visible: root.clusterKeys.length > 0
          width: 48
          height: alert.cardH
          radius: 24
          color: root.cardColor
          Column {
            anchors.centerIn: parent
            spacing: -5
            Repeater {
              model: agentModel
              AgentFace {
                required property string key
                required property string agent
                required property string ident
                required property string state
                required property real updated
                visible: key !== root.alertKey && root.clusterKeys.indexOf(key) >= 0
                mini: true
                size: 20
                tint: root.idColor(agent, ident)
                faceStyle: root.faceStyleFor(agent)
                accessory: root.accessoryFor(agent, ident)
                forceReaction: root.forceReaction
                mood: root.moodFor(state, updated)
              }
            }
          }
        }
      }

      // ================================================================ greet
      // The reel's hello: glitter bands swirl round a sleeping orb, a ring of
      // sparks pops, it wakes and waves, the bands drift to the edges and the
      // notch folds back up.
      Rectangle {
        id: greetCard
        x: root.pad
        y: root.pad
        width: root.greetW - root.pad * 2
        height: 136 - root.pad * 2
        radius: 24
        color: root.cardColor
        clip: true
        opacity: root.mode === "greet" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 260 } }

        // Warm light pooled behind the orb.
        Shape {
          anchors.centerIn: parent
          width: 260; height: 260
          opacity: 0.55 * root.greetOrbScale
          ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillGradient: RadialGradient {
              centerX: 130; centerY: 130; centerRadius: 130
              focalX: 130; focalY: 130
              GradientStop { position: 0.0; color: "#C9A27A" }
              GradientStop { position: 0.4; color: "#553A2A" }
              GradientStop { position: 1.0; color: "#00000000" }
            }
            PathAngleArc { centerX: 130; centerY: 130; radiusX: 130; radiusY: 130; startAngle: 0; sweepAngle: 360 }
          }
        }

        ParticleSystem {
          id: sparkSys
          running: greetCard.visible
        }

        ImageParticle {
          system: sparkSys
          source: "qrc:///particleresources/fuzzydot.png"
          color: "#E6ECF7"
          colorVariation: 0.12
          alpha: 0.85
          alphaVariation: 0.4
          entryEffect: ImageParticle.Fade
        }

        // Four glitter bands: they start hugging the orb and spread outward.
        Repeater {
          model: 4
          Emitter {
            required property int index
            readonly property real side: index < 2 ? -1 : 1
            readonly property real lane: index % 2
            system: sparkSys
            width: 22
            height: greetCard.height
            x: greetCard.width / 2 - width / 2
              + side * (46 + lane * 30 + root.greetSpread * (greetCard.width * 0.36 - lane * 10))
            y: 0
            emitRate: 110
            lifeSpan: 1100
            lifeSpanVariation: 400
            size: 3
            sizeVariation: 2
            endSize: 1
            velocity: AngleDirection { angle: 270; angleVariation: 30; magnitude: 26; magnitudeVariation: 20 }
          }
        }

        Wander {
          system: sparkSys
          anchors.fill: parent
          xVariance: 30
          pace: 140
        }

        Emitter {
          id: ringBurst
          system: sparkSys
          anchors.centerIn: parent
          width: 4; height: 4
          enabled: false
          lifeSpan: 800
          size: 4
          endSize: 1
          velocity: AngleDirection { angle: 0; angleVariation: 360; magnitude: 150; magnitudeVariation: 40 }
        }

        AgentFace {
          anchors.centerIn: parent
          size: 54
          glowAlways: true
          showBadge: root.greetMood === "working"
          tint: root.orbTint("claude", "")
          faceStyle: root.faceStyleFor("claude")
          accessory: root.accessoryFor("claude", "")
          forceReaction: root.forceReaction
          mood: root.greetMood
          waving: root.greetWave
          scale: root.greetOrbScale
        }
      }

      // ============================================================ custom
      // Live preview on the left; who / style / gear / colour on the right.
      // Every click is saved to config.json straight away.
      Row {
        id: customView
        x: root.pad
        y: root.pad
        spacing: 8
        opacity: root.mode === "custom" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: root.mode === "custom" ? 260 : 120 } }

        readonly property real cardH: Math.max(260, customCol.implicitHeight + 30)
        readonly property color previewTint: root.customTarget === "claude" ? root.orbTint("claude", "")
          : Qt.tint("#EEF2F7", Qt.alpha(root.palette[0], 0.16))
        readonly property var swatches: ["#E0784F"].concat(root.palette)

        Rectangle {
          width: 200
          height: customView.cardH
          radius: 24
          color: root.cardColor
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.04)

          Text {
            x: 18; y: 14
            text: root.tr("custom.title")
            color: "#9AA0AA"
            font.family: root.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 0.6
          }

          AgentFace {
            id: previewFace
            anchors.horizontalCenter: parent.horizontalCenter
            y: 66
            size: 60
            glowAlways: true
            tint: customView.previewTint
            faceStyle: root.customStyle
            accessory: root.customGear
            mood: root.previewMoods[root.previewMoodIndex]
            live: root.mode === "custom"
          }

          Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            spacing: 8

            // ‹ mood ›
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: 4
              Repeater {
                model: [-1, 0, 1]
                Rectangle {
                  required property int modelData
                  width: modelData === 0 ? 104 : 28
                  height: 28
                  radius: 14
                  color: modelData !== 0 && arrowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                  Text {
                    anchors.centerIn: parent
                    text: modelData === -1 ? "‹" : modelData === 1 ? "›"
                      : root.stateText[root.previewMoods[root.previewMoodIndex]]
                    color: modelData === 0 ? root.stateColor[root.previewMoods[root.previewMoodIndex]] : "#E4E6EA"
                    font.family: root.fontFamily
                    font.pixelSize: modelData === 0 ? 12 : 16
                  }
                  MouseArea {
                    id: arrowMouse
                    anchors.fill: parent
                    enabled: modelData !== 0
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      var n = root.previewMoods.length
                      root.previewMoodIndex = (root.previewMoodIndex + modelData + n) % n
                    }
                  }
                }
              }
            }
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: 6
              OptPill { label: root.tr("custom.annoy"); onPicked: previewFace.react("annoyed") }
              OptPill { label: root.tr("custom.dizzy"); onPicked: previewFace.react("dizzy") }
            }
          }
        }

        Rectangle {
          width: root.customW - root.pad * 2 - 200 - customView.spacing
          height: customView.cardH
          radius: 24
          color: root.cardColor
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.04)

          Column {
            id: customCol
            x: 16; y: 14
            width: parent.width - 32
            spacing: 8

            Row {
              spacing: 6
              OptPill { label: root.assistantName; on: root.customTarget === "claude"; onPicked: root.customTarget = "claude" }
              OptPill { label: root.grokName + " Bots"; on: root.customTarget === "grok"; onPicked: root.customTarget = "grok" }
            }

            Text { text: root.tr("custom.style"); color: "#8B93A1"; font.family: root.fontFamily; font.pixelSize: 11; topPadding: 4 }
            Row {
              spacing: 6
              Repeater {
                model: ["orb", "cat", "dog", "hamster"]
                OptPill {
                  required property string modelData
                  label: root.tr("custom.style." + modelData)
                  face: true
                  faceStyleName: modelData
                  gear: root.customGear
                  faceTint: customView.previewTint
                  on: root.customStyle === modelData
                  onPicked: root.setCustomStyle(modelData)
                }
              }
            }

            Text { text: root.tr("custom.gear"); color: "#8B93A1"; font.family: root.fontFamily; font.pixelSize: 11; topPadding: 4 }
            Flow {
              width: parent.width
              spacing: 6
              Repeater {
                model: [""].concat(root.gearNames)
                OptPill {
                  required property string modelData
                  label: root.tr(modelData === "" ? "custom.none" : "gear." + modelData)
                  face: modelData !== ""
                  faceStyleName: root.customStyle
                  gear: modelData
                  faceTint: customView.previewTint
                  on: modelData === "" ? root.customGear.length === 0 : root.customGear.indexOf(modelData) >= 0
                  onPicked: root.toggleGear(modelData)
                }
              }
            }

            Text {
              visible: root.customTarget === "claude"
              text: root.tr("custom.color"); color: "#8B93A1"; font.family: root.fontFamily; font.pixelSize: 11; topPadding: 4
            }
            Row {
              visible: root.customTarget === "claude"
              spacing: 7
              Repeater {
                model: customView.swatches
                Rectangle {
                  required property string modelData
                  readonly property bool on: String(root.claudeColor).toLowerCase() === modelData.toLowerCase()
                  width: 22; height: 22; radius: 11
                  color: modelData
                  border.width: on ? 2 : 0
                  border.color: "white"
                  scale: swMouse.containsMouse ? 1.15 : 1
                  Behavior on scale { NumberAnimation { duration: 120 } }
                  MouseArea {
                    id: swMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.saveOpt("claudeColor", modelData)
                  }
                }
              }
            }

            Text { text: root.tr("custom.tap"); color: "#8B93A1"; font.family: root.fontFamily; font.pixelSize: 11; topPadding: 4 }
            Row {
              spacing: 6
              Repeater {
                model: ["chat", "terminal", "play"]
                OptPill {
                  required property string modelData
                  label: root.tr("custom.tap." + modelData)
                  on: root.petTap === modelData
                  onPicked: root.saveOpt("petTap", modelData)
                }
              }
            }

            Item {
              width: parent.width
              height: 34
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.tr("custom.hint")
                color: "#6B7280"
                font.family: root.fontFamily
                font.pixelSize: 11
              }
              OptPill {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: root.tr("custom.done")
                on: true
                onPicked: root.customOpen = false
              }
            }
          }
        }
      }

      // =============================================================== detect
      // Which coding agents are installed, and which of them report here.
      Rectangle {
        id: detectView
        readonly property var installed: root.detected.filter(function (a) { return a.installed })
        readonly property var missing: root.detected.filter(function (a) { return !a.installed })
        x: root.pad
        y: root.pad
        width: root.detectW - root.pad * 2
        height: detectCol.implicitHeight + 30
        radius: 24
        color: root.cardColor
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.04)
        opacity: root.mode === "detect" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: root.mode === "detect" ? 260 : 120 } }
        focus: root.mode === "detect"
        Keys.onEscapePressed: root.detectOpen = false

        Column {
          id: detectCol
          x: 18; y: 15
          width: parent.width - 36
          spacing: 8

          Item {
            width: parent.width
            height: 34
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1
              Text { text: root.tr("detect.title"); color: "#F2F3F5"; font.family: root.fontFamily; font.pixelSize: 15; font.weight: Font.DemiBold }
              Text {
                text: root.detecting ? root.tr("detect.scanning") : detectView.installed.length + " / " + root.detected.length
                color: "#6B7280"; font.family: root.fontFamily; font.pixelSize: 10
              }
            }
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 6
              OptPill {
                label: "⟳  " + root.tr("detect.rescan")
                onPicked: root.rescan()
              }
              OptPill { label: root.tr("custom.done"); on: true; onPicked: root.detectOpen = false }
            }
          }

          Flickable {
            width: parent.width
            height: Math.min(detectList.implicitHeight, 300)
            contentHeight: detectList.implicitHeight
            clip: true
            interactive: contentHeight > height
            Column {
              id: detectList
              width: parent.width
              spacing: 6
              Repeater {
                model: detectView.installed
                Rectangle {
                  required property var modelData
                  readonly property color tone: modelData.connected ? "#3DD68C" : "#F5B544"
                  width: detectList.width
                  height: 44
                  radius: 14
                  color: Qt.rgba(1, 1, 1, 0.05)
                  Rectangle {
                    id: dot
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 4
                    color: parent.tone
                  }
                  Column {
                    anchors.left: dot.right
                    anchors.leftMargin: 12
                    anchors.right: tag.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                      text: modelData.name + (modelData.version ? "  v" + modelData.version : "")
                      color: "#F2F3F5"; font.family: root.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Text {
                      width: parent.width
                      text: modelData.connected ? String(modelData.path).replace(root.home, "~") : root.tr("detect.hint")
                      elide: Text.ElideMiddle
                      color: "#7C7F88"; font.family: root.fontFamily; font.pixelSize: 10
                    }
                  }
                  Rectangle {
                    id: tag
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: tagLbl.implicitWidth + 18; height: 20; radius: 10
                    color: Qt.alpha(parent.tone, 0.18)
                    Text {
                      id: tagLbl
                      anchors.centerIn: parent
                      text: root.tr(modelData.connected ? "detect.connected" : "detect.found")
                      color: parent.parent.tone; font.family: root.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold
                    }
                  }
                }
              }
              Text {
                width: detectList.width
                visible: detectView.missing.length > 0
                topPadding: 4
                wrapMode: Text.Wrap
                text: root.tr("detect.notfound") + ":  " + detectView.missing.map(function (a) { return a.name }).join(" · ")
                color: "#5E626B"; font.family: root.fontFamily; font.pixelSize: 10
              }
            }
          }
        }
      }

      // ================================================================ input
      // The reel's prompt box: text on top, "+" (working folder) bottom-left,
      // send bottom-right, the other agents stacked on the side.
      Row {
        id: inputView
        x: root.pad
        y: root.pad
        spacing: 8
        opacity: root.mode === "input" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: root.mode === "input" ? 260 : 120 } }

        readonly property real cardH: Math.max(104, promptFlick.height + 70 + (inputExtras.height > 0 ? inputExtras.height + 12 : 0))

        Rectangle {
          id: inputCard
          width: root.inputW - root.pad * 2 - sideStack.width - inputView.spacing
          height: inputView.cardH
          radius: 24
          color: root.cardColor
          border.width: 1
          border.color: promptEdit.activeFocus ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.05)
          Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

          AgentFace {
            id: inputOrb
            x: 16
            y: 14
            size: 26
            showBadge: false
            glowAlways: true
            tint: root.orbTint("claude", "")
            faceStyle: root.faceStyleFor("claude")
            accessory: root.accessoryFor("claude", "")
            forceReaction: root.forceReaction
            mood: promptEdit.text.length > 0 ? "thinking" : "idle"
          }

          Flickable {
            id: promptFlick
            anchors.left: inputOrb.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.top: parent.top
            anchors.topMargin: 16
            height: Math.max(22, Math.min(promptEdit.contentHeight, 132))
            contentHeight: promptEdit.contentHeight
            clip: true
            interactive: contentHeight > height

            TextEdit {
              id: promptEdit
              width: promptFlick.width
              wrapMode: TextEdit.Wrap
              color: "#F2F3F5"
              selectionColor: "#3B8BFF"
              selectedTextColor: "white"
              font.family: root.fontFamily
              font.pixelSize: 14
              onCursorRectangleChanged: {
                if (cursorRectangle.y + cursorRectangle.height > promptFlick.contentY + promptFlick.height)
                  promptFlick.contentY = cursorRectangle.y + cursorRectangle.height - promptFlick.height
              }
              Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Escape) { root.closeInput(); event.accepted = true }
                else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) { root.pasteInto(promptEdit); event.accepted = true }
                else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                         && !(event.modifiers & Qt.ShiftModifier)) { root.send(); event.accepted = true }
              }
            }

            Text {
              visible: promptEdit.text.length === 0
              text: root.tr("ask.placeholder", { name: root.agentName(root.askAgent) })
              color: "#6E717A"
              font.family: root.fontFamily
              font.pixelSize: 14
            }
          }

          // Pasted images, then who answers and with which model.
          Column {
            id: inputExtras
            anchors.left: promptFlick.left
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.top: promptFlick.bottom
            anchors.topMargin: 10
            spacing: 8
            AttachStrip { width: parent.width }
            Flow {
              width: parent.width
              spacing: 5
              visible: root.chatAgents.length > 1
              Repeater {
                model: root.chatAgents
                MiniPill {
                  required property var modelData
                  label: modelData.name
                  on: root.askAgent === modelData.id
                  onPicked: { root.askAgent = modelData.id; promptEdit.forceActiveFocus() }
                }
              }
            }
            Flow {
              width: parent.width
              spacing: 5
              visible: root.modelChoices(root.askAgent).length > 0
              Repeater {
                model: root.modelChoices(root.askAgent)
                MiniPill {
                  required property string modelData
                  label: modelData === "auto" ? "Auto" : root.capitalize(modelData)
                  tone: "#8B93A1"
                  on: root.askModel === modelData
                  onPicked: { root.askModel = modelData; promptEdit.forceActiveFocus() }
                }
              }
            }
          }

          // "+" = where the assistant works; click to cycle through your projects.
          Rectangle {
            id: dirBtn
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            height: 30
            width: dirRow.implicitWidth + 16
            radius: 15
            color: dirMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.07)
            Row {
              id: dirRow
              anchors.centerIn: parent
              spacing: 7
              Rectangle {
                width: 18; height: 18; radius: 9
                color: Qt.rgba(1, 1, 1, 0.12)
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "+"; color: "#E4E6EA"; font.pixelSize: 13; font.bold: true }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.askDir
                color: "#AEB3BC"
                font.family: root.fontFamily
                font.pixelSize: 11
              }
            }
            MouseArea {
              id: dirMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.askDirIndex = (root.askDirIndex + 1) % root.askDirs.length
                promptEdit.forceActiveFocus()
              }
            }
          }

          MiniPill {
            anchors.left: dirBtn.right
            anchors.leftMargin: 6
            anchors.verticalCenter: dirBtn.verticalCenter
            visible: root.hasDraft
            label: root.tr("ask.discard")
            tone: "#FF6B6B"
            onPicked: root.discardDraft()
          }

          Text {
            anchors.right: sendBtn.left
            anchors.rightMargin: 12
            anchors.verticalCenter: sendBtn.verticalCenter
            text: root.tr("ask.hint")
            color: "#5B5E66"
            font.family: root.fontFamily
            font.pixelSize: 10
          }

          Rectangle {
            id: sendBtn
            readonly property bool ready: promptEdit.text.trim().length > 0 || root.attachments.length > 0
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            width: 34; height: 34; radius: 17
            color: ready ? "#F4F4F5" : Qt.rgba(1, 1, 1, 0.12)
            scale: sendMouse.pressed ? 0.88 : (ready ? 1 : 0.94)
            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            Text {
              anchors.centerIn: parent
              text: "↑"
              color: sendBtn.ready ? "#111113" : "#8A8D96"
              font.pixelSize: 17
              font.bold: true
            }
            MouseArea {
              id: sendMouse
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.send()
            }
          }
        }

        Rectangle {
          id: sideStack
          width: 48
          height: inputView.cardH
          radius: 24
          color: root.cardColor
          Column {
            anchors.centerIn: parent
            spacing: -5
            Repeater {
              model: agentModel
              AgentFace {
                required property string key
                required property string agent
                required property string ident
                required property string state
                required property real updated
                visible: root.clusterKeys.indexOf(key) >= 0
                mini: true
                size: 20
                tint: root.idColor(agent, ident)
                faceStyle: root.faceStyleFor(agent)
                accessory: root.accessoryFor(agent, ident)
                forceReaction: root.forceReaction
                mood: root.moodFor(state, updated)
              }
            }
          }
        }
      }

      // =============================================================== answer
      // the assistant's reply for a notch task, with a bar to keep the conversation
      // going (resumes the same session) or jump into a terminal.
      Rectangle {
        id: answerView
        readonly property var d: root.answerData
        readonly property string mood: d ? root.moodFor(d.state, d.updated) : "idle"
        readonly property bool busy: ["working", "thinking", "upload", "restart"].indexOf(mood) >= 0
        x: root.pad
        y: root.pad
        width: root.answerW - root.pad * 2
        height: answerCol.implicitHeight + 28
        radius: 24
        color: root.cardColor
        opacity: root.mode === "answer" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: root.mode === "answer" ? 280 : 120 } }

        Column {
          id: answerCol
          x: 18
          y: 14
          width: parent.width - 36
          spacing: 12

          Item {
            width: parent.width
            height: 36

            AgentFace {
              id: ansOrb
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              size: 30
              glowAlways: true
              tint: answerView.d ? root.orbTint(answerView.d.agent, answerView.d.ident) : root.orbTint("claude", "")
              faceStyle: root.faceStyleFor(answerView.d ? answerView.d.agent : "claude")
              accessory: root.accessoryFor(answerView.d ? answerView.d.agent : "claude", answerView.d ? answerView.d.ident : "")
              forceReaction: root.forceReaction
              mood: answerView.mood
            }

            Column {
              anchors.left: ansOrb.right
              anchors.leftMargin: 14
              anchors.right: ansButtons.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1
              Row {
                spacing: 8
                Text {
                  text: (answerView.d ? root.agentName(answerView.d.agent) : root.assistantName)
                    + "  ·  " + (answerView.d ? root.stateText[answerView.mood] : "")
                  color: "#F2F3F5"
                  font.family: root.fontFamily
                  font.pixelSize: 13
                  font.weight: Font.DemiBold
                }
                ModelBadge { d: answerView.d; anchors.verticalCenter: parent.verticalCenter }
              }
              Text {
                width: parent.width
                text: answerView.d ? answerView.d.task : ""
                elide: Text.ElideRight
                color: "#7C7F88"
                font.family: root.fontFamily
                font.pixelSize: 11
              }
            }

            Row {
              id: ansButtons
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 6
              Rectangle {
                width: termLbl.implicitWidth + 20; height: 28; radius: 14
                color: termMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                Text { id: termLbl; anchors.centerIn: parent; text: root.tr("answer.terminal"); color: "#D4D4D8"; font.family: root.fontFamily; font.pixelSize: 11 }
                MouseArea { id: termMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.openTerminal(answerView.d) }
              }
              Rectangle {
                width: forgetLbl.implicitWidth + 20; height: 28; radius: 14
                color: forgetMouse.containsMouse ? Qt.rgba(1, 0.35, 0.35, 0.25) : Qt.rgba(1, 1, 1, 0.08)
                Text { id: forgetLbl; anchors.centerIn: parent; text: root.tr("answer.close"); color: "#D4D4D8"; font.family: root.fontFamily; font.pixelSize: 11 }
                MouseArea { id: forgetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.forget(answerView.d.agent, answerView.d.ident) }
              }
              Rectangle {
                width: 28; height: 28; radius: 14
                color: ansClose.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                Text { anchors.centerIn: parent; text: "✕"; color: "#D4D4D8"; font.pixelSize: 12 }
                MouseArea { id: ansClose; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.answerKey = "" }
              }
            }
          }

          Flickable {
            id: ansFlick
            width: parent.width
            height: Math.min(ansText.implicitHeight, 280)
            contentHeight: ansText.implicitHeight
            clip: true
            interactive: contentHeight > height

            Text {
              id: ansText
              width: ansFlick.width
              wrapMode: Text.Wrap
              textFormat: Text.MarkdownText
              text: !answerView.d ? ""
                : answerView.busy ? "_" + root.tr("answer.busy") + "_  " + (answerView.d.detail || "")
                : (answerView.d.answer || answerView.d.detail || "").split("\n")
                    .filter(function (l) { return l.indexOf("🔊") !== 0 }).join("\n")
              color: "#E4E6EA"
              linkColor: "#7FB2FF"
              font.family: root.fontFamily
              font.pixelSize: 13
              lineHeight: 1.15
              onLinkActivated: function (link) { Qt.openUrlExternally(link) }
            }
          }

          AttachStrip { width: parent.width }

          // Model for this chat's next turns (remembered per chat).
          Flow {
            width: parent.width
            spacing: 5
            visible: !!answerView.d && root.modelChoices(answerView.d.agent).length > 0
            Repeater {
              model: answerView.d ? root.modelChoices(answerView.d.agent) : []
              MiniPill {
                required property string modelData
                label: modelData === "auto" ? "Auto" : root.capitalize(modelData)
                tone: "#8B93A1"
                on: !!answerView.d && root.chatModel(answerView.d.key) === modelData
                onPicked: root.setChatModel(answerView.d.key, modelData)
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 42
            radius: 21
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: replyInput.activeFocus ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.06)

            TextInput {
              id: replyInput
              anchors.left: parent.left
              anchors.leftMargin: 18
              anchors.right: replySend.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              color: "#F2F3F5"
              selectionColor: "#3B8BFF"
              font.family: root.fontFamily
              font.pixelSize: 13
              clip: true
              enabled: !answerView.busy
              Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Escape) { root.answerKey = ""; event.accepted = true }
                else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) { root.pasteInto(replyInput); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.reply(); event.accepted = true }
              }
            }
            Text {
              anchors.left: replyInput.left
              anchors.verticalCenter: parent.verticalCenter
              visible: replyInput.text.length === 0
              text: answerView.busy ? root.tr("answer.busy", { name: answerView.d ? root.agentName(answerView.d.agent) : root.assistantName })
                : root.tr("answer.reply", { name: answerView.d ? root.agentName(answerView.d.agent) : root.assistantName })
              color: "#6E717A"
              font.family: root.fontFamily
              font.pixelSize: 13
            }
            Rectangle {
              id: replySend
              readonly property bool ready: replyInput.text.trim().length > 0 || root.attachments.length > 0
              anchors.right: parent.right
              anchors.rightMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              width: 30; height: 30; radius: 15
              color: ready ? "#F4F4F5" : Qt.rgba(1, 1, 1, 0.12)
              Behavior on color { ColorAnimation { duration: 160 } }
              Text { anchors.centerIn: parent; text: "↑"; color: replySend.ready ? "#111113" : "#8A8D96"; font.pixelSize: 15; font.bold: true }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.reply() }
            }
          }
        }
      }
    }
  }
}
