import PounceKit
import UIKit
import UserNotifications

/// Push and local notifications (spec §7.5, §10).
///
/// - Registers with APNs on every launch once the user allowed notifications, and uploads the
///   token every time it arrives (the server contract). A failed upload is kept and retried on
///   the next foreground or the next successful call to the server. The token is kept for the
///   launch and goes up again whenever the API client mints a new device credential (a re-mint
///   after a 401), since the server has no token for the new device.
/// - A tap on a "your turn" notification opens that table. On a cold start the tap can land
///   before SwiftUI attaches the app model, so it waits here like the token does.
/// - In the foreground a banner is dropped only when its table is on screen (the table shows
///   the turn already); any other table's banner shows and Home's list refreshes.
/// - The local turn reminder looks exactly like the server's push.
@MainActor
final class PushCoordinator: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppModel? {
        didSet {
            watchCredential()
            uploadPendingToken()
            routePendingTap()
        }
    }

    /// The last token APNs gave this launch and which device the server holds it for.
    private(set) var tokens = PushTokenState()
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
        tokens.received(PushPolicy.hexToken(token))
        uploadPendingToken()
    }

    /// Re-sends the token when the API client mints a new device.
    private func watchCredential() {
        guard let api = model?.api else { return }
        let handler: @Sendable (DeviceCredential) -> Void = { [weak self] credential in
            Task { @MainActor in self?.credentialChanged(credential.deviceId) }
        }
        Task { await api.setCredentialChangeHandler(handler) }
    }

    private func credentialChanged(_ deviceId: String) {
        tokens.deviceChanged(deviceId)
        uploadPendingToken()
    }

    /// Tries a held token again (foreground, or after another server call succeeded).
    func retryUpload() {
        uploadPendingToken()
    }

    private func uploadPendingToken() {
        // A kitten's push token never goes up: it is online contact information (spec §14.1).
        guard let model, model.limits.uploadsPushToken, let token = tokens.pending, !uploading else { return }
        uploading = true
        Task {
            do {
                // A newer token or a new device may have arrived while this one was in flight;
                // `tokens` only clears what the server now holds.
                let deviceId = try await model.api.setPushToken(token)
                tokens.uploaded(token, deviceId: deviceId)
            } catch {
                // Offline or the server is down: kept for the next foreground or server call.
                uploading = false
                return
            }
            uploading = false
            // Cleared before retrying, so a token or device that changed mid-flight goes now.
            if tokens.pending != nil { uploadPendingToken() }
        }
    }

    // MARK: across devices (spec §12.5)

    /// The badge says how many tables wait on your move. Best effort: needs badge permission.
    func setBadge(_ count: Int) {
        center.setBadgeCount(count) { _ in }
    }

    /// A background push said the player moved at `code` on another device: that table's
    /// delivered notifications go, and the tables (and the badge) refresh.
    func dismiss(code: String) async {
        let delivered = await center.deliveredNotifications()
        let ids = delivered
            .filter {
                PushPolicy.matches(
                    code: code, userInfo: $0.request.content.userInfo, threadId: $0.request.content.threadIdentifier)
            }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        #if DEBUG
        print("[push] dismissed \(code): removed \(ids.count) delivered")
        #endif
        await model?.refreshTables()
    }

    static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    // MARK: local turn reminder

    /// The same shape as the server's push: title = whose turn, body "Your turn at <table>",
    /// thread = room code, top-level `code` for the tap.
    func scheduleTurnReminder(code: String, name: String, table: String, after: Duration) {
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = String(
            localized: "Your turn at \(table)", comment: "Notification body: it is this person's turn at this table")
        content.sound = .default
        content.threadIdentifier = code
        content.userInfo = ["code": code]
        let seconds = max(1, Double(after.components.seconds) + Double(after.components.attoseconds) / 1e18)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let id = PushPolicy.reminderID(code: code)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        scheduledReminders.insert(id)
        Self.add(request)
    }

    /// Nonisolated so the completion closure isn't main-actor isolated: the center calls it on
    /// a background queue, where an isolated closure would trap.
    nonisolated private static func add(_ request: UNNotificationRequest) {
        let id = request.identifier
        UNUserNotificationCenter.current().add(request) { _ in
            #if DEBUG
            logPendingReminders("scheduled \(id)")
            #endif
        }
    }

    /// Reminders scheduled by this process, removed by identifier straight away on foreground.
    private var scheduledReminders: Set<String> = []

    /// Removes every local turn reminder, pending or delivered, for any room. Called at launch
    /// and on every foreground: a reminder scheduled before iOS terminated the app in the
    /// background is only found by listing them (spec §7.5, "cancelled on foreground").
    func cancelAllTurnReminders() {
        let known = Array(scheduledReminders)
        scheduledReminders.removeAll()
        center.removePendingNotificationRequests(withIdentifiers: known)
        center.removeDeliveredNotifications(withIdentifiers: known)
        Self.removeListedReminders()
    }

    /// Lists pending and delivered requests and removes every turn reminder. Nonisolated for
    /// the same reason as `add`: the list callbacks arrive on a background queue.
    nonisolated private static func removeListedReminders() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter(PushPolicy.isReminderID)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            #if DEBUG
            logPendingReminders("cancelled pending \(ids)")
            #endif
        }
        center.getDeliveredNotifications { notifications in
            let ids = notifications.map(\.request.identifier).filter(PushPolicy.isReminderID)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    #if DEBUG
    /// `[push] <event>; pending reminders: [...]` (verification aid).
    nonisolated private static func logPendingReminders(_ event: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter(PushPolicy.isReminderID)
            print("[push] \(event); pending reminders: \(ids)")
        }
    }
    #endif

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
