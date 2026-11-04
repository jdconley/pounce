import Testing
@testable import PounceKit

private let mia = Person(id: "mia", name: "Mia", cat: 0)
private let leo = Person(id: "leo", name: "Leo", cat: 1)

private func room(_ seats: [SeatView], status: RoomStatus = .playing) -> TableModel {
    TableModel(room: RoomView(code: "BCDFG", status: status, youAreHost: true, seats: seats))
}

@Suite struct SeatNamesTests {
    @Test func peopleBotsAndEmptySeats() {
        let seats = [
            SeatView(kind: .human, person: mia, yours: true, presence: .awake),
            SeatView(kind: .bot),
            SeatView(kind: .open),
            SeatView(kind: .closed),
        ]
        #expect(SeatNames.names(seats, bot: "House Cat") == ["Mia", "House Cat", "", ""])
    }

    @Test func secondAndThirdBotsAreNumbered() {
        let seats = [SeatView(kind: .bot), SeatView(kind: .human, person: leo), SeatView(kind: .bot), SeatView(kind: .bot)]
        #expect(SeatNames.names(seats, bot: "House Cat") == ["House Cat", "Leo", "House Cat 2", "House Cat 3"])
    }

    @Test func renamesMySeatsWhosePersonWasRenamedHere() {
        var sync = NameSync()
        let model = room([
            SeatView(kind: .human, person: mia, yours: true, presence: .awake),
            SeatView(kind: .human, person: leo, yours: false, presence: .awake),
        ])
        // Leo is on another phone: only my seat is mine to rename.
        let people = [Person(id: "mia", name: "Mia J", cat: 0), Person(id: "leo", name: "Leon", cat: 1)]
        #expect(sync.renames(model, people: people) == [.renameSeat(seat: 0, name: "Mia J")])
    }

    @Test func sendsEachRenameOnceUntilTheNameChangesAgain() {
        var sync = NameSync()
        let model = room([SeatView(kind: .human, person: mia, yours: true, presence: .awake)])
        let renamed = [Person(id: "mia", name: "Mimi", cat: 0)]
        #expect(sync.renames(model, people: renamed) == [.renameSeat(seat: 0, name: "Mimi")])
        // The old snapshot again (the rename is in flight, or was refused): nothing more.
        #expect(sync.renames(model, people: renamed).isEmpty)
        // Renamed again before it landed: the newer name goes.
        #expect(sync.renames(model, people: [Person(id: "mia", name: "Mo", cat: 0)]) == [.renameSeat(seat: 0, name: "Mo")])
    }

    @Test func matchingNamesSendNothingAndResetTheLastSent() {
        var sync = NameSync()
        let model = room([SeatView(kind: .human, person: mia, yours: true, presence: .awake)])
        #expect(sync.renames(model, people: [mia]).isEmpty)
        _ = sync.renames(model, people: [Person(id: "mia", name: "Mimi", cat: 0)])
        // The rename landed; renaming back to Mimi later must go out again.
        let landed = room([SeatView(kind: .human, person: Person(id: "mia", name: "Mimi", cat: 0), yours: true, presence: .awake)])
        #expect(sync.renames(landed, people: [Person(id: "mia", name: "Mimi", cat: 0)]).isEmpty)
        #expect(sync.renames(model, people: [Person(id: "mia", name: "Mimi", cat: 0)]) == [.renameSeat(seat: 0, name: "Mimi")])
    }

    @Test func nothingForStrangersBotsOrAFinishedRoom() {
        var sync = NameSync()
        let stranger = Person(id: "moved-here", name: "Pip", cat: 4)
        let seats = [
            SeatView(kind: .human, person: stranger, yours: true, presence: .awake),
            SeatView(kind: .bot),
            SeatView(kind: .human, person: mia, yours: true, presence: .awake),
        ]
        let renamed = [Person(id: "mia", name: "Mimi", cat: 0)]
        #expect(sync.renames(room(seats, status: .over), people: renamed).isEmpty)
        #expect(sync.renames(room(seats), people: renamed) == [.renameSeat(seat: 2, name: "Mimi")])
    }
}
