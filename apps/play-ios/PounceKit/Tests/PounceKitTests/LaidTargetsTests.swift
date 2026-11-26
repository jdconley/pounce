import CoreGraphics
import Testing
@testable import PounceKit

/// Which laid group a dragged card is over, and which end of it.
@Suite struct LaidTargetsTests {
    private let a = HitTarget(seat: 1, group: 0)
    private let b = HitTarget(seat: 1, group: 1)
    private let c = HitTarget(seat: 2, group: 0)

    /// Two groups side by side (8 pt apart) and one row 8 pt below, as `LaidZoneNode` draws
    /// them; mini cards 41 x 58.
    private var frames: [(target: HitTarget, frame: CGRect)] {
        [
            (a, CGRect(x: 40, y: 100, width: 80, height: 58)),
            (b, CGRect(x: 128, y: 100, width: 60, height: 58)),
            (c, CGRect(x: 40, y: 34, width: 100, height: 58)),
        ]
    }

    /// JD's bug: a drop in the strip between two rows went to the row listed first, even with
    /// the finger nearer the other one. The nearest group wins.
    @Test func theNearestGroupWinsBetweenRows() {
        #expect(LaidTargets.target(at: CGPoint(x: 60, y: 95), in: frames) == c)   // 3 pt off c, 5 off a
        #expect(LaidTargets.target(at: CGPoint(x: 60, y: 97), in: frames) == a)   // 3 off a, 5 off c
        #expect(LaidTargets.target(at: CGPoint(x: 125, y: 120), in: frames) == b) // 3 off b, 5 off a
        #expect(LaidTargets.target(at: CGPoint(x: 123, y: 120), in: frames) == a)
    }

    @Test func aFingerOnAGroupAlwaysPicksIt() {
        for (target, f) in frames {
            for p in [CGPoint(x: f.minX + 1, y: f.minY + 1), CGPoint(x: f.midX, y: f.midY), CGPoint(x: f.maxX - 1, y: f.maxY - 1)] {
                #expect(LaidTargets.target(at: p, in: frames) == target)
            }
        }
    }

    /// Generous on the smallest phone: a finger up to `reach` past a group's edge still takes it.
    @Test func reachIsGenerousButBounded() {
        #expect(LaidTargets.reach >= 14)
        #expect(LaidTargets.target(at: CGPoint(x: 40 - 13, y: 120), in: frames) == a)
        #expect(LaidTargets.target(at: CGPoint(x: 80, y: 158 + 13), in: frames) == a)
        #expect(LaidTargets.target(at: CGPoint(x: 80, y: 158 + LaidTargets.reach + 1), in: frames) == nil)
        #expect(LaidTargets.target(at: CGPoint(x: 300, y: 120), in: frames) == nil)
        #expect(LaidTargets.target(at: .zero, in: []) == nil)
    }

    @Test func theHalfOfTheGroupPicksTheEnd() {
        let f = CGRect(x: 40, y: 100, width: 80, height: 58)
        #expect(LaidTargets.side(at: CGPoint(x: 41, y: 120), of: f) == .start)
        #expect(LaidTargets.side(at: CGPoint(x: 79, y: 120), of: f) == .start)
        #expect(LaidTargets.side(at: CGPoint(x: 81, y: 120), of: f) == .end)
        #expect(LaidTargets.side(at: CGPoint(x: 20, y: 120), of: f) == .start)  // past the left edge
        #expect(LaidTargets.side(at: CGPoint(x: 140, y: 120), of: f) == .end)
    }

    // MARK: a card that fits one place

    /// The laid zone around the frames above.
    private let zone = CGRect(x: 20, y: 20, width: 300, height: 200)

    /// JD: "for sets or runs where it only fits in one place, don't need to be precise". A card
    /// only `b` takes goes to `b` from anywhere on the zone, and says it got there that way.
    @Test func aCardThatFitsOnePlaceGoesThereFromAnywhereOnTheZone() {
        let far = CGPoint(x: 280, y: 200)  // nowhere near a group
        #expect(LaidTargets.target(at: far, in: frames) == nil)
        let drop = LaidTargets.drop(at: far, in: frames, fits: [b], zone: zone)
        #expect(drop?.target == b)
        #expect(drop?.toward == .end)  // right of b's middle
        #expect(drop?.anywhere == true)
        let left = LaidTargets.drop(at: CGPoint(x: 25, y: 200), in: frames, fits: [b], zone: zone)
        #expect(left?.target == b)
        #expect(left?.toward == .start)
    }

    /// A finger on a group is that group, even one that can't take the card (it says so), and
    /// off the zone there is no drop.
    @Test func aGroupUnderTheFingerStillWinsAndOffTheZoneIsNothing() {
        let onA = LaidTargets.drop(at: CGPoint(x: 60, y: 120), in: frames, fits: [b], zone: zone)
        #expect(onA?.target == a)
        #expect(onA?.anywhere == false)
        #expect(LaidTargets.drop(at: CGPoint(x: 280, y: 260), in: frames, fits: [b], zone: zone) == nil)
    }

    /// Two places (or none) the card fits: only a group near the finger takes it.
    @Test func aCardThatFitsTwoPlacesNeedsAGroupNearTheFinger() {
        let far = CGPoint(x: 280, y: 200)
        #expect(LaidTargets.drop(at: far, in: frames, fits: [a, b], zone: zone) == nil)
        #expect(LaidTargets.drop(at: far, in: frames, fits: [], zone: zone) == nil)
        let onB = LaidTargets.drop(at: CGPoint(x: 150, y: 120), in: frames, fits: [a, b], zone: zone)
        #expect(onB?.target == b)
        #expect(onB?.anywhere == false)
    }

    /// The one group it fits, though no longer drawn (a row went away), is no drop.
    @Test func theOneGroupMustBeOnTheTable() {
        let gone = HitTarget(seat: 3, group: 0)
        #expect(LaidTargets.drop(at: CGPoint(x: 280, y: 200), in: frames, fits: [gone], zone: zone) == nil)
    }
}
