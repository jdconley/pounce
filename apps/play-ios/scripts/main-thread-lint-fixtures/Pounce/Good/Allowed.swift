// expect: none
import Foundation
@MainActor func documented() -> URL {
    FileManager.default.temporaryDirectory // main-thread-ok: a path lookup, no disk access
}
