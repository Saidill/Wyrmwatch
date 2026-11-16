import SwiftUI

// The Hearth design: no boxes. Rules and type on black, outlined controls, numbers and titles in the system
// serif, bone-coloured text and one amber accent taken from the dragon's eye.

/// The outline of every control and of the few filled plates left (pops, covers): a continuous rounded
/// rectangle, or a plain capsule once the radius reaches half the height.
struct Plate: InsettableShape {
    var radius: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        // A continuous shape draws stray ticks at its ends when stroked as a pill.
        if radius >= min(rect.width, rect.height) / 2 { return Capsule(style: .circular).path(in: r) }
        return RoundedRectangle(cornerRadius: max(radius - inset, 0), style: .continuous).path(in: r)
    }

    func inset(by amount: CGFloat) -> Plate { Plate(radius: radius, inset: inset + amount) }
}

/// A block of the page: no box, just a rule down its left edge, like a ledger column. The rule of an `active`
/// block (Claude working, a timer running) takes the accent.
struct CardSurface: ViewModifier {
    var padding: CGFloat = 12
    var active = false
    /// Stretch to the height on offer (cards side by side); off for blocks that size themselves.
    var fillHeight = true

    func body(content: Content) -> some View {
        content.padding(.leading, padding).padding(.trailing, 4).padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .overlay(alignment: .leading) { Rectangle().fill(active ? Palette.accent : Palette.hairline).frame(width: 1) }
    }
}

/// What sits behind a button, tab, preset or field: an outline. `on` (selected, hovered, or a block's main
/// action) fills it.
struct ControlPlate: View {
    var radius: CGFloat = Radius.button
    var on = false

    var body: some View {
        let shape = Radius.shape(radius)
        shape.fill(on ? Palette.buttonHi : .clear)
            .overlay(shape.strokeBorder(on ? Palette.text3 : Palette.hairline, lineWidth: 1))
    }
}
