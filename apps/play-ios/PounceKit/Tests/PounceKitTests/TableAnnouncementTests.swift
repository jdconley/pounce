import Testing
@testable import PounceKit

@Suite struct TableAnnouncementTests {
    @Test func yourTurnOnlyForMySeats() {
        let one = TableModel(room: makeRoom(seatCount: 3, mine: [1]))
        #expect(TableAnnouncement.announcement(for: .turn(seat: 1), model: one) == .yourTurn(seat: 1, multiSeat: false))
        #expect(TableAnnouncement.announcement(for: .turn(seat: 2), model: one) == nil)
        let two = TableModel(room: makeRoom(seatCount: 3, mine: [0, 2]))
        #expect(TableAnnouncement.announcement(for: .turn(seat: 2), model: two) == .yourTurn(seat: 2, multiSeat: true))
    }

    @Test func roundOverCarriesMyPointsOnly() {
        let model = TableModel(room: makeRoom(seatCount: 3, mine: [0, 2]))
        let event = GameEvent.roundOver(wentOut: 1, points: [15, 0, 35], advanced: [1], scores: [15, 0, 35], phase: [0, 1, 0])
        #expect(TableAnnouncement.announcement(for: event, model: model) == .roundOver(mine: [
            .init(seat: 0, points: 15), .init(seat: 2, points: 35),
        ]))
        let seatless = TableModel(room: makeRoom(seatCount: 3, mine: []))
        #expect(TableAnnouncement.announcement(for: event, model: seatless) == .roundOver(mine: []))
    }

    @Test func gameOverNamesTheWinnersAndOtherEventsAreSilent() {
        let model = TableModel(room: makeRoom())
        #expect(TableAnnouncement.announcement(for: .gameOver(winners: [2, 3]), model: model) == .gameOver(winners: [2, 3]))
        #expect(TableAnnouncement.announcement(for: .drew(seat: 1, from: .deck, card: nil), model: model) == nil)
        #expect(TableAnnouncement.announcement(for: .discarded(seat: 0, card: 4, skipTarget: nil), model: model) == nil)
    }
}
