import XCTest

/// The app's DEBUG `MainThreadWatchdog`, read from the tables' `watchdog` element (every test app
/// runs with `-watchdog`, through `Live.arguments()`):
/// `screen=<fps> table=<fps> tpc=<0|1> hangs=<n> hangmax=<ms> other=<n> othermax=<ms> work=<ms>
/// workover=<n> readwork=<ms> readframe=<ms> | link <frames> | table <frames>`, each `<frames>` being
/// `n=<count> frame=<ms> over=<n> slow=<n> max=<ms> ax=<n> h=<bucket>:<count>,…`.
///
/// Counts are cumulative over gameplay (a table on screen for over a second), so a window is one
/// reading minus an earlier one (`-`). Frames and hangs that held a read of the accessibility tree
/// (a test's own query) are counted apart and never gated.
struct Watchdog {
    struct Frames {
        /// Gaps counted, and the frame time they were judged against (ms).
        var count = 0
        var frameMs = 0.0
        /// Over 1.5 times the frame time, and over 16.7 ms (plus 2 ms of display clock jitter).
        var over = 0
        var slow = 0
        var maxMs = 0.0
        /// Gaps that held an accessibility read (not counted in the rest).
        var queried = 0
        /// 0.5 ms buckets; the last (100) holds 50 ms and up.
        var histogram: [Int: Int] = [:]

        static let bucketMs = 0.5

        init() {}

        init(_ text: Substring) {
            for part in text.split(separator: " ") {
                let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { continue }
                switch pair[0] {
                case "n": count = Int(pair[1]) ?? 0
                case "frame": frameMs = Double(pair[1]) ?? 0
                case "over": over = Int(pair[1]) ?? 0
                case "slow": slow = Int(pair[1]) ?? 0
                case "max": maxMs = Double(pair[1]) ?? 0
                case "ax": queried = Int(pair[1]) ?? 0
                case "h":
                    for entry in pair[1].split(separator: ",") {
                        let kv = entry.split(separator: ":").compactMap { Int($0) }
                        if kv.count == 2 { histogram[kv[0]] = kv[1] }
                    }
                default: break
                }
            }
        }

        /// This window minus an earlier reading. The worst gap comes from the histogram's top
        /// bucket (its upper edge), unless nothing changed.
        static func - (a: Frames, b: Frames) -> Frames {
            var out = Frames()
            out.count = a.count - b.count
            out.frameMs = a.frameMs
            out.over = a.over - b.over
            out.slow = a.slow - b.slow
            out.queried = a.queried - b.queried
            for (bucket, n) in a.histogram {
                let left = n - (b.histogram[bucket] ?? 0)
                if left > 0 { out.histogram[bucket] = left }
            }
            out.maxMs = out.histogram.keys.max().map { min(Double($0 + 1) * bucketMs, a.maxMs) } ?? 0
            return out
        }

        /// The gap at fraction `p` (0.5 is the median), as its bucket's middle, in ms.
        func percentile(_ p: Double) -> Double {
            let total = histogram.values.reduce(0, +)
            guard total > 0 else { return 0 }
            let rank = Int((Double(total) * p).rounded(.up))
            var seen = 0
            for bucket in histogram.keys.sorted() {
                seen += histogram[bucket] ?? 0
                if seen >= max(rank, 1) { return (Double(bucket) + 0.5) * Self.bucketMs }
            }
            return maxMs
        }

        /// Frames a second at the median gap.
        var fps: Double {
            let median = percentile(0.5)
            return median > 0 ? 1000 / median : 0
        }

        var line: String {
            String(format: "n=%d fps=%.0f p50=%.2fms p95=%.2fms max=%.1fms over1.5x=%d over16.7ms=%d ax=%d",
                   count, fps, percentile(0.5), percentile(0.95), maxMs, over, slow, queried)
        }
    }

    var screen = 0
    var table = 0
    var checkerLoaded = false
    var hangs = 0
    var hangMaxMs = 0.0
    var otherHangs = 0
    var otherMaxMs = 0.0
    /// The most app work (the app's `FrameWork` pieces) in one gameplay frame so far, and the
    /// frames whose app work went over the 120 Hz budget, 8.3 ms.
    var workMaxMs = 0.0
    var workOver = 0
    /// The longest accessibility rebuild (what VoiceOver and a test's query wait for).
    var readWorkMs = 0.0
    /// The most app work in a frame that held, or came just after, a read of the screen (not
    /// gated: the reader's accessibility runtime runs inside it).
    var readFrameWorkMs = 0.0
    static let workBudgetMs = 1000.0 / 120
    /// The app's fixed benchmark on this machine (`MainThreadWatchdog.speedMs`), and the same on
    /// the reference: an iPhone 17 Pro simulator on the M-series Mac the budgets were set on.
    var speedMs = 0.0
    static let referenceSpeedMs = 0.29

    /// How many times slower than the reference this machine's main thread is (1 at least: a
    /// faster phone keeps the reference's budgets). Time budgets scale by it; raw numbers are
    /// reported beside the result.
    var slowdown: Double { speedMs > 0 ? max(1, speedMs / Self.referenceSpeedMs) : 1 }
    /// The app's work budget for one frame on this machine.
    var workBudgetMs: Double { Self.workBudgetMs * slowdown }
    /// Up to this much slower than the reference, a machine is judged as the reference is (a
    /// phone, the Mac the budgets were set on); beyond it (a CI virtual machine, whose host steals
    /// time that the guest counts as its own) by percentiles, with a cap on the worst frame.
    static let nearReference = 1.25
    var nearReference: Bool { slowdown <= Self.nearReference }

    /// Gameplay hangs the app's own work filled at least half of, and the worst of them.
    var appHangs = 0
    var appHangMaxMs = 0.0
    /// The app's work per frame, in 0.5 ms buckets.
    var workHistogram: [Int: Int] = [:]

    /// The app's work per frame at fraction `p`, as its bucket's top, in ms.
    func workPercentile(_ p: Double) -> Double {
        let total = workHistogram.values.reduce(0, +)
        guard total > 0 else { return 0 }
        let rank = max(Int((Double(total) * p).rounded(.up)), 1)
        var seen = 0
        for bucket in workHistogram.keys.sorted() {
            seen += workHistogram[bucket] ?? 0
            if seen >= rank { return Double(bucket + 1) * Frames.bucketMs }
        }
        return workMaxMs
    }

    /// Why the app's time budgets fail on this machine, or nothing (see `nearReference`).
    ///
    /// Near the reference's speed (a phone, the Mac the budgets were set on): no frame over 8.3 ms
    /// of the app's own work, and no hang over 100 ms that the app's work filled.
    ///
    /// On a slower machine (a CI virtual machine, whose host steals time that the guest counts as
    /// its own, so that single frames of 100 to 160 ms land inside the app's work at random): the
    /// app's work at p95 within 8.3 ms times the slowdown and at p99 within three times that, which
    /// catches a regression in many frames; and no hang over 250 ms times the slowdown that the
    /// app's work filled, which catches a single long block. A single slow frame under that is
    /// left to a phone or the reference Mac (`scripts/frame-rate.sh`).
    func timeFailures() -> [String] {
        var out: [String] = []
        let f = slowdown
        let hangLimit = nearReference ? 100 : 250 * f
        if appHangs > 0, appHangMaxMs > hangLimit {
            out.append(String(format: "the app's own work hung the main thread (%d, worst %.0f ms, budget %.0f ms)", appHangs, appHangMaxMs, hangLimit))
        }
        if nearReference {
            if workMaxMs > Self.workBudgetMs {
                out.append(String(format: "a frame held %.1f ms of the app's own work, over 8.3 ms", workMaxMs))
            }
        } else {
            let p95 = workPercentile(0.95), p99 = workPercentile(0.99)
            if p95 > workBudgetMs {
                out.append(String(format: "the app's work per frame at p95 was %.1f ms, over %.1f ms (8.3 ms at the reference's speed)", p95, workBudgetMs))
            }
            if p99 > 3 * workBudgetMs {
                out.append(String(format: "the app's work per frame at p99 was %.1f ms, over %.1f ms (three frames at the reference's speed)", p99, 3 * workBudgetMs))
            }
        }
        return out
    }

    var link = Frames()
    var tableFrames = Frames()

    init?(_ value: String?) {
        guard let value, value != "off" else { return nil }
        let sections = value.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard sections.count == 3 else { return nil }
        for part in sections[0].split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            switch pair[0] {
            case "screen": screen = Int(pair[1]) ?? 0
            case "table": table = Int(pair[1]) ?? 0
            case "tpc": checkerLoaded = pair[1] == "1"
            case "hangs": hangs = Int(pair[1]) ?? 0
            case "hangmax": hangMaxMs = Double(pair[1]) ?? 0
            case "other": otherHangs = Int(pair[1]) ?? 0
            case "othermax": otherMaxMs = Double(pair[1]) ?? 0
            case "work": workMaxMs = Double(pair[1]) ?? 0
            case "workover": workOver = Int(pair[1]) ?? 0
            case "readwork": readWorkMs = Double(pair[1]) ?? 0
            case "readframe": readFrameWorkMs = Double(pair[1]) ?? 0
            case "speed": speedMs = Double(pair[1]) ?? 0
            case "apphangs": appHangs = Int(pair[1]) ?? 0
            case "apphangmax": appHangMaxMs = Double(pair[1]) ?? 0
            case "workh":
                for entry in pair[1].split(separator: ",") {
                    let kv = entry.split(separator: ":").compactMap { Int($0) }
                    if kv.count == 2 { workHistogram[kv[0]] = kv[1] }
                }
            default: break
            }
        }
        guard sections[1].hasPrefix("link "), sections[2].hasPrefix("table ") else { return nil }
        link = Frames(sections[1].dropFirst(5))
        tableFrames = Frames(sections[2].dropFirst(6))
    }

    private init() {}

    /// This window minus an earlier reading.
    static func - (a: Watchdog, b: Watchdog) -> Watchdog {
        var out = Watchdog()
        out.screen = a.screen
        out.table = a.table
        out.checkerLoaded = a.checkerLoaded
        out.hangs = a.hangs - b.hangs
        out.hangMaxMs = out.hangs > 0 ? a.hangMaxMs : 0
        out.otherHangs = a.otherHangs - b.otherHangs
        out.otherMaxMs = out.otherHangs > 0 ? a.otherMaxMs : 0
        // The worst frame's work is over all of gameplay (a maximum doesn't subtract).
        out.workMaxMs = a.workMaxMs
        out.workOver = a.workOver - b.workOver
        out.readWorkMs = a.readWorkMs
        out.readFrameWorkMs = a.readFrameWorkMs
        out.speedMs = a.speedMs
        out.appHangs = a.appHangs - b.appHangs
        out.appHangMaxMs = out.appHangs > 0 ? a.appHangMaxMs : 0
        for (bucket, n) in a.workHistogram {
            let left = n - (b.workHistogram[bucket] ?? 0)
            if left > 0 { out.workHistogram[bucket] = left }
        }
        out.link = a.link - b.link
        out.tableFrames = a.tableFrames - b.tableFrames
        return out
    }

    /// The `FRAMES` line the frame-rate tests print.
    func report(_ name: String) -> String {
        String(format: "FRAMES %@ screen=%dfps table=%dfps tpc=%d | table %@ | main %@ | app work worst %.1fms, over 8.3ms=%d, accessibility rebuild worst %.1fms, near a screen read worst %.1fms | hangs=%d (worst %.0fms) ax-or-outside-hangs=%d | speed %.2fms, %.2fx the reference | app work p95 %.1fms p99 %.1fms, app hangs %d (worst %.0fms)",
               name, screen, table, checkerLoaded ? 1 : 0, tableFrames.line, link.line, workMaxMs, workOver, readWorkMs, readFrameWorkMs, hangs, hangMaxMs, otherHangs, speedMs, slowdown,
               workPercentile(0.95), workPercentile(0.99), appHangs, appHangMaxMs)
    }
}

@MainActor
extension XCTestCase {
    /// The app's watchdog now, or nil when no table is on screen (or the app runs without it).
    func watchdog(_ app: XCUIApplication) -> Watchdog? {
        Watchdog(value(el(app, "watchdog")))
    }

    /// Waits for the table's watchdog to report gameplay frames (the table has been up for its
    /// settle second) and returns that reading, to subtract from a later one.
    func gameplayBaseline(_ app: XCUIApplication, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> Watchdog {
        XCTAssertTrue(el(app, "watchdog").waitForExistence(timeout: Live.t(timeout)), "no watchdog on the table (-watchdog)", file: file, line: line)
        var reading: Watchdog?
        // The settle second, then a frame or two counted.
        _ = until(timeout) {
            reading = self.watchdog(app)
            return (reading?.link.count ?? 0) + (reading?.link.queried ?? 0) > 0
        }
        guard let reading else {
            XCTFail("the watchdog reads \(value(el(app, "watchdog")) ?? "nothing")", file: file, line: line)
            return Watchdog("screen=0 table=0 | link n=0 | table n=0")!
        }
        return reading
    }
}

/// The machine the app runs on: the Mac under a simulator (which shares its kernel), or the phone.
enum Host {
    /// Over this many runnable threads per core (the 1-minute load average), a simulator's own
    /// frames are held up by the rest of the Mac: frame times are reported, not enforced. The
    /// app's work per frame is CPU time and is always enforced, and so is everything on a phone.
    static let busyLoadPerCore = 0.5

    /// The frame-time check can't be trusted here: a simulator on a Mac over `busyLoadPerCore`.
    /// Never on a phone, whose own load average says nothing about its frames (a ProMotion phone
    /// reads 0.75 to 1.3 per core while it holds 121 fps).
    static func framesUnreliable() -> (busy: Bool, load: Double) {
        #if targetEnvironment(simulator)
        let load = loadPerCore()
        return (load > busyLoadPerCore, load)
        #else
        return (false, loadPerCore())
        #endif
    }

    static func loadPerCore() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) > 0 else { return 0 }
        return loads[0] / Double(cores())
    }

    /// The machine's CPUs (`hw.ncpu`): in a simulator `ProcessInfo.activeProcessorCount` can say 1.
    static func cores() -> Int {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.ncpu", &count, &size, nil, 0) == 0, count > 0 else {
            return max(ProcessInfo.processInfo.activeProcessorCount, 1)
        }
        return Int(count)
    }
}
