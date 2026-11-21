#if DEBUG
import PounceKit
import SwiftUI

/// DEBUG: Sniff on local state, with no server (`-demo-sniff <fresh|mid|solved|missed>`), until
/// the Dish's host runs it (phase B). The demo's referee answers with the server's own reveals for
/// one run (`SniffDemo`, the answer KITTY); any other word comes back plain. The top bar stands in
/// for the host's.
struct SniffDemoView: View {
    let start: SniffBoard

    static func from(arguments: [String] = CommandLine.arguments) -> SniffDemoView? {
        guard let i = arguments.firstIndex(of: "-demo-sniff") else { return nil }
        let name = arguments.indices.contains(i + 1) ? arguments[i + 1] : "fresh"
        let script = SniffDemo.script.map(\.guess)
        let board: SniffBoard =
            switch name {
            case "mid": SniffBoard(guesses: Array(script.prefix(2)))
            case "solved": SniffBoard(guesses: script, answer: SniffDemo.answer)
            case "missed":
                SniffBoard(
                    guesses: Array(script.prefix(5)) + [SniffGuess(word: "crane", marks: Array(repeating: .none, count: 5))],
                    answer: SniffDemo.answer)
            default: SniffBoard()
            }
        return SniffDemoView(start: board)
    }

    var body: some View {
        VStack(spacing: 0) {
            OutlinedText("Sniff", size: 30)
                .frame(height: 56)
                .accessibilityAddTraits(.isHeader)
            SniffPlayView(model: SniffPlayModel(board: start, referee: DemoReferee()))
        }
        .background(Palette.night.ignoresSafeArea())
    }
}

/// Answers like the server, a round trip later.
private struct DemoReferee: SniffReferee {
    func guess(_ word: String) async -> SniffReveal? {
        try? await Task.sleep(for: Pace.duration(.milliseconds(350)))
        return SniffDemo.reveal(word)
    }
}
#endif
