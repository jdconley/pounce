import Foundation
import Testing
@testable import PounceKit

/// A Yarn in a run keeps the spot the player gave it, from the tray through the lay-down to
/// hits on the laid run (Cat Tower design, "Yarn in a run").
private func card(_ value: Int, _ coat: Coat, copy: Int = 0) -> CardID {
    Coat.allCases.firstIndex(of: coat)! * 24 + copy * 12 + value - 1
}

private let yarn: CardID = 96
private let yarn2: CardID = 97
private let four = card(4, .tabby), five = card(5, .tuxedo), six = card(6, .calico)
private let nines = [card(9, .tabby), card(9, .gray), card(9, .calico)]
private let phase2 = Rules.phases[1]  // set of 3, run of 4
private let run4 = Requirement(kind: .run, size: 4)

@Suite struct WildOrderRulesTests {
    @Test func aYarnKeepsItsSpotInTheCardsOrder() {
        #expect(Rules.buildGroup(run4, cards: [yarn, four, five, six]) == .run(cards: [yarn, four, five, six], start: 3, end: 6))
        #expect(Rules.buildGroup(run4, cards: [four, five, six, yarn]) == .run(cards: [four, five, six, yarn], start: 4, end: 7))
        #expect(Rules.buildGroup(run4, cards: [four, yarn, six, card(7, .gray)])
            == .run(cards: [four, yarn, six, card(7, .gray)], start: 4, end: 7))
        #expect(Rules.buildGroup(run4, cards: [yarn, five, six, yarn2]) == .run(cards: [yarn, five, six, yarn2], start: 4, end: 7))
    }

    @Test func runStartWinsAndANonRunOrderFallsBack() {
        #expect(Rules.buildGroup(run4, cards: [four, five, six, yarn], runStart: 3)
            == .run(cards: [yarn, four, five, six], start: 3, end: 6))
        #expect(Rules.buildGroup(run4, cards: [four, yarn, five, six]) == .run(cards: [yarn, four, five, six], start: 3, end: 6))
        #expect(Rules.buildGroup(run4, cards: [card(10, .tabby), card(11, .tabby), card(12, .tabby), yarn])
            == .run(cards: [yarn, card(10, .tabby), card(11, .tabby), card(12, .tabby)], start: 9, end: 12))
    }

    @Test func hitsUseTheYarnsRealRank() throws {
        let low = try #require(Rules.buildGroup(run4, cards: [yarn, four, five, six]))  // 3-6
        #expect(Rules.canHit(low, card: card(2, .gray)) == .run(cards: [card(2, .gray), yarn, four, five, six], start: 2, end: 6))
        #expect(Rules.canHit(low, card: card(7, .gray)) == .run(cards: [yarn, four, five, six, card(7, .gray)], start: 3, end: 7))
        #expect(Rules.canHit(low, card: card(3, .gray)) == nil)
        let high = try #require(Rules.buildGroup(run4, cards: [four, five, six, yarn]))  // 4-7
        #expect(Rules.canHit(high, card: card(3, .gray)) == .run(cards: [card(3, .gray), four, five, six, yarn], start: 3, end: 7))
        #expect(Rules.canHit(high, card: card(8, .gray)) == .run(cards: [four, five, six, yarn, card(8, .gray)], start: 4, end: 8))
        #expect(Rules.canHit(high, card: card(7, .gray)) == nil)
    }

    /// A game saved before this change (the Yarn low, 3-6) still decodes and plays.
    @Test func aRunLaidTheOldWayStillLoads() throws {
        let json = #"{"kind":"run","cards":[96,3,28,53],"start":3,"end":6}"#
        let group = try JSONDecoder().decode(Group.self, from: Data(json.utf8))
        #expect(group == .run(cards: [yarn, four, five, six], start: 3, end: 6))
        #expect(Rules.canHit(group, card: card(7, .gray)) != nil)
        #expect(Rules.canHit(group, card: card(3, .gray)) == nil)
    }
}

@Suite struct WildOrderTrayTests {
    private func trays(run: [CardID]) -> TrayState {
        var t = TrayState(requirements: phase2)
        for c in nines { t.add(c, to: 0) }
        for c in run { t.add(c, to: 1) }
        return t
    }

    @Test func aYarnDroppedAtTheEndStandsForTheHighCard() {
        var t = trays(run: [four, five, six])
        t.add(yarn, to: 1, at: 3)
        #expect(t.slots[1] == [four, five, six, yarn])
        #expect(t.layGroups()[1] == LayGroup(cards: [four, five, six, yarn], runStart: 4))
        #expect(Rules.matchPhase(1, groups: t.layGroups())?[1] == .run(cards: [four, five, six, yarn], start: 4, end: 7))
    }

    @Test func aYarnDroppedAtTheStartStandsForTheLowCard() {
        var t = trays(run: [four, five, six])
        t.add(yarn, to: 1, at: 0)
        #expect(t.slots[1] == [yarn, four, five, six])
        #expect(t.layGroups()[1] == LayGroup(cards: [yarn, four, five, six], runStart: 3))
    }

    @Test func aYarnWithNoSpotTakesTheDefault() {
        var t = trays(run: [four, five, six])
        t.add(yarn, to: 1)  // the tap path names no spot
        #expect(t.layGroups()[1].runStart == 3)
    }

    @Test func aPlacedYarnKeepsItsSpotWhileTheTrayFills() {
        var t = trays(run: [four, five])
        t.add(yarn, to: 1, at: 0)
        #expect(t.slots[1] == [yarn, four, five])  // not shoved to the end of an unfinished tray
        t.add(six, to: 1)
        #expect(t.slots[1] == [yarn, four, five, six])
        #expect(t.layGroups()[1].runStart == 3)

        var u = trays(run: [four, five])
        u.add(yarn, to: 1, at: 2)
        #expect(u.slots[1] == [four, five, yarn])
        u.add(six, to: 1)
        #expect(u.slots[1] == [four, five, six, yarn])  // still after the naturals: 7
        #expect(u.layGroups()[1].runStart == 4)
    }

    @Test func aGapStillDecides() {
        // 4 _ 6 7: the Yarn must be 5 wherever it was dropped.
        var t = trays(run: [four, six, card(7, .gray)])
        t.add(yarn, to: 1, at: 3)
        #expect(t.slots[1] == [four, yarn, six, card(7, .gray)])
        #expect(t.layGroups()[1].runStart == 4)
    }

    @Test func twoYarnsKeepThePlayersOrder() {
        var t = trays(run: [five, six])
        t.add(yarn, to: 1, at: 0)
        t.add(yarn2, to: 1, at: 3)
        #expect(t.slots[1] == [yarn, five, six, yarn2])
        #expect(t.layGroups()[1].runStart == 4)
    }

    @Test func aMovedYarnKeepsItsSpotWhenANaturalComesAndGoes() {
        var t = trays(run: [four, five, six, yarn])
        t.moveYarn(yarn, inTray: 1, toIndex: 3)
        #expect(t.slots[1] == [four, five, six, yarn])
        t.remove(four)
        t.add(four, to: 1)
        #expect(t.slots[1] == [four, five, six, yarn])
        #expect(t.layGroups()[1].runStart == 4)
    }

    @Test func whatTheTraySendsIsWhatItShows() {
        // Every placement path, then: the lay-down builds exactly the tray's order.
        for spot in [nil, 0, 1, 2, 3] as [Int?] {
            for naturals in [[four, five, six], [card(1, .gray), card(2, .gray), card(3, .gray)], [four, six, card(7, .gray)]] {
                var t = trays(run: naturals)
                t.add(yarn, to: 1, at: spot)
                let built = Rules.matchPhase(1, groups: t.layGroups())
                #expect(built?[1].cards == t.slots[1], "spot \(String(describing: spot)) \(naturals)")
            }
        }
    }
}
