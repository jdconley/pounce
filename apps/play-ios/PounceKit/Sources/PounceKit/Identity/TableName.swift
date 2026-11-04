/// A table's name, as everyone at it sees it. The server names every table (a cat-themed
/// default until someone renames it) and checks every rename the same way `clean` does.
public enum TableName {
    /// The server's limit, in Unicode code points.
    public static let maxLength = 30

    /// `raw` as the server would store it: trimmed, runs of whitespace collapsed to one space.
    /// Nil when nothing is left, it is too long, or it has a control, separator or bidi character.
    public static func clean(_ raw: String) -> String? {
        guard !raw.unicodeScalars.contains(where: isForbidden) else { return nil }
        let name = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !name.isEmpty, name.unicodeScalars.count <= maxLength else { return nil }
        return name
    }

    /// `raw` cut to `maxLength` code points without splitting a character, for a text field.
    public static func clamp(_ raw: String) -> String {
        var clipped = raw
        while clipped.unicodeScalars.count > maxLength { clipped.removeLast() }
        return clipped
    }

    /// The words the server's default names are made of (play-api `room/names.ts`).
    static let adjectives = [
        "Sleepy", "Sneaky", "Fuzzy", "Zoomy", "Grumpy", "Fancy",
        "Chonky", "Velvet", "Midnight", "Sunny", "Wobbly", "Purring",
    ]
    static let nouns = [
        "Sardines", "Whiskers", "Mittens", "Yarn Club", "Box Fort", "Sunbeams",
        "Tuna Heist", "Catnip Lounge", "Laser Dots", "Hairballs", "Scratch Post", "Nap Squad",
    ]

    /// A name like the server's defaults ("The Sleepy Sardines"), for the rename sheet's dice.
    public static func random<G: RandomNumberGenerator>(using g: inout G) -> String {
        "The \(adjectives.randomElement(using: &g) ?? "Sleepy") \(nouns.randomElement(using: &g) ?? "Sardines")"
    }

    /// What to call a table whose name this phone doesn't know yet (an older server, or a
    /// Home entry from before tables had names).
    public static func fallback(code: String) -> String { "Table \(code)" }

    private static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.generalCategory == .control { return true }
        switch scalar.value {
        case 0x2028, 0x2029, 0x202A...0x202E, 0x2066...0x2069: return true
        default: return false
        }
    }
}
