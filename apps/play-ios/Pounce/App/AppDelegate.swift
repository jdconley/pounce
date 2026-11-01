import UIKit
import UserNotifications

/// UIKit's entry points for push. The work lives in `PushCoordinator`; the app model attaches
/// after SwiftUI builds it, and the coordinator holds a token or a tap that arrives first.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let push = PushCoordinator()

    weak var model: AppModel? {
        didSet {
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
        Sound.shared.preload()
        push.registerEveryLaunch()
        return true
    }

    func application(
        _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        push.didRegister(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Expected on the simulator and in Debug builds without a sandbox token; nothing to do.
    }
}
