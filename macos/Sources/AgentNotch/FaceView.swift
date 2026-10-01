import SwiftUI

/// Pointer position in the notch's coordinate space; faces look toward it.
private struct PointerKey: EnvironmentKey { static let defaultValue: CGPoint? = nil }
extension EnvironmentValues {
    var notchPointer: CGPoint? {
        get { self[PointerKey.self] }
        set { self[PointerKey.self] = newValue }
    }
}

let faceStyles = ["orb", "cat", "dog", "hamster"]
let faceAccessories = ["hat", "cowboy", "crown", "party", "bow", "headphones", "helmet", "mask", "glasses", "shades"]

/// Glossy orb (or cat / dog / hamster) with eyes that change shape per mood.
/// mood: idle | thinking | working | upload | restart | waiting | done | error | errorStale | sleep
/// reaction: "" | annoyed | dizzy (temporarily overrides the eyes)
struct FaceView: View {
    var mood: String
    var tint: Color
    var size: CGFloat
    var mini = false
    var glowAlways = false
    var style = "orb"
    var accessory: [String] = []
    var reaction = ""

    @Environment(\.notchPointer) private var pointer
    @State private var center: CGPoint?

    private var glowColor: Color {
        switch mood {
        case "working": return Color(hex: "#3B8BFF")
        case "upload": return Color(hex: "#22D3EE")
        case "restart": return Color(hex: "#D946EF")
        case "thinking": return Color(hex: "#8B5CF6")
        case "waiting": return Color(hex: "#F5A524")
        case "done": return Color(hex: "#3DD68C")
        case "error", "errorStale": return Color(hex: "#FF4D4D")
        case "sleep": return Color(hex: "#6B7280")
        default: return Color(hex: "#9FB3C8")
        }
    }

    private var glowStrength: Double {
        switch mood {
        case "sleep": return 0
        case "idle": return glowAlways ? 0.35 : 0
        case "errorStale": return mini ? 0.3 : 0.5
        default: return mini ? 0.55 : 0.9
        }
    }

    /// Unit-ish vector from the face toward the pointer (zero when far away or unknown).
    private var gaze: CGPoint {
        guard let p = pointer, let c = center, mood != "sleep" else { return .zero }
        let dx = p.x - c.x, dy = p.y - c.y
        let d = max(1, hypot(dx, dy))
        let k = min(1, d / 60)
        return CGPoint(x: dx / d * k, y: dy / d * k)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, canvas in
                draw(ctx, t: tl.date.timeIntervalSinceReferenceDate, canvas: canvas)
            }
            .frame(width: size * 3, height: size * 3)
        }
        .frame(width: size, height: size)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { center = CGPoint(x: g.frame(in: .named("notch")).midX, y: g.frame(in: .named("notch")).midY) }
                .onChange(of: g.frame(in: .named("notch"))) { center = CGPoint(x: $0.midX, y: $0.midY) }
        })
        .allowsHitTesting(false)
    }

    // MARK: drawing

    private func draw(_ gc: GraphicsContext, t: Double, canvas: CGSize) {
        let s = Double(size)
        let look = mood == "errorStale" ? "error" : mood
        var bobY = 0.0, lookX = 0.0, lookY = 0.0, tilt = 0.0, shake = 0.0, open = 1.0

        switch look {
        case "idle":
            let ph = t.truncatingRemainder(dividingBy: 4.3)
            if ph < 0.16 { open = 0.1 + 0.9 * abs(ph - 0.08) / 0.08 }
            lookX = sin(t * 0.5) * 0.04 * s
        case "thinking":
            lookX = sin(t * 1.8) * 0.07 * s; lookY = -0.05 * s; tilt = sin(t * 1.2) * 4
        case "working":
            lookX = sin(t * 6) * 0.08 * s; bobY = sin(t * 9) * 0.02 * s; open = 0.85
        case "upload":
            lookY = -0.07 * s; bobY = -abs(sin(t * 4)) * 0.06 * s; lookX = sin(t * 2) * 0.03 * s
        case "restart":
            tilt = sin(t * 5) * 6; lookX = sin(t * 7) * 0.05 * s
        case "waiting":
            lookY = -0.07 * s; bobY = -abs(sin(t * 3.2)) * 0.07 * s; tilt = sin(t * 6.4) * 3
        case "done":
            bobY = -abs(sin(t * 2.5)) * 0.05 * s
        case "error":
            if mood == "error" { shake = sin(t * 38) * 0.035 * s }
        case "sleep":
            bobY = sin(t * 1.1) * 0.01 * s
        default: break
        }

        // Follow the pointer when nothing more dramatic is going on.
        if reaction.isEmpty, ["idle", "thinking", "waiting", "done"].contains(look), pointer != nil {
            let g = gaze
            if g != .zero { lookX = g.x * 0.09 * s; lookY = g.y * 0.07 * s }
        }
        if reaction == "annoyed" { shake = sin(t * 30) * 0.02 * s }
        if reaction == "dizzy" { tilt = sin(t * 7) * 10; bobY = sin(t * 3.5) * 0.03 * s }

        let breathe = 0.8 + 0.2 * sin(t * 2)
        var ctx = gc
        ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)

        // glow
        let strength = glowStrength * breathe
        if strength > 0.01 {
            let r = s * (mini ? 1.1 : 1.35)
            var g = ctx
            g.opacity = strength
            g.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                   with: .radialGradient(
                    Gradient(stops: [
                        .init(color: glowColor.opacity(0.9), location: 0),
                        .init(color: glowColor.opacity(0.45), location: 0.32),
                        .init(color: glowColor.opacity(0.12), location: 0.62),
                        .init(color: glowColor.opacity(0), location: 1)]),
                    center: .zero, startRadius: 0, endRadius: r))
        }

        // upload arrow floats above the head
        if look == "upload" && !mini {
            let k = t.truncatingRemainder(dividingBy: 1.0)
            var a = ctx
            a.opacity = 1 - k
            let y = -s * (0.62 + 0.35 * k)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y + s * 0.12)); p.addLine(to: CGPoint(x: 0, y: y - s * 0.08))
            p.move(to: CGPoint(x: -s * 0.07, y: y - s * 0.01)); p.addLine(to: CGPoint(x: 0, y: y - s * 0.09))
            p.addLine(to: CGPoint(x: s * 0.07, y: y - s * 0.01))
            a.stroke(p, with: .color(glowColor), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round, lineJoin: .round))
        }

        ctx.translateBy(x: shake, y: bobY)
        ctx.rotate(by: .degrees(tilt))
        if look == "restart" { ctx.rotate(by: .degrees(sin(t * 2.4) * 14)) }
        if look == "sleep" { ctx.opacity = 0.72 }

        let base = (look == "error") ? mix(tint, Color(hex: "#FF7A8A"), 0.45) : tint

        drawBehind(ctx, s: s, t: t, base: base, look: look)

        // body
        let body = Path(ellipseIn: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
        ctx.fill(body, with: .linearGradient(
            Gradient(colors: [mix(base, .white, 0.2), base, mix(base, .black, mini ? 0.2 : 0.4)]),
            startPoint: CGPoint(x: 0, y: -s / 2), endPoint: CGPoint(x: 0, y: s / 2)))

        // specular highlight
        var h = ctx
        h.translateBy(x: -s * 0.15, y: -s * 0.27)
        h.rotate(by: .degrees(-28))
        h.opacity = mini ? 0.35 : 0.5
        let hw = s * 0.34
        h.fill(Path(ellipseIn: CGRect(x: -hw / 2, y: -hw * 0.31, width: hw, height: hw * 0.62)), with: .color(.white))

        drawFace(ctx, s: s, t: t, base: base, look: look)

        // eyes
        let eye = Color(hex: "#141418")
        let cy = lookY + (look == "sleep" ? s * 0.08 : s * 0.02)
        for side in [-1.0, 1.0] {
            let cx = lookX + side * s * 0.17
            drawEye(ctx, s: s, t: t, cx: cx, cy: cy, side: side, look: look, open: open, color: eye)
        }

        for a in accessory { drawAccessory(ctx, name: a, s: s, t: t) }
    }

    private func drawEye(_ ctx: GraphicsContext, s: Double, t: Double, cx: Double, cy: Double,
                         side: Double, look: String, open: Double, color eye: Color) {
        if reaction == "dizzy" {
            var p = Path()
            let r0 = s * 0.075
            for i in 0...40 {
                let a = Double(i) / 40 * 5 * .pi + t * 8 * side
                let r = r0 * Double(i) / 40
                let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(eye), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
            return
        }
        if reaction == "annoyed" {
            var p = Path()
            p.move(to: CGPoint(x: cx - s * 0.07, y: cy - side * s * 0.05))
            p.addLine(to: CGPoint(x: cx + s * 0.07, y: cy + side * s * 0.03))
            ctx.stroke(p, with: .color(eye), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
            return
        }
        switch look {
        case "done":
            var p = Path()
            p.move(to: CGPoint(x: cx - s * 0.065, y: cy + s * 0.04))
            p.addQuadCurve(to: CGPoint(x: cx + s * 0.065, y: cy + s * 0.04),
                           control: CGPoint(x: cx, y: cy - s * 0.1))
            ctx.stroke(p, with: .color(eye), style: StrokeStyle(lineWidth: s * 0.055, lineCap: .round))
        case "error":
            let d = s * 0.055
            var p = Path()
            p.move(to: CGPoint(x: cx - d, y: cy - d)); p.addLine(to: CGPoint(x: cx + d, y: cy + d))
            p.move(to: CGPoint(x: cx + d, y: cy - d)); p.addLine(to: CGPoint(x: cx - d, y: cy + d))
            ctx.stroke(p, with: .color(eye), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
        case "sleep":
            var p = Path()
            p.move(to: CGPoint(x: cx - s * 0.06, y: cy)); p.addLine(to: CGPoint(x: cx + s * 0.06, y: cy))
            ctx.stroke(p, with: .color(eye), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
        case "restart":
            var p = Path()
            let r = s * 0.06
            p.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .radians(t * 9 * side),
                     endAngle: .radians(t * 9 * side + 4.6), clockwise: false)
            ctx.stroke(p, with: .color(eye), style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round))
        default:
            let w = s * (look == "waiting" ? 0.13 : 0.11)
            let hgt = max(s * 0.02, s * (look == "waiting" ? 0.22 : 0.2) * open)
            ctx.fill(Path(roundedRect: CGRect(x: cx - w / 2, y: cy - hgt / 2, width: w, height: hgt),
                          cornerRadius: w / 2), with: .color(eye))
        }
    }

    // MARK: animal parts

    private func tri(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
        var p = Path(); p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.closeSubpath(); return p
    }

    private func oval(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double, rot: Double = 0) -> Path {
        Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
            .applying(CGAffineTransform(translationX: -cx, y: -cy).concatenating(CGAffineTransform(rotationAngle: rot))
                .concatenating(CGAffineTransform(translationX: cx, y: cy)))
    }

    /// Ears and tails: behind the body.
    private func drawBehind(_ ctx: GraphicsContext, s: Double, t: Double, base: Color, look: String) {
        let dark = mix(base, .black, 0.3)
        let pink = Color(hex: "#F4A6B8")
        let happy = look == "done" || look == "working" || look == "upload"
        switch style {
        case "cat":
            for side in [-1.0, 1.0] {
                ctx.fill(tri(CGPoint(x: side * s * 0.46, y: -s * 0.12), CGPoint(x: side * s * 0.4, y: -s * 0.66),
                             CGPoint(x: side * s * 0.1, y: -s * 0.44)), with: .color(base))
                ctx.fill(tri(CGPoint(x: side * s * 0.4, y: -s * 0.2), CGPoint(x: side * s * 0.37, y: -s * 0.55),
                             CGPoint(x: side * s * 0.18, y: -s * 0.41)), with: .color(pink.opacity(0.85)))
            }
            var tail = Path()
            let sw = sin(t * (happy ? 6 : 2)) * s * 0.12
            tail.move(to: CGPoint(x: s * 0.36, y: s * 0.3))
            tail.addQuadCurve(to: CGPoint(x: s * 0.72 + sw, y: -s * 0.1),
                              control: CGPoint(x: s * 0.72, y: s * 0.5))
            ctx.stroke(tail, with: .color(dark), style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
        case "dog":
            for side in [-1.0, 1.0] {
                let flop = sin(t * 3 + side) * 0.05
                ctx.fill(oval(side * s * 0.47, -s * 0.02, s * 0.26, s * 0.5, rot: side * (0.25 + flop)), with: .color(dark))
            }
            var tail = Path()
            let sw = sin(t * (happy ? 14 : 3)) * s * 0.1
            tail.move(to: CGPoint(x: s * 0.36, y: s * 0.3))
            tail.addQuadCurve(to: CGPoint(x: s * 0.66 + sw, y: s * 0.02), control: CGPoint(x: s * 0.6, y: s * 0.3))
            ctx.stroke(tail, with: .color(dark), style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round))
        case "hamster":
            for side in [-1.0, 1.0] {
                ctx.fill(oval(side * s * 0.34, -s * 0.42, s * 0.3, s * 0.3), with: .color(base))
                ctx.fill(oval(side * s * 0.34, -s * 0.42, s * 0.18, s * 0.18), with: .color(pink.opacity(0.85)))
            }
        default: break
        }
    }

    /// Muzzle, cheeks, whiskers: on top of the body, under the eyes.
    private func drawFace(_ ctx: GraphicsContext, s: Double, t: Double, base: Color, look: String) {
        let pink = Color(hex: "#F4A6B8")
        let ink = Color(hex: "#141418")
        switch style {
        case "cat":
            ctx.fill(tri(CGPoint(x: -s * 0.04, y: s * 0.1), CGPoint(x: s * 0.04, y: s * 0.1),
                         CGPoint(x: 0, y: s * 0.145)), with: .color(pink))
            var w = Path()
            for side in [-1.0, 1.0] {
                for k in [-1.0, 0.0, 1.0] {
                    w.move(to: CGPoint(x: side * s * 0.14, y: s * 0.15 + k * s * 0.02))
                    w.addLine(to: CGPoint(x: side * s * 0.4, y: s * 0.15 + k * s * 0.07))
                }
            }
            ctx.stroke(w, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: s * 0.014, lineCap: .round))
        case "dog":
            ctx.fill(oval(0, s * 0.2, s * 0.38, s * 0.26), with: .color(mix(base, .white, 0.55)))
            ctx.fill(oval(0, s * 0.14, s * 0.11, s * 0.07), with: .color(ink))
            if look == "done" || look == "working" || look == "upload" {
                let len = s * (0.06 + 0.02 * sin(t * 8))
                ctx.fill(Path(roundedRect: CGRect(x: -s * 0.04, y: s * 0.24, width: s * 0.08, height: len),
                              cornerRadius: s * 0.04), with: .color(pink))
            }
        case "hamster":
            for side in [-1.0, 1.0] {
                ctx.fill(oval(side * s * 0.3, s * 0.16, s * 0.22, s * 0.18), with: .color(pink.opacity(0.55)))
            }
            ctx.fill(oval(0, s * 0.11, s * 0.06, s * 0.04), with: .color(pink))
            for side in [-1.0, 1.0] {
                ctx.fill(Path(roundedRect: CGRect(x: side > 0 ? 0 : -s * 0.035, y: s * 0.14, width: s * 0.035, height: s * 0.06),
                              cornerRadius: s * 0.01), with: .color(.white))
            }
        default: break
        }
    }

    // MARK: accessories

    private func drawAccessory(_ ctx: GraphicsContext, name: String, s: Double, t: Double) {
        let ink = Color(hex: "#141418")
        func stroke(_ p: Path, _ c: Color, _ w: Double) {
            ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
        switch name {
        case "hat":
            ctx.fill(Path(roundedRect: CGRect(x: -s * 0.4, y: -s * 0.52, width: s * 0.8, height: s * 0.07), cornerRadius: s * 0.03),
                     with: .color(ink))
            ctx.fill(Path(roundedRect: CGRect(x: -s * 0.25, y: -s * 0.92, width: s * 0.5, height: s * 0.42), cornerRadius: s * 0.04),
                     with: .color(ink))
            ctx.fill(Path(CGRect(x: -s * 0.25, y: -s * 0.6, width: s * 0.5, height: s * 0.07)), with: .color(Color(hex: "#C0392B")))
        case "cowboy":
            let brown = Color(hex: "#8B5A2B")
            ctx.fill(oval(0, -s * 0.5, s * 1.05, s * 0.16), with: .color(brown))
            ctx.fill(Path(roundedRect: CGRect(x: -s * 0.22, y: -s * 0.78, width: s * 0.44, height: s * 0.32), cornerRadius: s * 0.12),
                     with: .color(mix(brown, .black, 0.15)))
        case "crown":
            var p = Path()
            let y0 = -s * 0.46, y1 = -s * 0.8
            p.move(to: CGPoint(x: -s * 0.27, y: y0)); p.addLine(to: CGPoint(x: -s * 0.3, y: y1))
            p.addLine(to: CGPoint(x: -s * 0.14, y: y1 + s * 0.14)); p.addLine(to: CGPoint(x: 0, y: y1 - s * 0.04))
            p.addLine(to: CGPoint(x: s * 0.14, y: y1 + s * 0.14)); p.addLine(to: CGPoint(x: s * 0.3, y: y1))
            p.addLine(to: CGPoint(x: s * 0.27, y: y0)); p.closeSubpath()
            ctx.fill(p, with: .linearGradient(Gradient(colors: [Color(hex: "#FFE066"), Color(hex: "#E0A800")]),
                                              startPoint: CGPoint(x: 0, y: y1), endPoint: CGPoint(x: 0, y: y0)))
        case "party":
            ctx.fill(tri(CGPoint(x: -s * 0.2, y: -s * 0.45), CGPoint(x: s * 0.2, y: -s * 0.45), CGPoint(x: 0, y: -s * 0.95)),
                     with: .linearGradient(Gradient(colors: [Color(hex: "#FF5FA2"), Color(hex: "#7C5CFF")]),
                                           startPoint: CGPoint(x: 0, y: -s * 0.95), endPoint: CGPoint(x: 0, y: -s * 0.45)))
            ctx.fill(oval(0, -s * 0.95, s * 0.1, s * 0.1), with: .color(.white))
        case "bow":
            let c = Color(hex: "#FF5FA2")
            ctx.fill(tri(CGPoint(x: s * 0.28, y: -s * 0.4), CGPoint(x: s * 0.5, y: -s * 0.52), CGPoint(x: s * 0.5, y: -s * 0.26)), with: .color(c))
            ctx.fill(tri(CGPoint(x: s * 0.28, y: -s * 0.4), CGPoint(x: s * 0.06, y: -s * 0.52), CGPoint(x: s * 0.06, y: -s * 0.26)), with: .color(c))
            ctx.fill(oval(s * 0.28, -s * 0.4, s * 0.1, s * 0.1), with: .color(mix(c, .black, 0.25)))
        case "headphones":
            var band = Path()
            band.addArc(center: CGPoint(x: 0, y: -s * 0.02), radius: s * 0.52, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            stroke(band, Color(hex: "#2B2B33"), s * 0.07)
            for side in [-1.0, 1.0] {
                ctx.fill(Path(roundedRect: CGRect(x: side * s * 0.52 - s * 0.07, y: -s * 0.14, width: s * 0.14, height: s * 0.28), cornerRadius: s * 0.05),
                         with: .color(Color(hex: "#3A3A45")))
            }
        case "helmet":
            var p = Path()
            p.addArc(center: CGPoint(x: 0, y: -s * 0.06), radius: s * 0.54, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            p.closeSubpath()
            ctx.fill(p, with: .linearGradient(Gradient(colors: [Color(hex: "#C9CED6"), Color(hex: "#7C8492")]),
                                              startPoint: CGPoint(x: 0, y: -s * 0.6), endPoint: CGPoint(x: 0, y: -s * 0.06)))
            ctx.fill(Path(CGRect(x: -s * 0.55, y: -s * 0.09, width: s * 1.1, height: s * 0.05)), with: .color(Color(hex: "#5B6270")))
        case "mask":
            ctx.fill(Path(roundedRect: CGRect(x: -s * 0.42, y: -s * 0.1, width: s * 0.84, height: s * 0.26), cornerRadius: s * 0.12),
                     with: .color(ink.opacity(0.92)))
            for side in [-1.0, 1.0] {
                ctx.fill(Path(ellipseIn: CGRect(x: side * s * 0.17 - s * 0.06, y: -s * 0.02, width: s * 0.12, height: s * 0.14)),
                         with: .color(.white))
            }
        case "glasses":
            for side in [-1.0, 1.0] {
                stroke(Path(ellipseIn: CGRect(x: side * s * 0.17 - s * 0.12, y: -s * 0.09, width: s * 0.24, height: s * 0.24)), ink, s * 0.03)
            }
            var b = Path(); b.move(to: CGPoint(x: -s * 0.05, y: s * 0.02)); b.addLine(to: CGPoint(x: s * 0.05, y: s * 0.02))
            stroke(b, ink, s * 0.03)
        case "shades":
            for side in [-1.0, 1.0] {
                ctx.fill(Path(roundedRect: CGRect(x: side * s * 0.17 - s * 0.13, y: -s * 0.08, width: s * 0.26, height: s * 0.19), cornerRadius: s * 0.07),
                         with: .color(ink))
            }
            var b = Path(); b.move(to: CGPoint(x: -s * 0.05, y: -s * 0.03)); b.addLine(to: CGPoint(x: s * 0.05, y: -s * 0.03))
            stroke(b, ink, s * 0.03)
        default: break
        }
    }
}
