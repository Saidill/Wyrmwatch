import SwiftUI

/// Design directions under review (docs/directions/README.md). `current` is what ships. The other three are
/// prototypes for Home and Focus only, shown with `--design <name>` or by the self-test's `--only directions`;
/// none of them is applied to the rest of the app until one is chosen.
enum Design: String, CaseIterable {
    case current
    /// Slabs of cut volcanic glass: chamfered corners, one lit edge.
    case obsidian
    /// No boxes: rules and type on black, the dragon walking the header's ground line.
    case hearth
    /// Raised plates and sunken wells, soft and heavy; the dragon perched on the first card.
    case vault

    static var active: Design = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--design"), args.count > i + 1, let design = Design(rawValue: args[i + 1]) { return design }
        return .current
    }()

    /// One value per direction, in the order current, obsidian, hearth, vault.
    static func pick<T>(_ current: T, _ obsidian: T, _ hearth: T, _ vault: T) -> T {
        switch active {
        case .current: return current
        case .obsidian: return obsidian
        case .hearth: return hearth
        case .vault: return vault
        }
    }
}

/// The outline of every card, button and tab: rounded today; cut corners in Obsidian; fuller rounds in Vault.
struct Plate: InsettableShape {
    var radius: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        switch Design.active {
        case .obsidian:
            let c = min(max(radius - inset, 0) * 0.45, min(r.width, r.height) / 2)
            var p = Path()
            p.move(to: CGPoint(x: r.minX + c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
            p.closeSubpath()
            return p
        case .vault:
            // Cards a little rounder; controls fully round.
            if radius < Radius.card { return Capsule(style: .circular).path(in: r) }
            return RoundedRectangle(cornerRadius: max(radius + 2 - inset, 0), style: .continuous).path(in: r)
        default:
            // A radius of half the height is a pill; a continuous one draws stray ticks at its ends when stroked.
            if radius >= min(rect.width, rect.height) / 2 { return Capsule(style: .circular).path(in: r) }
            return RoundedRectangle(cornerRadius: max(radius - inset, 0), style: .continuous).path(in: r)
        }
    }

    func inset(by amount: CGFloat) -> Plate { Plate(radius: radius, inset: inset + amount) }
}

/// The lit top edge of an Obsidian slab: the top side and its two cut corners.
private struct SlabEdge: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        let c = min(radius * 0.45, min(r.width, r.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        return p
    }
}

/// A card's surface. `active` (Claude working, a timer running) is the one place the accent appears on a card.
struct CardSurface: ViewModifier {
    var padding: CGFloat = 12
    var active = false

    func body(content: Content) -> some View {
        let shape = Radius.shape(Radius.card)
        switch Design.active {
        case .current:
            content.padding(padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(shape.fill(Palette.card))
                .overlay(shape.strokeBorder(active ? Palette.buttonHi : .clear, lineWidth: 1))
        case .obsidian:
            // A slab: flat violet-black, light only on the top edge.
            content.padding(padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(shape.fill(Palette.card))
                .overlay(SlabEdge(radius: Radius.card).stroke(active ? Palette.accent : Palette.hairline, lineWidth: 1))
        case .hearth:
            // No box: a rule down the block's left edge, like a ledger column.
            content.padding(.leading, padding).padding(.trailing, 4).padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .leading) { Rectangle().fill(active ? Palette.accent : Palette.hairline).frame(width: 1) }
        case .vault:
            // A raised plate, lit from above; the active one sits higher and catches the ember.
            let rim = LinearGradient(colors: [active ? Palette.accent.opacity(0.7) : Color.white.opacity(0.1), .clear],
                                     startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))
            content.padding(padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(shape.fill(active ? Palette.raised : Palette.card))
                .overlay(shape.strokeBorder(rim, lineWidth: 1))
        }
    }
}

/// What sits behind a button, tab, preset or field. `on`: selected, active or hovered.
struct ControlPlate: View {
    var radius: CGFloat = Radius.button
    var on = false

    var body: some View {
        // A radius of half the height or more means a pill.
        GeometryReader { geo in
            plate(Radius.shape(min(radius, geo.size.height / 2)))
        }
    }

    @ViewBuilder
    private func plate(_ shape: Plate) -> some View {
        switch Design.active {
        case .hearth:
            // Outlined, never filled until it is on.
            shape.fill(on ? Palette.buttonHi : .clear)
                .overlay(shape.strokeBorder(on ? Palette.text3 : Palette.hairline, lineWidth: 1))
        case .vault:
            // Off: a well, shaded at the top. On: a raised stud, lit at the top.
            let edge = on
                ? LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom)
                : LinearGradient(colors: [.black.opacity(0.8), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom)
            shape.fill(on ? Palette.buttonHi : Palette.button).overlay(shape.strokeBorder(edge, lineWidth: 1))
        default:
            shape.fill(on ? Palette.buttonHi : Palette.button)
        }
    }
}
