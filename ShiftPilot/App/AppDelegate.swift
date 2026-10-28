import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    let environment = AppEnvironment()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // iOS relaunches a terminated app in the background for a significant location
        // change or a restored BLE connection. Recreating the location and Bluetooth
        // managers here, before any UI, is what lets those events reach us.
        environment.start()
        return true
    }
}
