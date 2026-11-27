import Foundation

/// xoshiro128** 1.1 with its state passed in and out, a line-for-line port of play-api's
/// `tumble/rng.ts`, so a Toy Tumble box keeps its generator in plain JSON and every engine draws
/// exactly the same numbers. The shared vectors pin it bit for bit.
public enum TumbleRng {
    @inline(__always) static func rotl(_ x: UInt32, _ k: UInt32) -> UInt32 { (x &<< k) | (x &>> (32 &- k)) }

    /// The next uint32 output and the state after it.
    public static func next(_ s: [UInt32]) -> (UInt32, [UInt32]) {
        let s0 = s[0], s1 = s[1], s2 = s[2], s3 = s[3]
        let result = rotl(s1 &* 5, 7) &* 9
        let t = s1 &<< 9
        var n2 = s2 ^ s0
        var n3 = s3 ^ s1
        let n1 = s1 ^ n2
        let n0 = s0 ^ n3
        n2 ^= t
        n3 = rotl(n3, 11)
        return (result, [n0, n1, n2, n3])
    }

    /// A uint32 output as a float in [0, 1), the same double as `u / 4294967296` in TypeScript.
    public static func float(_ u: UInt32) -> Double { Double(u) / 4_294_967_296 }

    /// Fisher-Yates from the end, as `rngShuffle`. The new order and the state after.
    public static func shuffle<T>(_ items: [T], _ s: [UInt32]) -> ([T], [UInt32]) {
        var out = items
        var state = s
        var i = out.count - 1
        while i > 0 {
            let (u, next) = next(state)
            state = next
            let j = Int((float(u) * Double(i + 1)).rounded(.down))
            out.swapAt(i, j)
            i -= 1
        }
        return (out, state)
    }
}
