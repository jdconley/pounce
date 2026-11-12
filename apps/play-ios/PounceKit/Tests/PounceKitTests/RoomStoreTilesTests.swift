#if DEBUG
import Foundation
import Testing
@testable import PounceKit

/// The store in a room playing the tile game: its turns go out in the same `act` envelope, its
/// events arrive under their own kind, and pass-and-play follows its turn.
@MainActor @Suite(.timeLimit(.minutes(1))) struct RoomStoreTilesTests {
    private func snapshot(_ room: RoomView, seq: Int) -> SocketEvent {
        .message(.snapshot(protocol: 1, seq: seq, room: room))
    }

    private func event(_ event: TilesEvent, seq: Int) -> SocketEvent {
        .message(.event(seq: seq, event: .tiles(event)))
    }

    private func store(_ room: RoomView, link: Bool = false) -> (RoomStore, FakeSocket) {
        let socket = FakeSocket()
        var next = 0
        let store = RoomStore(code: room.code, socket: socket) {
            next += 1
            return "m\(next)"
        }
        var room = room
        if link { room.link = RoomLink(ping: 3000) }
        store.handle(.connected)
        store.handle(snapshot(room, seq: 5))
        return (store, socket)
    }

    private func intents(_ store: RoomStore) async -> [TableIntent] {
        await store.close()
        var out: [TableIntent] = []
        for await intent in store.intents { out.append(intent) }
        return out
    }

    @Test func aTilesSnapshotIsAPlayingRoom() {
        let (store, _) = store(DemoFixtures.tilesMid())
        #expect(store.phase == .playing)
        #expect(store.room?.isTiles == true)
        #expect(store.room?.game == nil)
        #expect(store.pass.state == .revealed(0))
    }

    @Test func aTurnGoesOutAsAnActAndLocksUntilItsSnapshot() async {
        let (store, socket) = store(DemoFixtures.tilesMid())
        let table = [[0, 1, 2]]
        #expect(store.actTiles(seat: 0, .play(table: table)))
        #expect(store.actionInFlight)
        // One at a time, as in Cat Tower.
        #expect(!store.actTiles(seat: 0, .draw))
        #expect(!store.act(seat: 0, .draw(.deck)))
        await store.settle()
        #expect(socket.calls.sends == [.actTiles(seat: 0, action: .play(table: table))])
        store.handle(snapshot(DemoFixtures.tilesOther(), seq: 7))
        #expect(!store.actionInFlight)
    }

    @Test func aRefusedTurnUnlocksAndSaysWhy() async {
        let (store, _) = store(DemoFixtures.tilesMid())
        #expect(store.actTiles(seat: 0, .play(table: [[0, 1]])))
        store.handle(.message(.error(.badSet)))
        #expect(!store.actionInFlight)
        #expect(store.lastError == .badSet)
        #expect(await intents(store).last == .rejected(.badSet))
    }

    @Test func withLinksATurnCarriesAnIdAndIsSentAgainAfterAReconnect() async {
        let (store, socket) = store(DemoFixtures.tilesMid(), link: true)
        #expect(store.actTiles(seat: 0, .draw))
        await store.settle()
        #expect(socket.calls.sends == [.actTiles(seat: 0, action: .draw, id: "m1")])
        #expect(store.pendingMove?.id == "m1")
        #expect(store.pendingMove?.move == .tiles(.draw))
        #expect(store.pendingMove?.action == nil)
        // The socket drops; the first snapshot on the new connection doesn't list the move.
        store.handle(.disconnected)
        store.handle(.connected)
        var room = DemoFixtures.tilesMid()
        room.link = RoomLink(ping: 3000)
        store.handle(snapshot(room, seq: 5))
        await store.settle()
        #expect(socket.calls.sends.count == 2)
        #expect(socket.calls.sends.last == .actTiles(seat: 0, action: .draw, id: "m1"))
        #expect(store.actionInFlight)
        room.link?.acks = ["m1"]
        store.handle(snapshot(room, seq: 7))
        #expect(store.pendingMove == nil)
        #expect(!store.actionInFlight)
    }

    @Test func eventsBecomeIntentsAndFoldInTheTurn() async {
        let (store, _) = store(DemoFixtures.tilesOther())
        #expect(store.room?.tiles?.turn == 2)
        let epoch = store.turnEpoch
        let played = TilesEvent.played(seat: 2, table: [[0, 1, 2]], placed: [0, 1, 2], opened: false)
        store.handle(event(played, seq: 6))
        // Only the turn and the status are folded in; the rug waits for the snapshot.
        #expect(store.room?.tiles?.table == DemoFixtures.tilesOther().tiles?.table)
        #expect(store.settledSeq == 5)
        store.handle(event(.turn(seat: 3), seq: 7))
        #expect(store.room?.tiles?.turn == 3)
        #expect(store.turnEpoch == epoch + 1)
        #expect(store.lastSeq == 7)
        let all = await intents(store)
        #expect(all == [.reconcile, .tiles(played, seq: 6), .tiles(.turn(seat: 3), seq: 7)])
    }

    @Test func gameOverAndForfeitFoldIn() {
        let (store, _) = store(DemoFixtures.tilesOther())
        store.handle(event(.forfeited(seat: 1), seq: 6))
        #expect(store.forfeitNotice == .init(seat: 1, serial: 1))
        store.handle(event(.gameOver(winners: [0], reason: .blocked, scores: [1, 0, -1, 0], left: [0, 0, 1, 0]), seq: 7))
        #expect(store.room?.tiles?.status == .gameOver)
        #expect(store.room?.liveTurn == nil)
    }

    @Test func aGapInTilesEventsReconnects() async {
        let (store, socket) = store(DemoFixtures.tilesOther())
        store.handle(event(.turn(seat: 3), seq: 9))
        await store.settle()
        #expect(socket.calls.reconnects == 1)
        #expect(store.room?.tiles?.turn == 2)
    }

    @Test func theTurnEpochMovesWithEveryTilesTurn() {
        let (store, _) = store(DemoFixtures.tilesMid())
        let start = store.turnEpoch
        // The same seat again after a whole round (two seats, the other drew): `turns` moved.
        var next = DemoFixtures.tilesMid()
        next.tiles?.turns += 2
        store.handle(snapshot(next, seq: 9))
        #expect(store.turnEpoch == start + 1)
        // The same snapshot again changes nothing.
        store.handle(snapshot(next, seq: 9))
        #expect(store.turnEpoch == start + 1)
    }

    @Test func aSharedPhoneCurtainsEachOfItsTilesTurns() {
        let (store, _) = store(DemoFixtures.tilesCurtain())
        #expect(store.pass.state == .curtain(0))
        store.completeHold()
        #expect(store.pass.state == .revealed(0))
        // Seat 0 plays; the move goes to a remote seat: nothing of this phone's stays up.
        store.handle(event(.turn(seat: 1), seq: 6))
        #expect(store.pass.state == .none)
        // Off turn, a local cat can peek behind a curtain.
        store.peek(2)
        #expect(store.pass.state == .curtain(2))
        store.hidePass()
        // Then the move comes to this phone's other seat: its own curtain.
        store.handle(event(.turn(seat: 2), seq: 7))
        #expect(store.pass.state == .curtain(2))
        store.completeHold()
        #expect(store.pass.state == .revealed(2))
    }

    @Test func aForfeitedLocalSeatLeavesAOneSeatPhoneWithNoCurtain() {
        var room = DemoFixtures.tilesCurtain()
        room.tiles?.forfeited[2] = true
        room.tiles?.rackCounts[2] = 0
        room.tiles?.racks[2] = nil
        let (store, _) = store(room)
        #expect(store.pass.state == .revealed(0))
    }

    @Test func nudgesAndRetiringFollowTheTilesTurn() {
        var room = DemoFixtures.tilesOther()
        room.nudge = NudgeView(seat: 2)
        room.retire = RetireView(seat: 2, wait: 0)
        let (store, _) = store(room)
        #expect(store.nudgeButton(for: 2) == .ready)
        #expect(store.nudgeButton(for: 1) == nil)
        #expect(store.canRetire(seat: 2))
        var over = DemoFixtures.tilesOver()
        over.nudge = NudgeView(seat: 1)
        let (done, _) = self.store(over)
        #expect(done.nudgeButton(for: 1) == nil)
    }
}
#endif
