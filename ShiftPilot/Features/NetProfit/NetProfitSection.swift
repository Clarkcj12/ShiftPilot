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

    var body: some View {
        Section {
            if let cost = snapshot.vehicleCost, let net = snapshot.netProfit {
                LabeledContent("Fuel & wear", value: "−\(Format.money(cost))")
                LabeledContent("Net profit", value: Format.money(net))
                    .fontWeight(.semibold)
                LabeledContent("Net per hour", value: Format.rate(snapshot.netHourlyRate, per: "hr"))
            } else {
                NavigationLink {
                    VehicleSettingsView()
                } label: {
                    Label("Set up your vehicle to see net profit", systemImage: "fuelpump.fill")
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
