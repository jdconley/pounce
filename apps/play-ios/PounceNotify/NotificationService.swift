import PounceKit
import UIKit
@preconcurrency import UserNotifications

/// `PounceNotify` (spec §12.5): pushes from a person (your move, a pounce, Play again, a pounce's
/// answer) become communication notifications with the sender's cat as the avatar
/// (`Communication`). Anything else, or anything that fails, is delivered as it came.
///
/// Writing the payload's `streak` block to the App Group for the widgets waits for PR 6, which
/// adds the widgets and the group.
final class NotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var original: UNNotificationContent?

    /// The app bundle around this extension (`Pounce.app/PlugIns/PounceNotify.appex`), whose
    /// asset catalog has the cats.
    private static var appBundle: Bundle? {
        Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
    }

    override func didReceive(
        _ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        handler = contentHandler
        original = request.content
        deliver(Communication.content(for: request.content, art: Self.appBundle) ?? request.content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let original { deliver(original) }
    }

    private func deliver(_ content: UNNotificationContent) {
        handler?(content)
        handler = nil
    }
}
