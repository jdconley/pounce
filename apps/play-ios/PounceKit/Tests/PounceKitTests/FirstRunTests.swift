import Foundation
import Testing
@testable import PounceKit

/// A lobby with the given seat kinds; `mine` are this device's (human) seats.
private func lobby(_ kinds: [SeatKind], mine: Set<Seat> = [0], status: RoomStatus = .lobby) -> TableModel {
    let seats = kinds.enumerated().map { i, kind in
        SeatView(
            kind: kind, person: kind == .human ? Person(id: "p\(i)", name: "P\(i)", cat: i) : nil,
            yours: kind == .human && mine.contains(i), presence: kind == .human ? .awake : nil)
    }
    return TableModel(room: RoomView(code: "BCDFG", name: "The Sneaky Lounge", status: status, youAreHost: true, seats: seats))
}

/// First-run funnel, part 1: the lobby a first table opens on, and who invited a guest.
@Suite struct FirstTableTests {
    @Test func aFirstTableSeatsAHouseCatSoStartIsLit() {
        let fresh = lobby([.human, .open, .closed, .closed])
        #expect(fresh.firstTableMessages == [.configure(seat: 1, kind: .bot)])
        #expect(!fresh.startLit)
        // With the House Cat in, Start deals.
        let ready = lobby([.human, .bot, .closed, .closed])
        #expect(ready.canStart && ready.startLit)
        #expect(ready.firstTableMessages == nil, "the House Cat is already there")
    }

    @Test func noHouseCatWhenSomeoneElseIsHereOrNobodyIsSeated() {
        #expect(lobby([.human, .human, .open, .closed], mine: [0]).firstTableMessages == nil)
        #expect(lobby([.open, .open, .closed, .closed], mine: []).firstTableMessages == nil)
        #expect(lobby([.human, .closed, .closed, .closed]).firstTableMessages == nil, "no open seat")
        #expect(lobby([.human, .open, .closed, .closed], status: .playing).firstTableMessages == nil)
        // Two people on this phone (pass and play) still get a House Cat.
        #expect(lobby([.human, .human, .open, .closed], mine: [0, 1]).firstTableMessages == [.configure(seat: 2, kind: .bot)])
    }

    @Test func startIsLitWithTwoCatsEvenWithASeatStillOpen() {
        let waiting = lobby([.human, .bot, .open, .closed])
        #expect(!waiting.canStart)
        #expect(waiting.startLit, "Start asks, then closes the open seat")
        #expect(!lobby([.human, .open, .closed, .closed]).startLit, "alone: Start waits")
    }

    @Test func anInviteOpensASeatOnlyWhenNoneIsOpen() {
        #expect(lobby([.human, .bot, .closed, .closed]).inviteMessages == [.configure(seat: 2, kind: .open)])
        #expect(lobby([.human, .open, .closed, .closed]).inviteMessages == nil, "a seat is already open")
        #expect(lobby([.human, .bot, .human, .bot], mine: [0]).inviteMessages == nil, "no closed seat to open")
        #expect(lobby([.open, .closed, .closed, .closed], mine: []).inviteMessages == nil, "not seated")
    }

    @Test func aGuestTakesAnOpenSeatFirstThenAHouseCats() {
        let owner = Person(id: "me", name: "Mia", cat: 2)
        let open = lobby([.human, .bot, .open, .closed], mine: [])
        #expect(RoomEntry.autoClaim(model: open, owner: owner) == .claim(seat: 2, person: owner))
        let catOnly = lobby([.human, .bot, .closed, .closed], mine: [])
        #expect(catOnly.takeableSeats == [1])
        #expect(RoomEntry.autoClaim(model: catOnly, owner: owner) == .claim(seat: 1, person: owner))
        let full = lobby([.human, .human, .closed, .closed], mine: [])
        #expect(RoomEntry.autoClaim(model: full, owner: owner) == nil)
        #expect(lobby([.human, .bot], mine: [], status: .playing).takeableSeats.isEmpty)
    }
}

@Suite struct InviteHostTests {
    @Test func theFirstPersonSeatedSavedTheSeat() throws {
        let room = lobby([.bot, .human, .open, .closed], mine: []).room
        let host = try #require(InviteHost.from(room))
        #expect(host == InviteHost(name: "P1", cat: 1, table: "The Sneaky Lounge", seatWaits: true))
    }

    @Test func aFullOrPlayingTableOnlySaysWhoInvited() throws {
        let full = try #require(InviteHost.from(lobby([.human, .human, .closed], mine: []).room))
        #expect(!full.seatWaits)
        let playing = try #require(InviteHost.from(lobby([.human, .open], mine: [], status: .playing).room))
        #expect(!playing.seatWaits)
        #expect(InviteHost.from(lobby([.bot, .open], mine: []).room) == nil, "nobody to name")
    }

    @Test func aPeekTakesTheFirstSnapshotAndHangsUp() async {
        let socket = FakeSocket()
        let room = lobby([.human, .bot], mine: []).room
        socket.feed.yield(.connecting)
        socket.feed.yield(.connected)
        socket.feed.yield(.message(.snapshot(protocol: 1, seq: 3, room: room)))
        let seen = await InviteHost.peek(socket, timeout: .seconds(5))
        #expect(seen == room)
        #expect(socket.calls.starts == 1)
        #expect(socket.calls.stops == 1)
        #expect(socket.calls.sends.isEmpty, "a peek never claims a seat")
    }

    @Test func aPeekGivesUpOnAMissingRoomOrSilence() async {
        let gone = FakeSocket()
        gone.feed.yield(.notFound)
        #expect(await InviteHost.peek(gone, timeout: .seconds(5)) == nil)
        let quiet = FakeSocket()
        #expect(await InviteHost.peek(quiet, timeout: .milliseconds(50)) == nil)
        #expect(quiet.calls.stops == 1)
    }
}
