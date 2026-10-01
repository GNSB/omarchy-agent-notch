import SwiftUI

struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = min(radius, r.height / 2, r.width / 2)
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct NotchRoot: View {
    @ObservedObject var m: NotchModel
    @State private var pointer: CGPoint?

    private var width: CGFloat {
        switch m.mode {
        case .collapsed: return (m.geometry.hasNotch ? m.geometry.notchW : 150) + 104
        case .expanded: return 580
        case .alert: return 540
        case .input: return 580
        case .answer: return 600
        case .custom: return 580
        case .detect: return 580
        }
    }

    var body: some View {
        let _ = m.cfgVersion
        VStack(spacing: 0) {
            header
            switch m.mode {
            case .collapsed: EmptyView()
            case .expanded: ExpandedBody(m: m).transition(.opacity)
            case .alert: AlertBody(m: m).transition(.opacity)
            case .input: InputBody(m: m).transition(.opacity)
            case .answer: AnswerBody(m: m).transition(.opacity)
            case .custom: CustomBody(m: m).transition(.opacity)
            case .detect: DetectBody(m: m).transition(.opacity)
            }
            if [.alert, .input, .answer].contains(m.mode) {
                UsageCard(m: m).padding(.horizontal, 22).padding(.bottom, 12)
            }
        }
        .frame(width: width)
        .background(NotchShape(radius: m.mode == .collapsed ? 12 : 26).fill(m.notchColor))
        .background(GeometryReader { g in
            Color.clear
                .onAppear { m.hitSize = g.size }
                .onChange(of: g.size) { m.hitSize = $0 }
        })
        .contentShape(Rectangle())
        .onHover { m.setHover($0) }
        .coordinateSpace(name: "notch")
        .onContinuousHover(coordinateSpace: .named("notch")) { phase in
            switch phase {
            case .active(let p): pointer = p
            case .ended: pointer = nil
            }
        }
        .environment(\.notchPointer, pointer)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: m.mode)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: m.agents.count)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .font(m.fontFamily.map { .custom($0, size: 13) } ?? .system(size: 13))
        .environment(\.colorScheme, .dark)
    }

    /// The row that lines up with the physical notch: Claude's orb on the left wing,
    /// the other agents' 2×2 cluster on the right wing.
    private var header: some View {
        HStack(spacing: 0) {
            let main = m.mainClaude
            FaceView(mood: main.map { m.mood($0) } ?? "sleep", tint: m.tint(main), size: 22, glowAlways: true,
                     style: m.style(main), accessory: m.gear(main), reaction: m.reaction(main))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .onTapGesture { m.openInput() }
            Spacer(minLength: 0)
            let cluster = m.cluster
            LazyVGrid(columns: [GridItem(.fixed(12), spacing: 4), GridItem(.fixed(12), spacing: 4)], spacing: 4) {
                ForEach(cluster) { a in
                    FaceView(mood: m.mood(a), tint: m.miniTint(a), size: 11, mini: true, style: m.style(a))
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 28)
        }
        .padding(.horizontal, 16)
        .frame(height: m.geometry.notchH)
    }
}

// MARK: - expanded

private struct ExpandedBody: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        VStack(spacing: 12) {
            if let f = m.focus {
                FocusCard(m: m, a: f)
            } else {
                Text(m.tr("cli.none")).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
            }
            if m.agents.count > 1 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                    ForEach(m.agents) { a in Chip(m: m, a: a) }
                }
            }
            HStack(spacing: 8) {
                Button { m.openInput() } label: {
                    Text(m.tr("ask.button", ["name": m.assistantName]))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Capsule().fill(m.claudeColor.opacity(0.22)))
                        .foregroundStyle(m.claudeColor)
                }.buttonStyle(.plain)
                Button { m.openDetect() } label: {
                    Text("⌕  " + m.tr("detect.button"))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                Button { m.openCustom() } label: {
                    Text(m.tr("custom.button"))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            UsageCard(m: m)
        }
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 2)
    }
}

/// Quiet footer: context fill of the focused session as a hairline, month total as a whisper.
/// No card, no colour until it matters (amber from 70%, red from 90%).
/// The month only gets a bar when `monthlyTokenBudget` is set in config.json.
private struct UsageCard: View {
    @ObservedObject var m: NotchModel

    private func fmt(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\(n / 1000)k" : "\(n)"
    }
    private func fill(_ pct: Double) -> Color {
        pct >= 90 ? Color(hex: "#FF6B6B").opacity(0.85) : pct >= 70 ? Color(hex: "#F5B544").opacity(0.8) : Color.white.opacity(0.32)
    }

    private func line(_ label: String, _ pct: Double?, _ trailing: String) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 52, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                if let pct {
                    GeometryReader { g in
                        Capsule().fill(fill(pct)).frame(width: max(3, g.size.width * min(max(pct / 100, 0), 1)))
                    }
                }
            }
            .frame(height: 2)
            .animation(.smooth(duration: 0.9), value: pct)
            Text(trailing).monospacedDigit().frame(width: 74, alignment: .trailing)
        }
        .font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.55))
    }

    var body: some View {
        if let u = m.usage, u.sessionPct != nil || u.monthTokens > 0 {
            VStack(spacing: 5) {
                if let p = u.sessionPct { line(m.tr("usage.session"), p, "\(fmt(u.sessionTokens)) · \(Int(p))%") }
                if u.monthTokens > 0 {
                    line(m.tr("usage.month"), u.monthBudget > 0 ? u.monthPct : nil,
                         u.monthBudget > 0 && u.monthPct != nil ? "\(fmt(u.monthTokens)) · \(Int(u.monthPct!))%" : fmt(u.monthTokens))
                }
            }
            .padding(.horizontal, 6).padding(.top, 2)
            .transition(.opacity)
        }
    }
}

private struct FocusCard: View {
    @ObservedObject var m: NotchModel
    let a: Agent

    var body: some View {
        let mood = m.mood(a)
        let tone = NotchModel.stateColor[mood] ?? .gray
        HStack(alignment: .top, spacing: 14) {
            FaceView(mood: mood, tint: m.tint(a), size: 44, glowAlways: true,
                     style: m.style(a), accessory: m.gear(a), reaction: m.reaction(a))
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
                .onTapGesture { m.tapPet(a) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(m.displayName(a)).fontWeight(.semibold).lineLimit(1)
                    Text(m.tr("state." + mood)).font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(tone.opacity(0.2))).foregroundStyle(tone)
                    Spacer()
                    Text(m.ago(a.since)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if !a.task.isEmpty {
                    Text(a.task).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                let prev = m.previousStep(a)
                if !prev.isEmpty && prev != a.detail {
                    Text(prev).font(.system(size: 11)).foregroundStyle(.secondary.opacity(0.6)).lineLimit(1)
                }
                if !a.detail.isEmpty {
                    Text(a.detail).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        .id(a.detail).transition(.opacity)
                }
                if a.source == "notch" && !a.answer.isEmpty {
                    Button { m.answerKey = a.key; AppDelegate.shared?.makeKey() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "text.bubble").font(.system(size: 12, weight: .semibold))
                            Text(m.tr("ask.viewAnswer")).font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(m.claudeColor.opacity(0.24)))
                        .overlay(Capsule().stroke(m.claudeColor.opacity(0.5), lineWidth: 1))
                        .foregroundStyle(m.claudeColor)
                        .contentShape(Capsule())
                    }.buttonStyle(.plain).padding(.top, 4)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(m.cardColor))
        .animation(.easeInOut(duration: 0.25), value: a.detail)
    }
}

private struct Chip: View {
    @ObservedObject var m: NotchModel
    let a: Agent

    var body: some View {
        let mood = m.mood(a)
        let selected = m.focus?.key == a.key
        HStack(spacing: 8) {
            FaceView(mood: mood, tint: m.miniTint(a), size: 16, mini: true, style: m.style(a)).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(m.displayName(a)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(m.tr("state." + mood)).font(.system(size: 10))
                    .foregroundStyle(NotchModel.stateColor[mood] ?? .gray)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(m.cardColor))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? m.miniTint(a).opacity(0.7) : .clear, lineWidth: 1.2))
        .contentShape(Rectangle())
        .onTapGesture { m.pickedKey = a.key }
        .contextMenu { Button("Remove") { m.forget(a) } }
    }
}

// MARK: - alert

private struct AlertBody: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        if let a = m.alertAgent {
            let tone: Color = a.state == "error" ? Color(hex: "#FF5A36")
                : a.state == "waiting" ? Color(hex: "#F5A524") : Color(hex: "#2FD17F")
            HStack(spacing: 14) {
                FaceView(mood: m.mood(a), tint: m.tint(a), size: 40, glowAlways: true,
                         style: m.style(a), accessory: m.gear(a)).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.tr("alert." + a.state, ["who": m.displayName(a)]) +
                         (a.source == "notch" && !a.answer.isEmpty ? m.tr("alert.tapAnswer") : ""))
                        .fontWeight(.semibold).lineLimit(1)
                    Text(a.detail.isEmpty ? a.task : a.detail).font(.system(size: 12))
                        .foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(mix(m.cardColor, tone, 0.18)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(tone.opacity(0.55), lineWidth: 1))
            .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 2)
            .contentShape(Rectangle())
            .onTapGesture { m.alertTapped() }
        }
    }
}

// MARK: - ask input

private struct AttachmentStrip: View {
    @ObservedObject var m: NotchModel
    var body: some View {
        if !m.attachments.isEmpty {
            HStack(spacing: 6) {
                ForEach(m.attachments, id: \.self) { p in
                    HStack(spacing: 5) {
                        Image(systemName: "photo").font(.system(size: 10))
                        Text((p as NSString).lastPathComponent).lineLimit(1).frame(maxWidth: 120)
                        Button { m.attachments.removeAll { $0 == p } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                            .buttonStyle(.plain)
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct InputBody: View {
    @ObservedObject var m: NotchModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                FaceView(mood: text.isEmpty ? "idle" : "thinking", tint: m.tint(m.mainClaude), size: 34, glowAlways: true,
                         style: m.style(m.mainClaude), accessory: m.gear(m.mainClaude))
                    .frame(width: 40, height: 40)
                TextField(m.tr("ask.placeholder", ["name": m.assistantName]), text: $text, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...5).focused($focused)
                    .onSubmit { m.send(text); text = "" }
                    .padding(.top, 10)
            }
            AttachmentStrip(m: m)
            HStack {
                Button { m.cycleDir() } label: {
                    Text("+  " + m.askDir).font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }.buttonStyle(.plain)
                Spacer()
                Text(m.tr("ask.hint")).font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.7))
                Button { m.send(text); text = "" } label: {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(text.trimmingCharacters(in: .whitespaces).isEmpty
                                                  ? Color.white.opacity(0.1) : m.claudeColor))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(m.cardColor))
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 2)
        .onExitCommand { text = ""; m.closeInput() }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true } }
    }
}

// MARK: - answer

private struct AnswerBody: View {
    @ObservedObject var m: NotchModel
    @State private var reply = ""
    @FocusState private var focused: Bool

    var body: some View {
        if let a = m.answerAgent {
            let mood = m.mood(a)
            let busy = ["working", "thinking", "upload", "restart"].contains(mood)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    FaceView(mood: mood, tint: m.tint(a), size: 26, glowAlways: true,
                             style: m.style(a), accessory: m.gear(a)).frame(width: 30, height: 30)
                    Text(a.task).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { m.openTerminal(a) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal").font(.system(size: 12, weight: .semibold))
                            Text(m.tr("answer.terminal")).font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(m.claudeColor.opacity(0.24)))
                        .overlay(Capsule().stroke(m.claudeColor.opacity(0.5), lineWidth: 1))
                        .foregroundStyle(m.claudeColor)
                        .contentShape(Capsule())
                    }.buttonStyle(.plain)
                    Button { m.answerKey = "" } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.14)))
                            .foregroundStyle(.white.opacity(0.9))
                            .contentShape(Circle())
                    }.buttonStyle(.plain).help(m.tr("answer.close"))
                }
                ScrollView {
                    Group {
                        if busy {
                            Text(m.tr("answer.busy", ["name": m.assistantName])).foregroundStyle(.secondary)
                        } else {
                            Text(markdown(a.answer)).textSelection(.enabled)
                        }
                    }
                    .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
                AttachmentStrip(m: m)
                HStack {
                    TextField(m.tr("answer.reply", ["name": m.assistantName]), text: $reply)
                        .textFieldStyle(.plain).focused($focused)
                        .onSubmit { m.reply(reply); reply = "" }
                    Button { m.reply(reply); reply = "" } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)) }
                        .buttonStyle(.plain).foregroundStyle(reply.isEmpty ? Color.gray : m.claudeColor)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(m.cardColor))
            .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 2)
            .onExitCommand { m.answerKey = "" }
        }
    }

    private func markdown(_ s: String) -> AttributedString {
        let clean = s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("🔊") }.joined(separator: "\n")
        return (try? AttributedString(markdown: clean, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(clean)
    }
}

// MARK: - customize

private struct CustomBody: View {
    @ObservedObject var m: NotchModel
    private let moods = ["idle", "thinking", "working", "upload", "restart", "waiting", "done", "error", "sleep"]
    private let swatches = ["#E0784F", "#35C2AE", "#8B6CF6", "#4C9AFF", "#EC6FB3", "#F2C94C", "#7ED957", "#F0544F"]

    private var isClaude: Bool { m.customTarget == "claude" }
    private var style: String { isClaude ? m.faceStyle : m.grokFaceStyle }
    private var gear: [String] { isClaude ? m.accessory : m.grokAccessory }
    private var tint: Color {
        isClaude ? mix(Color(hex: "#EEF2F7"), m.claudeColor, 0.28) : mix(Color(hex: "#EEF2F7"), Color(hex: m.palette[0]), 0.16)
    }
    private var moodTone: Color { NotchModel.stateColor[m.customMood] ?? .gray }

    // MARK: building blocks

    /// Segmented control: one capsule that slides under the selected option.
    private func segmented(_ items: [(id: String, title: String)], selected: String, _ pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.id) { it in
                Text(it.title).font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .foregroundStyle(selected == it.id ? Color.white : Color.secondary)
                    .background { if selected == it.id { Capsule().fill(m.claudeColor.opacity(0.85)) } }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.smooth(duration: 0.25)) { pick(it.id) } }
            }
        }
        .padding(2).background(Capsule().fill(Color.white.opacity(0.07)))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                .foregroundStyle(.secondary.opacity(0.7))
            content()
        }
    }

    private func chip(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if on { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                Text(title.capitalized).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(on ? m.claudeColor.opacity(0.26) : Color.white.opacity(0.07)))
            .foregroundStyle(on ? m.claudeColor : Color.secondary)
            .animation(.smooth(duration: 0.2), value: on)
        }.buttonStyle(.plain)
    }

    private func styleTile(_ st: String) -> some View {
        let on = style == st
        return VStack(spacing: 5) {
            FaceView(mood: "idle", tint: tint, size: 30, style: st, accessory: [])
                .frame(width: 38, height: 38)
            Text(m.tr("custom.style." + st)).font(.system(size: 10, weight: .medium))
                .foregroundStyle(on ? m.claudeColor : .secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(on ? m.claudeColor.opacity(0.14) : Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? m.claudeColor.opacity(0.7) : .clear, lineWidth: 1.2))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.smooth(duration: 0.2)) { m.setStyle(st) } }
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .foregroundStyle(.secondary).contentShape(Circle())
        }.buttonStyle(.plain)
    }

    private func stepMood(_ d: Int) {
        let i = moods.firstIndex(of: m.customMood) ?? 0
        m.customMood = moods[(i + d + moods.count) % moods.count]
    }

    // MARK: body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // header
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.tr("custom.title").capitalized).font(.system(size: 15, weight: .semibold))
                    Text(m.tr("custom.hint")).font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.7))
                }
                Spacer()
                segmented([("claude", m.assistantName), ("grok", "Bots")], selected: m.customTarget) { m.customTarget = $0 }
                Button { m.closeCustom(); m.pinned = false } label: {
                    Text(m.tr("custom.done")).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Capsule().fill(m.claudeColor))
                        .foregroundStyle(.white).contentShape(Capsule())
                }.buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 14) {
                // live preview
                VStack(spacing: 10) {
                    FaceView(mood: m.customMood, tint: tint, size: 74, glowAlways: true, style: style, accessory: gear,
                             reaction: m.reactions["preview"] ?? "")
                        .frame(width: 92, height: 92)
                        .contentShape(Rectangle())
                        .onTapGesture { m.poke("preview") }
                    HStack(spacing: 5) {
                        stepButton("chevron.left") { stepMood(-1) }
                        HStack(spacing: 5) {
                            Circle().fill(moodTone).frame(width: 6, height: 6)
                            Text(m.tr("state." + m.customMood)).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                .id(m.customMood).transition(.opacity)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .animation(.smooth(duration: 0.2), value: m.customMood)
                        stepButton("chevron.right") { stepMood(1) }
                    }.padding(.horizontal, 10)
                    HStack(spacing: 5) {
                        chip(m.tr("custom.annoy"), false) { m.react("preview", "annoyed", 1.6) }
                        chip(m.tr("custom.dizzy"), false) { m.react("preview", "dizzy", 2.4) }
                    }
                }
                .padding(.vertical, 14).frame(width: 156)
                .background(RoundedRectangle(cornerRadius: 18).fill(mix(m.cardColor, moodTone, 0.07)))
                .animation(.smooth(duration: 0.4), value: m.customMood)

                // options
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        section(m.tr("custom.style")) {
                            HStack(spacing: 6) { ForEach(faceStyles, id: \.self) { styleTile($0) } }
                        }
                        section(m.tr("custom.gear")) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 5)], alignment: .leading, spacing: 5) {
                                chip(m.tr("custom.none"), gear.isEmpty) { m.clearGear() }
                                ForEach(faceAccessories, id: \.self) { a in chip(a, gear.contains(a)) { m.toggleGear(a) } }
                            }
                        }
                        if isClaude {
                            section(m.tr("custom.color")) {
                                HStack(spacing: 8) {
                                    ForEach(swatches, id: \.self) { hex in
                                        let on = m.cfg.str("claudeColor", "#E0784F").lowercased() == hex.lowercased()
                                        Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                                            .overlay(Circle().stroke(.white.opacity(on ? 0.95 : 0), lineWidth: 2).padding(-3))
                                            .scaleEffect(on ? 1.08 : 1)
                                            .animation(.smooth(duration: 0.2), value: on)
                                            .onTapGesture { m.setColor(hex) }
                                    }
                                }.padding(.leading, 3)
                            }
                        }
                        section(m.tr("custom.tap")) {
                            segmented(["chat", "terminal", "play"].map { ($0, m.tr("custom.tap." + $0)) }, selected: m.petTap) { m.setPetTap($0) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 262)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(m.cardColor))
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 2)
        .onExitCommand { m.closeCustom() }
    }
}

// MARK: - detect agents

private struct DetectBody: View {
    @ObservedObject var m: NotchModel

    private var installed: [DetectedAgent] { m.detected.filter(\.installed) }
    private var missing: [DetectedAgent] { m.detected.filter { !$0.installed } }

    private func row(_ a: DetectedAgent) -> some View {
        let tone = a.connected ? Color(hex: "#3DD68C") : Color(hex: "#F5B544")
        return HStack(spacing: 10) {
            Circle().fill(tone).frame(width: 8, height: 8).shadow(color: tone.opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(a.name).font(.system(size: 13, weight: .semibold))
                    if !a.version.isEmpty { Text("v" + a.version).font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                Text(a.connected ? shortPath(a.path) : m.tr("detect.hint"))
                    .font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.75)).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(m.tr(a.connected ? "detect.connected" : "detect.found")).font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(tone.opacity(0.2))).foregroundStyle(tone)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.tr("detect.title")).font(.system(size: 15, weight: .semibold))
                    Text(m.detecting ? m.tr("detect.scanning") : "\(installed.count) / \(m.detected.count)")
                        .font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.7))
                }
                Spacer()
                Button { m.rescan() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(m.detecting ? 360 : 0))
                            .animation(m.detecting ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: m.detecting)
                        Text(m.tr("detect.rescan")).font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.09))).foregroundStyle(.primary).contentShape(Capsule())
                }.buttonStyle(.plain)
                Button { m.closeDetect() } label: {
                    Text(m.tr("custom.done")).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Capsule().fill(m.claudeColor)).foregroundStyle(.white).contentShape(Capsule())
                }.buttonStyle(.plain)
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(installed) { row($0) }
                    if !missing.isEmpty {
                        Text(m.tr("detect.notfound") + ":  " + missing.map(\.name).joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6).padding(.horizontal, 4)
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(m.cardColor))
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 2)
        .onExitCommand { m.closeDetect() }
    }
}
