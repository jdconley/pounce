#if DEBUG
import PounceKit
import SwiftUI

/// Birdwatch's DEBUG demos (`-demo bird-<name>`, `DemoFixtures.BirdDemo`): the table in each
/// phase with no server. `BirdDemoSocket` answers moves the way the server would, roughly: a bid
/// wins the feeder (everyone else passes), the put-back, trump and the partner call move the hand
/// on, and a card played gets the other seats' cards and the trick. `-demo bird-tv` is `bird-play`
/// at a table a TV shows (just the hand), `-demo bird-lobby` a lobby of three.
enum BirdDemo {
    static func room(_ mode: DemoMode) -> RoomView {
        let name = mode.rawValue.replacingOccurrences(of: "bird-", with: "")
        if name == "lobby" { return DemoFixtures.birdLobby() }
        if name == "lobby-ready" { return DemoFixtures.birdLobby(seated: 4) }
        if name == "tv" {
            var room = DemoFixtures.birdRoom(.play)
            room.screen = true
            return room
        }
        return DemoFixtures.birdRoom(DemoFixtures.BirdDemo(rawValue: name) ?? .play)
    }

    static func socket(_ mode: DemoMode) -> any RoomSocketing { BirdDemoSocket(room: room(mode)) }
}

actor BirdDemoSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private var room: RoomView
    private var seq = 1

    init(room: RoomView) {
        self.room = room
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    func start() async {
        continuation.yield(.connected)
        continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: room)))
    }

    func reconnectNow() async {}
    func stop() async { continuation.finish() }

    private func emit(_ event: BirdEvent) {
        seq += 1
        continuation.yield(.message(.event(seq: seq, event: .birdwatch(event))))
    }

    private func snapshot() {
        continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: room)))
    }

    func send(_ m: ClientMessage) async throws {
        if case .setOptions(let options) = m {
            room.options = options
            return snapshot()
        }
        if case .swapSeats(let a, let b) = m {
            room.seats.swapAt(a, b)
            return snapshot()
        }
        guard case .actBirdwatch(let seat, let action, _) = m, var view = room.birdwatch else { return }
        try? await Task.sleep(for: Pace.duration(.milliseconds(250)))
        let n = view.seats
        switch action {
        case .bid(let amount):
            view.bids[seat] = amount
            view.high = BirdHigh(seat: seat, amount: amount)
            emit(.bid(seat: seat, amount: amount))
            for other in 0..<n where other != seat { view.passed[other] = true; emit(.passed(seat: other)) }
            emit(.bidWon(seat: seat, amount: amount))
            let deck = DemoFixtures.birdDeck(view.rules, seats: n)
            let held = Set(view.hands[seat] ?? [])
            let nest = Array(deck.filter { !held.contains($0) }.prefix(view.nestSize))
            view.hands[seat] = (view.hands[seat] ?? []) + nest
            view.handCounts[seat] += nest.count
            view.fromNest = nest
            view.bidRange = nil
            view.phase = .nest
            emit(.nest(seat: seat, cards: nest))
        case .pass:
            view.passed[seat] = true
            view.bidRange = nil
            emit(.passed(seat: seat))
            view.turn = (seat + 1) % n
            emit(.turn(seat: (seat + 1) % n))
        case .nest(let discard):
            view.hands[seat] = (view.hands[seat] ?? []).filter { !discard.contains($0) }
            view.handCounts[seat] -= discard.count
            view.putBack = discard
            view.fromNest = nil
            view.phase = .trump
            emit(.putBack(seat: seat, count: discard.count, cards: discard))
        case .trump(let suit):
            view.trump = suit
            emit(.trump(seat: seat, suit: suit))
            if view.isFive {
                view.phase = .partner
                let held = Set(view.hands[seat] ?? [])
                view.partnerChoices = DemoFixtures.birdDeck(view.rules, seats: n).filter { !held.contains($0) }
            } else {
                startPlay(&view, leader: seat)
            }
        case .partner(let card):
            view.called = card
            view.partnerChoices = nil
            emit(.called(seat: seat, card: card))
            startPlay(&view, leader: seat)
        case .play(let card):
            view.hands[seat] = (view.hands[seat] ?? []).filter { $0 != card }
            view.handCounts[seat] -= 1
            view.trick.append(BirdTrickCard(seat: seat, card: card))
            view.played.append(card)
            view.playable = nil
            emit(.played(seat: seat, card: card))
            // The other seats follow with cards nobody holds or has played.
            let used = Set(view.played + view.hands.values.flatMap { $0 } + (view.putBack ?? []))
            var free = DemoFixtures.birdDeck(view.rules, seats: n).filter { !used.contains($0) }
            var next = (seat + 1) % n
            while view.trick.count < n, !free.isEmpty {
                let c = free.removeFirst()
                view.trick.append(BirdTrickCard(seat: next, card: c))
                view.played.append(c)
                view.handCounts[next] = max(view.handCounts[next] - 1, 0)
                emit(.played(seat: next, card: c))
                next = (next + 1) % n
            }
            let points = view.trick.reduce(0) { $0 + (BirdCard(id: $1.card)?.points ?? 0) }
            emit(.trick(winner: seat, cards: view.trick, points: points))
            view.lastTrick = BirdLastTrick(cards: view.trick, winner: seat)
            view.trick = []
            view.points[seat] += points
            view.tricks[seat] += 1
            view.turn = seat
            view.playable = view.hands[seat]
            emit(.turn(seat: seat))
        case .forfeit:
            break
        }
        room.birdwatch = view
        snapshot()
    }

    private func startPlay(_ view: inout BirdView, leader: Seat) {
        view.phase = .play
        view.leader = leader
        view.turn = leader
        view.playable = view.hands[leader]
        emit(.turn(seat: leader))
    }
}
#endif
