import PounceKit
import UIKit

/// The person's text size setting, as the table's small words follow it (`TableTextScale`): name
/// pills, card counts and level chips grow with it as far as the fixed stage has room.
@MainActor
enum TableText {
    /// 1 at the default setting, up to `TableTextScale.most` at the largest ones.
    static var scale: CGFloat {
        #if DEBUG
        // `-text-scale 1.4` (screenshots and UI tests): as if the setting were that large.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-text-scale"), let value = args[safe: i + 1].flatMap(Double.init) {
            return TableTextScale.scale(scaledHundred: CGFloat(value) * 100)
        }
        #endif
        return TableTextScale.scale(scaledHundred: UIFontMetrics.default.scaledValue(for: 100))
    }

    /// How long a passing thing on the table (a move note, the discard's Undo) stays, given its
    /// usual `seconds`. DEBUG `-linger` (screenshots): four times as long.
    static func lingering(_ seconds: Double) -> Double {
        #if DEBUG
        if CommandLine.arguments.contains("-linger") { return seconds * 4 }
        #endif
        return seconds
    }
}
