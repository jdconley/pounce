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

    /// The samples' solutions (the column of each row's cat), for the local referee's hints.
    static func solution(_ quilt: NapQuilt) -> [Int] { quilt.n == 5 ? [1, 3, 0, 2, 4] : [5, 7, 0, 4, 2, 8, 1, 3, 6] }

    /// A board mid-run: some "no cat" marks, two cats, and two that touch.
    static func midRun(_ quilt: NapQuilt) -> NapState {
        var s = NapState.empty(quilt)
        for cell in [0, 1, 2, 9, 10] where cell < quilt.size { s.cells[cell] = NapState.noCat }
        for cell in [4, 12, 13] where cell < quilt.size { s.cells[cell] = NapState.cat }
        return s
    }
}

/// A daily server in memory for one Cat Nap run, refereed by the Swift rules and the sample's
/// known solution: it takes every legal batch, answers hints as the server's module does, and ends
/// the run solved when the cats are the solution. So `CatNapDaily` plays through a real
/// `DailyRunSession` before the Dish's host and a local server are wired up.
actor CatNapLocalReferee: DailyService {
    let quilt: NapQuilt
    let solution: [Int]
    private var state: NapState
    private var seq = 0
    private var hints = 0
    private let began = Date()

    init(quilt: NapQuilt) {
        self.quilt = quilt
        solution = CatNapSamples.solution(quilt)
        state = .empty(quilt)
    }

    nonisolated func startAnswer() -> DailyStart {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return DailyStart(
            run: "lab", game: "cat-nap", date: "2027-01-04", number: 1, level: quilt.n == 5 ? 1 : 7, startedAt: now, now: now,
            puzzle: (try? DailyJSON(quilt)) ?? .null, state: (try? DailyJSON(NapState.empty(quilt))) ?? .null, seq: 0, hints: 0,
            result: nil, closesAt: now + 3_600_000)
    }

    private var solved: Bool { state.cats == solution.enumerated().map { $0.offset * quilt.n + $0.element } }

    private func answer(reveals: [DailyJSON]) -> DailyMovesAnswer {
        let ms = Int(Date().timeIntervalSince(began) * 1000) + 30_000 * hints
        let progress = Double(CatNapRules.placed(quilt, state)) / Double(quilt.n)
        let result = solved
            ? DailyResult(game: "cat-nap", date: "2027-01-04", number: 1, outcome: .solved, timeMs: ms, hints: hints, progress: 1) : nil
        return .accepted(seq: seq, reveals: reveals, progress: progress, result: result)
    }

    func start(game: String, person: String?) async throws -> DailyStart { startAnswer() }

    func moves(run: String, body: DailyMovesBody, person: String?) async throws -> DailyMovesAnswer {
        guard body.from == seq else { return .refused(.stale, at: 0, seq: seq) }
        var next = state
        for (i, raw) in body.moves.enumerated() {
            guard let move = try? raw.decoded(as: NapMove.self), let applied = CatNapRules.apply(quilt, next, move) else {
                return .refused(.illegal, at: i, seq: seq)
            }
            next = applied
        }
        state = next
        seq += body.moves.count
        return answer(reveals: [])
    }

    func hint(run: String, hints used: Int, person: String?) async throws -> DailyMovesAnswer {
        guard used == hints else { return answer(reveals: []) }  // a resend: already given
        let cats = state.cats
        guard let cell = solution.enumerated().map({ $0.offset * quilt.n + $0.element }).first(where: { cell in
            state.cells[cell] != NapState.cat || cats.contains { CatNapRules.conflict(quilt, cell, $0) }
        }) else { return .refused(.over, at: 0, seq: seq) }
        state = CatNapRules.applyHint(quilt, state, cell: cell)
        hints += 1
        return answer(reveals: [(try? DailyJSON(NapReveal(cell: cell))) ?? .null])
    }

    func giveUp(run: String, person: String?) async throws -> DailyMovesAnswer { answer(reveals: []) }
    func showOnTV(run: String, on: Bool, person: String?) async throws {}
    func board(date: String?, person: String?) async throws -> DailyBoard { throw APIError.notFound }
    func stats(person: String?) async throws -> DailyStatsList { throw APIError.notFound }
    func linkBoard(_ key: ScreenKey, person: String?) async throws {}
    func unlinkBoard(person: String?) async throws {}
}

/// The Cat Nap screen on a local referee, laid out as the Dish's puzzle host will: a top bar,
/// then the game's box.
private struct CatNapDailyLab: View {
    let session: DailyRunSession
    let quilt: NapQuilt
    @State private var ended: DailyResult?

    init(quilt: NapQuilt) {
        let referee = CatNapLocalReferee(quilt: quilt)
        self.quilt = quilt
        session = DailyRunSession(start: referee.startAnswer(), service: referee, person: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(ended.map { "\($0.outcome.rawValue) \($0.timeMs / 1000)s, \($0.hints) hints" } ?? "Cat Nap 1")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.black.opacity(0.25))
                .accessibilityIdentifier("catnap.lab.status")
            CatNapDaily(session: session, puzzle: quilt, state: .empty(quilt))
                .padding(.vertical, 12)
        }
        .background(Palette.night.ignoresSafeArea())
        .task {
            for await event in await session.events() { if case .ended(let r) = event { ended = r } }
        }
    }
}

/// DEBUG `-catnap-lab <small|large|watch|daily|daily-small>`: the board on a local state (or a
/// local referee), for looking at it before the Dish's host exists.
struct CatNapLabScreen: View {
    var body: some View {
        let args = CommandLine.arguments
        let which = args.firstIndex(of: "-catnap-lab").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "large"
        switch which {
        case "small": CatNapLab(quilt: CatNapSamples.small)
        case "daily": CatNapDailyLab(quilt: CatNapSamples.large)
        case "daily-small": CatNapDailyLab(quilt: CatNapSamples.small)
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
