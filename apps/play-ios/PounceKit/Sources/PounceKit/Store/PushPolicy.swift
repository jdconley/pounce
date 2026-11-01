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
        model.isMyTurn ? reminderInterval : nil
    }

    /// The local reminder's delay: 10 minutes.
    public static let reminderInterval: Duration = .seconds(600)

    private static let reminderPrefix = "turn-reminder-"

    /// The local turn reminder's request identifier for a room.
    public static func reminderID(code: String) -> String { reminderPrefix + code }

    /// A local turn reminder's identifier (for any room). Every one is removed on each
    /// foreground, including ones scheduled before the app was terminated and relaunched.
    public static func isReminderID(_ identifier: String) -> Bool {
        identifier.hasPrefix(reminderPrefix)
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

/// What the server holds of this phone's APNs token. The token goes up every time APNs hands
/// it over (each launch), and again whenever the device credential changes: a re-mint after a
/// 401 makes a new device on the server, which has no token until this phone sends it.
public struct PushTokenState: Equatable, Sendable {
    /// The last token APNs gave this launch.
    public private(set) var token: String?
    /// The device the server stored `token` for, once an upload succeeded.
    private var uploadedFor: String?
    /// The device credential's id as last reported by the API client.
    private var device: String?

    public init() {}

    /// The token to upload now, if the server doesn't hold it for the current device.
    public var pending: String? {
        guard let token else { return nil }
        guard let uploadedFor else { return token }
        if let device, device != uploadedFor { return token }
        return nil
    }

    public mutating func received(_ token: String) {
        self.token = token
        uploadedFor = nil
    }

    /// An upload of `token` succeeded under `deviceId` (ignored for an older token).
    public mutating func uploaded(_ token: String, deviceId: String) {
        guard token == self.token else { return }
        uploadedFor = deviceId
    }

    /// The API client minted a credential (first launch or a re-mint).
    public mutating func deviceChanged(_ deviceId: String) {
        device = deviceId
    }
}
