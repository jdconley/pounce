import Foundation

/// JSON text <-> protocol messages.
public enum Codec {
    /// A snapshot is read as `t` and `protocol` first: any protocol but 1 becomes
    /// `.unsupportedProtocol` without decoding the room.
    public static func decode(_ text: String) throws -> ServerMessage {
        try JSONDecoder().decode(ServerMessage.self, from: Data(text.utf8))
    }

    public static func encode(_ message: ClientMessage) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(message), as: UTF8.self)
    }
}
