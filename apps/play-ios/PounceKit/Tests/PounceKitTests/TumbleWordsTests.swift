import Foundation
import Testing

/// Toy Tumble never names the classic falling-blocks games or the trade words for their pieces
/// (spec §2, §9.2): not in code, comments, tests, prompts or asset names. The list is kept in
/// ROT13 so this test never spells the words; it is decoded only in memory.
@Suite struct TumbleWordsTests {
    static let banned = ["Grgevf", "GrgevArg", "grgebzvab", "Grgevzvab"].map(rot13).map { $0.lowercased() }

    static func rot13(_ s: String) -> String {
        String(s.unicodeScalars.map { u -> Character in
            switch u.value {
            case 65...90: Character(UnicodeScalar((u.value - 65 + 13) % 26 + 65)!)
            case 97...122: Character(UnicodeScalar((u.value - 97 + 13) % 26 + 97)!)
            default: Character(u)
            }
        })
    }

    /// `apps/play-ios`, from this file.
    static let root: URL = {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { dir.deleteLastPathComponent() }
        return dir
    }()

    /// Every file with Toy Tumble in its path or name, under the app's sources, tests and art.
    static func files() -> [URL] {
        let skip = ["build", ".build", "DerivedData", "Pounce.xcodeproj"]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [URL] = []
        for case let url as URL in walk {
            if skip.contains(url.lastPathComponent) {
                walk.skipDescendants()
                continue
            }
            let path = url.path.lowercased()
            guard path.contains("tumble"), (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            out.append(url)
        }
        return out
    }

    @Test func theListDecodes() {
        #expect(Self.banned.count == 4)
        #expect(Self.rot13(Self.rot13("Toy box")) == "Toy box")
    }

    @Test func noToyTumbleFileUsesThem() throws {
        let files = Self.files()
        #expect(files.count >= 8, "found \(files.count) Toy Tumble files")
        for url in files {
            let name = url.lastPathComponent.lowercased()
            for word in Self.banned { #expect(!name.contains(word), "\(url.path)") }
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { continue }
            let lower = text.lowercased()
            for word in Self.banned { #expect(!lower.contains(word), "\(url.path)") }
        }
    }
}
