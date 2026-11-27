#if DEBUG
import MachO
import OSLog
import QuartzCore
import SpriteKit
import UIKit

/// DEBUG launch argument `-watchdog` (every UI test passes it, through `Live.arguments()`): counts
/// what keeps the main thread from drawing (`docs/main-thread.md`).
///
/// - **Frames**: a display link at the screen's top rate notes every gap between two of its
///   ticks. A gap over 1.5 times the display's frame time is a dropped frame, and one over
///   16.7 ms (plus 2 ms of display clock jitter) is slow on any screen. The table's own rendered
///   frames (its `SKView`, while it runs) are counted the same way, from `AnimationDirector.frame`.
/// - **Hangs**: run loop observers time every stretch the main thread works without going back to
///   sleep; one over 100 ms is a hang, and is logged on stdout and in the unified log
///   (`[watchdog] hang …`, category `watchdog`).
/// - **Thread Performance Checker**: whether Xcode loaded it into the app (`tpc=1`).
///
/// A UI test's own queries (each one snapshots the app's accessibility tree on the main thread)
/// stall the app too. A gap or stretch during which the tree was read is counted apart (`ax`), so
/// the test's polling doesn't count against the app.
///
/// "Gameplay" is while a table is on screen, from a second after it appeared: only those frames
/// and hangs are counted, so launch and the way in don't. The UI tests read the counts from the
/// `watchdog` element (`summary`), a 1-point view at the back of the app's window, so it can be
/// read on any screen.
@MainActor
final class MainThreadWatchdog {
    static private(set) var shared: MainThreadWatchdog?
    private static let log = Logger(subsystem: "com.conleychaos.play", category: "watchdog")

    /// A stretch of main-thread work this long is a hang.
    static let hangSeconds: CFTimeInterval = 0.1
    /// A frame longer than this is slow on any screen: 60 Hz's frame time, 16.7 ms, plus 2 ms
    /// for the display clock's jitter (a 60 Hz frame is often 16.8).
    nonisolated static let slowFrameMs = 1000.0 / 60 + 2
    /// Gameplay counts from this long after a table appears (its entrance and the shell's
    /// transition to it don't).
    static let settleSeconds: CFTimeInterval = 1
    /// A table frame gap this long is the view resuming (the app came back), not a frame.
    static let resumeMs = 1000.0

    static func startIfAsked(arguments: [String] = CommandLine.arguments) {
        guard shared == nil, arguments.contains("-watchdog") else { return }
        let dog = MainThreadWatchdog()
        shared = dog
        dog.start()
    }

    /// Frame gaps: counts, the worst, and a histogram in 0.5 ms buckets (the last bucket holds
    /// everything from 50 ms up), so a test can take percentiles over a window by subtracting.
    struct Frames {
        static let bucketMs = 0.5
        static let buckets = 100

        var count = 0
        /// Over 1.5 times the frame time.
        var overBudget = 0
        /// Over 16.7 ms (`slowFrameMs`).
        var slow = 0
        var worstMs = 0.0
        var histogram = [Int](repeating: 0, count: buckets + 1)
        /// Gaps that held a read of the accessibility tree (a UI test's query): not counted above.
        var queried = 0
        /// The frame time the last gap was judged against.
        var frameMs = 0.0

        mutating func add(_ ms: Double, frameMs: Double, queried isQuery: Bool) {
            self.frameMs = frameMs
            if isQuery {
                queried += 1
                return
            }
            count += 1
            if ms > frameMs * 1.5 { overBudget += 1 }
            if ms > MainThreadWatchdog.slowFrameMs { slow += 1 }
            worstMs = max(worstMs, ms)
            histogram[min(Int(ms / Self.bucketMs), Self.buckets)] += 1
        }

        /// `n=<frames> frame=<ms> over=<n> slow=<n> max=<ms> ax=<n> h=<bucket>:<n>,…`
        var summary: String {
            let h = histogram.enumerated().filter { $0.element > 0 }.map { "\($0.offset):\($0.element)" }.joined(separator: ",")
            return String(format: "n=%d frame=%.2f over=%d slow=%d max=%.1f ax=%d h=%@", count, frameMs, overBudget, slow, worstMs, queried, h)
        }
    }

    /// The main thread's frames (the display link), and the table's rendered frames.
    private(set) var link = Frames()
    private(set) var table = Frames()
    private(set) var hangs = 0
    private(set) var worstHangMs = 0.0
    /// Hangs during which the accessibility tree was read, and all hangs outside gameplay: only
    /// logged and counted here, never gated.
    private(set) var otherHangs = 0
    private(set) var worstOtherHangMs = 0.0
    /// Thread Performance Checker is loaded into this process (Xcode's diagnostic, `libRPAC`).
    let checkerLoaded: Bool

    /// The table on screen (its `SKView`), and when it appeared.
    private weak var tableView: SKView?
    private var tableSince: CFTimeInterval?
    /// A SwiftUI play screen with no table (the Daily Dish, a daily puzzle): when it came up.
    private var screenSince: CFTimeInterval?

    /// Why a test's touch or a gate's frames went missing: table views that came on screen
    /// (`views`, one per table unless SwiftUI rehosted it), times a table's view left its window
    /// (`offs`), times the app left the foreground (`inactive`), and the touches the app's windows
    /// were handed (`wtouch`: began, moved, ended, cancelled), whatever view they went on to.
    private(set) var views = 0
    private(set) var offs = 0
    private(set) var inactive = 0
    fileprivate(set) var windowTouches = (began: 0, moved: 0, ended: 0, cancelled: 0)
    /// The latest touch's view and the gesture recognizers it was handed to (`wgr`): each one's
    /// class, its state now and whether it holds the view's touch-ends until it decides. A touch
    /// the window saw end but the table didn't was held or taken by one of these.
    fileprivate weak var lastTouchView: UIView?
    fileprivate var lastTouchRecognizers: [WeakRecognizer] = []
    fileprivate struct WeakRecognizer { weak var value: UIGestureRecognizer? }
    private var activeObserver: NSObjectProtocol?

    private let probe = Probe(id: "watchdog") { MainThreadWatchdog.shared?.summary() }
    private let framesProbe = Probe(id: "watchdog.frames") { MainThreadWatchdog.shared?.recentFrames() }
    private var windowObserver: NSObjectProtocol?
    private var sceneObserver: NSObjectProtocol?
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private var observers: [CFRunLoopObserver] = []
    /// When the main thread last woke or passed a run loop step, nil while it sleeps.
    private var lastStep: CFTimeInterval?
    /// Since the last display link tick: the main thread's busy time, and its longest stretch of
    /// work without sleeping. A slow frame with little busy time wasn't the main thread's doing.
    private var busySinceTick = 0.0
    private var stretchSinceTick = 0.0
    private var stretch = 0.0
    /// Slow frames, each with the main thread's share: printed as `[frame] slow …`.
    private(set) var slowFrames: [String] = []
    /// The last `[frame]` lines (slow frames and frames over the work budget), with when, for a
    /// test to print (`watchdog.frames`): on a phone the unified log is out of reach.
    private var recentLines: [String] = []

    private func remember(_ line: String) {
        recentLines.append(String(format: "t=%.2f ", CACurrentMediaTime()) + line)
        if recentLines.count > 40 { recentLines.removeFirst(recentLines.count - 40) }
    }

    /// `recentLines`, one per line (the `watchdog.frames` element's value).
    func recentFrames() -> String {
        noteQuery()
        return recentLines.joined(separator: "\n")
    }
    private static let logsSummary = CommandLine.arguments.contains("-watchdog-log")

    /// How long this machine's main thread takes for a fixed piece of frame-like work (median of
    /// 9, in CPU time, measured once before any table): Swift collections, SpriteKit node changes
    /// and a small texture with a numeral drawn. A test divides it by the reference Mac's to get
    /// the machine's speed factor, and scales its time budgets by it (a CI virtual machine is
    /// several times slower per thread than the Mac the budgets were set on).
    private(set) var speedMs = 0.0

    /// The fixed work, its CPU time in ms.
    private static func benchOnce() -> Double {
        let start = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID))
        // Collections, as a redraw's bookkeeping.
        var groups: [Int: [Int]] = [:]
        for i in 0..<3000 { groups[i % 97, default: []].append((i * 7919) % 1013) }
        var seen = Set<Int>()
        for (_, values) in groups { for v in values.sorted() where v % 3 == 0 { seen.insert(v) } }
        // Node changes, as a redraw's settling.
        let parent = SKNode()
        for i in 0..<120 {
            let node = SKSpriteNode(color: .white, size: CGSize(width: 30, height: 36))
            node.position = CGPoint(x: i % 12 * 31, y: i / 12 * 37)
            node.zPosition = CGFloat(i % 7)
            node.setScale(seen.contains(i) ? 1.1 : 1)
            parent.addChild(node)
        }
        parent.removeAllChildren()
        // A small texture with a numeral, as a piece face.
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 2
        _ = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 43), format: format).image { _ in
            UIColor.orange.setFill()
            UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: 34, height: 41), cornerRadius: 8).fill()
            ("13" as NSString).draw(at: CGPoint(x: 6, y: 4), withAttributes: [.font: UIFont.systemFont(ofSize: 20, weight: .black)])
        }
        return (Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) - start) / 1e6
    }

    private func measureSpeed() {
        _ = Self.benchOnce()  // warm: the first run pays one-time setup
        let runs = (0..<9).map { _ in Self.benchOnce() }.sorted()
        speedMs = runs[runs.count / 2]
    }
    private var lastSummary: CFTimeInterval = 0
    /// `FrameWork` pieces since the last tick that took a millisecond or more (for the log), and
    /// the outermost pieces' total: the app's own main-thread work in this frame.
    private var workSinceTick: [(name: String, ms: Double)] = []
    private var frameWorkSinceTick = 0.0
    /// The most app work (`FrameWork`, outermost pieces) in any one gameplay frame, and how many
    /// frames went over the 120 Hz budget, 8.3 ms.
    private(set) var worstFrameWorkMs = 0.0
    private(set) var framesOverWorkBudget = 0
    nonisolated static let workBudgetMs = 1000.0 / 120

    /// The longest accessibility rebuild (`FrameWork(read: true)`) in gameplay: VoiceOver waits
    /// for it, and so does a UI test's query.
    private(set) var worstReadWorkMs = 0.0

    /// One piece of the table's main-thread work (`FrameWork`) took `ms`.
    func noteWork(_ name: StaticString, ms: Double, outermost: Bool, read: Bool) {
        guard inGameplay else { return }
        if read {
            worstReadWorkMs = max(worstReadWorkMs, ms)
        } else if outermost {
            frameWorkSinceTick += ms
            workSinceStep += ms
        }
        if ms >= 0.5 { workSinceTick.append(("\(name)", ms)) }
    }

    /// Accessibility reads so far, and the count when each clock last ticked: a change means
    /// the gap held one.
    private var queries = 0
    private var queriesAtTick = 0
    private var queriesAtStep = 0
    private var queriesAtTableFrame = 0
    private var lastTableFrame: TimeInterval?

    private init() {
        checkerLoaded = (0..<_dyld_image_count()).contains { i in
            _dyld_get_image_name(i).map { String(cString: $0).hasSuffix("/libRPAC.dylib") } ?? false
        }
    }

    // MARK: what the tables tell it

    /// A table's view went on screen (`window != nil`) or off it.
    func watch(_ view: SKView) {
        if view.window != nil {
            if tableView !== view {
                tableSince = CACurrentMediaTime()
                views += 1
            }
            tableView = view
            // The table's screen is known now (at launch there may be none yet, and the link
            // fell back to 60): judge the main thread's frames at that screen's top rate.
            matchScreenRate(view.window)
        } else if tableView === view {
            tableView = nil
            tableSince = nil
            offs += 1
        }
        lastTableFrame = nil
    }

    /// A SwiftUI play screen with no table came up or went (`.frameGate()`): its frames and
    /// hangs count as gameplay, as a table's do.
    func screen(_ on: Bool) {
        screenSince = on ? CACurrentMediaTime() : nil
    }

    /// Gameplay: a table, or a SwiftUI play screen, is on screen and has been for `settleSeconds`.
    private var inGameplay: Bool {
        if let since = screenSince, CACurrentMediaTime() - since >= Self.settleSeconds { return true }
        guard tableView?.window != nil, let since = tableSince else { return false }
        return CACurrentMediaTime() - since >= Self.settleSeconds
    }

    /// The table rendered a frame at `time` (its scene's `update` time). `resumed`: the view was
    /// paused since its last frame, so there is no gap to measure.
    func tableFrame(_ time: TimeInterval, resumed: Bool) {
        defer {
            lastTableFrame = time
            queriesAtTableFrame = queries
        }
        guard !resumed, let last = lastTableFrame, inGameplay, let view = tableView else { return }
        let ms = (time - last) * 1000
        guard ms > 0, ms < Self.resumeMs else { return }
        let rate = max(min(view.preferredFramesPerSecond, Self.screenRate(view.window)), 1)
        table.add(ms, frameMs: 1000 / Double(rate), queried: queries != queriesAtTableFrame)
    }

    /// The accessibility tree is being read (a UI test's query, or VoiceOver).
    func noteQuery() {
        queries += 1
        lastQueryAt = CACurrentMediaTime()
    }

    /// When the accessibility tree was last read, and how long after that a frame's work is
    /// counted apart.
    private var lastQueryAt: CFTimeInterval = 0
    static let readGraceSeconds: CFTimeInterval = 0.25
    /// The most app work in a frame that held, or came just after, a read of the screen.
    private(set) var worstReadFrameWorkMs = 0.0
    /// The app's own work (outermost `FrameWork` pieces) since the last run loop step: how much of
    /// a hang was the app's.
    private var workSinceStep = 0.0
    /// Gameplay hangs the app's own work filled at least half of.
    private(set) var appHangs = 0
    private(set) var worstAppHangMs = 0.0
    /// The app's work in each gameplay frame (not near a screen read), in 0.5 ms buckets (the
    /// last, 100, holds 50 ms and up): percentiles over a window, on a machine too noisy to
    /// judge by its single worst frame.
    private(set) var workHistogram = [Int](repeating: 0, count: Frames.buckets + 1)

    // MARK: the probe

    /// What the `watchdog` element reads, and what `FrameRateTests` parses:
    /// `screen=<fps> table=<fps> tpc=<0|1> hangs=<n> hangmax=<ms> other=<n> othermax=<ms>
    /// | link <frames> | table <frames>`.
    func summary() -> String {
        noteQuery()
        let screen = Self.screenRate(tableView?.window)
        let rate = tableView?.preferredFramesPerSecond ?? 0
        let head = String(
            format: "screen=%d table=%d tpc=%d hangs=%d hangmax=%.1f other=%d othermax=%.1f work=%.1f workover=%d readwork=%.1f readframe=%.1f speed=%.3f",
            screen, rate, checkerLoaded ? 1 : 0, hangs, worstHangMs, otherHangs, worstOtherHangMs, worstFrameWorkMs,
            framesOverWorkBudget, worstReadWorkMs, worstReadFrameWorkMs, speedMs)
            + String(format: " apphangs=%d apphangmax=%.1f workh=%@", appHangs, worstAppHangMs,
                     workHistogram.enumerated().filter { $0.element > 0 }.map { "\($0.offset):\($0.element)" }.joined(separator: ","))
        let t = windowTouches
        let seen = String(format: " views=%d offs=%d inactive=%d wtouch=%d,%d,%d,%d",
                          views, offs, inactive, t.began, t.moved, t.ended, t.cancelled)
        let held = lastTouchRecognizers.compactMap(\.value).map { g in
            "\(Self.short(g))/\(Self.name(g.state))/\(g.delaysTouchesEnded ? 1 : 0)\(g.view === lastTouchView ? "" : "^")"
        }
        let viewName = lastTouchView.map { "\(Self.short($0))\($0.window == nil ? "/off" : "")" } ?? "-"
        let grs = " wview=\(viewName) wgr=\(held.isEmpty ? "-" : held.joined(separator: ","))"
        return "\(head)\(seen)\(grs) | link \(link.summary) | table \(table.summary)"
    }

    /// A class name without generic arguments, so it holds no spaces or commas.
    private static func short(_ object: AnyObject) -> String {
        String(String(describing: type(of: object)).prefix { $0 != "<" && $0 != " " && $0 != "," })
    }

    private static func name(_ state: UIGestureRecognizer.State) -> String {
        switch state {
        case .possible: "possible"
        case .began: "began"
        case .changed: "changed"
        case .ended: "ended"
        case .cancelled: "cancelled"
        case .failed: "failed"
        @unknown default: "other"
        }
    }

    static func screenRate(_ window: UIWindow?) -> Int { UIScreen.topFrameRate(for: window) }

    // MARK: clocks

    private func start() {
        windowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { MainThreadWatchdog.shared?.attachProbe() }
        }
        let target = Ticker()
        target.tick = { [weak self] link in self?.tick(link) }
        let link = CADisplayLink(target: target, selector: #selector(Ticker.fire(_:)))
        let top = Float(Self.screenRate(nil))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: top, maximum: top, preferred: top)
        link.add(to: .main, forMode: .common)
        displayLink = link
        // A window's screen, once there is one.
        sceneObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { MainThreadWatchdog.shared?.matchScreenRate(nil) }
        }

        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { MainThreadWatchdog.shared?.inactive += 1 }
        }

        // The thread wakes (first in line), and finishes each step (last in line, so a step's
        // Core Animation commit and SwiftUI layout count with it) or goes to sleep.
        let woke = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { _, _ in
            MainActor.assumeIsolated { MainThreadWatchdog.shared?.step(sleeping: false, woke: true) }
        }
        let steps: CFRunLoopActivity = [.entry, .beforeTimers, .beforeSources, .beforeWaiting, .exit]
        let stepped = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, steps.rawValue, true, CFIndex.max) { _, activity in
            MainActor.assumeIsolated { MainThreadWatchdog.shared?.step(sleeping: activity == .beforeWaiting, woke: false) }
        }
        for observer in [woke, stepped].compactMap({ $0 }) {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            observers.append(observer)
        }
        measureSpeed()
        let on = "[watchdog] on: screen \(Self.screenRate(nil)) fps, thread performance checker \(checkerLoaded ? "loaded" : "not loaded"), speed \(String(format: "%.3f", speedMs)) ms"
        print(on)
        Self.log.notice("\(on, privacy: .public)")
    }

    /// Asks the display link for the screen's top rate (120 on ProMotion), so a frame is judged
    /// against that screen's frame time.
    private func matchScreenRate(_ window: UIWindow?) {
        guard let link = displayLink else { return }
        let top = Float(Self.screenRate(window))
        guard link.preferredFrameRateRange.maximum != top else { return }
        link.preferredFrameRateRange = CAFrameRateRange(minimum: top, maximum: top, preferred: top)
        lastTick = nil
    }

    private func tick(_ link: CADisplayLink) {
        defer {
            lastTick = link.timestamp
            queriesAtTick = queries
        }
        let busy = busySinceTick, longest = max(stretchSinceTick, stretch)
        let work = workSinceTick, frameWork = frameWorkSinceTick
        busySinceTick = 0
        stretchSinceTick = 0
        workSinceTick = []
        frameWorkSinceTick = 0
        guard let last = lastTick, inGameplay else { return }
        let frameMs = max(link.targetTimestamp - link.timestamp, 0.001) * 1000
        let gap = (link.timestamp - last) * 1000
        let queried = queries != queriesAtTick
        self.link.add(gap, frameMs: frameMs, queried: queried)
        // A frame that held a read of the accessibility tree (a UI test's query, VoiceOver), or
        // came just after one, is counted apart: the accessibility runtime the reader loads runs
        // inside the app's own work then, and inflates it.
        let nearRead = queried || link.timestamp - lastQueryAt < Self.readGraceSeconds
        if nearRead {
            worstReadFrameWorkMs = max(worstReadFrameWorkMs, frameWork)
        } else {
            worstFrameWorkMs = max(worstFrameWorkMs, frameWork)
            workHistogram[min(Int(frameWork / Frames.bucketMs), Frames.buckets)] += 1
            if frameWork > Self.workBudgetMs { framesOverWorkBudget += 1 }
        }
        if frameWork > Self.workBudgetMs {
            let pieces = work.sorted { $0.ms > $1.ms }.prefix(9).map { String(format: "%@ %.1f", $0.name, $0.ms) }.joined(separator: ", ")
            let line = String(
                format: "[frame] work %.1f ms over the 8.3 ms budget (frame %.1f ms%@): %@",
                frameWork, gap, nearRead ? ", near a screen read: not counted" : "", pieces)
            remember(line)
            print(line)
            Self.log.notice("\(line, privacy: .public)")
        }
        // `-watchdog-log`: the summary in the log every 10 s, for runs no UI test reads.
        if Self.logsSummary, link.timestamp - lastSummary >= 10 {
            lastSummary = link.timestamp
            let line = "[watchdog] summary " + summary()
            print(line)
            Self.log.notice("\(line, privacy: .public)")
        }
        if gap > Self.slowFrameMs, !queried {
            let pieces = work.sorted { $0.ms > $1.ms }.prefix(4).map { String(format: "%@ %.1f", $0.name, $0.ms) }.joined(separator: ", ")
            let line = String(
                format: "[frame] slow %.1f ms: main thread busy %.1f ms, longest stretch %.1f ms; app work %.1f ms: %@",
                gap, busy, longest, frameWork, pieces.isEmpty ? "none" : pieces)
            slowFrames.append(line)
            remember(line)
            print(line)
            Self.log.notice("\(line, privacy: .public)")
        }
    }

    /// A run loop step: times the work since the last one, unless the thread was asleep.
    private func step(sleeping: Bool, woke: Bool) {
        let now = CACurrentMediaTime()
        if !woke, let last = lastStep {
            let ms = (now - last) * 1000
            busySinceTick += ms
            stretch += ms
            if ms > Self.hangSeconds * 1000 { hang(ms, queried: queries != queriesAtStep, appWork: workSinceStep) }
        }
        workSinceStep = 0
        if sleeping {
            stretchSinceTick = max(stretchSinceTick, stretch)
            stretch = 0
        }
        lastStep = sleeping ? nil : now
        queriesAtStep = queries
    }

    private func hang(_ ms: Double, queried: Bool, appWork: Double) {
        let gameplay = inGameplay
        if gameplay, !queried {
            hangs += 1
            worstHangMs = max(worstHangMs, ms)
            // The app's own: its timed work fills at least half the stretch.
            if appWork >= ms / 2 {
                appHangs += 1
                worstAppHangMs = max(worstAppHangMs, ms)
            }
        } else {
            otherHangs += 1
            worstOtherHangMs = max(worstOtherHangMs, ms)
        }
        let why = queried ? ", during an accessibility read" : gameplay ? "" : ", outside gameplay"
        let line = String(format: "[watchdog] hang %.0f ms on the main thread%@ (app work %.1f ms)", ms, why, appWork)
        print(line)
        // Also in the unified log, where a UI test's app output can be read back
        // (`xcrun simctl spawn <device> log show --predicate 'category == "watchdog"'`).
        Self.log.notice("\(line, privacy: .public)")
    }

    /// A window just showed: the probe goes at the back of the app's own window (not an overlay
    /// or a system one), if it isn't on one already.
    private func attachProbe() {
        guard probe.window == nil || probe.window?.isHidden == true else { return }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: { $0.windowLevel == .normal && !$0.isHidden }) else { return }
        window.insertSubview(probe, at: 0)
        window.insertSubview(framesProbe, at: 0)
        if window.gestureRecognizers?.contains(where: { $0 is TouchCensus }) != true {
            window.addGestureRecognizer(TouchCensus())
        }
    }

    /// Counts the touches a window is handed (`wtouch`), whichever view they go to, without
    /// claiming, delaying or cancelling any.
    private final class TouchCensus: UIGestureRecognizer, UIGestureRecognizerDelegate {
        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let watchdog = MainThreadWatchdog.shared else { return }
            watchdog.windowTouches.began += touches.count
            if let touch = touches.first {
                watchdog.lastTouchView = touch.view
                watchdog.lastTouchRecognizers = (touch.gestureRecognizers ?? [])
                    .filter { $0 !== self }.map { WeakRecognizer(value: $0) }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            MainThreadWatchdog.shared?.windowTouches.moved += touches.count
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            MainThreadWatchdog.shared?.windowTouches.ended += touches.count
            if numberOfTouches <= touches.count { state = .failed }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            MainThreadWatchdog.shared?.windowTouches.cancelled += touches.count
            if numberOfTouches <= touches.count { state = .failed }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    /// The `watchdog` and `watchdog.frames` elements: draw nothing, take no touches, read
    /// their value live.
    private final class Probe: UIView {
        private let read: @MainActor () -> String?

        init(id: String, read: @escaping @MainActor () -> String?) {
            self.read = read
            super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            isUserInteractionEnabled = false
            backgroundColor = .clear
            isAccessibilityElement = true
            accessibilityIdentifier = id
            accessibilityLabel = id
            accessibilityTraits = .staticText
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override var accessibilityValue: String? {
            get { read() }
            set {}
        }
    }

    /// The display link's target (the link runs on the main run loop).
    @MainActor
    private final class Ticker: NSObject {
        var tick: (@MainActor (CADisplayLink) -> Void)?

        @objc func fire(_ link: CADisplayLink) { tick?(link) }
    }
}
#endif
