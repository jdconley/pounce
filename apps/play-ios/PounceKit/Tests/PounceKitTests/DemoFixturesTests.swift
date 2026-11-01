import Testing
@testable import PounceKit

@Suite struct DemoFixturesTests {
    /// Every table size and seat the demo can ask for.
    static let shapes: [(seats: Int, mySeat: Seat, phase: Int)] = [
        (2, 0, 0), (3, 1, 4), (4, 0, 2), (4, 3, 9), (5, 2, 6), (6, 5, 1),
    ]

    @Test(arguments: shapes.indices)
    func tableIsMyTurnWithOnlyMyHand(_ i: Int) throws {
        let (seats, mySeat, phase) = Self.shapes[i]
        let room = DemoFixtures.table(seats: seats, mySeat: mySeat, phase: phase)
        let model = TableModel(room: room)
        let game = try #require(room.game)
        #expect(room.status == .playing)
        #expect(room.seats.count == seats)
        #expect(model.mySeats == [mySeat])
        #expect(model.isMyTurn)
        #expect(Set(game.hands.keys) == [mySeat])
        #expect(game.phase[mySeat] == phase)
    }

    @Test(arguments: shapes.indices)
    func tableArraysMatchSeatCount(_ i: Int) throws {
        let (seats, mySeat, phase) = Self.shapes[i]
        let game = try #require(DemoFixtures.table(seats: seats, mySeat: mySeat, phase: phase).game)
        for count in [game.phase.count, game.scores.count, game.laid.count, game.handCounts.count, game.pendingSkip.count] {
            #expect(count == seats)
        }
    }

    @Test(arguments: shapes.indices)
    func tableCardsAreConsistent(_ i: Int) throws {
        let (seats, mySeat, phase) = Self.shapes[i]
        let game = try #require(DemoFixtures.table(seats: seats, mySeat: mySeat, phase: phase).game)
        // Hand counts match the visible hands.
        for (seat, hand) in game.hands {
            #expect(game.handCounts[seat] == hand.count)
        }
        // Every visible id is a real card and appears once.
        var visible = game.hands.values.flatMap { $0 }
        visible += game.laid.compactMap { $0 }.flatMap { $0.flatMap(\.cards) }
        if let top = game.discardTop { visible.append(top) }
        #expect(visible.allSatisfy { (0..<Card.deckSize).contains($0) })
        #expect(Set(visible).count == visible.count)
        // The whole deck is accounted for.
        let laidCount = game.laid.compactMap { $0 }.flatMap { $0 }.reduce(0) { $0 + $1.cards.count }
        #expect(game.deckCount + game.discardCount + game.handCounts.reduce(0, +) + laidCount == Card.deckSize)
        #expect(game.discardCount >= (game.discardTop == nil ? 0 : 1))
    }

    @Test(arguments: shapes.indices)
    func laidGroupsMatchTheirPhase(_ i: Int) throws {
        let (seats, mySeat, phase) = Self.shapes[i]
        let game = try #require(DemoFixtures.table(seats: seats, mySeat: mySeat, phase: phase).game)
        #expect(game.laid.contains { $0 != nil }, "the demo shows a laid zone")
        for (seat, groups) in game.laid.enumerated() {
            guard let groups else { continue }
            let lay = groups.map { LayGroup(cards: $0.cards) }
            #expect(Rules.matchPhase(game.phase[seat], groups: lay) != nil)
        }
    }

    @Test func lobbyIsMineAndWaiting() {
        let room = DemoFixtures.lobby()
        let model = TableModel(room: room)
        #expect(room.status == .lobby)
        #expect(room.game == nil)
        #expect(room.seats.count == 6)
        #expect(model.mySeats.count == 1)
        #expect(room.seats.contains { $0.kind == .bot })
        #expect(room.seats.contains { $0.kind == .human && !$0.yours })
        #expect(room.seats.allSatisfy { ($0.kind == .human) == ($0.person != nil) })
    }

    @Test func curtainHasTwoLocalHandsAndHidesThem() throws {
        let room = DemoFixtures.curtain()
        let model = TableModel(room: room)
        let game = try #require(room.game)
        #expect(model.mySeats.count == 2)
        #expect(model.isMyTurn)
        #expect(Set(game.hands.keys) == Set(model.mySeats))
        for (seat, hand) in game.hands {
            #expect(game.handCounts[seat] == hand.count)
        }
        let all = game.hands.values.flatMap { $0 } + game.laid.compactMap { $0 }.flatMap { $0.flatMap(\.cards) }
        #expect(Set(all).count == all.count)
        var pass = PassAndPlay()
        pass.update(model)
        #expect(pass.revealed == nil)
        #expect(pass.state == .curtain(game.turn))
    }

    @Test func replayCoversEveryAnimatedEventAndStaysConsistent() throws {
        let steps = DemoFixtures.replay()
        var kinds: Set<String> = []
        for step in steps {
            for event in step.events {
                kinds.insert(String(describing: event).prefix { $0 != "(" }.description)
            }
            let game = try #require(step.room.game)
            for (seat, hand) in game.hands {
                #expect(game.handCounts[seat] == hand.count)
            }
            var visible = game.hands.values.flatMap { $0 }
            visible += game.laid.compactMap { $0 }.flatMap { $0.flatMap(\.cards) }
            if let top = game.discardTop { visible.append(top) }
            #expect(Set(visible).count == visible.count)
            let laidCount = game.laid.compactMap { $0 }.flatMap { $0 }.reduce(0) { $0 + $1.cards.count }
            #expect(game.deckCount + game.discardCount + game.handCounts.reduce(0, +) + laidCount == Card.deckSize)
        }
        #expect(kinds == ["roundStarted", "drew", "laidDown", "hit", "discarded", "skipped", "turn", "reshuffled"])
        #expect(steps.last?.room.game?.hands == DemoFixtures.replayStart().game?.hands)
    }

    @Test func roundOverEventsFollowTheFinalTable() throws {
        let base = try #require(DemoFixtures.table(seats: 4, mySeat: 0, phase: 9).game)
        let events = DemoFixtures.roundOverEvents()
        guard case .roundOver(let wentOut, let points, let advanced, let scores, let phase)? = events.first else {
            Issue.record("first event is roundOver")
            return
        }
        let out = try #require(wentOut)
        #expect(points.count == 4)
        #expect(points[out] == 0)
        #expect(points.allSatisfy { $0 >= 0 && $0 % 5 == 0 })
        #expect(advanced.contains(out))
        #expect(scores == zip(base.scores, points).map { $0 + $1 })
        #expect(phase == base.phase.indices.map { base.phase[$0] + (advanced.contains($0) ? 1 : 0) })
        guard case .gameOver(let winners)? = events.last, events.count == 2 else {
            Issue.record("then gameOver")
            return
        }
        let finished = phase.indices.filter { phase[$0] == Rules.phases.count }
        let best = finished.map { scores[$0] }.min()
        #expect(!winners.isEmpty)
        #expect(winners == finished.filter { scores[$0] == best })
    }
}
