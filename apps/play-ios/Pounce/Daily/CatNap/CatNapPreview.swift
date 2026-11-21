#if DEBUG
import PounceKit
import SwiftUI

/// Cat Nap on a local board, until the Dish's puzzle host runs it against the server: sample
/// quilts from the server's maker (copied from its golden vectors and tests), moves kept here.
enum CatNapSamples {
    /// Monday's size, 5 by 5.
    static let small = NapQuilt(n: 5, patches: [0, 0, 1, 1, 1, 0, 2, 2, 1, 1, 3, 2, 2, 2, 1, 3, 3, 2, 4, 4, 3, 3, 4, 4, 4])
    /// Sunday's size, 9 by 9 (the `finish-9x9` vector's quilt).
    static let large = NapQuilt(n: 9, patches: [
        0, 0, 0, 0, 1, 2, 3, 3, 3,
        0, 0, 0, 0, 1, 1, 3, 3, 3,
        0, 0, 0, 0, 0, 1, 1, 1, 1,
        0, 4, 4, 1, 1, 1, 1, 1, 1,
        0, 0, 4, 4, 4, 5, 1, 1, 6,
        0, 7, 4, 4, 4, 5, 1, 1, 6,
        0, 7, 4, 4, 4, 5, 5, 6, 6,
        7, 7, 7, 5, 5, 5, 5, 8, 6,
        7, 7, 7, 5, 5, 5, 8, 8, 8,
    ])

    /// A board mid-run: some "no cat" marks, two cats, and two that touch.
    static func midRun(_ quilt: NapQuilt) -> NapState {
        var s = NapState.empty(quilt)
        for cell in [0, 1, 2, 9, 10] where cell < quilt.size { s.cells[cell] = NapState.noCat }
        for cell in [4, 12, 13] where cell < quilt.size { s.cells[cell] = NapState.cat }
        return s
    }
}

/// DEBUG `-catnap-lab <small|large|watch>`: the board alone on a local state, for looking at it
/// before the Dish's host exists.
struct CatNapLabScreen: View {
    var body: some View {
        let args = CommandLine.arguments
        let which = args.firstIndex(of: "-catnap-lab").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "large"
        switch which {
        case "small": CatNapLab(quilt: CatNapSamples.small)
        case "watch":
            CatNapWatchView(quilt: CatNapSamples.large, state: CatNapSamples.midRun(CatNapSamples.large))
                .padding(24)
                .background(Palette.night.ignoresSafeArea())
        default: CatNapLab(quilt: CatNapSamples.large, state: CatNapSamples.midRun(CatNapSamples.large))
        }
    }
}

private struct CatNapLab: View {
    @State private var model: CatNapModel

    init(quilt: NapQuilt, state: NapState? = nil) {
        _model = State(initialValue: CatNapModel(quilt: quilt, state: state) { _ in })
    }

    var body: some View {
        CatNapPlayView(model: model)
            .padding(.vertical, 24)
            .background(Palette.night.ignoresSafeArea())
    }
}

#Preview("5 by 5") { CatNapLab(quilt: CatNapSamples.small) }
#Preview("9 by 9 mid-run") { CatNapLab(quilt: CatNapSamples.large, state: CatNapSamples.midRun(CatNapSamples.large)) }
#Preview("Watch") {
    CatNapWatchView(quilt: CatNapSamples.large, state: CatNapSamples.midRun(CatNapSamples.large))
        .padding(48)
        .background(Palette.night)
}
#endif
