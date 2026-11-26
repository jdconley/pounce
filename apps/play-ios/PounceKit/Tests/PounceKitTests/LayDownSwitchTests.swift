import Testing
@testable import PounceKit

/// A phone on Cards at a TV table goes to Table when its own player lays down.
@Suite struct LayDownSwitchTests {
    private let laid = GameEvent.laidDown(seat: 1, groups: [])

    @Test func myLayDownOnCardsShowsTheTable() {
        #expect(TableView.afterLayDown(laid, mine: [1], showing: .cards) == .table)
        #expect(TableView.afterLayDown(laid, mine: [0, 1], showing: .cards) == .table)  // pass and play
    }

    @Test func someoneElsesLayDownOrAnotherMoveChangesNothing() {
        #expect(TableView.afterLayDown(laid, mine: [0], showing: .cards) == nil)
        #expect(TableView.afterLayDown(.turn(seat: 1), mine: [1], showing: .cards) == nil)
        #expect(TableView.afterLayDown(.hit(seat: 1, card: 5, target: HitTarget(seat: 0, group: 0), group: .set(cards: [], value: 5)),
                                       mine: [1], showing: .cards) == nil)
    }

    @Test func alreadyOnTableOrNoTVChangesNothing() {
        #expect(TableView.afterLayDown(laid, mine: [1], showing: .table) == nil)
        #expect(TableView.afterLayDown(laid, mine: [1], showing: nil) == nil)
    }
}
