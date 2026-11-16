// expect: data-contents-of
import Foundation
@MainActor func label(_ url: URL) -> String {
    "size: \((try? Data(contentsOf: url))?.count ?? 0) bytes"
}
