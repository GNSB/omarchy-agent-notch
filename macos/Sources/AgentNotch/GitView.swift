import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

struct Remote: Identifiable { var id: String { name }; var name: String, url: String; var ok: Bool?; var note: String }
struct Commit: Identifiable { var id: String { hash }; var hash: String, subject: String, author: String, date: String }
struct FileChange: Identifiable { var id: String { path }; var code: String, path: String }

/// Git + checksum state for the client. `focus(dir:)` follows whatever chat is open.
@MainActor
final class GitModel: ObservableObject {
    @Published var repos: [String] = []
    @Published var root = ""            // resolved repo top-level ("" = not a repo)
    @Published var asked = ""           // directory that was asked about
    @Published var branch = ""
    @Published var tracking = ""
    @Published var sync = ""
    @Published var files: [FileChange] = []
    @Published var remotes: [Remote] = []
    @Published var commits: [Commit] = []
    @Published var head = ""
    @Published var busy = false
    @Published var checksumFile = ""
    @Published var checksums: [(algo: String, value: String)] = []
    @Published var expected = ""
    private var gen = 0

    static func candidates(_ globs: [String]) -> [String] {
        var out: [String] = [home]
        for g in globs + ["~/Proyectos/*", "~/Projects/*", "~/omarchy-agent-notch"] { out += expandGlob(g) }
        var seen = Set<String>()
        return out.filter { FileManager.default.fileExists(atPath: $0 + "/.git") && seen.insert($0).inserted }
    }

    func scan(_ globs: [String]) { repos = Self.candidates(globs).map(shortPath) }

    /// Repos the open chat actually worked in (its transcript mentions their files), most used first.
    @Published var related: [String] = []
    private var followGen = 0

    /// Follows a chat: its working dir if that's a repo, else the repo it touched the most
    /// (a chat started in ~ that `cd`s into a project still shows that project).
    func follow(ids: [String], dir: String, text: String) {
        followGen += 1; let me = followGen
        let d = (dir.isEmpty ? "~" : dir as NSString).expandingTildeInPath
        Task.detached {
            let touched = Self.touchedRepos(ids: ids, text: text)
            let own = Self.repoRoot(d)
            await MainActor.run {
                guard me == self.followGen else { return }
                self.related = touched
                self.focus(own ?? touched.first ?? d)
            }
        }
    }

    nonisolated static func repoRoot(_ path: String) -> String? {
        var p = (path as NSString).standardizingPath
        let fm = FileManager.default
        while p.count > 1 {
            if fm.fileExists(atPath: p + "/.git") { return p == home ? nil : p }   // a dotfiles repo in ~ would match everything
            p = (p as NSString).deletingLastPathComponent
        }
        return nil
    }

    nonisolated static func touchedRepos(ids: [String], text: String) -> [String] {
        var blob = text
        for id in Set(ids) where !id.isEmpty {
            for f in expandGlob(home + "/.claude/projects/*/").map({ $0 + "/" + id + ".jsonl" })
            where FileManager.default.fileExists(atPath: f) {
                guard let h = FileHandle(forReadingAtPath: f) else { continue }
                let size = (try? h.seekToEnd()) ?? 0
                try? h.seek(toOffset: size > 3_000_000 ? size - 3_000_000 : 0)
                blob += String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
                try? h.close()
            }
        }
        let pattern = "(?:" + NSRegularExpression.escapedPattern(for: home) + "|~)(/[A-Za-z0-9._\\-]+)+"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        var counts: [String: Int] = [:], cache: [String: String?] = [:]
        let ns = blob as NSString
        for m in re.matches(in: blob, range: NSRange(location: 0, length: ns.length)) {
            var p = ns.substring(with: m.range)
            if p.hasPrefix("~") { p = home + p.dropFirst() }
            let dir = (p as NSString).deletingLastPathComponent
            let root: String?
            if let c = cache[dir] { root = c } else { root = repoRoot(p); cache[dir] = root }
            if let root { counts[root, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    func focus(_ dir: String) {
        let d = (dir.isEmpty ? "~" : dir as NSString).expandingTildeInPath
        guard d != asked || root.isEmpty else { return }
        asked = d
        refresh()
    }

    @Published var updatedAt: Date?
    private var timer: Timer?
    private var ticks = 0
    private var lightRunning = false

    /// Keeps the open repo live: status/commits every 3 s, remote connectivity every minute,
    /// only while `isActive()` (the client window is on screen).
    func startAutoRefresh(isActive: @escaping () -> Bool) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, isActive(), !self.root.isEmpty, !self.busy else { return }
                self.ticks += 1
                if self.ticks % 20 == 0 { self.refresh(silent: true) } else { self.refreshLocal() }
            }
        }
    }

    /// Full reload (repo, status, commits, remotes). `silent` skips the spinner.
    func refresh(silent: Bool = false) {
        gen += 1; let me = gen
        if !silent { busy = true }
        let dir = asked
        Task {
            let top = (await Self.git(["rev-parse", "--show-toplevel"], dir)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard me == gen else { return }
            guard !top.hasPrefix("ERR"), !top.isEmpty else { root = ""; files = []; commits = []; remotes = []; busy = false; return }
            root = top
            await loadLocal(top)
            let r = await Self.git(["remote", "-v"], top)
            guard me == gen else { return }
            var seen = Set<String>(), rows: [Remote] = []
            for line in r.split(separator: "\n") where line.hasSuffix("(fetch)") {
                let p = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
                if p.count >= 2, seen.insert(p[0]).inserted {
                    // keep the last result on screen while re-checking, no flicker back to "checking…"
                    let old = remotes.first { $0.name == p[0] && $0.url == p[1] }
                    rows.append(old ?? Remote(name: p[0], url: p[1], ok: nil, note: "checking…"))
                }
            }
            remotes = rows
            busy = false
            for (i, row) in rows.enumerated() {
                let out = await Self.git(["ls-remote", "--exit-code", "--heads", row.name], top, timeout: 12)
                guard me == gen, remotes.indices.contains(i) else { return }
                let ok = !out.hasPrefix("ERR")
                remotes[i].ok = ok
                remotes[i].note = ok ? "connected" : String(out.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first ?? "failed"
            }
        }
    }

    /// Cheap local-only pass: working tree, branch, HEAD and history.
    private func refreshLocal() {
        guard !lightRunning else { return }
        lightRunning = true
        let top = root
        Task {
            await loadLocal(top)
            lightRunning = false
        }
    }

    private func loadLocal(_ top: String) async {
        async let st = Self.git(["status", "--porcelain=v1", "-b"], top)
        async let log = Self.git(["log", "-40", "--pretty=format:%h%x09%s%x09%an%x09%ar"], top)
        async let hd = Self.git(["rev-parse", "--short", "HEAD"], top)
        let (s, l, h) = await (st, log, hd)
        guard top == root else { return }      // switched repo meanwhile
        if !s.hasPrefix("ERR") { parse(s) }
        let newHead = h.hasPrefix("ERR") ? "" : h.trimmingCharacters(in: .whitespacesAndNewlines)
        if newHead != head { head = newHead }
        let cs = l.hasPrefix("ERR") ? [] : l.split(separator: "\n").compactMap { line -> Commit? in
            let p = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return p.count == 4 ? Commit(hash: p[0], subject: p[1], author: p[2], date: p[3]) : nil
        }
        if cs.map(\.hash) != commits.map(\.hash) || cs.first?.date != commits.first?.date { commits = cs }
        updatedAt = Date()
    }

    private func parse(_ s: String) {
        var fs: [FileChange] = []
        for (i, line) in s.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            if i == 0, line.hasPrefix("## ") {
                let t = String(line.dropFirst(3))
                let parts = t.components(separatedBy: "...")
                branch = parts[0].replacingOccurrences(of: "No commits yet on ", with: "")
                tracking = parts.count > 1 ? parts[1].components(separatedBy: " [").first ?? "" : ""
                sync = t.contains("[") ? String(t[t.firstIndex(of: "[")!...].dropFirst().dropLast()) : ""
            } else if line.count > 3 {
                fs.append(FileChange(code: String(line.prefix(2)).trimmingCharacters(in: .whitespaces), path: String(line.dropFirst(3))))
            }
        }
        if fs.map({ $0.code + $0.path }) != files.map({ $0.code + $0.path }) { files = fs }
    }

    func checksum(_ url: URL) {
        checksumFile = url.path
        checksums = []
        Task.detached { [path = url.path] in
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
            func hex<D: Sequence>(_ d: D) -> String where D.Element == UInt8 { d.map { String(format: "%02x", $0) }.joined() }
            let rows = [("SHA-256", hex(SHA256.hash(data: data))), ("SHA-512", hex(SHA512.hash(data: data))),
                        ("SHA-1", hex(Insecure.SHA1.hash(data: data))), ("MD5", hex(Insecure.MD5.hash(data: data)))]
            await MainActor.run { if self.checksumFile == path { self.checksums = rows } }
        }
    }

    nonisolated static func git(_ args: [String], _ dir: String, timeout: Double = 20) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                p.arguments = ["-C", dir] + args
                var env = ProcessInfo.processInfo.environment
                env["GIT_TERMINAL_PROMPT"] = "0"; env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=8"
                p.environment = env
                let out = Pipe(), err = Pipe()
                p.standardOutput = out; p.standardError = err
                guard (try? p.run()) != nil else { cont.resume(returning: "ERR git not found"); return }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
                let o = out.fileHandleForReading.readDataToEndOfFile()
                let e = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: p.terminationStatus == 0 ? String(decoding: o, as: UTF8.self) : "ERR " + String(decoding: e, as: UTF8.self))
            }
        }
    }
}

// MARK: - shared bits

struct Card<C: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder var content: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
                Text(title.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

/// Branch / changes / connections / commits for whichever repo `g` is focused on.
struct GitPanel: View {
    @ObservedObject var m: NotchModel
    @ObservedObject var g: GitModel
    var commitLimit = 8

    var body: some View {
        VStack(spacing: 12) {
            if g.root.isEmpty {
                Card(title: "Git", icon: "arrow.triangle.branch") {
                    Text(g.busy ? "Looking…" : "\(shortPath(g.asked)) is not a git repository.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else {
                Card(title: "Repository", icon: "folder") {
                    HStack(spacing: 6) {
                        Text(shortPath(g.root)).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        if g.busy { ProgressView().controlSize(.mini) }
                        Button { g.refresh() } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22).background(Circle().fill(Color.white.opacity(0.08)))
                        }.buttonStyle(.plain).help("Reload now (it also refreshes on its own every few seconds)")
                    }
                    if let t = g.updatedAt {
                        TimelineView(.periodic(from: .now, by: 5)) { _ in
                            Text("live · updated \(Int(-t.timeIntervalSinceNow))s ago")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 6) {
                        Pill(text: g.branch, icon: "arrow.triangle.branch", tint: m.claudeColor)
                        if !g.head.isEmpty { Pill(text: g.head, icon: "number", tint: .secondary) }
                        if !g.sync.isEmpty { Pill(text: g.sync, icon: "arrow.up.arrow.down", tint: .orange) }
                    }
                    if !g.tracking.isEmpty { Text("tracks \(g.tracking)").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Card(title: g.files.isEmpty ? "Working tree" : "Changes · \(g.files.count)", icon: "doc.badge.gearshape") {
                    if g.files.isEmpty { Label("Clean", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.green) }
                    ForEach(g.files.prefix(commitLimit + 4)) { f in
                        HStack(spacing: 8) {
                            Text(f.code).font(.system(size: 10, weight: .bold, design: .monospaced))
                                .frame(width: 22).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).fill(tone(f.code).opacity(0.2)))
                                .foregroundStyle(tone(f.code))
                            Text(f.path).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    if g.files.count > commitLimit + 4 { Text("+ \(g.files.count - commitLimit - 4) more").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Card(title: "Connections", icon: "network") {
                    if g.remotes.isEmpty { Text("No remotes configured").font(.system(size: 12)).foregroundStyle(.secondary) }
                    ForEach(g.remotes) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 7) {
                                Circle().fill(r.ok == nil ? Color.yellow : (r.ok! ? Color.green : Color.red)).frame(width: 7, height: 7)
                                Text(r.name).font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text(r.note).font(.system(size: 10)).foregroundStyle(r.ok == false ? .red : .secondary).lineLimit(1)
                            }
                            Text(r.url).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                Card(title: "History", icon: "clock.arrow.circlepath") {
                    ForEach(g.commits.prefix(commitLimit)) { c in
                        HStack(alignment: .top, spacing: 8) {
                            Text(c.hash).font(.system(size: 10, design: .monospaced)).foregroundStyle(m.claudeColor).padding(.top, 1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.subject).font(.system(size: 12)).lineLimit(2)
                                Text("\(c.author) · \(c.date)").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func tone(_ c: String) -> Color {
        if c.contains("?") { return .gray }
        if c.contains("D") { return .red }
        if c.contains("A") { return .green }
        return .orange
    }
}

struct Pill: View {
    let text: String; var icon: String? = nil; var tint: Color = .secondary
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.16))).foregroundStyle(tint)
    }
}

/// The full "Tools" tab: pick any repo, see everything for it, verify file checksums.
struct GitToolsView: View {
    @ObservedObject var m: NotchModel
    @ObservedObject var g: GitModel
    @State private var picking = false

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    Card(title: "Repository", icon: "externaldrive") {
                        HStack {
                            Menu {
                                ForEach(g.repos, id: \.self) { r in Button(r) { g.focus(r) } }
                            } label: { Label(g.root.isEmpty ? "Choose repo" : shortPath(g.root), systemImage: "folder") }
                            Button { g.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            if g.busy { ProgressView().controlSize(.small) }
                        }
                    }
                    GitPanel(m: m, g: g, commitLimit: 40)
                }.frame(maxWidth: .infinity)
                VStack(spacing: 12) { checksumCard }.frame(width: 340)
            }.padding(20)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { if case .success(let u) = $0 { g.checksum(u) } }
    }

    private var checksumCard: some View {
        Card(title: "Checksum", icon: "checkmark.seal") {
            Button { picking = true } label: { Label("Choose file…", systemImage: "doc") }
            if !g.checksumFile.isEmpty { Text(shortPath(g.checksumFile)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            ForEach(g.checksums, id: \.algo) { c in
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.algo).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Text(c.value).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                }
            }
            if !g.checksums.isEmpty {
                TextField("Paste expected checksum", text: $g.expected).textFieldStyle(.roundedBorder)
                let e = g.expected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !e.isEmpty {
                    let ok = g.checksums.contains { $0.value == e }
                    Label(ok ? "Match" : "Does not match", systemImage: ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ok ? .green : .red)
                }
            }
        }
    }
}
