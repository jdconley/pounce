// expect: io-layer-isolation, io-layer-main-actor
import Foundation
public enum Files {
    public static func readNow(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }
}
public actor Vault {
    let url: URL
    init(url: URL) { self.url = url }
    public static func peek(_ url: URL) -> Data? { try? Data(contentsOf: url) }
}
@MainActor public final class Panel {}
