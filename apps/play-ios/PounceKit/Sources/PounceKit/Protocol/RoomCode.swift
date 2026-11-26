/// Room codes (5 characters) and move codes (6 characters) share one alphabet:
/// consonants and digits with no vowels, `0 1 5`, `I`, `O`, `S` or `Y`, so a
/// code never spells a word and is hard to misread aloud.
public enum RoomCode {
    public static let alphabet = "BCDFGHJKLMNPQRTVWXZ2346789"

    private static let roomLength = 5
    private static let moveLength = 6

    /// A room code's length.
    public static let length = roomLength
    /// A Purrtrait TV's typed code: the room code and the first 2 characters of its key.
    public static let easelLength = roomLength + 2

    public static func isValid(_ s: String) -> Bool { matches(s, length: roomLength) }

    /// A Purrtrait TV's 7-character typed code.
    public static func isValidEasel(_ s: String) -> Bool { matches(s, length: easelLength) }

    /// A Purrtrait TV's join key (8 characters from the same alphabet).
    public static func isValidNearKey(_ s: String) -> Bool { matches(s, length: 8) }

    public static func isValidMoveCode(_ s: String) -> Bool { matches(s, length: moveLength) }

    private static func matches(_ s: String, length: Int) -> Bool {
        s.utf8.count == length && s.allSatisfy { alphabet.contains($0) }
    }
}
