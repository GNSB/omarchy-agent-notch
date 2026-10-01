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
            let soft = StrokeStyle(lineWidth: s * 0.06, lineCap: .round, lineJoin: .round)   // rounds the ear tips
            for side in [-1.0, 1.0] {
                let outer = tri(CGPoint(x: side * s * 0.45, y: -s * 0.1), CGPoint(x: side * s * 0.39, y: -s * 0.62),
                                CGPoint(x: side * s * 0.1, y: -s * 0.43))
                ctx.fill(outer, with: .color(base)); ctx.stroke(outer, with: .color(base), style: soft)
                let inner = tri(CGPoint(x: side * s * 0.39, y: -s * 0.2), CGPoint(x: side * s * 0.36, y: -s * 0.52),
                                CGPoint(x: side * s * 0.19, y: -s * 0.4))
                ctx.fill(inner, with: .color(pink.opacity(0.85)))
                ctx.stroke(inner, with: .color(pink.opacity(0.85)), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round, lineJoin: .round))
            }
            var tail = Path()
            let sw = sin(t * (happy ? 6 : 2)) * s * 0.12
            tail.move(to: CGPoint(x: s * 0.36, y: s * 0.3))
            tail.addQuadCurve(to: CGPoint(x: s * 0.72 + sw, y: -s * 0.1),
                              control: CGPoint(x: s * 0.72, y: s * 0.5))
            ctx.stroke(tail, with: .color(dark), style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
        case "dog":
            // long floppy ears hanging past the cheeks, in a warm brown so they don't read as monkey ears
            let ear = mix(base, Color(hex: "#6B3F22"), 0.62)
            for side in [-1.0, 1.0] {
                let flop = sin(t * 3 + side) * 0.05
                ctx.fill(oval(side * s * 0.5, s * 0.1, s * 0.3, s * 0.66, rot: side * (0.16 + flop)), with: .color(ear))
            }
            var tail = Path()
            let sw = sin(t * (happy ? 14 : 3)) * s * 0.1
            tail.move(to: CGPoint(x: s * 0.36, y: s * 0.3))
            tail.addQuadCurve(to: CGPoint(x: s * 0.66 + sw, y: s * 0.02), control: CGPoint(x: s * 0.6, y: s * 0.3))
            ctx.stroke(tail, with: .color(ear), style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round))
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
            // tabby stripes on the forehead + soft cheeks
            var stripes = Path()
            for (dx, len) in [(-0.09, 0.1), (0.0, 0.13), (0.09, 0.1)] {
                stripes.move(to: CGPoint(x: s * dx, y: -s * 0.47)); stripes.addLine(to: CGPoint(x: s * dx, y: -s * (0.47 - len)))
            }
            ctx.stroke(stripes, with: .color(mix(base, .black, 0.28).opacity(0.7)), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
            for side in [-1.0, 1.0] {
                ctx.fill(oval(side * s * 0.29, s * 0.2, s * 0.16, s * 0.1), with: .color(pink.opacity(0.4)))
            }
            ctx.fill(tri(CGPoint(x: -s * 0.045, y: s * 0.1), CGPoint(x: s * 0.045, y: s * 0.1),
                         CGPoint(x: 0, y: s * 0.15)), with: .color(pink))
            var mouth = Path()   // little "w" mouth
            mouth.move(to: CGPoint(x: 0, y: s * 0.15)); mouth.addLine(to: CGPoint(x: 0, y: s * 0.19))
            mouth.move(to: CGPoint(x: -s * 0.07, y: s * 0.2))
            mouth.addQuadCurve(to: CGPoint(x: 0, y: s * 0.19), control: CGPoint(x: -s * 0.035, y: s * 0.24))
            mouth.addQuadCurve(to: CGPoint(x: s * 0.07, y: s * 0.2), control: CGPoint(x: s * 0.035, y: s * 0.24))
            ctx.stroke(mouth, with: .color(ink.opacity(0.55)), style: StrokeStyle(lineWidth: s * 0.014, lineCap: .round))
            var w = Path()
            for side in [-1.0, 1.0] {
                for k in [-1.0, 0.0, 1.0] {
                    w.move(to: CGPoint(x: side * s * 0.14, y: s * 0.16 + k * s * 0.02))
                    w.addQuadCurve(to: CGPoint(x: side * s * 0.42, y: s * 0.15 + k * s * 0.08),
                                   control: CGPoint(x: side * s * 0.28, y: s * 0.13 + k * s * 0.04))
                }
            }
            ctx.stroke(w, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: s * 0.014, lineCap: .round))
        case "dog":
            let patch = mix(base, Color(hex: "#6B3F22"), 0.62)
            ctx.fill(oval(s * 0.17, s * 0.0, s * 0.3, s * 0.34, rot: 0.2), with: .color(patch.opacity(0.9)))   // eye patch
            ctx.fill(oval(0, s * 0.22, s * 0.5, s * 0.34), with: .color(mix(base, .white, 0.6)))               // snout
            ctx.fill(oval(0, s * 0.13, s * 0.16, s * 0.1), with: .color(ink))                                  // nose
            var mouth = Path()
            mouth.move(to: CGPoint(x: 0, y: s * 0.18)); mouth.addLine(to: CGPoint(x: 0, y: s * 0.25))
            mouth.move(to: CGPoint(x: -s * 0.09, y: s * 0.27))
            mouth.addQuadCurve(to: CGPoint(x: 0, y: s * 0.25), control: CGPoint(x: -s * 0.05, y: s * 0.31))
            mouth.addQuadCurve(to: CGPoint(x: s * 0.09, y: s * 0.27), control: CGPoint(x: s * 0.05, y: s * 0.31))
            ctx.stroke(mouth, with: .color(ink.opacity(0.7)), style: StrokeStyle(lineWidth: s * 0.016, lineCap: .round))
            if look == "done" || look == "working" || look == "upload" {
                let len = s * (0.1 + 0.025 * sin(t * 8))
                ctx.fill(Path(roundedRect: CGRect(x: -s * 0.05, y: s * 0.27, width: s * 0.1, height: len),
                              cornerRadius: s * 0.05), with: .color(pink))
            }
        case "hamster":
            let gold = mix(base, Color(hex: "#C98A3C"), 0.7)
            ctx.fill(oval(0, -s * 0.28, s * 0.66, s * 0.36), with: .color(gold.opacity(0.92)))               // golden cap
            ctx.fill(oval(-s * 0.08, -s * 0.36, s * 0.2, s * 0.08, rot: -0.3), with: .color(.white.opacity(0.28)))
            for side in [-1.0, 1.0] {
                ctx.fill(oval(side * s * 0.31, s * 0.17, s * 0.27, s * 0.22), with: .color(pink.opacity(0.5)))  // stuffed cheeks
                ctx.fill(oval(side * s * 0.27, s * 0.13, s * 0.09, s * 0.05, rot: -0.4 * side), with: .color(.white.opacity(0.3)))
            }
            ctx.fill(oval(0, s * 0.1, s * 0.07, s * 0.045), with: .color(pink))
            var wh = Path()
            for side in [-1.0, 1.0] {
                for k in [-1.0, 1.0] {
                    wh.move(to: CGPoint(x: side * s * 0.2, y: s * 0.17 + k * s * 0.01))
                    wh.addLine(to: CGPoint(x: side * s * 0.42, y: s * 0.17 + k * s * 0.06))
                }
            }
            ctx.stroke(wh, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: s * 0.012, lineCap: .round))
            for side in [-1.0, 1.0] {
                ctx.fill(Path(roundedRect: CGRect(x: side > 0 ? 0 : -s * 0.04, y: s * 0.14, width: s * 0.04, height: s * 0.07),
                              cornerRadius: s * 0.012), with: .color(.white))
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
        func grad(_ a: String, _ b: String, _ y0: Double, _ y1: Double) -> GraphicsContext.Shading {
            .linearGradient(Gradient(colors: [Color(hex: a), Color(hex: b)]), startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1))
        }
        func gleam(_ x: Double, _ y: Double, _ w: Double, _ h: Double, rot: Double = -0.5, _ a: Double = 0.5) {
            ctx.fill(oval(x, y, w, h, rot: rot), with: .color(.white.opacity(a)))
        }
        switch name {
        case "hat":   // top hat
            ctx.fill(Path(roundedRect: CGRect(x: -s * 0.25, y: -s * 0.92, width: s * 0.5, height: s * 0.44), cornerRadius: s * 0.04),
                     with: .linearGradient(Gradient(colors: [Color(hex: "#2A2A33"), ink, Color(hex: "#2A2A33")]),
                                           startPoint: CGPoint(x: -s * 0.25, y: 0), endPoint: CGPoint(x: s * 0.25, y: 0)))
            ctx.fill(Path(roundedRect: CGRect(x: -s * 0.4, y: -s * 0.53, width: s * 0.8, height: s * 0.08), cornerRadius: s * 0.04),
                     with: grad("#2E2E38", "#0E0E12", -s * 0.53, -s * 0.45))
            ctx.fill(Path(CGRect(x: -s * 0.25, y: -s * 0.62, width: s * 0.5, height: s * 0.085)), with: .color(Color(hex: "#C0392B")))
            ctx.fill(Path(roundedRect: CGRect(x: -s * 0.045, y: -s * 0.635, width: s * 0.09, height: s * 0.115), cornerRadius: s * 0.015),
                     with: .color(Color(hex: "#F2C94C")))
            ctx.fill(Path(roundedRect: CGRect(x: -s * 0.19, y: -s * 0.86, width: s * 0.035, height: s * 0.2), cornerRadius: s * 0.015),
                     with: .color(.white.opacity(0.14)))
        case "cowboy":
            let brown = Color(hex: "#9A6633")
            var brim = Path()   // upturned brim
            brim.move(to: CGPoint(x: -s * 0.56, y: -s * 0.58))
            brim.addQuadCurve(to: CGPoint(x: s * 0.56, y: -s * 0.58), control: CGPoint(x: 0, y: -s * 0.36))
            brim.addQuadCurve(to: CGPoint(x: -s * 0.56, y: -s * 0.58), control: CGPoint(x: 0, y: -s * 0.5))
            ctx.fill(brim, with: grad("#B07A40", "#7A4F24", -s * 0.58, -s * 0.4))
            var crown = Path()
            crown.move(to: CGPoint(x: -s * 0.24, y: -s * 0.5)); crown.addQuadCurve(to: CGPoint(x: -s * 0.18, y: -s * 0.84), control: CGPoint(x: -s * 0.27, y: -s * 0.8))
            crown.addQuadCurve(to: CGPoint(x: 0, y: -s * 0.76), control: CGPoint(x: -s * 0.08, y: -s * 0.82))
            crown.addQuadCurve(to: CGPoint(x: s * 0.18, y: -s * 0.84), control: CGPoint(x: s * 0.08, y: -s * 0.82))
            crown.addQuadCurve(to: CGPoint(x: s * 0.24, y: -s * 0.5), control: CGPoint(x: s * 0.27, y: -s * 0.8))
            crown.closeSubpath()
            ctx.fill(crown, with: grad("#A8733A", "#835629", -s * 0.84, -s * 0.5))
            ctx.fill(Path(CGRect(x: -s * 0.235, y: -s * 0.59, width: s * 0.47, height: s * 0.07)), with: .color(mix(brown, .black, 0.45)))
            ctx.fill(oval(0, -s * 0.555, s * 0.07, s * 0.05), with: .color(Color(hex: "#E8C468")))
        case "crown":
            var p = Path()
            let y0 = -s * 0.46, y1 = -s * 0.8
            p.move(to: CGPoint(x: -s * 0.27, y: y0)); p.addLine(to: CGPoint(x: -s * 0.3, y: y1))
            p.addLine(to: CGPoint(x: -s * 0.14, y: y1 + s * 0.14)); p.addLine(to: CGPoint(x: 0, y: y1 - s * 0.04))
            p.addLine(to: CGPoint(x: s * 0.14, y: y1 + s * 0.14)); p.addLine(to: CGPoint(x: s * 0.3, y: y1))
            p.addLine(to: CGPoint(x: s * 0.27, y: y0)); p.closeSubpath()
            ctx.fill(p, with: grad("#FFE680", "#D99A00", y1, y0))
            stroke(p, Color(hex: "#B8860B").opacity(0.7), s * 0.014)
            ctx.fill(Path(roundedRect: CGRect(x: -s * 0.275, y: y0 - s * 0.06, width: s * 0.55, height: s * 0.06), cornerRadius: s * 0.02),
                     with: grad("#F2B81C", "#B8860B", y0 - s * 0.06, y0))
            for (x, y, c) in [(-0.3, y1 / s, "#FF5A6E"), (0.0, (y1 - s * 0.04) / s, "#4CC9F0"), (0.3, y1 / s, "#FF5A6E")] {
                ctx.fill(oval(s * x, s * y, s * 0.075, s * 0.075), with: .color(Color(hex: c)))
                ctx.fill(oval(s * x - s * 0.012, s * y - s * 0.012, s * 0.025, s * 0.025), with: .color(.white.opacity(0.7)))
            }
        case "party":
            let cone = tri(CGPoint(x: -s * 0.2, y: -s * 0.45), CGPoint(x: s * 0.2, y: -s * 0.45), CGPoint(x: 0, y: -s * 0.95))
            ctx.fill(cone, with: .linearGradient(Gradient(colors: [Color(hex: "#FF5FA2"), Color(hex: "#7C5CFF")]),
                                                 startPoint: CGPoint(x: 0, y: -s * 0.95), endPoint: CGPoint(x: 0, y: -s * 0.45)))
            var stripes = Path()
            for (a, b) in [(-0.14, -0.62), (0.14, -0.6), (-0.07, -0.78), (0.07, -0.76)] as [(Double, Double)] {
                stripes.move(to: CGPoint(x: s * a, y: -s * 0.45)); stripes.addLine(to: CGPoint(x: s * a * 0.2, y: s * b - s * 0.18))
            }
            ctx.stroke(stripes, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
            for (x, y, c) in [(-0.07, -0.55, "#FFE066"), (0.08, -0.65, "#7FE5C3"), (-0.02, -0.74, "#FFE066")] as [(Double, Double, String)] {
                ctx.fill(oval(s * x, s * y, s * 0.035, s * 0.035), with: .color(Color(hex: c)))
            }
            ctx.fill(oval(0, -s * 0.95, s * 0.13, s * 0.13), with: .color(.white))
            ctx.fill(oval(0, -s * 0.45, s * 0.42, s * 0.05), with: .color(Color(hex: "#FFE066")))
        case "bow":
            let c = Color(hex: "#FF5FA2")
            for side in [-1.0, 1.0] {
                let loop = tri(CGPoint(x: s * 0.28, y: -s * 0.4), CGPoint(x: s * (0.28 + side * 0.23), y: -s * 0.54), CGPoint(x: s * (0.28 + side * 0.23), y: -s * 0.26))
                ctx.fill(loop, with: .linearGradient(Gradient(colors: [mix(c, .white, 0.25), c]),
                                                     startPoint: CGPoint(x: s * (0.28 + side * 0.23), y: -s * 0.54), endPoint: CGPoint(x: s * 0.28, y: -s * 0.3)))
                stroke(loop, c, s * 0.03)
            }
            ctx.fill(oval(s * 0.28, -s * 0.4, s * 0.11, s * 0.11), with: .color(mix(c, .black, 0.22)))
            gleam(s * 0.255, -s * 0.425, s * 0.04, s * 0.025)
        case "headphones":
            var band = Path()
            band.addArc(center: CGPoint(x: 0, y: -s * 0.02), radius: s * 0.52, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            stroke(band, Color(hex: "#2B2B33"), s * 0.075)
            var hi = Path()
            hi.addArc(center: CGPoint(x: 0, y: -s * 0.02), radius: s * 0.52, startAngle: .degrees(215), endAngle: .degrees(270), clockwise: false)
            stroke(hi, .white.opacity(0.2), s * 0.02)
            for side in [-1.0, 1.0] {
                let cup = CGRect(x: side * s * 0.53 - s * 0.085, y: -s * 0.16, width: s * 0.17, height: s * 0.32)
                ctx.fill(Path(roundedRect: cup, cornerRadius: s * 0.07), with: grad("#4A4A57", "#2A2A33", -s * 0.16, s * 0.16))
                ctx.fill(Path(roundedRect: cup.insetBy(dx: s * 0.035, dy: s * 0.05), cornerRadius: s * 0.04), with: .color(Color(hex: "#1B1B21")))
                ctx.fill(oval(side * s * 0.53, 0, s * 0.03, s * 0.03), with: .color(Color(hex: "#5AD1E6")))
            }
        case "helmet":
            var p = Path()
            p.addArc(center: CGPoint(x: 0, y: -s * 0.06), radius: s * 0.54, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            p.closeSubpath()
            ctx.fill(p, with: grad("#E3E7EE", "#7C8492", -s * 0.6, -s * 0.06))
            var ridge = Path(); ridge.move(to: CGPoint(x: 0, y: -s * 0.6)); ridge.addLine(to: CGPoint(x: 0, y: -s * 0.1))
            stroke(ridge, Color(hex: "#5B6270").opacity(0.55), s * 0.03)
            ctx.fill(Path(roundedRect: CGRect(x: -s * 0.56, y: -s * 0.1, width: s * 1.12, height: s * 0.06), cornerRadius: s * 0.02), with: .color(Color(hex: "#555C69")))
            gleam(-s * 0.26, -s * 0.42, s * 0.2, s * 0.08, rot: -0.7, 0.55)
            for x in [-0.34, 0.34] { ctx.fill(oval(s * x, -s * 0.16, s * 0.035, s * 0.035), with: .color(Color(hex: "#3F4551"))) }
        case "mask":
            var m = Path()
            m.move(to: CGPoint(x: -s * 0.46, y: -s * 0.06))
            m.addQuadCurve(to: CGPoint(x: 0, y: -s * 0.1), control: CGPoint(x: -s * 0.22, y: -s * 0.14))
            m.addQuadCurve(to: CGPoint(x: s * 0.46, y: -s * 0.06), control: CGPoint(x: s * 0.22, y: -s * 0.14))
            m.addQuadCurve(to: CGPoint(x: s * 0.34, y: s * 0.17), control: CGPoint(x: s * 0.5, y: s * 0.1))
            m.addQuadCurve(to: CGPoint(x: 0, y: s * 0.13), control: CGPoint(x: s * 0.16, y: s * 0.2))
            m.addQuadCurve(to: CGPoint(x: -s * 0.34, y: s * 0.17), control: CGPoint(x: -s * 0.16, y: s * 0.2))
            m.addQuadCurve(to: CGPoint(x: -s * 0.46, y: -s * 0.06), control: CGPoint(x: -s * 0.5, y: s * 0.1))
            ctx.fill(m, with: grad("#2B2B36", "#0F0F14", -s * 0.14, s * 0.18))
            for side in [-1.0, 1.0] {
                ctx.fill(Path(ellipseIn: CGRect(x: side * s * 0.17 - s * 0.075, y: -s * 0.03, width: s * 0.15, height: s * 0.15)), with: .color(.white))
            }
        case "glasses":
            for side in [-1.0, 1.0] {
                let r = CGRect(x: side * s * 0.17 - s * 0.125, y: -s * 0.1, width: s * 0.25, height: s * 0.25)
                ctx.fill(Path(ellipseIn: r), with: .color(Color(hex: "#9FD8FF").opacity(0.16)))
                stroke(Path(ellipseIn: r), ink, s * 0.03)
                gleam(r.minX + s * 0.07, r.minY + s * 0.06, s * 0.07, s * 0.025, rot: -0.7, 0.6)
                var arm = Path(); arm.move(to: CGPoint(x: side * s * 0.295, y: s * 0.0)); arm.addLine(to: CGPoint(x: side * s * 0.47, y: -s * 0.02))
                stroke(arm, ink, s * 0.025)
            }
            var b = Path(); b.move(to: CGPoint(x: -s * 0.045, y: s * 0.02)); b.addQuadCurve(to: CGPoint(x: s * 0.045, y: s * 0.02), control: CGPoint(x: 0, y: -s * 0.01))
            stroke(b, ink, s * 0.03)
        case "shades":
            for side in [-1.0, 1.0] {
                let r = CGRect(x: side * s * 0.17 - s * 0.14, y: -s * 0.09, width: s * 0.28, height: s * 0.21)
                ctx.fill(Path(roundedRect: r, cornerRadius: s * 0.08), with: grad("#2C2C36", "#0A0A0E", r.minY, r.maxY))
                gleam(r.minX + s * 0.08, r.minY + s * 0.05, s * 0.1, s * 0.025, rot: -0.55, 0.45)
                var arm = Path(); arm.move(to: CGPoint(x: side * s * 0.31, y: -s * 0.03)); arm.addLine(to: CGPoint(x: side * s * 0.48, y: -s * 0.05))
                stroke(arm, ink, s * 0.025)
            }
            var b = Path(); b.move(to: CGPoint(x: -s * 0.04, y: -s * 0.04)); b.addLine(to: CGPoint(x: s * 0.04, y: -s * 0.04))
            stroke(b, ink, s * 0.035)
        default: break
        }
    }
}
