import PounceKit
import UIKit
import UserNotifications

/// UIKit's entry points for push. The work lives in `PushCoordinator`; the app model attaches
/// after SwiftUI builds it, and the coordinator holds a token or a tap that arrives first.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let push = PushCoordinator()

    weak var model: AppModel? {
        didSet {
            guard model !== oldValue else { return }
            model?.push = push
            push.model = model
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set before launch finishes, so a tap that cold-started the app is delivered here.
        UNUserNotificationCenter.current().delegate = push
        push.registerCategories()
        Sound.shared.preload()
        // The one app model, attached now so a notification button that launched the app in the
        // background (a pounce's In a bit) can answer before any scene connects.
        model = AppModel.shared
        // A reminder left from before the app was terminated must not fire now that it's open.
        push.cancelAllTurnReminders()
        #if DEBUG
        TouchMarks.installIfAsked()
        #endif
        return true
    }

    func application(
        _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        push.didRegister(token: deviceToken)
    }

    /// Background pushes (`content-available`): a "dismiss" clears a table this player moved at on
    /// another device (spec §12.5). Anything else is left alone.
    func application(
        _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard let code = PushPolicy.dismissCode(fromPayload: userInfo) else { return .noData }
        await push.dismiss(code: code)
        return .newData
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Expected on the simulator and in Debug builds without a sandbox token; nothing to do.
    }
}
