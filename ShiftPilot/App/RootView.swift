import SwiftData
import SwiftUI

/// Tab bar: the day's work first, then the screens drivers check between shifts.
struct RootView: View {
    enum Tab: String {
        case today, trips, insights, taxes, garage
    }

    @Query(filter: #Predicate<Trip> { $0.purposeRawValue == nil && $0.endedAt != nil })
    private var tripsToReview: [Trip]
    @SceneStorage("selectedTab") private var selection: Tab = .today

    var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Today", systemImage: "gauge.with.dots.needle.67percent", value: Tab.today) {
                DashboardView()
            }
            SwiftUI.Tab("Trips", systemImage: "car.fill", value: Tab.trips) {
                NavigationStack { TripListView() }
            }
            .badge(tripsToReview.count)
            SwiftUI.Tab("Insights", systemImage: "chart.bar.xaxis", value: Tab.insights) {
                NavigationStack { EarningsInsightsView() }
            }
            SwiftUI.Tab("Taxes", systemImage: "building.columns", value: Tab.taxes) {
                NavigationStack { TaxVaultView() }
            }
            SwiftUI.Tab("Garage", systemImage: "wrench.and.screwdriver", value: Tab.garage) {
                NavigationStack { GarageView() }
            }
        }
    }
}
