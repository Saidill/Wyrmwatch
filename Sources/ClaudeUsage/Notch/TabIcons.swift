import SwiftUI

/// The four tab icons, drawn as outlines (not SF Symbols) so they share one line weight.

struct HomeIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        p.move(to: pt(0.1, 0.48))
        p.addLine(to: pt(0.5, 0.13))
        p.addLine(to: pt(0.9, 0.48))
        p.move(to: pt(0.22, 0.4))
        p.addLine(to: pt(0.22, 0.86))
        p.addLine(to: pt(0.78, 0.86))
        p.addLine(to: pt(0.78, 0.4))
        p.move(to: pt(0.42, 0.86))
        p.addLine(to: pt(0.42, 0.62))
        p.addLine(to: pt(0.58, 0.62))
        p.addLine(to: pt(0.58, 0.86))
        return p
    }
}

/// A stopwatch.
struct FocusIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        let radius = 0.34 * min(r.width, r.height)
        p.addEllipse(in: CGRect(x: pt(0.5, 0.58).x - radius, y: pt(0.5, 0.58).y - radius, width: radius * 2, height: radius * 2))
        p.move(to: pt(0.4, 0.1))
        p.addLine(to: pt(0.6, 0.1))
        p.move(to: pt(0.5, 0.1))
        p.addLine(to: pt(0.5, 0.24))
        p.move(to: pt(0.5, 0.58))
        p.addLine(to: pt(0.62, 0.44))
        p.move(to: pt(0.8, 0.22))
        p.addLine(to: pt(0.87, 0.29))
        return p
    }
}

/// Two beamed eighth notes.
struct MusicIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        let head = 0.12 * r.width
        for c in [pt(0.3, 0.76), pt(0.74, 0.68)] {
            p.addEllipse(in: CGRect(x: c.x - head * 1.15, y: c.y - head * 0.85, width: head * 2.3, height: head * 1.7))
        }
        p.move(to: pt(0.43, 0.74))
        p.addLine(to: pt(0.43, 0.2))
        p.addLine(to: pt(0.87, 0.12))
        p.addLine(to: pt(0.87, 0.66))
        p.move(to: pt(0.43, 0.34))
        p.addLine(to: pt(0.87, 0.26))
        return p
    }
}

/// A four-pointed sparkle.
struct ClaudeIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let outer = 0.46 * Double(min(r.width, r.height)), inner = 0.12 * Double(min(r.width, r.height))
        let cx = Double(c.x), cy = Double(c.y)
        for i in 0..<4 {
            let a = Double(i) * .pi / 2 - .pi / 2
            let tip = CGPoint(x: cx + cos(a) * outer, y: cy + sin(a) * outer)
            let next = Double(i + 1) * .pi / 2 - .pi / 2
            let tip2 = CGPoint(x: cx + cos(next) * outer, y: cy + sin(next) * outer)
            let mid = (a + next) / 2
            let waist = CGPoint(x: cx + cos(mid) * inner, y: cy + sin(mid) * inner)
            if i == 0 { p.move(to: tip) }
            p.addQuadCurve(to: tip2, control: waist)
        }
        p.closeSubpath()
        return p
    }
}

/// A gear: a ring with six teeth.
struct SettingsIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let side = Double(min(r.width, r.height))
        let outer = 0.44 * side, inner = 0.31 * side, hole = 0.13 * side
        let cx = Double(c.x), cy = Double(c.y)
        for i in 0..<12 {
            // Alternate tooth tops and gaps, each a short arc.
            let radius = i % 2 == 0 ? outer : inner
            let a0 = Double(i) * .pi / 6 - .pi / 14, a1 = Double(i) * .pi / 6 + .pi / 14
            let start = CGPoint(x: cx + cos(a0) * radius, y: cy + sin(a0) * radius)
            if i == 0 { p.move(to: start) } else { p.addLine(to: start) }
            p.addLine(to: CGPoint(x: cx + cos(a1) * radius, y: cy + sin(a1) * radius))
        }
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: cx - hole, y: cy - hole, width: hole * 2, height: hole * 2))
        return p
    }
}
