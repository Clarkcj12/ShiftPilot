import SwiftUI

@main
struct ShiftPilotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let env = appDelegate.environment
        WindowGroup {
            DashboardView()
                .environment(env.autoDrive)
                .environment(env.tracker)
                .environment(env.shifts)
                .environment(env.permissions)
                .environment(env.knownDevices)
                .environment(env.bleMonitor)
                .environment(env.vehicle)
        }
        .modelContainer(env.modelContainer)
    }
}
