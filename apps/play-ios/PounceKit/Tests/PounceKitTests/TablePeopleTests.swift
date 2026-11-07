import Foundation
import Testing
@testable import PounceKit

@Suite struct TablePeopleTests {
    private let me = Person(id: "me", name: "JD", cat: 2)
    private let leo = Person(id: "leo", name: "Leo", cat: 5)

    private func human(_ name: String, _ cat: Int, id: String? = nil, yours: Bool = false) -> CachedSeat {
        CachedSeat(kind: .human, name: name, cat: cat, yours: yours, person: id)
    }

    private func pair(_ name: String, _ cat: Int, moves: [String] = []) -> StreakView {
        StreakView(pair: "pr_\(name)", partner: .init(name: name, cat: cat), count: 3, theirMove: moves)
    }

    private func line(
        _ seats: [CachedSeat], household: [Person] = [], pairs: [StreakView] = [], band: AgeBand? = .adult
    ) -> TablePeople.Line {
        TablePeople.line(
            seats: seats, code: "K7QM4", owner: me.id, household: household, pairs: pairs, band: band,
            bot: "House Cat", botCat: 3)
    }

    private func names(_ line: TablePeople.Line) -> [String] { line.faces.map(\.name) }

    @Test func youAreNeverListed() {
        let l = line([human("JD", 2, id: "me", yours: true), human("Sam", 4, id: "sam")])
        #expect(names(l) == ["Sam"])
        // Your seat from your account's list on another device: marked yours, another person id.
        #expect(names(line([human("JD", 2, id: "ipad", yours: true), human("Sam", 4)])) == ["Sam"])
        // An older cache: no ids, your seat only marked yours.
        #expect(names(line([human("JD", 2, yours: true), human("Sam", 4)])) == ["Sam"])
    }

    @Test func connectionsComeFirstOnPills() {
        let l = line(
            [human("JD", 2, id: "me", yours: true), human("Biscuit", 1), human("Sam", 4), human("Pickle", 7)],
            pairs: [pair("Sam", 4)])
        #expect(l.faces == [
            .init(name: "Sam", cat: 4, close: true),
            .init(name: "Biscuit", cat: 1, close: false),
            .init(name: "Pickle", cat: 7, close: false),
        ])
    }

    @Test func aConnectionMatchesByNameAndCatOrByNameAtASharedTable() {
        // A new cat since: still them at a table the pair shares.
        #expect(line([human("Sam", 1)], pairs: [pair("Sam", 4, moves: ["K7QM4"])]).faces.first?.close == true)
        // Same name, other cat, no shared table: someone else.
        #expect(line([human("Sam", 1)], pairs: [pair("Sam", 4)]).faces.first?.close == false)
    }

    @Test func someoneSharingThisPhoneIsListedAsYourOwn() {
        let l = line([human("JD", 2, id: "me", yours: true), human("Leo", 5, id: "leo", yours: true)], household: [leo])
        #expect(l.faces == [.init(name: "Leo", cat: 5, close: true)])
    }

    @Test func botsReadAsTheBotsNameNumberedAfterPeople() {
        let l = line([CachedSeat(kind: .bot), human("JD", 2, id: "me", yours: true), CachedSeat(kind: .bot), human("Sam", 4)])
        #expect(names(l) == ["Sam", "House Cat", "House Cat 2"])
        #expect(l.faces.last?.cat == 3)
    }

    @Test func openAndClosedSeatsAreNobody() {
        let l = line([human("JD", 2, id: "me", yours: true), CachedSeat(kind: .open), CachedSeat(kind: .closed)])
        #expect(l.isEmpty)
    }

    @Test func aKittensPhoneNamesOnlyItsOwnPeopleAndBots() {
        let seats = [
            human("JD", 2, id: "me", yours: true), human("Mom", 6), human("Biscuit", 1), CachedSeat(kind: .bot),
        ]
        let l = line(seats, pairs: [pair("Mom", 6)], band: .kitten)
        #expect(names(l) == ["Mom", "House Cat"])
        #expect(l.unnamed == 1)
        // A teen's and an adult's phone name everyone.
        #expect(names(line(seats, pairs: [pair("Mom", 6)], band: .teen)) == ["Mom", "Biscuit", "House Cat"])
    }

    @Test func variantsDropOneNameAtATimeIntoTheCount() {
        let faces = ["A", "B", "C"].map { TablePeople.Face(name: $0, cat: 0, close: false) }
        let variants = TablePeople.Line(faces: faces, unnamed: 1).variants
        #expect(variants.map { $0.faces.map(\.name) } == [["A", "B", "C"], ["A", "B"], ["A"]])
        #expect(variants.map(\.more) == [1, 2, 3])
        #expect(TablePeople.Line(faces: [], unnamed: 2).variants.map(\.more) == [2])
    }
}
