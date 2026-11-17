import Foundation

/// What a TV must never hear (docs/tv-protocol.md, "A screen"): a hand, a rack, a seat of its own,
/// the host's place, or the card or tile drawn from the deck. `pounce-e2e screen` checks every
/// message its TV hears with it, as raw JSON, so a key the app's decoder would skip still counts.
public enum ScreenPrivacy {
    /// What is private in one message's text, or nil. Text that isn't a JSON object is nil.
    public static func leak(inJSON text: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return nil }
        return leak(in: object)
    }

    public static func leak(in message: [String: Any]) -> String? {
        if message["t"] as? String == "snapshot", let room = message["room"] as? [String: Any] {
            if holds((room["game"] as? [String: Any])?["hands"]) { return "hands" }
            if holds((room["tiles"] as? [String: Any])?["racks"]) { return "racks" }
            if (room["seats"] as? [[String: Any]] ?? []).contains(where: { $0["yours"] as? Bool == true }) { return "a seat" }
            if room["youAreHost"] as? Bool == true { return "the host" }
        }
        if message["t"] as? String == "event", let outer = message["event"] as? [String: Any],
           let event = outer["event"] as? [String: Any], event["kind"] as? String == "drew" {
            if outer["kind"] as? String == "game", event["from"] as? String != "discard", event["card"] != nil { return "a drawn card" }
            if outer["kind"] as? String == "tiles", event["tile"] != nil { return "a drawn tile" }
        }
        return nil
    }

    /// Present and not empty, whatever its shape (an object by seat, or a list).
    private static func holds(_ value: Any?) -> Bool {
        switch value {
        case nil, is NSNull: false
        case let object as [String: Any]: !object.isEmpty
        case let list as [Any]: !list.isEmpty
        default: true
        }
    }
}
