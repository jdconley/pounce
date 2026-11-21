#if DEBUG
import PounceKit
import SwiftUI

/// Box Fort on a local dealer, for working on the screen without a server: the sets come from a
/// fixed seed in the app, and each one is "dealt" a moment after the set before it is placed, as
/// the server would. Never in a Release build; the real game's sets only ever come from the server.
@MainActor
final class BoxFortDemoDealer {
    private(set) var sets: [[BoxFortPiece]]
    let rug: [Int]
    private var model: BoxFortPlayModel?

    init(seed: UInt64 = 7, sets count: Int = 15, boxes: Int = 8) {
        var rng = SplitMix(seed: seed)
        sets = (0..<count).map { _ in
            (0..<3).map { _ in
                let picture = Self.pictures[Int(rng.next() % UInt64(Self.pictures.count))]
                return Self.piece(picture, tint: 1 + Int(rng.next() % 6))
            }
        }
        var rug = [Int](repeating: 0, count: 64)
        var placed = 0
        while placed < boxes {
            let at = Int(rng.next() % 64)
            if rug[at] == 0 && at / 8 != 7 { rug[at] = BoxFortRules.clutter; placed += 1 }
        }
        self.rug = rug
    }

    func makeModel() -> BoxFortPlayModel {
        let start = BoxFortRules.start(BoxFortPublicPuzzle(rug: rug, sets: sets.count, pieces: sets[0]))
        var placedInSet = 0
        var set = 0
        let model = BoxFortPlayModel(state: start) { [weak self] _, _ in
            placedInSet += 1
            guard placedInSet == 3 else { return }
            placedInSet = 0
            set += 1
            guard let self, set < self.sets.count else { return }
            let reveal = BoxFortReveal(set: set, pieces: self.sets[set])
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                await self?.model?.receive(reveal)
            }
        }
        self.model = model
        return model
    }

    private static let pictures = [
        "#", "##", "#/#", "###", "#/#/#", "##/##", "##/#.", ".#/##", "####", "#/#/#/#", "###/###",
        "#./#./##", "###/#..", ".#./###", "#####", "###/###/###", "##./.##", ".#./###/.#.", "#./.#", "###/..#/..#",
    ]

    private static func piece(_ picture: String, tint: Int) -> BoxFortPiece {
        var cells: [BoxFortCell] = []
        for (r, line) in picture.split(separator: "/").enumerated() {
            for (c, ch) in line.enumerated() where ch == "#" { cells.append(BoxFortCell(row: r, col: c)) }
        }
        return BoxFortPiece(id: picture, tint: tint, cells: cells)
    }

    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

/// The play view on the local dealer, on the app's night background.
struct BoxFortDemoScreen: View {
    @State private var dealer = BoxFortDemoDealer()
    @State private var model: BoxFortPlayModel?

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            if let model { BoxFortPlayView(model: model) }
        }
        .onAppear { if model == nil { model = dealer.makeModel() } }
    }
}

#Preview("Box Fort") { BoxFortDemoScreen() }

#Preview("Box Fort, watching") {
    let dealer = BoxFortDemoDealer()
    ZStack {
        Palette.night.ignoresSafeArea()
        BoxFortWatch(state: BoxFortRules.start(BoxFortPublicPuzzle(rug: dealer.rug, sets: 15, pieces: dealer.sets[0])))
    }
}
#endif
