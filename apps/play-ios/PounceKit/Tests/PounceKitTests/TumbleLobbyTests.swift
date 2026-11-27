import Foundation
import Testing
@testable import PounceKit

/// Toy Tumble's lobby: Start waits for every person's device, and a device holds one seat.
@Suite struct TumbleLobbyTests {
    static func lobby(miaAway: Bool) -> RoomView {
        RoomView(
            code: "ABCDEF", status: .lobby, youAreHost: true,
            seats: [
                SeatView(kind: .human, person: Person(id: "a", name: "Sam", cat: 0), yours: true, presence: .awake),
                SeatView(kind: .human, person: Person(id: "b", name: "Mia", cat: 1), presence: miaAway ? .away : .awake),
                SeatView(kind: .bot),
            ],
            gameId: GameID.tumble)
    }

    @Test func startWaitsForEveryPersonsDevice() {
        let waiting = TableModel(room: Self.lobby(miaAway: true))
        #expect(waiting.startBlock == .offline(seats: [1]))
        #expect(!waiting.canStart)
        let ready = TableModel(room: Self.lobby(miaAway: false))
        #expect(ready.startBlock == nil)
        #expect(ready.canStart)
        #expect(ready.oneSeatPerDevice)
    }

    @Test func otherGamesDontWaitForDevices() {
        var room = Self.lobby(miaAway: true)
        room.gameId = GameID.catTower
        #expect(TableModel(room: room).offlineSeats.isEmpty)
        #expect(!TableModel(room: room).oneSeatPerDevice)
    }
}
