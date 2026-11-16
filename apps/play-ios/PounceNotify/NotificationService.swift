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
        let delivery = Delivery(Handler(call: contentHandler))
        self.delivery = delivery
        original = request.content
        let payload = PushPayload(userInfo: request.content.userInfo)
        let content = Content(Communication.content(for: request.content, art: Self.appBundle) ?? request.content)
        // The snapshot is written (by the IO layer's actor) before the notification is handed
        // back, so the extension isn't torn down mid-write.
        Task.detached { await NotificationService.finish(payload, content, delivery) }
    }

    private static func finish(_ payload: PushPayload?, _ content: Content, _ delivery: Delivery) async {
        await updateWidgets(payload)
        await delivery.deliver(content)
    }

    override func serviceExtensionTimeWillExpire() {
        guard let original, let delivery else { return }
        let content = Content(original)
        Task.detached { await delivery.deliver(content) }
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

/// A notification's content, carried across actors. `UNNotificationContent` is immutable (the
/// mutable kind is a subclass this never holds after building it); it just isn't marked Sendable.
private struct Content: @unchecked Sendable {
    let value: UNNotificationContent
    init(_ value: UNNotificationContent) { self.value = value }
}

/// The content handler. UserNotifications takes it back on any thread; it just isn't marked
/// Sendable.
private struct Handler: @unchecked Sendable {
    let call: (UNNotificationContent) -> Void
}

/// Hands the content back once, whichever comes first: the finished content or the time limit.
private actor Delivery {
    private var handler: Handler?

    init(_ handler: Handler) {
        self.handler = handler
    }

    func deliver(_ content: Content) {
        handler?.call(content.value)
        handler = nil
    }
}
