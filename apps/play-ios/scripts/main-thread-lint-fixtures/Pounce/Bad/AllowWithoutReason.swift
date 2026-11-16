// expect: allow-without-reason, file-manager
import Foundation
@MainActor func path() -> URL {
    FileManager.default.temporaryDirectory // main-thread-ok:
}
