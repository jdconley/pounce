import Foundation

/// The words a Sniff player may guess (the server's `src/daily/sniff/words/allowed.txt`, bundled
/// as `sniff-allowed.txt`): an unknown word shakes and is never sent. Checking is a binary search
/// over the file's bytes as read (five letters and a newline each), so nothing is parsed or built
/// and `allows` is safe on the main actor (about 14 comparisons). Reading the file is not: `load`
/// goes through the IO layer.
public struct SniffWords: Sendable {
    private static let stride = 6
    private let bytes: [UInt8]

    /// Nil unless `data` is whole lines of five letters.
    public init?(data: Data) {
        guard !data.isEmpty, data.count % Self.stride == 0 else { return nil }
        bytes = [UInt8](data)
    }

    /// Reads the bundled list off the main actor.
    public static func load(bundle: Bundle = .main) async -> SniffWords? {
        guard let data = await Disk.resource("sniff-allowed", ofType: "txt", in: bundle) else { return nil }
        return SniffWords(data: data)
    }

    public func allows(_ word: String) -> Bool {
        let letters = Array(word.utf8)
        guard letters.count == 5, letters.allSatisfy({ (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0) }) else {
            return false
        }
        var lo = 0
        var hi = bytes.count / Self.stride - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let at = mid * Self.stride
            var order = 0
            for i in 0..<5 where order == 0 {
                order = Int(bytes[at + i]) - Int(letters[i])
            }
            if order == 0 { return true }
            if order < 0 { lo = mid + 1 } else { hi = mid - 1 }
        }
        return false
    }
}
