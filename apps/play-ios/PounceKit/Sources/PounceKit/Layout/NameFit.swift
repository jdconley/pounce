import CoreGraphics

/// Fits a player's name on a name pill of a given width. A long name first gets smaller type,
/// never below the smallest legible size; only then is it cut, at a sensible place: a number
/// at the end stays ("House Cat 2" becomes "House 2", not "House C…"), then whole words go
/// from the end ("Mary Jane" becomes "Mary"), and only a single long word is cut with an
/// ellipsis.
public enum NameFit {
    public struct Result: Equatable, Sendable {
        public var text: String
        public var size: CGFloat
        /// The whole name shows.
        public var whole: Bool
    }

    /// The type sizes to try, largest first: from `preferred` down to `minimum` in 1 pt steps.
    public static func sizes(preferred: CGFloat, minimum: CGFloat) -> [CGFloat] {
        guard preferred > minimum else { return [preferred] }
        return Array(stride(from: preferred, to: minimum, by: -1)) + [minimum]
    }

    /// `name` at the largest of `sizes` it fits `width` at; at the smallest size, cut short.
    /// `measure` gives a string's width at a type size. A shortened name made of whole words
    /// ("House" for "House Cat") may go down to `wordFloor`, a little under the smallest size,
    /// when that saves it from losing letters.
    public static func fit(
        _ name: String, width: CGFloat, sizes: [CGFloat], wordFloor: CGFloat? = nil,
        measure: (String, CGFloat) -> CGFloat
    ) -> Result {
        let name = name.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard let smallest = sizes.last else { return Result(text: name, size: 0, whole: true) }
        for size in sizes where measure(name, size) <= width {
            return Result(text: name, size: size, whole: true)
        }
        let candidates = shortened(name)
        for candidate in candidates where measure(candidate, smallest) <= width {
            return Result(text: candidate, size: smallest, whole: false)
        }
        if let wordFloor, wordFloor < smallest {
            for size in NameFit.sizes(preferred: smallest - 1, minimum: wordFloor) {
                for candidate in candidates where measure(candidate, size) <= width {
                    return Result(text: candidate, size: size, whole: false)
                }
            }
        }
        // One word too long for the pill: as many letters as fit, then an ellipsis.
        var cut = String(name.split(separator: " ").first ?? Substring(name))
        while !cut.isEmpty {
            cut.removeLast()
            if measure(cut + "…", smallest) <= width { return Result(text: cut + "…", size: smallest, whole: false) }
        }
        return Result(text: "…", size: smallest, whole: false)
    }

    /// Shorter forms of a name of several words, best first.
    static func shortened(_ name: String) -> [String] {
        let words = name.split(separator: " ").map(String.init)
        guard words.count > 1 else { return [] }
        var out: [String] = []
        // "House Cat 2": the number tells two cats apart, so it outlives the middle words.
        if let last = words.last, last.allSatisfy(\.isNumber) {
            for keep in stride(from: words.count - 2, through: 1, by: -1) {
                out.append((words.prefix(keep) + [last]).joined(separator: " "))
            }
        }
        // "Mary Jane Smith": "Mary Jane S.", "Mary Jane", "Mary J.", "Mary".
        for keep in stride(from: words.count - 1, through: 1, by: -1) {
            if let initial = words[keep].first, initial.isLetter {
                out.append(words.prefix(keep).joined(separator: " ") + " \(initial).")
            }
            out.append(words.prefix(keep).joined(separator: " "))
        }
        return out
    }
}

/// How much the table's small words (name pills, card counts, level chips) grow with the
/// person's text size setting. The table is a fixed stage, so the growth is capped by the room
/// each seat has in the top bar.
public enum TableTextScale {
    /// The most the table's words grow, however large the setting.
    public static let most: CGFloat = 1.4

    /// The scale for a text size setting that makes a 100 pt body `scaled` points tall.
    public static func scale(scaledHundred scaled: CGFloat) -> CGFloat {
        min(max(scaled / 100, 1), most)
    }

    /// A name pill's type size: 16 pt at the default setting, growing with it.
    public static func nameSize(scale: CGFloat) -> CGFloat { (16 * min(max(scale, 1), most)).rounded() }

    /// The smallest a name gets before it is cut short.
    public static let nameFloor: CGFloat = 16

    /// The smallest a shortened name of whole words gets, to keep its last letters.
    public static let wordFloor: CGFloat = 14

    /// The scale for a cat's card count and level chip, which share the ring's bottom edge:
    /// they grow only as far as the cat's own slot allows with the widest chip ("10") in it
    /// (`spacing` between cat centers, `diameter` of a ring), and never shrink.
    public static func chips(scale: CGFloat, spacing: CGFloat, diameter: CGFloat) -> CGFloat {
        guard diameter > 0 else { return 1 }
        let k = diameter / 72
        // The widest chip is about 2.3 of its height; the count's mini card 20 pt at full size.
        let need = 2.3 * max(22 * k, 20) + 20 * max(k, 0.8) + 3
        return min(max(scale, 1), max((spacing - 2) / need, 1), most)
    }
}
