import SwiftUI

/// Today's numbers at a glance, shown on the dashboard.
struct TodayTotals {
    var gross: Decimal = 0
    var seconds: TimeInterval = 0
    var net: Decimal?
    var deduction: Decimal = 0
    var hasHistory = false
}

/// Dashboard hero: the live shift, or today's earnings and a Start shift button.
struct ShiftCard: View {
    var today = TodayTotals()

    @Environment(ShiftManager.self) private var shifts

    var body: some View {
        content
            .sensoryFeedback(.impact(weight: .medium), trigger: shifts.activeShift != nil)
    }

    @ViewBuilder
    private var content: some View {
        if let shift = shifts.activeShift {
            ActiveShiftCard(shift: shift)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.money(today.gross))
                        .font(Theme.hero())
                        .contentTransition(.numericText())
                    Text("Earned today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if today.hasHistory {
                    MetricRow(metrics: [
                        MetricView(title: "True EPH", value: Format.rate(EarningsCalculator.hourlyRate(today.gross, over: today.seconds), per: "hr")),
                        MetricView(title: "Net profit", value: today.net.map(Format.money) ?? "—"),
                        MetricView(title: "Deduction", value: Format.money(today.deduction)),
                    ])
                } else {
                    Text("Start a shift when you go online. Drives are logged automatically, so every mile counts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    shifts.startShift()
                } label: {
                    Label("Start shift", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.vertical, 6)
        }
    }
}

private struct ActiveShiftCard: View {
    let shift: Shift

    @Environment(ShiftManager.self) private var shifts
    @Environment(GarageStore.self) private var garage
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault
    @State private var isAddingPayout = false
    @State private var isConfirmingEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let snapshot = shift.snapshot(now: context.date, costPerMeter: garage.costPerMeter)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("On shift", systemImage: "clock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text(Format.duration(snapshot.duration))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.rate(snapshot.hourlyRate, per: "hr"))
                        .font(Theme.hero())
                        .contentTransition(.numericText())
                    Text("True earnings per hour")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                MetricRow(metrics: [
                    MetricView(title: "Earned", value: Format.money(snapshot.gross)),
                    MetricView(title: "Net", value: snapshot.netProfit.map(Format.money) ?? "—"),
                    MetricView(title: "Distance", value: unit.format(meters: snapshot.distanceMeters)),
                ])

                HStack {
                    Button {
                        isAddingPayout = true
                    } label: {
                        Label("Payout", systemImage: "plus")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        isConfirmingEnd = true
                    } label: {
                        Label("End shift", systemImage: "stop.fill")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(.vertical, 6)
        }
        .sensoryFeedback(.success, trigger: shift.payouts.count)
        .sheet(isPresented: $isAddingPayout) {
            AddPayoutView(shift: shift)
        }
        .endShiftDialog(shift: shift, isPresented: $isConfirmingEnd, isAddingPayout: $isAddingPayout)
    }
}

extension View {
    /// Confirms ending a shift. A shift with no payouts can't end: the dialog offers
    /// to add one (platform and amount are required there) or discard the shift.
    func endShiftDialog(shift: Shift, isPresented: Binding<Bool>, isAddingPayout: Binding<Bool>) -> some View {
        modifier(EndShiftDialog(shift: shift, isPresented: isPresented, isAddingPayout: isAddingPayout))
    }
}

private struct EndShiftDialog: ViewModifier {
    let shift: Shift
    @Binding var isPresented: Bool
    @Binding var isAddingPayout: Bool

    @Environment(ShiftManager.self) private var shifts

    func body(content: Content) -> some View {
        let canEnd = ShiftManager.canEnd(shift)
        content.confirmationDialog(
            canEnd ? "End this shift?" : "Add a payout first",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            if canEnd {
                Button("End shift", role: .destructive) { shifts.endShift() }
            } else {
                Button("Add payout") { isAddingPayout = true }
                Button("Discard shift", role: .destructive) { shifts.deleteShift(shift) }
            }
        } message: {
            Text(canEnd
                ? "You can still add payouts to it afterwards."
                : "A shift needs at least one payout, with the app that paid you, before it can end. Discard it if you didn't work.")
        }
    }
}

struct ShiftMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.metric)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
