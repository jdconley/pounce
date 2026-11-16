// expect: none
import Foundation
public enum Files {
    @concurrent
    public static func read(_ url: URL) async -> Data? { try? Data(contentsOf: url) }

    @discardableResult
    @concurrent
    public static func write(_ data: Data, to url: URL) async -> Bool {
        (try? data.write(to: url, options: .atomic)) != nil
    }

    /// No IO: a plain helper may run anywhere.
    public static func name(_ url: URL) -> String { url.lastPathComponent }
}
public actor Vault {
    let url: URL
    init(url: URL) { self.url = url }
    public func load() -> Data? { try? Data(contentsOf: url) }
}
extension Vault {
    public func remove() { try? FileManager.default.removeItem(at: url) }
}
