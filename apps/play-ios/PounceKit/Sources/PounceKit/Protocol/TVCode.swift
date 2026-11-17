import Foundation

/// What "Show on TV" reads (docs/tv-protocol.md, TV links): a TV's QR, or its backup code typed
/// on the phone.
public enum TVCode {
    /// A TV's backup code has six characters from the room-code alphabet.
    public static let length = 6

    /// The token in a scanned QR's text, when the text is exactly a TV's link
    /// (`https://play.conleychaos.com/tv/<22 base64url chars>`); nil for anything else, so the
    /// scanner keeps looking. `DeepLink.parse` is the one parser; the debug scheme never counts here.
    public static func token(scanned text: String) -> String? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              case .tv(let token)? = DeepLink.parse(url, allowDevScheme: false)
        else { return nil }
        return token
    }

    /// A whole backup code from typed text, or nil: upper case, spaces and dashes dropped, then
    /// exactly six characters from the alphabet.
    public static func normalized(_ text: String) -> String? {
        let code = text.uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "\u{2010}" && $0 != "\u{2013}" }
        return RoomCode.isValidMoveCode(code) ? code : nil
    }
}

/// The camera permission as Show on TV sees it (AVFoundation's, without importing it here).
public enum CameraPermission: Sendable {
    case authorized, denied, restricted, notDetermined
}

/// What Show on TV shows first: the camera, the code entry, or the system's camera question
/// before deciding.
public enum TVSheetStart: Equatable, Sendable {
    case scan
    case type
    case askForCamera

    /// `supported`: the device has the QR scanner at all. `available`: it may run now. The camera
    /// is asked for only when the sheet's button opened it (`askForCamera`), never for a TV link
    /// opened on the phone. Anything but a camera that may be used gets the code entry.
    public static func first(supported: Bool, available: Bool, permission: CameraPermission, askForCamera: Bool) -> TVSheetStart {
        guard supported else { return .type }
        switch permission {
        case .authorized: return available ? .scan : .type
        case .notDetermined: return askForCamera ? .askForCamera : .type
        case .denied, .restricted: return .type
        }
    }

    /// After the system's question: the camera only if it was allowed and the scanner can run.
    public static func afterAsking(allowed: Bool, available: Bool) -> TVSheetStart {
        allowed && available ? .scan : .type
    }
}
