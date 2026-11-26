import Foundation

/// How fast toys fall (spec §4.2), a port of play-api's `tumble/clock.ts`, shared by every client
/// and the House Cats. Not checked by the server: a box's own device runs its own clock.
public enum TumbleClock {
    public static let startMs: Double = 1000
    public static let minMs: Double = 50
    /// 15% faster every 30 seconds.
    static let stepMs: Double = 30_000
    static let step = 0.85
    /// The Zoomies, from 2:30: 30% faster every 15 seconds.
    public static let zoomiesAt: Double = 150_000
    static let zoomiesStepMs: Double = 15_000
    static let zoomiesStep = 0.7
    /// Catnip makes toys fall 4 times as fast (§4.6).
    static let catnipFactor: Double = 4
    /// A toy that can't fall sets down this long after, reset by a move or turn up to 15 times.
    public static let setDownMs: Double = 500
    public static let setDownResets = 15

    /// Ms per row, `elapsed` ms into the round.
    public static func gravityMs(_ elapsed: Double, catnip: Bool = false) -> Double {
        let t = max(0, elapsed)
        var g = startMs * pow(step, (min(t, zoomiesAt) / stepMs).rounded(.down))
        if t >= zoomiesAt { g *= pow(zoomiesStep, 1 + ((t - zoomiesAt) / zoomiesStepMs).rounded(.down)) }
        if catnip { g /= catnipFactor }
        return max(minMs, g)
    }

    // The clients' own timings (docs/live-protocol.md, spec §4.5, §4.6), not part of clock.ts.

    /// How long junk waits in the meter, from its ack.
    public static let junkWait: Double = 2000
    /// Catnip and Nap, from the ack.
    public static let effectLength: Double = 10_000
    /// Soft drop: a row at least this often while held.
    public static let softMs: Double = 40
}
