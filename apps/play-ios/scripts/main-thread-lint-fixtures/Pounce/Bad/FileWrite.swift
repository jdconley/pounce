// expect: write-to, file-manager, file-handle, with-file
import Foundation
@MainActor func save(_ data: Data, to url: URL) {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
    _ = FileHandle(forReadingAtPath: url.path)
    _ = NSKeyedUnarchiver.unarchiveObject(withFile: url.path)
}
