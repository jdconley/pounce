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
    private var delivery: Delivery?
    private var original: UNNotificationContent?

    /// The app bundle around this extension (`Pounce.app/PlugIns/PounceNotify.appex`), whose
    /// asset catalog has the cats.
    private static var appBundle: Bundle? {
        Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
    }

    override func didReceive(
        _ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        // UserNotifications takes the handler back on any thread; it just isn't marked Sendable.
        nonisolated(unsafe) let handler = contentHandler
        let delivery = Delivery { handler($0) }
        self.delivery = delivery
        original = request.content
        let payload = PushPayload(userInfo: request.content.userInfo)
        let content = Communication.content(for: request.content, art: Self.appBundle) ?? request.content
        // The snapshot is written (by the IO layer's actor) before the notification is handed
        // back, so the extension isn't torn down mid-write.
        Task {
            await Self.updateWidgets(payload)
            await delivery.deliver(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        guard let original, let delivery else { return }
        Task { await delivery.deliver(original) }
    }

    /// Folds the push into the widgets' snapshot. Reloads at once when a paw, the numeral or the
    /// bell changed, and for moved tables alone at most every 15 minutes: reloads from an
    /// extension spend the widgets' daily budget.
    private static func updateWidgets(_ payload: PushPayload?) async {
        guard let payload, let store = await WidgetSnapshotStore.shared() else { return }
        let now = Date.now
        let reload = await store.update(noting: { old in
            var next = old.applying(payload, now: now)
            let reload = WidgetSnapshot.reloadsAfterPush(old: old, new: next, now: now)
            if reload { next.pushReloadAt = now }
            return (next, reload)
        })
        if reload == true { WidgetCenter.shared.reloadAllTimelines() }
    }
}

/// Hands the content back once, whichever comes first: the finished content or the time limit.
private actor Delivery {
    private var handler: (@Sendable (UNNotificationContent) -> Void)?

    init(_ handler: @escaping @Sendable (UNNotificationContent) -> Void) {
        self.handler = handler
    }

    func deliver(_ content: UNNotificationContent) {
        handler?(content)
        handler = nil
    }
}
