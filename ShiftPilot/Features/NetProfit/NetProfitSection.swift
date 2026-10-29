import SwiftUI

enum NetProfit {
    /// Combined net profit, or nil if any shift's vehicle cost is unknown.
    static func total(_ shifts: [ShiftSnapshot]) -> Decimal? {
        guard !shifts.isEmpty else { return nil }
        let nets = shifts.map(\.netProfit)
        guard !nets.contains(nil) else { return nil }
        return nets.reduce(Decimal(0)) { $0 + ($1 ?? 0) }
    }
}

/// Gross − fuel & wear = net, or a prompt to set up the vehicle.
struct NetProfitSection: View {
    let snapshot: ShiftSnapshot

    @Environment(GarageStore.self) private var garage

    var body: some View {
        Section {
            if let cost = snapshot.vehicleCost, let net = snapshot.netProfit {
                LabeledContent("Fuel & wear", value: "−\(Format.money(cost))")
                if snapshot.expenses > 0 {
                    LabeledContent("Tolls, parking & other", value: "−\(Format.money(TaxCalculator.round(snapshot.expenses)))")
                }
                LabeledContent("Net profit", value: Format.money(net))
                    .fontWeight(.semibold)
                LabeledContent("Net per hour", value: Format.rate(snapshot.netHourlyRate, per: "hr"))
            } else if let vehicle = garage.current {
                NavigationLink {
                    VehicleDetailView(vehicle: vehicle)
                } label: {
                    Label(Self.missingCostPrompt(garage.effectiveProfile(for: vehicle)), systemImage: "fuelpump.fill")
                }
            } else {
                NavigationLink {
                    GarageView()
                } label: {
                    Label("Add your vehicle to see net profit", systemImage: "fuelpump.fill")
                }
            }
        } header: {
            Text("Net profit")
        } footer: {
            if snapshot.vehicleCost != nil {
                Text("Estimated from your vehicle settings for this shift's business trips.")
            }
        }
    }
}

extension NetProfitSection {
    /// Names what's missing, so a half set-up vehicle isn't told to "set up" again.
    static func missingCostPrompt(_ profile: VehicleProfile) -> String {
        let hasEconomy = (profile.fuelEconomy ?? 0) > 0
        let hasPrice = (profile.fuelPrice ?? 0) > 0
        switch (hasEconomy, hasPrice) {
        case (true, false): return "Add a fuel price to see net profit"
        case (false, true): return "Add your \(profile.units == .us ? "MPG" : "fuel economy") to see net profit"
        default: return "Add fuel economy and price to see net profit"
        }
    }
}
