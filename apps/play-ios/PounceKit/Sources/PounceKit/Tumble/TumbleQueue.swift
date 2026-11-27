import Foundation

/// A round's toy queue (spec §4.1), a port of play-api's `tumble/queue.ts`. Every box in a round
/// gets the same queue. Bags are dealt in order from one generator that starts at the round seed:
/// the seven small toys every bag, and a 5-cell toy every other bag (the paw print in bags 0, 4,
/// 8..., the food bowl in bags 2, 6...), so bags run 8, 7, 8, 7.
public struct TumbleQueue: Sendable, Equatable {
    static let small: [TumbleToy] = [.i3, .v3, .i4, .o4, .t4, .l4, .j4]
    /// Toys in a pair of bags: one with a 5-cell toy, one without.
    public static let pair = 15

    public let roundSeed: [UInt32]
    private var bags: [[TumbleToy]] = []
    private var state: [UInt32]

    public init(roundSeed: [UInt32]) {
        self.roundSeed = roundSeed
        state = roundSeed
    }

    /// Toy `n`, dealing bags as needed and keeping them.
    public mutating func toy(_ n: Int) -> TumbleToy {
        let p = n / Self.pair
        let i = n % Self.pair
        let first = i < Self.small.count + 1
        let bag = p * 2 + (first ? 0 : 1)
        while bags.count <= bag {
            let b = bags.count
            let five: [TumbleToy] = b % 2 == 1 ? [] : [b % 4 == 0 ? .p5 : .u5]
            let (order, next) = TumbleRng.shuffle(Self.small + five, state)
            bags.append(order)
            state = next
        }
        return bags[bag][first ? i : i - (Self.small.count + 1)]
    }

    /// Toy `n` of the round with this seed, dealt fresh (a few microseconds for any real round).
    public static func toyAt(_ roundSeed: [UInt32], _ n: Int) -> TumbleToy {
        var q = TumbleQueue(roundSeed: roundSeed)
        return q.toy(n)
    }
}
