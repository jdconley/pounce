import Foundation
import Observation

/// This phone's view of the shared streaks (spec §7–§10): the owner's pairs from
/// `GET /v1/me/streaks`, kept fresh by each `{t:"streak"}` a table socket brings, plus the
/// streaks the owner left (the ghosted cats). Other people on this phone only reach it through
/// their tables' sockets, for those tables' badges.
///
/// `enabled` is nil until the server answered, false once it said 404 (streaks off): then
/// nothing streak-shaped shows. Going offline keeps the last list.
@MainActor @Observable public final class StreakStore {
    /// The local person the list is for (the phone's owner); nothing loads without one.
    public var person: String? {
        didSet { if person != oldValue { pairs = []; left = []; others = [:] } }
    }
    public private(set) var enabled: Bool?
    public private(set) var pairs: [StreakView] = []
    public private(set) var left: [LeftPair] = []
    /// Views for other people on this phone, by person, then pair.
    private var others: [String: [String: StreakView]] = [:]

    @ObservationIgnored private let service: any StreakService
    @ObservationIgnored private var opening: Set<String> = []

    public init(service: any StreakService) {
        self.service = service
    }

    /// The pair shown first everywhere: pinned, else the longest, as the server ordered it.
    public var top: StreakView? { pairs.first }

    public func refresh() async {
        guard let person else { return }
        do {
            let list = try await service.streaks(person: person)
            guard person == self.person else { return }
            enabled = true
            pairs = list.pairs
            left = list.left
        } catch APIError.notFound {
            enabled = false
            pairs = []
            left = []
        } catch {
            // Offline or the server is down: keep what was shown.
        }
    }

    /// A socket's `{t:"streak"}`. Returns the stamp it earns at the table, if any.
    @discardableResult
    public func apply(pair: String, person: String, view: StreakView) -> StreakStamp? {
        if person == self.person {
            if let i = pairs.firstIndex(where: { $0.pair == pair }) {
                let old = pairs[i]
                var next = view
                next.pinned = old.pinned
                pairs[i] = next
                return StreakStamp.diff(old: old, new: next)
            }
            pairs.append(view)
            if enabled == nil { enabled = true }
            return StreakStamp.diff(old: nil, new: view)
        }
        let old = others[person]?[pair]
        others[person, default: [:]][pair] = view
        // First heard since launch: only a brand-new pair's first day is news, not a long streak.
        if old == nil && view.count > 1 { return nil }
        return StreakStamp.diff(old: old, new: view)
    }

    /// A person's pairs: the owner's list, or what this phone heard for someone else.
    public func views(for person: String) -> [StreakView] {
        if person == self.person { return pairs }
        return others[person].map { Array($0.values).sorted { $0.count > $1.count } } ?? []
    }

    public func pair(_ id: String) -> StreakView? { pairs.first { $0.pair == id } }

    /// Forgets everything shown (the account signed out or was deleted); the next refresh refills it.
    public func reset() {
        pairs = []
        left = []
        others = [:]
        enabled = nil
    }

    /// The first gift waiting in any pair (Home's gift box, §9.5).
    public var waitingGift: (pair: String, gift: StreakView.Gift)? {
        for view in pairs { if let gift = view.gifts.first { return (view.pair, gift) } }
        return nil
    }

    // MARK: actions (each refreshes after)

    /// Pause for 1 to 14 days (§8.3); again extends it.
    @discardableResult
    public func pause(_ pair: String, days: Int) async -> Bool {
        guard (1...14).contains(days) else { return false }
        return await act { try await $0.pause(pair: pair, days: days, person: $1) }
    }

    @discardableResult
    public func unpause(_ pair: String) async -> Bool {
        await act { try await $0.unpause(pair: pair, person: $1) }
    }

    /// Opens a gift once (a second tap while it's opening does nothing). Its item is this
    /// person's at once, before the refresh lands.
    @discardableResult
    public func openGift(_ pair: String, _ gift: String) async -> Bool {
        let key = "\(pair)/\(gift)"
        guard !opening.contains(key), let person else { return false }
        opening.insert(key)
        defer { opening.remove(key) }
        do {
            try await service.openGift(pair: pair, gift: gift, person: person)
        } catch {
            return false
        }
        if let i = pairs.firstIndex(where: { $0.pair == pair }), let g = pairs[i].gifts.first(where: { $0.id == gift }) {
            pairs[i].gifts.removeAll { $0.id == gift }
            if g.item.hasPrefix("rug-"), !pairs[i].unlocked.rugs.contains(g.item) { pairs[i].unlocked.rugs.append(g.item) }
            if g.item.hasPrefix("back-"), !pairs[i].unlocked.backs.contains(g.item) { pairs[i].unlocked.backs.append(g.item) }
        }
        await refresh()
        return true
    }

    @discardableResult
    public func pin(_ pair: String) async -> Bool {
        await act { try await $0.pin(pair: pair, person: $1) }
    }

    /// Leaves a streak for both people (§14); the leaver keeps a ghosted cat.
    @discardableResult
    public func leave(_ pair: String) async -> Bool {
        await act { try await $0.leave(pair: pair, person: $1) }
    }

    @discardableResult
    public func rejoin(_ pair: String) async -> Bool {
        await act { try await $0.rejoin(pair: pair, person: $1) }
    }

    private func act(_ call: (any StreakService, String) async throws -> Void) async -> Bool {
        guard let person else { return false }
        do {
            try await call(service, person)
        } catch {
            return false
        }
        await refresh()
        return true
    }

    // MARK: derived

    /// The card backs and rugs the owner can put on a table: the defaults, and everything unlocked
    /// with anyone (§9.4), in catalog order.
    public var unlocked: StreakView.Unlocks { unlocked(for: person.map { [$0] } ?? []) }

    /// What these people can put on a table: the server checks the unlocks of the players seated
    /// there from this phone, so the tray offers theirs, not the owner's.
    public func unlocked(for people: [String]) -> StreakView.Unlocks {
        let views = people.flatMap { views(for: $0) }
        let backs = Set(views.flatMap(\.unlocked.backs) + [StreakCatalog.defaultBack])
        let rugs = Set(views.flatMap(\.unlocked.rugs) + [StreakCatalog.defaultRug])
        return StreakView.Unlocks(
            backs: StreakCatalog.backs.filter(backs.contains), rugs: StreakCatalog.rugs.filter(rugs.contains))
    }

    /// Your turn at this table would complete today for a pair (Home's corner paw, §10.1).
    public func completesToday(code: String) -> Bool {
        pairs.contains { !$0.kept && $0.them && !$0.me && $0.myMove.contains(code) }
    }
}
