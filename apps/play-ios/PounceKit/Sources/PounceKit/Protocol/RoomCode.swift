/// Room codes (5 characters) and move codes (6 characters) share one alphabet:
/// consonants and digits with no vowels, `0 1 5`, `I`, `O`, `S` or `Y`, so a
/// code never spells a word and is hard to misread aloud.
public enum RoomCode {
    public static let alphabet = "BCDFGHJKLMNPQRTVWXZ2346789"

    private static let roomLength = 5
    private static let moveLength = 6

    public static func isValid(_ s: String) -> Bool { matches(s, length: roomLength) }

    public static func isValidMoveCode(_ s: String) -> Bool { matches(s, length: moveLength) }

    private static func matches(_ s: String, length: Int) -> Bool {
        s.utf8.count == length && s.allSatisfy { alphabet.contains($0) }
    }
}
