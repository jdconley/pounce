import Testing
@testable import PounceKit

/// A lobby with the server's starting seats (0-1 open, 2-5 closed) unless given others.
private func lobby(_ seats: [SeatView]? = nil) -> RoomView {
    let start = [SeatView(kind: .open), SeatView(kind: .open)] + Array(repeating: SeatView(kind: .closed), count: 4)
    return RoomView(code: "BCDFG", status: .lobby, youAreHost: false, seats: seats ?? start)
}

private let owner = Person(id: "me", name: "Mochi", cat: 2)
private let host = Person(id: "host", name: "JD", cat: 0)

@Suite struct RoomEntryTests {
    @Test func autoClaimFirstOpenSeat() {
        // The host sits on 0; the first open seat is 1.
        let room = lobby([
            SeatView(kind: .human, person: host, yours: false, presence: .awake),
            SeatView(kind: .open),
            SeatView(kind: .closed),
            SeatView(kind: .open),
        ])
        #expect(RoomEntry.autoClaim(model: TableModel(room: room), owner: owner) == .claim(seat: 1, person: owner))
        // A fresh lobby: seat 0.
        #expect(RoomEntry.autoClaim(model: TableModel(room: lobby()), owner: owner) == .claim(seat: 0, person: owner))
    }

    @Test func noAutoClaimWhenAlreadySeated() {
        let room = lobby([
            SeatView(kind: .human, person: owner, yours: true, presence: .awake),
            SeatView(kind: .open),
        ])
        #expect(RoomEntry.autoClaim(model: TableModel(room: room), owner: owner) == nil)
    }

    @Test func noAutoClaimWhenFullOrPlaying() {
        let full = lobby([
            SeatView(kind: .human, person: host, presence: .awake),
            SeatView(kind: .bot),
            SeatView(kind: .closed),
        ])
        #expect(RoomEntry.autoClaim(model: TableModel(room: full), owner: owner) == nil)
    }

    @Test func noAutoClaimWhenPlaying() {
        var room = makeRoom(seatCount: 2, mine: [])
        room.seats[1] = SeatView(kind: .open)  // never happens on the server, but must not claim
        #expect(RoomEntry.autoClaim(model: TableModel(room: room), owner: owner) == nil)
        var over = lobby()
        over.status = .over
        #expect(RoomEntry.autoClaim(model: TableModel(room: over), owner: owner) == nil)
    }

    @Test func knownCode404IsClosed() {
        #expect(RoomEntry.notFoundMeaning(code: "BCDFG", known: true) == .roomClosed)
    }

    @Test func typedCode404IsBadCode() {
        #expect(RoomEntry.notFoundMeaning(code: "BCDFG", known: false) == .badCode)
    }
}
