import Testing
@testable import PounceKit

/// The hit list a phone shows on Cards (its table on a TV): the table's own legal targets, mine
/// first, then the others in turn order, each labelled just enough to tell it apart.
@Suite struct HitChoicesTests {
    private func id(_ value: Int, _ coat: Coat, copy: Int = 0) -> CardID {
        Coat.allCases.firstIndex(of: coat)! * 24 + value - 1 + copy * 12
    }

    private func run(_ start: Int, _ end: Int, _ coat: Coat = .tabby, copy: Int = 0) -> Group {
        .run(cards: (start...end).map { id($0, coat, copy: copy) }, start: start, end: end)
    }

    private func set(_ value: Int, _ coats: [Coat], copy: Int = 0) -> Group {
        .set(cards: coats.map { id(value, $0, copy: copy) }, value: value)
    }

    @Test func theDemoYarnListsMineFirstThenLeosAndOnlyLegalOnes() {
        let model = TableModel(room: DemoFixtures.hitTable())
        let choices = HitChoices.choices(model: model, card: 96, seat: 0)
        #expect(choices.map(\.target) == [
            HitTarget(seat: 0, group: 0), HitTarget(seat: 0, group: 1), HitTarget(seat: 1, group: 0), HitTarget(seat: 1, group: 1),
        ])
        #expect(choices.map(\.kind) == [.set(value: 9), .set(value: 10), .set(value: 7), .run(start: 4)])
        #expect(choices.map(\.mine) == [true, true, false, false])
        #expect(choices.map(\.detail) == [.number, .number, .number, .plain])
        // The calico 3 fits only below Leo's run; the gray 2 fits nothing.
        #expect(HitChoices.choices(model: model, card: id(3, .calico), seat: 0).map(\.target) == [HitTarget(seat: 1, group: 1)])
        #expect(HitChoices.choices(model: model, card: id(2, .gray), seat: 0).isEmpty)
    }

    @Test func nothingIsListedOffTurnOrBeforeLayingDown() {
        var room = DemoFixtures.hitTable()
        room.game?.turn = 1
        #expect(HitChoices.choices(model: TableModel(room: room), card: 96, seat: 0).isEmpty)
        room = DemoFixtures.hitTable()
        room.game?.laid[0] = nil
        #expect(HitChoices.choices(model: TableModel(room: room), card: 96, seat: 0).isEmpty)
    }

    @Test func othersComeInTurnOrderAfterThePicker() {
        let room = makeRoom(
            seatCount: 4, mine: [2], turn: 2, step: .play,
            laid: [[run(1, 4)], [run(2, 5, .gray)], [set(9, [.tabby, .gray, .calico])], [run(3, 6, .calico)]])
        let targets = [HitTarget(seat: 0, group: 0), HitTarget(seat: 1, group: 0), HitTarget(seat: 2, group: 0), HitTarget(seat: 3, group: 0)]
        let choices = HitChoices.choices(model: TableModel(room: room), targets: targets, seat: 2)
        #expect(choices.map(\.target.seat) == [2, 3, 0, 1])
        #expect(choices.map(\.mine) == [true, false, false, false])
        // One run each: just "run".
        #expect(choices.filter { $0.target.seat != 2 }.allSatisfy { $0.detail == .plain })
    }

    @Test func twoRunsOfOneOwnerNameTheirStartAndTwinsAreNumbered() {
        let room = makeRoom(
            seatCount: 3, mine: [0], turn: 0, step: .play,
            laid: [
                [set(9, [.tabby, .gray, .calico]), set(9, [.tabby, .gray, .calico], copy: 1)],
                [run(1, 4), run(7, 10, .gray), run(1, 4, .calico)],
                [.coat(cards: [id(1, .tuxedo), id(5, .tuxedo), id(9, .tuxedo)], coat: .tuxedo)],
            ])
        let targets = [
            HitTarget(seat: 0, group: 0), HitTarget(seat: 0, group: 1),
            HitTarget(seat: 1, group: 0), HitTarget(seat: 1, group: 1), HitTarget(seat: 1, group: 2),
            HitTarget(seat: 2, group: 0),
        ]
        let choices = HitChoices.choices(model: TableModel(room: room), targets: targets, seat: 0)
        #expect(choices.map(\.detail) == [.ordinal(1), .ordinal(2), .ordinal(1), .number, .ordinal(2), .number])
        #expect(choices.map(\.kind) == [
            .set(value: 9), .set(value: 9), .run(start: 1), .run(start: 7), .run(start: 1), .coat(.tuxedo),
        ])
        // Listing one of Leo's runs alone: just "Leo's run".
        let one = HitChoices.choices(model: TableModel(room: room), targets: [HitTarget(seat: 1, group: 1)], seat: 0)
        #expect(one.map(\.detail) == [.plain])
    }
}
