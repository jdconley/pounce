import CryptoKit
import Foundation

/// Sign in with Apple's nonce (spec §4.6): a fresh random one per request. Apple gets its
/// SHA-256 as lowercase hex and puts that in the identity token; the server gets the raw one,
/// hashes it and compares, so a token can't be replayed with another request.
public enum Nonce {
    public static func raw() -> String { PersonKeys.random() }

    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
