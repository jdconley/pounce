import CoreGraphics
import Foundation
import Testing
@testable import PounceKit

@Suite struct BirdTableModelTests {
    static func room(_ name: String) throws -> RoomView {
        let json = try #require(try Fixtures.birdwatchServerMessages().first { $0.name == name }).json
        guard case .snapshot(_, _, let room) = try Codec.decode(json) as ServerMessage else {
            throw Fixtures.FixtureError.malformed(name)
        }
        return room
    }

    static func model(_ name: String) throws -> BirdTableModel {
        try #require(BirdTableModel(room: try room(name)))
    }

    @Test func panelFromSnapshot() throws {
        #expect(try Self.model("snapshot-bidding-your-move").panel(for: 1) == .bid(BirdBidRange(min: 70, max: 120, step: 5)))
        #expect(try Self.model("snapshot-bidding-watching").panel(for: 0)?.isWaiting == true)
        let nest = try Self.model("snapshot-nest-bid-winner")
        #expect(nest.panel(for: 1) == .nest(count: 5, fromNest: [11, 40, 47, 54, 55]))
        #expect(try Self.model("snapshot-nest-waiting").panel(for: nil) == .waiting(phase: .nest, seat: 1))
        guard case .trump = try Self.model("snapshot-trump-bid-winner").panel(for: 1) else {
            Issue.record("no trump panel"); return
        }
        guard case .partner(let choices) = try Self.model("snapshot-five-partner-call").panel(for: 1) else {
            Issue.record("no partner panel"); return
        }
        #expect(choices.count == 47)
        #expect(try Self.model("snapshot-play-follow").panel(for: 1) == nil)
        #expect(try Self.model("snapshot-between").panel(for: 3) == nil)
        #expect(try Self.model("snapshot-over-target").panel(for: 1) == nil)
        // Every snapshot gives some answer without a crash, for every seat and for nobody.
        for (name, json) in try Fixtures.birdwatchServerMessages() {
            guard case .snapshot(_, _, let room) = try Codec.decode(json) as ServerMessage,
                  let model = BirdTableModel(room: room) else { continue }
            for seat in [nil] + (0..<model.seatCount).map(Optional.some) { _ = model.panel(for: seat) }
            _ = name
        }
    }

    @Test func theHandSortsBySuitWithTrumpAndTheBirdLast() {
        // fish 5 (4), mouse 1 (14), feather 14 (41), bell 7 (48), the Bird, fish 14 (13)
        let cards = [56, 41, 4, 48, 14, 13]
        #expect(BirdTableModel.sorted(cards, trump: nil) == [4, 13, 14, 41, 48, 56])
        #expect(BirdTableModel.sorted(cards, trump: .fish) == [14, 41, 48, 4, 13, 56])
        // A 1 sits above the 14.
        #expect(BirdTableModel.sorted([27, 14, 15], trump: nil) == [15, 27, 14])
    }

    @Test func playableOnlyOnTheSeatsMove() throws {
        let follow = try Self.model("snapshot-play-follow")
        let seat = try #require(follow.mySeats.first)
        #expect(!follow.playable(seat).isEmpty)
        #expect(follow.playable(seat).isSubset(of: Set(follow.hand(seat) ?? [])))
        let watching = try Self.model("snapshot-play-watching")
        for s in watching.mySeats { #expect(watching.playable(s).isEmpty) }
    }

    @Test func ribbonsFollowTheTeams() throws {
        let four = try Self.model("snapshot-play-follow")
        #expect((0..<4).map { four.ribbon(of: $0) } == [.orange, .teal, .orange, .teal])
        let six = try Self.model("snapshot-six-house-cat")
        #expect((0..<6).map { six.ribbon(of: $0) } == [.orange, .teal, .magenta, .orange, .teal, .magenta])
        let hidden = try Self.model("snapshot-five-partner-hidden")
        #expect((0..<5).allSatisfy { hidden.ribbon(of: $0) == nil })
        let shown = try Self.model("snapshot-five-partner-shown")
        #expect((0..<5).map { shown.ribbon(of: $0) } == [nil, .gold, nil, .gold, nil])
        #expect(shown.sides.count == 5)
        #expect(shown.sides.allSatisfy { $0.ribbon == nil })
    }

    @Test func partnerMarkOnlyBehindCurtain() throws {
        let one = try Self.model("snapshot-five-you-are-partner")
        #expect(one.partnerMark(for: 3, revealed: nil))
        #expect(!one.partnerMark(for: 0, revealed: nil))
        // The same seat on a shared phone: only once its hand is up.
        var room = try Self.room("snapshot-five-you-are-partner")
        room.seats[4].yours = true
        let shared = try #require(BirdTableModel(room: room))
        #expect(!shared.partnerMark(for: 3, revealed: nil))
        #expect(!shared.partnerMark(for: 3, revealed: 4))
        #expect(shared.partnerMark(for: 3, revealed: 3))
        // Nobody else's view carries it.
        #expect(!(try Self.model("snapshot-five-partner-hidden")).partnerMark(for: 2, revealed: nil))
    }

    @Test func signsShowBidsPassesAndTheResult() throws {
        let after = try Self.model("snapshot-bidding-after-bid")
        for seat in 0..<4 {
            if after.view.passed[seat] { #expect(after.sign(seat) == .pass) }
            if let bid = after.view.bids[seat], !after.view.passed[seat] { #expect(after.sign(seat) == .bid(bid)) }
        }
        let play = try Self.model("snapshot-play-follow")
        let high = try #require(play.view.high)
        #expect(play.sign(high.seat) == .bid(high.amount))
        let over = try Self.model("snapshot-over-target")
        #expect(over.sign(1) == .missed(70))
        #expect(over.sign(0) == nil)
    }

    @Test func labelsReadAsTheSpecSays() {
        #expect(BirdTableModel.label(9) == "10, fish, 10 points")
        #expect(BirdTableModel.label(56) == "Bird, 20 points, top trump")
        #expect(BirdTableModel.label(42) == "1, bell, 15 points")
        #expect(BirdTableModel.label(20) == "7, mouse")
    }

    @Test func trumpHintIsTheLongestSuit() throws {
        // Seat 1: 4, 6, 9 (fish 5, 7, 10), 24 (mouse 11), 38 (feather 11), 49, 50, 53 (bell 8, 9, 12), Bird.
        let trump = try Self.model("snapshot-trump-bid-winner")
        #expect(trump.trumpHint(1) == .fish)
    }

    @Test func partnerRowsPutTrumpFirst() {
        let rows = BirdTableModel.partnerRows([0, 13, 14, 56, 30, 42], trump: .feather)
        #expect(rows.map(\.suit) == [.feather, .fish, .mouse, .bell])
        #expect(rows[0].cards == [56, 30])
        #expect(rows[1].cards == [0, 13])
    }

    @Test func standingsPutWinnersFirst() throws {
        let over = try Self.model("snapshot-over-target")
        #expect(over.standings.map(\.index) == [0, 1])
        #expect(over.standings[0].score == 345)
    }

    @Test func aBirdwatchLobbyNeedsFourToSix() throws {
        var room = try Self.room("snapshot-lobby")
        room.seats[1].yours = true
        // Four people, two closed seats: Start deals.
        #expect(TableModel(room: room).canStart)
        #expect(TableModel(room: room).seatRange == 4...6)
        // Three people and an open seat: no "start with 3?".
        room.seats[3] = SeatView(kind: .open)
        var table = TableModel(room: room)
        #expect(!table.canStart)
        #expect(table.startClosingOpenSeats == nil)
        #expect(table.startBlock == .openSeats(open: 1, players: 3))
        // Three people, every other seat closed: not enough.
        room.seats[3] = SeatView(kind: .closed)
        table = TableModel(room: room)
        #expect(table.startBlock == .notEnoughPlayers(players: 3, needed: 4))
        // Four people and two open: start closes them.
        room.seats[3] = SeatView(kind: .bot)
        room.seats[4] = SeatView(kind: .open)
        room.seats[5] = SeatView(kind: .open)
        table = TableModel(room: room)
        #expect(table.startClosingOpenSeats?.last == .start)
    }

    @Test func lobbyRibbonsCountFilledSeats() throws {
        var room = try Self.room("snapshot-lobby")
        let four = TableModel(room: room)
        #expect((0..<6).map { four.lobbyRibbon($0) } == [.orange, .teal, .orange, .teal, nil, nil])
        room.seats[1] = SeatView(kind: .open)
        room.seats[4] = SeatView(kind: .bot)
        room.seats[5] = SeatView(kind: .bot)
        let five = TableModel(room: room)
        #expect((0..<6).allSatisfy { five.lobbyRibbon($0) == nil })
        room.seats[1] = SeatView(kind: .bot)
        let six = TableModel(room: room)
        #expect((0..<6).map { six.lobbyRibbon($0) } == [.orange, .teal, .magenta, .orange, .teal, .magenta])
    }
}

extension BirdTableModel.Panel {
    var isWaiting: Bool { if case .waiting = self { true } else { false } }
}

@Suite struct BirdLayoutTests {
    @Test func seventeenCardsFitSE() {
        let layout = BirdLayout(size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0, others: 4, handCount: 17)
        let slots = layout.handSlots(count: 17)
        #expect(slots.count == 17)
        #expect(layout.handRows(count: 17) == 2)
        #expect(layout.peek(count: 17) >= 22)
        for slot in slots {
            #expect(slot.x - layout.cardSize.width / 2 >= 0)
            #expect(slot.x + layout.cardSize.width / 2 <= 375)
        }
        #expect(layout.hand.maxY < layout.strip.minY)
        #expect(layout.strip.maxY <= layout.window.minY)
    }

    @Test func nineCardsOnOneRow() {
        let layout = BirdLayout(size: CGSize(width: 393, height: 852), safeTop: 59, safeBottom: 34, others: 3, handCount: 9)
        #expect(layout.handRows(count: 9) == 1)
        #expect(layout.peek(count: 9) >= layout.cardSize.width * 0.5)
        #expect(layout.handSlots(count: 9).count == 9)
    }

    @Test func catsSitAroundTheWindowAndClearTheSill() {
        for others in 3...5 {
            for size in [CGSize(width: 375, height: 667), CGSize(width: 440, height: 956), CGSize(width: 1032, height: 1376), CGSize(width: 1376, height: 1032)] {
                let layout = BirdLayout(size: size, safeTop: 24, safeBottom: 20, others: others, handCount: 10)
                #expect(layout.seatSpots.count == others)
                for spot in layout.seatSpots {
                    let cat = CGRect(x: spot.x - layout.catSide / 2, y: spot.y - layout.catSide / 2, width: layout.catSide, height: layout.catSide)
                    #expect(!cat.intersects(layout.sill.insetBy(dx: 4, dy: 4)), "\(others) at \(size): cat \(cat) sill \(layout.sill)")
                    #expect(cat.minX >= 0 && cat.maxX <= size.width, "\(others) at \(size)")
                    #expect(cat.maxY <= layout.topBand.minY + 4, "\(others) at \(size)")
                }
            }
        }
    }

    @Test func aTVHasNoHand() {
        let layout = BirdLayout(size: CGSize(width: 1920, height: 1080), safeTop: 60, safeBottom: 60, others: 6, handCount: 0, mode: .tv)
        #expect(layout.hand == .zero)
        #expect(layout.handSlots(count: 9).isEmpty)
        #expect(layout.seatSpots.count == 6)
        #expect(layout.seatSpots[0].y < layout.sill.minY)
    }
}

@Suite struct BirdLobbyHouseCatTests {
    @Test func aFirstBirdwatchTableFillsUpToFour() {
        var room = DemoFixtures.birdLobby(seated: 1)
        room.seats[0].yours = true
        let table = TableModel(room: room)
        #expect(table.firstTableMessages == [.configure(seat: 1, kind: .bot), .configure(seat: 2, kind: .bot), .configure(seat: 3, kind: .bot)])
        #expect(table.practiceMessages == [
            .configure(seat: 1, kind: .bot), .configure(seat: 2, kind: .bot), .configure(seat: 3, kind: .bot), .start,
        ])
    }

    @Test func catTowerStillAddsOne() {
        let table = TableModel(room: DemoFixtures.lobby())
        if let first = table.firstTableMessages { #expect(first.count <= 1) }
    }
}

@Suite struct BirdLiveTableTests {
    @Test func aBirdwatchTableShowsSideScoresOnTheChips() {
        let seats = [
            LiveTableState.Seat(cat: 1, phase: 1, name: "Mia", bot: false, me: true, progress: 145),
            LiveTableState.Seat(cat: 3, phase: 1, name: nil, bot: true, me: false, progress: -70),
        ]
        let bird = LiveTableLook(LiveTableState(table: "Window Seat", seats: seats, turn: 1, mine: false, streak: nil, progressKind: "score"))
        #expect(bird.seats.map(\.chip) == ["145", "-70"])
        let tower = LiveTableLook(LiveTableState(table: "Cats", seats: seats, turn: 1, mine: false, streak: nil))
        #expect(tower.seats.map(\.chip) == ["1", "1"])
    }
}
