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
            SeatView(kind: .human, person: Person(id: "p2", name: "Ben", cat: 5), presence: .awake),
            SeatView(kind: .closed),
        ])
        #expect(RoomEntry.autoClaim(model: TableModel(room: full), owner: owner) == nil)
        // A House Cat's seat is not full: a person takes it over (first-run funnel).
        let withCat = lobby([
            SeatView(kind: .human, person: host, presence: .awake),
            SeatView(kind: .bot),
            SeatView(kind: .closed),
        ])
        #expect(RoomEntry.autoClaim(model: TableModel(room: withCat), owner: owner) == .claim(seat: 1, person: owner))
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

    // MARK: auto-claim retry

    private func seated(_ room: RoomView, at seat: Seat) -> TableModel {
        var r = room
        r.seats[seat] = SeatView(kind: .human, person: owner, yours: true, presence: .awake)
        return TableModel(room: r)
    }

    private let seat0: ClientMessage = .claim(seat: 0, person: owner)

    @Test func autoClaimIsSentOnceOnTheFirstSnapshot() {
        var claim = AutoClaim()
        let model = TableModel(room: lobby())
        let first = claim.snapshot(model, owner: owner, first: { seat0 })
        #expect(first == seat0)
        #expect(claim.pending)
        let again = claim.snapshot(model, owner: owner, first: { Issue.record("first() twice"); return nil })
        #expect(again == nil)
        // Seated: answered.
        _ = claim.snapshot(seated(lobby(), at: 0), owner: owner, first: { nil })
        #expect(!claim.pending)
        let late = claim.refused(.seatTaken)
        #expect(!late)  // nothing pending: a later error is a tap's
    }

    @Test func refusedAutoClaimRetriesOnceOnTheNextLobbySnapshot() {
        var claim = AutoClaim()
        _ = claim.snapshot(TableModel(room: lobby()), owner: owner, first: { seat0 })
        let refused = claim.refused(.seatTaken)
        #expect(refused)  // suppressed: no nope
        #expect(!claim.pending)

        // Someone else took seat 0; seat 1 is still open.
        let taken = lobby([SeatView(kind: .human, person: host, presence: .awake), SeatView(kind: .open)])
        let retry = claim.snapshot(TableModel(room: taken), owner: owner, first: { nil })
        #expect(retry == .claim(seat: 1, person: owner))
        #expect(claim.pending)
        let refusedAgain = claim.refused(.seatTaken)
        #expect(refusedAgain)  // the retry's refusal is suppressed too
        // But there is no second retry, and later errors are a tap's again.
        let none = claim.snapshot(TableModel(room: taken), owner: owner, first: { nil })
        #expect(none == nil)
        let tap = claim.refused(.seatTaken)
        #expect(!tap)
    }

    @Test func noRetryOnceSeatedOrOutsideTheLobby() {
        var claim = AutoClaim()
        _ = claim.snapshot(TableModel(room: lobby()), owner: owner, first: { seat0 })
        _ = claim.refused(.seatTaken)
        // The person tapped a seat themselves before the next snapshot: no retry.
        let afterSeated = claim.snapshot(seated(lobby(), at: 1), owner: owner, first: { nil })
        #expect(afterSeated == nil)

        var other = AutoClaim()
        _ = other.snapshot(TableModel(room: lobby()), owner: owner, first: { seat0 })
        _ = other.refused(.seatTaken)
        var playing = lobby()
        playing.status = .playing
        let inGame = other.snapshot(TableModel(room: playing), owner: owner, first: { nil })
        #expect(inGame == nil)
    }

    @Test func roomWideErrorsAreNotTheClaims() {
        var claim = AutoClaim()
        _ = claim.snapshot(TableModel(room: lobby()), owner: owner, first: { seat0 })
        let stalled = claim.refused(.botStalled)
        let closed = claim.refused(.roomClosed)
        #expect(!stalled && !closed)
        #expect(claim.pending)
    }

    @Test func aMoveClaimIsNotAnAutoClaim() {
        var claim = AutoClaim()
        _ = claim.snapshot(TableModel(room: lobby()), owner: owner, first: { .claimMove(code: "BCDFGH") })
        #expect(!claim.pending)
        let refused = claim.refused(.badCode)
        #expect(!refused)
    }
}
