import SwiftUI
import AppKit
import Darwin

// MARK: - helpers

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
    let na = NSColor(a).usingColorSpace(.sRGB) ?? .white
    let nb = NSColor(b).usingColorSpace(.sRGB) ?? .white
    return Color(nsColor: na.blended(withFraction: CGFloat(t), of: nb) ?? na)
}

func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

func expandGlob(_ pattern: String) -> [String] {
    var g = glob_t()
    defer { globfree(&g) }
    guard glob((pattern as NSString).expandingTildeInPath, GLOB_TILDE | GLOB_MARK, nil, &g) == 0 else { return [] }
    return (0..<Int(g.gl_pathc)).compactMap { i -> String? in
        guard let p = g.gl_pathv[i] else { return nil }
        let s = String(cString: p)
        return s.hasSuffix("/") ? String(s.dropLast()) : nil
    }.sorted()
}

let home = NSHomeDirectory()


func shortPath(_ p: String) -> String { p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p }

// MARK: - data

struct Agent: Identifiable, Equatable {
    var key: String, agent: String, ident: String, name: String
    var state: String, task: String, detail: String, cwd: String
    var answer: String, source: String
    var since: Double, updated: Double
    var id: String { key }
}

struct DetectedAgent: Identifiable, Equatable {
    var id: String, name: String, path: String, version: String
    var installed: Bool, connected: Bool
}

struct UsageInfo: Equatable {
    var sessionTokens = 0, sessionWindow = 0
    var sessionPct: Double?
    var monthTokens = 0, monthBudget = 0
    var monthPct: Double?
}

enum Mode { case collapsed, expanded, alert, input, answer, custom, detect }

struct NotchGeometry {
    var notchW: CGFloat = 0
    var notchH: CGFloat = 32
    var hasNotch = false
}

// MARK: - config + strings

final class Config {
    private(set) var raw: [String: Any] = [:]
    private var i18n: [String: [String: String]] = [:]
    private var stamp: [Date?] = [nil, nil]

    let configPath = ProcessInfo.processInfo.environment["AGENT_NOTCH_CONFIG"]
        ?? home + "/.config/agent-notch/config.json"
    lazy var i18nPath: String = {
        let env = ProcessInfo.processInfo.environment["AGENT_NOTCH_I18N"]
        let candidates = [env, home + "/.config/agent-notch/i18n.json",
                          home + "/.config/omarchy/plugins/myzk.notch/i18n.json"].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
    }()

    private func mtime(_ p: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date
    }

    /// Reloads when either file changed. Returns true if anything was reloaded.
    @discardableResult
    func reloadIfNeeded() -> Bool {
        let now = [mtime(configPath), mtime(i18nPath)]
        if now == stamp { return false }
        stamp = now
        raw = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: configPath))))
            as? [String: Any] ?? [:]
        i18n = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: i18nPath))))
            as? [String: [String: String]] ?? [:]
        return true
    }

    func str(_ k: String, _ d: String) -> String { raw[k] as? String ?? d }
    func num(_ k: String, _ d: Double) -> Double { (raw[k] as? NSNumber)?.doubleValue ?? d }
    func bool(_ k: String, _ d: Bool) -> Bool { raw[k] as? Bool ?? d }
    func list(_ k: String, _ d: [String]) -> [String] { Self.asList(raw[k]) ?? d }
    /// Accepts a single name or a list of names.
    static func asList(_ v: Any?) -> [String]? {
        if let l = v as? [String] { return l }
        if let s = v as? String { return s.isEmpty ? [] : [s] }
        return nil
    }

    /// Writes one key to config.json; the mtime poll then reloads it.
    func save(_ key: String, _ value: Any) {
        var r = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: configPath)))) as? [String: Any] ?? [:]
        r[key] = value
        guard let data = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(atPath: (configPath as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        raw = r
    }

    func tr(_ key: String, _ vars: [String: String] = [:]) -> String {
        let overrides = raw["strings"] as? [String: String] ?? [:]
        var t = overrides[key] ?? i18n[str("language", "en")]?[key] ?? i18n["en"]?[key] ?? key
        t = t.replacingOccurrences(of: "{name}", with: str("assistantName", "Claude"))
        for (k, v) in vars { t = t.replacingOccurrences(of: "{\(k)}", with: v) }
        return t
    }
}

// MARK: - model

@MainActor
final class NotchModel: ObservableObject {
    static let shared = NotchModel()

    let cfg = Config()
    @Published var geometry = NotchGeometry()
    @Published var agents: [Agent] = []
    @Published var now = Date().timeIntervalSince1970
    @Published var hovered = false
    @Published var pinned = false
    @Published var pickedKey = ""
    @Published var alertKey = ""
    @Published var inputOpen = false
    @Published var answerKey = ""
    @Published var askDirs: [String] = ["~"]
    @Published var askDirIndex = 0
    @Published var cfgVersion = 0
    @Published var customOpen = false
    @Published var customTarget = "claude"      // "claude" | "grok"
    @Published var customMood = "idle"
    @Published var reactions: [String: String] = [:]
    @Published var attachments: [String] = []
    @Published var askAgent = "claude"
    @Published var detectOpen = false
    @Published var detecting = false
    @Published var detected: [DetectedAgent] = []
    @Published var usage: UsageInfo?
    private var usageStamp = 0.0
    private var usageKey = "-"
    private let usageTool = home + "/.local/bin/claude-usage"
    private var pokes: [String: (count: Int, last: Date)] = [:]
    private var reactionTasks: [String: Task<Void, Never>] = [:]
    /// Size of the drawn notch, used by the window to decide which clicks fall through.
    var hitSize = CGSize(width: 200, height: 32)

    private var hist: [String: String] = [:]
    private var lastStates: [String: String]?
    private var colorMap: [String: Color] = [:]
    private var nextColor = 0
    private var stateStamp: Date?
    private var alertTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?

    private let stateFile = (ProcessInfo.processInfo.environment["XDG_STATE_HOME"] ?? home + "/.local/state")
        + "/myzk-agents/summary.json"
    private let backend = ProcessInfo.processInfo.environment["AGENT_NOTCH_BACKEND"]
        ?? home + "/.local/bin/myzk-agents"

    // MARK: config accessors
    var assistantName: String { cfg.str("assistantName", "Claude") }
    var notchColor: Color { Color(hex: cfg.str("notchColor", "#000000")) }
    var cardColor: Color { Color(hex: cfg.str("cardColor", "#18181B")) }
    var claudeColor: Color { Color(hex: cfg.str("claudeColor", "#E0784F")) }
    var palette: [String] {
        cfg.list("palette", ["#35C2AE", "#8B6CF6", "#4C9AFF", "#EC6FB3", "#F2C94C",
                             "#7ED957", "#F0544F", "#5AD1E6", "#C084FC", "#FF9F5A"])
    }
    var fontFamily: String? {
        let f = cfg.str("fontFamily", "")
        return (f.isEmpty || f == "Noto Sans") ? nil : f
    }
    func tr(_ k: String, _ v: [String: String] = [:]) -> String { cfg.tr(k, v) }

    // face style + accessories (per bot override > grok/claude default)
    var faceStyle: String { cfg.str("faceStyle", "orb") }
    var grokFaceStyle: String { cfg.str("grokFaceStyle", faceStyle) }
    var accessory: [String] { cfg.list("accessory", []) }
    var grokAccessory: [String] { cfg.list("grokAccessory", accessory) }

    func style(_ a: Agent?) -> String {
        guard let a else { return faceStyle }
        return a.agent == "claude" ? faceStyle : grokFaceStyle
    }
    func gear(_ a: Agent?) -> [String] {
        guard let a else { return accessory }
        if let own = Config.asList((cfg.raw["accessories"] as? [String: Any])?[a.ident]) { return own }
        return a.agent == "claude" ? accessory : grokAccessory
    }
    func reaction(_ a: Agent?) -> String { a.flatMap { reactions[$0.key] } ?? "" }

    static let stateColor: [String: Color] = [
        "idle": Color(hex: "#8B93A1"), "thinking": Color(hex: "#A78BFA"), "working": Color(hex: "#5B9DFF"),
        "waiting": Color(hex: "#F5B544"), "done": Color(hex: "#3DD68C"), "error": Color(hex: "#FF6B6B"),
        "sleep": Color(hex: "#6B7280"), "errorStale": Color(hex: "#FF6B6B"),
        "upload": Color(hex: "#22D3EE"), "restart": Color(hex: "#D946EF"),
    ]
    private static let rank: [String: Double] = [
        "waiting": 6, "error": 5, "errorStale": 1.5, "upload": 4.2, "working": 4, "restart": 3.5, "thinking": 3, "done": 2, "idle": 1, "sleep": 0,
    ]

    // MARK: lifecycle

    func start() {
        cfg.reloadIfNeeded()
        rescan()
        pollState(force: true)
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        if cfg.reloadIfNeeded() { cfgVersion += 1 }
        pollState(force: false)
        let t = Date().timeIntervalSince1970
        if Int(t) != Int(now) { now = t }
        if mode != .collapsed && mode != .custom { refreshUsageIfStale(t) }
    }

    // MARK: usage (context of the focused session + tokens this month)

    private func refreshUsageIfStale(_ t: Double) {
        let sid = ((alertAgent ?? answerAgent ?? focus).flatMap { $0.agent == "claude" ? $0.ident : nil }) ?? ""
        guard sid != usageKey || t - usageStamp > 20 else { return }
        usageKey = sid
        usageStamp = t
        let tool = usageTool
        Task.detached { [weak self] in
            let info = Self.runUsage(tool, sid)
            await self?.setUsage(info)
        }
    }

    private func setUsage(_ info: UsageInfo?) { if let info { usage = info } }

    nonisolated private static func runUsage(_ tool: String, _ sid: String) -> UsageInfo? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = sid.isEmpty ? [] : ["--session", sid]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func n(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        var u = UsageInfo()
        if let s = j["session"] as? [String: Any] {
            u.sessionTokens = Int(n(s["tokens"]) ?? 0)
            u.sessionWindow = Int(n(s["window"]) ?? 0)
            u.sessionPct = n(s["pct"])
        }
        if let m = j["month"] as? [String: Any] {
            u.monthTokens = Int(n(m["total"]) ?? 0)
            u.monthBudget = Int(n(m["budget"]) ?? 0)
            u.monthPct = n(m["pct"])
        }
        return u
    }

    private func pollState(force: Bool) {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: stateFile))?[.modificationDate] as? Date
        if !force && stamp == stateStamp { return }
        stateStamp = stamp
        let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile))
        let map = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["agents"]
            as? [String: [String: Any]] ?? [:]
        ingest(map)
    }

    private func ingest(_ map: [String: [String: Any]]) {
        func s(_ v: Any?) -> String { v.map { "\($0)" } ?? "" }
        func d(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
        let old = Dictionary(uniqueKeysWithValues: agents.map { ($0.key, $0) })
        var rows: [Agent] = []
        var states: [String: String] = [:]
        for key in map.keys.sorted() {
            let a = map[key]!
            let row = Agent(key: key, agent: s(a["agent"]), ident: s(a["id"]),
                            name: s(a["name"] ?? a["id"]), state: a["state"] == nil ? "idle" : s(a["state"]),
                            task: s(a["task"]), detail: s(a["detail"]), cwd: s(a["cwd"]),
                            answer: s(a["answer"]), source: s(a["source"]),
                            since: d(a["since"]), updated: d(a["updated"]))
            if let prev = old[key] {
                if prev.detail != row.detail && !prev.detail.isEmpty { hist[key] = prev.detail }
            } else if row.agent != "claude" && colorMap[key] == nil {
                colorMap[key] = Color(hex: palette[nextColor % palette.count])
                nextColor += 1
            }
            rows.append(row)
            states[key] = row.state
            if let before = lastStates?[key], before != row.state,
               ["waiting", "done", "error"].contains(row.state) {
                raiseAlert(key)
            }
        }
        lastStates = states
        if rows != agents { agents = rows }
        if !alertKey.isEmpty && !states.keys.contains(alertKey) { alertKey = "" }
        if !answerKey.isEmpty && !states.keys.contains(answerKey) { answerKey = "" }
    }

    private func raiseAlert(_ key: String) {
        alertKey = key
        alertTask?.cancel()
        let ms = cfg.num("alertMs", 7000)
        alertTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
            if !Task.isCancelled { self?.alertKey = "" }
        }
    }

    // MARK: derived state

    func moodFor(_ state: String, _ updated: Double) -> String {
        let age = now - updated
        switch state {
        case "done":
            return age < cfg.num("doneGlow", 90) ? "done" : (age > cfg.num("sleepAfter", 600) ? "sleep" : "idle")
        case "idle": return age > cfg.num("sleepAfter", 600) ? "sleep" : "idle"
        case "error": return age > cfg.num("errorLoud", 120) ? "errorStale" : "error"
        default: return state
        }
    }

    func mood(_ a: Agent) -> String { moodFor(a.state, a.updated) }
    private func score(_ a: Agent) -> Double { (Self.rank[mood(a)] ?? 0) * 1e10 + a.updated }

    var claudes: [Agent] { agents.filter { $0.agent == "claude" } }
    var others: [Agent] { agents.filter { $0.agent != "claude" } }
    var mainClaude: Agent? { claudes.max { score($0) < score($1) } }
    var cluster: [Agent] { Array(others.sorted { score($0) > score($1) }.prefix(4)) }
    var primary: Agent? { agents.max { score($0) < score($1) } }
    var focus: Agent? { agent(pickedKey) ?? primary }
    var alertAgent: Agent? { agent(alertKey) }
    var answerAgent: Agent? { agent(answerKey) }
    func agent(_ key: String) -> Agent? { key.isEmpty ? nil : agents.first { $0.key == key } }
    func previousStep(_ a: Agent) -> String { hist[a.key] ?? "" }

    var mode: Mode {
        if customOpen { return .custom }
        if detectOpen { return .detect }
        if inputOpen { return .input }
        if answerAgent != nil { return .answer }
        if hovered || pinned { return .expanded }
        if alertAgent != nil { return .alert }
        return .collapsed
    }

    func displayName(_ a: Agent) -> String {
        if a.agent != "claude" { return a.name }
        return claudes.count > 1 ? "\(assistantName) · \(a.name)" : assistantName
    }

    func tint(_ a: Agent?) -> Color {
        guard let a else { return Color(hex: "#EEF2F7") }
        let base = Color(hex: "#EEF2F7")
        if a.agent == "claude" { return mix(base, claudeColor, 0.28) }
        return mix(base, colorMap[a.key] ?? Color(hex: palette[0]), 0.16)
    }

    func miniTint(_ a: Agent) -> Color {
        a.agent == "claude" ? claudeColor : (colorMap[a.key] ?? Color(hex: palette[0]))
    }

    func ago(_ t: Double) -> String {
        let s = max(0, Int(now - (t > 0 ? t : now)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h" + String(format: "%02d", s % 3600 / 60)
    }

    // MARK: interaction

    func setHover(_ on: Bool) {
        hoverTask?.cancel()
        if on {
            hovered = true
        } else {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 280_000_000)
                if !Task.isCancelled { self?.hovered = false; self?.pickedKey = "" }
            }
        }
    }

    func openInput() {
        customOpen = false
        alertKey = ""
        answerKey = ""
        inputOpen = true
        var dirs = ["~"]
        for g in cfg.list("projectDirs", ["~/Projects/*"]) { dirs += expandGlob(g).map(shortPath) }
        askDirs = dirs
        askDirIndex = 0
        AppDelegate.shared?.makeKey()
    }

    /// What tapping the pet in the agents view does: "chat" | "terminal" | "play".
    var petTap: String { cfg.str("petTap", "chat") }
    func setPetTap(_ v: String) { cfg.save("petTap", v); cfgVersion += 1 }
    func tapPet(_ a: Agent) {
        switch petTap {
        case "terminal": openTerminal(a)
        case "play": poke(a.key)
        default: openChat(a)
        }
    }

    /// Opens an agent's conversation: its conversation if it was started from the notch, else a fresh question.
    func openChat(_ a: Agent) {
        if a.source == "notch" { alertKey = ""; answerKey = a.key; AppDelegate.shared?.makeKey() }
        else { openInput() }
    }

    func closeInput() { inputOpen = false; attachments = [] }
    func openCustom() {
        detectOpen = false
        alertKey = ""; answerKey = ""; inputOpen = false
        customOpen = true; pinned = true
    }
    func closeCustom() { customOpen = false }

    /// Clicks on a face: 3 quick ones annoy it, 6 make it dizzy.
    func poke(_ key: String) {
        let n = Date()
        var e = pokes[key] ?? (0, n)
        e.count = n.timeIntervalSince(e.last) < 0.7 ? e.count + 1 : 1
        e.last = n
        pokes[key] = e
        if e.count >= 6 { react(key, "dizzy", 2.4); pokes[key] = (0, n) }
        else if e.count >= 3 { react(key, "annoyed", 1.6) }
    }

    func react(_ key: String, _ kind: String, _ secs: Double) {
        reactions[key] = kind
        reactionTasks[key]?.cancel()
        reactionTasks[key] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(secs * 1e9))
            if !Task.isCancelled { self?.reactions[key] = nil }
        }
    }

    func toggleGear(_ name: String) {
        let key = customTarget == "claude" ? "accessory" : "grokAccessory"
        var cur = customTarget == "claude" ? accessory : grokAccessory
        if let i = cur.firstIndex(of: name) { cur.remove(at: i) } else { cur.append(name) }
        cfg.save(key, cur); cfgVersion += 1
    }
    func clearGear() {
        cfg.save(customTarget == "claude" ? "accessory" : "grokAccessory", [String]()); cfgVersion += 1
    }
    func setStyle(_ name: String) {
        cfg.save(customTarget == "claude" ? "faceStyle" : "grokFaceStyle", name); cfgVersion += 1
    }
    func setColor(_ hex: String) {
        cfg.save("claudeColor", hex); cfgVersion += 1
    }

    /// Agents the notch can chat with headlessly (Claude always; Codex when it was detected).
    var chatAgents: [(id: String, name: String)] {
        var l = [("claude", assistantName)]
        if detected.contains(where: { $0.id == "codex" && $0.installed }) { l.append(("codex", "Codex")) }
        return l
    }

    func openDetect() {
        alertKey = ""; answerKey = ""; inputOpen = false; customOpen = false
        detectOpen = true; pinned = true
        rescan()
    }
    func closeDetect() { detectOpen = false; pinned = false }

    func rescan() {
        guard !detecting else { return }
        detecting = true
        let backend = self.backend
        Task.detached { [weak self] in
            let rows = Self.runDetect(backend)
            await self?.setDetected(rows)
        }
    }
    private func setDetected(_ rows: [DetectedAgent]) { detected = rows; detecting = false }

    nonisolated private static func runDetect(_ backend: String) -> [DetectedAgent] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: backend)
        p.arguments = ["detect"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        return list.map { d in
            DetectedAgent(id: d["id"] as? String ?? "", name: d["name"] as? String ?? "", path: d["path"] as? String ?? "",
                          version: d["version"] as? String ?? "", installed: d["installed"] as? Bool ?? false,
                          connected: d["connected"] as? Bool ?? false)
        }
    }

    func closeAll() { detectOpen = false; customOpen = false; inputOpen = false; answerKey = ""; pinned = false; alertKey = "" }
    func toggle() { pinned.toggle(); if !pinned { pickedKey = "" } }
    func cycleDir() { askDirIndex = (askDirIndex + 1) % max(askDirs.count, 1) }
    var askDir: String { askDirs.indices.contains(askDirIndex) ? askDirs[askDirIndex] : "~" }

    func showLast() {
        if let a = agents.filter({ $0.source == "notch" }).max(by: { $0.updated < $1.updated }) {
            answerKey = a.key
            AppDelegate.shared?.makeKey()
        }
    }

    func alertTapped() {
        guard let a = alertAgent else { return }
        alertKey = ""
        if a.source == "notch" && !a.answer.isEmpty { answerKey = a.key; AppDelegate.shared?.makeKey() }
    }

    // MARK: attachments (pasted images / copied image files)

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]

    /// Returns true if the clipboard held something to attach (and so ⌘V shouldn't paste text).
    func attachFromPasteboard() -> Bool {
        let pb = NSPasteboard.general
        let files = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter { Self.imageExts.contains($0.pathExtension.lowercased()) }
        if !files.isEmpty { attachments += files.map(\.path); return true }
        // every image on the clipboard, not just the first (e.g. several copied from Preview/Photos)
        let imgs = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage] ?? []
        guard pb.string(forType: .string) == nil, !imgs.isEmpty else { return false }
        let dir = home + "/.local/state/myzk-agents/pastes"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var added = false
        for (i, img) in imgs.enumerated() {
            guard let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            let path = dir + "/paste-\(Int(Date().timeIntervalSince1970 * 1000))-\(i).png"
            if (try? png.write(to: URL(fileURLWithPath: path))) != nil { attachments.append(path); added = true }
        }
        return added
    }

    private func withAttachments(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { attachments = [] }
        guard !attachments.isEmpty else { return t }
        return (t.isEmpty ? "Look at the attached image(s)." : t) + "\n\n"
            + attachments.map { "[attached image: \($0)]" }.joined(separator: "\n")
    }

    func send(_ text: String) {
        let t = withAttachments(text)
        guard !t.isEmpty else { return }
        let id = UUID().uuidString.lowercased()
        let dir = (askDir as NSString).expandingTildeInPath
        let who = chatAgents.contains { $0.id == askAgent } ? askAgent : "claude"
        runBackend(["ask", t, "--id", id, "--agent", who], cwd: dir)
        pickedKey = who + ":" + id
        inputOpen = false
    }

    func reply(_ text: String) {
        guard let a = answerAgent else { return }
        let t = withAttachments(text)
        guard !t.isEmpty else { return }
        runBackend(["ask", t, "--resume", a.ident, "--agent", a.agent], cwd: a.cwd.isEmpty ? home : a.cwd)
    }

    func forget(_ a: Agent) {
        if pickedKey == a.key { pickedKey = "" }
        if answerKey == a.key { answerKey = "" }
        runBackend(["rm", a.agent, a.ident], cwd: home)
    }

    private func runBackend(_ args: [String], cwd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: backend)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin"]
            .joined(separator: ":")
        env["MYZK_NOTCH_CWD"] = cwd
        p.environment = env
        try? p.run()
    }

    func openTerminal(_ a: Agent) {
        let claude = cfg.str("claudeCommand", "claude")
        let dir = a.cwd.isEmpty ? home : a.cwd
        let cmd = a.agent == "codex"
            ? "cd \(shellQuote(dir)) && codex resume --last"
            : "cd \(shellQuote(dir)) && \(claude) --resume \(a.ident)"
        let term = cfg.str("terminal", "")
        let p = Process()
        if term.isEmpty || term.contains("xdg-terminal-exec") {
            let esc = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "tell application \"Terminal\" to activate",
                           "-e", "tell application \"Terminal\" to do script \"\(esc)\""]
        } else {
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", "\(term) zsh -lc \(shellQuote(cmd))"]
        }
        try? p.run()
        answerKey = ""
    }
}
