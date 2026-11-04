import Testing
@testable import PounceKit

@Suite struct TableNameTests {
    @Test func cleanTrimsAndCollapsesWhitespace() {
        #expect(TableName.clean("  Friday   Night\u{00A0}Cats ") == "Friday Night Cats")
        #expect(TableName.clean("Taco Night") == "Taco Night")
    }

    @Test func cleanRefusesEmptyLongAndControlCharacters() {
        for raw in ["", "   ", String(repeating: "x", count: 31), "a\tb", "two\nlines", "a\u{0}b", "a\u{2028}b",
                    "a\u{202E}b", "a\u{2066}b"] {
            #expect(TableName.clean(raw) == nil, "\(raw.debugDescription)")
        }
    }

    @Test func lengthCountsCodePointsLikeTheServer() {
        // Each cat face is one code point (two UTF-16 units): 30 of them fit.
        let cats = String(repeating: "\u{1F431}", count: 30)
        #expect(TableName.clean(cats) == cats)
        #expect(TableName.clean(cats + "\u{1F431}") == nil)
    }

    @Test func clampCutsWholeCharactersToTheLimit() {
        #expect(TableName.clamp(String(repeating: "x", count: 40)).count == 30)
        // "e" plus a combining accent is one Character of two code points: never split.
        let accented = TableName.clamp(String(repeating: "e\u{301}", count: 20))
        #expect(accented.unicodeScalars.count == 30)
        #expect(accented.count == 15)
        #expect(TableName.clamp("Short") == "Short")
    }

    @Test func randomNamesAreValidNames() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let name = TableName.random(using: &rng)
            #expect(name.hasPrefix("The "))
            #expect(TableName.clean(name) == name)
        }
    }

    @Test func fallbackNamesTheCode() {
        #expect(TableName.fallback(code: "BCDFG") == "Table BCDFG")
    }
}
