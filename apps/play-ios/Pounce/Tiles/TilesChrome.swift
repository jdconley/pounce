import PounceKit
import SwiftUI

/// The tile game's chrome while a TV shows the table: the Cards/Table switch in its band at the
/// top (the scene's paw at its right end), in the same place on both, and while the stash is all
/// there is (Cards, off turn) the status line under it. It measures both at the person's text size
/// and tells the stage how the scene should draw (`TVFrame`), as Cat Tower's `CardsChrome` does.
struct TilesChrome: View {
    let shown: TableShown
    /// Whose turn it is, shown under the switch while the scene draws just the stash.
    let status: (text: String, mine: Bool)?
    let onSwitch: (TablePick) -> Void
    let onFrame: (TVFrame) -> Void

    @State private var measured = Measured()

    private struct Measured: Equatable {
        var band: CGFloat = 38
        var status: CGFloat = 30
    }

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(
                width: geo.size.width + insets.leading + insets.trailing,
                height: geo.size.height + insets.top + insets.bottom)
            let chrome = ControllerChrome(switchBand: measured.band + 6, status: measured.status + 2)
            // The switch's band and the status line are where the scene's layout leaves them.
            let layout = TilesLayout(
                size: full, safeTop: insets.top, safeBottom: insets.bottom, opponents: 1, rackCount: TilesRules.rackSize,
                controller: .rackOnly(chrome))
            let frame: TVFrame = shown == .cards ? .cards(chrome) : .table(switchBand: layout.switchBand.height)
            // Scene space (y up from the bottom of the screen) to this view's.
            let local: (CGRect) -> CGRect = { r in
                CGRect(x: r.minX - insets.leading, y: full.height - r.maxY - insets.top, width: r.width, height: r.height)
            }
            let band = local(layout.switchBand)
            ZStack(alignment: .topLeading) {
                ViewSwitch(shown: shown, onPick: onSwitch)
                    // Clear of the paw at the band's right end, and centred.
                    .frame(maxWidth: max(band.width - 2 * (TilesLayout.buttonHit + 8), 160))
                    .position(x: band.midX, y: band.midY)
                if shown == .cards, let status {
                    let line = local(layout.statusLine)
                    StatusLine(text: status.text, mine: status.mine)
                        .frame(width: line.width, height: line.height)
                        .position(x: line.midX, y: line.midY)
                        .transition(.opacity)
                }
            }
            .onChange(of: frame, initial: true) { _, frame in onFrame(frame) }
            .background { templates }
        }
        .animation(.easeOut(duration: 0.2).paced, value: status?.text)
    }

    /// Unseen copies of the switch and the status line, for their heights at this text size.
    private var templates: some View {
        VStack {
            ViewSwitch(shown: .table) { _ in }
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.band = $0 }
            StatusLine(text: "Your turn", mine: true)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.status = $0 }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
