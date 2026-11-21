import PounceKit
import SwiftUI

/// Someone's Box Fort run as the server sees it, for a TV that pressed Watch (spec §8): the
/// score row, the rug and the set in play, read only. It draws with the play view's own parts.
/// Built for tvOS too: nothing here takes input or uses the phone's haptics.
struct BoxFortWatch: View {
    let state: BoxFortState

    var body: some View {
        GeometryReader { geo in
            // A TV is read from the couch: the score row grows with the stage, and its text with the row.
            let layout = BoxFortLayout(size: geo.size, headerHeight: BoxFortLayout.watchHeader(for: geo.size))
            ZStack(alignment: .topLeading) {
                BoxFortHeader(points: state.points, combo: state.combo, set: state.set, sets: state.sets, height: layout.header.height)
                    .frame(width: layout.header.width)
                    .offset(x: layout.header.minX, y: layout.header.minY)
                BoxFortRugView(rug: state.rug, cell: layout.cell)
                    .equatable()
                    .offset(x: layout.rug.minX, y: layout.rug.minY)
                ForEach(state.left, id: \.self) { slot in
                    if state.pieces.indices.contains(slot) {
                        BoxFortTrayPiece(piece: state.pieces[slot], layout: layout, slot: slot, fits: true)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                if let over = state.over {
                    BoxFortOverStamp(over: over, layout: layout)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.spring(duration: Pace.seconds(0.3), bounce: 0.3), value: state)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Box Fort")
        .accessibilityValue("\(state.points) points, set \(min(state.set + 1, state.sets)) of \(state.sets)")
    }
}

/// A TV watching a Box Fort run: the public state carries the rug and the set in play, so the
/// puzzle isn't needed.
extension BoxFortWatch: DailyWatchView {
    nonisolated static let game = DailyCatalog.boxFort

    init(puzzle: BoxFortPublicPuzzle, state: BoxFortState) {
        self.init(state: state)
    }
}
