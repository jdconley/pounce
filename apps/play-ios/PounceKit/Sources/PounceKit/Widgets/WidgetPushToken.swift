import Foundation

/// The WidgetKit push token's rule (spec §11.2, §14.1): it goes to `PUT /v1/devices/me/widget-push`
/// only from a teen's or an adult's device, and only when the server doesn't already hold it for
/// this device. A kitten's token, or one whose age isn't known yet, never leaves the device: a push
/// token is online contact information.
public enum WidgetPushToken {
    /// What the server last took.
    public struct Uploaded: Codable, Equatable, Sendable {
        public var deviceId: String
        public var token: String

        public init(deviceId: String, token: String) {
            self.deviceId = deviceId
            self.token = token
        }
    }

    public static func uploads(band: AgeBand?) -> Bool { PushPolicy.registersRemote(band: band) }

    /// `deviceId` is the current credential's device, when known (a new device needs the token
    /// again); unknown means only a changed token goes up.
    public static func needsUpload(token: String?, deviceId: String?, last: Uploaded?, band: AgeBand?) -> Bool {
        guard uploads(band: band), let token, !token.isEmpty else { return false }
        guard let last else { return true }
        if last.token != token { return true }
        if let deviceId, deviceId != last.deviceId { return true }
        return false
    }
}
