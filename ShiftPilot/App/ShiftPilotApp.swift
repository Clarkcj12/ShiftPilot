import SwiftUI

@main
struct ShiftPilotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

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
                .environment(env.garage)
                .environment(env.garage.fuelPrices)
                .task(id: FuelPriceTrigger(isActive: scenePhase == .active, state: env.garage.current?.plateRegion)) {
                    if scenePhase == .active {
                        await env.garage.refreshFuelPrice()
                    }
                }
        }
        .modelContainer(env.modelContainer)
    }
}

/// Refetch the regional fuel price when the app comes to the foreground or the plate state changes.
private struct FuelPriceTrigger: Equatable {
    var isActive: Bool
    var state: String?
}
