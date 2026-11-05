/// The game over screen's Play again pill (§10.4). Any seated phone may ask once the room is over;
/// the server deals once and tells everyone in the old room the new code. The phone that asked
/// goes there by itself; any other phone's pill becomes a jump to the same table.
public struct PlayAgain: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Send `{t:"rematch"}`.
        case send
        /// Open this table.
        case jump(String)
        case none
    }

    /// This phone asked and no answer came yet.
    public private(set) var waiting = false

    public init() {}

    /// Shown only on a finished table of a server with looks (streaks on), which is also the one
    /// that takes `rematch`.
    public static func available(_ room: RoomView?) -> Bool {
        guard let room else { return false }
        return room.status == .over && room.look != nil
    }

    public mutating func tap(room: RoomView?, rematch: String?) -> Action {
        if let code = rematch ?? room?.rematch { return .jump(code) }
        guard Self.available(room), !waiting else { return .none }
        waiting = true
        return .send
    }

    /// The server dealt `code`: where this phone goes now, if it asked.
    public mutating func arrived(code: String) -> String? {
        defer { waiting = false }
        return waiting ? code : nil
    }

    /// The server refused (an error came back): the pill can be tapped again.
    public mutating func refused() {
        waiting = false
    }
}

/// The table menu's look tray (§9.4): the rugs and card backs this person may put on the table,
/// the defaults always, then everything they unlocked with anyone, in catalog order.
public enum LookTray {
    public struct Item: Equatable, Identifiable, Sendable {
        public var id: String
        public var selected: Bool
    }

    public static func rugs(unlocked: StreakView.Unlocks, current: Look?) -> [Item] {
        items(StreakCatalog.rugs, owned: Set(unlocked.rugs + [StreakCatalog.defaultRug]), current: current?.rug)
    }

    public static func backs(unlocked: StreakView.Unlocks, current: Look?) -> [Item] {
        items(StreakCatalog.backs, owned: Set(unlocked.backs + [StreakCatalog.defaultBack]), current: current?.back)
    }

    private static func items(_ catalog: [String], owned: Set<String>, current: String?) -> [Item] {
        catalog.filter(owned.contains).map { Item(id: $0, selected: $0 == current) }
    }
}
