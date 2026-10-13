import StickySync
import UIKit

final class ScrapsMobileDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        StickyCloudSync.shared.start()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard StickyCloudSync.shared.isEnabled else { return .noData }
        await StickyCloudSync.shared.synchronize()
        return .newData
    }
}
