import Testing
@testable import PounceKit

/// Card id for `value` (1-12) in `coat`; `copy` 1 picks the second deck copy.
private func card(_ value: Int, _ coat: Coat, copy: Int = 0) -> CardID {
    Coat.allCases.firstIndex(of: coat)! * 24 + copy * 12 + value - 1
}

private let yarn: CardID = 96
private let yarn2: CardID = 97
private let cucumber: CardID = 104
private let phase2 = Rules.phases[1]  // set of 3, run of 4

@Suite struct TrayStateTests {
    @Test func phaseTwoTraysProduceGroupsInPhaseOrder() {
        var trays = TrayState(requirements: phase2)
        #expect(trays.slots == [[], []])
        #expect(!trays.allValid)
        // Run first, out of order: it auto-sorts ascending.
        for c in [card(6, .gray), card(4, .tabby), card(7, .calico), card(5, .tuxedo)] { trays.add(c, to: 1) }
        #expect(trays.isValid(1))
        #expect(trays.slots[1] == [card(4, .tabby), card(5, .tuxedo), card(6, .gray), card(7, .calico)])
        #expect(!trays.allValid)
        for c in [card(9, .tabby), card(9, .gray), card(9, .calico)] { trays.add(c, to: 0) }
        #expect(trays.isValid(0))
        #expect(trays.allValid)
        let groups = trays.layGroups()
        #expect(groups.count == 2)
        #expect(groups[0] == LayGroup(cards: [card(9, .tabby), card(9, .gray), card(9, .calico)]))
        #expect(groups[1].cards == [card(4, .tabby), card(5, .tuxedo), card(6, .gray), card(7, .calico)])
        #expect(groups[1].runStart == 4)
        #expect(Rules.matchPhase(1, groups: groups) != nil)
        #expect(trays.cardsInTrays.count == 7)
    }

    @Test func runWithYarnUsesTheDefaultStart() {
        var trays = TrayState(requirements: phase2)
        for c in [card(7, .gray), yarn, card(5, .tabby), card(6, .calico)] { trays.add(c, to: 1) }
        #expect(trays.isValid(1))
        // The server's default is the lowest start that fits: 4, so the Yarn stands for 4.
        let run = trays.layGroups()[1]
        #expect(run.runStart == 4)
        #expect(run.cards == [yarn, card(5, .tabby), card(6, .calico), card(7, .gray)])
        #expect(trays.slots[1] == run.cards)
        #expect(Rules.buildGroup(phase2[1], cards: run.cards, runStart: run.runStart) == .run(cards: run.cards, start: 4, end: 7))
    }

    @Test func moveYarnChangesRunStart() {
        var trays = TrayState(requirements: phase2)
        for c in [card(5, .tabby), card(6, .calico), card(7, .gray), yarn] { trays.add(c, to: 1) }
        #expect(trays.layGroups()[1].runStart == 4)
        // To the back: the Yarn now stands for 8.
        trays.moveYarn(yarn, inTray: 1, toIndex: 3)
        #expect(trays.layGroups()[1].runStart == 5)
        #expect(trays.slots[1] == [card(5, .tabby), card(6, .calico), card(7, .gray), yarn])
        #expect(trays.isValid(1))
        // Back to the front: runStart moves by -1.
        trays.moveYarn(yarn, inTray: 1, toIndex: 0)
        #expect(trays.layGroups()[1].runStart == 4)
        #expect(trays.slots[1].first == yarn)
        let run = trays.layGroups()[1]
        #expect(Rules.buildGroup(phase2[1], cards: run.cards, runStart: run.runStart) != nil)
    }

    @Test func canMoveYarnOnlyInAValidRunTray() {
        var trays = TrayState(requirements: phase2)
        for c in [card(5, .tabby), card(6, .calico), yarn] { trays.add(c, to: 1) }
        #expect(!trays.canMoveYarn(yarn, inTray: 1))  // 3 of 4: not a run yet
        trays.add(card(7, .gray), to: 1)
        #expect(trays.canMoveYarn(yarn, inTray: 1))
        #expect(!trays.canMoveYarn(card(5, .tabby), inTray: 1))  // a natural
        #expect(!trays.canMoveYarn(yarn, inTray: 0))  // not in that tray
        for c in [card(9, .tabby), card(9, .gray), yarn2] { trays.add(c, to: 0) }
        #expect(trays.isValid(0))
        #expect(!trays.canMoveYarn(yarn2, inTray: 0))  // a set: the Yarn has no place to move
    }

    @Test func moveYarnIgnoresIllegalPlacements() {
        var trays = TrayState(requirements: phase2)
        for c in [card(1, .tabby), card(2, .calico), card(3, .gray), yarn] { trays.add(c, to: 1) }
        #expect(trays.layGroups()[1].runStart == 1)
        trays.moveYarn(yarn, inTray: 1, toIndex: 0)  // would need a 0
        #expect(trays.layGroups()[1].runStart == 1)
        #expect(trays.slots[1] == [card(1, .tabby), card(2, .calico), card(3, .gray), yarn])
        // A natural can't be moved, and a set tray has no placement.
        trays.moveYarn(card(2, .calico), inTray: 1, toIndex: 0)
        #expect(trays.slots[1] == [card(1, .tabby), card(2, .calico), card(3, .gray), yarn])
    }

    @Test func moveYarnInAGapPicksTheMatchingStart() {
        // Two Yarns around 6 and 8: Yarns fill 7 and one end.
        var trays = TrayState(requirements: phase2)
        for c in [card(6, .tabby), yarn, card(8, .gray), yarn2] { trays.add(c, to: 1) }
        #expect(trays.layGroups()[1].runStart == 5)
        #expect(trays.slots[1] == [yarn, card(6, .tabby), yarn2, card(8, .gray)])
        trays.moveYarn(yarn, inTray: 1, toIndex: 3)
        #expect(trays.layGroups()[1].runStart == 6)
        #expect(trays.slots[1] == [card(6, .tabby), yarn2, card(8, .gray), yarn])
        // Swapping the two Yarns inside the same start keeps the start.
        trays.moveYarn(yarn, inTray: 1, toIndex: 1)
        #expect(trays.layGroups()[1].runStart == 6)
        #expect(trays.slots[1] == [card(6, .tabby), yarn, card(8, .gray), yarn2])
    }

    @Test func cucumberKeepsATrayInvalid() {
        var trays = TrayState(requirements: phase2)
        for c in [card(9, .tabby), card(9, .gray), cucumber] { trays.add(c, to: 0) }
        #expect(!trays.isValid(0))
        trays.add(card(9, .calico), to: 0)  // full: ignored
        #expect(trays.slots[0] == [card(9, .tabby), card(9, .gray), cucumber])
        #expect(!trays.isValid(0))
        trays.remove(cucumber)
        trays.add(card(9, .calico), to: 0)
        #expect(trays.isValid(0))
    }

    @Test func removingACardUngolds() {
        var trays = TrayState(requirements: phase2)
        for c in [card(9, .tabby), card(9, .gray), card(9, .calico)] { trays.add(c, to: 0) }
        #expect(trays.isValid(0))
        trays.remove(card(9, .gray))
        #expect(!trays.isValid(0))
        #expect(!trays.cardsInTrays.contains(card(9, .gray)))
        #expect(trays.slots[0] == [card(9, .tabby), card(9, .calico)])
    }

    @Test func addingMovesACardBetweenTraysAndResetsPlacement() {
        var trays = TrayState(requirements: phase2)
        for c in [card(5, .tabby), card(6, .calico), card(7, .gray), yarn] { trays.add(c, to: 1) }
        trays.moveYarn(yarn, inTray: 1, toIndex: 3)
        #expect(trays.layGroups()[1].runStart == 5)
        trays.add(yarn, to: 0)
        #expect(trays.slots[0] == [yarn])
        #expect(trays.slots[1] == [card(5, .tabby), card(6, .calico), card(7, .gray)])
        trays.add(yarn, to: 1)
        #expect(trays.layGroups()[1].runStart == 4)  // the explicit placement went with the change
        // Bad tray indexes are ignored.
        trays.add(card(1, .gray), to: 5)
        #expect(!trays.cardsInTrays.contains(card(1, .gray)))
    }

    @Test func keepOnlyDropsCardsThatLeftTheHand() {
        var trays = TrayState(requirements: phase2)
        for c in [card(9, .tabby), card(9, .gray), card(9, .calico)] { trays.add(c, to: 0) }
        trays.keep(only: [card(9, .tabby), card(9, .calico), card(2, .gray)])
        #expect(trays.slots[0] == [card(9, .tabby), card(9, .calico)])
    }

    @Test func emptyRequirementsAreNeverValid() {
        let trays = TrayState(requirements: [])
        #expect(!trays.allValid)
        #expect(trays.layGroups().isEmpty)
        #expect(!trays.isValid(0))
    }

    @Test func coatTrayKeepsInsertionOrder() {
        var trays = TrayState(requirements: Rules.phases[7])  // 7 of one coat
        let cards = [card(3, .tabby), card(11, .tabby), card(1, .tabby), yarn, card(8, .tabby), card(3, .tabby, copy: 1), card(12, .tabby)]
        for c in cards { trays.add(c, to: 0) }
        #expect(trays.isValid(0))
        #expect(trays.layGroups() == [LayGroup(cards: cards)])
    }
}
