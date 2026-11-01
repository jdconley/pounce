import Foundation

/// The pure rules behind push notifications (spec §7.5, §10).
public enum PushPolicy {
    /// Ask for push the first time this phone is in a started game with a human seat on
    /// another phone, since only then can a turn come round while it is away. Bots answer
    /// on their own and a game held entirely by this phone never waits on anyone else.
    public static func shouldPrime(model: TableModel, primed: Bool) -> Bool {
        guard !primed, model.room.status == .playing, !model.mySeats.isEmpty else { return false }
        return model.room.seats.contains { $0.kind == .human && !$0.yours }
    }

    /// How long after going to the background mid-turn the local "your turn" reminder fires;
    /// nil when no seat of this phone is playing. The server only pushes when a turn starts.
    public static func reminderDelay(model: TableModel) -> Duration? {
        model.isMyTurn ? .seconds(600) : nil
    }

    /// The APNs device token as the lowercase hex the server stores.
    public static func hexToken(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// The room code a notification is about: the top-level `code` the server sends,
    /// only when it is a well-formed room code.
    public static func code(fromPayload userInfo: [AnyHashable: Any]) -> String? {
        guard let code = userInfo["code"] as? String, RoomCode.isValid(code) else { return nil }
        return code
    }
}
