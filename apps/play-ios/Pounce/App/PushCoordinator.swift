import PounceKit
import UIKit
import UserNotifications

/// Push and local notifications (spec §7.5, §10).
///
/// - Registers with APNs on every launch once the user allowed notifications, and uploads the
///   token every time it arrives (the server contract). A failed upload is kept and retried on
///   the next foreground or the next successful call to the server, then cleared.
/// - A tap on a "your turn" notification opens that table. On a cold start the tap can land
///   before SwiftUI attaches the app model, so it waits here like the token does.
/// - In the foreground a banner is dropped only when its table is on screen (the table shows
///   the turn already); any other table's banner shows and Home's list refreshes.
/// - The local turn reminder looks exactly like the server's push.
@MainActor
final class PushCoordinator: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppModel? {
        didSet {
            uploadPendingToken()
            routePendingTap()
        }
    }

    /// The last token APNs gave this launch, until the server has it.
    private(set) var pendingToken: String?
    private var uploading = false
    /// A notification tapped before the app model (or its owner) was ready.
    private var pendingTapCode: String?

    private var center: UNUserNotificationCenter { .current() }

    // MARK: registration

    /// Called at every launch: re-register only when the user already allowed notifications.
    /// The priming screen asks first; the system prompt never shows at launch.
    func registerEveryLaunch() {
        Task {
            if Self.isAllowed(await center.notificationSettings().authorizationStatus) {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// The system prompt (after the priming screen). Registers on yes.
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Uploads every time: each launch hands a token here, changed or not.
    func didRegister(token: Data) {
        pendingToken = PushPolicy.hexToken(token)
        uploadPendingToken()
    }

    /// Tries a held token again (foreground, or after another server call succeeded).
    func retryUpload() {
        uploadPendingToken()
    }

    private func uploadPendingToken() {
        guard let model, let token = pendingToken, !uploading else { return }
        uploading = true
        Task {
            defer { uploading = false }
            do {
                try await model.api.setPushToken(token)
                // A newer token may have arrived while this one was in flight.
                if pendingToken == token { pendingToken = nil }
            } catch {
                // Offline or the server is down: kept for the next foreground or server call.
                return
            }
            if pendingToken != nil { uploadPendingToken() }
        }
    }

    static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    // MARK: local turn reminder

    private static func reminderID(_ code: String) -> String { "turn-reminder-\(code)" }

    /// The same shape as the server's push: title = whose turn, body "Your turn",
    /// thread = room code, top-level `code` for the tap.
    func scheduleTurnReminder(code: String, name: String, after: Duration) {
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = String(localized: "Your turn", comment: "Notification body: it is this person's turn")
        content.sound = .default
        content.threadIdentifier = code
        content.userInfo = ["code": code]
        let seconds = max(1, Double(after.components.seconds) + Double(after.components.attoseconds) / 1e18)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: Self.reminderID(code), content: content, trigger: trigger)
        center.add(request) { _ in }
    }

    func cancelTurnReminder(code: String) {
        let id = Self.reminderID(code)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let code = PushPolicy.code(fromPayload: notification.request.content.userInfo)
        return await presentation(for: code)
    }

    /// The completion-handler form on purpose: UIKit asserts this handler runs on the main
    /// thread, and the async form's bridge finishes on a background thread (a crash on tap).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let tap = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let code = PushPolicy.code(fromPayload: response.notification.request.content.userInfo)
        let done = MainThreadCallback(completionHandler)
        Task { @MainActor in
            if tap { self.tapped(code: code) }
            done.call()
        }
    }

    private func presentation(for code: String?) -> UNNotificationPresentationOptions {
        if let code, let model, model.isOnScreen(code: code) { return [] }
        if let model { Task { await model.refreshTables() } }
        return [.banner, .list, .sound]
    }

    private func tapped(code: String?) {
        guard let code else { return }
        pendingTapCode = code
        routePendingTap()
    }

    private func routePendingTap() {
        guard let code = pendingTapCode, let model, model.people.owner != nil else { return }
        pendingTapCode = nil
        model.open(code: code, intent: .rejoin)
    }
}

/// Carries a UIKit completion handler to the main actor, where it is called.
private struct MainThreadCallback: @unchecked Sendable {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @MainActor func call() { body() }
}
