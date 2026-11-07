import CoreGraphics
import Testing
@testable import PounceKit

/// A drag over the laid groups asks where the card would land on every touch move (60 to 120
/// times a second). JD's playtest: dragging over a busy table stuttered and the card lagged
/// behind the finger. The rules run once per pick-up and once per group end reached, and the
/// card is drawn on its target every frame.
@Suite struct DragPerfTests {
    /// The `-demo crowdedHit` table: six seats, all laid, my play step.
    private let model = TableModel(room: DemoFixtures.crowdedHit())

    private var allGroups: [HitTarget] {
        guard let game = model.game else { return [] }
        return game.laid.enumerated().flatMap { seat, groups in
            (groups ?? []).indices.map { HitTarget(seat: seat, group: $0) }
        }
    }

    @Test func aimsRunTheRulesOncePerGroupEndNotPerMove() {
        let yarn: CardID = 96
        var aims = HitAims(model: model, card: yarn, seat: 0)
        #expect(aims.ruleRuns == 1)
        #expect(aims.targets == Set(model.hitTargets(card: yarn, seat: 0)))
        #expect(aims.targets.count >= 8, "a Yarn fits most of the crowded table's groups")

        // A long drag: 600 touch moves sweeping back and forth over every group and end.
        let groups = allGroups
        for move in 0..<600 {
            let target = groups[(move / 7) % groups.count]
            _ = aims.plan(target: target, toward: move % 2 == 0 ? .start : .end)
        }
        // Once for the targets, then at most once per group and end that can take the card.
        #expect(aims.ruleRuns <= 1 + 2 * aims.targets.count)
        let after = aims.ruleRuns
        for move in 0..<600 {
            _ = aims.plan(target: groups[move % groups.count], toward: move % 3 == 0 ? .start : .end)
        }
        #expect(aims.ruleRuns == after, "nothing new: the rules never run again")
    }

    @Test func aimsAgreeWithTheModelEverywhere() {
        for card in [CardID(96), 104] + (model.game?.hands[0] ?? []) {
            var aims = HitAims(model: model, card: card, seat: 0)
            for target in allGroups + [HitTarget(seat: 9, group: 0), HitTarget(seat: 1, group: 7)] {
                for side in [HitSide.start, .end] {
                    #expect(aims.plan(target: target, toward: side) == model.hitPlan(card: card, seat: 0, target: target, toward: side))
                }
            }
        }
    }

    @Test func aimsWithNoSeatToActForHitNothing() {
        var aims = HitAims(model: model, card: 96, seat: nil)
        #expect(aims.targets.isEmpty)
        #expect(allGroups.allSatisfy { aims.plan(target: $0, toward: .end) == nil })
        #expect(aims.ruleRuns == 1)
    }

    @Test func crowdedHitTableIsConsistent() throws {
        let game = try #require(model.game)
        #expect(game.laid.allSatisfy { $0 != nil })
        #expect(game.step == .play)
        var visible = game.hands.values.flatMap { $0 }
        visible += game.laid.compactMap { $0 }.flatMap { $0.flatMap(\.cards) }
        if let top = game.discardTop { visible.append(top) }
        #expect(Set(visible).count == visible.count)
        let laidCount = game.laid.compactMap { $0 }.flatMap { $0 }.reduce(0) { $0 + $1.cards.count }
        #expect(game.deckCount + game.discardCount + game.handCounts.reduce(0, +) + laidCount == Card.deckSize)
        #expect(Rules.matchPhase(game.phase[0], groups: (game.laid[0] ?? []).map { LayGroup(cards: $0.cards) }) != nil)
    }

    // MARK: following the finger

    @Test func theCardSitsOnTheFingerEveryMove() {
        var follow = DragFollow(duration: 0.12)
        follow.move(to: CGPoint(x: 100, y: 100), jump: false, at: 0)
        // 120 Hz moves, no jump: drawn exactly where the finger puts it, never behind.
        for i in 1...120 {
            let t = Double(i) / 120
            let target = CGPoint(x: 100 + 5 * Double(i), y: 100 + 2 * Double(i))
            follow.move(to: target, jump: false, at: t)
            #expect(follow.position(at: t) == target)
        }
    }

    @Test func aJumpEasesOverWhileTheCardKeepsMovingWithTheFinger() throws {
        var follow = DragFollow(duration: 0.12)
        follow.move(to: CGPoint(x: 100, y: 100), jump: false, at: 0)
        // Lifted above a laid group: the target jumps 80 pt up.
        follow.move(to: CGPoint(x: 100, y: 180), jump: true, at: 1)
        #expect(follow.position(at: 1) == CGPoint(x: 100, y: 100), "no snap")
        #expect(follow.isEasing(at: 1.05))
        // The finger keeps moving every frame; the card moves with it while the jump eases.
        var lastGap = CGFloat.infinity
        for i in 1...14 {
            let t = 1 + Double(i) / 120
            let target = CGPoint(x: 100 + 4 * Double(i), y: 180)
            follow.move(to: target, jump: false, at: t)
            let drawn = try #require(follow.position(at: t))
            #expect(drawn.x == target.x, "it moves with the finger across")
            let gap = target.y - drawn.y
            #expect(gap < lastGap, "the jump only ever closes")
            lastGap = gap
        }
        // Done after `duration`, however often the finger moved meanwhile.
        #expect(!follow.isEasing(at: 1.12))
        #expect(follow.position(at: 1.12) == CGPoint(x: 156, y: 180))
    }

    @Test func aJumpDuringAJumpStartsFromWhereTheCardIsDrawn() throws {
        var follow = DragFollow(duration: 0.12)
        follow.move(to: .zero, jump: false, at: 0)
        follow.move(to: CGPoint(x: 0, y: 100), jump: true, at: 1)
        let mid = try #require(follow.position(at: 1.06))
        follow.move(to: CGPoint(x: 0, y: -50), jump: true, at: 1.06)
        #expect(follow.position(at: 1.06) == mid)
        #expect(follow.position(at: 1.2) == CGPoint(x: 0, y: -50))
    }
}
