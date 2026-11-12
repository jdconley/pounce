import Foundation

/// A dotted app version ("1.1", "1.2.0"), compared number by number. The same rules as the
/// server's `parseVersion` (play-api `src/app/version.ts`), so both sides agree on who is behind.
///
/// Forgiving about what surrounds the numbers ("v1.2", " 1.2 ", "1.2-beta" and "1.2 (57)" are all
/// 1.2) and strict about there being numbers: anything else is nil, never a guess. Nobody is told
/// to update on a version that couldn't be read.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// The numbers, most significant first, without trailing zeros: 1.1.0 and 1.1 are the same version.
    public let parts: [Int]
    /// As it was written, cleaned: "1.2.0".
    public let description: String

    private static let maxParts = 4
    private static let maxPart = 999_999

    public init?(_ text: String?) {
        guard let text else { return nil }
        var rest = Substring(text).drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" })
        if let first = rest.first, first == "v" || first == "V" { rest = rest.dropFirst() }
        var numbers: [Int] = []
        while true {
            let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
            guard !digits.isEmpty, digits.count <= 7, let n = Int(digits), n <= Self.maxPart else { return nil }
            numbers.append(n)
            rest = rest.dropFirst(digits.count)
            guard rest.first == "." else { break }
            rest = rest.dropFirst()
            // "1." and "1.x" name no version.
            guard let next = rest.first, next.isASCII, next.isNumber else { return nil }
        }
        guard numbers.count <= Self.maxParts else { return nil }
        description = numbers.map(String.init).joined(separator: ".")
        var trimmed = numbers
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        parts = trimmed
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { a.parts == b.parts }

    public func hash(into hasher: inout Hasher) { hasher.combine(parts) }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let (x, y) = (i < a.parts.count ? a.parts[i] : 0, i < b.parts.count ? b.parts[i] : 0)
            if x != y { return x < y }
        }
        return false
    }

    /// `a` is older than `b`. Either one unreadable: false.
    public static func isOlder(_ a: String?, than b: String?) -> Bool {
        guard let a = AppVersion(a), let b = AppVersion(b) else { return false }
        return a < b
    }
}
