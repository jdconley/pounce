import Foundation

/// A box as text, for the shared vectors and tests (play-api `tumble/codec.ts`): one string per
/// row, top row (y 21) first. Cells are `.`, `1` to `9` for the toy (its index + 1) and `#` for
/// junk; tricks are `.` or `a` to `h` in `TumbleTrick` order.
public enum TumbleText {
    public struct Rows: Equatable, Sendable {
        public var cells: [String]
        public var tricks: [String]
    }

    public enum Failure: Error { case unknownTrick }

    public static func of(_ box: TumbleBox) -> Rows {
        var cells: [String] = []
        var tricks: [String] = []
        var y = Tumble.total - 1
        while y >= 0 {
            var c = ""
            var t = ""
            for x in 0..<Tumble.width {
                let v = box.cell(x, y)
                c.append(v == 0 ? "." : v == Tumble.junk ? "#" : Character(String(v)))
                let k = box.trick(x, y)
                t.append(k == 0 ? "." : Character(UnicodeScalar(UInt8(96 + k))))
            }
            cells.append(c)
            tricks.append(t)
            y -= 1
        }
        return Rows(cells: cells, tricks: tricks)
    }

    /// The reverse of `of`. Shorter lists are the bottom rows (the last string is y 0); missing rows are empty.
    public static func box(cells cellRows: [String], tricks trickRows: [String] = [], trickSeed: [UInt32] = [0, 0, 0, 0]) throws -> TumbleBox {
        var box = TumbleBox(trickSeed: trickSeed)
        for (i, row) in cellRows.enumerated() {
            let y = cellRows.count - 1 - i
            let chars = Array(row)
            for x in 0..<Tumble.width {
                let ch = x < chars.count ? chars[x] : "."
                box.cells[y * Tumble.width + x] = ch == "." ? 0 : ch == "#" ? Tumble.junk : Int(String(ch)) ?? 0
            }
        }
        for (i, row) in trickRows.enumerated() {
            let y = trickRows.count - 1 - i
            let chars = Array(row)
            for x in 0..<Tumble.width {
                let ch = x < chars.count ? chars[x] : "."
                let v = ch == "." ? 0 : Int(ch.asciiValue ?? 96) - 96
                if v > TumbleTrick.allCases.count { throw Failure.unknownTrick }
                box.tricks[y * Tumble.width + x] = v
            }
        }
        return box
    }
}
