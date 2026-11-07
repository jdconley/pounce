import Testing
@testable import PounceKit

@Suite struct PlayerCardTests {
    /// The demo table: me (Mia, seat 0) on phase 3, Leo laid phase 1, Kiki asleep on 7 with a
    /// skip waiting, the House Cat on 4.
    private let table = TableModel(room: DemoFixtures.table(seats: 4, mySeat: 0, phase: 2))
    private let me = "demo-0"

    @Test func gameFacts() throws {
        let leo = try #require(PlayerCard.make(model: table, seat: 1, streaks: nil))
        #expect(leo.kind == .away(.awake))
        #expect(leo.phase == 0)
        #expect(leo.phaseText == Rules.describe(phase: 0))
        #expect(leo.laid)
        #expect(!leo.skipped)
        #expect(leo.cards == table.game?.handCounts[1])
        #expect(leo.score == table.game?.scores[1])
        #expect(!leo.isTurn)
        #expect(leo.connection == .none, "streaks off: no row")

        let kiki = try #require(PlayerCard.make(model: table, seat: 2, streaks: nil))
        #expect(kiki.kind == .away(.asleep))
        #expect(kiki.skipped)
        #expect(kiki.phase == 6)
    }

    @Test func botHasGameFactsOnly() throws {
        let bot = try #require(PlayerCard.make(model: table, seat: 3, streaks: []))
        #expect(bot.kind == .bot)
        #expect(bot.person == nil)
        #expect(bot.connection == .none)
    }

    @Test func noCardForASeatTheGameDoesNotHave() {
        #expect(PlayerCard.make(model: table, seat: 9, streaks: nil) == nil)
    }

    @Test func pairMatchesByNameAndCat() throws {
        let kiki = streakView("pr_kiki", count: 9, partner: .init(name: "Kiki", cat: 6))
        let namesake = streakView("pr_leo", count: 4, partner: .init(name: "Leo", cat: 5))
        let card = try #require(PlayerCard.make(model: table, seat: 2, streaks: [(me, namesake), (me, kiki)]))
        #expect(card.connection == .connected(person: me, view: kiki))
        let leo = try #require(PlayerCard.make(model: table, seat: 1, streaks: [(me, namesake), (me, kiki)]))
        #expect(leo.connection == .notYet, "a Leo with another cat isn't this Leo")
    }

    @Test func pairAtThisTableCountsForItsOnlyOtherPerson() throws {
        // Two seats: Mia here, Leo on his phone, who changed his cat since the pair was made.
        let two = TableModel(room: DemoFixtures.table(seats: 2, mySeat: 0, phase: 0))
        let moved = streakView("pr_leo", partner: .init(name: "Leo", cat: 5), myMove: [DemoFixtures.code])
        #expect(PlayerCard.make(model: two, seat: 1, streaks: [(me, moved)])?.connection == .connected(person: me, view: moved))
        let reported = streakView("pr_leo", partner: .init(name: "Leon", cat: 5))
        #expect(PlayerCard.make(model: two, seat: 1, streaks: [(me, reported)], reported: ["pr_leo"])?.connection
            == .connected(person: me, view: reported))
        // With two other people at the table it could be either: not a match.
        #expect(PlayerCard.make(model: table, seat: 1, streaks: [(me, moved)])?.connection == .notYet)
    }

    @Test func aSharedPhonesOtherSeat() throws {
        var room = DemoFixtures.table(seats: 2, mySeat: 0, phase: 0)
        room.seats[1].yours = true
        let shared = TableModel(room: room)
        let leoID = try #require(room.seats[1].person?.id)
        // Leo's own pairs never count as a pair with Leo.
        let leos = streakView("pr_leo_mom", partner: .init(name: "Mom", cat: 5))
        let card = try #require(PlayerCard.make(model: shared, seat: 1, streaks: [(leoID, leos)]))
        #expect(card.kind == .here)
        #expect(card.connection == .notYet)
        let together = streakView("pr_mia_leo", partner: .init(name: "Leo", cat: 1))
        #expect(PlayerCard.make(model: shared, seat: 1, streaks: [(leoID, leos), (me, together)])?.connection
            == .connected(person: me, view: together))
    }

    @Test func pastTheLastPhaseHasNoText() throws {
        var room = DemoFixtures.table(seats: 2, mySeat: 0, phase: 0)
        room.game?.phase[1] = Rules.phases.count
        let card = try #require(PlayerCard.make(model: TableModel(room: room), seat: 1, streaks: nil))
        #expect(card.phase == Rules.phases.count)
        #expect(card.phaseText == nil)
    }
}
