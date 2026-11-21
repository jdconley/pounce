import PounceKit
import SwiftUI

/// Pieces of the Box Fort screen that the play view and the TV's watch view both draw.

/// The row over the rug: points on the left, the combo when there is one, and the set count.
struct BoxFortHeader: View {
    let points: Int
    let combo: Int
    let set: Int
    let sets: Int
    let height: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            OutlinedText("\(points)", size: height * 0.62)
                .fixedSize()
                .pop(trigger: points)
                .accessibilityLabel("Points")
                .accessibilityValue("\(points)")
                .accessibilityIdentifier("boxfort.points")
            Spacer(minLength: 4)
            if combo >= 2 {
                Text("Combo \(combo)")
                    .font(.system(size: height * 0.34, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.yellow))
                    .overlay(Capsule().stroke(Palette.ink, lineWidth: 2.5))
                    .pop(trigger: combo)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityIdentifier("boxfort.combo")
                Spacer(minLength: 4)
            }
            Text("Set \(min(set + 1, sets)) of \(sets)")
                .font(.system(size: height * 0.34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
                .accessibilityIdentifier("boxfort.set")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: height)
        .animation(.spring(duration: Pace.seconds(0.25)), value: combo >= 2)
    }
}

/// A tray slot's piece at tray scale, centered in its slot. A piece with no room anywhere dims
/// (one layer, so its boxes don't show through each other).
struct BoxFortTrayPiece: View {
    let piece: BoxFortPiece
    let layout: BoxFortLayout
    let slot: Int
    let fits: Bool

    var body: some View {
        let origin = layout.trayOrigin(slot: slot, size: piece.size)
        BoxFortPieceView(piece: piece, cell: layout.trayCell)
            .equatable()
            .compositingGroup()
            .opacity(fits ? 1 : 0.35)
            .offset(x: origin.x, y: origin.y)
    }
}

/// The stamp across the rug when the run is over.
struct BoxFortOverStamp: View {
    let over: BoxFortState.Over
    let layout: BoxFortLayout

    var body: some View {
        let text = over == .full ? "Full fort" : "Out of room"
        OutlinedText(text, size: layout.cell * 0.85, fill: over == .full ? Palette.yellow : .white, width: 4)
            .padding(.horizontal, layout.cell * 0.4)
            .padding(.vertical, layout.cell * 0.15)
            .background(RoundedRectangle(cornerRadius: layout.cell * 0.25).fill(over == .full ? Palette.magenta : Palette.violet))
            .overlay(RoundedRectangle(cornerRadius: layout.cell * 0.25).stroke(Palette.ink, lineWidth: 4))
            .rotationEffect(.degrees(-8))
            .frame(maxWidth: layout.rug.width)
            .position(x: layout.rug.midX, y: layout.rug.midY)
            .transition(.scale(scale: 2).combined(with: .opacity))
            .accessibilityIdentifier("boxfort.over")
    }
}
