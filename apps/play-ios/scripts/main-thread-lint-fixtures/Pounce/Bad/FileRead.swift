// expect: data-contents-of, string-contents-of, contents-of-file, audio-contents-of
import AVFoundation
import UIKit
@MainActor func load(_ url: URL) {
    _ = try? Data(contentsOf: url)
    _ = try? String(contentsOf: url, encoding: .utf8)
    _ = UIImage(contentsOfFile: url.path)
    _ = try? AVAudioPlayer(contentsOf: url)
}
