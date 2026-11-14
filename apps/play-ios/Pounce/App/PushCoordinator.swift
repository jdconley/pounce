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
/// - Categories and their buttons (spec §12.5): Play opens the app; In an hour re-posts the
///   notification locally; a pounce's In a bit and Not now are answered in the background
///   through the app's answer queue. A kitten's device never registers for remote push (§14.1)
///   without a parent's consent. Parent consent's confirmation (consent design D6) has Revoke,
///   in the background; a tap opens the Kittens panel on that kitten.
/// - In the foreground a banner is dropped only when its table is on screen (the table shows
///   the turn already); any other table's banner shows and Home's list refreshes.
/// - The local turn reminder looks exactly like the server's push.
/// - Every call to the notification center goes through `NotificationCenterQueue`, never on the
///   main thread.
@MainActor
final class PushCoordinator: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppModel? {
        didSet {
            guard model !== oldValue else { return }
            watchCredential()
            registerIfAllowed()
            uploadPendingToken()
            routePendingTap()
        }
    }

    /// The last token APNs gave this launch and which device the server holds it for.
    private(set) var tokens = PushTokenState()
    private var uploading = false

    // MARK: registration

    /// The categories and their buttons (spec §12.5), set at every launch before any arrives.
    func registerCategories() {
        let categories = Set(PushCategory.allCases.map { category in
            UNNotificationCategory(
                identifier: category.rawValue, actions: NotifyActions.actions(for: category).map(Self.action),
                intentIdentifiers: [], options: [])
        })
        let set = Unchecked(categories)
        NotificationCenterQueue.run { $0.setNotificationCategories(set.value) }
    }

    private static func action(_ action: NotifyAction) -> UNNotificationAction {
        let title: String
        let icon: String
        switch action {
        case .play:
            title = String(localized: "Play", comment: "Notification button: open the table and play")
            icon = "play.fill"
        case .inAnHour:
            title = String(localized: "In an hour", comment: "Notification button: remind me again in an hour")
            icon = "clock.fill"
        case .later:
            title = String(localized: "In a bit", comment: "Notification button: answer a pounce, coming in a bit")
            icon = "clock.fill"
        case .notNow:
            title = String(localized: "Not now", comment: "Notification button: answer a pounce, not now")
            icon = "moon.zzz.fill"
        case .revoke:
            title = String(
                localized: "Revoke",
                comment: "Notification button on parent consent's confirmation: take back a child's notifications (legal text)")
            icon = "bell.slash.fill"
        }
        var options: UNNotificationActionOptions = action.foreground ? [.foreground] : []
        // Revoke runs in the background, drawn red, and only on an unlocked device.
        if action.destructive { options.formUnion([.destructive, .authenticationRequired]) }
        return UNNotificationAction(
            identifier: action.rawValue, title: title, options: options, icon: UNNotificationActionIcon(systemImageName: icon))
    }

    /// Registers with APNs when the user allowed notifications (fully or provisionally) and this
    /// device may hold a push token at all: never a kitten's, or one whose age isn't known yet
    /// (spec §14.1). The priming screen asks first; the system prompt never shows at launch.
    func registerIfAllowed() {
        guard let model else { return }
        guard PushPolicy.registersRemote(band: model.ageBand, kittenConsented: model.kittenConsented) else {
            // Consent ended (consent design §2 Revocation): the server already dropped the token;
            // this device drops its registration too.
            if model.kittens.registeredAsKitten {
                UIApplication.shared.unregisterForRemoteNotifications()
                model.kittens.noteRegistered(false)
            }
            return
        }
        let kitten = model.ageBand == .kitten
        Task {
            if Self.isAllowed(await NotificationCenterQueue.authorizationStatus()) {
                UIApplication.shared.registerForRemoteNotifications()
                if kitten { model.kittens.noteRegistered(true) }
            }
        }
    }

    /// The system prompt (after the priming screen). Registers on yes.
    func requestAuthorization() async -> Bool {
        let granted = await NotificationCenterQueue.requestAuthorization([.alert, .sound, .badge])
        model?.funnel.answeredPush(allowed: granted)
        if granted { registerIfAllowed() }
        return granted
    }

    /// Priming's "not now" (§12.5): provisional authorization, with no prompt. Notifications then
    /// land quietly in Notification Center with iOS's own Keep and Turn Off buttons.
    func requestProvisional() async {
        guard await NotificationCenterQueue.authorizationStatus() == .notDetermined else { return }
        let granted = await NotificationCenterQueue.requestAuthorization([.alert, .sound, .badge, .provisional])
        if granted { registerIfAllowed() }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await NotificationCenterQueue.authorizationStatus()
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
        // The new device has no widget token on the server either (spec §11.2), nor live table ones (§11.3).
        Task { await model?.uploadWidgetToken() }
        model?.liveTables.deviceChanged()
        Task { await model?.liveTables.retry() }
    }

    /// Tries a held token again (foreground, or after another server call succeeded).
    func retryUpload() {
        uploadPendingToken()
    }

    private func uploadPendingToken() {
        // A kitten's push token goes up only with a parent's consent: it is online contact
        // information (spec §14.1, consent design §2).
        guard let model, model.limits.uploadsPushToken || model.kittenConsented, let token = tokens.pending, !uploading else { return }
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
        NotificationCenterQueue.run { $0.setBadgeCount(count) { _ in } }
    }

    /// A background push said the player moved at `code` on another device: that table's
    /// delivered notifications go, and the tables (and the badge) refresh.
    func dismiss(code: String) async {
        let removed: Int = await NotificationCenterQueue.value { center, answer in
            center.getDeliveredNotifications { delivered in
                let ids = delivered
                    .filter {
                        PushPolicy.matches(
                            code: code, userInfo: $0.request.content.userInfo, threadId: $0.request.content.threadIdentifier)
                    }
                    .map(\.request.identifier)
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
                answer(ids.count)
            }
        }
        #if DEBUG
        print("[push] dismissed \(code): removed \(removed) delivered")
        #endif
        await model?.refreshTables()
    }

    static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    static func mirror(_ status: UNAuthorizationStatus) -> PushAuthorization {
        switch status {
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        case .denied: .denied
        default: .notDetermined
        }
    }

    // MARK: "In an hour" (spec §12.5): the same notification again, on this phone only

    func snooze(_ content: UNNotificationContent, key: String, after seconds: Int) {
        guard let copy = content.mutableCopy() as? UNMutableNotificationContent else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        Self.add(UNNotificationRequest(identifier: PushPolicy.snoozeID(key), content: copy, trigger: trigger))
    }

    /// A snoozed "your move" goes once its table is open, or no longer waits on you.
    func cancelSnoozes(codes: [String]) {
        guard !codes.isEmpty else { return }
        let ids = codes.map { PushPolicy.snoozeID($0) }
        NotificationCenterQueue.run { $0.removePendingNotificationRequests(withIdentifiers: ids) }
    }

    #if DEBUG
    /// A pounce from Mia (play-api's `pounce-new` sample), as a communication notification.
    func postDemoPounce(after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "JD"
        content.body = "Mia wants to play. New game?"
        content.sound = .default
        content.categoryIdentifier = PushCategory.pounce.rawValue
        content.threadIdentifier = "pounce:pr_3f9cAAAAAAAAAAAAAAAAAA"
        content.interruptionLevel = .active
        content.relevanceScore = 0.9
        content.userInfo = [
            "kind": "pounce", "from": ["name": "Mia", "cat": 2],
            "pounce": ["id": "pc_demoKikiAAAAAAAAAAAAAA", "target": "new"],
            "aps": ["alert": ["title": "JD", "body": content.body], "thread-id": content.threadIdentifier, "category": "POUNCE"],
        ]
        let drawn = Communication.content(for: content, art: .main) ?? content
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        Self.add(UNNotificationRequest(identifier: "demo-pounce", content: drawn, trigger: trigger))
    }
    #endif

    // MARK: a kitten's daily reminder (spec §14.1): local, at a fixed 17:00, off by default

    func setKittenDaily(on: Bool, name: String) {
        NotificationCenterQueue.run { $0.removePendingNotificationRequests(withIdentifiers: [KittenReminder.id]) }
        guard on else { return }
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = String(localized: "The cats are on the rug.", comment: "A kitten's local daily reminder (spec §12.2 copy)")
        content.sound = .default
        content.threadIdentifier = KittenReminder.id
        let when = DateComponents(hour: KittenReminder.time.h, minute: KittenReminder.time.m)
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        Self.add(UNNotificationRequest(identifier: KittenReminder.id, content: content, trigger: trigger))
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
    /// a background queue, where an isolated closure would trap. Queued after any cancel asked
    /// for before it.
    nonisolated private static func add(_ request: UNNotificationRequest) {
        let id = request.identifier
        let request = Unchecked(request)
        NotificationCenterQueue.run { center in
            center.add(request.value) { _ in
                #if DEBUG
                logPendingReminders("scheduled \(id)")
                #endif
            }
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
        NotificationCenterQueue.run { center in
            center.removePendingNotificationRequests(withIdentifiers: known)
            center.removeDeliveredNotifications(withIdentifiers: known)
        }
        Self.removeListedReminders()
    }

    /// Lists pending and delivered requests and removes every turn reminder. Nonisolated for
    /// the same reason as `add`: the list callbacks arrive on a background queue. The queue
    /// holds until the pending ones are gone, so a reminder scheduled after this lands after
    /// it and survives.
    nonisolated private static func removeListedReminders() {
        NotificationCenterQueue.runHolding { center, done in
            center.getPendingNotificationRequests { requests in
                let ids = requests.map(\.identifier).filter(PushPolicy.isReminderID)
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
                done()
                #if DEBUG
                logPendingReminders("cancelled pending \(ids)")
                #endif
            }
        }
        NotificationCenterQueue.run { center in
            center.getDeliveredNotifications { notifications in
                let ids = notifications.map(\.request.identifier).filter(PushPolicy.isReminderID)
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            }
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
        let userInfo = notification.request.content.userInfo
        let code = PushPolicy.code(fromPayload: userInfo)
        let kind = userInfo["kind"] as? String
        return await presentation(for: code, kind: kind)
    }

    /// The completion-handler form on purpose: UIKit asserts this handler runs on the main
    /// thread, and the async form's bridge finishes on a background thread (a crash on tap).
    /// A background button (In a bit, Not now) calls it only once its answer is sent or queued.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let request = response.notification.request
        let payload = PushPayload(userInfo: request.content.userInfo)
        let content = Snoozable(content: request.content, key: payload?.code ?? request.content.threadIdentifier)
        let done = MainThreadCallback(completionHandler)
        Task { @MainActor in
            await self.respond(action: action, payload: payload, snoozable: content)
            done.call()
        }
    }

    private func respond(action: String, payload: PushPayload?, snoozable: Snoozable) async {
        guard let payload else { return }
        switch NotifyActions.outcome(action: action, payload: payload) {
        case .open(let code):
            tapped(code: code)
        case .answer(let id, let answer, let opensApp):
            pending = .answer(id: id, answer, opens: opensApp, title: payload.title)
            if opensApp {
                routePendingTap()
            } else {
                // Runs in the background: iOS gives it a little time; the queue (on disk before the
                // request) keeps the answer for the next launch if that isn't enough.
                let task = BackgroundTask()
                task.id = UIApplication.shared.beginBackgroundTask(withName: "pounce-answer") { task.end() }
                await routePending()
                task.end()
            }
        case .pick(let id, let target, let from):
            pending = .pick(id: id, target: target, from: from, title: payload.title)
            routePendingTap()
        case .snooze(let seconds):
            snooze(snoozable.content, key: snoozable.key.isEmpty ? UUID().uuidString : snoozable.key, after: seconds)
        case .kittens(let kitten):
            pending = .kittens(kitten)
            routePendingTap()
        case .revokeConsent(let kitten):
            // In the background, like a pounce's answer: iOS gives it a little time. The store keeps
            // the revoke on disk before the request, so a failure is tried again on the next launch
            // or foreground.
            let task = BackgroundTask()
            task.id = UIApplication.shared.beginBackgroundTask(withName: "pounce-revoke") { task.end() }
            if let model {
                await model.kittens.revoke(kitten: kitten)
            } else {
                pending = .revoke(kitten)
                await routePending()
            }
            task.end()
        case .none:
            break
        }
    }

    private func presentation(for code: String?, kind: String?) -> UNNotificationPresentationOptions {
        if let model, ["pounce", "pounce_answered"].contains(kind) { Task { await model.refreshStreaks() } }
        if let model, kind == "consent" { Task { await model.kittens.refreshKittens() } }
        if let code, let model, model.isOnScreen(code: code), kind != "pounce" { return [] }
        if let model { Task { await model.refreshTables() } }
        return [.banner, .list, .sound]
    }

    private func tapped(code: String) {
        pending = .open(code)
        routePendingTap()
    }

    /// What a tap or a button asked for, waiting for the app model (and its owner) if needed.
    private enum Pending {
        case open(String)
        /// `title` names the person on this phone the pounce is for (§12.2).
        case answer(id: String, PounceAnswer, opens: Bool, title: String?)
        case pick(id: String, target: PounceTarget, from: PushFace?, title: String?)
        /// A consent notification: the Kittens panel on this kitten, or its Revoke button.
        case kittens(String)
        case revoke(String)
    }

    private var pending: Pending?

    private func routePendingTap() {
        Task { await routePending() }
    }

    private func routePending() async {
        guard let next = pending, let model, model.people.owner != nil else { return }
        pending = nil
        switch next {
        case .open(let code):
            model.open(code: code, intent: .rejoin)
        case .answer(let id, let answer, let opens, let title):
            await model.answerPounce(
                id: id, answer: answer, choice: nil, link: nil, person: model.pounceRecipient(title: title), opens: opens)
        case .pick(let id, let target, let from, let title):
            model.showPick(PickRequest(id: id, target: target, from: from, link: nil, person: model.pounceRecipient(title: title)))
        case .kittens(let kitten):
            model.showKittens(focus: kitten)
        case .revoke(let kitten):
            await model.kittens.revoke(kitten: kitten)
        }
    }
}

/// Every call to the notification center, on one serial queue off the main thread, in the order
/// they were asked for (a reminder scheduled after a cancel lands after it).
///
/// The center's adds, removes and lists wait on a reply from `usernotificationsd`; a slow daemon
/// (a freshly booted iOS 27 simulator can take minutes) would otherwise freeze the app at launch.
enum NotificationCenterQueue {
    private static let queue = DispatchQueue(label: "com.conleychaos.play.notification-center", qos: .userInitiated)

    /// Runs `work` after everything asked for before it.
    static func run(_ work: @escaping @Sendable (UNUserNotificationCenter) -> Void) {
        queue.async { work(.current()) }
    }

    /// Runs `work`, and nothing asked for after it until `work` calls `done` (once, from any
    /// thread, typically a center callback). No thread waits meanwhile: the queue is suspended.
    static func runHolding(
        _ work: @escaping @Sendable (UNUserNotificationCenter, _ done: @escaping @Sendable () -> Void) -> Void
    ) {
        queue.async {
            // Takes effect once this block returns, even if `done` already ran.
            queue.suspend()
            work(.current()) { queue.resume() }
        }
    }

    /// Runs `work` in order and waits (without blocking a thread) for the answer it hands back once.
    static func value<T: Sendable>(
        _ work: @escaping @Sendable (UNUserNotificationCenter, _ answer: @escaping @Sendable (T) -> Void) -> Void
    ) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { work(.current()) { continuation.resume(returning: $0) } }
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await value { center, answer in center.getNotificationSettings { answer($0.authorizationStatus) } }
    }

    /// False on an error, as the async form's `try?` was.
    static func requestAuthorization(_ options: UNAuthorizationOptions) async -> Bool {
        await value { center, answer in center.requestAuthorization(options: options) { granted, _ in answer(granted) } }
    }
}

/// An immutable framework object carried to the notification queue.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// A background task ended once: when its work is done, or when iOS says time is up.
@MainActor private final class BackgroundTask {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// A delivered notification's content, carried to the main actor for "In an hour".
private struct Snoozable: @unchecked Sendable {
    let content: UNNotificationContent
    let key: String
}

/// Carries a UIKit completion handler to the main actor, where it is called.
private struct MainThreadCallback: @unchecked Sendable {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @MainActor func call() { body() }
}
