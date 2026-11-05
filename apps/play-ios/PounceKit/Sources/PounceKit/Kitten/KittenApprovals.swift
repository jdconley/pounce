import Foundation

/// Mirroring Apple's Communication Limits answers to the server (consent design D3; plan
/// decision 22). The app asks PermissionKit for each partner once, reads `knownHandles(in:)` for
/// all of them, and sends the known set when it changed. Without Communication Limits it sends
/// `null` once, so the parent's own toggles count again. Handles are pair ids.
public enum KittenApprovals {
    /// The body of `PUT /v1/kittens/me/approved`: Apple's list, or nil for "not Apple's call".
    public struct Mirror: Equatable, Codable, Sendable {
        public var apple: [String]?

        public init(apple: [String]?) {
            self.apple = apple
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(apple, forKey: .apple)
        }

        private enum CodingKeys: String, CodingKey { case apple }
    }

    public struct Plan: Equatable, Sendable {
        /// Partners to ask PermissionKit about (new, not known, not asked before).
        public var ask: [String]
        /// What to send, when it differs from what the server last took.
        public var send: Mirror?
    }

    /// - Parameters:
    ///   - limits: Declared Age Range reports Communication Limits on this device.
    ///   - partners: the kitten's pair ids.
    ///   - known: the handles Apple says are approved.
    ///   - asked: the handles already asked about on this device.
    ///   - last: what the server last took from this device (nil: never sent).
    public static func plan(limits: Bool, partners: [String], known: Set<String>, asked: Set<String>, last: Mirror?) -> Plan {
        guard limits else {
            // Only once, and only if this device ever sent Apple's list.
            let send: Mirror? = last?.apple != nil ? Mirror(apple: nil) : nil
            return Plan(ask: [], send: send)
        }
        let ask = partners.filter { !known.contains($0) && !asked.contains($0) }
        let mirror = Mirror(apple: partners.filter(known.contains).sorted())
        return Plan(ask: ask, send: mirror == last ? nil : mirror)
    }
}
