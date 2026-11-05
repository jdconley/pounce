import PounceKit
import UIKit
@preconcurrency import UserNotifications
import WidgetKit

/// `PounceNotify` (spec §12.5): pushes from a person (your move, a pounce, Play again, a pounce's
/// answer) become communication notifications with the sender's cat as the avatar
/// (`Communication`). Anything else, or anything that fails, is delivered as it came.
///
/// Every push's `streak` block (and a pounce's answer) also goes into the widgets' snapshot in
/// the App Group, and the widgets reload (spec §11.2).
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
        Self.updateWidgets(request.content.userInfo)
        deliver(Communication.content(for: request.content, art: Self.appBundle) ?? request.content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let original { deliver(original) }
    }

    /// Folds the push into the widgets' snapshot; reloads them only when something changed.
    private static func updateWidgets(_ userInfo: [AnyHashable: Any]) {
        guard let payload = PushPayload(userInfo: userInfo), let store = WidgetSnapshotStore.shared else { return }
        let now = Date.now
        if store.update({ $0.applying(payload, now: now) }) { WidgetCenter.shared.reloadAllTimelines() }
    }

    private func deliver(_ content: UNNotificationContent) {
        handler?(content)
        handler = nil
    }
}
