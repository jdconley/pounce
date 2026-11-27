import Foundation

/// One Toy Tumble table on this device: the room's rounds (`room.tumble`), this device's own box
/// (`TumbleLocal`) and every other box (`TumbleReplay`), fed by the room's snapshots and the live
/// stream, and stepped by the scene each frame. A screen (the TV) has no own box and replays all.
///
/// Sockets and JSON stay in `RoomSocket`, off the main thread; this only holds memory and runs
/// the engine's small steps.
@MainActor public final class TumbleTable {
    public private(set) var room: RoomView?
    public private(set) var view: TumbleView?
    public private(set) var local: TumbleLocal?
    public private(set) var replay: TumbleReplay?
    /// This device's seat at the table (a device holds at most one), nil for a screen or a watcher.
    public private(set) var mySeat: Int?
    private let send: (ClientMessage) -> Void
    private let screen: Bool
    private var backgrounded = false
    /// The server's clock minus this device's, from the last snapshot's `now` (0 without one).
    public private(set) var clockOffset: Double = 0

    /// The round's start on this device's clock.
    public var startsAt: Double? { view?.startsAt.map { $0 - clockOffset } }

    /// A server time (`waitingSince`, `startsAt`) on this device's clock.
    public func local(_ serverTime: Double) -> Double { serverTime - clockOffset }

    /// `send` hands a message to the room's socket (in order, off the main thread).
    public init(screen: Bool = false, send: @escaping (ClientMessage) -> Void) {
        self.screen = screen
        self.send = send
    }

    public var r: Int? { view?.r }

    /// The device's wall clock in ms, the clock every Toy Tumble time here is on.
    public nonisolated static func now() -> Double { Date().timeIntervalSince1970 * 1000 }

    /// The seats at the table, in order.
    public var seatCount: Int { view?.seats ?? room?.seats.count ?? 0 }

    public var isPlaying: Bool { view?.status == .playing || view?.status == .countdown }

    /// A new snapshot: a new round (or a first look at one) makes fresh boxes from its seeds.
    public func update(room: RoomView, now: Double) {
        self.room = room
        guard room.isTumble, let next = room.tumble else {
            view = nil
            local = nil
            replay = nil
            return
        }
        if let serverNow = next.now { clockOffset = serverNow - now }
        let mine = screen ? nil : room.seats.indices.first { room.seats[$0].yours }
        let fresh = next.r != view?.r || mine != mySeat || replay == nil
        view = next
        mySeat = mine
        let live = next.status == .countdown || next.status == .playing
        // Between rounds and at the end the last boxes stay up, still.
        guard live, let roundSeed = next.roundSeed, let seeds = next.trickSeeds, let serverStart = next.startsAt else { return }
        let startsAt = serverStart - clockOffset
        guard fresh else { return }
        let r = next.r
        replay = TumbleReplay(r: r, roundSeed: roundSeed, trickSeeds: seeds, skip: mine)
        if let mine, seeds.indices.contains(mine), next.inRound(mine) {
            let send = self.send
            local = TumbleLocal(r: r, seat: mine, roundSeed: roundSeed, trickSeed: seeds[mine], startsAt: startsAt) { ev in
                send(.tumble(r: r, ev: ev))
            }
            if backgrounded { local?.suspend() }
            // Joining a round already playing (a relaunch): ask for the truth first.
            if next.status == .playing, now > startsAt + 1000 {
                local?.suspend()
                local?.resume(now)
            }
        } else {
            local = nil
        }
    }

    /// The live stream, already decoded.
    public func receive(_ message: TumbleMessage, now: Double) {
        guard message.round == view?.r else { return }
        switch message {
        case .hit(let h) where h.to == mySeat:
            local?.hit(h, now: now)
            replay?.apply(message, now: now)
        case .sync(let sync):
            if let mine = mySeat, let own = sync.boxes.first(where: { $0.s == mine }) { local?.sync(own, now: now) }
            replay?.apply(message, now: now)
        default:
            replay?.apply(message, now: now)
        }
        if replay?.takeSyncRequest() == true, let r = view?.r { send(.tumble(r: r, ev: [])) }
    }

    /// The frame: the own box steps; nothing else needs the clock.
    public func step(now: Double) {
        guard isPlaying, let local, local.r == view?.r else { return }
        local.step(now)
    }

    /// The app went to the background: the socket drops, and there is no pause.
    public func suspend() {
        backgrounded = true
        local?.suspend()
    }

    /// Back: ask for a sync of every box before the own box steps again.
    public func resume(now: Double) {
        backgrounded = false
        if let local {
            local.resume(now)
        } else if let r = view?.r, isPlaying, !screen {
            send(.tumble(r: r, ev: []))
        }
    }

    /// A new connection's first snapshot: a box still waiting for its sync asks for it again.
    public func reconnected(now: Double) {
        guard !backgrounded, let local, local.awaitingSync else { return }
        local.resume(now)
    }

    /// The box a seat shows: its own device's, or the replayed copy.
    public func box(_ seat: Int) -> TumbleBox? {
        if seat == mySeat, let local { return local.box }
        return replay?.box(seat)
    }

    public func isOut(_ seat: Int) -> Bool {
        if let view, view.outs.contains(seat) { return true }
        return box(seat)?.out ?? false
    }

    public func lagging(_ seat: Int) -> Bool { replay?.seats[seat]?.status == .lag }
}
