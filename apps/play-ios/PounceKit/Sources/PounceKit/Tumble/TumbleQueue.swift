import Foundation

/// A round's toy queue (spec §4.1), a port of play-api's `tumble/queue.ts`. Every box in a round
/// gets the same queue. Bags of 8 are dealt in order from one generator that starts at the round
/// seed: the seven small toys shuffled with one 5-cell toy, `p5` and `u5` bag by bag.
public struct TumbleQueue: Sendable, Equatable {
    static let small: [TumbleToy] = [.i3, .v3, .i4, .o4, .t4, .l4, .j4]
    public static let bag = 8

    public let roundSeed: [UInt32]
    private var bags: [[TumbleToy]] = []
    private var state: [UInt32]

    public init(roundSeed: [UInt32]) {
        self.roundSeed = roundSeed
        state = roundSeed
    }

    /// Toy `n`, dealing bags as needed and keeping them.
    public mutating func toy(_ n: Int) -> TumbleToy {
        let b = n / Self.bag
        while bags.count <= b {
            let (order, next) = TumbleRng.shuffle(Self.small + [bags.count % 2 == 0 ? .p5 : .u5], state)
            bags.append(order)
            state = next
        }
        return bags[b][n % Self.bag]
    }

    /// Toy `n` of the round with this seed, dealt fresh (a few microseconds for any real round).
    public static func toyAt(_ roundSeed: [UInt32], _ n: Int) -> TumbleToy {
        var q = TumbleQueue(roundSeed: roundSeed)
        return q.toy(n)
    }
}
