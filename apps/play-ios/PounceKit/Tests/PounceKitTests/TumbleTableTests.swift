import Foundation
import Testing
@testable import PounceKit

/// The table model between the room's snapshots, the live stream and the scene.
@MainActor @Suite struct TumbleTableTests {
    static func room(status: TumbleView.Status = .countdown, r: Int = 1, seats: Int = 3, mine: Int? = 0, outs: [Int] = []) -> RoomView {
        RoomView(
            code: "ABCDEF", status: .playing, youAreHost: true,
            seats: (0..<seats).map { SeatView(kind: $0 == 2 ? .bot : .human, yours: $0 == mine) },
            gameId: GameID.tumble,
            tumble: TumbleView(
                seats: seats, wins: Array(repeating: 0, count: seats), status: status, r: r, startsAt: 3000, roundSeed: [7, 7, 7, 7],
                trickSeeds: (0..<seats).map { [UInt32($0) + 1, 2, 3, 4] }, outs: outs))
    }

    final class Sent { var messages: [ClientMessage] = [] }

    @Test func aCountdownMakesTheOwnBoxAndReplaysTheRest() {
        let sent = Sent()
        let table = TumbleTable { sent.messages.append($0) }
        table.update(room: Self.room(), now: 0)
        #expect(table.mySeat == 0)
        #expect(table.local?.seat == 0)
        #expect(table.replay?.seats.keys.sorted() == [1, 2])
        #expect(table.box(1) == TumbleBox(trickSeed: [2, 2, 3, 4]))
        table.step(now: 3000)
        #expect(table.local?.toy?.n == 0)
        #expect(sent.messages.first == .tumble(r: 1, ev: [.move(n: 0, rot: 0, x: TumbleToys.spawn(TumbleQueue.toyAt([7, 7, 7, 7], 0)).x, y: TumbleToys.spawn(TumbleQueue.toyAt([7, 7, 7, 7], 0)).y)]))
    }

    /// `room.tumble.now`: a device whose clock is 5 s fast still starts with everyone else.
    @Test func theRoundCountsOnTheServersClock() {
        let table = TumbleTable { _ in }
        var room = Self.room()
        room.tumble?.now = 1000
        table.update(room: room, now: 6000)
        #expect(table.clockOffset == -5000)
        #expect(table.startsAt == 8000)
        #expect(table.local?.startsAt == 8000)
        table.step(now: 7990)
        #expect(table.local?.toy == nil)
        table.step(now: 8000)
        #expect(table.local?.toy != nil)
    }

    @Test func aHitThatBuriesTheToyLiftsItAndSaysWhere() throws {
        let sent = Sent()
        let table = TumbleTable { sent.messages.append($0) }
        table.update(room: Self.room(status: .playing), now: 0)
        table.step(now: 3000)
        table.step(now: 9000)
        let toy = try #require(table.local?.toy)
        // Fill the box up to just under the toy's lowest row, then swap that box in.
        var full = TumbleBox(trickSeed: [9, 9, 9, 9])
        let top = toy.cells.map(\.y).max() ?? 0
        #expect(top < 17)
        for y in 0...top { for x in 0..<11 { full.cells[y * 12 + x] = Tumble.junk } }
        table.receive(.hit(TumbleHitWire(r: 1, id: 7, from: 1, to: 0, k: .swap, hit: .swap(cells: full.cells, tricks: full.tricks))), now: 9100)
        let lifted = try #require(table.local?.toy)
        #expect(lifted.spot.y > toy.spot.y)
        guard case .tumble(_, let ev) = sent.messages.last else { Issue.record("nothing sent"); return }
        #expect(ev.contains(.move(n: lifted.n, rot: lifted.spot.rot, x: lifted.spot.x, y: lifted.spot.y)))
        #expect(ev.contains(.ack(id: 7)))
    }

    @Test func theSameRoundKeepsItsBoxesAndANewOneStartsFresh() {
        let table = TumbleTable { _ in }
        table.update(room: Self.room(), now: 0)
        let first = table.local
        table.update(room: Self.room(status: .playing), now: 100)
        #expect(table.local === first)
        table.update(room: Self.room(status: .between), now: 200)
        #expect(table.local === first, "the last boxes stay up between rounds")
        table.step(now: 9000)
        #expect(table.local?.toy == nil, "and nothing falls")
        table.update(room: Self.room(status: .countdown, r: 2), now: 300)
        #expect(table.local !== first)
        #expect(table.local?.r == 2)
    }

    @Test func aScreenHasNoOwnBoxAndReplaysEveryBox() {
        let table = TumbleTable(screen: true) { _ in }
        table.update(room: Self.room(mine: nil), now: 0)
        #expect(table.local == nil)
        #expect(table.replay?.seats.keys.sorted() == [0, 1, 2])
    }

    @Test func aGapAsksForASyncWithAnEmptyBatch() {
        let sent = Sent()
        let table = TumbleTable { sent.messages.append($0) }
        table.update(room: Self.room(), now: 0)
        table.receive(.relay(TumbleRelay(r: 1, s: 1, q: 4, ev: [])), now: 10)
        #expect(sent.messages.last == .tumble(r: 1, ev: []))
    }

    @Test func hitsForThisSeatGoToTheOwnBoxAndAnotherRoundsAreDropped() {
        let sent = Sent()
        let table = TumbleTable { sent.messages.append($0) }
        table.update(room: Self.room(status: .playing), now: 0)
        table.step(now: 3000)
        table.receive(.hit(TumbleHitWire(r: 1, id: 3, from: 1, to: 0, k: .hairball, hit: .hairball(gap: 0))), now: 3100)
        #expect(table.box(0)?.cell(1, 0) == Tumble.junk)
        #expect(sent.messages.last == .tumble(r: 1, ev: [.ack(id: 3)]))
        table.receive(.hit(TumbleHitWire(r: 9, id: 4, from: 1, to: 0, k: .bath, hit: .bath)), now: 3200)
        #expect(table.box(0)?.cell(1, 0) == Tumble.junk)
    }

    /// Review Focus 1: the background drops the socket; coming back asks for every box first.
    @Test func theBackgroundSuspendsAndTheReturnAsksForASync() {
        let sent = Sent()
        let table = TumbleTable { sent.messages.append($0) }
        table.update(room: Self.room(status: .playing), now: 0)
        table.step(now: 3500)
        table.suspend()
        table.step(now: 5000)
        #expect(table.local?.toy == nil)
        sent.messages.removeAll()
        table.resume(now: 9000)
        #expect(sent.messages == [.tumble(r: 1, ev: [])])
        table.step(now: 9100)
        #expect(table.local?.toy == nil, "no step before the sync")
        var b = TumbleBox(trickSeed: [1, 2, 3, 4])
        b.next = 4
        table.receive(.sync(TumbleSync(r: 1, boxes: [TumbleBoxSync(s: 0, box: b, q: 6), TumbleBoxSync(s: 1, box: TumbleBox(trickSeed: [2, 2, 3, 4]), q: 2)])), now: 9200)
        #expect(table.local?.toy?.n == 4)
        #expect(table.replay?.seats[1]?.q == 2)
    }

    @Test func theRoomStoreHandsTheLiveStreamOn() async {
        let socket = FakeSocket()
        let store = RoomStore(code: "ABCDEF", socket: socket)
        var got: [TumbleMessage] = []
        store.onTumble = { got.append($0) }
        store.handle(.connected)
        store.handle(.message(.snapshot(protocol: 1, seq: 1, room: Self.room())))
        store.handle(.message(.tumble(.seat(TumbleSeat(r: 1, s: 1, st: .lag)))))
        #expect(got == [.seat(TumbleSeat(r: 1, s: 1, st: .lag))])
        store.send(.tumble(r: 1, ev: [.ack(id: 2)]))
        await store.settle()
        #expect(socket.calls.sends.last == .tumble(r: 1, ev: [.ack(id: 2)]))
    }
}
