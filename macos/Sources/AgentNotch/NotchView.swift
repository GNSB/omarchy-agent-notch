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
            UsageCard(m: m)
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
                Button { m.openCustom() } label: {
                    Text(m.tr("custom.button"))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 2)
    }
}

/// Context fill of the focused session + tokens used this month. Purely additive:
/// hidden until claude-usage has answered once, and the month only gets a bar when
/// `monthlyTokenBudget` is set in config.json (the CLI doesn't expose a monthly limit).
private struct UsageCard: View {
    @ObservedObject var m: NotchModel

    private func tone(_ pct: Double) -> Color {
        pct >= 90 ? Color(hex: "#FF4D4D") : pct >= 70 ? Color(hex: "#F5A524") : Color(hex: "#3DD68C")
    }
    private func fmt(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\(n / 1000)k" : "\(n)"
    }

    private func meter(_ title: String, _ value: String, _ frac: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(value).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            if let frac {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(color).frame(width: max(4, g.size.width * min(max(frac, 0), 1)))
                    }
                }
                .frame(height: 5)
                .animation(.spring(response: 0.5, dampingFraction: 0.9), value: frac)
            }
        }
    }

    var body: some View {
        if let u = m.usage, u.sessionPct != nil || u.monthTokens > 0 {
            VStack(spacing: 10) {
                if let p = u.sessionPct {
                    meter(m.tr("usage.session"), "\(fmt(u.sessionTokens)) / \(fmt(u.sessionWindow)) · \(Int(p))%", p / 100, tone(p))
                }
                if u.monthTokens > 0 {
                    if let p = u.monthPct, u.monthBudget > 0 {
                        meter(m.tr("usage.month"), "\(fmt(u.monthTokens)) / \(fmt(u.monthBudget)) · \(Int(p))%", p / 100, tone(p))
                    } else {
                        meter(m.tr("usage.month"), "\(fmt(u.monthTokens)) tokens", nil, .clear)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(m.cardColor))
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
                .onTapGesture { m.poke(a.key) }
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
                    Button(m.tr("ask.viewAnswer")) { m.answerKey = a.key; AppDelegate.shared?.makeKey() }
                        .buttonStyle(.plain).foregroundStyle(m.claudeColor).font(.system(size: 12, weight: .medium))
                        .padding(.top, 2)
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
                    Button(m.tr("answer.terminal")) { m.openTerminal(a) }
                        .buttonStyle(.plain).foregroundStyle(m.claudeColor).font(.system(size: 11, weight: .medium))
                    Button { m.answerKey = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(m.tr("answer.close"))
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

    private func pill(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(on ? m.claudeColor.opacity(0.3) : Color.white.opacity(0.08)))
                .foregroundStyle(on ? m.claudeColor : Color.secondary)
        }.buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(m.tr("custom.title")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                pill(m.assistantName, isClaude) { m.customTarget = "claude" }
                pill("Bots", !isClaude) { m.customTarget = "grok" }
                pill(m.tr("custom.done"), false) { m.closeCustom(); m.pinned = false }
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 6) {
                    FaceView(mood: m.customMood, tint: tint, size: 70, glowAlways: true, style: style, accessory: gear,
                             reaction: m.reactions["preview"] ?? "")
                        .frame(width: 84, height: 84)
                        .contentShape(Rectangle())
                        .onTapGesture { m.poke("preview") }
                    HStack(spacing: 6) {
                        pill(m.tr("custom.annoy"), false) { m.react("preview", "annoyed", 1.6) }
                        pill(m.tr("custom.dizzy"), false) { m.react("preview", "dizzy", 2.4) }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(m.tr("custom.style")).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                        ForEach(faceStyles, id: \.self) { st in pill(m.tr("custom.style." + st), style == st) { m.setStyle(st) } }
                    }
                    HStack(alignment: .top, spacing: 6) {
                        Text(m.tr("custom.gear")).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 5)], alignment: .leading, spacing: 5) {
                            pill(m.tr("custom.none"), gear.isEmpty) { m.clearGear() }
                            ForEach(faceAccessories, id: \.self) { a in pill(a, gear.contains(a)) { m.toggleGear(a) } }
                        }
                    }
                    if isClaude {
                        HStack(spacing: 6) {
                            Text(m.tr("custom.color")).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                            ForEach(swatches, id: \.self) { hex in
                                Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(.white.opacity(m.cfg.str("claudeColor", "#E0784F").lowercased() == hex.lowercased() ? 0.9 : 0), lineWidth: 1.5))
                                    .onTapGesture { m.setColor(hex) }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 5) {
                ForEach(moods, id: \.self) { mo in
                    Button { m.customMood = mo } label: {
                        Text(m.tr("state." + mo)).font(.system(size: 10))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(m.customMood == mo ? (NotchModel.stateColor[mo] ?? .gray).opacity(0.3) : Color.white.opacity(0.06)))
                            .foregroundStyle(m.customMood == mo ? (NotchModel.stateColor[mo] ?? .gray) : Color.secondary)
                    }.buttonStyle(.plain)
                }
            }
            Text(m.tr("custom.hint")).font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(m.cardColor))
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 2)
        .onExitCommand { m.closeCustom() }
    }
}
