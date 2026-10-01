import SwiftUI

/// The notch's own client window: conversations on the left, the chat in the middle,
/// and a git inspector on the right that follows the working directory of the open chat.
struct ClientView: View {
    @ObservedObject var m: NotchModel
    @StateObject private var g = GitModel()
    @State private var selected = ""      // "" = new chat
    @State private var text = ""
    @State private var tab = 0            // 0 chat · 1 tools
    @State private var inspector = true

    private var current: Agent? { m.agent(selected) }
    private var rows: [Agent] { m.agents.sorted { $0.updated > $1.updated } }
    private var chatDir: String { current.map { $0.cwd.isEmpty ? "~" : $0.cwd } ?? m.askDir }

    var body: some View {
        let _ = m.cfgVersion
        HStack(spacing: 0) {
            sidebar.frame(width: 250)
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            VStack(spacing: 0) {
                topBar
                if tab == 0 {
                    HStack(spacing: 0) {
                        chat
                        if inspector {
                            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
                            ScrollView {
                                VStack(spacing: 12) {
                                    if g.related.count > 1 || (!g.root.isEmpty && !g.related.isEmpty && g.related.first != g.root) {
                                        Menu {
                                            ForEach(g.related, id: \.self) { r in Button(shortPath(r)) { g.focus(r) } }
                                        } label: { Label("Repos in this chat · \(g.related.count)", systemImage: "square.stack.3d.up") }
                                            .menuStyle(.borderlessButton).font(.system(size: 11, weight: .semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    GitPanel(m: m, g: g)
                                }.padding(14)
                            }.frame(width: 300)
                                .background(Color.black.opacity(0.12))
                        }
                    }
                } else {
                    GitToolsView(m: m, g: g)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 600)
        .background(LinearGradient(colors: [m.cardColor, Color(hex: "#0E0E11")], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
        .onAppear {
            m.rescan(); refreshDirs()
            g.scan(m.cfg.list("projectDirs", ["~/Projects/*"])); followChat()
        }
        .onChange(of: selected) { _ in followChat() }
        .onChange(of: current?.updated) { _ in followChat() }
        .onChange(of: m.askDirIndex) { _ in if current == nil { followChat() } }
        .onChange(of: m.askDirs) { _ in if current == nil { followChat() } }
    }

    // MARK: top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $tab) {
                Label("Chat", systemImage: "bubble.left.and.bubble.right").tag(0)
                Label("Git & Checksum", systemImage: "arrow.triangle.branch").tag(1)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 300)
            Spacer()
            if tab == 0 {
                Button { withAnimation(.smooth(duration: 0.25)) { inspector.toggle() } } label: {
                    Image(systemName: "sidebar.right").font(.system(size: 14))
                        .foregroundStyle(inspector ? m.claudeColor : .secondary)
                }.buttonStyle(.plain).help("Git inspector")
            }
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
    }

    // MARK: sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 34)   // traffic lights
            Button { selected = ""; m.newChat() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text("New chat").font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected.isEmpty ? m.claudeColor.opacity(0.28) : Color.white.opacity(0.06)))
                .foregroundStyle(selected.isEmpty ? m.claudeColor : Color.primary)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 10)

            Text("CONVERSATIONS").font(.system(size: 10, weight: .bold)).tracking(0.8)
                .foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 6)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(rows) { a in
                        let on = selected == a.key
                        HStack(spacing: 10) {
                            FaceView(mood: m.mood(a), tint: m.tint(a), size: 20, glowAlways: false,
                                     style: m.style(a), accessory: m.gear(a)).frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.task.isEmpty ? m.displayName(a) : a.task)
                                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(shortPath(a.cwd.isEmpty ? "~" : a.cwd) + " · " + m.ago(a.updated))
                                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Color.white.opacity(0.1) : .clear))
                        .onTapGesture { selected = a.key; tab = 0 }
                        .contextMenu {
                            Button("Open in Terminal") { m.openTerminal(a) }
                            Button("Forget") { m.forget(a); if selected == a.key { selected = "" } }
                        }
                    }
                }.padding(.horizontal, 12)
            }
        }
        .background(.ultraThinMaterial.opacity(0.5)).background(Color.black.opacity(0.3))
    }

    // MARK: chat

    private var chat: some View {
        VStack(spacing: 0) {
            if let a = current { conversation(a) } else { welcome }
            composer
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            FaceView(mood: "idle", tint: m.claudeColor, size: 54, glowAlways: true, style: m.style(nil), accessory: m.gear(nil))
                .frame(width: 64, height: 64)
            Text("Ask \(m.chatAgents.first { $0.id == m.askAgent }?.name ?? m.assistantName)")
                .font(.system(size: 22, weight: .semibold))
            Text("Working in \(shortPath(m.askDir))").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private func conversation(_ a: Agent) -> some View {
        let busy = ["working", "thinking", "upload", "restart"].contains(m.mood(a))
        let turns = m.turns(a)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(m.displayName(a)).font(.system(size: 14, weight: .semibold))
                ModelBadge(a: a)
                Spacer()
                Button { m.openTerminal(a) } label: { Label("Terminal", systemImage: "terminal").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }.padding(.horizontal, 22).padding(.vertical, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(turns) { t in
                            userBubble(t.q)
                            agentBubble(a, Text(markdown(t.a)), error: t.error)
                        }
                        if busy {
                            if !a.task.isEmpty { userBubble(a.task) }
                            agentBubble(a, Text(m.tr("answer.busy", ["name": m.assistantName])), busy: true)
                        } else if turns.isEmpty {
                            // chats from before transcripts existed, or terminal sessions: last turn only
                            if !a.task.isEmpty { userBubble(a.task) }
                            agentBubble(a, a.answer.isEmpty ? Text(a.detail.isEmpty ? "No answer yet." : a.detail) : Text(markdown(a.answer)),
                                        dim: a.answer.isEmpty)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(22)
                }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: turns.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: busy) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
    }

    /// Prompt text with "[attached image: …]" lines shown as thumbnails.
    private func userBubble(_ q: String) -> some View {
        let lines = q.components(separatedBy: "\n")
        let images = lines.compactMap { l -> String? in
            guard l.hasPrefix("[attached image: "), l.hasSuffix("]") else { return nil }
            return String(l.dropFirst(17).dropLast())
        }
        let body = lines.filter { !($0.hasPrefix("[attached image: ") && $0.hasSuffix("]")) }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack { Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 8) {
                if !images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(images, id: \.self) { p in
                            if let img = NSImage(contentsOfFile: p) {
                                Image(nsImage: img).resizable().scaledToFill().frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
                if !body.isEmpty {
                    Text(body).font(.system(size: 13)).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(m.claudeColor.opacity(0.22)))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func agentBubble(_ a: Agent, _ content: Text, busy: Bool = false, error: Bool = false, dim: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            FaceView(mood: busy ? m.mood(a) : (error ? "error" : "idle"), tint: m.tint(a), size: 22, glowAlways: busy,
                     style: m.style(a), accessory: m.gear(a))
                .frame(width: 28, height: 28)
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                content.textSelection(.enabled)
            }
            .foregroundStyle(busy || dim ? Color.secondary : (error ? Color(hex: "#FF8A8A") : Color.primary))
            .font(.system(size: 13.5)).lineSpacing(3)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
            Spacer(minLength: 40)
        }
    }

    /// Terminal sessions are owned by their terminal: resuming them headless from here would
    /// run a second process on the same conversation, so the client only offers to jump there.
    @ViewBuilder private var composer: some View {
        if let a = current, a.source != "notch" {
            HStack(spacing: 10) {
                Image(systemName: "terminal").foregroundStyle(.secondary)
                Text("This session lives in a terminal.").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Open in Terminal") { m.openTerminal(a) }
                Button("New chat here") { if let i = m.askDirs.firstIndex(of: shortPath(a.cwd)) { m.askDirIndex = i }; selected = ""; m.newChat() }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
            .padding(.horizontal, 20).padding(.bottom, 16).padding(.top, 6)
        } else { input }
    }

    private var input: some View {
        VStack(spacing: 8) {
            AttachmentStrip(m: m, size: 54)
            HStack(spacing: 8) {
                if current == nil {
                    Menu {
                        ForEach(m.chatAgents, id: \.id) { c in Button(c.name) { m.askAgent = c.id } }
                    } label: { Pill(text: m.chatAgents.first { $0.id == m.askAgent }?.name ?? "Claude", icon: "sparkles", tint: m.claudeColor) }
                        .menuStyle(.borderlessButton).fixedSize()
                    Menu {
                        ForEach(Array(m.askDirs.enumerated()), id: \.offset) { i, d in Button(d) { m.askDirIndex = i } }
                    } label: { Pill(text: m.askDir, icon: "folder", tint: .secondary) }
                        .menuStyle(.borderlessButton).fixedSize()
                }
                ModelPicker(m: m, agent: current?.agent ?? m.askAgent, chat: current?.key)
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(current == nil ? "Message…" : m.tr("answer.reply", ["name": m.assistantName]), text: $text, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...6).onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(canSend ? m.claudeColor : Color.white.opacity(0.12)))
                        .foregroundStyle(canSend ? Color.black : Color.secondary)
                }.buttonStyle(.plain).disabled(!canSend)
            }
            .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .padding(.horizontal, 20).padding(.bottom, 16).padding(.top, 6)
    }

    /// Points the git inspector at the open chat (or the folder picked for a new one).
    private func followChat() {
        guard let a = current else { g.related = []; g.focus(chatDir); return }
        let text = m.turns(a).map { $0.q + "\n" + $0.a }.joined(separator: "\n") + a.answer
        g.follow(ids: [a.ident, a.session], dir: chatDir, text: text)
    }

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !m.attachments.isEmpty }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        text = ""
        if let a = current { m.reply(t, to: a) }
        else if let k = m.start(t, agent: m.askAgent, dir: m.askDir) { selected = k }
    }

    private func refreshDirs() {
        var dirs = ["~"]
        for g in m.cfg.list("projectDirs", ["~/Projects/*"]) + ["~/Proyectos/*"] {
            for d in expandGlob(g).map(shortPath) where !dirs.contains(d) { dirs.append(d) }
        }
        m.askDirs = dirs
    }

    private func markdown(_ s: String) -> AttributedString {
        let clean = s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("🔊") }.joined(separator: "\n")
        return (try? AttributedString(markdown: clean, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(clean)
    }
}
