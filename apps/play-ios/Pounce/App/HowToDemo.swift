#if DEBUG
import Foundation
import PounceKit

/// `-demo howto`: the table Cat Tower's How to play video is recorded on
/// (`DemoFixtures.howTo()`, `apps/play-ios/HowTo/`). A fake server that takes one whole turn of
/// mine the way the real one does: the draw (the deck gives the third 9), the lay-down, hits and
/// the discard, a Cucumber's skip included. Then the other seats play a short turn each (draw,
/// discard) and the move comes back to me.
actor HowToSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private var room: RoomView
    private var seq = 1
    private var others: Task<Void, Never>?

    init(room: RoomView = DemoFixtures.howTo()) {
        self.room = room
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    func start() async {
        continuation.yield(.connected)
        continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: room)))
    }

    func send(_ m: ClientMessage) async throws {
        guard case .act(let seat, let action, _) = m, var game = room.game, game.turn == seat else { return }
        try? await Task.sleep(for: Pace.duration(.milliseconds(200)))
        switch action {
        case .draw(let source):
            guard game.step == .draw else { return refuse(.badStep) }
            let card: CardID
            if source == .discard, let top = game.discardTop {
                card = top
                game.discardCount -= 1
                game.discardTop = DemoFixtures.howToDiscards[3]
            } else {
                card = DemoFixtures.howToDraw
                game.deckCount -= 1
            }
            game.hands[seat, default: []].append(card)
            game.handCounts[seat] += 1
            game.step = .play
            commit(game, [.drew(seat: seat, from: source, card: card)])
        case .layDown(let groups):
            guard game.step == .play, let built = Rules.matchPhase(game.phase[seat], groups: groups) else {
                return refuse(.badGroups)
            }
            let used = Set(built.flatMap(\.cards))
            game.laid[seat] = built
            game.hands[seat]?.removeAll { used.contains($0) }
            game.handCounts[seat] -= used.count
            commit(game, [.laidDown(seat: seat, groups: built)])
        case .hit(let card, let target, let side):
            guard game.laid[seat] != nil, var groups = game.laid[safe: target.seat] ?? nil, groups.indices.contains(target.group),
                  let group = Rules.canHit(groups[target.group], card: card, side: side) else {
                return refuse(.badTarget)
            }
            groups[target.group] = group
            game.laid[target.seat] = groups
            game.hands[seat]?.removeAll { $0 == card }
            game.handCounts[seat] -= 1
            commit(game, [.hit(seat: seat, card: card, target: target, group: group)])
        case .discard(let card, let skipTarget):
            guard game.step == .play else { return refuse(.badStep) }
            game.hands[seat]?.removeAll { $0 == card }
            game.handCounts[seat] -= 1
            game.discardTop = card
            game.discardCount += 1
            var events: [GameEvent] = [.discarded(seat: seat, card: card, skipTarget: skipTarget)]
            if let skipTarget { game.pendingSkip[skipTarget] = true }
            events += pass(&game, from: seat)
            commit(game, events)
            playOthers()
        default:
            return
        }
    }

    func reconnectNow() async {}

    func stop() async {
        others?.cancel()
        continuation.finish()
    }

    /// The move goes round from `seat`, past any seat with a skip waiting (each skip spent).
    private func pass(_ game: inout GameView, from seat: Seat) -> [GameEvent] {
        var events: [GameEvent] = []
        var next = (seat + 1) % game.handCounts.count
        while game.pendingSkip[next] {
            game.pendingSkip[next] = false
            events.append(.skipped(seat: next))
            next = (next + 1) % game.handCounts.count
        }
        game.turn = next
        game.step = .draw
        events.append(.turn(seat: next))
        return events
    }

    /// Each other seat draws from the deck and discards, at a House Cat's pace, until the move
    /// is mine again.
    private func playOthers() {
        others?.cancel()
        others = Task {
            while !Task.isCancelled {
                guard var game = room.game, !(room.seats[safe: game.turn]?.yours ?? true) else { return }
                let seat = game.turn
                try? await Task.sleep(for: Pace.duration(.milliseconds(1300)))
                game.deckCount -= 1
                game.handCounts[seat] += 1
                game.step = .play
                commit(game, [.drew(seat: seat, from: .deck, card: nil)])
                try? await Task.sleep(for: Pace.duration(.milliseconds(1100)))
                let card = DemoFixtures.howToDiscards[seat] ?? DemoFixtures.howToDraw
                game.handCounts[seat] -= 1
                game.discardTop = card
                game.discardCount += 1
                let events = [GameEvent.discarded(seat: seat, card: card, skipTarget: nil)] + pass(&game, from: seat)
                commit(game, events)
            }
        }
    }

    private func refuse(_ code: ErrorCode) {
        continuation.yield(.message(.error(code)))
    }

    /// As the server: the events, then the snapshot after them.
    private func commit(_ game: GameView, _ events: [GameEvent]) {
        room.game = game
        for event in events {
            seq += 1
            continuation.yield(.message(.event(seq: seq, event: .game(event))))
        }
        continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: room)))
    }
}
#endif
