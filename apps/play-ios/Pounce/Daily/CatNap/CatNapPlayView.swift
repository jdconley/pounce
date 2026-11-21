import PounceKit
import SwiftUI

/// Cat Nap's board on a phone or iPad: the beds that count the cats, and the quilt as big as the
/// space allows. Tap a cell for "no cat", again for a cat; drag to mark many. The puzzle host
/// draws everything around it (the top bar, the clock, hints, give up, the end).
struct CatNapPlayView: View {
    @Bindable var model: CatNapModel

    var body: some View {
        GeometryReader { box in
            let beds = CatNapPlayView.bedSize(width: box.size.width, n: model.quilt.n)
            let gap: CGFloat = 16
            let side = CatNapPlayView.side(in: box.size, reserved: beds + gap)
            VStack(spacing: gap) {
                CatNapBeds(n: model.quilt.n, placed: model.check.placed, size: beds)
                board(side: side)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The quilt's side: as big as fits under the beds, with an 8 pt margin, never over 640 pt.
    static func side(in size: CGSize, reserved: CGFloat) -> CGFloat {
        max(0, min(640, size.width - 16, size.height - reserved - 8)).rounded(.down)
    }

    /// The beds shrink to fit nine across an iPhone SE.
    static func bedSize(width: CGFloat, n: Int) -> CGFloat {
        min(36, (width - 32) / (CGFloat(n) * 1.18))
    }

    private func board(side: CGFloat) -> some View {
        let geo = CatNapGeometry(n: model.quilt.n, side: side)
        return CatNapQuilt(quilt: model.quilt, state: model.shown, check: model.check, side: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { model.pointer(at: $0.location, from: $0.startLocation, geo: geo) }
                    .onEnded { _ in model.pointerEnded() },
                isEnabled: model.playing)
            .overlay(alignment: .topLeading) { cells(geo) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Quilt")
            .accessibilityIdentifier("catnap.quilt")
    }

    /// One accessibility element per cell, for VoiceOver and the UI tests; touches pass through to
    /// the quilt's gesture.
    private func cells(_ geo: CatNapGeometry) -> some View {
        ForEach(0..<model.quilt.size, id: \.self) { cell in
            let r = geo.rect(cell)
            Color.clear
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(CatNapPlayView.label(model.quilt, model.shown, cell))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("catnap.cell.\(cell)")
                .accessibilityAction { model.tap(cell) }
        }
    }

    /// "Row 3, column 4, violet stripes, cat."
    static func label(_ quilt: NapQuilt, _ state: NapState, _ cell: Int) -> String {
        let mark = switch state.cells[cell] {
        case NapState.cat: state.hinted.contains(cell) ? ", cat, locked" : ", cat"
        case NapState.noCat: ", no cat"
        default: ""
        }
        return "Row \(cell / quilt.n + 1), column \(cell % quilt.n + 1), \(CatNapFabric.cloth(quilt.patches[cell]).name)\(mark)"
    }
}
