import Foundation

/// How this phone's own connection to the room looks while the socket is up.
public enum LinkQuality: Equatable, Sendable {
    case good
    /// Round trips are slow (over `LinkMeter.Config.weakAfter`), or a heartbeat is that late.
    case weak
}

/// What `LinkMeter.tick` says about the connection.
public enum LinkVerdict: Equatable, Sendable {
    case alive
    /// Nothing at all has come back for `deadAfter`: drop the socket and connect again.
    case dead
}

/// The connection-quality state machine behind the bad connection indicator, one per socket.
///
/// The socket sends one heartbeat at a time, `pingEvery` apart (a ping is never sent while
/// another is out). The link turns `weak` as soon as a pong takes `weakAfter` or longer, or the
/// outstanding one has been out that long; it is `good` again after `goodPongs` pongs in a row
/// under `goodUnder` (a pong between the two thresholds keeps whatever it was). With a ping out
/// for `deadAfter` and no frame heard in that time either, the connection is `dead`: iOS can
/// take a minute or more to notice a socket that cellular has quietly lost, so the socket
/// reconnects instead of waiting.
///
/// Times are durations since any fixed origin (the socket passes its clock's).
public struct LinkMeter: Sendable {
    public struct Config: Equatable, Sendable {
        public var pingEvery: Duration
        public var weakAfter: Duration
        public var goodUnder: Duration
        public var goodPongs: Int
        public var deadAfter: Duration

        public init(
            pingEvery: Duration = .seconds(3), weakAfter: Duration = .milliseconds(1500),
            goodUnder: Duration = .seconds(1), goodPongs: Int = 2, deadAfter: Duration = .seconds(10)
        ) {
            self.pingEvery = pingEvery
            self.weakAfter = weakAfter
            self.goodUnder = goodUnder
            self.goodPongs = goodPongs
            self.deadAfter = deadAfter
        }
    }

    public var config: Config
    public private(set) var quality: LinkQuality = .good
    /// The last pong's round trip.
    public private(set) var lastRoundTrip: Duration?
    private var outstanding: Duration?
    private var lastPing: Duration?
    private var lastHeard: Duration
    private var fastPongs = 0

    /// A fresh connection, open at `now`: good until shown otherwise.
    public init(config: Config = Config(), now: Duration) {
        self.config = config
        lastHeard = now
    }

    /// No ping out, and `pingEvery` since the last one (or none sent yet).
    public func shouldPing(now: Duration) -> Bool {
        guard outstanding == nil else { return false }
        guard let lastPing else { return true }
        return now - lastPing >= config.pingEvery
    }

    public mutating func pingSent(now: Duration) {
        outstanding = now
        lastPing = now
    }

    /// The outstanding ping's pong arrived; a pong with none out (a late duplicate) changes nothing.
    public mutating func pong(now: Duration) {
        lastHeard = max(lastHeard, now)
        guard let sent = outstanding else { return }
        outstanding = nil
        let trip = now - sent
        lastRoundTrip = trip
        if trip >= config.weakAfter {
            quality = .weak
            fastPongs = 0
        } else if trip < config.goodUnder {
            fastPongs += 1
            if fastPongs >= config.goodPongs { quality = .good }
        } else {
            fastPongs = 0
        }
    }

    /// Any frame from the room: the connection is alive, though that says nothing of its speed.
    public mutating func heard(now: Duration) {
        lastHeard = max(lastHeard, now)
    }

    /// Checks the outstanding ping against the clock.
    public mutating func tick(now: Duration) -> LinkVerdict {
        guard let sent = outstanding else { return .alive }
        if now - sent >= config.weakAfter {
            quality = .weak
            fastPongs = 0
        }
        if now - sent >= config.deadAfter, now - lastHeard >= config.deadAfter { return .dead }
        return .alive
    }
}
