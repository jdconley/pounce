import PounceKit
import SwiftUI

/// Someone's Cat Nap run as the server sees it, for a TV that pressed Watch: the beds and the
/// quilt, no input. Drawn by the same code as the phone's board. The rule check runs off the
/// main actor each time a frame brings new cats.
struct CatNapWatchView: View {
    let quilt: NapQuilt
    let state: NapState

    @State private var check: NapCheck = .none

    var body: some View {
        GeometryReader { box in
            let beds = min(56, box.size.width / (CGFloat(quilt.n) * 1.18) * 0.5)
            let side = max(0, min(box.size.width, box.size.height - beds - 24)).rounded(.down)
            VStack(spacing: 24) {
                CatNapBeds(n: quilt.n, placed: check.placed, size: beds)
                CatNapQuilt(quilt: quilt, state: state, check: check, side: side)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: state) { check = await CatNapRules.check(quilt, state) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cat Nap, \(check.placed) of \(quilt.n) cats")
    }
}
