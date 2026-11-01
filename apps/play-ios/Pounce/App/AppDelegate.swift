import UIKit
import UserNotifications

/// Push plumbing. The APNs token is uploaded on every launch (the server contract); the app model
/// attaches after SwiftUI builds it, so a token that arrives first is held until then.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: AppModel? {
        didSet { uploadPendingToken() }
    }
    private var pendingToken: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Sound.shared.preload()
        // Only re-register when the user already allowed notifications; the priming screen asks first.
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pendingToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        uploadPendingToken()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Expected on the simulator and in Debug builds without a sandbox token; nothing to do.
    }

    private func uploadPendingToken() {
        guard let model, let token = pendingToken else { return }
        Task { try? await model.api.setPushToken(token) }
    }

    // The table shows turns live, so skip foreground banners.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
