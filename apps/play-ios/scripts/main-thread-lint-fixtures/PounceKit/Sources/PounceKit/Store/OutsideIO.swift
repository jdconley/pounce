// expect: data-contents-of
import Foundation
public final class SomeStore {
    public func load(_ url: URL) -> Data? { try? Data(contentsOf: url) }
}
